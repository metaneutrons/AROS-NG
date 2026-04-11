/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Thread-Local Storage for AArch64 kernel.
          Uses TPIDR_EL1 (kernel-only TLS register).
*/

#ifndef ASM_TLS_H
#define ASM_TLS_H

#include <exec/types.h>

typedef struct tls
{
    struct ExecBase     *SysBase;
    void                *KernelBase;
    struct Task         *ThisTask;
    ULONG               ScheduleFlags;
    BYTE                IDNestCnt;
    BYTE                TDNestCnt;
    BYTE                SupervisorCount; /* >0 when in exception handler */
    BYTE                Pad0;
} tls_t;

#define TLSSF_Quantum   (1 << 0)
#define TLSSF_Switch    (1 << 1)
#define TLSSF_Dispatch  (1 << 2)

#define TLS_OFFSET(name) ((char *)&(((tls_t *)0)->name) - (char *)0)

/*
 * AArch64: Use TPIDR_EL1 for kernel TLS pointer.
 * This register is only accessible from EL1, so user tasks can't corrupt it.
 */
#define TLS_PTR_GET() \
    ({ \
        tls_t *__tls; \
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls)); \
        __tls; \
    })

#define TLS_GET(name) \
    ({ \
        tls_t *__tls; \
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls)); \
        typeof(__tls->name) __ret = (__tls->name); \
        __ret; \
    })

#define TLS_SET(name, val) \
    do { \
        tls_t *__tls; \
        __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls)); \
        (__tls->name) = val; \
    } while(0)

#endif /* ASM_TLS_H */
