/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: BCM2711 (Raspberry Pi 4) platform probe and serial output.

    Peripheral addresses from BCM2711 ARM Peripherals datasheet §1.2.
    CPU identification from ARM ARM D13.2.89 (MIDR_EL1).
    PL011 register offsets from ARM PL011 TRM (DDI 0183).
    Platform probe pattern from arch/arm-native/kernel/platform_init.c (AROS).
*/

#include <stdint.h>
#include "kernel_intern.h"

/*
 * BCM2711 peripheral addresses from kernel_intern.h (SSOT).
 */
#define BCM2711_PL011_BASE      (BCM2711_PERIBASE + 0x201000)

/* PL011 register offsets — DDI 0183 §3.2 */
#define PL011_DR                0x00
#define PL011_FR                0x18
#define PL011_FR_TXFF           (1 << 5)
#define PL011_FR_RXFE           (1 << 4)

static inline void mmio_wr(unsigned long addr, uint32_t val)
{
    *(volatile uint32_t *)addr = val;
}

static inline uint32_t mmio_rd(unsigned long addr)
{
    return *(volatile uint32_t *)addr;
}

/* Serial output — assumes UART already initialized by bootstrap */
static void bcm2711_ser_putc(uint8_t chr)
{
    int timeout = 100000;
    while (timeout-- > 0 && (mmio_rd(BCM2711_PL011_BASE + PL011_FR) & PL011_FR_TXFF))
        ;
    if (chr == '\n')
    {
        mmio_wr(BCM2711_PL011_BASE + PL011_DR, '\r');
        timeout = 100000;
        while (timeout-- > 0 && (mmio_rd(BCM2711_PL011_BASE + PL011_FR) & PL011_FR_TXFF))
            ;
    }
    mmio_wr(BCM2711_PL011_BASE + PL011_DR, chr);
}

static int bcm2711_ser_getc(void)
{
    if (!(mmio_rd(BCM2711_PL011_BASE + PL011_FR) & PL011_FR_RXFE))
        return (int)mmio_rd(BCM2711_PL011_BASE + PL011_DR);
    return -1;
}

/*
 * bcm2711_probe — detect BCM2711 SoC via MIDR_EL1.
 *
 * Cortex-A72 part number = 0xD08 (ARM ARM D13.2.89).
 * In the full AROS build, this will also check the device tree
 * compatible string for "brcm,bcm2711".
 * Fills the AARCH64_Implementation struct for kernel use.
 */
int bcm2711_probe(struct AARCH64_Implementation *impl, void *bootmsg)
{
    uint64_t midr;
    __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));

    if (((midr >> 4) & 0xFFF) != 0xD08)
        return 0;

    impl->ARMI_Family        = 8;
    impl->ARMI_Platform      = 0x2711;
    impl->ARMI_PeripheralBase = (void *)BCM2711_PERIBASE;
    impl->ARMI_SerPutChar    = bcm2711_ser_putc;
    impl->ARMI_SerGetChar    = bcm2711_ser_getc;

    return 1;
}
