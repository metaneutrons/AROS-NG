/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
    Desc: KrnSwitch — save current task context and dispatch next, AArch64.
*/

#include <aros/kernel.h>
#include <kernel_base.h>
#include <kernel_syscall.h>
#include <proto/kernel.h>

AROS_LH0(void, KrnSwitch,
    struct KernelBase *, KernelBase, 5, Kernel)
{
    AROS_LIBFUNC_INIT

    krnSysCall(SC_SWITCH);

    AROS_LIBFUNC_EXIT
}
