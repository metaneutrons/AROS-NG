/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: POSIX sigsetjmp(), AArch64 version
    Lang: english

    On AROS, sigsetjmp is identical to setjmp (no signal mask to save).
    jmp_buf layout: see stdc/setjmp.S
*/

#include "aros/aarch64/asm.h"

    .text
    .balign 4
    .global AROS_CDEFNAME(sigsetjmp)
    .type   AROS_CDEFNAME(sigsetjmp), %function

AROS_CDEFNAME(sigsetjmp):
    /* x0 = sigjmp_buf pointer, w1 = savemask (ignored on AROS) */
    stp     x19, x20, [x0, #0]
    stp     x21, x22, [x0, #16]
    stp     x23, x24, [x0, #32]
    stp     x25, x26, [x0, #48]
    stp     x27, x28, [x0, #64]
    stp     x29, x30, [x0, #80]
    mov     x2, sp
    str     x2,       [x0, #96]
    stp     d8,  d9,  [x0, #104]
    stp     d10, d11, [x0, #120]
    stp     d12, d13, [x0, #136]
    stp     d14, d15, [x0, #152]
    mov     w0, #0
    ret
