/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Bootstrap support functions for AArch64 Raspberry Pi.
*/

#include "boot.h"
#include <sys/types.h>

static unsigned char __tmpspace[BOOT_TMP_SIZE];
static unsigned char *first_free;
static unsigned long free_memory;

void aarch64_flush_cache(uintptr_t addr, uintptr_t length)
{
    uintptr_t end = addr + length;
    addr &= ~63UL;
    while (addr < end)
    {
        __asm__ volatile("dc civac, %0" : : "r"(addr));
        addr += 64;
    }
    __asm__ volatile("dsb sy" ::: "memory");
}

void aarch64_icache_invalidate(uintptr_t addr, uintptr_t length)
{
    uintptr_t end = addr + length;
    addr &= ~63UL;
    while (addr < end)
    {
        __asm__ volatile("ic ivau, %0" : : "r"(addr));
        addr += 64;
    }
    __asm__ volatile("dsb ish; isb" ::: "memory");
}

void *malloc(size_t size)
{
    void *ret = (void *)0;

    size = (size + 15) & ~15;

    if (size <= free_memory)
    {
        ret = first_free;
        first_free += size;
        free_memory -= size;
    }

    if (!ret)
        kprintf("[BOOT] malloc - OUT OF MEMORY\n");

    return ret;
}

void mem_init(void)
{
    first_free = &__tmpspace[0];
    free_memory = BOOT_TMP_SIZE;
}

void explicit_mem_init(void *first, unsigned long free)
{
    first_free = first;
    free_memory = free;
}

size_t mem_avail(void)
{
    return free_memory;
}

size_t mem_used(void)
{
    return BOOT_TMP_SIZE - free_memory;
}

int32_t strlen(const char *c)
{
    int32_t result = 0;
    while (*c++)
        result++;
    return result;
}

const char *remove_path(const char *in)
{
    const char *p = &in[strlen(in) - 1];
    while (p > in && p[-1] != '/' && p[-1] != ':') p--;
    return p;
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b) { a++; b++; }
    return *(unsigned char *)a - *(unsigned char *)b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    while (n && *a && *a == *b) { a++; b++; n--; }
    return n ? *(unsigned char *)a - *(unsigned char *)b : 0;
}

void *memcpy(void *dest, const void *src, size_t n)
{
    char *d = dest;
    const char *s = src;
    while (n--) *d++ = *s++;
    return dest;
}

void *memset(void *s, int c, size_t n)
{
    unsigned char *p = s;
    while (n--) *p++ = (unsigned char)c;
    return s;
}

void bzero(void *s, size_t n)
{
    memset(s, 0, n);
}
