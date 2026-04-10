/*
    Ported from Circle - A C++ bare metal environment for Raspberry Pi
    Copyright (C) 2016-2025 R. Stange <rsta2@o2online.de>
    Licensed under GPLv3

    Adapted for AROS by The AROS Development Team, 2026

    Desc: AArch64 MMU setup for bootstrap.
          64KB granule, identity-mapped, Level 2 + Level 3 tables.
          Level 2 is the first lookup level (each entry covers 512MB).
          Level 3 is the final level (each entry covers 64KB page).

    Pi 4 memory map:
        0x00000000 - RAM_END     Normal memory (cacheable, inner-shareable)
        0xFC000000 - 0xFF7FFFFF  BCM2711 peripherals (device, non-cacheable)
        0xFF800000 - 0xFFFFFFFF  GIC-400 + ARM local peripherals (device)
*/

#include <stdint.h>
#include <string.h>
#include "mmu.h"
#include "boot.h"

extern void *malloc(size_t size);

/* 64KB granule constants */
#define PAGE_SIZE           0x10000UL       /* 64KB */
#define TABLE_ENTRIES       8192            /* entries per table */
#define L3_PAGE_SIZE        PAGE_SIZE       /* 64KB */
#define L2_BLOCK_SIZE       (TABLE_ENTRIES * L3_PAGE_SIZE)  /* 512MB */

/* Pi 4: 128 L2 entries = 64GB address space */
#define L2_TABLE_ENTRIES    128

/* MAIR_EL1 attribute indices */
#define ATTRINDX_NORMAL     0   /* Write-back cacheable */
#define ATTRINDX_DEVICE     1   /* Device-nGnRnE */
#define ATTRINDX_COHERENT   2   /* Non-cacheable */

/* MAIR_EL1 value: attr0=Normal WB, attr1=Device, attr2=Non-cacheable */
#define MAIR_VALUE  ( \
    (0xFFUL << (ATTRINDX_NORMAL  * 8)) | \
    (0x00UL << (ATTRINDX_DEVICE  * 8)) | \
    (0x44UL << (ATTRINDX_COHERENT * 8))  \
)

/* Descriptor bits */
#define DESC_VALID          (1UL << 0)
#define DESC_TABLE          (1UL << 1)  /* L2: table descriptor */
#define DESC_PAGE           (1UL << 1)  /* L3: page descriptor */
#define DESC_AF             (1UL << 10) /* Access flag */
#define DESC_SH_INNER       (3UL << 8)  /* Inner shareable */
#define DESC_SH_OUTER       (2UL << 8)  /* Outer shareable */
#define DESC_AP_RW_EL1      (0UL << 6)  /* R/W at EL1 */
#define DESC_UXN            (1UL << 54) /* Unprivileged execute never */
#define DESC_PXN            (1UL << 53) /* Privileged execute never */

/* TCR_EL1 fields */
#define TCR_T0SZ_64GB       28
#define TCR_TG0_64KB        (1UL << 14)
#define TCR_SH0_INNER       (3UL << 12)
#define TCR_ORGN0_WB_ALLOC  (1UL << 10)
#define TCR_IRGN0_WB_ALLOC  (1UL << 8)
#define TCR_EPD1            (1UL << 23) /* Disable TTBR1 walks */
#define TCR_IPS_64GB        (1UL << 32)

/* SCTLR_EL1 bits */
#define SCTLR_M            (1UL << 0)  /* MMU enable */
#define SCTLR_C            (1UL << 2)  /* Data cache enable */
#define SCTLR_I            (1UL << 12) /* Instruction cache enable */

/*
 * Page table storage.
 * L2 table: 8192 entries × 8 bytes = 64KB (1 page).
 * L3 tables: one per active L2 entry, each 64KB.
 * Allocated from bootstrap heap via malloc().
 */
static uint64_t *l2_table;
static uint64_t *l3_tables[L2_TABLE_ENTRIES];
static uint64_t mem_size;

static uint64_t make_l3_page(uint64_t phys, int attrindx, int shareable)
{
    uint64_t desc = DESC_VALID | DESC_PAGE;
    desc |= (phys & 0x0000FFFFFFFF0000UL);     /* OutputAddress [47:16] */
    desc |= ((uint64_t)attrindx << 2);
    desc |= DESC_AF;
    desc |= DESC_AP_RW_EL1;
    desc |= DESC_UXN;
    desc |= shareable;
    return desc;
}

