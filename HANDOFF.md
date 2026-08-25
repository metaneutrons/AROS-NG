# Handoff

Written 25 August 2026, on `feat/cmake-build-propagation` (225 commits ahead of
`main`, working tree clean). This is the short document: enough to start a fresh
session without re-deriving the environment. `OPEN-POINTS.md` carries the
findings themselves and is the authority wherever the two disagree.

## Where the boot stands

The PC target boots the bootstrap, loads the kickstart, brings up exec and the
kernel resource, and dies in `InitResident`:

```
Software Failure!  Error 0x80000003 - Illegal address access
Module usbromstartup.resource Segment 2 .text
Function __strncmp_StdCBase_wrapper + 0x11
Stack: Exec_17_InitResident <- Exec_12_InitCode <- kernel_cstart <- start64
```

That is point 48. `usbromstartup.resource` is built by `%build_module_simple`,
which generates no InitLib, so the module's `StdCBase` is never opened and the
first stdc call jumps through a null base. Ten modules still carry
`__aros_set_LIBS___aros_libset_StdCBase`; the fix pattern that worked three times
is `USER_LDFLAGS := -static -nostdc` in the module's mmakefile, which selects the
static C runtime instead of the shared library (`config/elf-specs.in:19` --
`-nostdc`, not `-static`, is what does it). For Poseidon that flag is
file-global and would also hit `poseidon.library`, which is why it is still open.

Memory is sound as of today: `SysBase->MemList` walks four `NT_MEMORY` headers,
ROM last at priority -128, terminating at `&lh_Tail`. Point 27g has the story of
how it was not.

## Build and boot

```bash
cmake --preset pc-x86_64
```

```bash
ninja -C build/pc-x86_64 -j 8 SYS/boot/pc/kernel
```

```bash
tools/aros-tools/target/release/aros test --preset pc-x86_64 --packages
```

Presets: `pc-x86_64`, `rpi-aarch64`, `rpi4-aarch64-debug`, `arm-raspi`. A full
`ninja` still stops in the C++ Ports (`cstdint` not found in libde265), which is
point 25 -- build the boot targets by name rather than everything.

For watching a boot by hand there is `scripts/boot/qemu-pc-x86_64.sh`. `aros
test` is deliberately non-interactive: it asserts from the serial log and the
QEMU exception trace.

### The trap that cost the most time today

CMake runs the **release binaries** at configure time:
`tools/aros-tools/target/release/aros-genmodule` and `.../aros-transpiler`
(`CMakeLists.txt:20-26`). Editing the Rust source and re-running `cmake` changes
nothing until the binary is rebuilt:

```bash
cargo build --release --manifest-path tools/aros-tools/Cargo.toml -p aros-genmodule -p aros-transpiler
```

Two related surprises worth knowing. Our genmodule writes its libdefs at
*configure* time into `build/<preset>/gen`, so those files are not Ninja targets
and never appear in `build.ninja`; and it only rewrites bytes that changed, so an
old mtime does not mean an orphan. Both of those misled me for a while (point
50).

## Gate before committing

From `tools/aros-tools`:

```bash
cargo fmt --all --check && cargo clippy --workspace --all-targets && cargo test --workspace
```

From the repository root:

```bash
for t in cmake/tests/*Test.cmake; do cmake -P "$t" || echo "FAIL $t"; done
```

```bash
git diff --check
```

The fixture sweep costs about five minutes, 254 seconds of it `GrubBuildTest`
alone; the other twenty run in 45 seconds together. `toolchains/HANDOFF.md`
explains why each check is in the list -- each was added after a commit passed a
shorter gate and broke something.

When refactoring the transpiler, the byte-for-byte baseline is
`aros golden capture` / `aros golden verify`; it replays the recorded argv from
`generated_targets.cmake.invocation` rather than re-deriving it, and it captures
twice, refusing a baseline that is not reproducible. Baselines live in
`build/golden/` and are not committed.

## Debugging recipes that worked

**Read guest memory.** Back the guest RAM with a file and inspect it after the
run:

