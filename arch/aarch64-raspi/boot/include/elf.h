/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
*/

#ifndef ELF_H_
#define ELF_H_

#include <inttypes.h>

struct bss_tracker {
    void *addr;
    uint64_t length;
};

extern struct bss_tracker tracker[];

int getElfSize(void *elf_file, uint64_t *size_rw, uint64_t *size_ro);
void initAllocator(uintptr_t addr_ro, uintptr_t addr_rw, uintptr_t virtoffset);
uintptr_t loadElf(void *elf_file);

#define ELF64_R_SYM(val)   ((val) >> 32)
#define ELF64_R_TYPE(val)   ((val) & 0xffffffffUL)

#endif /* ELF_H_ */
