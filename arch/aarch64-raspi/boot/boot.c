/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 bootstrap entry point for Raspberry Pi 4.
          Initializes UART, prints hardware info, halts.
          Later tasks will add: device tree parsing, memory detection,
          ELF loading, and jump to kernel.
    Lang: english
*/

#include <stdint.h>

#include "serialdebug.h"

/* Read AArch64 system registers */
static inline uint64_t read_midr_el1(void)
{
    uint64_t val;
    __asm__ volatile("mrs %0, midr_el1" : "=r"(val));
    return val;
}

static inline uint64_t read_mpidr_el1(void)
{
    uint64_t val;
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(val));
    return val;
}

static inline uint64_t read_currentel(void)
{
    uint64_t val;
    __asm__ volatile("mrs %0, CurrentEL" : "=r"(val));
    return val;
}

static inline uint64_t read_cntfrq_el0(void)
{
    uint64_t val;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(val));
    return val;
}

void boot(void *dtb_ptr)
{
    uint64_t midr, mpidr, el, cntfrq;

    serInit();

    kprintf("\n\n");
    kprintf("AROS - Amiga Research Operating System\n");
    kprintf("AArch64 Bootstrap (" __DATE__ ")\n");
    kprintf("========================================\n\n");

    /* Exception level */
    el = read_currentel() >> 2;
    kprintf("[BOOT] Exception level: EL%d\n", (int)el);

    /* CPU identification */
    midr = read_midr_el1();
    kprintf("[BOOT] MIDR_EL1: 0x%08lx\n", midr);
    kprintf("[BOOT]   Implementer: 0x%02x", (unsigned int)((midr >> 24) & 0xFF));
    if (((midr >> 24) & 0xFF) == 0x41)
        kprintf(" (ARM)\n");
    else
        kprintf("\n");
    kprintf("[BOOT]   Part number: 0x%03x", (unsigned int)((midr >> 4) & 0xFFF));
    if (((midr >> 4) & 0xFFF) == 0xD08)
        kprintf(" (Cortex-A72)\n");
    else if (((midr >> 4) & 0xFFF) == 0xD0B)
        kprintf(" (Cortex-A76)\n");
    else
        kprintf("\n");

    /* Core ID */
    mpidr = read_mpidr_el1();
    kprintf("[BOOT] MPIDR_EL1: 0x%016lx (core %d)\n",
            mpidr, (int)(mpidr & 0x3));

    /* Timer frequency */
    cntfrq = read_cntfrq_el0();
    kprintf("[BOOT] Timer frequency: %lu Hz\n", cntfrq);

    /* DTB pointer */
    kprintf("[BOOT] DTB pointer: %p\n", dtb_ptr);

    /* Memory info */
    kprintf("[BOOT] UART0 (PL011): 0x%08x\n", 0xFE201000);
    kprintf("[BOOT] Kernel loaded at: 0x00080000\n");
    kprintf("[BOOT] Stack at: 0x00400000\n");

    kprintf("[BOOT] Handing off to kernel...\n\n");

    /* Call kernel entry point (monolithic image — no ELF load needed) */
    extern void kernel_cstart(void);
    kernel_cstart();

    /* Should not return */
    for (;;)
        __asm__ volatile("wfe");
}
