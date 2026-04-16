/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel startup — arch-specific part for kernel.resource kobj.
          The actual boot entry is in kernel_cstart.c (standalone core.elf).
          This file provides the kernel_cstart function that the kobj links against.
*/

#define DEBUG 0

#include <aros/kernel.h>
#include <aros/symbolsets.h>
#include <aros/aarch64/cpucontext.h>
#include <aros/cpu.h>
#include <exec/memory.h>
#include <exec/memheaderext.h>
#include <exec/tasks.h>
#include <exec/alerts.h>
#include <exec/execbase.h>
#include <proto/kernel.h>
#include <proto/exec.h>

#include <strings.h>
#include <string.h>

#include "exec_intern.h"
#include "etask.h"
#include "tlsf.h"

#include "kernel_intern.h"
#include "kernel_debug.h"
#include "kernel_romtags.h"

#undef KernelBase
#include "tls.h"

extern struct TagItem *BootMsg;

struct AARCH64_Implementation __aarch64_arosintern
    __attribute__((aligned(8), section(".data"))) = {0};

struct ExecBase *SysBase __attribute__((section(".data"))) = NULL;

struct KernelBase *getKernelBase(void)
{
    return (struct KernelBase *)KernelBase;
}
