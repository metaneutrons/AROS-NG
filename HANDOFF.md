# Handoff

## Update 27 August 2026 — `aros` CLI diagnostics match the shared tool contract

The user-facing `aros` orchestrator now has the same versioned diagnostic and
opt-in logging boundary as the transpiler, collector and AHI runner. Every
fatal path exits through one renderer and `ExitCode`; stable `AR0001`–`AR0999`
families distinguish invocation, observability, repository, configuration,
tool, toolchain, network, configure, build, boot, Pi, removable-media,
publication and internal failures. Human output remains the default;
`--diagnostic-format json` and the `AROS_DIAGNOSTIC_FORMAT` equivalent emit an
`aros-tool-diagnostics-v1` document with stage, hint and deterministic command
context.

`--log-level`, `--log-format` and `--log-file` add explicit local human or
`aros-cli-log-v1` JSONL logs. Logging remains off without a selected file and
contains no ambient timestamps, hostnames or CI metadata. The former Collector
and AHI copies of the renderer/logger now use one policy-driven implementation
in `aros-common`; their existing schemas and diagnostic tests remain green.

Non-interactive child failures preserve tool, exit code and signal. In JSON
mode their stdout/stderr cannot contaminate the diagnostic stream: output is
file-buffered, bounded to 64 KiB per stream on failure, and replayed unchanged
on success. The external serial terminal remains deliberately interactive.
The migration also closed two actual error-handling defects: `sync` and
`ccache` no longer ignore failed child statuses, and `clean --preset` validates
the preset before resolving or deleting a directory.

The shared strict Clippy gate, complete Rust workspace, dedicated CLI
integration tests and all 25 CMake fixtures including the real GRUB and native
AHI builds are green. The code and environment-variable contract is documented
in `tools/aros-tools/crates/aros-cli/README.md`.

## Update 27 August 2026 — V3D generated-source closure is green

The realised `linklibs-gallium_v3d` target now has a complete, fail-closed
generator graph on `pc-x86_64`, `arm-raspi` and `rpi-aarch64`. The transpiler
owns all twelve V3DX translation units (six Mesa sources compiled for V3D 3.3
and 4.1) and the three V3D 3.3/4.1/4.2 CLE packet headers. Their build-tree
paths match the handwritten MetaMake rules, every generated product is attached
to the archive consumer, and the wrapper contents use a source basename rather
than embedding a checkout-dependent absolute path.

The entire V3D recipe and target contract are admitted together. Recipe drift,
an unsupported target profile, a changed source/flag/include/output contract or
a missing Mesa fetch declaration removes the partial target and emits a typed
update-required capability error. The compile contract now carries undefines
explicitly, preserving V3D's `-UHAVE_VALGRIND`; mismatch diagnostics name the
individual contract fields instead of returning one opaque comparison error.

The first complete archive build exposed one real Mesa 20 portability defect:
`src/broadcom/qpu/qpu_pack.c` called `ffs` without a visible declaration. The
existing, visible AROS Mesa patch now includes Mesa's own `util/bitscan.h` in
that file. This is a source patch tracked by the fetch refresh mechanism, not a
package checksum or hidden pin.

All three real `libgallium_v3d.a` archives build successfully and their
immediate repeats are Ninja no-ops. No V3D/V3DX/CLE entry remains in the
missing-source, partial-source or unmodelled generated-file reports. Formatting,
strict workspace Clippy, the complete Rust workspace, all 25 CMake fixtures,
fresh three-profile 27-product golden capture/replay and `ninja verify` are
green. This proves V3D source/build closure, not byte identity with an upstream
MetaMake archive; point 12 remains the limit on the broader parity claim.

## Update 27 August 2026 — full architecture target parity is green

Point 10 and its point-29 policy dependency are closed. `ninja verify` now
passes completely for `pc-x86_64`, `arm-raspi` and `rpi-aarch64`, including
the point-50 `FUNCTIONS_COUNT` audit. Fresh target results are 1,078/1,078
declared/emitted/realised on PC and 1,075/1,075 on both Pi profiles.

