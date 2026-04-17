/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
    Desc: KrnSti — enable interrupts on AArch64.
*/

#include <aros/kernel.h>
#include <kernel_base.h>
#include <proto/kernel.h>

#include "tls.h"

AROS_LH0I(void, KrnSti,
    struct KernelBase *, KernelBase, 10, Kernel)
{
    AROS_LIBFUNC_INIT

    /*
     * Do not unmask IRQs if we are inside an exception handler
     * (SupervisorCount > 0).  SoftIntDispatch calls KrnSti()
     * before each handler; allowing that inside an IRQ context
     * would cause nested IRQs on the shared SP_EL1 stack.
     */
    tls_t *__tls;
    __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
    if (__tls->SupervisorCount == 0)
        asm volatile("msr daifclr, #3" ::: "memory");

    AROS_LIBFUNC_EXIT
}
