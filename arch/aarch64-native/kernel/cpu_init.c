/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 cpu_Init — set correct kb_ContextSize.
*/

#include <aros/symbolsets.h>
#include <exec/types.h>

#include "kernel_base.h"
#include "kernel_cpu.h"

static int cpu_Init(struct KernelBase *KernelBase)
{
    KernelBase->kb_ContextSize = sizeof(struct AROSCPUContext);
    return TRUE;
}

ADD2INITLIB(cpu_Init, 5);