The denominator is explicit rather than reduced invisibly. Ten applicable PC
and eight applicable Pi toolchain producer declarations are written to
`toolchain-provisioning-targets.txt`: the ordinary and release LLVM lanes plus
GCC libatomic. Exact declaration arguments and structural source checks make
the boundary fail closed. PC's preset explicitly selects `grub2gfx`, so the
distinct legacy GRUB 0.97 declaration is visible in
`inactive-profile-targets.txt`; selecting `grub` returns it to the required
target set. Every preset pins both its toolchain and bootloader.

The verifier now recognises the exact handwritten upstream
`linklibs-hiddstubs` archive contract rather than treating its synthesized
CMake target as undeclared. The transpiler also safely adopts literal shared
`.cfg` fragments such as Mesa's `mesa.cfg` and no longer mistakes an indented C
compiler `-include` option for a Make include. This restores all fetched V3D
source stems and makes `linklibs-gallium_v3d` a realised CMake target.

Do not overstate this gate: it proves declaration, shape and CMake-target
realisation parity, not byte-identical outputs. The newer update above closes
the formerly missing V3DX/CLE source generation and real V3D archive build,
but does not compare that archive byte-for-byte with a MetaMake build.

The completion gate includes formatting, strict workspace-wide Clippy, the
complete Rust workspace tests, all 25 CMake fixtures, three fresh 27-product
golden captures plus replays, and fresh `ninja verify` runs for all three
release profiles.

## Update 27 August 2026 — FUNCTIONS_COUNT parity is a build-time invariant

Point 50 is closed. The old configure-time warning was not a canonical
measurement: it paired duplicate basenames from different module directories
and could compare fresh Rust output with reference genmodule headers that Ninja
had not rebuilt. Its reported 25/29/30 disagreements must not be used as a
baseline.

The replacement `functions-count-audit` target registers exact declaration and
path pairs, depends on the corresponding upstream genmodule output, and checks
only Rust headers that can actually shadow that reference header. Missing,
under-sized and over-sized `FUNCTIONS_COUNT` values fail closed and publish a
stable report. The target is also part of `verify`.

`aros-genmodule` now discovers every module bound to a shared configuration,
handles explicit `conffile` and merged `confoverride` declarations, accepts
`cfunctionlist` and spaced section markers, and safely prunes only stale
unowned private libdefs headers. Fresh shadow-capable pair results are:

```text
pc-x86_64    compared=370  missing=0  under=0  over=0  mismatches=0
arm-raspi    compared=375  missing=0  under=0  over=0  mismatches=0
rpi-aarch64  compared=376  missing=0  under=0  over=0  mismatches=0
```

Point-50 verification is complete: formatting, strict workspace Clippy, the
complete Rust workspace tests, all 25 CMake fixtures, and three 27-product
golden replays pass. Real AHI and complete BSP/package targets were rebuilt for
all three profiles; their immediate repeats are Ninja no-ops. The fresh Pi
packages contain 55 ARM modules with 3,002,864 payload bytes, 10 BCM2708 modules
with 353,288 bytes, and 60 AArch64 modules with 4,052,872 bytes.

The audit portion and the complete `ninja verify` target now pass in all three
profiles; the newer update above records the policy and final counts.

## Update 27 August 2026 — workspace-wide Rust lint gate is clean

The complete Rust workspace now passes
`cargo clippy --workspace --all-targets -- -D warnings` on Rust 1.96. The
remaining findings in `aros-genmodule`, `aros-transpiler` and `aros-cli` were
fixed without crate-wide or workspace-wide lint suppressions. The changes are
semantic-preserving cleanups: output construction, option handling, typed
configuration state, path parsing, checked integer conversion and removal of
stale code.

The complete workspace test suite and formatting gate pass. Because the
generator and transpiler are configure-time host tools, their release binaries
were rebuilt and the real AHI target was rebuilt for `pc-x86_64`, `arm-raspi`
and `rpi-aarch64`. Immediate repeats are Ninja no-ops, and all 73/85/85
declared products remain byte-identical to the pre-change baseline.

## Update 27 August 2026 — typed native AHI runner

