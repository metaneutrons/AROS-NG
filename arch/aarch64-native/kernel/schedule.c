/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
    Desc: KrnSchedule — run task scheduling, AArch64.
*/

#include <aros/kernel.h>
#include <kernel_base.h>
#include <kernel_syscall.h>
#include <proto/kernel.h>

AROS_LH0(void, KrnSchedule,
    struct KernelBase *, KernelBase, 6, Kernel)
{
    AROS_LIBFUNC_INIT

    krnSysCall(SC_SCHEDULE);

    AROS_LIBFUNC_EXIT
}
