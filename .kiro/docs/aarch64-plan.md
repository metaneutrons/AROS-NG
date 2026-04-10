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
- **Status**: NOT STARTED
- **Objective**: `configure --target=raspi-aarch64` completes, build starts.
- **Work**:
  - Fix `arch/aarch64-all/include/aros/cpu.h`: replace ARM32 FullJumpVec (`0xe51ff004`) with AArch64 (`ldr x16, .+8; br x16`)
  - Update `configure.in` aarch64 raspi case: `cortex-a72` tuning for Pi 4
  - Create directory skeleton + minimal `mmakefile.src` files
- **Demo**: `./configure --target=raspi-aarch64` succeeds
- **Depends on**: nothing

### Task 2: AArch64 genmodule.h — library call stubs
- **Status**: NOT STARTED
- **Objective**: AROS libraries compile for AArch64.
- **Work**:
  - Create `arch/aarch64-all/include/aros/genmodule.h`
  - Implement `AROS_GM_LIBFUNCSTUB` using `ldr x16, [x12, #offset]; br x16`
  - Implement `AROS_GM_RELLIBFUNCSTUB`, `AROS_GM_STACKCALL`, `AROS_GM_STACKALIAS`
- **Reference**: `arch/arm-all/include/aros/genmodule.h` (adapt inline asm to AArch64)
- **Demo**: Library stubs disassemble correctly via `objdump -d`
- **Depends on**: Task 1

### Task 3: AArch64 exec core — context switching and stack swap
- **Status**: NOT STARTED
- **Objective**: Exec can switch between tasks on AArch64.
- **Work**:
  - `arch/aarch64-all/exec/execstubs.S` — SVC entry/exit, library call wrappers
  - `arch/aarch64-all/exec/preparecontext.c` — init task register context
  - `arch/aarch64-all/exec/stackswap.S` — save x19-x30/sp, switch, restore
  - `arch/aarch64-all/exec/newstackswap.c`, `alert_cpu.c`
  - Update `cpucontext.h` if VFP/NEON state fields needed
- **Reference**: `arch/arm-all/exec/`, Circle `setjmp.S` for register list
- **Demo**: Object files compile and link without errors
- **Depends on**: Task 1

### Task 4: AArch64 setjmp/longjmp and POSIX signal variants
- **Status**: NOT STARTED
- **Objective**: C runtime support for AROS libraries and applications.
- **Work**:
  - `arch/aarch64-all/stdc/setjmp.S`, `longjmp.S` (x19-x30, sp)
  - `arch/aarch64-all/stdc/fenv.c` (FPCR/FPSR)
  - `arch/aarch64-all/posixc/sigsetjmp.S`, `siglongjmp.S`, `vfork.S`, `vfork_longjmp.S`
- **Reference**: Circle `setjmp.S` AArch64 section
- **Demo**: stdc and posixc libraries build for aarch64
- **Depends on**: Task 1

### Task 5: AArch64 bootstrap — serial boot on Pi 4
- **Status**: NOT STARTED
- **Objective**: Bootable `aros-aarch64-raspi.img` prints to UART on Pi 4.
- **Work**:
  - `arch/aarch64-raspi/boot/startup64.S` — EL2→EL1, VBAR, stack (from Circle `startup64.S`, GPLv3)
  - `arch/aarch64-raspi/boot/mmu.c` — AArch64 page tables, 64KB granule (from Circle `translationtable64.cpp`, GPLv3)
  - `arch/aarch64-raspi/boot/serialdebug.c` — PL011 UART at `0xFE201000`
  - `arch/aarch64-raspi/boot/boot.c` — device tree, memory query, load core.elf, jump to kernel
  - `arch/aarch64-raspi/boot/elf.c` — ELF64 loader (`EM_AARCH64`)
  - `arch/aarch64-raspi/boot/devicetree.c`, `vc_mb.c`, `vc_fb.c`, `kprintf.c`, `support.c`
  - `arch/aarch64-raspi/boot/ldscript.lds`, `mmakefile.src`
  - `boot/config.txt`: `arm_64bit=1`, `kernel=aros-aarch64-raspi.img`, `enable_uart=1`
- **Reference**: Circle `startup64.S`, `translationtable64.cpp`; AROS `arch/arm-raspi/boot/`
- **Demo**: Serial console shows AROS bootstrap messages on Pi 4 / QEMU
- **Depends on**: Tasks 1-4

### Task 6: AArch64 kernel startup — exec initialization
- **Status**: NOT STARTED
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
- **Status**: NOT STARTED
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
