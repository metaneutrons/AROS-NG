/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: AArch64 startup for Raspberry Pi 4 bootstrap
    Lang: english

    Entry state:
        Entered at 0x80000 from armstub8 in EL2 (or EL1 on some QEMU versions).
        x0 = DTB pointer (passed by firmware).
        MMU off, caches off.

    Exit state:
        Running in EL1, FP/SIMD enabled, stack set up, branches to boot().

    EL2 → EL1 transition derived from:
    - ARM Architecture Reference Manual (DDI 0487):
      - D1.9:    Changing Exception level
      - D13.2.27 CNTHCTL_EL2 (timer access control)
      - D13.2.30 CPTR_EL2 (coprocessor trap control)
      - D13.2.36 CPACR_EL1 (FP/SIMD enable)
      - D13.2.47 HCR_EL2 (execution state control)
      - D13.2.113 SCTLR_EL1 (RES1 bits)
      - D13.2.109 SPSR_EL2 (return state)

    Exception vector table layout from ARM ARM D1.10.2.
*/

    .section .aros.startup, "ax"
    .globl _start

    /*
     * EL2 → EL1 transition macro.
     *
     * Configures EL2 to allow EL1 access to timers and FP/SIMD,
     * sets EL1 execution state to AArch64, then returns to EL1
     * via eret.
     *
     * Each register write is the only correct value per the ARM ARM:
     *   CNTHCTL_EL2[1:0] = 0b11  → EL1 can access CNTPCT/CNTVCT
     *   CNTVOFF_EL2 = 0          → no virtual timer offset
     *   CPTR_EL2 = 0x33FF        → no traps to EL2 (all bits clear except RES1)
     *   HSTR_EL2 = 0             → no system register traps
     *   CPACR_EL1[21:20] = 0b11  → FP/SIMD not trapped at EL1
     *   HCR_EL2[31] = 1          → EL1 is AArch64
     *   SCTLR_EL1 = 0x30D00800   → RES1 bits, MMU/caches off
     *   SPSR_EL2 = 0x3C4         → EL1h, DAIF masked
     */
    .macro el2_to_el1, tmp1, tmp2

    /* D13.2.27: enable EL1 physical and virtual counter access */
    mrs     \tmp1, cnthctl_el2
    orr     \tmp1, \tmp1, #0x3
    msr     cnthctl_el2, \tmp1
    msr     cntvoff_el2, xzr

    /* D13.2.141/142: copy MIDR/MPIDR to virtualization registers */
    mrs     \tmp1, midr_el1
    mrs     \tmp2, mpidr_el1
    msr     vpidr_el2, \tmp1
    msr     vmpidr_el2, \tmp2

    /* D13.2.30: disable all coprocessor traps to EL2 */
    mov     \tmp1, #0x33FF
    msr     cptr_el2, \tmp1
    msr     hstr_el2, xzr

    /* D13.2.36: enable FP/SIMD at EL1 (FPEN bits [21:20] = 0b11) */
    mov     \tmp1, #(3 << 20)
    msr     cpacr_el1, \tmp1

    /* D13.2.47: EL1 executes in AArch64 (RW bit [31] = 1) */
    mov     \tmp1, #(1 << 31)
    msr     hcr_el2, \tmp1

    /* D13.2.113: SCTLR_EL1 RES1 bits, everything else off */
    mov     \tmp1, #0x0800
    movk    \tmp1, #0x30D0, lsl #16
    msr     sctlr_el1, \tmp1

    /* D13.2.109: return to EL1h (M[3:0]=0b0100) with DAIF masked */
    mov     \tmp1, #0x3C4
    msr     spsr_el2, \tmp1
    adr     \tmp1, 1f
    msr     elr_el2, \tmp1
    eret
1:
    .endm

_start:
    /* Save DTB pointer (firmware passes it in x0) */
    mov     x20, x0

    /* Check current exception level — ARM ARM D1.9 */
    mrs     x0, CurrentEL
    cmp     x0, #8                  /* CurrentEL == 8 means EL2 */
    b.eq    in_el2
    cmp     x0, #4                  /* CurrentEL == 4 means EL1 */
    b.eq    in_el1
    b       .                       /* EL3 or EL0 — should not happen, hang */

in_el2:
    el2_to_el1 x0, x1

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
     * SP_EL0 = 0x00800000 (main stack, grows down)
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
    ldr     x0, =0x00800000
    mov     sp, x0              /* SP_EL0 = main stack */

    /* Install exception vector table — ARM ARM D1.10.2 */
    adr     x0, boot_vectors
    msr     vbar_el1, x0
    isb

    /* Restore DTB pointer as first argument to boot() */
    mov     x0, x20

    /* Branch to C boot entry */
    bl      boot

    /* Should not return — hang if it does */
hang:
    wfe
    b       hang

/*
 * Minimal exception vector table for bootstrap debugging.
 * Layout per ARM ARM D1.10.2:
 *   4 groups × 4 vectors × 128 bytes each = 2048 bytes total.
 *   Group 0: Current EL with SP_EL0
 *   Group 1: Current EL with SP_ELx
 *   Group 2: Lower EL, AArch64
 *   Group 3: Lower EL, AArch32
 */
    .balign 2048
boot_vectors:
    /* Current EL with SP_EL0 */
    b       boot_sync_handler   /* Synchronous */
    .balign 128
    b       hang                /* IRQ */
    .balign 128
    b       hang                /* FIQ */
    .balign 128
    b       hang                /* SError */
    .balign 128

    /* Current EL with SP_ELx */
    b       boot_sync_handler   /* Synchronous */
    .balign 128
    b       hang                /* IRQ */
    .balign 128
    b       hang                /* FIQ */
    .balign 128
    b       hang                /* SError */
    .balign 128

    /* Lower EL using AArch64 */
    b       hang
    .balign 128
    b       hang
    .balign 128
    b       hang
    .balign 128
    b       hang
    .balign 128

    /* Lower EL using AArch32 */
    b       hang
    .balign 128
    b       hang
    .balign 128
    b       hang
    .balign 128
    b       hang
    .balign 128

boot_sync_handler:
    /* Print exception info via C helper */
    mrs     x0, esr_el1
    mrs     x1, elr_el1
    mrs     x2, far_el1
    bl      boot_exception_handler
    b       hang

    .section .aros.startup
    .string "AROS/AArch64 Bootstrap (" __DATE__ ")"
    .balign 8
