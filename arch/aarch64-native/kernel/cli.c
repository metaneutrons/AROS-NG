/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
    Desc: KrnCli — disable interrupts on AArch64.
*/

#include <aros/kernel.h>
#include <kernel_base.h>
#include <proto/kernel.h>

AROS_LH0I(void, KrnCli,
    struct KernelBase *, KernelBase, 9, Kernel)
{
    AROS_LIBFUNC_INIT

    asm volatile("msr daifset, #3" ::: "memory"); /* mask IRQ + FIQ */

    AROS_LIBFUNC_EXIT
}
