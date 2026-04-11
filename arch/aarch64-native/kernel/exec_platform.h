/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: exec_platform.h for AArch64 native.
          TLS accessed via TPIDR_EL1 system register.
*/
#ifndef __EXEC_PLATFORM_H
#define __EXEC_PLATFORM_H

#include <aros/config.h>
#include <aros/atomic.h>

#include "tls.h"

#define SCHEDQUANTUM_VALUE      4

struct Exec_PlatformData
{
    /* No platform-specific data by default */
};

/* TLS access via TPIDR_EL1 */
#define __GET_TLS() \
    ({ tls_t *__tls; __asm__ volatile("mrs %0, tpidr_el1" : "=r"(__tls)); __tls; })

#define IDNESTCOUNT_INC     do { __GET_TLS()->IDNestCnt++; } while(0)
#define IDNESTCOUNT_DEC     do { __GET_TLS()->IDNestCnt--; } while(0)
#define TDNESTCOUNT_INC     do { __GET_TLS()->TDNestCnt++; } while(0)
#define TDNESTCOUNT_DEC     do { __GET_TLS()->TDNestCnt--; } while(0)

#define IDNESTCOUNT_GET     ({ __GET_TLS()->IDNestCnt; })
#define IDNESTCOUNT_SET(val) do { __GET_TLS()->IDNestCnt = (val); } while(0)
#define TDNESTCOUNT_GET     ({ __GET_TLS()->TDNestCnt; })
#define TDNESTCOUNT_SET(val) do { __GET_TLS()->TDNestCnt = (val); } while(0)

#define FLAG_SCHEDQUANTUM_CLEAR  do { AROS_ATOMIC_AND(__GET_TLS()->ScheduleFlags, ~TLSSF_Quantum); } while(0)
#define FLAG_SCHEDQUANTUM_SET    do { AROS_ATOMIC_OR(__GET_TLS()->ScheduleFlags, TLSSF_Quantum); } while(0)
#define FLAG_SCHEDSWITCH_CLEAR   do { AROS_ATOMIC_AND(__GET_TLS()->ScheduleFlags, ~TLSSF_Switch); } while(0)
#define FLAG_SCHEDSWITCH_SET     do { AROS_ATOMIC_OR(__GET_TLS()->ScheduleFlags, TLSSF_Switch); } while(0)
#define FLAG_SCHEDDISPATCH_CLEAR do { AROS_ATOMIC_AND(__GET_TLS()->ScheduleFlags, ~TLSSF_Dispatch); } while(0)
#define FLAG_SCHEDDISPATCH_SET   do { AROS_ATOMIC_OR(__GET_TLS()->ScheduleFlags, TLSSF_Dispatch); } while(0)

#define FLAG_SCHEDQUANTUM_ISSET  ({ (__GET_TLS()->ScheduleFlags & TLSSF_Quantum) ? TRUE : FALSE; })
#define FLAG_SCHEDSWITCH_ISSET   ({ (__GET_TLS()->ScheduleFlags & TLSSF_Switch) ? TRUE : FALSE; })
#define FLAG_SCHEDDISPATCH_ISSET ({ (__GET_TLS()->ScheduleFlags & TLSSF_Dispatch) ? TRUE : FALSE; })

#define GET_THIS_TASK           TLS_GET(ThisTask)
#define SET_THIS_TASK(x)        TLS_SET(ThisTask,(x))

#define SCHEDQUANTUM_SET(val)   (SysBase->Quantum=(val))
#define SCHEDQUANTUM_GET        (SysBase->Quantum)
#define SCHEDELAPSED_SET(val)   (SysBase->Elapsed=(val))
#define SCHEDELAPSED_GET        (SysBase->Elapsed)

#endif /* __EXEC_PLATFORM_H */
