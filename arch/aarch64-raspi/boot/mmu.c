/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: AArch64 MMU setup for bootstrap.
          4KB granule, Level 1 + Level 2 block descriptors (2MB blocks).
          This is simpler and uses far less memory than 64KB granule
          with L3 page tables. Sufficient for bootstrap.

    Translation table format and system register fields derived from:
    - ARM Architecture Reference Manual (DDI 0487), Chapter D5
      - D5.3: VMSAv8-64 translation table format descriptors
      - D5.2.6: Overview of VMSAv8-64 address translation
    - System registers:
      - D13.2.97  MAIR_EL1 (Memory Attribute Indirection Register)
      - D13.2.120 TCR_EL1  (Translation Control Register)
      - D13.2.113 SCTLR_EL1 (System Control Register)
      - D13.2.131 TTBR0_EL1 (Translation Table Base Register 0)
*/

#include <stdint.h>
#include <string.h>
#include "mmu.h"
#include "boot.h"

extern void *malloc(size_t size);

/* 4KB granule geometry — ARM ARM D5.2.6, Table D5-11 */
#define PAGE_SIZE           0x1000UL
#define L2_BLOCK_SIZE       0x200000UL      /* 2MB per L2 entry */
#define L1_BLOCK_SIZE       (512UL * L2_BLOCK_SIZE)  /* 1GB per L1 entry */
#define ENTRIES_PER_TABLE   512

/*
 * MAIR_EL1 attribute indices — ARM ARM D13.2.97
 *   Index 0: Normal Write-Back (outer+inner) = 0xFF
 *   Index 1: Device-nGnRnE = 0x00
 *   Index 2: Normal Non-Cacheable = 0x44
 */
#define ATTR_NORMAL         0
#define ATTR_DEVICE         1
#define ATTR_COHERENT       2

#define MAIR_VALUE  ( \
    (0xFFUL << (ATTR_NORMAL  * 8)) | \
    (0x00UL << (ATTR_DEVICE  * 8)) | \
    (0x44UL << (ATTR_COHERENT * 8))  \
)

/*
 * Translation table descriptor bits — ARM ARM D5.3.3
 */
#define DESC_VALID          (1UL << 0)
#define DESC_TABLE          (1UL << 1)  /* L1: next-level table pointer */
#define DESC_BLOCK          (0UL << 1)  /* L1/L2: block descriptor */
#define DESC_AF             (1UL << 10) /* Access Flag */
#define DESC_SH_INNER       (3UL << 8)  /* Inner Shareable */
#define DESC_SH_OUTER       (2UL << 8)  /* Outer Shareable */
#define DESC_AP_RW_EL1      (0UL << 6)  /* AP[2:1] = 00: EL1 R/W */
#define DESC_UXN            (1UL << 54) /* Unprivileged Execute-Never */
#define DESC_PXN            (1UL << 53) /* Privileged Execute-Never */

/*
 * TCR_EL1 fields — ARM ARM D13.2.120
 */
#define TCR_T0SZ_36BIT      28          /* 64 - 36 = 28 → 64GB VA space */
#define TCR_TG0_4KB         (0UL << 14)
#define TCR_SH0_INNER       (3UL << 12)
#define TCR_ORGN0_WB_ALLOC  (1UL << 10)
#define TCR_IRGN0_WB_ALLOC  (1UL << 8)
#define TCR_EPD1            (1UL << 23) /* Disable TTBR1 walks */
#define TCR_IPS_64GB        (1UL << 32) /* 36-bit PA = 64GB */

/* SCTLR_EL1 bits — ARM ARM D13.2.113 */
#define SCTLR_M             (1UL << 0)  /* MMU enable */
#define SCTLR_C             (1UL << 2)  /* Data cache enable */
#define SCTLR_I             (1UL << 12) /* Instruction cache enable */

static uint64_t *l1_table;
static uint64_t *l2_tables[4];
static uint64_t mem_top;

