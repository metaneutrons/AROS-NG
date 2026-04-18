/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: GIC-400 register definitions for BCM2711 (Raspberry Pi 4).

    Hardware register offsets and bit fields derived from:
    - ARM GIC-400 Generic Interrupt Controller TRM (DDI 0471B), Tables 4-1..4-6
    - ARM GIC Architecture Specification v2.0 (IHI 0048B)
*/

#ifndef GIC400_H
#define GIC400_H

#include <stdint.h>

/*
 * Interrupt line count.
 * GIC-400 on BCM2711 implements 256 interrupt IDs:
 *   0..15   SGI  (Software Generated Interrupts)
 *   16..31  PPI  (Private Peripheral Interrupts)
 *   32..255 SPI  (Shared Peripheral Interrupts)
 *
 * Ref: GIC Architecture Spec §1.3
 */
#define IRQ_LINES               256

#define GIC_SGI(n)              (n)
#define GIC_PPI(n)              (16 + (n))
#define GIC_SPI(n)              (32 + (n))

/* Non-secure physical timer PPI — GIC Architecture Spec §1.4.3 */
#define ARM_IRQ_TIMER_CNTPNS    GIC_PPI(14)     /* INTID 30 */

/*
 * GIC Distributor registers (offsets from GICD base).
 * Ref: GIC-400 TRM §4.1, Table 4-1
 */
#define GICD_CTLR               0x000
#define GICD_CTLR_DISABLE       0
#define GICD_CTLR_ENABLE        1

#define GICD_ISENABLER          0x100   /* Set-Enable      (IRQ/32 banks) */
#define GICD_ICENABLER          0x180   /* Clear-Enable    (IRQ/32 banks) */
#define GICD_ISPENDR            0x200   /* Set-Pending     (IRQ/32 banks) */
#define GICD_ICPENDR            0x280   /* Clear-Pending   (IRQ/32 banks) */
#define GICD_ISACTIVER          0x300   /* Set-Active      (IRQ/32 banks) */
#define GICD_ICACTIVER          0x380   /* Clear-Active    (IRQ/32 banks) */
#define GICD_IPRIORITYR         0x400   /* Priority        (IRQ/4 banks)  */
#define GICD_ITARGETSR          0x800   /* CPU Targets     (IRQ/4 banks)  */
#define GICD_ICFGR              0xC00   /* Configuration   (IRQ/16 banks) */

#define GICD_IPRIORITYR_DEFAULT 0xA0    /* Default priority level */
#define GICD_ITARGETSR_CORE0    0x01    /* Route to CPU 0 */

/*
 * GIC CPU Interface registers (offsets from GICC base).
 * Ref: GIC-400 TRM §4.1, Table 4-6
 */
#define GICC_CTLR               0x000
#define GICC_CTLR_DISABLE       0
#define GICC_CTLR_ENABLE        1
#define GICC_PMR                0x004   /* Priority Mask */
#define GICC_PMR_PRIORITY       0xF0    /* Accept all but lowest 16 levels */
#define GICC_IAR                0x00C   /* Interrupt Acknowledge */
#define GICC_IAR_INTID_MASK     0x3FF   /* INTID field [9:0] */
#define GICC_EOIR               0x010   /* End of Interrupt */

/* IRQ handler callback type */
typedef void (*irq_handler_t)(void *param);

/* API */
void gic400_Init(unsigned long gicd_base, unsigned long gicc_base);
void gic400_EnableIRQ(unsigned long gicd_base, unsigned int irq);
void gic400_DisableIRQ(unsigned long gicd_base, unsigned int irq);
void gic400_ConnectIRQ(unsigned int irq, irq_handler_t handler, void *param);
void gic400_HandleIRQ(unsigned long gicc_base);
unsigned long gic400_GetGICCBase(void);

#endif /* GIC400_H */
