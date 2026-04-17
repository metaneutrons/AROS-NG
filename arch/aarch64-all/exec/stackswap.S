/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: StackSwap() - Swap the stack of a task, AArch64 version.
    Lang: english

    Entry state:
        x0 = struct StackSwapStruct *newStack
        x1 = struct ExecBase *SysBase
        x30 = return address
        sp = current stack (16-byte aligned)

    Exit state:
        Stack pointer swapped. Old stack info saved in newStack struct.
        All callee-saved registers preserved.
*/

#include <aros/aarch64/asm.h>

    .text
    .balign 4
    .globl  AROS_SLIB_ENTRY(StackSwap,Exec,122)

AROS_SLIB_ENTRY(StackSwap,Exec,122):

    /* x0 = newStack, x1 = SysBase, x30 = return address */

    /* Save registers we need across calls */
    stp     x0, x1, [sp, #-48]!
    stp     x29, x30, [sp, #16]
    str     x19, [sp, #32]
    mov     x29, sp

    /* x19 = newStack (callee-saved, survives function calls) */
    mov     x19, x0

    /* FindTask(NULL) — get current task */
    mov     x0, #0
    mov     x16, FindTask
    ldr     x16, [x1, x16]
    blr     x16
    mov     x2, x0                 /* x2 = current task */

    /* Reload saved registers */
    ldp     x0, x1, [sp]           /* x0 = newStack, x1 = SysBase */

    /* Disable() */
    stp     x0, x1, [sp]
    stp     x2, x19, [sp, #16]
    mov     x0, x1
    mov     x16, Disable
    ldr     x16, [x1, x16]
    blr     x16
    ldp     x0, x1, [sp]
    ldp     x2, x19, [sp, #16]

    /* x0 = newStack, x1 = SysBase, x2 = task, x19 = newStack */

    /* Swap Lower boundaries */
    ldr     x3, [x2, tc_SPLower]
    ldr     x4, [x19, stk_Lower]
    str     x4, [x2, tc_SPLower]
    str     x3, [x19, stk_Lower]

    /* Swap Upper boundaries */
    ldr     x3, [x2, tc_SPUpper]
    ldr     x4, [x19, stk_Upper]
    str     x4, [x2, tc_SPUpper]
    str     x3, [x19, stk_Upper]

    /* Swap stack pointers */
    mov     x3, sp
    ldr     x4, [x19, stk_Pointer]
    mov     sp, x4
    str     x3, [x19, stk_Pointer]

    /* Enable() */
    stp     x0, x1, [sp, #-16]!
    mov     x0, x1
    mov     x16, Enable
    ldr     x16, [x1, x16]
    blr     x16
    ldp     x0, x1, [sp], #16

    /* Restore callee-saved and return */
    ldr     x19, [sp, #32]
    ldp     x29, x30, [sp, #16]
    add     sp, sp, #48
    ret
