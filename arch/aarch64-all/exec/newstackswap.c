/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: NewStackSwap() - Call a function with swapped stack, AArch64 version
*/

#include <aros/debug.h>
#include <exec/tasks.h>
#include <proto/exec.h>

AROS_LH3(IPTR, NewStackSwap,
        AROS_LHA(struct StackSwapStruct *,  sss, A0),
        AROS_LHA(LONG_FUNC, entry, A1),
        AROS_LHA(struct StackSwapArgs *, args, A2),
        struct ExecBase *, SysBase, 134, Exec)
{
    AROS_LIBFUNC_INIT

    volatile struct Task *t = FindTask(NULL);
    volatile IPTR *sp = sss->stk_Pointer;
    volatile APTR spreg = t->tc_SPReg;
    volatile APTR splower = t->tc_SPLower;
    volatile APTR spupper = t->tc_SPUpper;
    IPTR ret;

    /*
     * AArch64 AAPCS64: all 8 arguments go in registers x0-x7.
     * No stack arguments needed. If args is NULL, use zero.
     */
    struct StackSwapArgs noargs = {{0}};
    if (args == NULL)
        args = &noargs;

    if (t->tc_Flags & TF_STACKCHK)
    {
        UBYTE *startfill = sss->stk_Lower;

        while (startfill < (UBYTE *)sp)
            *startfill++ = 0xE1;
    }

    D(bug("[NewStackSwap] SP 0x%p, entry point 0x%p\n", sp, entry));
    Disable();

    /* Change limits */
    t->tc_SPReg = (APTR)sp;
    t->tc_SPLower = sss->stk_Lower;
    t->tc_SPUpper = sss->stk_Upper;

    asm volatile
    (
    /* Save frame pointer so we can restore original SP later */
    "   stp     x29, x30, [sp, #-16]!\n"
    "   mov     x29, sp\n"
    /* Switch to new stack */
    "   mov     sp, %2\n"

    /* Enable() — preserves all registers by convention */
    "   mov     x0, %4\n"
    "   ldr     x16, [x0, #%c5]\n"
    "   blr     x16\n"

    /* Load arguments into x0-x7 and call entry */
    "   ldp     x0, x1, [%3, #0]\n"
    "   ldp     x2, x3, [%3, #16]\n"
    "   ldp     x4, x5, [%3, #32]\n"
    "   ldp     x6, x7, [%3, #48]\n"
    "   blr     %1\n"

    /* Save return value, then Disable() */
    "   mov     %0, x0\n"
    "   adrp    x0, SysBase\n"
    "   ldr     x0, [x0, #:lo12:SysBase]\n"
    "   ldr     x16, [x0, #%c6]\n"
    "   blr     x16\n"

    /* Restore original SP */
    "   mov     sp, x29\n"
    "   ldp     x29, x30, [sp], #16\n"
    : "=r"(ret)
    : "r"(entry), "r"(sp), "r"(args), "r"(SysBase),
      "i"(-21 * (int)sizeof(struct JumpVec)),   /* Enable  LVO 21 */
      "i"(-20 * (int)sizeof(struct JumpVec))    /* Disable LVO 20 */
    : "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7",
      "x16", "x17", "x30", "cc", "memory");

    /* Restore limits and return */
    t->tc_SPReg = spreg;
    t->tc_SPLower = splower;
    t->tc_SPUpper = spupper;
    Enable();

    D(bug("[NewStackSwap] Returning 0x%p\n", ret));
    return ret;

    AROS_LIBFUNC_EXIT
}
