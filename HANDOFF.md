# Handoff

Written 25 August 2026 on `feat/cmake-build-propagation`. This is the short
restart document; `OPEN-POINTS.md` contains the investigation history and is
authoritative where details differ.

## Current result

The packaged PC x86_64 system now builds and boots cleanly on both macOS and
Linux. All six package targets and the PC bootstrap were rebuilt, all 76
packaged ELF modules were scanned, and no module retains a strong dynamic StdC
startup/base dependency. The final post-refactor 20-second non-interactive runs
on macOS (QEMU 11.1.0) and CachyOS Linux (QEMU 11.0.2) both reached user mode
without a failure or CPU exception:

```text
Booting [pc-x86_64] with 7 multiboot module(s) for 20s...
reached: user mode reached
✅ PASS: the boot produced no failure and no exception.
```

The serial log reaches ACPI/APIC setup and the VESA no-information diagnostic.
`aros test` currently has no later Workbench or Shell milestone, so "user mode"
is the strongest automated assertion made by this check; it is not a claim that
the desktop has opened.

The equivalent fresh checks for ARM/AArch64 remain to be run. The Linux result
is for the direct CMake build; the separate deterministic toolchain producer's
Linux/reproducibility matrix in `OPEN-POINTS.md` point 5 remains open.

## What fixed the packaged boot

The important fix is central rather than a list of AROS source workarounds.
AROS' native GCC and Clang patches define `-static` as the request to suppress
the shared posixc/stdcio/stdc clients and select `libstdc.static.a`. The
transpiler used to discard that driver switch while CMake reconstructed the
default link set from `config/elf-specs.in`, so early resident modules acquired
dynamic `stdc.library` dependencies that upstream does not give them.

The transpiler now records `static` as a compiler-spec fact and
`cmake/DefaultLinkSet.cmake` maps it to the checked-in spec's `nostdc` condition.
The temporary `-nostdc` edits in bootloader, OOP, and Poseidon were removed;
their original upstream `-static` semantics work again.

One independent early-start issue remained: `hid.class` linked libamiga's
`NewObject` and therefore required `IntuitionBase`, although HID starts at
resident priority 29 and Intuition at 15. Its existing GUI sources now compile
with `INTUITION_INLINE_NEWOBJECT`, avoiding that premature auto-open.

The boot checker also no longer treats QEMU's `Servicing hardware INT=...`
trace records as CPU exceptions. A regression test distinguishes these normal
hardware interrupt records from actual faults.

The Linux cold build exposed four host-dependent assumptions which are now
removed: direct presets pin Clang and the LLVM target utilities, freestanding
compiles explicitly disable a distro-default stack protector, direct lld links
do not inherit CMake's linker dependency-file syntax, and CDVDFS waits for the
codesets headers it includes. QEMU 11.0.2 also exposed two unchecked SMBIOS ROM
scanners: firmware text happened to contain `_SM3_` before the real SMBIOS 2
entry point. ACPICA and the PC IPMI HIDD now validate entry-point lengths,
anchors and checksums and bound every table walk. This is why testing both QEMU
versions matters; macOS/QEMU 11.1.0 had masked the defect.

## Other changes waiting in this branch

- Configure-time source inventories resolve fetched ACPICA and FreeType source
  globs. A cold configure fetches only the owning archives, reruns the
  transpiler, and fails closed if a second pass still has unresolved inventory.
- `hidd/unixio.h` is an exact public-header exception to the foreign-architecture
  filter. This unblocks the native PC parallel/serial HIDDs without admitting a
  broad foreign architecture namespace into the SDK.
- `aros-genmodule` emits the reference-compatible RAWARG format wrappers.
- The configure step still reports 25 of 366 `FUNCTIONS_COUNT` disagreements;
  point 50 remains open.

## Build and boot

Configure after rebuilding the release-time generators whenever their Rust
source changes:

```bash
cargo build --release --workspace \
  --manifest-path tools/aros-tools/Cargo.toml
cmake --preset pc-x86_64
```

Build the kernel and every package consumed by `aros test --packages`:

```bash
ninja -C build/pc-x86_64 -j 8 \
  SYS/boot/pc/bootstrap \
  SYS/boot/pc/kernel \
  kernel-package-base-file \
  kernel-package-fs-file \
  kernel-bsp-pc-x86_64-file \
  kernel-package-usb-file \
  kernel-acpi-file \
  kernel-legacy-pc-x86_64-file
```

Then run:

```bash
tools/aros-tools/target/release/aros test --preset pc-x86_64 --packages
```

`aros test --packages` consumes existing `bootstrap`, kernel and `.pkg` files;
it does not rebuild them. The final Linux evidence is on `cachy` at
`/home/fabian/aros-ng-linux-check.uyLICC/evidence-linux-pc-x86_64-smbios-final`;
the final macOS evidence was written to
`/tmp/aros-ng-evidence-macos-pc-x86_64-smbios-final`.

Presets are `pc-x86_64`, `rpi-aarch64`, `rpi4-aarch64-debug`, and
`arm-raspi`. A full unqualified `ninja` still stops in third-party C++ Ports
because target libc++ headers such as `cstdint` do not reach all consumers
(point 25); named boot targets avoid that unrelated lane.

## Verification gate

From `tools/aros-tools`:

```bash
cargo fmt --all --check
cargo clippy --workspace --all-targets
cargo test --workspace
```

Clippy passes with existing non-fatal warnings. The stricter `-D warnings` gate
is not clean because of pre-existing `must_use` and other warnings outside this
change.

From the repository root:

```bash
for t in cmake/tests/*Test.cmake; do cmake -P "$t" || exit 1; done
git diff --check
```

The CMake sweep takes roughly five minutes, mostly in `GrubBuildTest.cmake`.
The Rust workspace, every CMake fixture including the real GRUB host build and
the new source-inventory, preset-toolchain and SMBIOS-validation fixtures, and
both packaged PC boots are green as of this handoff. The thematic commit IDs
are the newest entries in `git log`.

For byte-for-byte transpiler refactors use `aros golden capture` and
`aros golden verify`. They replay the recorded argv from
`generated_targets.cmake.invocation`; baselines live under `build/golden/` and
are not committed.

## Next work

1. Configure/build the ARM and AArch64 lanes to prove the new generic mechanisms
   across every current architecture.
2. Resolve the 25 `FUNCTIONS_COUNT` disagreements in point 50.
3. Continue point 25 so an unqualified full build can pass.
4. Complete the deterministic toolchain producer's Linux and byte-comparison
   matrix (point 5); the clean direct Linux build does not close that work.
5. Add later boot milestones if Workbench/Shell readiness must be asserted
   automatically rather than inferred from the serial log.

## Working agreements

- Transpile upstream MetaMake semantics instead of adding target-specific glue.
- Keep architecture exceptions exact and test them across all current profiles.
- Anything unsupported is reported and fails closed; it is never silently
  dropped.
- Split work into thematic commits and never add a Codex co-author trailer.
