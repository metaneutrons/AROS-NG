/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel startup — parse boot tags, set up memory, create ExecBase.
          Ported from arch/arm-native/kernel/kernel_startup.c.
*/

#include <aros/kernel.h>
#include <aros/symbolsets.h>
#include <aros/aarch64/cpucontext.h>
#include <exec/memory.h>
#include <exec/memheaderext.h>
#include <exec/tasks.h>
#include <exec/alerts.h>
#include <exec/execbase.h>
#include <exec/resident.h>
#include <proto/kernel.h>
#include <proto/exec.h>

#include <strings.h>
#include <string.h>

#include "exec_intern.h"
#include "etask.h"
#include "tlsf.h"

#include "kernel_intern.h"
#include "kernel_debug.h"
#include "kernel_romtags.h"
#include "gic400.h"

/*
 * Patched AllocMem that strips MEMF_CHIP — AArch64 has no chip memory.
 * Follows the same pattern as arch/arm-native/kernel/platform_init.c.
 */
void *(*__chip_AllocMem)();

#define ExecAllocMem(byteSize, requirements) \
    AROS_CALL2(void *, __chip_AllocMem, \
        AROS_LCA(ULONG, byteSize, D0), \
        AROS_LCA(ULONG, requirements, D1), \
        struct ExecBase *, SysBase)

AROS_LH2(APTR, AllocMem,
        AROS_LHA(ULONG, byteSize, D0),
        AROS_LHA(ULONG, requirements, D1),
        struct ExecBase *, SysBase, 33, Kernel)
{
    AROS_LIBFUNC_INIT
    if (requirements & MEMF_CHIP)
        requirements &= ~MEMF_CHIP;
    return ExecAllocMem(byteSize, requirements);
    AROS_LIBFUNC_EXIT
}

#undef KernelBase
#include "tls.h"

/* BCM2711 PL011 UART — direct access for early boot (before bug() works) */
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
static void clear_bss(struct TagItem *msg);
static void setup_vectors(void);
void kernel_cstart(struct TagItem *msg);

/* Globals — defined in kernel_startup.c */
extern struct AARCH64_Implementation __aarch64_arosintern;
extern struct ExecBase *SysBase;
extern struct TagItem *BootMsg;

/* Stack for the kernel (40KB) -- in .data so clear_bss does not zero it */
static uint64_t stack[5120] __attribute__((used, aligned(16), section(".data")));

/*
 * _start — entry point, called by bootstrap.
 * x0 = pointer to TagItem list from bootstrap.
 * Placed in .text.startup so linker script can order it first.
 */
__asm__ (
    ".section .text.startup, \"ax\"\n"
    ".globl _start\n"
    ".type _start, %function\n"
    "_start:\n"
    "   msr  spsel, #1\n"          /* EL1h: use SP_EL1 everywhere */
    "   adrp x1, stack + 40960\n"
    "   add  x1, x1, :lo12:stack + 40960\n"
    "   mov  sp, x1\n"
    "   b    kernel_cstart\n"
    ".text\n"
);

/*
 * kernel_cstart — main kernel initialization.
 * Follows the same sequence as arch/arm-native/kernel/kernel_startup.c.
 */
