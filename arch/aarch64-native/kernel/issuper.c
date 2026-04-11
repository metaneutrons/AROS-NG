/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: KrnIsSuper — check if running in supervisor (exception) context, AArch64.
*/

#include <aros/kernel.h>
#include <aros/libcall.h>

#include <kernel_base.h>

#include <proto/kernel.h>

#include "tls.h"

/* See rom/kernel/issuper.c for documentation */

AROS_LH0I(int, KrnIsSuper,
    struct KernelBase *, KernelBase, 13, Kernel)
{
    AROS_LIBFUNC_INIT

    /*
     * On AArch64 native AROS, all code runs at EL1 — there is no
     * user-mode EL0. We use a TLS counter (SupervisorCount) that is
     * incremented on IRQ entry and decremented on IRQ exit to detect
     * whether we are inside an exception handler.
     */
    tls_t *__tls;
    __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
    return __tls->SupervisorCount > 0;

    AROS_LIBFUNC_EXIT
}
