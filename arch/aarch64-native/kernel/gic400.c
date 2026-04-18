/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: GIC-400 interrupt controller driver for BCM2711 (Raspberry Pi 4).

    Initialization and interrupt handling sequences derived from:
    - ARM GIC-400 TRM (DDI 0471B), Section 4.3 "Initialization"
    - ARM GIC Architecture Specification v2.0 (IHI 0048B), Section 3.4
    - BCM2711 ARM Peripherals datasheet (GICD 0xFF841000, GICC 0xFF842000)
*/

#include <stdint.h>
#include "gic400.h"

struct KernelBase;
extern struct KernelBase *getKernelBase(void);
extern void krnRunIRQHandlers(struct KernelBase *, uint8_t irq);

static inline void mmio_wr(unsigned long addr, uint32_t val)
{
    *(volatile uint32_t *)addr = val;
}

static inline uint32_t mmio_rd(unsigned long addr)
{
    return *(volatile uint32_t *)addr;
}

static irq_handler_t irq_table[IRQ_LINES];
static void         *irq_param[IRQ_LINES];
static unsigned long stored_gicd;
static unsigned long stored_gicc;

/*
 * gic400_Init — full GIC-400 initialization.
 *
 * Sequence per GIC-400 TRM §4.3:
 *   1. Disable distributor (GICD_CTLR = 0)
 *   2. Clear all enable, pending, and active bits
 *   3. Set default priority for all INTIDs
 *   4. Route all SPIs to CPU 0
 *   5. Configure all SPIs as level-triggered
 *   6. Enable distributor (GICD_CTLR = 1)
 *   7. Set CPU interface priority mask (GICC_PMR)
 *   8. Enable CPU interface (GICC_CTLR = 1)
 */
void gic400_Init(unsigned long gicd_base, unsigned long gicc_base)
{
    unsigned int i;

    stored_gicd = gicd_base;
    stored_gicc = gicc_base;

    for (i = 0; i < IRQ_LINES; i++)
    {
        irq_table[i] = (irq_handler_t)0;
        irq_param[i] = (void *)0;
    }

    /* Step 1: disable distributor */
    mmio_wr(gicd_base + GICD_CTLR, GICD_CTLR_DISABLE);

    /* Step 2: clear enable, pending, active for all 256 IRQs (8 banks of 32) */
    for (i = 0; i < IRQ_LINES / 32; i++)
    {
        mmio_wr(gicd_base + GICD_ICENABLER + 4 * i, ~0u);
        mmio_wr(gicd_base + GICD_ICPENDR   + 4 * i, ~0u);
        mmio_wr(gicd_base + GICD_ICACTIVER  + 4 * i, ~0u);
    }

    /* Step 3+4: set priority and CPU target for all 256 IRQs (64 banks of 4) */
    for (i = 0; i < IRQ_LINES / 4; i++)
    {
        uint32_t prio = GICD_IPRIORITYR_DEFAULT;
        mmio_wr(gicd_base + GICD_IPRIORITYR + 4 * i,
                prio | (prio << 8) | (prio << 16) | (prio << 24));

        uint32_t tgt = GICD_ITARGETSR_CORE0;
        mmio_wr(gicd_base + GICD_ITARGETSR + 4 * i,
                tgt | (tgt << 8) | (tgt << 16) | (tgt << 24));
    }

    /* Step 5: all IRQs level-triggered (ICFGR = 0) */
    for (i = 0; i < IRQ_LINES / 16; i++)
        mmio_wr(gicd_base + GICD_ICFGR + 4 * i, 0);

    /* Step 6: enable distributor */
    mmio_wr(gicd_base + GICD_CTLR, GICD_CTLR_ENABLE);

    /* Step 7+8: configure and enable CPU interface */
    mmio_wr(gicc_base + GICC_PMR, GICC_PMR_PRIORITY);
    mmio_wr(gicc_base + GICC_CTLR, GICC_CTLR_ENABLE);
}

void gic400_EnableIRQ(unsigned long gicd_base, unsigned int irq)
{
    if (irq < IRQ_LINES)
        mmio_wr(gicd_base + GICD_ISENABLER + 4 * (irq / 32), 1u << (irq % 32));
}

void gic400_DisableIRQ(unsigned long gicd_base, unsigned int irq)
{
    if (irq < IRQ_LINES)
        mmio_wr(gicd_base + GICD_ICENABLER + 4 * (irq / 32), 1u << (irq % 32));
}

void gic400_ConnectIRQ(unsigned int irq, irq_handler_t handler, void *param)
{
    if (irq < IRQ_LINES)
    {
        irq_table[irq] = handler;
        irq_param[irq] = param;
    }
}

/*
 * gic400_HandleIRQ — acknowledge, dispatch, and complete an interrupt.
 *
 * Flow per GIC Architecture Spec §3.4:
 *   1. Read GICC_IAR to acknowledge and get INTID
 *   2. If INTID >= 1020, it's spurious — do NOT write EOIR
 *   3. Otherwise dispatch handler, then write GICC_EOIR
 */
void gic400_HandleIRQ(unsigned long gicc_base)
{
    uint32_t iar = mmio_rd(gicc_base + GICC_IAR);
    unsigned int irq = iar & GICC_IAR_INTID_MASK;

    if (irq >= 1020)
        return; /* spurious */

    if (irq < IRQ_LINES)
    {
        if (irq_table[irq])
            irq_table[irq](irq_param[irq]);

        if (irq < 240)
            krnRunIRQHandlers(getKernelBase(), irq);
    }

    mmio_wr(gicc_base + GICC_EOIR, iar);
}

unsigned long gic400_GetGICCBase(void)
{
    return stored_gicc;
}

/* AROS kernel interrupt controller wrappers */
void ictl_enable_irq(unsigned int irq, struct KernelBase *KernelBase)
{
    (void)KernelBase;
    gic400_EnableIRQ(stored_gicd, irq);
}

void ictl_disable_irq(unsigned int irq, struct KernelBase *KernelBase)
{
    (void)KernelBase;
    gic400_DisableIRQ(stored_gicd, irq);
}
