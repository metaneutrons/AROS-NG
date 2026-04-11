/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Machine-specific definitions for AArch64 Raspberry Pi 4.
*/

#ifndef KERNEL_ARCH_H
#define KERNEL_ARCH_H

#include "kernel_cpu.h"
#include "gic400.h"

/* Number of IRQs — GIC-400 supports 256 lines */
#define IRQ_COUNT   IRQ_LINES

/* Interrupt controller functions used by kernel_base.h */
void ictl_enable_irq(unsigned int irq, struct KernelBase *KernelBase);
void ictl_disable_irq(unsigned int irq, struct KernelBase *KernelBase);

#endif /* KERNEL_ARCH_H */
