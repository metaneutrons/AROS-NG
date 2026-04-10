/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Serial debug output for AArch64 Raspberry Pi bootstrap
*/

#ifndef SERIALDEBUG_H
#define SERIALDEBUG_H

#include <stdint.h>

void serInit(void);
void putByte(uint8_t chr);
void putBytes(const char *str);
void kprintf(const char *format, ...);

#endif /* SERIALDEBUG_H */
