/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: krnPutC — serial debug output for AArch64 kernel.
*/

#include <aros/kernel.h>
#include <inttypes.h>

#include <kernel_base.h>
#include <kernel_debug.h>

/* BCM2711 PL011 UART0 registers */
#define PL011_BASE  0xFE201000UL
#define PL011_DR    0x00
#define PL011_FR    0x18
#define PL011_FR_TXFF (1 << 5)

static inline void uart_wait(void)
{
    while (*(volatile uint32_t *)(PL011_BASE + PL011_FR) & PL011_FR_TXFF)
        ;
}

int krnPutC(int chr, struct KernelBase *KernelBase)
{
    if (chr == '\n')
    {
        uart_wait();
        *(volatile uint32_t *)(PL011_BASE + PL011_DR) = '\r';
    }
    uart_wait();
    *(volatile uint32_t *)(PL011_BASE + PL011_DR) = (uint32_t)chr;
    return 1;
}
