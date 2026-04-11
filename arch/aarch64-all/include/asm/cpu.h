/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 memory barrier macros.
          Compatible with arch/arm-all/include/asm/cpu.h API.
*/

#ifndef ASM_AARCH64_CPU_H
#define ASM_AARCH64_CPU_H

static inline void dsb(void) { __asm__ volatile("dsb sy" ::: "memory"); }
static inline void dmb(void) { __asm__ volatile("dmb sy" ::: "memory"); }
static inline void isb(void) { __asm__ volatile("isb" ::: "memory"); }

#endif /* ASM_AARCH64_CPU_H */
