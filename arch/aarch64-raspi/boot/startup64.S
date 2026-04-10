/*
    Ported from Circle - A C++ bare metal environment for Raspberry Pi
    Copyright (C) 2014-2024 R. Stange <rsta2@o2online.de>
    Licensed under GPLv3

    Contains code from U-Boot (armv8_switch_to_el1_m macro):
    Copyright (C) 2009 Jean-Christophe PLAGNIOL-VILLARD <plagnioj@jcrosoft.com>
    Licensed under GPL-2.0+

    Adapted for AROS by The AROS Development Team, 2026

    Desc: AArch64 startup for Raspberry Pi 4 bootstrap
    Lang: english

    Entry state:
        Entered at 0x80000 from armstub8 in EL2 (or EL1 on some QEMU versions).
        x0 = DTB pointer (passed by firmware).
        MMU off, caches off.

    Exit state:
        Running in EL1, FP/SIMD enabled, stack set up, branches to boot().
*/

    .section .aros.startup, "ax"
    .globl _start

    /*
     * EL2 → EL1 transition macro.
     * Enables EL1 access to timers, FP/SIMD, sets AArch64 mode for EL1.
     */
    .macro armv8_switch_to_el1_m, xreg1, xreg2

    /* Enable EL1 access to generic timers */
    mrs     \xreg1, cnthctl_el2
    orr     \xreg1, \xreg1, #0x3
    msr     cnthctl_el2, \xreg1
    msr     cntvoff_el2, xzr

    /* Initialize MPID/MPIDR virtualization registers */
    mrs     \xreg1, midr_el1
    mrs     \xreg2, mpidr_el1
    msr     vpidr_el2, \xreg1
    msr     vmpidr_el2, \xreg2

    /* Disable coprocessor traps to EL2 */
    mov     \xreg1, #0x33ff
    msr     cptr_el2, \xreg1
    msr     hstr_el2, xzr

    /* Enable FP/SIMD at EL1 */
    mov     \xreg1, #(3 << 20)
    msr     cpacr_el1, \xreg1

    /* EL1 is AArch64 */
    mov     \xreg1, #(1 << 31)
    msr     hcr_el2, \xreg1

    /* SCTLR_EL1: RES1 bits set, everything else off (no MMU, no caches yet) */
    mov     \xreg1, #0x0800
    movk    \xreg1, #0x30d0, lsl #16
    msr     sctlr_el1, \xreg1

    /* Return to EL1h with DAIF masked */
    mov     \xreg1, #0x3c4
    msr     spsr_el2, \xreg1
    adr     \xreg1, 1f
    msr     elr_el2, \xreg1
    eret
1:
    .endm

_start:
    /* Save DTB pointer (firmware passes it in x0) */
    mov     x20, x0

    /* Check current exception level */
    mrs     x0, CurrentEL
    cmp     x0, #8                  /* CurrentEL == 8 means EL2 */
    b.eq    in_el2
    cmp     x0, #4                  /* CurrentEL == 4 means EL1 */
    b.eq    in_el1
    b       .                       /* EL3 or EL0 — should not happen, hang */

in_el2:
    armv8_switch_to_el1_m x0, x1

in_el1:
    /* Clear BSS */
    adrp    x0, __bss_start
    add     x0, x0, :lo12:__bss_start
    adrp    x1, __bss_end
    add     x1, x1, :lo12:__bss_end
bss_loop:
    cmp     x0, x1
    b.ge    bss_done
    str     xzr, [x0], #8
    b       bss_loop
bss_done:

    /* Set up stacks:
     * SP_EL1 = 0x00380000 (exception/IRQ stack, grows down)
     * SP_EL0 = 0x00400000 (main stack, grows down)
     *
     * DECISION: We switch to EL1h (SPSel=1) to set SP_EL1,
     * then back to EL1t (SPSel=0) for the main loop.
     * IRQs taken at EL1 use SP_EL1 (vector group 1).
     * Date: 2026-04-10
     */
    msr     spsel, #1           /* select SP_EL1 */
    ldr     x0, =0x00380000
    mov     sp, x0              /* SP_EL1 = exception stack */
    msr     spsel, #0           /* select SP_EL0 */
    ldr     x0, =0x00400000
    mov     sp, x0              /* SP_EL0 = main stack */

    /* Restore DTB pointer as first argument to boot() */
    mov     x0, x20

    /* Branch to C boot entry */
    bl      boot

    /* Should not return — hang if it does */
hang:
    wfe
    b       hang

    .section .aros.startup
    .string "AROS/AArch64 Bootstrap (" __DATE__ ")"
    .balign 8
