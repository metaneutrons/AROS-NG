#ifndef AROS_AARCH64_CPUCONTEXT_H
#define AROS_AARCH64_CPUCONTEXT_H

/*
    Copyright © 2016-2026, The AROS Development Team. All rights reserved.

    Desc: CPU context definition for ARM AArch64 processors
    Lang: english
*/

struct ExceptionContext
{
    IPTR r[29];     /* x0-x28: General purpose registers            */
    IPTR fp;        /* x29: Frame pointer                           */
    IPTR lr;        /* x30: Link register                           */
    IPTR sp;        /* Stack pointer (sp_el0)                       */
    IPTR pc;        /* Program counter (elr_el1)                    */
    IPTR pstate;    /* Saved processor state (spsr_el1)             */
    UWORD Flags;    /* Context flags (see enECFlags below)          */
    UBYTE FPUType;  /* FPU type (see below)                         */
    UBYTE Reserved; /* Unused, padding                              */
    APTR  fpuContext; /* Pointer to VFPContext area                  */
};

/* Flags */
enum enECFlags
{
    ECF_FPU = 1<<0  /* FPU/NEON data is present in fpuContext       */
};

/* FPU types */
#define FPU_NONE                0
#define FPU_VFP                 1   /* AArch64 always has NEON/VFP   */

/*
    VFP/NEON context for AArch64.
    AArch64 has 32 128-bit SIMD/FP registers (V0-V31),
    stored as pairs of 64-bit values (low/high).
*/
struct VFPContext
{
    IPTR fpr[64];   /* V0-V31: 32 x 128-bit regs stored as 64 x 64-bit */
    ULONG fpsr;     /* Floating-point Status Register                   */
    ULONG fpcr;     /* Floating-point Control Register                  */
};

#endif /* AROS_AARCH64_CPUCONTEXT_H */