static uint64_t *create_l3_table(uint64_t base_addr)
{
    uint64_t *table = malloc(PAGE_SIZE);
    if (!table) return (uint64_t *)0;
    memset(table, 0, PAGE_SIZE);

    for (unsigned page = 0; page < TABLE_ENTRIES; page++)
    {
        uint64_t addr = base_addr + (uint64_t)page * L3_PAGE_SIZE;
        int attrindx;
        uint64_t sh;

        if (addr < mem_size)
        {
            /* Normal RAM — cacheable, inner-shareable */
            attrindx = ATTRINDX_NORMAL;
            sh = DESC_SH_INNER;
        }
        else
        {
            /* Device memory — non-cacheable, outer-shareable */
            attrindx = ATTRINDX_DEVICE;
            sh = DESC_SH_OUTER;
        }

        table[page] = make_l3_page(addr, attrindx, sh);
    }

    return table;
}

void mmu_init(void)
{
    mem_size = 0;
    l2_table = (uint64_t *)0;
    memset(l3_tables, 0, sizeof(l3_tables));
}

/*
 * mmu_map — mark a physical range as normal memory or device memory.
 * Must be called before mmu_load(). Identity-mapped only.
 */
void mmu_map(uint64_t phys, uint64_t size, int is_device)
{
    if (!is_device)
    {
        /* Track highest RAM address for the normal/device boundary */
        if (phys + size > mem_size)
            mem_size = phys + size;
    }
}

void mmu_unmap(uint64_t phys, uint64_t size)
{
    /* For bootstrap we don't need dynamic unmapping */
    (void)phys;
    (void)size;
}

/*
 * mmu_load — build page tables and enable the MMU.
 * Call after all mmu_map() calls are done.
 */
void mmu_load(void)
{
    unsigned n;

    /* Allocate L2 table (must be 64KB aligned — malloc returns 16-byte aligned,
       but palloc from heap is page-aligned in practice for 64KB allocs) */
    l2_table = malloc(PAGE_SIZE);
    if (!l2_table)
    {
        kprintf("[BOOT] MMU: Failed to allocate L2 table!\n");
        return;
    }
    memset(l2_table, 0, PAGE_SIZE);

    /* Create L3 tables for each 512MB region that's in use */
    for (n = 0; n < L2_TABLE_ENTRIES; n++)
    {
        uint64_t base = (uint64_t)n * L2_BLOCK_SIZE;

        /* Skip unmapped regions above 4GB (Pi 4 has no memory there) */
        if (base >= 4UL * 1024 * 1024 * 1024)
            continue;

        /* Skip gap between RAM end and peripheral base if large */
        if (base >= mem_size && base < 0xFC000000UL)
            continue;

        uint64_t *l3 = create_l3_table(base);
        if (!l3) continue;
        l3_tables[n] = l3;

        /* L2 table descriptor: points to L3 table */
        uint64_t desc = DESC_VALID | DESC_TABLE;
        desc |= ((uint64_t)l3 & 0x0000FFFFFFFF0000UL);  /* TableAddress [47:16] */
        l2_table[n] = desc;
    }

    /* Flush all table memory to PoC */
    aarch64_flush_cache((uintptr_t)l2_table, PAGE_SIZE);
    for (n = 0; n < L2_TABLE_ENTRIES; n++)
    {
        if (l3_tables[n])
            aarch64_flush_cache((uintptr_t)l3_tables[n], PAGE_SIZE);
    }

    kprintf("[BOOT] MMU: L2 table at %p, mem_size=%luMB\n",
            l2_table, (unsigned long)(mem_size >> 20));

    /* Configure MAIR_EL1 */
    __asm__ volatile("msr mair_el1, %0" : : "r"(MAIR_VALUE));

    /* Configure TCR_EL1 */
    uint64_t tcr = TCR_T0SZ_64GB | TCR_TG0_64KB | TCR_SH0_INNER |
                   TCR_ORGN0_WB_ALLOC | TCR_IRGN0_WB_ALLOC |
                   TCR_EPD1 | TCR_IPS_64GB;
    __asm__ volatile("msr tcr_el1, %0" : : "r"(tcr));

    /* Set TTBR0_EL1 to L2 table base */
    __asm__ volatile("msr ttbr0_el1, %0" : : "r"((uint64_t)l2_table));

    /* Ensure all writes are visible */
    __asm__ volatile("dsb sy; isb" ::: "memory");

    /* Enable MMU + caches in SCTLR_EL1 */
    uint64_t sctlr;
    __asm__ volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    sctlr |= SCTLR_M | SCTLR_C | SCTLR_I;
    __asm__ volatile("msr sctlr_el1, %0" : : "r"(sctlr));
    __asm__ volatile("isb" ::: "memory");

    kprintf("[BOOT] MMU enabled\n");
}
