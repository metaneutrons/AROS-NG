/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.

    Desc: Linker script for AArch64 Raspberry Pi bootstrap image.
          Kernel is loaded at 0x80000 by the Pi firmware.
*/

ENTRY(_start)

SECTIONS
{
    . = 0x80000;

    __bootstrap_start = .;

    .aros.startup : {
        *(.aros.startup)
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

    . = ALIGN(16);
    __bss_start = .;
    .bss : {
        *(.bss .bss.*)
        *(COMMON)
    }
    . = ALIGN(16);
    __bss_end = .;

    __bootstrap_end = .;

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
    }
}
