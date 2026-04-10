/*
    Ported from Circle - A C++ bare metal environment for Raspberry Pi
    Copyright (C) 2016-2025 R. Stange <rsta2@o2online.de>
    Licensed under GPLv3

    Adapted for AROS by The AROS Development Team, 2026

    Desc: AArch64 MMU setup for bootstrap.
          4KB granule, Level 1 + Level 2 block descriptors.
          Level 1: 1GB blocks (or table pointers)
          Level 2: 2MB blocks

    This is simpler and uses far less memory than 64KB granule
    with L3 page tables. Sufficient for bootstrap.
*/

#include <stdint.h>
#include <string.h>
#include "mmu.h"
#include "boot.h"

extern void *malloc(size_t size);

/* 4KB granule constants */
#define PAGE_SIZE           0x1000UL
#define L1_ENTRIES          512         /* covers 512GB */
#define L2_ENTRIES          512         /* each L2 entry = 2MB */
#define L2_BLOCK_SIZE       0x200000UL  /* 2MB */
#define L1_BLOCK_SIZE       (512UL * L2_BLOCK_SIZE) /* 1GB */

/* MAIR_EL1 attribute indices */
#define ATTRINDX_NORMAL     0
#define ATTRINDX_DEVICE     1
#define ATTRINDX_COHERENT   2

#define MAIR_VALUE  ( \
    (0xFFUL << (ATTRINDX_NORMAL  * 8)) | \
    (0x00UL << (ATTRINDX_DEVICE  * 8)) | \
    (0x44UL << (ATTRINDX_COHERENT * 8))  \
)

/* Descriptor bits */
#define DESC_VALID          (1UL << 0)
#define DESC_TABLE          (1UL << 1)
#define DESC_BLOCK          (0UL << 1)  /* L1/L2 block */
#define DESC_AF             (1UL << 10)
#define DESC_SH_INNER       (3UL << 8)
#define DESC_SH_OUTER       (2UL << 8)
#define DESC_AP_RW_EL1      (0UL << 6)
#define DESC_UXN            (1UL << 54)
#define DESC_PXN            (1UL << 53)

/* TCR_EL1 fields for 4KB granule */
#define TCR_T0SZ_36BIT      28          /* 64GB address space */
#define TCR_TG0_4KB         (0UL << 14)
#define TCR_SH0_INNER       (3UL << 12)
#define TCR_ORGN0_WB_ALLOC  (1UL << 10)
#define TCR_IRGN0_WB_ALLOC  (1UL << 8)
#define TCR_EPD1            (1UL << 23)
#define TCR_IPS_64GB        (1UL << 32)

/* SCTLR_EL1 bits */
#define SCTLR_M            (1UL << 0)
#define SCTLR_C            (1UL << 2)
#define SCTLR_I            (1UL << 12)

/*
 * Page tables. With 4KB granule:
 * L1: 512 entries × 8 bytes = 4KB (covers 512GB, only need first few)
 * L2: 512 entries × 8 bytes = 4KB per table (each covers 1GB)
 * We need at most 4 L2 tables (for 0-1GB, 1-2GB, 3-4GB peripherals)
 */
static uint64_t *l1_table;
static uint64_t *l2_tables[4];  /* up to 4GB */
static uint64_t mem_size;

static void *alloc_table(void)
{
    /* 4KB table needs 4KB alignment. Allocate 8KB, align. */
    void *raw = malloc(PAGE_SIZE * 2);
    if (!raw) return (void *)0;
    return (void *)(((uintptr_t)raw + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1));
}

static uint64_t make_l2_block(uint64_t phys, int attrindx, uint64_t sh)
{
    uint64_t desc = DESC_VALID | DESC_BLOCK;
    desc |= (phys & 0x0000FFFFFFE00000UL);  /* OutputAddress [47:21] */
    desc |= ((uint64_t)attrindx << 2);
    desc |= DESC_AF | DESC_AP_RW_EL1 | DESC_UXN;
    desc |= sh;
    return desc;
}

void mmu_init(void)
{
    mem_size = 0;
    l1_table = (uint64_t *)0;
    memset(l2_tables, 0, sizeof(l2_tables));
}

void mmu_map(uint64_t phys, uint64_t size, int is_device)
{
    if (!is_device && phys + size > mem_size)
        mem_size = phys + size;
}

void mmu_unmap(uint64_t phys, uint64_t size)
{
    (void)phys; (void)size;
}

void mmu_load(void)
{
    unsigned gb, mb;

    /* Allocate L1 table */
    l1_table = alloc_table();
    if (!l1_table)
    {
        kprintf("[BOOT] MMU: Failed to allocate L1 table!\n");
        return;
    }
    memset(l1_table, 0, PAGE_SIZE);

    /* Create L2 tables for each 1GB region in use */
    for (gb = 0; gb < 4; gb++)
    {
        uint64_t gb_base = (uint64_t)gb * L1_BLOCK_SIZE;
        uint64_t gb_end = gb_base + L1_BLOCK_SIZE;

        /* Need this GB if it contains RAM or peripherals (0xFC000000+) */
        int need = 0;
        if (gb_base < mem_size) need = 1;
        if (gb_end > 0xFC000000UL) need = 1;
        if (!need) continue;

        uint64_t *l2 = alloc_table();
        if (!l2) continue;
        memset(l2, 0, PAGE_SIZE);
        l2_tables[gb] = l2;

        /* Fill L2 with 2MB block descriptors */
        for (mb = 0; mb < L2_ENTRIES; mb++)
        {
            uint64_t addr = gb_base + (uint64_t)mb * L2_BLOCK_SIZE;
            int attrindx;
            uint64_t sh;

            if (addr < mem_size)
            {
                attrindx = ATTRINDX_NORMAL;
                sh = DESC_SH_INNER;
            }
            else
            {
                attrindx = ATTRINDX_DEVICE;
                sh = DESC_SH_OUTER;
            }

            l2[mb] = make_l2_block(addr, attrindx, sh);
        }

        /* L1 table descriptor pointing to L2 */
        l1_table[gb] = DESC_VALID | DESC_TABLE |
                        ((uint64_t)l2 & 0x0000FFFFFFFFF000UL);
    }

    /* Flush tables */
    __asm__ volatile("dsb sy" ::: "memory");

    kprintf("[BOOT] MMU: L1 at %p, mem_size=%luMB, 4KB granule\n",
            l1_table, (unsigned long)(mem_size >> 20));

    /* MAIR_EL1 */
    __asm__ volatile("msr mair_el1, %0" : : "r"(MAIR_VALUE));

    /* TCR_EL1: 4KB granule, 64GB IPA, 36-bit VA (64GB) */
    uint64_t tcr = TCR_T0SZ_36BIT | TCR_TG0_4KB | TCR_SH0_INNER |
                   TCR_ORGN0_WB_ALLOC | TCR_IRGN0_WB_ALLOC |
                   TCR_EPD1 | TCR_IPS_64GB;
    __asm__ volatile("msr tcr_el1, %0" : : "r"(tcr));

    /* TTBR0_EL1 */
    __asm__ volatile("msr ttbr0_el1, %0" : : "r"((uint64_t)l1_table));

    /* Invalidate all TLBs */
    __asm__ volatile("tlbi vmalle1; dsb sy; isb" ::: "memory");

    /* Enable MMU + caches */
    uint64_t sctlr;
    __asm__ volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    sctlr |= SCTLR_M | SCTLR_C | SCTLR_I;
    __asm__ volatile("msr sctlr_el1, %0" : : "r"(sctlr));
    __asm__ volatile("isb" ::: "memory");

    kprintf("[BOOT] MMU enabled\n");
}
