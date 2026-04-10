/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel internal definitions.
          Modeled after arch/arm-native/kernel/kernel_intern.h.
*/

#ifndef KERNEL_INTERN_H_
#define KERNEL_INTERN_H_

#include <aros/libcall.h>
#include <inttypes.h>
#include <exec/lists.h>
#include <exec/execbase.h>
#include <exec/memory.h>
#include <utility/tagitem.h>
#include <stdio.h>
#include <stdarg.h>

#include "kernel_aarch64.h"

#undef KernelBase
struct KernelBase;

/* Device tree helpers */
void dt_set_root(void *r);
void *dt_find_node(char *key);
void *dt_find_node_by_phandle(uint32_t phandle);
void *dt_find_property(void *key, char *propname);
int dt_get_prop_len(void *prop);
void *dt_get_prop_value(void *prop);

/* CPU/platform init */
void cpu_Probe(struct AARCH64_Implementation *);
void cpu_Init(struct AARCH64_Implementation *, struct TagItem *);
void platform_Init(struct AARCH64_Implementation *, struct TagItem *);

void core_SetupIntr(void);
void *KrnAddSysTimerHandler(struct KernelBase *);

/* Tag helpers */
intptr_t krnGetTagData(Tag tagValue, intptr_t defaultVal, const struct TagItem *tagList);
struct TagItem *krnFindTagItem(Tag tagValue, const struct TagItem *tagList);
struct TagItem *krnNextTagItem(const struct TagItem **tagListPtr);

struct KernelBase *getKernelBase(void);

/* Debug */
#ifdef bug
#undef bug
#endif
#ifdef D
#undef D
#endif

#define DEBUG 1

#if DEBUG
#define D(x) x
#define DALLOCMEM(x)
#else
#define D(x)
#define DALLOCMEM(x)
#endif

AROS_LD2(int, KrnBug,
         AROS_LDA(const char *, format, A0),
         AROS_LDA(va_list, args, A1),
         struct KernelBase *, KernelBase, 12, Kernel);

static inline void bug(const char *format, ...)
{
    struct KernelBase *kbase = getKernelBase();
    va_list args;
    va_start(args, format);
    AROS_SLIB_ENTRY(KrnBug, Kernel, 12)(format, args, kbase);
    va_end(args);
}

/*
 * STORE_TASKSTATE — save CPU registers from exception frame to task context.
 * AArch64 exception frame: x0-x28, fp, lr, sp_el0, elr_el1, spsr_el1
 */
#define STORE_TASKSTATE(task, regs)                                             \
    struct ExceptionContext *ctx = task->tc_UnionETask.tc_ETask->et_RegFrame;   \
    int __i;                                                                    \
    for (__i = 0; __i < 29; __i++)                                              \
        ctx->r[__i] = ((uint64_t *)regs)[__i];                                 \
    ctx->fp     = ((uint64_t *)regs)[29];                                       \
    ctx->lr     = ((uint64_t *)regs)[30];                                       \
    ctx->sp     = ((uint64_t *)regs)[31];                                       \
    task->tc_SPReg = (void *)ctx->sp;                                           \
    ctx->pc     = ((uint64_t *)regs)[32];                                       \
    ctx->pstate = ((uint64_t *)regs)[33];                                       \
    if (__aarch64_arosintern.ARMI_Save_VFP_State && ctx->fpuContext)             \
        __aarch64_arosintern.ARMI_Save_VFP_State(ctx->fpuContext);

#define RESTORE_TASKSTATE(task, regs)                                           \
    struct ExceptionContext *ctx = task->tc_UnionETask.tc_ETask->et_RegFrame;   \
    int __i;                                                                    \
    for (__i = 0; __i < 29; __i++)                                              \
        ((uint64_t *)regs)[__i] = ctx->r[__i];                                 \
    ((uint64_t *)regs)[29] = ctx->fp;                                           \
    ((uint64_t *)regs)[30] = ctx->lr;                                           \
    ctx->sp = (intptr_t)task->tc_SPReg;                                         \
    ((uint64_t *)regs)[31] = ctx->sp;                                           \
    ((uint64_t *)regs)[32] = ctx->pc;                                           \
    ((uint64_t *)regs)[33] = ctx->pstate;                                       \
    if (__aarch64_arosintern.ARMI_Restore_VFP_State && ctx->fpuContext)          \
        __aarch64_arosintern.ARMI_Restore_VFP_State(ctx->fpuContext);

#endif /* KERNEL_INTERN_H_ */
