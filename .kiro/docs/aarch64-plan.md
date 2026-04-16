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
- **Status**: DONE — HDMI framebuffer working, vc4gfx HIDD fully operational, graphical boot screen renders
- **Commits**: `79e802b8b2` (bootstrap FB), `8cf3a3e423` (vc4gfx port), `34b6d87da1` (MEMF_CHIP fix)
- **What works**: VideoCore mailbox property interface (0xFE00B880, channel 8), 640x480x32 framebuffer allocation, vc4gfx HIDD creates OnScreenBM and OffScreenBM objects, cgxbootpic renders AROS eye logo, dosboot shows "Waiting for bootable media" screen with device icons
- **Key bugs fixed**:
  - PointerClass OM_NEW returned class pointer on failure instead of NULL (`527ed55d94`)
  - MEMF_CHIP allocations failed (no chip memory on AArch64) — patched AllocMem via SetFunction (`34b6d87da1`)
- **Verified**: QEMU screendump shows full AROS graphical boot screen (eye logo + "Waiting for bootable media")
- **Depends on**: Task 7

### Task 9: USB HID — keyboard and mouse via DWC2 (usb2otg)
- **Status**: DONE (build) — all modules compile, runtime testing needs Task 10 (DOS/filesystem)
- **Commit**: `c25455e026`
- **What was done**: Ported usb2otg DWC2 driver from ARM32 (fixed ARM32 asm nops, 64-bit cast). Created asm/cpu.h for AArch64 (dsb/dmb/isb). Created mbox.resource for BCM2711. Added `__aarch64__` guard to compiler/include/asm/cpu.h dispatcher.
- **What builds**: usb2otg.device, mbox.resource, poseidon.library, hub/hid/bootkeyboard/bootmouse classes, usbromstartup.resource
- **What's needed for runtime**: KrnGetSystemAttr(KATTR_PeripheralBase) returning 0xFE000000, DWC2 IRQ (GIC SPI 73 = IRQ 105) wired, modules loaded from BSP ROM or filesystem
- **Note**: QEMU raspi4b does NOT emulate xHCI (PCIe not implemented). It emulates the DWC2 OTG controller at 0xFE980000, which is what usb2otg drives. Real Pi 4 uses xHCI via PCIe for USB 3.0 ports — xHCI driver needed later for real hardware.
- **TODO**: Build mbox.resource as a proper resident (currently standalone). Consider packaging USB modules into BSP ROM for testing before DOS is available.
- **Objective**: User input working.
- **Work**:
  - xHCI HCD for Poseidon USB stack (from Circle `lib/usb/xhci*.cpp`, GPLv3). Pi 4 xHCI at `0xFE9C0000`.
  - Ring management, slot manager, root hub, endpoint management, DMA allocator
  - Wire existing Poseidon HID class drivers (hub, bootkeyboard, bootmouse)
- **Reference**: Circle `lib/usb/xhci*.cpp` (11 files)
- **Demo**: USB keyboard types, USB mouse moves pointer
- **Depends on**: Task 7

