/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: SVC syscall handler + task switch helpers for AArch64.
*/

#include <exec/execbase.h>
#include <exec/alerts.h>
#include <aros/aarch64/cpucontext.h>
#include <proto/exec.h>

#include <kernel_base.h>
#include <kernel_scheduler.h>
#include <kernel_syscall.h>
#include "kernel_intern.h"

#define AROS_NO_ATOMIC_OPERATIONS
#include "exec_platform.h"

extern void uart_puts(const char *s);
extern void uart_puthex(uint64_t val);

/*
 * switch_save_sp — called from asm after saving regs on stack.
 * Saves the current SP into the current task's context and calls core_Switch().
 */
void switch_save_sp(void)
{
    struct Task *task = GET_THIS_TASK;

    if (task)
    {
        register uint64_t sp_val __asm__("sp");
        task->tc_SPReg = (APTR)sp_val;

        if ((task->tc_Flags & TF_ETASK) && task->tc_UnionETask.tc_ETask->et_RegFrame)
        {
            struct ExceptionContext *ctx = task->tc_UnionETask.tc_ETask->et_RegFrame;
            ctx->sp = sp_val;
        }

        core_Switch();
    }
}

/*
 * switch_dispatch — called from asm after core_Switch().
 * Picks the next task and returns its saved SP.
 */
uint64_t switch_dispatch(void)
{
    struct Task *task;

    while (!(task = core_Dispatch()))
    {
        /* No ready tasks — enable interrupts and idle */
        __asm__ volatile("msr daifclr, #2" ::: "memory"); /* unmask IRQ */
        __asm__ volatile("wfi");
        __asm__ volatile("msr daifset, #2" ::: "memory"); /* mask IRQ */
    }

    /* Return the new task's saved SP */
    return (uint64_t)task->tc_SPReg;
}

/*
 * HandleSyscall — called from SynchronousStub for non-switch SVCs.
 */
void HandleSyscall(uint64_t syscall_num)
{
    switch (syscall_num)
    {
    default:
        uart_puts("[Kernel] Unknown syscall: ");
        uart_puthex(syscall_num);
        uart_puts("\n");
        break;
    }
}
