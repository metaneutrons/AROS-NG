/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel startup with GIC-400 and ARM Generic Timer.
*/

#include <stdint.h>
#include "kernel_intern.h"
#include "gic400.h"

/* Provided by intvecs.S */
extern void VectorTable(void);

/* Provided by serialdebug.c in the bootstrap */
extern void serInit(void);
extern void kprintf(const char *format, ...);

/* Provided by timer.c */
extern void timer_Init(unsigned long gicd_base);
extern uint64_t timer_GetTickCount(void);

/* Global platform implementation struct */
struct AARCH64_Implementation __aarch64_arosintern
    __attribute__((aligned(8), section(".data"))) = {0};

/* GIC base addresses — set by platform probe */
static unsigned long gicd_base;
static unsigned long gicc_base;

/* Forward declarations */
static void cpu_Probe(struct AARCH64_Implementation *impl);
static void setup_vectors(void);

/*
 * Exception handler — called from intvecs.S stubs.
 */
void ExceptionHandler(uint64_t exception, void *frame)
{
    kprintf("\n*** EXCEPTION %d ***\n", (int)exception);
    kprintf("Frame at %p\n", frame);
    for (;;)
        __asm__ volatile("wfe");
}

/*
 * Interrupt handler — called from IRQStub in intvecs.S.
 * Dispatches through GIC-400.
 */
void InterruptHandler(void)
{
    gic400_HandleIRQ(gicc_base);
}

/* Enable IRQs at CPU level (clear DAIF.I) */
static inline void enable_irqs(void)
{
    __asm__ volatile("msr daifclr, #2");
}

/* Disable IRQs at CPU level (set DAIF.I) */
static inline void disable_irqs(void)
{
    __asm__ volatile("msr daifset, #2");
}

/*
 * kernel_cstart — main kernel entry point.
 */
void kernel_cstart(void)
{
    kprintf("[Kernel] AROS AArch64 Kernel starting (" __DATE__ ")\n\n");

    /* Install exception vector table */
    setup_vectors();
    kprintf("[Kernel] Exception vectors installed (VBAR_EL1)\n");

    /* Probe CPU */
    cpu_Probe(&__aarch64_arosintern);

    /* Probe platform (SoC detection) */
    platform_Init(&__aarch64_arosintern, (void *)0);

    if (__aarch64_arosintern.ARMI_Platform == 0)
    {
        kprintf("[Kernel] FATAL: No platform detected!\n");
        for (;;) __asm__ volatile("wfe");
    }

    kprintf("[Kernel] Platform: BCM%x\n",
            (unsigned int)__aarch64_arosintern.ARMI_Platform);
    kprintf("[Kernel] Peripheral base: %p\n",
            __aarch64_arosintern.ARMI_PeripheralBase);

    /* Initialize GIC-400 */
    gicd_base = BCM2711_GICD_BASE;
    gicc_base = BCM2711_GICC_BASE;
    gic400_Init(gicd_base, gicc_base);
    kprintf("[Kernel] GIC-400 initialized (GICD %p, GICC %p)\n",
            (void *)gicd_base, (void *)gicc_base);

    /* Initialize ARM Generic Timer */
    timer_Init(gicd_base);
    kprintf("[Kernel] ARM Generic Timer initialized (50 Hz)\n");

    /* Enable IRQs at CPU level */
    enable_irqs();
    kprintf("[Kernel] IRQs enabled\n\n");

    /* Wait for timer ticks and print progress */
    kprintf("[Kernel] Waiting for timer interrupts...\n");

    uint64_t last_printed = 0;
    for (;;)
    {
        uint64_t ticks = timer_GetTickCount();
        if (ticks != last_printed && (ticks % 50) == 0 && ticks > 0)
        {
            kprintf("[Kernel] Timer: %lu ticks (%lu seconds)\n",
                    ticks, ticks / 50);
            last_printed = ticks;

            /* Stop after 5 seconds to show it works */
            if (ticks >= 250)
            {
                kprintf("\n[Kernel] Timer test PASSED — %lu ticks in 5 seconds.\n", ticks);
                kprintf("[Kernel] Interrupts working. System halted.\n");
                disable_irqs();
                for (;;) __asm__ volatile("wfe");
            }
        }
        /* Yield CPU until next interrupt */
        __asm__ volatile("yield");
    }
}

static void setup_vectors(void)
{
    uint64_t vbar = (uint64_t)&VectorTable;
    __asm__ volatile("msr vbar_el1, %0" : : "r"(vbar));
    __asm__ volatile("isb");
}

static void cpu_Probe(struct AARCH64_Implementation *impl)
{
    uint64_t midr, mpidr, cntfrq;

    __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(cntfrq));

    impl->ARMI_Family = 8;

    kprintf("[Kernel] CPU: ");
    if (((midr >> 24) & 0xFF) == 0x41) kprintf("ARM ");
    uint32_t part = (midr >> 4) & 0xFFF;
    if (part == 0xD08) kprintf("Cortex-A72");
    else if (part == 0xD0B) kprintf("Cortex-A76");
    else kprintf("Unknown (0x%03x)", part);
    kprintf(" r%dp%d\n", (int)((midr >> 20) & 0xF), (int)(midr & 0xF));
    kprintf("[Kernel] Core: %d, Timer: %lu Hz\n",
            (int)(mpidr & 0xFF), cntfrq);
}
