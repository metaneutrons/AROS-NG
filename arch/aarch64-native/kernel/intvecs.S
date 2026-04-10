/*
    Ported from Circle - A C++ bare metal environment for Raspberry Pi
    Copyright (C) 2014-2020 R. Stange <rsta2@o2online.de>
    Licensed under GPLv3

    Adapted for AROS by The AROS Development Team, 2026

    Desc: AArch64 exception vector table (VBAR_EL1)
    Lang: english

    AArch64 vector table layout:
      4 groups × 4 vectors × 128 bytes each = 2048 bytes total.
      Each vector entry is 128 bytes (32 instructions max).
      Group 0: Current EL with SP_EL0
      Group 1: Current EL with SP_ELx (x != 0)
      Group 2: Lower EL, AArch64
      Group 3: Lower EL, AArch32
*/

    /* Vector entry macro — each entry is 128-byte aligned */
    .macro vector handler
    .align 7
    b       \handler
    .endm

    /*
     * Exception stub macro — saves diagnostic registers and calls
     * C handler. Used for synchronous exceptions and SError.
     *
     * Entry state:  Exception taken, SP = sp_el1
     * Registers saved: ESR_EL1, SPSR_EL1, LR, ELR_EL1, SP_EL0, SP, FAR_EL1
     */
    .macro stub name, exception
    .globl \name
\name:
    mrs     x0, esr_el1
    mrs     x1, spsr_el1
    mov     x2, x30                 /* lr */
    mrs     x3, elr_el1
    mrs     x4, sp_el0
    mov     x5, sp
    mrs     x6, far_el1

    str     x6, [sp, #-16]!
    stp     x4, x5, [sp, #-16]!
    stp     x2, x3, [sp, #-16]!
    stp     x0, x1, [sp, #-16]!

    mov     x0, #\exception
    mov     x1, sp
    bl      ExceptionHandler        /* C handler — may not return */
    b       .                       /* hang if it does */
    .endm

    .text

    /*
     * Vector table — must be 2048-byte (0x800) aligned.
     * Installed via: msr vbar_el1, x0
     */
    .align 11

    .globl VectorTable
VectorTable:

    /* Group 0: Current EL with SP_EL0 (EL1t mode) */
    vector  SynchronousStub
    vector  IRQStub
    vector  FIQStub
    vector  SErrorStub

    /* Group 1: Current EL with SP_ELx (EL1h mode — used during IRQ) */
    vector  SynchronousStub
    vector  IRQStub
    vector  FIQStub
    vector  SErrorStub

    /* Group 2: Lower EL, AArch64 (EL0 → EL1) */
    vector  SynchronousStub
    vector  IRQStub
    vector  FIQStub
    vector  SErrorStub

    /* Group 3: Lower EL, AArch32 — not used, stub to unexpected */
    vector  UnexpectedStub
    vector  UnexpectedStub
    vector  UnexpectedStub
    vector  UnexpectedStub

/*
 * Exception stubs
 */
    stub    UnexpectedStub,     0
    stub    SynchronousStub,    1
    stub    SErrorStub,         3

/*
 * IRQ stub — saves all GPRs, calls InterruptHandler, restores and returns.
 *
 * Entry state:  IRQ taken at EL1, SP = sp_el1
 * Exit state:   All registers restored, eret back to interrupted code
 */
    .globl IRQStub
IRQStub:
    stp     x29, x30, [sp, #-16]!

    /* Save ELR and SPSR so we can nest if needed */
    mrs     x29, elr_el1
    mrs     x30, spsr_el1
    stp     x29, x30, [sp, #-16]!

    /* Save x0-x28 */
    stp     x27, x28, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x17, x18, [sp, #-16]!
    stp     x15, x16, [sp, #-16]!
    stp     x13, x14, [sp, #-16]!
    stp     x11, x12, [sp, #-16]!
    stp     x9,  x10, [sp, #-16]!
    stp     x7,  x8,  [sp, #-16]!
    stp     x5,  x6,  [sp, #-16]!
    stp     x3,  x4,  [sp, #-16]!
    stp     x1,  x2,  [sp, #-16]!
    str     x0,       [sp, #-16]!

    bl      InterruptHandler

    /* Restore x0-x28 */
    ldr     x0,       [sp], #16
    ldp     x1,  x2,  [sp], #16
    ldp     x3,  x4,  [sp], #16
    ldp     x5,  x6,  [sp], #16
    ldp     x7,  x8,  [sp], #16
    ldp     x9,  x10, [sp], #16
    ldp     x11, x12, [sp], #16
    ldp     x13, x14, [sp], #16
    ldp     x15, x16, [sp], #16
    ldp     x17, x18, [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x27, x28, [sp], #16

    /* Restore ELR and SPSR */
    ldp     x29, x30, [sp], #16
    msr     elr_el1, x29
    msr     spsr_el1, x30

    ldp     x29, x30, [sp], #16

    eret

/*
 * FIQ stub — minimal, just returns for now.
 * Will be expanded when GIC FIQ support is added (Task 7).
 */
    .globl FIQStub
FIQStub:
    eret
