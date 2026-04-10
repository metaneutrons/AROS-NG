---
name: aros-codebase-issues
description: Bugs and issues found in the AROS codebase during AArch64 porting. Some are fixed, some need attention for ARM32 or other architectures.
---

# AROS Codebase Issues Found During AArch64 Port

## Fixed Issues

### 1. `va_arg(args, STACKED LONG)` — undefined behavior (all architectures)
- **File**: `developer/debug/test/library/dummylib.c:55`
- **Problem**: `STACKED` expands to `__attribute__((aligned(8)))` on AArch64/x86_64. Using an aligned type in `va_arg` is undefined behavior per C standard. Clang warns; GCC 15.2.0 AArch64 triggers an ICE.
- **Fix**: Removed `STACKED` from `va_arg` call. This was the only occurrence in the entire codebase.
- **Impact**: Affects all architectures where `STACKED` is non-trivial (aarch64, x86_64).
- **Commit**: `6ec2b6fae3`

### 2. ARM32 inline asm in architecture-shared code
- **File**: `arch/arm-native/soc/broadcom/2708/hidd/i2c/i2c-bcm2708.c`
- **Problem**: `asm volatile ("mov r2,r2\n")` is ARM32-only. This code gets compiled for AArch64 too because `arch/arm-native/` is pulled into `raspi-aarch64` builds via the `%build_module` dependency chain (`hidd-i2c` → `hidd-i2c-$(ARCH)` → `hidd-i2c-raspi` → `hidd-i2c-bcm2708`).
- **Fix**: Replaced with `asm volatile ("" ::: "memory")` — architecture-neutral compiler barrier.
- **Lesson**: Any code in `arch/arm-native/` that uses ARM32 asm will break AArch64 builds because `$(ARCH)=raspi` is shared.
- **Commit**: `dc0e283476`

### 3. AROSTCP `va_list` handling missing AArch64
- **Files**: `workbench/network/stacks/AROSTCP/bsdsocket/api/amiga_generic2.c`, `kern/subr_prf.c`
- **Problem**: `va_set()` macro and `va_arg(ap, va_list)` guard only covered `__arm__`, not `__aarch64__`. On AArch64, `va_list` is a struct (like ARM), not a pointer.
- **Fix**: Added `__aarch64__` cases for both files.
- **Commit**: `b75a3ae5ff`

### 4. Missing `AROS_PRINTER_MAGIC` for AArch64
- **File**: `compiler/include/aros/printertag.h`
- **Problem**: No `__aarch64__` case → `#error` during compilation.
- **Fix**: Added `0xd65f03c0` (AArch64 `ret` instruction encoding).
- **Commit**: `fae27e295b`

### 5. libpng NEON symbols unresolved on AArch64
- **File**: `workbench/libs/png/mmakefile.src`
- **Problem**: libpng auto-detects AArch64 NEON via compiler predefs and references NEON symbols, but the mmakefile didn't compile the NEON source files.
- **Fix**: Enabled `arm/arm_init`, `arm/filter_neon_intrinsics`, `arm/palette_neon_intrinsics` for `aarch64` target.
- **Commit**: `84b6050339`

## Unfixed Issues (potential problems for ARM32 or other ports)

### 6. `dt_find_node()` returns wrong node on path mismatch
- **File**: `arch/arm-raspi/boot/devicetree.c` (and our copy in `arch/aarch64-raspi/boot/`)
- **Problem**: If no child matches the searched name, `dt_find_node` returns the parent node instead of NULL. Example: `dt_find_node("/memory")` returns the root node when the actual node is named `memory@0`.
- **Impact**: On ARM32 this doesn't matter because the Pi 1/2/3 DTB uses `/memory` (without `@0`). On Pi 4 the node is `/memory@0`.
- **Suggested fix**: After the `ForeachNode` loop, check if `ret` actually changed. If not, return NULL.

### 7. `atomic_v8.h` uses `teq` instruction (ARM32, not AArch64)
- **File**: `arch/aarch64-all/include/aros/aarch64/atomic_v8.h`
- **Problem**: The atomic macros use `teq` which is an ARM32 instruction, not available on AArch64. AArch64 should use `cbnz` or `tst`+`b.ne` instead.
- **Impact**: Currently not triggered because nothing includes these atomics directly yet. Will break when SMP kernel code is compiled.
- **Suggested fix**: Rewrite using `ldxr`/`stxr` with `cbnz` for the retry loop.

### 8. GCC 15.2.0 ICE with aligned types in `va_arg`
- **Not an AROS bug** — this is a GCC bug in `aarch64_function_arg_alignment` at `config/aarch64/aarch64.cc:6970`.
- **Workaround**: Don't use `__attribute__((aligned))` types in `va_arg`. The C standard says `va_arg` expects the promoted type.
- **Affects**: Any code using `va_arg(ap, STACKED <type>)` on AArch64 with GCC 15.

## Architecture Isolation Lessons

### Embedded binary data must be 8-byte aligned on AArch64
- **File**: `arch/aarch64-raspi/boot/mmakefile.src`
- **Problem**: Using `ld -r --format binary` to embed core.elf produces unaligned data. AArch64 `ldr x0, [x1, #offset]` on unaligned addresses causes Data Abort (ESR 0x96000021) even with SCTLR_EL1.A=0 in QEMU.
- **Fix**: Use `.incbin` with `.balign 8` in an assembly wrapper instead of `--format binary`.
- **Impact**: Any AArch64 code that embeds binary data via the linker must ensure 8-byte alignment.

### How `arch/arm-native/` code gets pulled into AArch64 builds
The AROS `%build_module` macro generates dependency chains:
```
hidd-i2c → hidd-i2c-$(CPU) → hidd-i2c-$(FAMILY) → hidd-i2c-$(ARCH)
```
Since `$(ARCH)=raspi` for both ARM32 and AArch64, any `#MM- hidd-i2c-raspi : hidd-i2c-bcm2708` in `arch/arm-native/` will pull ARM32 code into the AArch64 build. This is by design — the code must be portable or guarded with `#ifdef`.

### QEMU raspi4b does not provide a DTB
Unlike real Pi 4 firmware, QEMU's `raspi4b` machine does not automatically pass a DTB to the kernel. You must use `-dtb bcm2711-rpi-4-b.dtb` explicitly. QEMU does patch the DTB (e.g., `/memory@0` reg) before passing it.
