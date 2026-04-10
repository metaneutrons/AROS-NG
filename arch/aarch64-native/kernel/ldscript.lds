/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Linker script for AArch64 core.elf (kernel).
          Loaded by bootstrap at runtime address determined by memory layout.
*/

ENTRY(_start)

SECTIONS
{
    . = 0;

    .text.startup : {
        *(.text.startup)
    }

    .text : {
        *(.text .text.*)
    }

    .rodata : {
        *(.rodata .rodata.*)
    }

    .data : {
        *(.data .data.*)
    }

    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    }

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
