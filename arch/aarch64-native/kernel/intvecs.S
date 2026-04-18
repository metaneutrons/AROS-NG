/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: AArch64 exception vector table (VBAR_EL1)
    Lang: english

    Vector table layout per ARM ARM D1.10.2:
      4 groups × 4 vectors × 128 bytes each = 2048 bytes total.
      Each vector entry is 128 bytes (32 instructions max).
      Group 0: Current EL with SP_EL0
      Group 1: Current EL with SP_ELx (x != 0)
      Group 2: Lower EL, AArch64
      Group 3: Lower EL, AArch32

    Exception syndrome register (ESR_EL1) encoding: ARM ARM D13.2.36
    SVC exception class: EC = 0x15 (ARM ARM D13.2.36, Table D13-1)
*/

    /* Vector entry macro — each entry must be 128-byte aligned (ARM ARM D1.10.2) */
    .macro vector handler
    .align 7
    b       \handler
    .endm

    /*
     * Exception diagnostic stub — saves key system registers to stack
     * and calls C handler for reporting.
     *
     * Registers saved: ESR_EL1, SPSR_EL1, LR, ELR_EL1, SP_EL0, SP, FAR_EL1
     */
    .macro exc_stub name, exception
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
     * Installed via: msr vbar_el1, <addr>
     * Ref: ARM ARM D1.10.2
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
    exc_stub    UnexpectedStub,     0
    exc_stub    SErrorStub,         3

/*
 * Synchronous exception stub — handles SVC for AROS task switching.
 *
 * For SC_SWITCH/SC_SCHEDULE: cooperative context switch.
 * The SVC is called from C code (KrnSwitch), so only callee-saved
 * registers need to be preserved across the switch. The C compiler
 * has already saved caller-saved registers on the stack.
 *
 * Context switch strategy:
 *   1. Save callee-saved regs + SP to current task's ExceptionContext
 *   2. Call core_Switch() + core_Dispatch() to pick next task
 *   3. Restore callee-saved regs + SP from new task's ExceptionContext
 *   4. eret back to new task
 *
 * SVC exception class: ESR_EL1.EC == 0x15 (ARM ARM D13.2.36, Table D13-1)
 */
    .globl SynchronousStub
