# AROS AArch64 Porting Agent — Engineering Standards

You are working on porting AROS (Amiga Research Operating System) to AArch64 (ARM 64-bit) for Raspberry Pi 4 (BCM2711) and later Pi 5 (BCM2712). Circle SDK (`~/Source/circle`) serves as the primary hardware reference. Circle-derived code is ported to C with GPLv3 headers in separate files.

## Project Context

- AROS source: `~/Source/AROS`
- Circle SDK reference: `~/Source/circle`
- Target: Raspberry Pi 4 first (BCM2711, Cortex-A72), then Pi 5 (BCM2712, Cortex-A76)
- First milestone: Serial boot (kernel prints to UART)
- Final milestone: Full Workbench with keyboard/mouse/display
- Existing 32-bit ARM port in `arch/arm-native/` and `arch/arm-raspi/` must NOT be broken

## 1. Architecture Principles

### 1.1 Hardware Abstraction Layers (HAL)
- ALL hardware access MUST go through defined abstraction layers. NEVER access a peripheral register directly from kernel or exec code.
- Layer structure (bottom to top):
  1. **SoC driver** (e.g., `platform_bcm2711.c`) — register-level access, ONE file per SoC
  2. **Subsystem interface** (e.g., `AARCH64_Implementation` struct) — function pointers
  3. **Kernel consumer** (e.g., `kernel_startup.c`) — calls through interface ONLY
- A new SoC (Pi 5) MUST be addable by creating new SoC driver files and registering them via `ARMPLATFORMS` set — ZERO changes to kernel or exec code.
- When in doubt, look at how `arch/arm-native/kernel/platform_bcm2708.c` registers itself via `ADD2SET(bcm2708_probe, ARMPLATFORMS, 0)` and replicate that pattern.

### 1.2 Single Source of Truth (SSOT)
- Hardware addresses: defined ONCE in a SoC-specific header (e.g., `hardware/bcm2711.h`). Never duplicated. All consumers include the header.
- Memory map constants: defined ONCE in a `memorymap.h` per SoC variant.
- Configuration values (clock rates, timer intervals, stack sizes): defined ONCE in a config header, never as literals in code.
- If a value exists in an AROS header already, USE IT. Do not redefine.

### 1.3 DRY — Don't Repeat Yourself
- Before writing ANY function, search the existing AROS codebase for equivalent functionality. Use `grep` and `glob` to verify nothing exists already.
- Shared AArch64 code → `arch/aarch64-all/`
- SoC-specific code → `arch/aarch64-native/soc/broadcom/<chip>/`
- Boot code → `arch/aarch64-raspi/boot/`
- If code is needed by both Pi 4 and Pi 5: shared location, differences resolved through HAL function pointers or compile-time SoC identifier — NOT by duplicating files.
- Common patterns (register read/write with barriers, timeout loops, bit manipulation) MUST use shared macros/inline functions.

## 2. Coding Standards

### 2.1 AROS Conventions (for APL-licensed files)
- Follow existing AROS naming: `krnFunctionName` for kernel internals, `AROS_LH*`/`AROS_CALL*` macros for library functions.
- Use AROS types: `IPTR`, `APTR`, `ULONG`, `UBYTE`, `BOOL`, `TRUE`/`FALSE`.
- Use AROS debug macros: `D(bug(...))`, not `printf`/`kprintf` in kernel code.
- Include guards: `#ifndef FILENAME_H` / `#define FILENAME_H`.
- Copyright header on every file with correct year and "The AROS Development Team".

### 2.2 Circle-Ported Code (GPLv3-licensed files)
- GPLv3 header MUST reference Circle as origin:
  ```c
  /*
      Ported from Circle - A C++ bare metal environment for Raspberry Pi
      Copyright (C) <year> R. Stange <rsta2@o2online.de>
      Licensed under GPLv3

      Adapted for AROS by <contributor>, <year>
  */
  ```
- Translate C++ to C: classes become structs + function prefixes (e.g., `CInterruptSystem::Initialize()` → `gic400_Initialize(struct GIC400State *)`).
- Preserve Circle's logic structure and comments during port. Add AROS-specific comments where behavior differs.
- NEVER mix APL and GPLv3 code in the same file.

### 2.3 No Magic Numbers
- Every hardware register offset, bit mask, and constant MUST be a named `#define`.
- Format: `<SUBSYSTEM>_<REGISTER>_<FIELD>` (e.g., `GICD_CTLR_ENABLE`).
- Bit positions: use `(1 << n)` or `BIT(n)` macro, not hex literals for single bits.

### 2.4 No Hardcoded Addresses
- Peripheral base addresses come from device tree parsing or SoC header defines.
- Register access: `base + OFFSET` pattern, where `base` is resolved at runtime from the platform probe.
- NEVER: `*(volatile uint32_t *)0xFE201000 = value;`
- ALWAYS: `wr32(platform->uart_base + PL011_DR, value);`

### 2.5 Error Handling
- Every hardware initialization function MUST return a success/failure status.
- Timeout loops MUST have a bounded iteration count and return error on timeout. No infinite `while(1)` waiting for hardware.
  ```c
  /* WRONG */
  while (!(rd32(base + REG) & READY_BIT));

  /* RIGHT */
  int timeout;
  for (timeout = 10000; timeout > 0; timeout--) {
      if (rd32(base + REG) & READY_BIT) break;
  }
  if (timeout <= 0) {
      bug("[Module] ERROR: Timeout waiting for READY\n");
      return FALSE;
  }
  ```
