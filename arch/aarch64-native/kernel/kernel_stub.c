/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Minimal AArch64 kernel entry — prints to UART and halts.
          This is a temporary stub until the real kernel (kernel.resource,
          exec.library, task.resource) is built.
*/

#include <stdint.h>

/* BCM2711 PL011 UART */
#define PL011_BASE  0xFE201000UL
#define PL011_DR    0x00
#define PL011_FR    0x18
#define PL011_FR_TXFF (1 << 5)

static void uart_putc(char c)
{
    while (*(volatile uint32_t *)(PL011_BASE + PL011_FR) & PL011_FR_TXFF)
        ;
    if (c == '\n')
    {
        *(volatile uint32_t *)(PL011_BASE + PL011_DR) = '\r';
        while (*(volatile uint32_t *)(PL011_BASE + PL011_FR) & PL011_FR_TXFF)
            ;
    }
    *(volatile uint32_t *)(PL011_BASE + PL011_DR) = c;
}

static void uart_puts(const char *s)
{
    while (*s) uart_putc(*s++);
}

static void uart_puthex(uint64_t val)
{
    const char hex[] = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 60; i >= 0; i -= 4)
        uart_putc(hex[(val >> i) & 0xF]);
}

/*
 * Kernel entry point — called by bootstrap via function pointer.
 * TagItem list is passed as first argument.
 */
void _start(void *tags)
{
    uart_puts("\n[Kernel] AROS AArch64 Kernel (" __DATE__ ")\n");
    uart_puts("[Kernel] Tags at ");
    uart_puthex((uint64_t)tags);
    uart_puts("\n");

    /* Read CPU ID */
    uint64_t midr;
    __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));
    uart_puts("[Kernel] MIDR_EL1: ");
    uart_puthex(midr);
    uart_puts("\n");

    /* Read current EL */
    uint64_t el;
    __asm__ volatile("mrs %0, CurrentEL" : "=r"(el));
    uart_puts("[Kernel] Exception level: EL");
    uart_putc('0' + (int)((el >> 2) & 3));
    uart_puts("\n");

    /* Read SCTLR to verify MMU state */
    uint64_t sctlr;
    __asm__ volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    uart_puts("[Kernel] SCTLR_EL1: ");
    uart_puthex(sctlr);
    uart_puts(" (MMU=");
    uart_putc((sctlr & 1) ? '1' : '0');
    uart_puts(", Cache=");
    uart_putc((sctlr & 4) ? '1' : '0');
    uart_puts(")\n");

    uart_puts("\n[Kernel] System halted — waiting for real kernel.\n");

    for (;;)
        __asm__ volatile("wfe");
}
