/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: ARM Generic Timer driver for AArch64.
          Uses the non-secure physical timer (CNTP) to generate
          periodic 50Hz interrupts for the AROS VBlank heartbeat.

    Ported from Circle timer.cpp (GPLv3) by R. Stange.
*/

#include <hardware/intbits.h>
#include <exec/execbase.h>

#include "gic400.h"
#include "kernel_cpu.h"
#include "kernel_intern.h"
#include "kernel_intr.h"

/* Timer tick rate — 50Hz matches AROS VBlank convention */
#define TIMER_HZ    50

/* State */
static uint64_t timer_interval;     /* ticks per TIMER_HZ period    */

/* Forward declarations for early-boot UART (in kernel_cstart.c) */
extern void uart_puts(const char *s);
extern void uart_puthex(uint64_t val);

/* System register accessors */
static inline uint64_t read_cntfrq(void)
{
    uint64_t val;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(val));
    return val;
}

static inline uint64_t read_cntpct(void)
{
    uint64_t val;
    __asm__ volatile("mrs %0, cntpct_el0" : "=r"(val));
    return val;
}

static inline void write_cntp_cval(uint64_t val)
{
    __asm__ volatile("msr cntp_cval_el0, %0" : : "r"(val));
}

static inline void write_cntp_ctl(uint64_t val)
{
    __asm__ volatile("msr cntp_ctl_el0, %0" : : "r"(val));
}

static volatile uint64_t timer_tick_count;

/*
 * Timer IRQ handler — called from GIC dispatch at IRQ 30 (PPI 14).
 * Schedules next tick and signals the Exec VBlank server.
 */
static void timer_IRQHandler(void *param)
{
    (void)param;

    /* Schedule next interrupt */
    write_cntp_cval(read_cntpct() + timer_interval);

    timer_tick_count++;

    /* Signal the Exec VBlankServer */
    if (SysBase)
        core_Cause(INTB_VERTB, 1L << INTB_VERTB);
}

uint64_t timer_GetTickCount(void)
{
    return timer_tick_count;
}

/*
 * Initialize the ARM Generic Timer.
 * Must be called after gic400_Init().
 */
void timer_Init(unsigned long gicd_base)
{
    uint64_t freq = read_cntfrq();
    timer_interval = freq / TIMER_HZ;

    uart_puts("[Kernel] Timer: ");
    uart_puthex(freq);
    uart_puts(" Hz, interval=");
    uart_puthex(timer_interval);
    uart_puts(" (");
    uart_puthex(TIMER_HZ);
    uart_puts(" Hz)\n");

    /* Disable timer while configuring */
    write_cntp_ctl(0);

    /* Set first compare value */
    write_cntp_cval(read_cntpct() + timer_interval);

    /* Connect IRQ handler */
    gic400_ConnectIRQ(ARM_IRQ_TIMER_CNTPNS, timer_IRQHandler, (void *)0);

    /* Enable timer IRQ in GIC */
    gic400_EnableIRQ(gicd_base, ARM_IRQ_TIMER_CNTPNS);

    /* Enable timer, unmask interrupt */
    write_cntp_ctl(1);
}
