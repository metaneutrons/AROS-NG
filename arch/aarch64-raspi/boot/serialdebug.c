/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: PL011 UART serial debug output for AArch64 Raspberry Pi bootstrap.
          Init sequence based on Circle serial.cpp (GPLv3, R. Stange).
    Lang: english
*/

#include <stdint.h>
#include <stdarg.h>

#include "serialdebug.h"

/*
 * BCM2711 (Pi 4) peripheral base.
 * DECISION: Hardcoded for bootstrap. The kernel will use device-tree
 * based detection via the HAL. Date: 2026-04-10
 */
#define BCM2711_PERIBASE    0xFE000000UL
#define PL011_BASE          (BCM2711_PERIBASE + 0x201000)

/* PL011 register offsets */
#define PL011_DR            0x00
#define PL011_FR            0x18
#define PL011_IBRD          0x24
#define PL011_FBRD          0x28
#define PL011_LCRH          0x2C
#define PL011_CR            0x30
#define PL011_IMSC          0x38
#define PL011_ICR           0x44

/* Flag register bits */
#define PL011_FR_TXFF       (1 << 5)
#define PL011_FR_BUSY       (1 << 3)

/* Line control register bits */
#define PL011_LCRH_WLEN8    (3 << 5)
#define PL011_LCRH_FEN      (1 << 4)

/* Control register bits */
#define PL011_CR_UARTEN     (1 << 0)
#define PL011_CR_TXE        (1 << 8)
#define PL011_CR_RXE        (1 << 9)

static inline void mmio_write(unsigned long addr, uint32_t val)
{
    *(volatile uint32_t *)addr = val;
}

static inline uint32_t mmio_read(unsigned long addr)
{
    return *(volatile uint32_t *)addr;
}

void serInit(void)
{
    /* Disable UART */
    mmio_write(PL011_BASE + PL011_CR, 0);

    /* Wait for current TX to complete */
    int timeout;
    for (timeout = 100000; timeout > 0; timeout--)
    {
        if (!(mmio_read(PL011_BASE + PL011_FR) & PL011_FR_BUSY))
            break;
    }

    /* Flush FIFOs */
    mmio_write(PL011_BASE + PL011_LCRH, 0);

    /* Clear and disable all interrupts */
    mmio_write(PL011_BASE + PL011_ICR, 0x7FF);
    mmio_write(PL011_BASE + PL011_IMSC, 0);

    /*
     * Set baud rate: 115200 @ 48MHz UART clock (Pi 4 default).
     * Divisor = 48000000 / (16 * 115200) = 26.0416...
     * IBRD = 26, FBRD = round(0.0416 * 64) = 3
     */
    mmio_write(PL011_BASE + PL011_IBRD, 26);
    mmio_write(PL011_BASE + PL011_FBRD, 3);

    /* 8N1, FIFO enabled */
    mmio_write(PL011_BASE + PL011_LCRH, PL011_LCRH_WLEN8 | PL011_LCRH_FEN);

    /* Enable UART, TX, RX */
    mmio_write(PL011_BASE + PL011_CR, PL011_CR_UARTEN | PL011_CR_TXE | PL011_CR_RXE);
}

void putByte(uint8_t chr)
{
    /* Bounded wait for TX FIFO space */
    int timeout;
    for (timeout = 100000; timeout > 0; timeout--)
    {
        if (!(mmio_read(PL011_BASE + PL011_FR) & PL011_FR_TXFF))
            break;
    }

    if (chr == '\n')
    {
        mmio_write(PL011_BASE + PL011_DR, '\r');
        for (timeout = 100000; timeout > 0; timeout--)
        {
            if (!(mmio_read(PL011_BASE + PL011_FR) & PL011_FR_TXFF))
                break;
        }
    }
    mmio_write(PL011_BASE + PL011_DR, chr);
}

void putBytes(const char *str)
{
    while (*str)
        putByte(*str++);
}

/*
 * Minimal kprintf — integer-only, no heap allocation.
 * Supports: %s, %c, %d, %u, %x, %p, %l (long variants), %08x style padding.
 */
static void kprintf_putnum(unsigned long val, int base, int width, char pad)
{
    char buf[20];
    int i = 0;

    if (val == 0)
    {
        buf[i++] = '0';
    }
    else
    {
        while (val > 0)
        {
            int digit = val % base;
            buf[i++] = (digit < 10) ? ('0' + digit) : ('a' + digit - 10);
            val /= base;
        }
    }

    /* Pad */
    while (i < width)
        buf[i++] = pad;

    /* Output in reverse */
    while (i > 0)
        putByte(buf[--i]);
}

void kprintf(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);

    while (*format)
    {
        if (*format != '%')
        {
            putByte(*format++);
            continue;
        }
        format++;

        /* Parse width and pad character */
        char pad = ' ';
        int width = 0;
        if (*format == '0')
        {
            pad = '0';
            format++;
        }
        while (*format >= '0' && *format <= '9')
        {
            width = width * 10 + (*format - '0');
            format++;
        }

        /* Parse 'l' modifier */
        int is_long = 0;
        if (*format == 'l')
        {
            is_long = 1;
            format++;
        }

        switch (*format)
        {
        case 's':
        {
            const char *s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            putBytes(s);
            break;
        }
        case 'c':
            putByte((char)va_arg(ap, int));
            break;
        case 'd':
        {
            long val = is_long ? va_arg(ap, long) : (long)va_arg(ap, int);
            if (val < 0)
            {
                putByte('-');
                val = -val;
            }
            kprintf_putnum((unsigned long)val, 10, width, pad);
            break;
        }
        case 'u':
        {
            unsigned long val = is_long ? va_arg(ap, unsigned long) : (unsigned long)va_arg(ap, unsigned int);
            kprintf_putnum(val, 10, width, pad);
            break;
        }
        case 'x':
        case 'X':
        {
            unsigned long val = is_long ? va_arg(ap, unsigned long) : (unsigned long)va_arg(ap, unsigned int);
            kprintf_putnum(val, 16, width, pad);
            break;
        }
        case 'p':
        {
            unsigned long val = (unsigned long)va_arg(ap, void *);
            putBytes("0x");
            kprintf_putnum(val, 16, 16, '0');
            break;
        }
        case '%':
            putByte('%');
            break;
        default:
            putByte('%');
            putByte(*format);
            break;
        }
        format++;
    }

    va_end(ap);
}
