/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 platform probe framework.
          Iterates registered platform probes to find matching SoC.
          Follows the same pattern as arch/arm-native/kernel/platform_init.c.
*/

#include "kernel_intern.h"

/*
 * Platform probe function type.
 * Returns non-zero if this platform matches.
 */
typedef int (*platform_probe_func)(struct AARCH64_Implementation *, struct TagItem *);

extern int bcm2711_probe(struct AARCH64_Implementation *impl, struct TagItem *msg);

/*
 * Platform probe table — populated by platform_bcm2711.c, platform_bcm2712.c etc.
 * Each platform file adds itself via a constructor or explicit registration.
 *
 * For now, we use a simple static table. When the full AROS build system
 * is integrated, this will use DECLARESET(ARMPLATFORMS) / ADD2SET().
 */
static platform_probe_func platform_probes[] = {
    bcm2711_probe,
    /* bcm2712_probe will be added for Pi 5 (Task 11) */
    (platform_probe_func)0    /* terminator */
};

void platform_Init(struct AARCH64_Implementation *impl, struct TagItem *msg)
{
    int i;
    for (i = 0; platform_probes[i]; i++)
    {
        if (platform_probes[i](impl, msg))
            return;
    }
}
