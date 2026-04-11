---
name: aarch64-implementation-plan
description: Master implementation plan for AROS AArch64 port to Raspberry Pi 4/5. Consult when starting any task, checking dependencies, or reviewing progress.
---

# AROS AArch64 Implementation Plan

## Overview

Port AROS to AArch64 on Raspberry Pi 4 (BCM2711), then extend to Pi 5 (BCM2712).
Circle SDK (`~/Source/circle`) is the primary hardware reference.
Circle-derived code is ported to C with GPLv3 headers in separate files.

## Directory Structure

```
arch/
  aarch64-all/              # CPU-level: headers, exec stubs, setjmp, genmodule
    include/aros/           # cpu.h (fixed), genmodule.h (new), cpucontext.h
    exec/                   # execstubs.S, preparecontext.c, stackswap.S, newstackswap.c
    stdc/                   # setjmp.S, longjmp.S, fenv.c
    posixc/                 # sigsetjmp.S, siglongjmp.S, vfork.S
    kernel/                 # createcontext.c
  aarch64-raspi/            # Bootstrap (replaces arm-raspi for 64-bit)
    boot/                   # boot.c, startup64.S, mmu.c, serialdebug.c, elf.c, devicetree.c
  aarch64-native/           # Kernel + SoC drivers
    kernel/                 # kernel_startup.c, kernel_cpu.c, intr.c, syscall.c, mmu.c
                            # platform_init.c, platform_bcm2711.c, platform_bcm2712.c
    exec/                   # platform_init.c, coldreboot.c, cachecleare.c, superstate.c
    soc/broadcom/2711/      # GIC-400, EMMC2, xHCI USB (GPLv3)
    soc/broadcom/2712/      # RP1 southbridge, PCIe bridge (GPLv3)
```

## Phase 1 — AArch64 Core (Pi 4 serial boot)

### Task 1: Fix AArch64 core headers and build system
- **Status**: DONE
- **Commits**: `e86bed3c16` through `02336f5b62` (crosstools), `aa38bffce8`, `f3500b486f` (build fixes)

### Task 2: AArch64 genmodule.h — library call stubs
- **Status**: DONE (created in initial commit `18e687c19a`)

### Task 3: AArch64 exec core — context switching and stack swap
- **Status**: DONE (created in initial commit `18e687c19a`)

### Task 4: AArch64 setjmp/longjmp and POSIX signal variants
- **Status**: DONE (created in initial commit `18e687c19a`)

### Task 5: AArch64 bootstrap — serial boot on Pi 4
- **Status**: DONE — full bootstrap→kernel handoff working on QEMU raspi4b
- **Commits**: `c7aafea7e8` (initial), `4deed75977` (DTB fix), `5413b8f6f1` (MMU), `948227007a` (alignment fix), `6c706da9a0` (kernel handoff)
- **What works**: EL2→EL1, UART, DTB parsing, memory detection, SoC detection, MMU enable, ELF loading with RELA relocations, kernel entry
- **Key bugs found**: Embedded ELF must be 8-byte aligned (use .incbin with .balign 8, not --format binary). Entry point must be first function in .text.
- **QEMU command**: `qemu-system-aarch64 -M raspi4b -m 2G -serial stdio -display none -dtb bcm2711-rpi-4-b.dtb -kernel aros-aarch64-raspi.img`

### Task 6: AArch64 kernel startup — exec initialization
- **Status**: DONE — exec.library alive, SysBase created, InitCode runs
- **Commits**: `b81d67c98e` (initial), `44c0bc917f` (kobjs link), `1782dcb351` (BSS fix), `0d5e60ddd6` (exec init)
- **What works**: Tag parsing, TLS via TPIDR_EL1, VBAR_EL1 exception vectors, CPU probe (Cortex-A72), BSS clearing, TLSF memory (955MB), krnPrepareExecBase, InitCode(RTF_SINGLETASK + RTF_COLDSTART), kernel.resource + task.resource initialized
- **Key bugs found**: 1) Stack was in .bss — clear_bss destroyed it (fix: section(".data")). 2) GOT relocations in bootstrap ELF loader treated as direct refs — needed actual GOT slot allocation. 3) `__aros_libreq_SysBase` GOT-indirect load crashed Task_InitLib.
- **Objective**: Kernel starts, initializes exec.library, reaches idle loop.
- **Work**:
  - `arch/aarch64-native/kernel/kernel_startup.c` — entry, BSS clear, exception stacks, CPU probe, platform init, SysBase, memory pools, resident scan
  - `arch/aarch64-native/kernel/kernel_cpu.c` — MIDR_EL1 identification, cache ops
  - `arch/aarch64-native/kernel/kernel_intern.h` — AARCH64_Implementation struct
  - `arch/aarch64-native/kernel/intvecs.S` — VBAR_EL1 vector table (from Circle `exceptionstub64.S`, GPLv3)
  - `arch/aarch64-native/kernel/syscall.c` — SVC handler
  - `arch/aarch64-native/kernel/mmu.c` — runtime MMU management
  - `arch/aarch64-native/exec/platform_init.c`, `coldreboot.c`, `superstate.c`, `userstate.c`, `cachecleare.c`, `exec_idle.c`
- **Reference**: `arch/arm-native/kernel/kernel_startup.c`, Circle `exceptionstub64.S`
- **Demo**: Serial shows exec init, memory pools, resident scan, idle task
- **Depends on**: Task 5

## Phase 2 — Interrupts, Display, Input (Pi 4 Workbench)

