/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
    Desc: KrnSti — enable interrupts on AArch64.
*/

#include <aros/kernel.h>
#include <kernel_base.h>
#include <proto/kernel.h>

AROS_LH0I(void, KrnSti,
    struct KernelBase *, KernelBase, 10, Kernel)
{
    AROS_LIBFUNC_INIT

    asm volatile("msr daifclr, #3" ::: "memory"); /* unmask IRQ + FIQ */

    AROS_LIBFUNC_EXIT
}
