/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: PrepareContext() - Prepare a task context for dispatch, AArch64 version.
*/

#include <exec/execbase.h>
#include <exec/memory.h>
#include <utility/tagitem.h>
#include <proto/arossupport.h>
#include <proto/kernel.h>
#include <aros/aarch64/cpucontext.h>

#include "exec_intern.h"
#include "exec_util.h"
#if defined(__AROSEXEC_SMP__)
#include "etask.h"
#endif

BOOL PrepareContext(struct Task *task, APTR entryPoint, APTR fallBack,
                    const struct TagItem *tagList, struct ExecBase *SysBase)
{
    struct TagItem *t;
    struct ExceptionContext *ctx;

    /*
     * AArch64 AAPCS64: x0-x7 are argument registers (8 register args).
     * No stack arguments needed for up to 8 args.
     */
    IPTR args[8] = {0};
    int numargs = 0;

    if (!(task->tc_Flags & TF_ETASK))
        return FALSE;

    ctx = KrnCreateContext();
    task->tc_UnionETask.tc_ETask->et_RegFrame = ctx;
    if (!ctx)
        return FALSE;

    /* Set up function arguments from tags */
    while ((t = LibNextTagItem((struct TagItem **)&tagList)))
    {
        switch (t->ti_Tag)
        {
#if defined(__AROSEXEC_SMP__)
            case TASKTAG_AFFINITY:
                IntETask(task->tc_UnionETask.tc_ETask)->iet_CpuAffinity = t->ti_Data;
                break;
#endif
            /*
             * AArch64: first 8 arguments go in x0-x7 (all register args).
             * No stack arguments needed for TASKTAG_ARG1-ARG8.
             */
#define REGARG(x)                           \
            case TASKTAG_ARG ## x:          \
                args[x - 1] = t->ti_Data;  \
                if (x > numargs)            \
                    numargs = x;            \
                break;

            REGARG(1)
            REGARG(2)
            REGARG(3)
            REGARG(4)
            REGARG(5)
            REGARG(6)
            REGARG(7)
            REGARG(8)
#undef REGARG
        }
    }

    /* Place arguments in x0-x7 */
    {
        int i;
        for (i = 0; i < numargs && i < 8; i++)
            ctx->r[i] = args[i];
    }

    /* Frame pointer = 0 (end of call chain) */
    ctx->fp = 0;

    /* Link register = fallBack (where task returns to) */
    ctx->lr = (IPTR)fallBack;

    ctx->Flags = 0;

    /* Stack pointer and entry point */
    ctx->pc = (IPTR)entryPoint;

    /*
     * Set up a fake switch frame on the task's stack.
     * When the task is first dispatched via the SVC handler's
     * context restore path, it will pop this frame.
     *
     * Frame layout (growing downward):
     *   [SP+0]   x19, x20
     *   [SP+16]  x21, x22
     *   [SP+32]  x23, x24
     *   [SP+48]  x25, x26
     *   [SP+64]  x27, x28
     *   [SP+80]  ELR_EL1, SPSR_EL1
     *   [SP+96]  x29 (fp), x30 (lr)
     */
    {
        IPTR *sp = (IPTR *)task->tc_SPReg;
        /* 7 pairs = 14 slots = 112 bytes */
        sp -= 14;

        sp[0]  = 0;                    /* x19 */
        sp[1]  = 0;                    /* x20 */
        sp[2]  = 0;                    /* x21 */
        sp[3]  = 0;                    /* x22 */
        sp[4]  = 0;                    /* x23 */
        sp[5]  = 0;                    /* x24 */
        sp[6]  = 0;                    /* x25 */
        sp[7]  = 0;                    /* x26 */
        sp[8]  = 0;                    /* x27 */
        sp[9]  = 0;                    /* x28 */
        sp[10] = (IPTR)entryPoint;     /* ELR_EL1 — where eret jumps to */
        sp[11] = 0x00000005;           /* SPSR_EL1 — EL1h, interrupts enabled */
        sp[12] = 0;                    /* x29 (fp) */
        sp[13] = (IPTR)fallBack;       /* x30 (lr) — return address */

        task->tc_SPReg = (APTR)sp;
        ctx->sp = (IPTR)sp;
    }

    return TRUE;
}
