/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: POSIX siglongjmp(), AArch64 version
    Lang: english

    On AROS, siglongjmp is identical to longjmp (no signal mask to restore).
    jmp_buf layout: see stdc/setjmp.S
*/

#include "aros/aarch64/asm.h"

    .text
    .balign 4
    .global AROS_CDEFNAME(siglongjmp)
    .type   AROS_CDEFNAME(siglongjmp), %function

AROS_CDEFNAME(siglongjmp):
    /* x0 = sigjmp_buf pointer, w1 = return value */
    ldp     x19, x20, [x0, #0]
    ldp     x21, x22, [x0, #16]
    ldp     x23, x24, [x0, #32]
    ldp     x25, x26, [x0, #48]
    ldp     x27, x28, [x0, #64]
    ldp     x29, x30, [x0, #80]
    ldr     x2,       [x0, #96]
    mov     sp, x2
    ldp     d8,  d9,  [x0, #104]
    ldp     d10, d11, [x0, #120]
    ldp     d12, d13, [x0, #136]
    ldp     d14, d15, [x0, #152]
    mov     w0, w1
    cmp     w0, #0
    cinc    w0, w0, eq
    ret