The closed AHI lane now executes through the checkout-local Rust
`aros-ahi-runner`; the former 622-line `cmake/RunAhiBuild.cmake` interpreter
has been deleted. CMake only generates the contract and invokes the runner.
`aros hosttools build/check` treats the runner as a required release host tool,
so a fresh checkout cannot configure an AHI build edge whose executor is
missing.

The runner accepts exactly 44 generated fields in the literal
`set(NAME [==[value]==])` form. Missing, duplicate, unknown or executable CMake
content is rejected rather than evaluated. Typed validation closes the three
audited architecture identities, their 73/85/85 product sets, manifests,
source snapshots, derived paths, tools, feature headers, link libraries and
ELF class/machine values before any mutable staging begins. Configure and GNU
make run with a cleared environment and an explicit tool/flag contract. The
runner then validates every installed product and re-audits every checkout
source input.

Fatal diagnostics use the shared `aros-tool-diagnostics-v1` human/JSON model
and stable `AH0001`–`AH0901` codes. Optional human or
`aros-ahi-runner-log-v1` JSONL logs are disabled by default and require an
explicit local file; they contain no ambient timestamp, hostname or runner
metadata. Child-process output in a failure is bounded to 64 KiB per stream.

The focused fixture passes all three modes under a hostile environment and
covers actual collector execution, no-op and repair behaviour, missing tools,
path whitespace, source immutability and symlink rejection. Real native
rebuilds of `workbench-devs-AHI-subsystem` pass for `pc-x86_64`, `arm-raspi`
and `rpi-aarch64`; immediate repeats are Ninja no-ops. All 73, 85 and 85
declared products are byte-identical to the pre-runner baseline. This changes
only AROS-NG orchestration; upstream AHI source remains unchanged.

## Update 27 August 2026 — AHI final links use the shared collector

The closed AHI capability no longer invokes `ld.lld` directly. Its generated
compiler adapter now sends every final link through `aros-collect` and passes
the audited `ld.lld` as the explicit backend. Compile-only and compiler-probe
invocations remain on Clang. `AROS_COLLECT_BIN` is an explicit, absolute,
executable member of both the configure-time and runner contracts; a missing
collector fails configuration with a direct diagnostic. The build edge also
depends on the collector binary, so replacing it invalidates the AHI product
stamp.

The focused fixture proves the contract and actual collector invocation for
x86_64, ARM hard-float and AArch64, including a missing-collector failure. The
transpiler's three AHI contract tests, shell syntax and patch hygiene pass.
Real `workbench-devs-AHI-subsystem` rebuilds pass for `pc-x86_64`, `arm-raspi`
and `rpi-aarch64`, and immediate repeats are true Ninja no-ops. All 73, 85 and
85 declared products remain present. Against the pre-change baseline, only
the 13, 19 and 19 ELF link products changed; every non-ELF product remained
byte-identical. Every changed ELF contains the collected `.aros.sets` section
and none retains a raw `.aros.set.*` section.

This closes the collector-bypass defect in the current AHI path. The typed
Rust runner described in the update above subsequently replaced the
CMake-script orchestration while preserving these three-profile gates.

## Update 27 August 2026 — one collector engine and three-profile build gate

The direct CMake form and the released `collect-aros`/`collect-aros32` aliases
now feed one collection engine. Staging, ELF inspection, set and library
requirement discovery, script generation, the second link, cleanup,
diagnostics, local logging, and atomic publication no longer have two
implementations. Explicit front-end policy retains the intentional alias-only
sysroot extras, library resupply, undefined audit, AROS ABI marking and output
permissions; direct links retain their empty-second-pass optimisation and
report/retained-script interface. A failed direct second pass can no longer
replace an existing good output.

The focused gate passes 35 collector unit tests, four CLI integration tests,
warning-free collector Clippy, and the complete Rust workspace. Forced-clean
package/kernel builds pass for `pc-x86_64`, `arm-raspi`, and `rpi-aarch64`;
immediate repeats are no-ops. A controlled replay of the collector phase from
the real x86_64 `kernel-kernel.o` rule, using identical inputs, produced
byte-identical output with the pre-refactor collector from `HEAD` and the
shared engine (`a88e56bbd78201a3...` for both).

