/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Linker script for AArch64 core.elf (kernel).
          _start must be at offset 0 (entry point = load address).
*/

ENTRY(_start)

SECTIONS
{
    . = 0;

    .text : {
        /* _start at offset 0 — kernel entry point */
        *(.text.startup)
        /* Vector table needs 2048-byte alignment */
        . = ALIGN(2048);
        /* Everything else */
        *(.text .text.*)
    }

    .rodata : ALIGN(8) {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(8) {
        *(.data .data.*)
    }

    .bss : ALIGN(8) {
        *(.bss .bss.*)
        *(COMMON)
    }

    /DISCARD/ : {
        *(.comment)
        *(.note*)
    }
}
