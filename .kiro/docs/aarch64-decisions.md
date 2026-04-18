---
name: aarch64-decisions
description: Technical decisions and rationale for the AROS AArch64 port. Consult when reviewing code or making changes to understand WHY things were done a certain way.
---

# AArch64 Port — Decision Log

## Build System

### Cross-toolchain: GCC 15.2.0 via AROS crosstools
- **Decision**: Use AROS's own crosstools build (`scripts/fetch-crosstools.sh`) with `--target=aarch64-aros`.
- **Rationale**: Ensures ABI compatibility with AROS headers. The `aarch64-none-elf-` prefix is configured in `configure.in`.
- **Issues found**: GCC 15.2.0 has an ICE with `aligned` types in `va_arg` (see codebase-issues doc).

### macOS (Darwin/AArch64) as build host
- **Commits**: `e86bed3c16`, `722013652f`, `c8ebb760ee`
- **Issues fixed**: HOST_RANLIB detection, libgcc `t-aros` config, `--disable-gcov` for crosstools.
- **Key insight**: macOS `ranlib` behaves differently from GNU `ranlib`. The configure script needed fixes to detect the host toolchain correctly.

## Bootstrap (`arch/aarch64-raspi/boot/`)

### EL2→EL1 transition
- **Decision**: Write the EL2→EL1 macro from ARM Architecture Reference Manual (DDI 0487, D1.9).
- **Rationale**: The register writes are fully specified by the ARM spec. Every value is mandated (CNTHCTL_EL2, CPTR_EL2, HCR_EL2, SCTLR_EL1 RES1 bits, SPSR_EL2).
- **Source**: ARM ARM D1.9, D13.2.27, D13.2.30, D13.2.36, D13.2.47, D13.2.113, D13.2.109.

### MMU: 4KB granule with L2 block descriptors (not 64KB granule)
- **Decision**: Use 4KB granule with 2MB L2 block descriptors instead of 64KB granule with L3 page tables.
- **Rationale**: 64KB granule requires 64KB-aligned page tables (each 64KB). With a bump allocator, this wastes enormous memory for alignment. 4KB granule with L2 blocks needs only 4KB per table, and 2MB blocks are sufficient for bootstrap (no fine-grained permissions needed yet).
- **Trade-off**: Less granular memory protection. The kernel can switch to 64KB granule later if needed.
- **TCR_EL1**: T0SZ=28 (36-bit VA = 64GB), TG0=4KB, IPS=64GB.

### Device tree: reused ARM32 parser verbatim
- **Decision**: Copy `devicetree.c` from `arch/arm-raspi/boot/` without modification.
- **Rationale**: The FDT parser is architecture-neutral C code. It uses `exec/lists.h` macros (NEWLIST, ADDTAIL, ForeachNode) and `malloc` — all portable.
- **Known bug**: `dt_find_node()` returns parent on mismatch instead of NULL (see codebase-issues doc). Worked around by searching `/memory@0` before `/memory`.

### Pi 4 DTB: `#address-cells=2` handling
- **Decision**: Hardcode the cell counts for `/soc/ranges` (4 cells per entry) and `/memory` reg (3 cells).
- **Rationale**: The Pi 4 DTB root has `#address-cells=2, #size-cells=1`. A generic parser would read these properties dynamically, but for bootstrap simplicity we hardcode the known Pi 4 layout.
- **Risk**: Won't work if a future Pi DTB changes cell counts. Acceptable for bootstrap; the kernel's OF parser handles this generically.

### BOOT_TMP_SIZE: 512KB
- **Decision**: Increased from ARM32's 64KB to 512KB.
- **Rationale**: The Pi 4 DTB is 56KB (132KB after QEMU patching). The DT parser uses ~107KB for the unpacked tree. Plus MMU tables need ~32KB. 512KB gives comfortable headroom.

### Identity-mapped memory (no virtual offset)
- **Decision**: `kernel_virt = kernel_phys` (virtual offset = 0).
- **Rationale**: The ARM32 port uses a virtual offset (`KERNEL_VIRT_ADDRESS = 0xf8000000`), but this adds complexity to the ELF loader and MMU setup. For the initial AArch64 port, identity mapping is simpler and sufficient. Can be changed later.

## Kernel (`arch/aarch64-native/kernel/`)

### `AARCH64_Implementation` struct modeled after `ARM_Implementation`
- **Decision**: Same pattern as `arch/arm-native/kernel/kernel_arm.h`.
- **Rationale**: Proven pattern for SoC abstraction. Each platform (BCM2711, BCM2712) registers its functions. Kernel code calls through function pointers only.

### GIC-400 driver from ARM specs
- **Decision**: Write GIC-400 driver from ARM GIC-400 TRM (DDI 0471B) and GIC Architecture Spec (IHI 0048B).
- **Rationale**: The GIC-400 is standard ARM IP. The init sequence and interrupt handling flow are fully specified in the TRM §4.3 and Architecture Spec §3.4. GICD at `0xFF841000`, GICC at `0xFF842000` (BCM2711-specific, from datasheet).

### ARM Generic Timer for heartbeat (not BCM system timer)
- **Decision**: Use CNTP (non-secure physical timer) PPI 14 instead of BCM2708 system timer.
- **Rationale**: The ARM Generic Timer is standard across all ARMv8 SoCs. The BCM system timer is legacy (Pi 1-3). Using the generic timer makes the code portable to Pi 5 (BCM2712).

## ELF Loader

### RELA relocations for AArch64
- **Decision**: Handle `SHT_RELA` (with explicit addend) instead of `SHT_REL`.
- **Rationale**: AArch64 ELF uses RELA exclusively. The ARM32 loader handles REL.
- **Relocation types implemented**: R_AARCH64_ABS64, ABS32, CALL26, JUMP26, ADR_PREL_PG_HI21, ADD_ABS_LO12_NC, LDST*_ABS_LO12_NC.
- **Status**: Compiles but crashes on the stub core.elf. Needs debugging — likely issue with section header parsing of REL-type (relocatable) ELF objects.

### Stack switch in _start must be pure assembly
- **Decision**: `_start` is a top-level `__asm__()` block, not a C function with inline asm.
- **Rationale**: If `_start` is a C function, the compiler may spill `x0` (the tags pointer argument) to the old bootstrap stack before the inline asm switches to the new kernel stack. Then `ldr x0, [sp, #offset]` reads garbage from the new stack. Pure asm avoids this by switching SP before any C code runs.
- **Bug found**: With C `_start`, GCC generated `str x0, [sp, #24]` (save to old stack), `mov sp, x1` (switch), `ldr x0, [sp, #24]` (load from new stack = garbage). All boot tags showed as 0.

## Files Created/Modified

### New directories
- `arch/aarch64-raspi/boot/` — Bootstrap (7 C files, 1 ASM, headers, linker script, mmakefile)
- `arch/aarch64-native/kernel/` — Kernel (stub + GIC + timer + vectors + platform, mmakefile)

### Modified existing files
- `compiler/include/aros/printertag.h` — Added AArch64 magic
- `workbench/libs/png/mmakefile.src` — Enabled NEON for AArch64
- `workbench/network/stacks/AROSTCP/bsdsocket/api/amiga_generic2.c` — AArch64 va_set
- `workbench/network/stacks/AROSTCP/bsdsocket/kern/subr_prf.c` — AArch64 va_list guard
- `arch/arm-native/soc/broadcom/2708/hidd/i2c/i2c-bcm2708.c` — Portable asm barrier
- `developer/debug/test/library/dummylib.c` — Fixed UB in va_arg
