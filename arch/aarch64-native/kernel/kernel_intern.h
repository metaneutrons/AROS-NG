/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 kernel internal definitions
*/

#ifndef KERNEL_INTERN_H
#define KERNEL_INTERN_H

#include <stdint.h>

/*
 * AARCH64_Implementation — hardware abstraction for SoC-specific functions.
 *
 * DECISION: Modeled after ARM_Implementation in arch/arm-native/kernel/kernel_arm.h.
 * Each SoC (BCM2711, BCM2712) registers its functions via the ARMPLATFORMS
 * symbol set. Kernel code calls through these pointers only.
 * Date: 2026-04-10
 */
struct AARCH64_Implementation
{
    uint64_t            ARMI_Family;        /* ARM architecture version      */
    uint64_t            ARMI_Platform;      /* Platform ID from device tree  */
    void               *ARMI_PeripheralBase;/* SoC peripheral base address   */
    uint32_t            ARMI_AffinityMask;  /* CPU affinity mask             */

    /* Platform init callbacks */
    void  (*ARMI_Init)(void *kbase, void *sbase);
    void  (*ARMI_InitCore)(void *kbase, void *sbase);

    /* IPI for SMP */
    void  (*ARMI_SendIPI)(uint32_t ipi, uint32_t data, uint32_t cpumask);

    /* Timer */
    void *(*ARMI_InitTimer)(void *kbase);
    void  (*ARMI_Delay)(int usec);
    uint64_t (*ARMI_GetTime)(void);

    /* Serial / debug output */
    void  (*ARMI_PutChar)(int c);
    void  (*ARMI_SerPutChar)(uint8_t c);
    int   (*ARMI_SerGetChar)(void);

    /* Interrupt controller */
    void  (*ARMI_IRQInit)(void);
    void  (*ARMI_IRQEnable)(int irq);
    void  (*ARMI_IRQDisable)(int irq);
    void  (*ARMI_IRQProcess)(void);

    /* LED control */
    void  (*ARMI_LED_Toggle)(int led, int state);

    /* VFP/NEON state management */
    void  (*ARMI_Save_VFP_State)(void *buf);
    void  (*ARMI_Restore_VFP_State)(void *buf);
    void  (*ARMI_Init_VFP_State)(void *buf);
};

extern struct AARCH64_Implementation __aarch64_arosintern;

/* LED constants */
#define ARM_LED_ON          1
#define ARM_LED_OFF         0
#define ARM_LED_POWER       0
#define ARM_LED_ACTIVITY    1

/* Platform init — iterates ARMPLATFORMS symbol set */
void platform_Init(struct AARCH64_Implementation *impl, void *bootmsg);

/*
 * BCM2711 (Pi 4) hardware addresses.
 * DECISION: Defined here as SSOT until a dedicated hardware/bcm2711.h is created.
 * Date: 2026-04-10
 */
#define BCM2711_PERIBASE        0xFE000000UL
#define BCM2711_GICD_BASE       0xFF841000UL
#define BCM2711_GICC_BASE       0xFF842000UL

/* Debug output — uses ARMI_SerPutChar if available */
void kprintf(const char *format, ...);

#endif /* KERNEL_INTERN_H */