- Memory allocations MUST be checked. `AllocMem` can return NULL.
- Failed hardware init MUST leave the system in a safe state (interrupts disabled, no half-initialized controllers).

### 2.6 Assembly Code
- Every assembly file MUST have a C-readable comment block explaining:
  - What CPU state is expected on entry
  - What registers are used and why
  - What state is guaranteed on exit
- Use `.macro` for repeated patterns. No copy-paste of instruction sequences.
- Callee-saved registers (x19-x30) MUST be preserved per AAPCS64.
- Stack MUST be 16-byte aligned at all times (AArch64 requirement).

## 3. Structural Rules

### 3.1 File Organization
- One concern per file. A GIC driver file does not also configure the timer.
- Maximum ~500 lines per C file. If larger, split by sub-concern.
- Header files expose the public interface ONLY. Internal helpers stay in the `.c` file or a `*_intern.h`.
- `mmakefile.src` for every directory. No orphan source files.

### 3.2 Build System Integration
- New directories MUST be wired into the mmake dependency tree.
- Use existing AROS build macros (`%build_module`, `%build_archspecific`, etc.).
- Architecture selection via `$(AROS_TARGET_CPU)` guards in mmakefiles.
- Every new module MUST build cleanly with `-Wall -Werror` (no warnings).

### 3.3 Commit Granularity
- Each task from the plan = one logical unit of work.
- Within a task, each file or closely related group of files = one commit.
- Commit message format: `[aarch64] <subsystem>: <what changed>`
  Example: `[aarch64] kernel: Add GIC-400 interrupt controller driver`
- No "WIP", "fix", "temp" commits. Every commit must compile.

## 4. Testing Requirements

### 4.1 Build Verification
- After every task: full `make` must succeed with zero warnings.
- Cross-compilation from the host to aarch64 must work.

### 4.2 Runtime Verification
- Each task specifies a "Demo" — that demo MUST be verified before moving on.
- QEMU `raspi4b` machine for tasks that support it (boot, kernel init, timer).
- Real hardware verification required for: USB, SD card, framebuffer, Pi 5.

### 4.3 Regression
- Existing ARM 32-bit raspi build (`--target=raspi-armhf`) MUST NOT be broken.
- Existing x86_64 and i386 builds MUST NOT be broken.

## 5. Anti-Patterns — Explicitly Forbidden

You MUST NOT use any of these patterns. If you find yourself reaching for one, stop and find the proper solution.

| Anti-Pattern | Why | Do This Instead |
|---|---|---|
| `#ifdef RASPPI_4` scattered through shared code | Couples shared code to specific hardware | Use HAL function pointers registered via ARMPLATFORMS |
| Copying an entire file and modifying for new SoC | Violates DRY, maintenance nightmare | Factor out common code, parameterize differences |
| `TODO` / `FIXME` / `HACK` without a plan | Accumulates tech debt silently | Fix it now, or document the issue with full rationale |
| Disabling interrupts "temporarily" without re-enabling | System hangs | Use paired `Disable()`/`Enable()` in same function scope |
| Global mutable state without synchronization | Race conditions in SMP | All shared state protected by spinlocks from day one |
| Polling in a tight loop without yield or timeout | Burns CPU, blocks other tasks | Use interrupt-driven I/O or bounded timeout loops |
| Casting away `const` or `volatile` | Hides bugs, confuses optimizer | Fix the type signature instead |
| Platform-specific code in `rom/` directories | Breaks other architectures | Platform code goes in `arch/` only |
| Inline assembly without register clobber lists | Silent register corruption | Always specify all clobbered registers |
| `#pragma once` | Not portable across all AROS toolchains | Use `#ifndef`/`#define` include guards |
| Assuming pointer size = 4 or 8 | Breaks portability | Use `IPTR`/`APTR` and `sizeof()` |
| Allocating large buffers on the stack | Stack overflow on small kernel stacks | Use `AllocMem()` for buffers > 256 bytes |
| Ignoring return values from hardware init | Silent failures cascade | Check and handle every return value |
| Writing "clever" code | Unmaintainable | Write obvious, readable code with comments |

## 6. Decision Log

When making architectural decisions, document them as comments in the relevant header file:
```c
/*
 * DECISION: We use 64KB MMU granule (not 4KB) because:
 * - Circle uses 64KB granule and it's tested on Pi 4/5
 * - Reduces TLB pressure for our workload
 * - Simpler page table structure (2 levels vs 4)
 * Date: YYYY-MM-DD
 */
```

## 7. Reference Lookup Protocol

Before implementing any hardware interaction:
1. Check Circle source (`~/Source/circle/lib/` and `~/Source/circle/include/circle/`) for the reference implementation
2. Check existing AROS ARM code (`arch/arm-native/`, `arch/arm-raspi/`) for the AROS integration pattern
3. Check the BCM2711/BCM2712 datasheet values against Circle's defines
4. Only then write the AROS implementation, following both references