SynchronousStub:
    /* Check if this is an SVC (ESR_EL1.EC == 0x15) */
    mrs     x0, esr_el1
    lsr     x1, x0, #26
    cmp     x1, #0x15
    b.ne    .Lsync_not_svc

    /* Extract syscall number from ESR_EL1.ISS[15:0] */
    and     x0, x0, #0xFFFF

    /* AROS syscall dispatch */
    cmp     x0, #2                 /* SC_SWITCH */
    b.eq    .Ldo_switch
    cmp     x0, #3                 /* SC_SCHEDULE */
    b.eq    .Ldo_schedule
    cmp     x0, #1                 /* SC_DISPATCH */
    b.eq    .Ldo_dispatch

    /* Other syscalls: save minimal state and call C handler */
    stp     x29, x30, [sp, #-16]!
    bl      HandleSyscall
    ldp     x29, x30, [sp], #16
    eret

.Ldo_schedule:
    /* Save minimal state to check if reschedule is needed */
    stp     x29, x30, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    bl      core_Schedule           /* returns BOOL in x0 */
    cbz     x0, .Lno_reschedule
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    b       .Ldo_switch

.Lno_reschedule:
    ldp     x19, x20, [sp], #16
    ldp     x29, x30, [sp], #16
    eret

.Ldo_switch:
    /*
     * Save current task's context.
     * We save: x0-x7 (args), x19-x28 (callee-saved), x29 (fp), x30 (lr),
     *          ELR_EL1 (return PC), SPSR_EL1
     * These are saved on the current stack, then we store SP
     * into the task's ExceptionContext.
     */
    stp     x29, x30, [sp, #-16]!
    mrs     x29, elr_el1
    mrs     x30, spsr_el1
    stp     x29, x30, [sp, #-16]!
    stp     x27, x28, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x6,  x7,  [sp, #-16]!
    stp     x4,  x5,  [sp, #-16]!
    stp     x2,  x3,  [sp, #-16]!
    stp     x0,  x1,  [sp, #-16]!

    /* Save SP into current task's context */
    mov     x0, sp
    bl      switch_save_sp          /* x0 = SP with saved regs */

    /* Pick next task */
    bl      switch_dispatch         /* returns new task SP in x0 */

    /* Restore new task's SP */
    mov     sp, x0

    /* Restore registers */
    ldp     x0,  x1,  [sp], #16
    ldp     x2,  x3,  [sp], #16
    ldp     x4,  x5,  [sp], #16
    ldp     x6,  x7,  [sp], #16
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

.Ldo_dispatch:
    /*
     * SC_DISPATCH: dispatch next task WITHOUT saving current context.
     * Used by RemTask(NULL) — the current task is being destroyed,
     * so there's nothing to save.
     */
    bl      switch_dispatch_only    /* returns new task SP in x0 */
    mov     sp, x0

    /* Restore SVC frame */
    ldp     x0,  x1,  [sp], #16
    ldp     x2,  x3,  [sp], #16
    ldp     x4,  x5,  [sp], #16
    ldp     x6,  x7,  [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x27, x28, [sp], #16
    ldp     x29, x30, [sp], #16
    msr     elr_el1, x29
    msr     spsr_el1, x30
    ldp     x29, x30, [sp], #16
    eret

    /* --- Non-SVC synchronous exception --- */
.Lsync_not_svc:
    mrs     x0, esr_el1
    mrs     x1, spsr_el1
    mov     x2, x30
    mrs     x3, elr_el1
    mrs     x4, sp_el0
    mov     x5, sp
    mrs     x6, far_el1

    str     x6, [sp, #-16]!
    stp     x4, x5, [sp, #-16]!
    stp     x2, x3, [sp, #-16]!
    stp     x0, x1, [sp, #-16]!

    mov     x0, #1
    mov     x1, sp
    bl      ExceptionHandler
    b       .

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

    /*
     * Check if preemptive task switch is needed.
     * irq_RescheduleCheck() returns 1 if core_Schedule() says switch.
     */
    bl      irq_RescheduleCheck
    cbnz    x0, .Lirq_switch

    /* No switch needed — restore all registers and return */
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
    ldp     x29, x30, [sp], #16
    msr     elr_el1, x29
    msr     spsr_el1, x30
    ldp     x29, x30, [sp], #16
    eret

.Lirq_switch:
    /*
     * Preemptive task switch from IRQ context.
     *
     * The full register set is saved on the IRQ stack (SP_EL1).
     * We need to convert the IRQ frame to an SVC-compatible frame
     * so the SVC restore path can dispatch the new task.
     *
     * IMPORTANT: We must use the SVC frame format for the save
     * so that the SVC restore path can restore it correctly.
     *
     * Approach: pop the full IRQ frame back into registers,
     * then push an SVC-compatible frame.
     *
     * IRQ frame (on stack): x0, x1-x2, ..., x27-x28, ELR, SPSR, x29, x30
     * SVC frame: x0-x1, x2-x3, x4-x5, x6-x7, x19-x20, x21-x22, x23-x24,
     *            x25-x26, x27-x28, ELR, SPSR, x29, x30
     */

    /* Restore all regs from IRQ frame into CPU registers */
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
    /* Stack now has: [SP] = ELR, SPSR, [SP+16] = x29, x30 */

    /* Stash ELR and SPSR in x8/x9 (already restored from IRQ frame) */
    ldp     x29, x30, [sp], #16    /* x29=ELR, x30=SPSR (temp) */
    mov     x8, x29                 /* x8 = ELR_EL1 */
    mov     x9, x30                 /* x9 = SPSR_EL1 */
    ldp     x29, x30, [sp], #16    /* restore real x29, x30 */

    /* Now all registers are restored. Push SVC-compatible frame. */
    stp     x29, x30, [sp, #-16]!
    stp     x8,  x9,  [sp, #-16]!  /* ELR, SPSR */
    stp     x27, x28, [sp, #-16]!
    stp     x25, x26, [sp, #-16]!
    stp     x23, x24, [sp, #-16]!
    stp     x21, x22, [sp, #-16]!
    stp     x19, x20, [sp, #-16]!
    stp     x6,  x7,  [sp, #-16]!
    stp     x4,  x5,  [sp, #-16]!
    stp     x2,  x3,  [sp, #-16]!
    stp     x0,  x1,  [sp, #-16]!

    /* Do the same switch as .Ldo_switch */
    mov     x0, sp
    bl      switch_save_sp
    bl      switch_dispatch
    mov     sp, x0

    /* Restore SVC frame (same as .Ldo_switch) */
    ldp     x0,  x1,  [sp], #16
    ldp     x2,  x3,  [sp], #16
    ldp     x4,  x5,  [sp], #16
    ldp     x6,  x7,  [sp], #16
    ldp     x19, x20, [sp], #16
    ldp     x21, x22, [sp], #16
    ldp     x23, x24, [sp], #16
    ldp     x25, x26, [sp], #16
    ldp     x27, x28, [sp], #16
    ldp     x29, x30, [sp], #16
    msr     elr_el1, x29
    msr     spsr_el1, x30
    ldp     x29, x30, [sp], #16
    eret

/*
 * FIQ stub — minimal, just returns for now.
 */
    .globl FIQStub
FIQStub:
    eret