static void *alloc_page_table(void)
{
    void *raw = malloc(PAGE_SIZE * 2);
    if (!raw) return (void *)0;
    return (void *)(((uintptr_t)raw + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1));
}

static uint64_t block_desc(uint64_t phys, int attr, uint64_t sh)
{
    return DESC_VALID | DESC_BLOCK |
           (phys & 0x0000FFFFFFE00000UL) |
           ((uint64_t)attr << 2) |
           DESC_AF | DESC_AP_RW_EL1 | DESC_UXN | sh;
}

void mmu_init(void)
{
    mem_top = 0;
    l1_table = (uint64_t *)0;
    memset(l2_tables, 0, sizeof(l2_tables));
}

void mmu_map(uint64_t phys, uint64_t size, int is_device)
{
    if (!is_device && phys + size > mem_top)
        mem_top = phys + size;
}

void mmu_unmap(uint64_t phys, uint64_t size)
{
    (void)phys; (void)size;
}

/*
 * mmu_load — build page tables and enable the MMU.
 *
 * Creates a two-level identity map:
 *   L1 (512 entries, each 1GB) → L2 tables (512 entries, each 2MB block)
 *   RAM regions: Normal Write-Back, Inner Shareable
 *   Device regions (≥ 0xFC000000): Device-nGnRnE, Outer Shareable
 */
void mmu_load(void)
{
    unsigned int gb, mb;

    l1_table = alloc_page_table();
    if (!l1_table)
    {
        kprintf("[BOOT] MMU: Failed to allocate L1 table!\n");
        return;
    }
    memset(l1_table, 0, PAGE_SIZE);

    for (gb = 0; gb < 4; gb++)
    {
        uint64_t base = (uint64_t)gb * L1_BLOCK_SIZE;
        uint64_t end  = base + L1_BLOCK_SIZE;

        if (base >= mem_top && end <= 0xFC000000UL)
            continue;

        uint64_t *l2 = alloc_page_table();
        if (!l2) continue;
        memset(l2, 0, PAGE_SIZE);
        l2_tables[gb] = l2;

        for (mb = 0; mb < ENTRIES_PER_TABLE; mb++)
        {
            uint64_t addr = base + (uint64_t)mb * L2_BLOCK_SIZE;
            if (addr < mem_top)
                l2[mb] = block_desc(addr, ATTR_NORMAL, DESC_SH_INNER);
            else
                l2[mb] = block_desc(addr, ATTR_DEVICE, DESC_SH_OUTER);
        }

        l1_table[gb] = DESC_VALID | DESC_TABLE |
                        ((uint64_t)l2 & 0x0000FFFFFFFFF000UL);
    }

    __asm__ volatile("dsb sy" ::: "memory");

    kprintf("[BOOT] MMU: L1 at %p, mem=%luMB, 4KB granule\n",
            l1_table, (unsigned long)(mem_top >> 20));

    /* Program system registers — ARM ARM D13.2 */
    __asm__ volatile("msr mair_el1, %0" : : "r"(MAIR_VALUE));

    uint64_t tcr = TCR_T0SZ_36BIT | TCR_TG0_4KB | TCR_SH0_INNER |
                   TCR_ORGN0_WB_ALLOC | TCR_IRGN0_WB_ALLOC |
                   TCR_EPD1 | TCR_IPS_64GB;
    __asm__ volatile("msr tcr_el1, %0" : : "r"(tcr));
    __asm__ volatile("msr ttbr0_el1, %0" : : "r"((uint64_t)l1_table));
    __asm__ volatile("tlbi vmalle1; dsb sy; isb" ::: "memory");

    uint64_t sctlr;
    __asm__ volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    sctlr |= SCTLR_M | SCTLR_C | SCTLR_I;
    __asm__ volatile("msr sctlr_el1, %0" : : "r"(sctlr));
    __asm__ volatile("isb" ::: "memory");

    kprintf("[BOOT] MMU enabled\n");
}