### Task 7: GIC-400 interrupt controller and ARM Generic Timer
- **Status**: DONE — GIC-400 + CNTP timer firing at 50Hz, core_Cause(INTB_VERTB) working
- **Commit**: `cdd3609827`
- **What works**: GIC-400 init (GICD 0xFF841000, GICC 0xFF842000), 256 IRQ lines, timer PPI 14 at 50Hz, IRQ dispatch via intvecs.S → gic400_HandleIRQ, VBlank signal to exec
- **New files**: kernel_arch.h (IRQ_COUNT), kernel_cpu.h (regs_t, GetCPUNumber), exec_platform.h (TLS macros via TPIDR_EL1)
- **Objective**: Working interrupts and 50Hz timer tick on Pi 4.
- **Work**:
  - `arch/aarch64-native/soc/broadcom/2711/gic400.c` — GIC-400 driver (from Circle `interruptgic.cpp`, GPLv3). GICD `0xFF841000`, GICC `0xFF842000`.
  - `arch/aarch64-native/kernel/kernel_systimer.c` — ARM Generic Timer (CNTPCT_EL0, CNTP_CTL_EL0)
  - `arch/aarch64-native/kernel/platform_bcm2711.c` — platform probe, register GIC + timer (GPLv3)
  - `arch/aarch64-native/kernel/kernel_scheduler.c` — task scheduling on timer IRQ
- **Reference**: Circle `interruptgic.cpp`, `timer.cpp`, `multicore.cpp`
- **Demo**: Timer ticks on serial, task switching works
- **Depends on**: Task 6

### Task 8: Framebuffer and boot console
- **Status**: NOT STARTED
- **Objective**: Visual output on HDMI.
- **Work**:
  - VideoCore mailbox framebuffer at `0xFE00B880` (same API as Pi 1-3)
  - Framebuffer HIDD for AArch64-native (adapt `vc4gfx` from `arch/arm-native/soc/broadcom/2708/hidd/vc4gfx/`)
  - Boot console text mode on framebuffer
- **Demo**: AROS boot messages on HDMI display
- **Depends on**: Task 7

### Task 9: USB HID — keyboard and mouse via xHCI
- **Status**: NOT STARTED
- **Objective**: User input working.
- **Work**:
  - xHCI HCD for Poseidon USB stack (from Circle `lib/usb/xhci*.cpp`, GPLv3). Pi 4 xHCI at `0xFE9C0000`.
  - Ring management, slot manager, root hub, endpoint management, DMA allocator
  - Wire existing Poseidon HID class drivers (hub, bootkeyboard, bootmouse)
- **Reference**: Circle `lib/usb/xhci*.cpp` (11 files)
- **Demo**: USB keyboard types, USB mouse moves pointer
- **Depends on**: Task 7

### Task 10: SD card, DOS, and Workbench boot
- **Status**: NOT STARTED
- **Objective**: Full AROS Workbench on Pi 4.
- **Work**:
  - SD card driver for EMMC2 (`0xFE340000`, SDHCI-compatible)
  - FAT filesystem handler (arch-independent, should work)
  - Boot DOS, mount SD as DH0:, load Workbench startup-sequence
  - Verify Intuition, graphics, layers, gadtools
- **Demo**: AROS Workbench desktop, interactive with USB keyboard/mouse
- **Depends on**: Tasks 8, 9

## Phase 3 — Raspberry Pi 5

### Task 11: Pi 5 — PCIe and RP1 southbridge
- **Status**: NOT STARTED
- **Objective**: Pi 5 boots to serial.
- **Work**:
  - `bcmpciehostbridge.c` — PCIe host bridge for BCM2712 (from Circle, GPLv3)
  - `southbridge.c` — RP1 enumeration, second-level interrupt controller (from Circle, GPLv3)
  - `platform_bcm2712.c` — platform probe, peripheral base `0x107C000000`, GIC at different address (GPLv3)
  - MMU tables for 40-bit address space (AXI `0x1000000000`, PCIe `0x1F00000000`)
  - Bootstrap Pi 4/5 detection from device tree
- **Reference**: Circle `bcmpciehostbridge.cpp`, `southbridge.cpp`, `bcm2712.h`
- **Demo**: AROS boot messages on Pi 5 serial
- **Depends on**: Task 7

### Task 12: Pi 5 — USB, SD, GPIO via RP1
- **Status**: NOT STARTED
- **Objective**: Full peripherals on Pi 5.
- **Work**:
  - xHCI via RP1 PCIe (different base address routing)
  - SD card via RP1
  - GPIO: `gpiopin2712.c`, `gpiomanager2712.c` (from Circle, GPLv3)
  - I2C/SPI: `i2cmaster-rp1.c`, `spimaster-rp1.c` (from Circle, GPLv3)
- **Demo**: Full Workbench on Pi 5
- **Depends on**: Tasks 10, 11

### Task 13: SMP — multi-core support
- **Status**: NOT STARTED
- **Objective**: All 4 CPU cores active on Pi 4 and Pi 5.
- **Work**:
  - PSCI CPU_ON via `SMC #0` (function `0xC4000003`) (from Circle `multicore.cpp`, GPLv3)
  - Pi 4: Aff0 for core ID. Pi 5: Aff1 (Cortex-A76)
  - Secondary core startup: exception stack, TLS, VBAR_EL1
  - AROS exec SMP: per-core scheduling, IPI via GIC SGI, spinlock-protected shared state
- **Reference**: Circle `multicore.cpp`, `startup64.S` `_start_secondary`
- **Demo**: SysExplorer shows 4 cores, tasks on different cores
- **Depends on**: Task 7
