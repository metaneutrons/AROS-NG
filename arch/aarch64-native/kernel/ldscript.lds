/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Linker script for AArch64 core.elf (kernel).
          Loaded by bootstrap at runtime address.
          _start must be at offset 0 (entry point = load address).
*/

ENTRY(_start)

SECTIONS
{
    . = 0;

    .text : {
        /* kernel_cstart.o first — _start at offset 0 */
        *kernel_cstart.o(.text .text.*)
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
