/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 CPU context parsing routines for alerts.
*/

#include <exec/rawfmt.h>
#include <proto/exec.h>

#include "exec_intern.h"
#include "exec_util.h"

static const char *gpr_fmt =
    " X0=0x%016lx  X1=0x%016lx  X2=0x%016lx  X3=0x%016lx\n"
    " X4=0x%016lx  X5=0x%016lx  X6=0x%016lx  X7=0x%016lx\n"
    " X8=0x%016lx  X9=0x%016lx X10=0x%016lx X11=0x%016lx\n"
    "X12=0x%016lx X13=0x%016lx X14=0x%016lx X15=0x%016lx\n"
    "X16=0x%016lx X17=0x%016lx X18=0x%016lx X19=0x%016lx\n"
    "X20=0x%016lx X21=0x%016lx X22=0x%016lx X23=0x%016lx\n"
    "X24=0x%016lx X25=0x%016lx X26=0x%016lx X27=0x%016lx\n"
    "X28=0x%016lx  FP=0x%016lx  LR=0x%016lx  SP=0x%016lx\n"
    " PC=0x%016lx  PSTATE=0x%016lx";

char *FormatCPUContext(char *buffer, struct ExceptionContext *ctx,
                       struct ExecBase *SysBase)
{
    VOID_FUNC dest = buffer ? RAWFMTFUNC_STRING : RAWFMTFUNC_SERIAL;
    char *buf;

    buf = NewRawDoFmt(gpr_fmt, dest, buffer,
                      ctx->r[0],  ctx->r[1],  ctx->r[2],  ctx->r[3],
                      ctx->r[4],  ctx->r[5],  ctx->r[6],  ctx->r[7],
                      ctx->r[8],  ctx->r[9],  ctx->r[10], ctx->r[11],
                      ctx->r[12], ctx->r[13], ctx->r[14], ctx->r[15],
                      ctx->r[16], ctx->r[17], ctx->r[18], ctx->r[19],
                      ctx->r[20], ctx->r[21], ctx->r[22], ctx->r[23],
                      ctx->r[24], ctx->r[25], ctx->r[26], ctx->r[27],
                      ctx->r[28], ctx->fp,    ctx->lr,    ctx->sp,
                      ctx->pc,    ctx->pstate);

    return buf - 1;
}

APTR UnwindFrame(APTR fp, APTR *caller)
{
    /*
     * AArch64 frame layout (AAPCS64):
     *   [fp, #0]  = previous frame pointer (x29)
     *   [fp, #8]  = return address (x30)
     */
    APTR *frame = fp;

    *caller = frame[1];     /* x30 = return address */
    return frame[0];        /* x29 = previous fp    */
}
