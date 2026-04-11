/*
    Copyright (C) 2013-2026, The AROS Development Team. All rights reserved.

    Desc: VideoCore mailbox resource for BCM2711 (AArch64).
          Ported from arch/arm-native/soc/broadcom/2708/mbox/mbox_init.c.
*/

#define DEBUG 0

#include <aros/macros.h>
#include <aros/debug.h>
#include <aros/symbolsets.h>
#include <aros/libcall.h>
#include <proto/kernel.h>
#include <proto/exec.h>
#include <proto/mbox.h>

#include <asm/cpu.h>

#include "mbox_private.h"

/* BCM2711 mailbox registers */
#define VCMB_READ       0x00
#define VCMB_STATUS     0x18
#define VCMB_WRITE      0x20
#define VCMB_STATUS_READREADY   (1u << 30)
#define VCMB_STATUS_WRITEREADY  (1u << 31)
#define VCMB_CHAN_MAX   8
#define VCMB_CHAN_MASK  0xF

static int mbox_init(struct MBoxBase *MBoxBase)
{
    D(bug("[MBox] mbox_init()\n"));
    InitSemaphore(&MBoxBase->mbox_Sem);
    return TRUE;
}

AROS_LH1(unsigned int, MBoxStatus,
                AROS_LHA(void *, mb, A0),
                struct MBoxBase *, MBoxBase, 1, Mbox)
{
    AROS_LIBFUNC_INIT
    return AROS_LE2LONG(*((volatile unsigned int *)((IPTR)mb + VCMB_STATUS)));
    AROS_LIBFUNC_EXIT
}

AROS_LH2(volatile unsigned int *, MBoxRead,
                AROS_LHA(void *, mb, A0),
                AROS_LHA( unsigned int, chan, D0),
                struct MBoxBase *, MBoxBase, 2, Mbox)
{
    AROS_LIBFUNC_INIT

    unsigned int try = 0x2000000;
    unsigned int msg;

    if (chan <= VCMB_CHAN_MAX)
    {
        while(1)
        {
            ObtainSemaphore(&MBoxBase->mbox_Sem);

            while ((MBoxStatus(mb) & VCMB_STATUS_READREADY) != 0)
            {
                dsb();
                if(try-- == 0) break;
            }
            dmb();

            msg = AROS_LE2LONG(*((volatile unsigned int *)((IPTR)mb + VCMB_READ)));

            dmb();

            ReleaseSemaphore(&MBoxBase->mbox_Sem);

            if ((msg & VCMB_CHAN_MASK) == chan)
            {
                uint32_t *addr = (uint32_t *)(IPTR)(msg & ~VCMB_CHAN_MASK);
                uint32_t len = AROS_LE2LONG(addr[0]);

                CacheClearE(addr, len, CACRF_InvalidateD);

                return (volatile unsigned int *)(addr);
            }
        }
    }
    return (volatile unsigned int *)(IPTR)-1;

    AROS_LIBFUNC_EXIT
}

AROS_LH3(void, MBoxWrite,
                AROS_LHA(void *, mb, A0),
                AROS_LHA( unsigned int, chan, D0),
                AROS_LHA(void *, msg, A1),
                struct MBoxBase *, MBoxBase, 3, Mbox)
{
    AROS_LIBFUNC_INIT

    if ((((IPTR)msg & VCMB_CHAN_MASK) == 0) && (chan <= VCMB_CHAN_MAX))
    {
        ULONG length = AROS_LE2LONG(((ULONG *)msg)[0]);

        void *phys_addr = CachePreDMA(msg, &length, DMA_ReadFromRAM);

        ObtainSemaphore(&MBoxBase->mbox_Sem);

        while ((MBoxStatus(mb) & VCMB_STATUS_WRITEREADY) != 0)
            dsb();

        dmb();

        *((volatile unsigned int *)((IPTR)mb + VCMB_WRITE)) =
            AROS_LONG2LE(((unsigned int)(IPTR)phys_addr | chan));

        ReleaseSemaphore(&MBoxBase->mbox_Sem);
    }

    AROS_LIBFUNC_EXIT
}

ADD2INITLIB(mbox_init, 0)
