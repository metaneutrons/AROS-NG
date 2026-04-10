/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel startup — parse boot tags, set up memory, create ExecBase.
          Ported from arch/arm-native/kernel/kernel_startup.c.
*/

#include <stdint.h>
#include <aros/kernel.h>
#include "kernel_intern.h"
#include "tls.h"

/* BCM2711 PL011 UART — direct access for early boot */
#define PL011_BASE  0xFE201000UL
#define PL011_DR    0x00
#define PL011_FR    0x18
#define PL011_FR_TXFF (1 << 5)

/* Provided by intvecs.S */
extern void VectorTable(void);

/* Forward declarations */
void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex(uint64_t val);
void clear_bss(struct TagItem *msg);
void setup_vectors(void);
void cpu_Probe(struct AARCH64_Implementation *impl);
void kernel_cstart(struct TagItem *msg);

/* Globals */
extern struct AARCH64_Implementation __aarch64_arosintern;

extern struct ExecBase *SysBase;
extern struct TagItem *BootMsg;

/* Stack for the kernel (40KB) */
static uint64_t stack[5120] __attribute__((used, aligned(16)));

/*
 * _start — entry point, called by bootstrap.
 * Must be at offset 0 in .text.
 * x0 = pointer to TagItem list from bootstrap.
 *
 * Written in asm to avoid the compiler spilling x0 to the old stack
 * before we switch to the new one.
 *
 * Placed in .text.startup section so the linker script can put it first.
 */
__asm__ (
    ".section .text.startup, \"ax\"\n"
    ".globl _start\n"
    ".type _start, %function\n"
    "_start:\n"
    "   adrp x1, stack + 40960\n"
    "   add  x1, x1, :lo12:stack + 40960\n"
    "   mov  sp, x1\n"
    "   b    kernel_cstart\n"
    ".text\n"
);

/*
 * kernel_cstart — main kernel initialization.
 */
void __attribute__((noinline)) kernel_cstart(struct TagItem *msg)
{
    unsigned long memlower = 0, memupper = 0;
    unsigned long protlower = 0, protupper = 0;
    struct TagItem *tag;
    tls_t *__tls;

    BootMsg = msg;

    uart_puts("\n[Kernel] AROS AArch64 Kernel (" __DATE__ ")\n");

    /* Clear BSS */
    clear_bss(msg);

    /* Install exception vectors */
    setup_vectors();
    uart_puts("[Kernel] Exception vectors installed\n");

    /* Probe CPU */
    cpu_Probe(&__aarch64_arosintern);

    /* Parse boot tags */
    tag = msg;
    while (tag->ti_Tag != TAG_DONE)
    {
        switch (tag->ti_Tag)
        {
        case KRN_MEMLower:
            memlower = tag->ti_Data;
            break;
        case KRN_MEMUpper:
            memupper = tag->ti_Data;
            break;
        case KRN_ProtAreaStart:
            protlower = tag->ti_Data;
            break;
        case KRN_ProtAreaEnd:
            protupper = (tag->ti_Data + 4095) & ~4095UL;
            break;
        case KRN_Platform:
            __aarch64_arosintern.ARMI_Platform = tag->ti_Data;
            break;
        }
        tag++;
    }

    uart_puts("[Kernel] Memory: ");
    uart_puthex(memlower);
    uart_puts(" - ");
    uart_puthex(memupper);
    uart_puts(" (");
    uart_puthex((memupper - memlower) >> 20);
    uart_puts(" MB)\n");

    uart_puts("[Kernel] Protected: ");
    uart_puthex(protlower);
    uart_puts(" - ");
    uart_puthex(protupper);
    uart_puts("\n");

    /* Allocate TLS in protected area */
    __tls = (tls_t *)protupper;
    protupper += (sizeof(tls_t) + 4095) & ~4095UL;

    __tls->SysBase = NULL;
    __tls->KernelBase = NULL;
    __tls->ThisTask = NULL;
    __tls->IDNestCnt = -1;
    __tls->TDNestCnt = -1;

    /* Set TLS pointer in TPIDR_EL1 */
    __asm__ volatile("msr tpidr_el1, %0" : : "r"(__tls));

    uart_puts("[Kernel] TLS at ");
    uart_puthex((uint64_t)__tls);
    uart_puts("\n");

    /* Adjust memory lower bound past protected area */
    if (memlower >= protlower && memlower < protupper)
        memlower = protupper;

    uart_puts("[Kernel] Available memory: ");
    uart_puthex(memlower);
    uart_puts(" - ");
    uart_puthex(memupper);
    uart_puts("\n");

    /*
     * TODO: When the full AROS build system links kernel.resource and
     * exec.library into core.elf, the following sequence will be enabled:
     *
     *   krnCreateTLSFMemHeader("System Memory", 0, mh,
     *       memupper - memlower, MEMF_FAST|MEMF_PUBLIC|MEMF_KICK|MEMF_LOCAL);
     *   krnPrepareExecBase(ranges, mh, BootMsg);
     *   __tls->SysBase = SysBase;
     *   InitCode(RTF_SINGLETASK, 0);
     *   InitCode(RTF_COLDSTART, 0);
     *
     * For now, we halt here to prove the boot chain works.
     */

    /* Read SCTLR to verify MMU state */
    uint64_t sctlr;
    __asm__ volatile("mrs %0, sctlr_el1" : "=r"(sctlr));
    uart_puts("[Kernel] SCTLR_EL1: ");
    uart_puthex(sctlr);
    uart_puts(" (MMU=");
    uart_putc((sctlr & 1) ? '1' : '0');
    uart_puts(", D$=");
    uart_putc((sctlr & 4) ? '1' : '0');
    uart_puts(", I$=");
    uart_putc((sctlr & (1<<12)) ? '1' : '0');
    uart_puts(")\n");

    uart_puts("\n[Kernel] Boot chain complete. Waiting for full kernel build.\n");
    uart_puts("[Kernel] System halted.\n");

    for (;;) __asm__ volatile("wfe");
}

