/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel startup.
          This is the monolithic kernel entry point for the initial bringup.
          It will be refactored into the standard AROS bootstrap→core.elf
          split once the full build system is operational.
*/

#include <stdint.h>
#include "kernel_intern.h"

/* Provided by intvecs.S */
extern void VectorTable(void);

/* Provided by serialdebug.c in the bootstrap */
extern void serInit(void);
extern void kprintf(const char *format, ...);

/* Global platform implementation struct */
struct AARCH64_Implementation __aarch64_arosintern
    __attribute__((aligned(8), section(".data"))) = {0};

/* Forward declarations */
static void cpu_Probe(struct AARCH64_Implementation *impl);
static void setup_vectors(void);

/*
 * Exception handler — called from intvecs.S stubs.
 * For now, just prints the exception info and halts.
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
 * Placeholder until GIC-400 is integrated (Task 7).
 */
void InterruptHandler(void)
{
    /* No interrupts enabled yet — should not be reached */
}

/*
 * kernel_cstart — main kernel entry point.
 *
 * Called from boot() after UART init and basic hardware detection.
 * In the full AROS build, this will be the entry point of core.elf
 * called by the bootstrap with a TagItem list.
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

    if (__aarch64_arosintern.ARMI_Platform != 0)
    {
        kprintf("[Kernel] Platform: BCM%x detected\n",
                (unsigned int)__aarch64_arosintern.ARMI_Platform);
        kprintf("[Kernel] Peripheral base: %p\n",
                __aarch64_arosintern.ARMI_PeripheralBase);
    }
    else
    {
        kprintf("[Kernel] WARNING: No platform detected!\n");
    }

    /* Memory info — hardcoded for QEMU raspi4b (1GB RAM) */
    kprintf("[Kernel] Memory: 0x00000000 - 0x3FFFFFFF (1 GB)\n");

    /*
     * At this point in the full AROS build, we would:
     * 1. Parse boot TagItems for memory ranges
     * 2. Initialize TLSF memory allocator
     * 3. Call krnPrepareExecBase() to create SysBase
     * 4. Call InitCode(RTF_SINGLETASK, 0)
     * 5. Switch to user mode
     * 6. Call InitCode(RTF_COLDSTART, 0)
     *
     * For now, we demonstrate the kernel infrastructure works
     * and enter an idle loop.
     */

    kprintf("\n[Kernel] ========================================\n");
    kprintf("[Kernel] Kernel infrastructure ready.\n");
    kprintf("[Kernel] Next steps:\n");
    kprintf("[Kernel]   - AROS build system integration\n");
    kprintf("[Kernel]   - exec.library / SysBase creation\n");
    kprintf("[Kernel]   - GIC-400 interrupt controller (Task 7)\n");
    kprintf("[Kernel]   - ARM Generic Timer (Task 7)\n");
    kprintf("[Kernel] ========================================\n\n");

    kprintf("[Kernel] Entering idle loop.\n");

    for (;;)
        __asm__ volatile("wfe");
}

/*
 * Install the exception vector table at VBAR_EL1.
 */
static void setup_vectors(void)
{
    uint64_t vbar = (uint64_t)&VectorTable;
    __asm__ volatile("msr vbar_el1, %0" : : "r"(vbar));
    __asm__ volatile("isb");
}

/*
 * CPU identification via MIDR_EL1.
 */
static void cpu_Probe(struct AARCH64_Implementation *impl)
{
    uint64_t midr, mpidr, cntfrq;

    __asm__ volatile("mrs %0, midr_el1" : "=r"(midr));
    __asm__ volatile("mrs %0, mpidr_el1" : "=r"(mpidr));
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(cntfrq));

    uint32_t implementer = (midr >> 24) & 0xFF;
    uint32_t part = (midr >> 4) & 0xFFF;
    uint32_t revision = midr & 0xF;

    impl->ARMI_Family = 8;  /* ARMv8 */

    kprintf("[Kernel] CPU: ");
    if (implementer == 0x41)
        kprintf("ARM ");
    if (part == 0xD08)
        kprintf("Cortex-A72");
    else if (part == 0xD0B)
        kprintf("Cortex-A76");
    else
        kprintf("Unknown (part 0x%03x)", part);
    kprintf(" r%dp%d\n", (int)((midr >> 20) & 0xF), (int)revision);

    kprintf("[Kernel] Core: %d (MPIDR 0x%016lx)\n",
            (int)(mpidr & 0xFF), mpidr);
    kprintf("[Kernel] Timer: %lu Hz\n", cntfrq);
}
