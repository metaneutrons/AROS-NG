/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: AArch64 MMU setup for bootstrap (64KB granule, identity-mapped).
*/

#ifndef _MMU_H_
#define _MMU_H_

#include <stdint.h>

void mmu_init(void);
void mmu_map(uint64_t phys, uint64_t size, int is_device);
void mmu_unmap(uint64_t phys, uint64_t size);
void mmu_load(void);

#endif /* _MMU_H_ */
