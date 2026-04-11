/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
    Desc: KrnDispatch — dispatch next ready task, AArch64.
*/

#include <aros/kernel.h>
#include <kernel_base.h>
#include <kernel_syscall.h>
#include <proto/kernel.h>

AROS_LH0(void, KrnDispatch,
    struct KernelBase *, KernelBase, 4, Kernel)
{
    AROS_LIBFUNC_INIT

    krnSysCall(SC_DISPATCH);

    AROS_LIBFUNC_EXIT
}