/*
 * Clear BSS sections listed in KRN_KernelBss tag.
 */
void clear_bss(struct TagItem *msg)
{
    struct TagItem *tag = msg;
    while (tag->ti_Tag != TAG_DONE)
    {
        if (tag->ti_Tag == KRN_KernelBss && tag->ti_Data)
        {
            struct KernelBSS *bss = (struct KernelBSS *)tag->ti_Data;
            while (bss->addr && bss->len)
            {
                uint8_t *p = (uint8_t *)bss->addr;
                unsigned long len = bss->len;
                while (len--) *p++ = 0;
                bss++;
            }
            return;
        }
        tag++;
    }
}

void setup_vectors(void)
{
    __asm__ volatile("msr vbar_el1, %0; isb" : : "r"((uint64_t)&VectorTable));
}

void cpu_Probe(struct AARCH64_Implementation *impl)
{
    uint64_t midr, cntfrq;
    __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(cntfrq));

    impl->ARMI_Family = 8;

    uart_puts("[Kernel] CPU: ");
    uint32_t part = (midr >> 4) & 0xFFF;
    if (part == 0xD08) uart_puts("Cortex-A72");
    else if (part == 0xD0B) uart_puts("Cortex-A76");
    else { uart_puts("Unknown-"); uart_puthex(part); }
    uart_puts(", Timer: ");
    uart_puthex(cntfrq);
    uart_puts(" Hz\n");
}

/* Minimal UART output — no dependencies */
void uart_putc(char c)
{
    while (*(volatile uint32_t *)(PL011_BASE + PL011_FR) & PL011_FR_TXFF) ;
    if (c == '\n') {
        *(volatile uint32_t *)(PL011_BASE + PL011_DR) = '\r';
        while (*(volatile uint32_t *)(PL011_BASE + PL011_FR) & PL011_FR_TXFF) ;
    }
    *(volatile uint32_t *)(PL011_BASE + PL011_DR) = c;
}

void uart_puts(const char *s) { while (*s) uart_putc(*s++); }

void uart_puthex(uint64_t val)
{
    const char h[] = "0123456789abcdef";
    int started = 0;
    uart_puts("0x");
    for (int i = 60; i >= 0; i -= 4) {
        int d = (val >> i) & 0xF;
        if (d || started || i == 0) { uart_putc(h[d]); started = 1; }
    }
}

/* Stub for ExceptionHandler called from intvecs.S */
void ExceptionHandler(uint64_t exception, void *frame)
{
    uart_puts("\n*** EXCEPTION ");
    uart_puthex(exception);
    uart_puts(" ***\n");
    for (;;) __asm__ volatile("wfe");
}

/* Stub for InterruptHandler called from intvecs.S */
void InterruptHandler(void)
{
    /* TODO: GIC-400 dispatch */
}
