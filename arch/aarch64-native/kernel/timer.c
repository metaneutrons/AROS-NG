/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: ARM Generic Timer driver for AArch64.
          Generates periodic 50Hz interrupts via the non-secure physical
          timer (CNTP) for the AROS VBlank heartbeat.

    System register usage derived from:
    - ARM Architecture Reference Manual for A-profile (DDI 0487), Section D11.2
    - CNTP_CTL_EL0, CNTP_CVAL_EL0, CNTFRQ_EL0, CNTPCT_EL0
    - Timer PPI assignment: GIC Architecture Spec §1.4.3 (INTID 30 = PPI 14)
*/

#include <hardware/intbits.h>
#include <exec/execbase.h>

#include "gic400.h"
#include "kernel_cpu.h"
#include "kernel_intern.h"
#include "kernel_intr.h"

#define TIMER_HZ    50

static uint64_t tick_interval;

extern void uart_puts(const char *s);
extern void uart_puthex(uint64_t val);

/*
 * System register accessors.
 * Ref: ARM ARM D11.2.3 (CNTFRQ_EL0), D11.2.4 (CNTPCT_EL0),
 *      D11.2.1 (CNTP_CTL_EL0), D11.2.2 (CNTP_CVAL_EL0)
 */
static inline uint64_t rd_cntfrq(void)
{
    uint64_t v; __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(v)); return v;
}

static inline uint64_t rd_cntpct(void)
{
    uint64_t v; __asm__ volatile("mrs %0, cntpct_el0" : "=r"(v)); return v;
}

static inline void wr_cntp_cval(uint64_t v)
{
    __asm__ volatile("msr cntp_cval_el0, %0" : : "r"(v));
}

static inline void wr_cntp_ctl(uint64_t v)
{
    __asm__ volatile("msr cntp_ctl_el0, %0" : : "r"(v));
}

static volatile uint64_t timer_tick_count;

/*
 * Timer IRQ handler — called from GIC dispatch at INTID 30 (PPI 14).
 * Programs next compare value and signals the Exec VBlank server.
 */
static void timer_irq(void *param)
{
    (void)param;
    wr_cntp_cval(rd_cntpct() + tick_interval);
    timer_tick_count++;
    if (SysBase)
        core_Cause(INTB_VERTB, 1L << INTB_VERTB);
}

uint64_t timer_GetTickCount(void)
{
    return timer_tick_count;
}

/*
 * timer_Init — configure the ARM Generic Timer for periodic interrupts.
 *
 * Sequence per ARM ARM D11.2:
 *   1. Read counter frequency from CNTFRQ_EL0
 *   2. Compute interval for desired tick rate
 *   3. Disable timer (CNTP_CTL_EL0 = 0)
 *   4. Set first compare value (CNTP_CVAL_EL0)
 *   5. Register and enable IRQ in GIC
 *   6. Enable timer (CNTP_CTL_EL0.ENABLE = 1, IMASK = 0)
 *
 * Must be called after gic400_Init().
 */
void timer_Init(unsigned long gicd_base)
{
    uint64_t freq = rd_cntfrq();
    tick_interval = freq / TIMER_HZ;

    uart_puts("[Kernel] Timer: ");
    uart_puthex(freq);
    uart_puts(" Hz, interval=");
    uart_puthex(tick_interval);
    uart_puts(" (");
    uart_puthex(TIMER_HZ);
    uart_puts(" Hz)\n");

    wr_cntp_ctl(0);
    wr_cntp_cval(rd_cntpct() + tick_interval);
    gic400_ConnectIRQ(ARM_IRQ_TIMER_CNTPNS, timer_irq, (void *)0);
    gic400_EnableIRQ(gicd_base, ARM_IRQ_TIMER_CNTPNS);
    wr_cntp_ctl(1);  /* ENABLE=1, IMASK=0 */
}
