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
 * The asm stub passes the current SP (with saved regs) in x0.
 */
void switch_save_sp(uint64_t sp_val)
{
    struct Task *task = SysBase->ThisTask;

    /* Direct TLS debug */
    {
        tls_t *_dbg_tls;
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(_dbg_tls));
        uart_puts("[Switch] tls=");
        uart_puthex((uint64_t)_dbg_tls);
        uart_puts(" ThisTask=");
        uart_puthex((uint64_t)_dbg_tls->ThisTask);
        uart_puts(" task=");
        uart_puthex((uint64_t)task);
        uart_puts("\n");
    }

    /* Mark as supervisor context so Enable() won't call KrnSti/KrnSchedule */
    tls_t *__tls;
    __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
    __tls->SupervisorCount++;

    if (task)
    {
        task->tc_SPReg = (APTR)sp_val;

        uart_puts("[Switch] save ");
        uart_puts(task->tc_Node.ln_Name ? task->tc_Node.ln_Name : "?");
        uart_puts(" SP=");
        uart_puthex(sp_val);
        uart_puts("\n");

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
        uart_puts("[Dispatch] idle\n");
        tls_t *__tls;
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
        __tls->SupervisorCount--;
        __asm__ volatile("msr daifclr, #2" ::: "memory"); /* unmask IRQ */
        __asm__ volatile("wfi");
        __asm__ volatile("msr daifset, #2" ::: "memory"); /* mask IRQ */
        __tls->SupervisorCount++;
    }

    uart_puts("[Dispatch] -> ");
    uart_puts(task->tc_Node.ln_Name ? task->tc_Node.ln_Name : "?");
    uart_puts(" SP=");
    uart_puthex((uint64_t)task->tc_SPReg);
    uart_puts("\n");

    /* Sync TLS ThisTask with SysBase->ThisTask (set by core_Dispatch) */
    TLS_SET(ThisTask, task);

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
    switch (syscall_num)
    {
    default:
        uart_puts("[Kernel] Unknown syscall: ");
        uart_puthex(syscall_num);
        uart_puts("\n");
        break;
    }
}

void debug_print_eret(uint64_t elr)
{
    uint64_t spsr;
    __asm__ volatile("mrs %0, spsr_el1" : "=r"(spsr));
    uart_puts("[eret] ELR=");
    uart_puthex(elr);
    uart_puts(" SPSR=");
    uart_puthex(spsr);
    uart_puts("\n");
}
