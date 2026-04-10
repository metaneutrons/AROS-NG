/*
    Ported from Circle - A C++ bare metal environment for Raspberry Pi
    Copyright (C) 2015-2023 R. Stange <rsta2@o2online.de>
    Licensed under GPLv3

    Adapted for AROS by The AROS Development Team, 2026

    Desc: BCM2711 (Raspberry Pi 4) platform probe and serial output.
*/

#include <stdint.h>
#include "kernel_intern.h"

/*
 * BCM2711 peripheral addresses from kernel_intern.h (SSOT).
 */
#define BCM2711_PL011_BASE      (BCM2711_PERIBASE + 0x201000)

/* PL011 register offsets */
#define PL011_DR                0x00
#define PL011_FR                0x18
#define PL011_FR_TXFF           (1 << 5)

static inline void wr32(unsigned long addr, uint32_t val)
{
    *(volatile uint32_t *)addr = val;
}

static inline uint32_t rd32(unsigned long addr)
{
    return *(volatile uint32_t *)addr;
}

/*
 * Serial output via PL011.
 * Assumes UART is already initialized by the bootstrap (serialdebug.c).
 */
static void bcm2711_ser_putc(uint8_t chr)
{
    int timeout;
    for (timeout = 100000; timeout > 0; timeout--)
    {
        if (!(rd32(BCM2711_PL011_BASE + PL011_FR) & PL011_FR_TXFF))
            break;
    }

    if (chr == '\n')
    {
        wr32(BCM2711_PL011_BASE + PL011_DR, '\r');
        for (timeout = 100000; timeout > 0; timeout--)
        {
            if (!(rd32(BCM2711_PL011_BASE + PL011_FR) & PL011_FR_TXFF))
                break;
        }
    }
    wr32(BCM2711_PL011_BASE + PL011_DR, chr);
}

static int bcm2711_ser_getc(void)
{
    if (!(rd32(BCM2711_PL011_BASE + PL011_FR) & (1 << 4)))  /* RXFE */
        return (int)rd32(BCM2711_PL011_BASE + PL011_DR);
    return -1;
}

/*
 * Platform probe for BCM2711 (Raspberry Pi 4).
 *
 * Detection: reads MIDR_EL1 for Cortex-A72 (part 0xD08).
 * In the full AROS build, this will also check the device tree
 * compatible string for "brcm,bcm2711".
 */
int bcm2711_probe(struct AARCH64_Implementation *impl, void *bootmsg)
{
    uint64_t midr;
    __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));

    uint32_t part = (midr >> 4) & 0xFFF;

    /* Cortex-A72 = 0xD08 (BCM2711 / Pi 4) */
    if (part != 0xD08)
        return 0;

    impl->ARMI_Family = 8;
    impl->ARMI_Platform = 0x2711;
    impl->ARMI_PeripheralBase = (void *)BCM2711_PERIBASE;

    impl->ARMI_SerPutChar = bcm2711_ser_putc;
    impl->ARMI_SerGetChar = bcm2711_ser_getc;

    /* IRQ, timer, SMP init will be added in Task 7 */

    return 1;   /* probe succeeded */
}
