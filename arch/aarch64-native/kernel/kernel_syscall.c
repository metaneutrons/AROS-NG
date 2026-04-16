/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: SVC syscall handler + task switch helpers for AArch64.
*/

#include <exec/execbase.h>
#include <exec/alerts.h>
#include <hardware/intbits.h>
#include <aros/aarch64/cpucontext.h>
#include <proto/exec.h>

#include <kernel_base.h>
#include <kernel_scheduler.h>
#include <kernel_syscall.h>
#include "kernel_intern.h"
#include <kernel_intr.h>

#define AROS_NO_ATOMIC_OPERATIONS
#include "exec_platform.h"

/*
 * dispatch_idle — common dispatch loop with idle wait.
 * Calls core_Dispatch() repeatedly; if no task is ready, enables
 * IRQs and executes WFI until one becomes available.
 */
static inline struct Task *dispatch_idle(void)
{
    struct Task *task;
    tls_t *__tls;
    __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));

    while (!(task = core_Dispatch()))
    {
        __tls->SupervisorCount--;
        __asm__ volatile("msr daifclr, #2" ::: "memory");
        __asm__ volatile("wfi");
        __asm__ volatile("msr daifset, #2" ::: "memory");
        __tls->SupervisorCount++;
    }
    return task;
}

/*
 * switch_save_sp — called from asm after saving regs on stack.
 * The asm stub passes the current SP (with saved regs) in x0.
 */
void switch_save_sp(uint64_t sp_val)
{
    struct Task *task = SysBase->ThisTask;

    /* Mark as supervisor context so Enable() won't call KrnSti/KrnSchedule */
    tls_t *__tls;
    __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
    __tls->SupervisorCount++;

    if (task)
    {
        task->tc_SPReg = (APTR)sp_val;

        if ((task->tc_Flags & TF_ETASK) && task->tc_UnionETask.tc_ETask->et_RegFrame)
        {
            struct ExceptionContext *ctx = task->tc_UnionETask.tc_ETask->et_RegFrame;
            ctx->sp = sp_val;
        }

        /* Save TDNestCnt to task before switching */
        task->tc_TDNestCnt = TDNESTCOUNT_GET;

        core_Switch();
    }
}

/*
 * switch_dispatch — called from asm after core_Switch().
 * Picks the next task and returns its saved SP.
 */
uint64_t switch_dispatch(void)
{
    struct Task *task = dispatch_idle();

    /* Sync TLS ThisTask with SysBase->ThisTask (set by core_Dispatch) */
    TLS_SET(ThisTask, task);

    /* Restore task's nesting counts to TLS */
    TDNESTCOUNT_SET(task->tc_TDNestCnt);
    IDNESTCOUNT_SET(task->tc_IDNestCnt);

    /* Leave supervisor context — eret will return to task */
    {
        tls_t *__tls;
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
        __tls->SupervisorCount--;
    }

    /* Return the new task's saved SP */
    return (uint64_t)task->tc_SPReg;
}

/*
 * HandleSyscall — called from SynchronousStub for non-switch SVCs.
 */
void HandleSyscall(uint64_t syscall_num)
{
    (void)syscall_num;
}

/*
 * switch_dispatch_only — called from SC_DISPATCH (RemTask path).
 * Dispatches next task WITHOUT saving current task context.
 */
uint64_t switch_dispatch_only(void)
{
    struct Task *task;

    {
        tls_t *__tls;
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
        __tls->SupervisorCount++;
    }

    task = dispatch_idle();

    TLS_SET(ThisTask, task);
    TDNESTCOUNT_SET(task->tc_TDNestCnt);
    IDNESTCOUNT_SET(task->tc_IDNestCnt);

    {
        tls_t *__tls;
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
        __tls->SupervisorCount--;
    }

    return (uint64_t)task->tc_SPReg;
}

/*
 * irq_RescheduleCheck — called from IRQStub after InterruptHandler.
 * Returns 1 if a task switch is needed, 0 otherwise.
 * Must be called with IRQs masked (we're still in the IRQ handler).
 */
int irq_RescheduleCheck(void)
{
    /* Process pending soft interrupts */
    if (SysBase->SysFlags & SFF_SoftInt)
        core_Cause(INTB_SOFTINT, 1L << INTB_SOFTINT);

    /*
     * Only attempt preemptive switch if we interrupted a running task,
     * not kernel code (idle loop, switch path, etc).
     */
    {
        struct Task *t = SysBase->ThisTask;
        if (!t || t->tc_State != TS_RUN)
            return 0;
    }

    /* If task switching is enabled, check if a switch is needed */
    if (TDNESTCOUNT_GET < 0)
    {
        if (FLAG_SCHEDSWITCH_ISSET || 
            (!IsListEmpty(&SysBase->TaskReady) && 
             ((struct Task *)SysBase->TaskReady.lh_Head)->tc_Node.ln_Pri > 
             SysBase->ThisTask->tc_Node.ln_Pri))
        {
            if (core_Schedule())
                return 1;
        }
    }
    return 0;
}
