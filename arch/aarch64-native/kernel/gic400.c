/*
    Ported from Circle - A C++ bare metal environment for Raspberry Pi
    Copyright (C) 2019-2023 R. Stange <rsta2@o2online.de>
    Licensed under GPLv3

    Adapted for AROS by The AROS Development Team, 2026

    Desc: GIC-400 interrupt controller driver for BCM2711 (Raspberry Pi 4).
*/

#include <stdint.h>
#include "gic400.h"

struct KernelBase;

/* MMIO helpers */
static inline void wr32(unsigned long addr, uint32_t val)
{
    *(volatile uint32_t *)addr = val;
}

static inline uint32_t rd32(unsigned long addr)
{
    return *(volatile uint32_t *)addr;
}

/* IRQ handler table */
static irq_handler_t irq_handlers[IRQ_LINES];
static void         *irq_params[IRQ_LINES];

/* Stored base addresses for use by ictl_ wrappers */
static unsigned long gicd_base_stored;
static unsigned long gicc_base_stored;

void gic400_Init(unsigned long gicd_base, unsigned long gicc_base)
{
    unsigned int n;

    gicd_base_stored = gicd_base;
    gicc_base_stored = gicc_base;

    /* Clear handler table */
    for (n = 0; n < IRQ_LINES; n++)
    {
        irq_handlers[n] = (irq_handler_t)0;
        irq_params[n] = (void *)0;
    }

    /* Disable distributor */
    wr32(gicd_base + GICD_CTLR, GICD_CTLR_DISABLE);

    /* Disable, clear pending, deactivate all interrupts */
    for (n = 0; n < IRQ_LINES / 32; n++)
    {
        wr32(gicd_base + GICD_ICENABLER + 4 * n, ~0u);
        wr32(gicd_base + GICD_ICPENDR   + 4 * n, ~0u);
        wr32(gicd_base + GICD_ICACTIVER  + 4 * n, ~0u);
    }

    /* Set default priority and target core 0 for all interrupts */
    for (n = 0; n < IRQ_LINES / 4; n++)
    {
        wr32(gicd_base + GICD_IPRIORITYR + 4 * n,
             GICD_IPRIORITYR_DEFAULT | (GICD_IPRIORITYR_DEFAULT << 8) |
             (GICD_IPRIORITYR_DEFAULT << 16) | (GICD_IPRIORITYR_DEFAULT << 24));

        wr32(gicd_base + GICD_ITARGETSR + 4 * n,
             GICD_ITARGETSR_CORE0 | (GICD_ITARGETSR_CORE0 << 8) |
             (GICD_ITARGETSR_CORE0 << 16) | (GICD_ITARGETSR_CORE0 << 24));
    }

    /* All interrupts level-triggered */
    for (n = 0; n < IRQ_LINES / 16; n++)
    {
        wr32(gicd_base + GICD_ICFGR + 4 * n, 0);
    }

    /* Enable distributor */
    wr32(gicd_base + GICD_CTLR, GICD_CTLR_ENABLE);

    /* Initialize CPU interface */
    wr32(gicc_base + GICC_PMR, GICC_PMR_PRIORITY);
    wr32(gicc_base + GICC_CTLR, GICC_CTLR_ENABLE);
}

void gic400_EnableIRQ(unsigned long gicd_base, unsigned int irq)
{
    if (irq < IRQ_LINES)
        wr32(gicd_base + GICD_ISENABLER + 4 * (irq / 32), 1u << (irq % 32));
}

void gic400_DisableIRQ(unsigned long gicd_base, unsigned int irq)
{
    if (irq < IRQ_LINES)
        wr32(gicd_base + GICD_ICENABLER + 4 * (irq / 32), 1u << (irq % 32));
}

void gic400_ConnectIRQ(unsigned int irq, irq_handler_t handler, void *param)
{
    if (irq < IRQ_LINES)
    {
        irq_handlers[irq] = handler;
        irq_params[irq] = param;
    }
}

/*
 * Called from IRQStub in intvecs.S.
 * Reads IAR, dispatches handler, writes EOIR.
 */
void gic400_HandleIRQ(unsigned long gicc_base)
{
    uint32_t iar = rd32(gicc_base + GICC_IAR);
    unsigned int irq = iar & GICC_IAR_INTID_MASK;

    if (irq < IRQ_LINES)
    {
        if (irq_handlers[irq])
            irq_handlers[irq](irq_params[irq]);

        /* End of interrupt */
        wr32(gicc_base + GICC_EOIR, iar);
    }
    /* else: spurious interrupt (ID >= 1020), ignore */
}

/* Return stored GICC base for InterruptHandler */
unsigned long gic400_GetGICCBase(void)
{
    return gicc_base_stored;
}

/* AROS kernel interrupt controller interface */
void ictl_enable_irq(unsigned int irq, struct KernelBase *KernelBase)
{
    (void)KernelBase;
    gic400_EnableIRQ(gicd_base_stored, irq);
}

void ictl_disable_irq(unsigned int irq, struct KernelBase *KernelBase)
{
    (void)KernelBase;
    gic400_DisableIRQ(gicd_base_stored, irq);
}