```bash
qemu-system-x86_64 -object memory-backend-file,id=guest-ram,size=512M,mem-path=ram.bin,share=on -machine q35,memory-backend=guest-ram -cpu qemu64,+avx2 -smp 1 -m 512 -no-reboot -display none -append " debug=serial" -serial file:boot.log -kernel build/pc-x86_64/SYS/boot/pc/bootstrap -initrd "build/pc-x86_64/SYS/boot/pc/kernel,<pkgs>"
```

Then seek to the physical address directly; `SysBase` is at `0x1002870` and its
`MemList` head at `0x1002ae0` in the runs recorded so far, but confirm rather
than assume.

**Data watchpoints.** Start QEMU with `-S -s` and drive lldb in batch:

```
gdb-remote 1234
watchpoint set expression -w write -s 8 -- <addr>
continue
register read rip rsp rdi rsi
memory read -s8 -c10 -f x $rsp
```

Registers at a hit are only trustworthy as arguments when the hit is a few bytes
into the function; `rdi` reading `SysBase` fooled me into naming the wrong
argument until the stack settled it. Read the stack, not just the registers.

**Resolve a kickstart address to a symbol.** `/usr/bin/nm` reads the kickstart
ELF (there is no `llvm-nm` or `llvm-objdump` in PATH on this machine, and
`llvm-readelf` is absent too -- Python's `struct` over the section headers is the
reliable fallback for anything nm cannot answer). Offsets are section-relative
because the kickstart is `ET_REL`. In the runs so far the load base was
`0x17b2000` with `.text` at read-only offset `0x120`, so
`.text offset = rip - 0x17b2000 - 0x120`; derive both per run rather than reusing
the constants. The boot check in `tools/aros-tools/crates/aros-cli/src/boot.rs`
does this properly and reports how it located a fault -- by arithmetic, by bytes,
or by bytes with the drift from the arithmetic named.

## What to pick up

Boot-critical, in the order that unblocks the most:

- **48** -- `usbromstartup.resource`, the current fault. Ten modules still open
  stdc at init. The Poseidon mmakefile needs the flag scoped so it misses
  `poseidon.library`.
- **50** -- 25 of 366 modules disagree between our genmodule and the reference on
  `FUNCTIONS_COUNT`. The configure step now names them all. Where ours is
  smaller (`parallel` and `serial` are devices, so `firstlvo` is 7; `bz2`,
  `expat`, `freetype2`, `popupmenu` read as having no function list at all) the
  base is under-allocated, and that is the shape that corrupts memory. Where
  ours is larger it only wastes space.
- **25 / 24** -- the C++ Ports keep a full `ninja` from finishing.
- **22** -- ACPICA is a fetched Port that `kernel-kernel` needs.

Structural, no boot dependency:

- **47** -- `parse_mmakefile_impl` runs from parser.rs:720 to 2366, 1647 lines of
  the file's 5251. Four of its five phases are extractable; the declaration loop
  needs a design.
- **34** -- `collect_extra`. **35** -- `aros/config.h`, 15 of 20 values absent.
  **9** -- three clippy false positives.

## Environment

zsh with `noclobber`, so `>` and even `>>` fail on a file that does not exist the
way you expect -- `: > file` first. `rm` and `mv` are interactively aliased; use
`/bin/rm -f` and `/bin/mv -f`. `grep` is ugrep and has regex complexity limits.
`--include=*.c` fails on `nomatch` unless quoted. There is no `/usr/bin/timeout`;
poll with a `kill -0` loop instead. `cargo` needs
`--manifest-path tools/aros-tools/Cargo.toml` from the repository root.

## Working agreements

- Transpile rather than write glue config. Anything skipped gets reported, never
  dropped silently.
- Bugs in AROS sources go on `pr/*` branches cut from `master`, so they can be
  sent upstream. Three exist: `pr/bootloader-nostdc`, `pr/oop-nostdc`,
  `pr/debug-registermodule-no-stdc`. Their changes are also present on this
  branch, because the build needs them.
- Split work into thematic commits.
- Macro support is complete for every architecture, not only the ones currently
  built.