void __attribute__((noinline)) kernel_cstart(struct TagItem *msg)
{
    UWORD *ranges[3];
    struct MemHeader *mh;
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

    /* Probe CPU */
    {
        uint64_t midr, cntfrq;
        __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));
        __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(cntfrq));
        __aarch64_arosintern.ARMI_Family = 8;

        uart_puts("[Kernel] CPU: ");
        uint32_t part = (midr >> 4) & 0xFFF;
        if (part == 0xD08) uart_puts("Cortex-A72");
        else if (part == 0xD0B) uart_puts("Cortex-A76");
        else { uart_puts("Unknown-"); uart_puthex(part); }
        uart_puts(", Timer: ");
        uart_puthex(cntfrq);
        uart_puts(" Hz\n");
    }

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
    uart_puts("\n");

    /* Allocate TLS in protected area */
    __tls = (tls_t *)protupper;
    protupper += (sizeof(tls_t) + 4095) & ~4095UL;

    __tls->SysBase = NULL;
    __tls->KernelBase = NULL;
    __tls->ThisTask = NULL;
    __tls->IDNestCnt = -1;
    __tls->TDNestCnt = -1;
    __tls->SupervisorCount = 0;

    /* Set TLS pointer in TPIDR_EL1 */
    __asm__ volatile("msr tpidr_el1, %0" : : "r"(__tls));

    uart_puts("[Kernel] TLS @ ");
    uart_puthex((uint64_t)__tls);
    uart_puts("\n");

    /* Adjust memory lower bound past protected area */
    if (memlower >= protlower)
        memlower = protupper;

    /* --- Memory and ExecBase initialization --- */

    mh = (struct MemHeader *)memlower;

    uart_puts("[Kernel] Creating TLSF memory @ ");
    uart_puthex(memlower);
    uart_puts(", size ");
    uart_puthex(memupper - memlower);
    uart_puts("\n");

    /* Initialize TLSF memory allocator */
    krnCreateTLSFMemHeader("System Memory", 0, mh,
        (memupper - memlower),
        MEMF_FAST | MEMF_PUBLIC | MEMF_KICK | MEMF_LOCAL);

    /* Protect the bootstrap area from allocation */
    if (memlower < protlower)
    {
        ((struct MemHeaderExt *)mh)->mhe_AllocAbs(
            (struct MemHeaderExt *)mh,
            protupper - protlower, (void *)protlower);
    }

    /* Kernel ROM ranges for resident scanning */
    ranges[0] = (UWORD *)krnGetTagData(KRN_KernelLowest, 0, BootMsg);
    ranges[1] = (UWORD *)krnGetTagData(KRN_KernelHighest, 0, BootMsg);
    ranges[2] = (UWORD *)-1;

    uart_puts("[Kernel] Preparing ExecBase...\n");
    krnPrepareExecBase(ranges, mh, BootMsg);

    __tls->SysBase = SysBase;

    uart_puts("[Kernel] SysBase @ ");
    uart_puthex((uint64_t)SysBase);
    uart_puts("\n");

    D(bug("[Kernel] SysBase @ 0x%p, KernelBase @ 0x%p\n",
          SysBase, __tls->KernelBase));

    /* --- Framebuffer init --- */
    extern int vcfb_init(void);
    extern void fb_Putc(char chr);
    if (vcfb_init())
    {
        /* Print banner on screen */
        const char *banner = "[Kernel] AROS AArch64 on Raspberry Pi 4\n";
        while (*banner) fb_Putc(*banner++);
    }

    /* --- GIC-400 and timer initialization --- */

    /* BCM2711_GICD_BASE / BCM2711_GICC_BASE from kernel_aarch64.h */
    uart_puts("[Kernel] Initializing GIC-400...\n");
    gic400_Init(BCM2711_GICD_BASE, BCM2711_GICC_BASE);

    /* Timer init — must be after GIC, before InitCode */
    extern void timer_Init(unsigned long gicd_base);
    timer_Init(BCM2711_GICD_BASE);

    /* Enable IRQs at CPU level */
    __asm__ volatile("msr daifclr, #2");  /* Clear IRQ mask bit */
    uart_puts("[Kernel] IRQs enabled\n");

    /* --- Run resident modules --- */

    uart_puts("[Kernel] InitCode(RTF_SINGLETASK)...\n");
    InitCode(RTF_SINGLETASK, 0);

    /*
     * Patch AllocMem to ignore MEMF_CHIP — AArch64 has no chip memory.
     * Must happen after RTF_SINGLETASK (kernel.resource init) but before
     * RTF_COLDSTART (graphics/intuition init which allocate sprite data
     * with MEMF_CHIP).
     */
    {
        #include <defines/exec_LVO.h>
        extern void *(*__chip_AllocMem)();
        __chip_AllocMem = SetFunction((struct Library *)SysBase,
            -LVOAllocMem * LIB_VECTSIZE,
            AROS_SLIB_ENTRY(AllocMem, Kernel, LVOAllocMem));
    }

    uart_puts("[Kernel] InitCode(RTF_COLDSTART)...\n");
    InitCode(RTF_COLDSTART, 0);

    /*
     * If we get here, no COLDSTART resident took over.
     * This is expected until we have timer.device, DOS, etc.
     */
    uart_puts("[Kernel] exec.library is alive! SysBase @ ");
    uart_puthex((uint64_t)SysBase);
    uart_puts("\n");

    /* Verify timer is ticking — wait for first 50 ticks (1 second) */
    extern uint64_t timer_GetTickCount(void);
    while (timer_GetTickCount() < 50)
        __asm__ volatile("wfe");
    uart_puts("[Kernel] Timer OK: ");
    uart_puthex(timer_GetTickCount());
    uart_puts(" ticks\n");

    uart_puts("[Kernel] System idle (no COLDSTART residents yet).\n");
    for (;;) __asm__ volatile("wfe");
}

