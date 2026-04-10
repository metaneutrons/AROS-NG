/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: POSIX vfork(), AArch64 version
    Lang: english

    Calls setjmp to save context into a stack-allocated jmp_buf,
    then passes it to __vfork() which never returns normally.

    Entry state:  x30 = return address, sp = 16-byte aligned
    Exit state:   Does not return (enters __vfork)
*/

#include "aros/aarch64/asm.h"

    .text
    .balign 4
    .global AROS_CDEFNAME(vfork)
    .type   AROS_CDEFNAME(vfork), %function

AROS_CDEFNAME(vfork):
    /* Allocate jmp_buf on stack (168 bytes, rounded to 176 for 16-byte alignment) */
    stp     x29, x30, [sp, #-192]!
    mov     x29, sp
    add     x0, sp, #16            /* x0 = &jmp_buf (after saved fp/lr) */
    bl      AROS_CDEFNAME(setjmp)

    /* Patch the saved lr into jmp_buf slot [11] (offset 88) = return address */
    ldr     x1, [sp, #8]           /* x1 = saved x30 (our caller's return addr) */
    str     x1, [sp, #16 + 88]     /* store into jmp_buf lr slot */

    /* Patch the saved sp: caller's sp = our sp + 192 */
    add     x1, sp, #192
    str     x1, [sp, #16 + 96]     /* store into jmp_buf sp slot */

    add     x0, sp, #16            /* x0 = &jmp_buf */
    b       __vfork                 /* tail-call __vfork, never returns */