Do not overread that result: hashes of several final AROS package/ROM outputs
changed between the preceding incremental baseline and the forced-clean
rebuild, although unchanged controls such as the PC bootstrap and ARM base
package remained identical. The controlled comparison proves that this
collector refactor preserves bytes for identical inputs; it is not yet a
proof that the complete AROS build is byte-reproducible across clean rebuilds.
That broader observation should be isolated separately rather than folded
into the collector work. The typed AHI-runner refactor described in the update
above subsequently preserved its exact contracts and generated products.

## Update 27 August 2026 — complete deterministic toolchain matrix

The collector-inclusive v1 toolchain matrix is now byte-reproducible on all
four release hosts and all three profiles. GitHub producer run
[`33020916404`](https://github.com/metaneutrons/AROS-NG/actions/runs/33020916404)
used commit `a7add2698cca2611...`, tree `9b9188ca2360fc25...`, and recipe
`38a7e453b46659db...`: all 24 independent A/B producers and all 12 formal
byte-comparison jobs passed. This includes `arm-raspi` and `rpi-aarch64` on
Linux x86-64/AArch64 and macOS x86-64/AArch64 as well as `pc-x86_64`.

The run closed two genuine nondeterminism sources: pointer-address ordering in
Clang 11 TableGen output and volatile GitHub runner observations embedded in
the compared manifest. Observed compiler/runner details remain preserved in
separate evidence artifacts. Compatibility replay
[`33033043062`](https://github.com/metaneutrons/AROS-NG/actions/runs/33033043062)
at `30fe824af7` proved the consumer-only fixes against the unchanged verified
archives; all 12 jobs passed. This separation prevents a probe repair from
silently changing the proven producer output. The complete immutable identity,
12 archive SHA-256 values, compatibility scope and promotion boundary are in
`toolchains/HANDOFF.md`; `OPEN-POINTS.md` point 5 records the resolved matrix.

This is a complete manual proof matrix, not a published release. The next
release must use a new tag and pass the fail-closed draft/index/provenance/SBOM
workflow. The older exploratory tag `toolchain-v1-20260826-rc1` predates this
matrix and must not be moved or promoted.

## Update 26 August 2026 — relocatable release collector

Commits `15091fbe91`, `07f7d4080b`, `41f511764a`, and `ead40df509` integrate
the Rust `aros-collect` driver into every deterministic toolchain release.
Relative `collect-aros` aliases resolve only sibling LLVM tools and the
explicit Developer `--sysroot`; the PC profile adds `collect-aros32` for
`lib32`. The driver ports the complete two-pass AROS final-link contract,
including symbol sets, library requirements,
conditional pure-virtual/pthread inputs, undefined auditing, AROS ELF ABI
marking and atomic publication. The classic C collector remains available to
the normal upstream-compatible build. Upstream configure's initial
library-free compiler probe is allowed before it discovers and applies the
sysroot; links that need a collector-owned target input still require it.

Focused Rust, producer, release-CMake, crosstools-release, poisoned-environment
and real x86-64/i386 link checks pass. Two independent canonical macOS builds
of the Rust collector are byte-identical. The producer now remaps and rejects
absolute Cargo source-cache paths as well as checkout/build/install paths.
Diagnostic packages with the final contract pass complete macOS and Linux
AROS-NG, vanilla-upstream and poisoned-`PATH` x86-64/i386 paths. Formal
collector-inclusive `pc-x86_64` builds from exact commit `ead40df509`, Git tree
`beb1b7dd…`, and recipe `b89bf41c…` now pass on both available hosts. The
macOS ARM64 archive is `f283b9aa…` with payload tree `fd78489f…`; the Linux
x86-64 archive is `752697c0…` with payload tree `fdf72fcb…`. Both pass package
verification, two-root relocation, AROS-NG configure, vanilla upstream
`includes`/`linklibs` at `6e196552…`, and poisoned-`PATH` x86-64/i386 final
links. At that commit these were one clean A-build per host; the 27 August
matrix above supersedes that interim limitation and closes all profiles.

## Update 26 August 2026 — deterministic toolchain release candidate

The fail-closed producer and consumer path is implemented through
`9f84f550c0`. Runtime and host builds receive normalized prefix maps;
producer-only `llvm-config` and LLVM CMake metadata are removed before
packaging. The release graph now owns a single top-level `genmodule` build, so
parallel target-header generation cannot execute a partially overwritten host
tool. CMake propagates the AROS prefix/CPU/platform contract into its internal
compiler probes.

The downstream check now builds isolated Rust generators, configures AROS-NG
against the extracted prefix, and builds `includes` plus `linklibs` from exact
upstream commit `6e196552834ec338072dda8675cf0c3f1d2df0d6`. That complete path
passed for the final macOS ARM64 `pc-x86_64` pair from commit `9f84f550c0`,
tree `9bad0804…`, recipe `2e8be353…`. Its two archives compare byte-for-byte at
SHA-256 `d7d7e735…`. The Linux x86_64 pair from the same inputs also compares
byte-for-byte at SHA-256 `dd9935e8…` and passes the same full compatibility
probe. Exact evidence paths and the no-overclaim completion gate are in
`toolchains/HANDOFF.md`. The workflow now initializes recursive submodules so
the clean CI consumer has the same complete source topology used by the local
probes.

This was the first two-host `pc-x86_64` proof. The 27 August matrix above
subsequently produced and byte-compared all four hosts times three target
profiles. Publication itself still requires a new reviewed tag run.

## Update 26 August 2026 — enterprise transpiler diagnostics and publication

`aros-transpiler` now carries structured fatal diagnostics with stable
`AT0001`–`AT0007` codes, typed stage/severity, source context and hints. Use
`--diagnostic-format json` for the versioned `aros-tool-diagnostics-v1`
document; its stderr stream is kept free of progress bars and tracing.
Capability failures are classified at the owning parser branch rather than by
matching words in rendered messages.

Every coverage report is indexed in
`generated_targets.coverage.json` (`aros-transpiler-coverage-v1`) with stable
`AT1001`–`AT1032` codes and explicit info/warning severity. Zero-count entries
remain visible. These are live observations, not accepted-count pins.

The generated CMake graph, source inventory, spec-switch manifest, coverage
index and all reports now publish through one staged, rollback-capable
transaction. The graph is replaced last as the commit marker. Report write and
removal failures are fatal. Tests cover pre-commit failure, injected
mid-commit rollback and stale-report deletion. The remaining narrow
capability-fingerprint registry is validated without panic before the source
walk.

Verified in the final local gate: 293 transpiler library tests, six binary/CLI
tests, the complete Rust workspace, all 24 CMake fixtures, and direct x86_64,
ARM hard-float and AArch64 profile runs are green. The later workspace-wide
lint cleanup recorded at the top of this file also makes the strict
all-targets Clippy gate warning-free.

## Update 26 August 2026 — no hidden transpiler package pins

On `integration/upstream-20260826`, the transpiler package/archive pins were
removed. Mesa, Mako, MarkupSafe, CUnit and libaom now follow their upstream
`%fetch` declarations; local scripts and patches are direct dependencies.
Only 14 documented fingerprints remain for opaque Mesa recipe fragments and
source inventories which are expanded into hard-coded jobs. Drift in one of
those inputs is fatal and explicitly requests a transpiler update.

The fixed per-file and redundant caller-provided hashes for configure, AHI and
SFDC were also removed. Their checked-in manifests now contain paths only;
CMake watches every listed source and calculates a transient runner snapshot
at configure time. A source edit automatically refreshes that snapshot and
does not require a digest edit. The fixed GRUB 2.12 archive SHA remains once in
`cmake/GrubSourceLock.cmake`, because that closed CMake lane downloads the
source directly. Toolchain release locks are a separate reproducibility
contract.

The unrelated broad `aros-verify` fingerprints of the complete LLVM
MetaMake/config/CMake inputs have also been removed. The verifier now checks
only the structural facts and exact declaration contracts that make the
applicable LLVM and GCC producer lanes provisioning rather than target
obligations; relevant drift still fails closed, while unrelated upstream edits
do not require a hash refresh.

Core error handling aggregates and fails on filesystem traversal, fetch
discovery, parsing and recognised capability drift. The typed-diagnostic,
machine-readable output and transactional report/publication work is completed
in the update above; `OPEN-POINTS.md` point 52 records the closed gates.

Verified in this change: all 291 transpiler unit tests and all integration
tests pass; the affected CMake fixtures pass, including real AHI and GRUB
contracts; direct x86_64, ARM hard-float and AArch64 transpiler runs each emit
a complete graph.

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

The direct ARM and AArch64 Raspberry Pi package lanes now build cleanly too.
The named full-package targets produce a 55-module ARM BSP, its 10-module
BCM2708 supplement, and a 60-module AArch64 BSP; an immediate second build is a
true Ninja no-op:

```text
build/arm-raspi/SYS/aros-arm-bsp.rom          55 modules, 3,002,864 payload bytes
build/arm-raspi/SYS/aros-arm-bcm2708.rom      10 modules,   353,288 payload bytes
build/rpi-aarch64/SYS/aros-aarch64-bsp.rom    60 modules, 4,052,872 payload bytes
```

These are compile/link/package results, not Raspberry Pi boot claims. Hardware
boot verification remains to be run. The separate deterministic toolchain
producer matrix is complete as recorded in the 27 August update above.

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
- ARM and AArch64's AROS-owned Gallium modules now inherit the same checked Mesa
  20 compile contract as the fetched Mesa archives. This restores the
  `pipe/p_shader_tokens.h` path and the Mesa feature/aliasing flags which the
  classic build receives through `mesa.cfg`.
- Bootstrap refreshes the central `asm/cpu.h` dispatcher in `GENINCDIR` as well
  as the SDK. This repairs existing build trees which retain a same-named
  foreign-architecture header from the old unfiltered staging implementation.
- `usb2otg` includes the standard declaration for the `memset` calls it already
  makes; the complete device now compiles for both ARM and AArch64.
- Exact build-time `FUNCTIONS_COUNT` parity is enforced for every private Rust
  header that can shadow an upstream genmodule header; point 50 is closed.

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

The Raspberry Pi package build checks are:

```bash
cmake --preset rpi-aarch64
ninja -C build/rpi-aarch64 -j 8 kernel-package-raspi-aarch64-file

cmake --preset arm-raspi
ninja -C build/arm-raspi -j 8 \
  kernel-package-raspi-arm-file \
  kernel-package-arm-bcm2708-file
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
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

The strict Clippy gate is clean on Rust 1.96 without workspace-wide or
crate-wide lint suppressions.

From the repository root:

```bash
for t in cmake/tests/*Test.cmake; do cmake -P "$t" || exit 1; done
git diff --check
```

The CMake sweep takes roughly ten minutes on the current macOS host, mostly in
`GrubBuildTest.cmake`.
The Rust workspace, every CMake fixture including the real GRUB host build and
the new source-inventory, preset-toolchain and SMBIOS-validation fixtures, and
both packaged PC boots are green as of this handoff. The thematic commit IDs
are the newest entries in `git log`.

For byte-for-byte transpiler refactors use `aros golden capture` and
`aros golden verify`. They replay the recorded argv from
`generated_targets.cmake.invocation`; baselines live under `build/golden/` and
are not committed.

## Next work

1. Boot the ARM and AArch64 packages on the intended Raspberry Pi hardware and
   capture UART evidence; the ROM packaging gate is clean, but runtime is not
   yet proved.
2. Continue point 25 so an unqualified full build can pass; the clean result is
   for the architecture's complete BSP package targets, not every unrelated
   third-party application target.
3. Cut and review a new deterministic toolchain release tag; the manual matrix
   proof is complete, but no release should reuse the stale exploratory tag.
4. Add later boot milestones if Workbench/Shell readiness must be asserted
   automatically rather than inferred from the serial log.

## Working agreements

- Transpile upstream MetaMake semantics instead of adding target-specific glue.
- Keep architecture exceptions exact and test them across all current profiles.
- Anything unsupported is reported and fails closed; it is never silently
  dropped.
- Split work into thematic commits and never add a Codex co-author trailer.
