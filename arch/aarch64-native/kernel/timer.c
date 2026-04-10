/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: ARM Generic Timer driver for AArch64.
          Uses the non-secure physical timer (CNTP) to generate
          periodic interrupts for the AROS VBlank heartbeat.

    Timer registers used:
        CNTFRQ_EL0  — timer frequency (read-only, set by firmware)
        CNTPCT_EL0  — current counter value
        CNTP_CVAL_EL0 — compare value (fires IRQ when counter >= CVAL)
        CNTP_CTL_EL0  — control (bit 0 = enable, bit 1 = mask, bit 2 = status)
*/

#include <stdint.h>
#include "gic400.h"

/* Timer tick rate — 50Hz matches AROS VBlank convention */
#define TIMER_HZ    50

/* State */
static uint64_t timer_freq;         /* CNTFRQ_EL0 value             */
static uint64_t timer_interval;     /* ticks per TIMER_HZ period    */
static volatile uint64_t timer_tick_count;  /* total ticks since boot */

/* Stored GIC bases for IRQ enable */
static unsigned long stored_gicd_base;

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

/*
 * Timer IRQ handler — called from GIC dispatch at IRQ 30 (PPI 14).
 *
 * Sets next compare value and increments tick counter.
 */
static void timer_IRQHandler(void *param)
{
    (void)param;

    /* Schedule next interrupt */
    uint64_t now = read_cntpct();
    write_cntp_cval(now + timer_interval);

    timer_tick_count++;
}

/*
 * Initialize the ARM Generic Timer.
 * Must be called after gic400_Init().
 */
void timer_Init(unsigned long gicd_base)
{
    stored_gicd_base = gicd_base;

    /* Read timer frequency from firmware-configured register */
    timer_freq = read_cntfrq();
    timer_interval = timer_freq / TIMER_HZ;
    timer_tick_count = 0;

    /* Disable timer while configuring */
    write_cntp_ctl(0);

    /* Set first compare value */
    uint64_t now = read_cntpct();
    write_cntp_cval(now + timer_interval);

    /* Connect IRQ handler */
    gic400_ConnectIRQ(ARM_IRQ_TIMER_CNTPNS, timer_IRQHandler, (void *)0);

    /* Enable timer IRQ in GIC */
    gic400_EnableIRQ(gicd_base, ARM_IRQ_TIMER_CNTPNS);

    /* Enable timer, unmask interrupt */
    write_cntp_ctl(1);
}

/*
 * Get current tick count (incremented at TIMER_HZ rate).
 */
uint64_t timer_GetTickCount(void)
{
    return timer_tick_count;
}