/* --- Helper functions --- */

static void clear_bss(struct TagItem *msg)
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

static void setup_vectors(void)
{
    __asm__ volatile("msr vbar_el1, %0; isb" : : "r"((uint64_t)&VectorTable));
}

/* Minimal UART output — no dependencies, for early boot before bug() works */
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

/* Exception/interrupt stubs called from intvecs.S */
void ExceptionHandler(uint64_t exception, void *frame)
{
    uint64_t esr, elr, far, spsr;
    uint64_t *f = (uint64_t *)frame;
    __asm__ volatile("mrs %0, esr_el1" : "=r"(esr));
    __asm__ volatile("mrs %0, elr_el1" : "=r"(elr));
    __asm__ volatile("mrs %0, far_el1" : "=r"(far));
    __asm__ volatile("mrs %0, spsr_el1" : "=r"(spsr));

    uart_puts("\n*** EXCEPTION ");
    uart_puthex(exception);
    uart_puts(" ***\n");
    uart_puts("  ESR_EL1: ");
    uart_puthex(esr);
    uart_puts(" (EC=");
    uart_puthex((esr >> 26) & 0x3F);
    uart_puts(")\n");
    uart_puts("  ELR_EL1: ");
    uart_puthex(elr);
    uart_puts("\n");
    uart_puts("  SPSR_EL1: ");
    uart_puthex(spsr);
    uart_puts("\n");
    uart_puts("  FAR_EL1: ");
    uart_puthex(far);
    uart_puts("\n");
    /* frame: [0]=ESR, [1]=SPSR, [2]=LR, [3]=ELR, [4]=SP_EL0, [5]=SP_orig, [6]=FAR */
    uart_puts("  LR: ");
    uart_puthex(f[2]);
    uart_puts("\n");
    uart_puts("  SP_orig: ");
    uart_puthex(f[5]);
    uart_puts("\n");
    /* Walk the frame pointer chain for a backtrace */
    {
        uint64_t *fp;
        int i;
        __asm__ volatile("mov %0, x29" : "=r"(fp));
        uart_puts("  Backtrace:");
        for (i = 0; i < 10 && fp && ((uint64_t)fp & 7) == 0 && (uint64_t)fp > 0x10000 && (uint64_t)fp < 0x3c000000; i++) {
            uart_puts(" ");
            uart_puthex(fp[1]); /* return address */
            fp = (uint64_t *)fp[0]; /* previous frame */
        }
        uart_puts("\n");
    }
    for (;;) __asm__ volatile("wfe");
}

void InterruptHandler(void)
{
    tls_t *__tls;
    __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls));
    __tls->SupervisorCount++;

    gic400_HandleIRQ(gic400_GetGICCBase());

    __tls->SupervisorCount--;
}