### Task 10: SD card, DOS, and Workbench boot
- **Status**: DONE — Full boot to shell prompt. Workbench screen, Startup-Sequence executed, CLI at `1>`. Only `SYS:Locale` missing (not in SD image).
- **Commits**: `889c3d9ef8` (BSP ROM), `510888149c`..`c8b26dad77` (interrupt fix, context switch, TLS sync), `0a43bea304` (inputclass fix), `527ed55d94` (pointerclass fix), `34b6d87da1` (MEMF_CHIP fix)
- **What works**: Full COLDSTART init sequence (45 modules), timer interrupts at 50Hz, SVC-based context switching + preemptive IRQ-based switching, vc4gfx display driver registered, cgxbootpic boot logo rendered, dosboot "Waiting for bootable media" screen displayed. sdcard.device fully initializes on QEMU raspi4b — card detected as "QEMU! SD2.0 128MB", reads sectors via CMD17. RDB partition table detected, DH0 partition found (DosType DOS\3 = FFS-I). afs-handler starts, opens device, reads FFS volume. mountBootNode succeeds. `Lock("DH0:")` succeeds. `CliInit` returns DOSTRUE. `RemTask(NULL)` via `SC_DISPATCH` works. Workbench Screen opens with Intuition system requesters.
- **Key fixes applied**:
  - exec_platform.h: AROS_NO_ATOMIC_OPERATIONS support
  - KrnIsSuper(): TLS SupervisorCount tracks exception context
  - SVC handler: full register save (176-byte frame)
  - EL1h mode: kernel runs in EL1h consistently
  - TLS/SysBase ThisTask sync: dual-write in SET_THIS_TASK
  - inputclass.hidd added to BSP ROM (keyboard/mouse HIDD dependency)
  - PointerClass OM_NEW: return NULL on failure instead of class pointer
  - MEMF_CHIP: patched AllocMem to strip MEMF_CHIP (no chip memory on AArch64)
  - sdcard.device IRQ: changed from legacy BCM2708 #62 to GIC SPI 126 (IRQ 158)
  - GIC-400: added krnRunIRQHandlers() bridge so KrnAddIRQHandler() works
  - sdcard.device IOBase: QEMU connects -sd to Arasan SDHCI at 0xFE300000, not EMMC2 at 0xFE340000
  - sdcard.device WaitCmd: added polling fallback for when GIC IRQ doesn't fire
  - sdcard.device card-detect: heuristic for broken-cd (BCM2711 EMMC2 never sets CARD_PRESENT bit)
  - sdcard.device SDSC geometry: CSD v1 block_size was raw READ_BL_LEN (128 bytes) instead of 512; fixed to always use 512-byte sectors
  - MakeDosNode heap corruption: DosEnvec was in same AllocVec block as DeviceNode; CreateNewProcTags corrupted it via adjacent heap allocations. Fixed by allocating DosEnvec separately.
  - TLSF heap corruption: unidentified overflow corrupts adjacent block headers, causing DosList `dol_Name` corruption and `FindDosEntry` failures. Workaround: 24-byte red zone in `tlsf_malloc()` (`rom/kernel/tlsf.c`) + padding in `MakeDosEntry()` (`rom/dos/makedosentry.c`). Root cause TBD — exhaustive analysis ruled out AFS buffer indexing, hash computation, and string handling.
  - SD image: switched from MBR+FAT to RDB+FFS (DOS\3). AROS uses RDB natively; MBR type 0x76 wasn't mapped. RDB stores DosType/DosEnvec directly in partition entries.
  - **Preemptive scheduling**: IRQStub now calls `irq_RescheduleCheck()` after `InterruptHandler`. If `FLAG_SCHEDSWITCH_ISSET` or a higher-priority task is ready, converts IRQ frame to SVC frame and does full context switch via `switch_save_sp`/`switch_dispatch`. Guard: only preempts if `ThisTask->tc_State == TS_RUN` (prevents preempting kernel idle loop).
  - **TDNestCnt/IDNestCnt sync**: `switch_dispatch` now restores `TDNESTCOUNT_SET(task->tc_TDNestCnt)` and `IDNESTCOUNT_SET(task->tc_IDNestCnt)` when dispatching a new task. Without this, TLS TDNestCnt stayed at 0 (from MEMF_CLEAR'd bootstrap task) and task switching appeared permanently disabled.
  - **TDNestCnt save on preempt**: `switch_save_sp` now saves `task->tc_TDNestCnt = TDNESTCOUNT_GET` before `core_Switch()`, so preempted tasks preserve their nesting state.
  - **SC_DISPATCH handler**: Added `.Ldo_dispatch` to SVC handler for `SC_DISPATCH` (syscall 1). Dispatches next task WITHOUT saving current context — used by `RemTask(NULL)` → `KrnDispatch()`. Without this, `RemTask` returned to caller, causing `dos_init` to return from `InitResident` and fail the boot.
- **SD test image**: `/tmp/aros_sd_rdb.img` — 128MB RDB, DH0 partition (DOS\3/FFS-I), populated with S/Startup-Sequence, C/, L/, Libs/, Devs/, Classes/ via rdbtool+xdftool
- **Previous issues (all fixed)**:
  - TLSF heap corruption during AFS bitmap ops (workaround: 16-byte red zone)
  - Preemptive scheduling not working (IRQStub didn't call scheduler)
  - TDNestCnt stuck at 0 (not synced on task dispatch)
  - SC_DISPATCH not handled (RemTask returned to caller)
  - `Lock("SYS:")` hang (task on ready list but never scheduled)
- **Objective**: Full AROS Workbench on Pi 4.
- **Work**:
  - ~~SD card driver for EMMC2~~ DONE (using Arasan at 0xFE300000 for QEMU)
  - ~~Create bootable SD image~~ DONE (RDB+FFS via rdbtool+xdftool)
  - ~~Heap corruption root cause~~ DONE — `kb_ContextSize` was 8 instead of 288 (commit `d2e4672710`)
  - ~~IsBootable / CliInit boot path~~ DONE (boots past IsBootable, assigns SYS:)
  - ~~Preemptive task scheduling~~ DONE (IRQStub → `irq_RescheduleCheck` → context switch)
  - ~~SC_DISPATCH for RemTask~~ DONE (SVC handler dispatches without saving context)
  - ~~TDNestCnt/IDNestCnt sync~~ DONE (save on switch, restore on dispatch)
  - ~~Find and fix heap corruption that breaks AFS handler~~ DONE — ROOT CAUSE: `rom/kernel/cpu_init.c` (generic) set `kb_ContextSize = sizeof(struct AROSCPUContext)` using the generic stub definition (8 bytes, just `IPTR pc`) instead of the aarch64 `ExceptionContext` (288 bytes). `KrnCreateContext()` allocated 8 bytes, `PrepareContext()` wrote 288 bytes, overflowing into adjacent TLSF block headers. Fix: arch-specific `cpu_init.c` in `arch/aarch64-native/kernel/` that includes the correct `kernel_cpu.h`. Commit `d2e4672710`. Found via GDB hardware watchpoint on Linux QEMU (cachy).
  - ~~GOT relocation handling in ELF loaders~~ DONE (`06733d204b`) — synthesize GOT entries for R_AARCH64_ADR_GOT_PAGE/LD64_GOT_LO12_NC in both bootstrap and runtime loaders; fix getElfSize() to account for GOT slot space
  - Verify Startup-Sequence execution, Intuition, graphics, layers
- **Demo**: AROS Workbench desktop, interactive with USB keyboard/mouse
- **Depends on**: Tasks 8, 9

### Code Audit (2026-04-16)
- **Status**: DONE — All findings fixed in commits `3648db9495` and `4fec742b24`
- **Findings fixed**:
  - CRITICAL: makedosnode.c memory leak (DosEnvec separate allocation reverted)
  - CRITICAL: exec_platform.h duplicated (exec/ now includes kernel/ copy)
  - CRITICAL: stackswap.S FindTask LVO was wrong (-196 instead of -392)
  - MODERATE: Debug instrumentation removed from 13 shared files
  - MODERATE: BCM2711_GICD/GICC_BASE SSOT (removed redefinition in kernel_cstart.c)
  - MODERATE: dispatch_idle() extracted from duplicated idle loops (DRY)
  - MINOR: DEBUG 0 in all arch-specific files, whitespace cleanup, improved comments
- **Build environment**: Fully self-contained on cachy (git repo + crosstools + build)

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

## Development Environment

### Primary build machine: cachy (CachyOS Linux x86_64)
- **Path**: `fabian@cachy:/home/fabian/AROS-AArch64/`
  - `AROS/` — source tree (synced from macOS `~/Source/AROS`)
  - `build/` — build directory
- **Configure**: `../AROS/configure --target=raspi-aarch64 --enable-debug=all --with-kernel-toolchain-prefix=aarch64-linux-gnu- --with-gcc-version=15.2.0`
- **Crosstools**: GCC 15.2.0 (`aarch64-aros-gcc`), binutils 2.32 — built automatically by AROS build system
- **Kernel toolchain**: `aarch64-linux-gnu-gcc` 15.1.0 (system package, used for bootstrap code)
- **QEMU**: `qemu-system-aarch64` 10.2.2 — supports GDB hardware watchpoints (key advantage over macOS)
- **CPU**: 12 cores, full build ~15 min after crosstools
- **Why cachy**: Linux QEMU provides proper GDB hardware watchpoints via `-gdb tcp::1234`. On macOS, QEMU's GDB stub had connection reliability issues and watchpoints timed out.

### macOS (secondary, source of truth for git)
- **Path**: `~/Source/AROS` (git repo), `~/Source/AROS-build-aarch64` (build dir)
- **Note**: macOS build was configured WITHOUT `--enable-debug=all` (uses `-O2`). The cachy build uses `-O0` which exposed additional issues.

### Build fixes for debug builds (`--enable-debug=all` / `-O0`)
- **libpng NEON**: `OPTIMIZATION_CFLAGS := -O2` in `workbench/libs/png/mmakefile.src` — NEON intrinsics require constant lane indices, only resolved at `-O1+`
- **zlib NEON/CRC**: Same fix in `workbench/libs/z/mmakefile.src`
- **core.elf libgcc**: Added `-lgcc` to core.elf link in `arch/aarch64-native/kernel/mmakefile.src` — AArch64 `long double` is 128-bit; at `-O0` GCC emits quad-float helper calls (`__lttf2`, `__multf3`, etc.)
- **cpumode_t**: Added `typedef int cpumode_t` and `#define goBack(mode)` to `arch/aarch64-native/kernel/kernel_cpu.h` — required by `rom/kernel/createcontext.c`

## Debugging Playbook

### QEMU + GDB connection issues

QEMU's GDB stub only supports **one connection at a time**. If GDB disconnects without `detach`, the stub enters `CLOSE_WAIT` and refuses new connections — QEMU must be restarted. Always use `detach` before `quit`.

GDB `-batch` mode treats `continue` as **non-blocking** — subsequent `-ex` commands fire immediately while the target is still running. Use `expect` to drive GDB interactively:

```bash
cat > /tmp/gdb.exp << 'EXPECT'
set timeout 180
spawn /opt/homebrew/bin/gdb -quiet -nx
expect "(gdb)"; send "set architecture aarch64\r"
expect "(gdb)"; send "target remote :5432\r"
expect "(gdb)"; send "watch *(long long *)0xADDRESS\r"
expect "(gdb)"; send "c\r"
expect {
    -re "Hardware watchpoint" {
        expect "(gdb)"; send "info reg\r"
        expect "(gdb)"; send "detach\r"
        expect "(gdb)"; send "quit\r"
        expect eof
    }
    timeout { send "\003"; expect "(gdb)"; send "detach\r"; expect "(gdb)"; send "quit\r"; expect eof }
}
EXPECT
expect /tmp/gdb.exp 2>&1
```

### Heap corruption debugging strategy

**Problem**: TLSF heap corruption where a buffer overflow from one allocation corrupts an adjacent block's header. Symptoms: `length` field in a free block header contains a pointer value instead of a small size.

**What doesn't work well**:
- **Fixed-address watchpoints via GDB**: Every code change shifts heap layout, invalidating the watched address. GDB connection fragility compounds this.
- **Fixed-address polling guards**: Same address-shifting problem. Adding debug code changes the binary, which changes allocation patterns.

**What works — Red Zone / Mungwall approach**:

Add 16 bytes to every TLSF allocation and write a canary pattern after the user's requested size. Check the canary on `free()`. This is address-independent and survives code changes.

In `tlsf_malloc()`:
```c
IPTR orig_size = size;
size = ROUNDUP(size + 16);  // Add red zone
// ... normal allocation ...
// Before return:
UBYTE *p = (UBYTE *)&b->mem[0];
IPTR rz = ROUNDUP(orig_size);
*(IPTR *)(p + rz) = orig_size;           // Store original size
*(ULONG *)(p + rz + 8) = 0xDEADBEEF;    // Canary pattern
```

In `tlsf_freevec()`:
```c
// After fb = MEM_TO_BHDR(ptr):
// Scan for stored size + check canary
```

**Gotchas**:
1. `MEMF_CLEAR` handling: TLSF's `bzero` must clear only `orig_size` bytes, not the full `size` (which includes the red zone). Otherwise the canary gets zeroed.
2. The compiler may optimize `bzero(ptr, N)` for small N to clear more bytes than requested (alignment optimization). This causes false positives for allocations < 16 bytes. Filter by `stored_size > 64`.
3. If the overflow lands entirely within the red zone, the corruption is **prevented** but the canary check only fires when the block is **freed**. If the block is never freed (e.g., a FileHandle that lives for the session), the check never runs. Solution: also check canaries on every Nth `malloc`, or instrument the specific `FreeDosObject` path.
4. Storing the original size in the red zone itself is fragile — the overflow may corrupt both the size and the canary. Better: store `orig_size` at a fixed offset from the block header (e.g., in unused `free_node` fields — but beware, `free_node` overlaps `mem[]` in the union, so writing to it corrupts user data). Safest: store at `ROUNDUP(orig_size)` offset and scan for it on free.

**Recommended workflow for heap corruption**:
1. First, reproduce with TLSF tracing (SPLIT/INSERT/REMOVE/MALLOC/FREE with address-range filter) to identify the corrupted block and its neighbors.
2. Add the red zone to confirm the overflow size and prove it's a buffer overflow (not a use-after-free or double-free).
3. If the red zone prevents the crash, the overflow is absorbed — use static analysis to find the writer (grep for struct field accesses past the allocation size).
4. If you need the exact writer, use QEMU's `-d guest_errors` or a TCG plugin to trace stores to the canary address, avoiding GDB entirely.

**Canary-based elimination technique**:
When you suspect a specific struct (e.g., FileHandle) is overflowing, add extra bytes + a canary to its `AllocDosObject`/`AllocMem` call and check the canary in the corresponding `Free` path. If the canary is intact on free, that struct is NOT the overflow source — the corruption comes from a different adjacent allocation. This eliminates suspects quickly without needing the exact writer address.

**TLSF integrity check false positives**:
When adding `GET_NEXT_BHDR` sanity checks in `tlsf_malloc`, beware that legitimate TLSF blocks can be very large. The initial free block spans nearly all of RAM (~955MB on a 1GB system). A threshold like `> 0x10000000` (256MB) will false-positive on these. Either use `(IPTR)nxt + size > mhe->mhe_MemHeader.mh_Upper` as the check, or track the last allocation in a specific address range and only check that block's neighbor.

Also note: `THIS_FREE = 1` and `THIS_BUSY = 0` in AROS TLSF — the opposite of what you might expect. A length field ending in `1` means FREE, not BUSY.

### Task scheduling hang diagnosis

**Symptom**: A task is on the ready list (`TS_READY`) but never gets CPU time. The system appears hung — no crash, no exception, just no progress.

**Diagnosis approach**:
1. Add traces to `PutMsg` and `Signal()` to confirm the reply message is sent and the signal is delivered.
2. In `Signal()`, log `task->tc_State`, `signalSet`, `tc_SigRecvd`, `tc_SigWait`, and the match (`tc_SigRecvd & tc_SigWait`). If `tc_State == TS_READY` and `tc_SigWait == 0`, the task was already woken up but never scheduled.
3. Check if the timer IRQ handler calls `core_ExitInterrupt()` — this is what triggers the scheduler to check for ready tasks and perform context switches.
4. On AROS, cooperative multitasking happens via `Wait()`/`Signal()`. Preemptive multitasking requires the timer IRQ to call into the scheduler. If the IRQ handler only does `core_Cause(INTB_VERTB)` but doesn't call `core_ExitInterrupt()`, tasks of equal priority will never preempt each other.

**Key insight**: The AFS handler processes a packet, replies via `PutMsg` (which signals the caller), then loops back to `WaitPort`. If the caller has equal priority, it needs preemptive scheduling to run — the AFS handler won't voluntarily yield until it calls `WaitPort` → `Wait()`, but by then it has already consumed the timer tick. The caller's signal was delivered but the scheduler never ran to switch to it.

### Common AArch64 porting bugs

| Pattern | Symptom | Root cause |
|---------|---------|------------|
| Struct size mismatch | Heap overflow 8-24 bytes | Pointers grew from 4→8 bytes; allocation uses hardcoded size or wrong sizeof |
| BPTR sentinel -1 | Translation fault at 0xFFFFFFFFFFFFFFFF | `AROS_FAST_BPTR` makes `(BPTR)-1` a literal pointer; code must check before dereferencing |
| MEMF_CHIP | AllocMem returns NULL | No chip memory on AArch64; patch AllocMem to strip MEMF_CHIP |
| Stack in .bss | Crash after clear_bss | Stack variable in .bss gets zeroed; use `section(".data")` |
| 32-bit register ops | Upper 32 bits of x-reg zeroed | ARM32 code using `w` registers or `ULONG` for pointer-sized values |
| Unaligned access | Data abort | AArch64 requires 16-byte stack alignment; `stp`/`ldp` require natural alignment |
| BSTR as task name | Task name shows `\x01` or garbage | Handler name set from BSTR (length-prefixed) instead of C string; `AROS_FAST_BSTR` expects C strings |
| No preemptive scheduling | System hangs, tasks in TS_READY never run | Timer IRQ doesn't call `core_ExitInterrupt()`; equal-priority tasks can't preempt each other |
| Adjacent-block heap corruption | Crash in unrelated code (NULL deref, wild jump) | Small overflow (8-16 bytes) from one allocation corrupts the TLSF header of the next block; manifests far from the actual bug |
| Jump to low address (0x0-0xF) | `ELR_EL1: 0x8`, EC=0x0 | Corrupted function pointer or jump table entry; often caused by heap corruption overwriting a `struct Library` vector |
| Missing SC_DISPATCH handler | `RemTask(NULL)` returns to caller | SVC handler only handled SC_SWITCH/SC_SCHEDULE but not SC_DISPATCH (1); `KrnDispatch()` SVC fell through to no-op `HandleSyscall` |
| TDNestCnt not synced on dispatch | Task switching appears permanently disabled (TDNest=0) | `switch_dispatch` must call `TDNESTCOUNT_SET(task->tc_TDNestCnt)` when dispatching; without it, TLS keeps the bootstrap task's initial value (0 from MEMF_CLEAR) |
| IRQ preempt during idle loop | Tasks stuck on ready list, never dispatched | IRQ fires during `wfi` in idle loop; preemptive switch saves idle loop context as task context, corrupting the previous task's SP. Guard: check `ThisTask->tc_State == TS_RUN` before preempting |
