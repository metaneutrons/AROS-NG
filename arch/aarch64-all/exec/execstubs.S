/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Stubs to call C functions while preserving all registers, AArch64 version
    Lang: english

    Entry state:  Called from user code via library jump vector.
                  x0-x7 may hold arguments. x30 = return address.
    Exit state:   All registers preserved (x0-x7, x9-x15, x29, x30).
                  Only x16/x17 may be clobbered (AAPCS64 ip0/ip1).
    Stack:        16-byte aligned at all times.
*/

#include "aros/aarch64/asm.h"

/*
 * STUB macro: call a C function while preserving all argument and
 * caller-saved registers. The C function address is loaded via
 * a PC-relative literal pool entry.
 *
 * Up to 8 arguments are preserved (x0-x7).
 * x9 is preserved as it may be used by the caller.
 */
.macro STUB cname, name
    .globl  \cname
    .type   \cname, %function
\cname:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x0, x1, [sp, #16]
    stp     x2, x3, [sp, #32]
    stp     x4, x5, [sp, #48]
    stp     x6, x7, [sp, #64]
    str     x9,     [sp, #80]
    bl      \name
    ldp     x0, x1, [sp, #16]
    ldp     x2, x3, [sp, #32]
    ldp     x4, x5, [sp, #48]
    ldp     x6, x7, [sp, #64]
    ldr     x9,     [sp, #80]
    ldp     x29, x30, [sp], #96
    ret
.endm

    .text

#ifdef UseExecstubs
    STUB AROS_SLIB_ENTRY(Disable,Exec,20),AROS_CSYMNAME(_Exec_20_Disable)
    STUB AROS_SLIB_ENTRY(Enable,Exec,21),AROS_CSYMNAME(_Exec_21_Enable)
    STUB AROS_SLIB_ENTRY(Forbid,Exec,22),AROS_CSYMNAME(_Exec_22_Forbid)
    STUB AROS_SLIB_ENTRY(Permit,Exec,23),AROS_CSYMNAME(_Exec_23_Permit)

    STUB AROS_SLIB_ENTRY(ObtainSemaphore,Exec,94),AROS_CSYMNAME(_Exec_94_ObtainSemaphore)
    STUB AROS_SLIB_ENTRY(ReleaseSemaphore,Exec,95),AROS_CSYMNAME(_Exec_95_ReleaseSemaphore)
    STUB AROS_SLIB_ENTRY(ObtainSemaphoreShared,Exec,113),AROS_CSYMNAME(_Exec_113_ObtainSemaphoreShared)
#endif
