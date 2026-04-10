/*
    Ported from Circle - A C++ bare metal environment for Raspberry Pi
    Copyright (C) 2019-2023 R. Stange <rsta2@o2online.de>
    Licensed under GPLv3

    Adapted for AROS by The AROS Development Team, 2026

    Desc: GIC-400 register definitions for BCM2711 (Raspberry Pi 4).
*/

#ifndef GIC400_H
#define GIC400_H

#include <stdint.h>

/*
 * IRQ line count.
 * BCM2711 GIC-400 supports 256 interrupt lines:
 *   0-15:   SGI (Software Generated Interrupts)
 *   16-31:  PPI (Private Peripheral Interrupts)
 *   32-255: SPI (Shared Peripheral Interrupts)
 */
#define IRQ_LINES               256

/* GIC interrupt number macros */
#define GIC_SGI(n)              (n)             /* 0-15  */
#define GIC_PPI(n)              (16 + (n))      /* 16-31 */
#define GIC_SPI(n)              (32 + (n))      /* 32+   */

/* ARM Generic Timer: non-secure physical timer PPI */
#define ARM_IRQ_TIMER_CNTPNS    GIC_PPI(14)     /* IRQ 30 */

/* GIC Distributor register offsets (from GICD base) */
#define GICD_CTLR               0x000
#define GICD_CTLR_DISABLE       (0 << 0)
#define GICD_CTLR_ENABLE        (1 << 0)

#define GICD_ISENABLER          0x100
#define GICD_ICENABLER          0x180
#define GICD_ISPENDR            0x200
#define GICD_ICPENDR            0x280
#define GICD_ISACTIVER          0x300
#define GICD_ICACTIVER          0x380
#define GICD_IPRIORITYR         0x400
#define GICD_IPRIORITYR_DEFAULT 0xA0
#define GICD_ITARGETSR          0x800
#define GICD_ITARGETSR_CORE0    (1 << 0)
#define GICD_ICFGR              0xC00

/* GIC CPU Interface register offsets (from GICC base) */
#define GICC_CTLR               0x000
#define GICC_CTLR_DISABLE       (0 << 0)
#define GICC_CTLR_ENABLE        (1 << 0)
#define GICC_PMR                0x004
#define GICC_PMR_PRIORITY       0xF0
#define GICC_IAR                0x00C
#define GICC_IAR_INTID_MASK     0x3FF
#define GICC_EOIR               0x010

/* IRQ handler function type */
typedef void (*irq_handler_t)(void *param);

/* API */
void gic400_Init(unsigned long gicd_base, unsigned long gicc_base);
void gic400_EnableIRQ(unsigned long gicd_base, unsigned int irq);
void gic400_DisableIRQ(unsigned long gicd_base, unsigned int irq);
void gic400_ConnectIRQ(unsigned int irq, irq_handler_t handler, void *param);
void gic400_HandleIRQ(unsigned long gicc_base);

#endif /* GIC400_H */
