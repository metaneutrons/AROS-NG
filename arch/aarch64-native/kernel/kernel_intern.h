/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel internal definitions
*/

#ifndef KERNEL_INTERN_H
#define KERNEL_INTERN_H

#include <inttypes.h>
#include <exec/lists.h>
#include <exec/execbase.h>
#include <exec/memory.h>
#include <utility/tagitem.h>
#include <aros/aarch64/cpucontext.h>

/*
 * AARCH64_Implementation — hardware abstraction for SoC-specific functions.
 * Modeled after ARM_Implementation in arch/arm-native/kernel/kernel_arm.h.
 */
struct AARCH64_Implementation
{
    IPTR                ARMI_Family;
    IPTR                ARMI_Platform;
    APTR                ARMI_PeripheralBase;
    uint32_t            ARMI_AffinityMask;

    void  (*ARMI_Init)(APTR, APTR);
    void  (*ARMI_InitCore)(APTR, APTR);
    void  (*ARMI_SendIPI)(uint32_t, uint32_t, uint32_t);
    APTR  (*ARMI_InitTimer)(APTR);
    void  (*ARMI_Delay)(int);
    unsigned int (*ARMI_GetTime)(void);
    void  (*ARMI_PutChar)(int);
    void  (*ARMI_SerPutChar)(uint8_t);
    int   (*ARMI_SerGetChar)(void);
    void  (*ARMI_IRQInit)(void);
    void  (*ARMI_IRQEnable)(int);
    void  (*ARMI_IRQDisable)(int);
    void  (*ARMI_IRQProcess)(void);
    void  (*ARMI_LED_Toggle)(int, int);
    void  (*ARMI_Save_VFP_State)(void *);
    void  (*ARMI_Restore_VFP_State)(void *);
    void  (*ARMI_Init_VFP_State)(void *);
};

extern struct AARCH64_Implementation __aarch64_arosintern;

#define ARM_LED_ON          1
#define ARM_LED_OFF         0
#define ARM_LED_POWER       0
#define ARM_LED_ACTIVITY    1

/* Platform init */
void platform_Init(struct AARCH64_Implementation *impl, struct TagItem *msg);

/* BCM2711 (Pi 4) hardware addresses */
#define BCM2711_PERIBASE        0xFE000000UL
#define BCM2711_GICD_BASE       0xFF841000UL
#define BCM2711_GICC_BASE       0xFF842000UL

/* Tag helpers (from rom/kernel) */
intptr_t krnGetTagData(Tag tagValue, intptr_t defaultVal, const struct TagItem *tagList);
struct TagItem *krnFindTagItem(Tag tagValue, const struct TagItem *tagList);
struct TagItem *krnNextTagItem(const struct TagItem **tagListPtr);

/* Debug output */
#ifdef bug
#undef bug
#endif
#ifdef D
#undef D
#endif
#define DEBUG 1
#if DEBUG
#define D(x) x
#else
#define D(x)
#endif

void kprintf(const char *format, ...);
#define bug kprintf

/*
 * STORE_TASKSTATE — save CPU registers from exception frame to task context.
 *
 * AArch64 exception frame layout (from intvecs.S):
 *   regs[0..28] = x0-x28
 *   regs[29]    = x29 (fp)
 *   regs[30]    = x30 (lr)
 *   regs[31]    = sp_el0
 *   regs[32]    = elr_el1 (pc)
 *   regs[33]    = spsr_el1 (pstate)
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

#endif /* KERNEL_INTERN_H */
