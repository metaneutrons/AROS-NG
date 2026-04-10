/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 bootstrap for Raspberry Pi 4.
          Parses device tree, detects memory, sets up MMU,
          loads core.elf, builds kernel tag list, jumps to kernel.
          Based on arch/arm-raspi/boot/boot.c.
*/

#include <inttypes.h>
#include <aros/macros.h>
#include <aros/kernel.h>
#include <string.h>

#include "boot.h"
#include "serialdebug.h"
#include "mmu.h"
#include "elf.h"
#include "devicetree.h"

#define DBOOT(x) x

static const char bootstrapName[] = "Bootstrap/AArch64 v8-a";

static struct TagItem *boottag;
static unsigned long *mem_upper;
static void *pkg_image;
static uint64_t pkg_size;

static void query_memory(void)
{
    of_node_t *mem = dt_find_node("/memory@0");

    /* Try /memory if /memory@0 doesn't exist (ARM32 DTBs) */
    if (!mem || !dt_find_property(mem, "reg"))
        mem = dt_find_node("/memory");

    kprintf("[BOOT] Query system memory\n");
    if (mem)
    {
        of_property_t *p = dt_find_property(mem, "reg");
        if (p && p->op_length)
        {
            uint32_t *addr = p->op_value;
            uint64_t lower, upper;

            /*
             * Pi 4 DT root has #address-cells=2, #size-cells=1
             * /memory reg = <addr_hi addr_lo size>
             * But firmware may also use #size-cells=2 for >4GB
             */
            if (p->op_length >= 12)
            {
                uint32_t addr_hi = AROS_BE2LONG(addr[0]);
                uint32_t addr_lo = AROS_BE2LONG(addr[1]);
                uint32_t size    = AROS_BE2LONG(addr[2]);
                (void)addr_hi;
                lower = addr_lo;
                upper = lower + size;
            }
            else
            {
                lower = 0;
                upper = 0;
            }

            if (upper <= lower)
            {
                /* Firmware hasn't patched /memory — use default 2GB */
                kprintf("[BOOT] /memory reg empty, assuming 2GB RAM\n");
                lower = 0;
                upper = 0x80000000UL;
            }

            kprintf("[BOOT] System memory: %08lx-%08lx (%luMB)\n",
                    (unsigned long)lower, (unsigned long)(upper - 1),
                    (unsigned long)((upper - lower) >> 20));

            boottag->ti_Tag = KRN_MEMLower;
            boottag->ti_Data = lower ? lower : 0x10000;
            boottag++;

            boottag->ti_Tag = KRN_MEMUpper;
            boottag->ti_Data = upper;
            mem_upper = (unsigned long *)&boottag->ti_Data;
            boottag++;

            mmu_map(lower, upper - lower, 0);
        }
    }
    else
    {
        kprintf("[BOOT] No /memory node, assuming 2GB RAM\n");
        boottag->ti_Tag = KRN_MEMLower;
        boottag->ti_Data = 0x10000;
        boottag++;
        boottag->ti_Tag = KRN_MEMUpper;
        boottag->ti_Data = 0x80000000UL;
        mem_upper = (unsigned long *)&boottag->ti_Data;
        boottag++;
        mmu_map(0, 0x80000000UL, 0);
    }
}

