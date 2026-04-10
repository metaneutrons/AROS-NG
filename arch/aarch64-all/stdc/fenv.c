/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Floating-point environment, AArch64 version
    Lang: english
*/

#include <fenv.h>

/*
 * Default floating-point environment.
 * AArch64 FPCR default: round-to-nearest, no exceptions enabled.
 */
const fenv_t __fe_dfl_env = 0;
