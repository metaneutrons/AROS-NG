/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: cpu_SuperState() — AArch64 version.
          On AArch64 native, we always run in EL1 (supervisor).
          SuperState() returns the current stack pointer.
*/

#include <proto/exec.h>

IPTR cpu_SuperState(void)
{
    register IPTR sp __asm__("sp");
    return sp;
}
