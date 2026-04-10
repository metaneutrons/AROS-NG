/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
*/

#ifndef BOOT_H_
#define BOOT_H_

#include <inttypes.h>
#include <sys/types.h>
#include <aros/kernel.h>

#define BOOT_STACK_SIZE     (768 << 2)
#define BOOT_TAGS_SIZE      (128 << 3)
#define BOOT_TMP_SIZE       524288

#define MAX_BSS_SECTIONS    256

void mem_init(void);
void explicit_mem_init(void *, unsigned long);
size_t mem_avail(void);
size_t mem_used(void);
const char *remove_path(const char *in);
void aarch64_flush_cache(uintptr_t addr, uintptr_t length);
void aarch64_icache_invalidate(uintptr_t addr, uintptr_t length);

extern uint8_t __bootstrap_start;
extern uint8_t __bootstrap_end;

extern void *_binary_core_bin_start;
extern long *_binary_core_bin_end;
extern long _binary_core_bin_size;

void kprintf(const char *format, ...);

#endif /* BOOT_H_ */
