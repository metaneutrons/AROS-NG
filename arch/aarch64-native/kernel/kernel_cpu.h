/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: CPU-specific definitions for AArch64 kernel.
*/

#ifndef KERNEL_CPU_AARCH64_H
#define KERNEL_CPU_AARCH64_H

#include <inttypes.h>
#include <aros/aarch64/cpucontext.h>
#include "kernel_aarch64.h"

/* We use native context format, no conversion needed */
#define regs_t struct ExceptionContext
#define AROSCPUContext ExceptionContext

#define EXCEPTIONS_COUNT    1

#define AARCH64_FPU_TYPE    FPU_VFP
#define AARCH64_FPU_SIZE    (32 * 128)

#define ADDTIME(dest, src)              \
    (dest)->tv_micro += (src)->tv_micro; \
    (dest)->tv_secs  += (src)->tv_secs;  \
    while ((dest)->tv_micro > 999999)    \
    {                                    \
        (dest)->tv_secs++;               \
        (dest)->tv_micro -= 1000000;     \
    }

typedef int cpumode_t;
#define goSuper() 0
#define goUser()
#define goBack(mode) ((void)(mode))

/* SVC call for system calls */
#undef krnSysCall
#define krnSysCall(n) __asm__ volatile("svc %[svc_no]" : : [svc_no] "I" (n) : "x30")

static inline int GetCPUNumber(void)
{
    uint64_t mpidr;
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
    return mpidr & 3;
}

#endif /* KERNEL_CPU_AARCH64_H */
