/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Licensed under the AROS Public License (APL), Version 1.1.

    Desc: PL011 UART serial debug output for AArch64 Raspberry Pi bootstrap.

    Register offsets and initialization sequence derived from:
    - ARM PL011 Technical Reference Manual (DDI 0183G), Section 3.3.8
    - BCM2711 ARM Peripherals datasheet §1.2 (peripheral base 0xFE000000)
    - Baud rate: 48MHz / (16 * 115200) = 26.0416 → IBRD=26, FBRD=3
*/

#include <stdint.h>
#include <stdarg.h>

#include "serialdebug.h"

/* BCM2711 PL011 UART0 base address — BCM2711 datasheet §1.2 */
/*
 * DECISION: Hardcoded for bootstrap. The kernel will use device-tree
 * based detection via the HAL. Date: 2026-04-10
 */
#define BCM2711_PERIBASE    0xFE000000UL
#define PL011_BASE          (BCM2711_PERIBASE + 0x201000)

/*
 * PL011 register offsets — DDI 0183G §3.2, Table 3-1
 */
#define PL011_DR            0x00    /* Data Register */
#define PL011_FR            0x18    /* Flag Register */
#define PL011_IBRD          0x24    /* Integer Baud Rate Divisor */
#define PL011_FBRD          0x28    /* Fractional Baud Rate Divisor */
#define PL011_LCRH          0x2C    /* Line Control Register */
#define PL011_CR            0x30    /* Control Register */
#define PL011_IMSC          0x38    /* Interrupt Mask Set/Clear */
#define PL011_ICR           0x44    /* Interrupt Clear Register */

/* FR bits — DDI 0183G §3.3.3 */
#define FR_TXFF             (1 << 5)    /* TX FIFO full */
#define FR_BUSY             (1 << 3)    /* UART busy */

/* LCRH bits — DDI 0183G §3.3.7 */
#define LCRH_WLEN8          (3 << 5)    /* 8-bit word length */
#define LCRH_FEN            (1 << 4)    /* FIFO enable */

/* CR bits — DDI 0183G §3.3.8 */
#define CR_UARTEN           (1 << 0)    /* UART enable */
#define CR_TXE              (1 << 8)    /* TX enable */
#define CR_RXE              (1 << 9)    /* RX enable */

static inline void mmio_wr(unsigned long addr, uint32_t val)
{
    *(volatile uint32_t *)addr = val;
}

static inline uint32_t mmio_rd(unsigned long addr)
{
    return *(volatile uint32_t *)addr;
}

/*
 * serInit — initialize PL011 UART for 115200 8N1.
 *
 * Sequence per PL011 TRM §3.3.8 "Disabling the UART":
 *   1. Disable UART (CR = 0)
 *   2. Wait for current transmission to complete (FR.BUSY == 0)
 *   3. Flush FIFOs by disabling them (LCRH.FEN = 0)
 *   4. Program baud rate (IBRD, FBRD)
 *   5. Program line control (LCRH)
 *   6. Enable UART, TX, RX (CR)
 */
void serInit(void)
{
    int timeout;

    mmio_wr(PL011_BASE + PL011_CR, 0);

    for (timeout = 100000; timeout > 0; timeout--)
        if (!(mmio_rd(PL011_BASE + PL011_FR) & FR_BUSY))
            break;

    mmio_wr(PL011_BASE + PL011_LCRH, 0);
    mmio_wr(PL011_BASE + PL011_ICR, 0x7FF);
    mmio_wr(PL011_BASE + PL011_IMSC, 0);

    /*
     * Baud rate divisor for 115200 baud at 48MHz UART clock:
     *   BRD = 48000000 / (16 × 115200) = 26.04166...
     *   IBRD = 26
     *   FBRD = round(0.04166 × 64) = 3
     * Ref: DDI 0183G §3.3.6
     */
    mmio_wr(PL011_BASE + PL011_IBRD, 26);
    mmio_wr(PL011_BASE + PL011_FBRD, 3);

    mmio_wr(PL011_BASE + PL011_LCRH, LCRH_WLEN8 | LCRH_FEN);
    mmio_wr(PL011_BASE + PL011_CR, CR_UARTEN | CR_TXE | CR_RXE);
}

void putByte(uint8_t chr)
{
    int timeout;

    for (timeout = 100000; timeout > 0; timeout--)
        if (!(mmio_rd(PL011_BASE + PL011_FR) & FR_TXFF))
            break;

    if (chr == '\n')
    {
        mmio_wr(PL011_BASE + PL011_DR, '\r');
        for (timeout = 100000; timeout > 0; timeout--)
            if (!(mmio_rd(PL011_BASE + PL011_FR) & FR_TXFF))
                break;
    }
    mmio_wr(PL011_BASE + PL011_DR, chr);
}

void putBytes(const char *str)
{
    while (*str)
        putByte(*str++);
}

/* Minimal kprintf — integer-only, no heap. Supports %s %c %d %u %x %p %l */
static void put_num(unsigned long val, int base, int width, char pad)
{
    char buf[20];
    int i = 0;

    if (val == 0)
        buf[i++] = '0';
    else
        while (val > 0)
        {
            int d = val % base;
            buf[i++] = (d < 10) ? ('0' + d) : ('a' + d - 10);
            val /= base;
        }

    while (i < width)
        buf[i++] = pad;

    while (i > 0)
        putByte(buf[--i]);
}

void kprintf(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);

    while (*format)
    {
        if (*format != '%') { putByte(*format++); continue; }
        format++;

        char pad = ' ';
        int width = 0;
        if (*format == '0') { pad = '0'; format++; }
        while (*format >= '0' && *format <= '9')
            width = width * 10 + (*format++ - '0');

        int is_long = 0;
        if (*format == 'l') { is_long = 1; format++; }

        switch (*format)
        {
        case 's': { const char *s = va_arg(ap, const char *);
                     putBytes(s ? s : "(null)"); break; }
        case 'c': putByte((char)va_arg(ap, int)); break;
        case 'd': { long v = is_long ? va_arg(ap, long) : (long)va_arg(ap, int);
                     if (v < 0) { putByte('-'); v = -v; }
                     put_num((unsigned long)v, 10, width, pad); break; }
        case 'u': { unsigned long v = is_long ? va_arg(ap, unsigned long)
                                              : (unsigned long)va_arg(ap, unsigned int);
                     put_num(v, 10, width, pad); break; }
        case 'x': case 'X':
                  { unsigned long v = is_long ? va_arg(ap, unsigned long)
                                              : (unsigned long)va_arg(ap, unsigned int);
                     put_num(v, 16, width, pad); break; }
        case 'p': { unsigned long v = (unsigned long)va_arg(ap, void *);
                     putBytes("0x"); put_num(v, 16, 16, '0'); break; }
        case '%': putByte('%'); break;
        default:  putByte('%'); putByte(*format); break;
        }
        format++;
    }

    va_end(ap);
}