void boot(void *dtb_ptr)
{
    void (*entry)(struct TagItem *) = (void *)0;
    uint64_t total_size_ro = 0, total_size_rw = 0;
    void *fdt = (void *)0;
    int dt_mem_usage = 0;

    serInit();

    kprintf("\n\n[BOOT] AROS %s\n", bootstrapName);

    /* Initialize memory allocator */
    mem_init();

    /* Parse device tree */
    dt_mem_usage = mem_avail();
    if (dtb_ptr && *(uint32_t *)dtb_ptr == AROS_LONG2BE(0xd00dfeed))
    {
        kprintf("[BOOT] DTB at %p, size %lu\n", dtb_ptr,
                (unsigned long)AROS_BE2LONG(((uint32_t *)dtb_ptr)[1]));
        dt_parse(dtb_ptr);
    }
    else
    {
        kprintf("[BOOT] No valid DTB (ptr=%p)\n", dtb_ptr);
        dtb_ptr = (void *)0;
    }
    dt_mem_usage -= mem_avail();

    /* Initialize MMU (tables not loaded yet) */
    mmu_init();

    /* Detect SoC peripherals from device tree */
    of_node_t *soc = dt_find_node("/soc");
    if (soc)
    {
        of_property_t *p = dt_find_property(soc, "ranges");
        if (p)
        {
            uint32_t *ranges = p->op_value;
            int32_t len = p->op_length;

            /*
             * /soc has #address-cells=1, #size-cells=1
             * but parent (root) has #address-cells=2
             * So each range entry is 4 cells:
             *   child_addr(1) parent_hi(1) parent_lo(1) size(1)
             */
            while (len >= 16)
            {
                uint32_t child_addr = AROS_BE2LONG(*ranges++);
                uint32_t parent_hi  = AROS_BE2LONG(*ranges++);
                uint32_t parent_lo  = AROS_BE2LONG(*ranges++);
                uint32_t size       = AROS_BE2LONG(*ranges++);
                (void)child_addr;
                (void)parent_hi;

                if (size > 0)
                {
                    kprintf("[BOOT] SoC peripheral: %08x-%08x\n",
                            parent_lo, parent_lo + size - 1);
                    mmu_map(parent_lo, size, 1);
                }
                len -= 16;
            }
        }
    }

    /* Map GIC-400 area (not in /soc ranges on Pi 4) */
    mmu_map(0xFF800000UL, 0x00800000UL, 1);

    kprintf("[BOOT] Booted on %s\n",
            (char *)dt_find_property(dt_find_node("/"), "model")->op_value);

    /* Set up boot tag list */
    boottag = (struct TagItem *)((uintptr_t)&__bootstrap_end + 0x1000);
    boottag = (struct TagItem *)(((uintptr_t)boottag + 15) & ~15);

    boottag->ti_Tag = KRN_Platform;
    boottag->ti_Data = 0x2711;
    boottag++;

    boottag->ti_Tag = KRN_BootLoader;
    boottag->ti_Data = (IPTR)bootstrapName;
    boottag++;

    kprintf("[BOOT] DT memory usage: %d bytes\n", dt_mem_usage);

    query_memory();

    kprintf("[BOOT] Bootstrap @ %p-%p\n", &__bootstrap_start, &__bootstrap_end);

    boottag->ti_Tag = KRN_ProtAreaStart;
    boottag->ti_Data = (IPTR)&__bootstrap_start;
    boottag++;

    boottag->ti_Tag = KRN_ProtAreaEnd;
    boottag->ti_Data = (IPTR)&__bootstrap_end;
    boottag++;

    /* Find initrd (core.elf or package) */
    of_node_t *chosen = dt_find_node("/chosen");
    if (chosen)
    {
        of_property_t *p = dt_find_property(chosen, "linux,initrd-start");
        if (p)
            pkg_image = (void *)(uintptr_t)AROS_BE2LONG(*(uint32_t *)p->op_value);
        else
            pkg_image = (void *)0;

        p = dt_find_property(chosen, "linux,initrd-end");
        if (p)
            pkg_size = AROS_BE2LONG(*(uint32_t *)p->op_value) - (uintptr_t)pkg_image;
        else
            pkg_size = 0;
    }

    /* If no initrd, use embedded core.elf */
    if (!pkg_image)
    {
        pkg_image = &_binary_core_bin_start;
        pkg_size = (uintptr_t)&_binary_core_bin_end - (uintptr_t)&_binary_core_bin_start;
    }

    kprintf("[BOOT] Kernel image: %p-%p (%lu bytes)\n",
            pkg_image, (void *)((uintptr_t)pkg_image + pkg_size - 1), (unsigned long)pkg_size);

    if (mem_upper && pkg_size > 256)
    {
        *mem_upper = *mem_upper & ~4095;

        uintptr_t kernel_phys = *mem_upper;
        uint64_t size_ro, size_rw;

        /* Calculate kernel size */
        getElfSize(pkg_image, &size_rw, &size_ro);
        total_size_ro = (size_ro + 4095) & ~4095;
        total_size_rw = (size_rw + 4095) & ~4095;

        /* Reserve space for flattened device tree */
        total_size_ro += (dt_total_size() + 31) & ~31;
        /* Reserve space for unpacked device tree */
        total_size_ro += (dt_mem_usage + 31) & ~31;

        /* Align to 2MB boundary */
        total_size_ro = (total_size_ro + 0x1FFFFF) & ~0x1FFFFF;
        total_size_rw = (total_size_rw + 0x1FFFFF) & ~0x1FFFFF;

        kernel_phys = *mem_upper - total_size_ro - total_size_rw;

        /* Identity-mapped: virtual = physical */
        uintptr_t kernel_virt = kernel_phys;

        bzero((void *)kernel_phys, total_size_ro + total_size_rw);

        kprintf("[BOOT] Kernel physical: %p\n", (void *)kernel_phys);
        kprintf("[BOOT] Kernel RO: %luKB, RW: %luKB\n",
                (unsigned long)(total_size_ro >> 10),
                (unsigned long)(total_size_rw >> 10));

        /* Copy flattened device tree */
        if (dt_total_size() > 0)
        {
            long dt_size = (dt_total_size() + 31) & ~31;
            memcpy((void *)(kernel_phys + total_size_ro - dt_size),
                   dtb_ptr, dt_size);
            fdt = (void *)(kernel_virt + total_size_ro - dt_size);

            boottag->ti_Tag = KRN_FlattenedDeviceTree;
            boottag->ti_Data = (IPTR)fdt;
            boottag++;
        }

        *mem_upper = kernel_phys;

        

        initAllocator(kernel_phys, kernel_phys + total_size_ro, 0);

        boottag->ti_Tag = KRN_KernelLowest;
        boottag->ti_Data = kernel_virt;
        boottag++;

        boottag->ti_Tag = KRN_KernelHighest;
        boottag->ti_Data = kernel_virt + total_size_ro + total_size_rw;
        boottag++;

        boottag->ti_Tag = KRN_KernelPhysLowest;
        boottag->ti_Data = kernel_phys;
        boottag++;

        /* Load kernel ELF -- entry point returned by loadElf */
        kprintf("[BOOT] Loading kernel ELF...\n");
        {
            uintptr_t elf_entry = loadElf(pkg_image);
            if (!elf_entry)
            {
                kprintf("[BOOT] WARNING: Failed to load kernel ELF\n");
                entry = (void *)0;
            }
            else
            {
                entry = (void (*)(struct TagItem *))elf_entry;
            }
        }

        aarch64_flush_cache(kernel_phys, total_size_ro + total_size_rw);
        aarch64_icache_invalidate(kernel_phys, total_size_ro + total_size_rw);

        boottag->ti_Tag = KRN_KernelBss;
        boottag->ti_Data = (IPTR)tracker;
        boottag++;
    }

    /* Enable MMU */
    mmu_load();

    /* Re-parse device tree in kernel area */
    if (dt_total_size() > 0 && fdt)
    {
        long dt_size = (dt_total_size() + 31) & ~31;
        long dt_unpack = (dt_mem_usage + 31) & ~31;
        void *dt_location = (void *)((uintptr_t)fdt - dt_unpack);

        kprintf("[BOOT] Re-parsing DT at %p\n", dt_location);
        explicit_mem_init(dt_location, dt_unpack);
        dt_parse(fdt);

        boottag->ti_Tag = KRN_OpenFirmwareTree;
        boottag->ti_Data = (IPTR)dt_location;
        boottag++;

        of_node_t *ch = dt_find_node("/chosen");
        if (ch)
        {
            of_property_t *p = dt_find_property(ch, "bootargs");
            if (p)
            {
                boottag->ti_Tag = KRN_CmdLine;
                boottag->ti_Data = (IPTR)p->op_value;
                boottag++;
            }
        }
    }

    boottag->ti_Tag = TAG_DONE;
    boottag->ti_Data = 0;

    kprintf("[BOOT] Kernel tags: %d entries\n",
            (int)((uintptr_t)boottag - (uintptr_t)entry) / (int)sizeof(struct TagItem));
    kprintf("[BOOT] Bootstrap used %d bytes\n", (int)mem_used());
    kprintf("[BOOT] Jumping to kernel @ %p\n\n", entry);

    if (!entry)
    {
        kprintf("[BOOT] No kernel to jump to. System halted.\n");
        for (;;) __asm__ volatile("wfe");
    }

    entry((struct TagItem *)((uintptr_t)&__bootstrap_end + 0x1000));

    kprintf("[BOOT] Kernel returned! Halting.\n");
    for (;;) __asm__ volatile("wfe");
}
