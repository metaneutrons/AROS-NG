/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: ANSI C function setjmp(), AArch64 version
    Lang: english

    jmp_buf layout (26 x 8 = 208 bytes):
      [0..9]   x19-x28  (callee-saved GPRs)
      [10]     x29 (fp)
      [11]     x30 (lr)
      [12]     sp
      [13..20] d8-d15   (callee-saved FP/NEON regs)
*/

#include "aros/aarch64/asm.h"

    .text
    .balign 4
    .global AROS_CDEFNAME(setjmp)
    .type   AROS_CDEFNAME(setjmp), %function

AROS_CDEFNAME(setjmp):
    /* x0 = jmp_buf pointer */
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
