# Open points

Status date: 2026-08-27. Open entries are undecided or unfinished; resolved and
superseded entries retain the evidence so it does not have to be rediscovered.

Marker meaning:

- **DECIDE** waiting on a decision, not on work
- **WORK** decided or obvious, not done
- **RISK** a latent defect that has not bitten yet, or has bitten once
- **WRONG** something recorded elsewhere in this tree that is not true

---

## Toolchain producer

### 1. DECIDE — boost is a hard dependency of the shipped SDK headers

`compiler/include/aros/preprocessor/` has nine headers that include boost
unconditionally, and `inline/posixc.h` reaches them, so any C source that
touches `proto/posixc.h` needs boost:

    nixmain.c -> proto/posixc.h -> inline/posixc.h
      -> aros/preprocessor/variadic/cast2iptr.hpp
      -> aros/preprocessor/variadic/size.hpp
      -> boost/preprocessor/cat.hpp        (not found)

Without boost the release package ships a `Developer/include` that cannot
compile such a source. boost is a fetched Port here
(`compiler/boost/mmakefile.src`, 1.89.0, archives.boost.io) attached to
`ports-includes`, and `CROSSTOOLS_PORTS_INCLUDES` is empty in release mode, so
it has never been available in a producer run.

This is not a consequence of the include-closure narrowing; it predates it and
was only reached once the port fetches stopped happening first.

Measured costs, because the first estimates were wrong in both directions:

- The archive is **190 099 283 bytes** (`content-length`, verified by HEAD),
  for what amounts to `boost/preprocessor` and `boost/config`.
- `toolchains/source-lock-v1.schema.json` has `additionalProperties: false`
  and `family: {"const": "llvm"}`, with only `sources` and
  `host_python_packages`. There is **no slot for a port source**, so pinning
  boost means a schema change plus matching work in `producer.py`
  (prefetch, verify, package) and in the recipe's `source_lock_sha256`.
- `%copy_dir_recursive` in `compiler/boost/mmakefile.src:27` stages **all** of
  boost into `$(GENINCDIR)/boost` and `$(AROS_INCLUDES)/boost`, not just the
  two directories needed.
- Removing the dependency instead is **not** the small patch I first called it.
  Across the nine headers the surface is 23 distinct macros, including
  `BOOST_PP_REPEAT`, `BOOST_PP_EQUAL`, `BOOST_PP_DIV`, `BOOST_PP_MUL`,
  `BOOST_PP_ARRAY_*`, `BOOST_PP_TUPLE_ENUM` and `BOOST_PP_IS_EMPTY`. That rests
  on boost's arithmetic and iteration machinery; replacing it is writing a
  preprocessor library, not deleting an include.

There is also `compiler/boost/boost_1_89_0-aros.diff`, which the `%fetch`
applies, so any pinned copy has to account for the patch.

### 2. RESOLVED — the root tools graph owns one complete genmodule build

A lane failed with `Bus error: 10` on
`gen/compiler/crt/stdc/stdc/include/.stdc.library-includes`. genmodule run by
hand with the same arguments succeeds, and the log shows genmodule's own
sources (`functionhead.c`, `muisupport.c`, `writefd.c`, `writelinkentries.c`)
being compiled immediately before. Under `-j 8` the recipe executes a
partially written binary.

Every generated directory makefile carried the same `$(GENMODULE)` recipe, so
parallel recursive makes could overwrite the host executable while another
directory was running it. The tree-wide `includes` target used to hide that
race as an accidental barrier; the narrowed release graph exposed it.

`0e3c136be5` makes the top-level `tools` target depend on one root-owned
`$(GENMODULE)` build. The fragment is included only when the real path of the
active makefile is the root `$(TOP)/Makefile`; using `realpath` is required on
macOS because `/tmp` is reached as `/private/tmp`. A fresh out-of-tree
`gmake -j16 tools` built `genmodule` exactly once and completed successfully.
The static producer contract checks both the root-only guard and the explicit
prerequisite.

### 3. WORK — the non-release include form is untested

`compiler/include/mmakefile.src` now offers `sdk-includes-0` and
`sdk-includes-1`. Only the release form has been exercised; this tree is
configured with `--enable-toolchain-release`. `sdk-includes-0` is a faithful
copy of what the three call sites had, except that `compiler/atomic` and
`compiler/libinit` now also name `includes-copy`, which `includes` already
implied through `includes-generate-deps`.

### 4. RESOLVED — the release collector is relocatable

Commits `15091fbe91`, `07f7d4080b`, `41f511764a`, and `ead40df509`
deliberately leave the classic C collector in the upstream build path and ship
a release-facing Rust implementation instead. `collect-aros` and the PC
profile's `collect-aros32` are relative aliases of sibling `aros-collect`; the
driver resolves only sibling `ld.lld` and `llvm-strip`, and takes libraries
exclusively from the caller's absolute Developer `--sysroot` (`lib32` for the
32-bit alias). It
never uses `PATH`, `COMPILER_PATH`, or a compiled-in producer prefix. The one
intentional no-sysroot case is upstream configure's initial library-free
compiler probe; a collector-discovered target input still requires the
absolute Developer root and reports that requirement directly.

The package and lock contracts require the aliases. The direct Clang/Clang++
compatibility probe poisons `PATH`, checks the symbol-set and C++ initializer
structure plus AROS OSABI, and tests both x86-64 and i386 in the PC profile.
The remaining boundary is explicit rather than hidden: the toolchain release
does not contain a Developer SDK/sysroot. A future application workflow must
obtain that as a separately versioned artifact.

The Rust binary initially retained absolute source locations for dependencies
compiled from Cargo's verified vendor cache. Linux's prefix scan caught this
because its cache name shared the checkout prefix; macOS's differently named
cache proved that this was not a sufficient invariant. `ead40df509` remaps the
entire source cache to `/usr/src/aros-sources` and scans that cache path
explicitly during packaging, independent of directory naming.

### 5. RESOLVED — the complete four-host release matrix is reproducible

Producer run
[`33020916404`](https://github.com/metaneutrons/AROS-NG/actions/runs/33020916404)
built the collector-inclusive release from exact commit `a7add2698cca2611...`,
tree `9b9188ca2360fc25...`, recipe `38a7e453b46659db...`, and source epoch
`1787784543`. All 24 independent producers completed: A and B for every
combination of Linux x86-64/AArch64 and macOS x86-64/AArch64 with
`pc-x86_64`, `arm-raspi`, and `rpi-aarch64`. All 12 formal comparison jobs
accepted the resulting archives as byte-identical.

The run found and closed two real reproducibility defects before reaching that
result. Clang 11 TableGen used pointer order for generated attribute switches;
the local LLVM patch now orders records by name. GitHub runner `ImageVersion`
also varied between independent Linux ARM64 jobs; actual runner observations
remain preserved as separate evidence artifacts, while the archive records the
stable host contract. The payload and archive are therefore deterministic
without pretending the two runner instances were identical.

The first compatibility pass exposed consumer-harness defects only after the
archives had compared successfully: incomplete audited macOS GRUB
prerequisites, the wrong upstream output-directory spelling for ARM, unwind
metadata in a deliberately library-free smoke link, and Bash 3's empty-array
behaviour. Replay workflow `toolchain-compatibility-replay.yml` consumed the
exact verified artifacts from the producer run at fix commit `30fe824af7`;
replay run
[`33033043062`](https://github.com/metaneutrons/AROS-NG/actions/runs/33033043062)
passed all 12 lanes. It did not rebuild or silently replace an archive. The
complete SHA-256 table and immutable identity are in `toolchains/HANDOFF.md`.

The manual matrix proof closes reproducibility, not publication. A reviewed
new tag run must still generate the draft release, provenance, SBOMs and final
index. The old exploratory `toolchain-v1-20260826-rc1` tag predates this proof
and must not be moved or promoted.

### 6. DECIDE — job count for the byte-comparison

The final macOS A/B pair ran with `--jobs 5` for each copy and the final Linux
A/B pair with `--jobs 2` for each copy. Each same-host pair is byte-identical.
The producer sets `SOURCE_DATE_EPOCH`, `ZERO_AR_DATE` and the prefix maps
itself, so the job count should not affect the output, but cross-job-count
identity has not been verified by comparing two otherwise identical runs at
different parallelism.

---

## The path to a graphical boot

A full CMake build of pc-x86_64 on 2026-08-23 after the Boost staging fix:
16378 of 16611 steps completed, 887 steps failed, 1496 errors.

### 37. PARTLY RESOLVED — 11 declared sources resolve to no file, down from 94

`aros_resolve_sources` used to drop a missing in-tree source with a bare
`continue`, so a target quietly built with fewer objects than its declaration
names. Now reported in `generated_targets.missing-sources.txt`, and there are 94.

The report earned itself twice over. `linklibs-udis86`'s generated `itab` was one
entry, which is why that failure showed up as a missing *header* one step away
from the cause. And 82 of the 94 were two bogus sources named `DEFAULT_MODTYPE`
and a modtype, on each of the 41 gadget, mcc and datatype declarations -- not a
Make-variable problem as first read here, but a CMake keyword that was read
without being declared, which is point 39.

Eleven remain and each looks genuine: `pfs3`'s `ks13wrapper`, android's
`androidgfx_bitmap`, six audio plugins of `diskimage-cue`, `Editor`'s `Prefs`,
and two kernel arch names that another declaration legitimately claims.

### 36. RESOLVED — udis86's instruction tables are generated

`aros-base.pkg` holds utility, oop, dos, intuition and 22 more, and the boot task
asked for exactly those. It did not build because `linklibs-udis86` did not:
`itab.c` and `itab.h` come from an in-tree Python script over an in-tree XML
table (`arch/all-pc/udis86/mmakefile.src:26`), and nothing modelled the rule. The
linklib already named the generated `itab` as a source and `udis86-includes-gen`
already copied `itab.h`; only the producer was missing.

The survey this point asked for came first, and its answer is no: the 21 rules in
`generated_targets.generated-file-rules.txt` are not one shape. Five are windres
compiles for mingw32, eight the m68k-amiga ROM link chain, two plain compiles
into `$(GENDIR)`, two the stdc Unicode tables, one a config copy, one an object
from `$(GENERATED)` -- and one, this, a Python generator. One modelled form would
not have covered them, so the modelled shape is narrow and the other twenty stay
reported.

`aros_generate_intree_script_outputs` is deliberately not
`aros_generate_python_outputs`. The latter exists for a *fetched* generator and
spends most of its length on integrity -- archive and driver digests, package
roots, a runner script -- which for a script and an input that are files in this
repository would state the same fact twice. What it shares is the part consumers
need: every output is registered under `AROS_PYTHON_OUTPUT_OWNER_<hash>`, which
`aros_resolve_sources` consults before it probes the filesystem.

The rule names `itab.c` and the script also writes `itab.h`. Rather than infer
the second output from the `%copy_includes` declaration beside it, the consumer
binding carries it: `add_dependencies` orders every object of the archive after
the generator, and one process writes both files.

Failed build steps 1083 -> 1078, generated-file rules 21 -> 20, missing sources
94 -> 93, `aros-base.pkg` built with all 26 members. The boot then moved on to
the next dangling symbol, which is point 38.

### 50. RESOLVED — exact build-time libdefs parity replaces the invalid configure audit

Most modules have two `<mod>_libdefs.h`. Ours goes to `${CMAKE_BINARY_DIR}/gen`
during configure, from the Rust genmodule's `--scan-dir` pass; the reference one
goes to `genmodule/<module>/gen` from a Ninja rule running `hosttools/genmodule`.

The compile reaches ours. `LC_LIBDEFS_FILE` expands to a quoted name, a quoted
include searches every `-iquote` before any `-I`, and `gen/<module>` is on the
quoted path while the genmodule directories were only ever added as `-I`. The
`-I` order suggests the opposite, which is what made this hard to see.

**Correcting this point's first diagnosis.** It read the gen/ files as residue
from an earlier arrangement, on the strength of their two-day-old timestamps and
their absence from `build.ninja`. Both observations were real and the conclusion
was wrong. They are absent from `build.ninja` because they are written at
configure time, not built; their timestamps were old because the writer only
rewrites a file whose bytes changed. Deleting them, as this point first
suggested, achieves nothing: the next configure writes them back.

What was actually wrong was the value in them. Measured before the fix, of the
340 modules with a file in both trees, 338 resolved to ours, and 307 of those
carried a different `FUNCTIONS_COUNT` -- the number that sizes a library base's
jump table. For kernel.resource ours said 59 where the reference said 71, and
point 27g follows that to the corrupted ROM MemHeader.

Three changes:

1. `functions_count()` takes the highest LVO rather than the function count, so
   `.skip` reservations are counted. 312 disagreements out of 346 became 21.
2. `first_lvo()` gained `mcc`, which belongs with `mui` and `mcp` at 6
   (`config.c:521`). 20 Zune classes declared `modtype=mcc` had been falling
   through to the library default of 5. 21 became 6.
3. `_aros_add_genmodule_quote_dirs()` puts the genmodule directories on the
   quoted path too, so the reference file wins wherever nothing else claims
   precedence. 338 resolving to gen/ became 6 -- the remainder are modules where
   `aros_bind_flexcat_source_consumers()` adds its generated directory with
   BEFORE, which it does for a good reason and which no ordering here can
   outrank.

The later configure-time counts of 25, 29 and 30 were not a valid parity
measurement. `_aros_report_disagreeing_libdefs()` indexed reference headers by
basename, so same-named modules such as the architecture-specific serial,
Bluetooth and PNG variants could be paired with a different declaration. It
also compared configure-time Rust output against reference output that Ninja
had not necessarily rebuilt. Some apparent defects disappeared as soon as the
right reference edge was run; stale Rust private headers could distort the
other side too.

The replacement is an exact build-time gate:

* every concrete upstream genmodule output is registered by declaration
  identity and full path, never by basename;
* only an existing Rust header that can actually shadow that exact reference
  header is compared;
* the audit depends on the upstream genmodule output, so the reference side is
  rebuilt before comparison;
* missing counters, under-allocation and over-allocation all fail closed and
  are written to a stable `aros-functions-count-audit-v1` report;
* `functions-count-audit` is attached to the normal `verify` target.

The Rust scanner now models all declarations bound to a shared configuration,
not just the first one. It understands explicit `conffile` and
`confoverride` bindings, merges an override with its base configuration, and
accepts both `functionlist` and `cfunctionlist` with upstream-compatible
section-marker whitespace. It also removes only stale, unowned private
`*_libdefs.h` outputs and fails closed if pruning cannot be completed.

Fresh reports for every shadow-capable header pair after complete package
rebuilds are clean:

```
pc-x86_64    compared=370  missing=0  under=0  over=0  mismatches=0
arm-raspi    compared=375  missing=0  under=0  over=0  mismatches=0
rpi-aarch64  compared=376  missing=0  under=0  over=0  mismatches=0
```

The fixture separately proves equal same-basename pairs and failure/reporting
for missing, under-sized and over-sized headers. All 25 CMake fixtures, the
complete Rust workspace tests, strict workspace Clippy, three 27-product golden
replays, the real AHI targets and all complete PC/ARM/AArch64 BSP package lanes
pass. Immediate repetitions of all real build targets are Ninja no-ops.

### 49. RESOLVED — the load model was one pointer width out

The model now places all 50 modules exactly where the loader does, and the boot
check says so of its own accord:

```
v=0e cpl=3 IP=0x1acf8c1 = usbromstartup.resource .text+0x7f1
    (by arithmetic, confirmed by its bytes) = __strncmp_StdCBase_wrapper+0x11
```

**The defect was one value.** The alignment step before each module's debug
descriptor is `(p + sizeof(void *)) & ~(sizeof(void *) - 1)`, and the model took
`sizeof(void *)` from the module. It comes from the *bootstrap*: on PC that is
32-bit code building 64-bit structures -- it links `gen/lib32/libbootstrap.a`,
and `bootstrap/elfloader.c:31` says as much in a comment -- so the step is 4
while the descriptor it writes is the 40-byte 64-bit one. Reading the width from
the bootstrap's own ELF class fixes it, and a test pins both widths plus the
unreadable case, which must not fall back to the narrow one.

**How it was found: by asking the loader.** `bootstrap/elfloader.c` has its
debug output behind `#define D(x)`, empty in the shipped build. Enabling it for
one run makes the loader print every module's load address and every section's
size and alignment, 568 chunk lines in this boot. Comparing that against the
model, module by module, gave:

```
Kickstart ELF        real 0        model 0        +0
console.device       real 3ea52    model 3ea56    +4
input.device         real 4b8c7    model 4b8c7    +0
hiddclass.hidd       real 67768    model 6776c    +4
gfx.hidd             real 6c677    model 6c687   +16
...
FileSystem.resource  real 1d3079   model 1d30b9  +64
```

which is what settled it: the error was not the constant it first looked like,
and it was not monotonic either -- a following section with a 16-byte alignment
absorbs a 4-byte error, so the drift appeared and vanished until it accumulated
past the next alignment. Both wrong hypotheses (a 36-byte descriptor, an 8-byte
step with a 36-byte descriptor) were rejected against all 50 modules in one run
each.

The kickstart's own twelve read-only chunks matched exactly throughout, which is
what pointed at the descriptor rather than at the section packing.

### 48. RESOLVED — upstream `-static` semantics remove early StdC dependencies

The final fix is central and matches the AROS compiler drivers. Their GCC and
Clang patches make `-static` suppress the shared posixc/stdcio/stdc clients and
select `libstdc.static.a`. The transpiler had discarded `-static`, while CMake
rebuilt the driver's default link set from `config/elf-specs.in`; this silently
turned upstream-static resident modules into dynamic `stdc.library` clients.

The transpiler now records `static` as a spec switch, and
`cmake/DefaultLinkSet.cmake` translates it to the checked-in external spec's
equivalent `nostdc` condition. The temporary source-level `-nostdc` workarounds
in bootloader, OOP and Poseidon were removed. This keeps the original upstream
mmake semantics and fixes every affected module rather than maintaining a list
of symptoms.

Two adjacent blockers were resolved as part of the measured boot:

  * `hidd/unixio.h` is now an exact public-header exception to the foreign-arch
    SDK filter, so `kernel-bsp-pc-x86_64-file` builds and packages ACPICA.
  * `hid.class` uses `INTUITION_INLINE_NEWOBJECT`; otherwise its two GUI sources
    pull the libamiga `NewObject` stub and `IntuitionBase`, even though HID's
    resident priority 29 runs before Intuition's priority 15.

After rebuilding the kernel and all six package files, a complete scan of all
76 packaged ELF modules found zero strong dynamic StdC startup/base
dependencies. The 20-second PC x86_64 run reached user mode with no reported
failure and no CPU exception. Evidence is in `build/pc-x86_64/boot-check`.

The boot auditor also learned that QEMU records beginning `Servicing hardware
INT=...` are ordinary hardware interrupts, not guest CPU faults. A regression
test preserves the distinction.

One packaging trap remains relevant: `aros test --packages` consumes existing
`.pkg` files but does not build them. Every package target must be rebuilt before
a result can be attributed to current code.

### 51. RESOLVED — the direct PC build and boot are clean on macOS and Linux

The same packaged pc-x86_64 graph now builds and boots on macOS and CachyOS
Linux. Both final post-refactor 20-second runs loaded seven multiboot modules,
reached user mode and reported neither a guest exception nor another boot
failure. Linux used QEMU 11.0.2; macOS used QEMU 11.1.0. The Linux evidence is
on `cachy` at
`/home/fabian/aros-ng-linux-check.uyLICC/evidence-linux-pc-x86_64-smbios-final`;
the final macOS evidence was written to
`/tmp/aros-ng-evidence-macos-pc-x86_64-smbios-final`.

The cold Linux build found four ways the direct graph had depended on the macOS
host without stating it:

  * configure presets left the compiler implicit, so CachyOS selected GCC while
    the target graph assumes the LLVM path; every direct preset now pins
    `clang`, `clang++`, the ASM compiler and `AROS_TOOLCHAIN=llvm`;
  * CachyOS Clang enables strong stack protection by default even for the i386
    target triple, leaving the freestanding bootstrap with
    `__stack_chk_fail`; the target compile contract now says
    `-fno-stack-protector` explicitly;
  * CMake 3.27 and newer added `-Xlinker --dependency-file` for a linker it
    believed was compiler-driven, but AROS invokes `aros-collect` and lld
    directly; direct lld links now disable that CMake facility;
  * a cold parallel build could compile CDVDFS before the codesets public
    headers it includes existed; the three CDVDFS MetaMake targets now state
    that dependency.

The first Linux boot then proved the binaries were not the problem: ACPICA's
code was byte-identical modulo addresses between the two hosts. QEMU 11.0.2's
legacy ROM window contains ordinary firmware text beginning
`_SM3_\0etc/extra-pci-roots...` before its real SMBIOS 2 entry point. Two AROS
scanners accepted the substring without checking the entry-point length or
checksum and interpreted the ASCII bytes `pci-root` as a table address.
ACPICA faulted first; once fixed, the later `smbios-ipmi.hidd` scanner exposed
the same defect.

Both scanners now validate SMBIOS 2/3 anchors, declared lengths and checksums
(including SMBIOS 2's intermediate DMI checksum), read entry fields without
unaligned accesses and bound every structure/string walk by the advertised
table size. The SMBIOS 3 header layout was corrected so its maximum table size
precedes its 64-bit table address as the specification requires. The first
patched Linux run reached user mode but named the second scanner's fault; the
second reached user mode cleanly. This host/version difference is now useful
integration coverage rather than unexplained nondeterminism.

**Historical investigation below.** It records the intermediate per-module
`-nostdc` experiments that proved the dependency mechanism. Those experiments
were superseded by the central `-static` interpretation above.

With point 41 fixed the boot task runs and reports for itself:

```
Exec Bootstrap Task: Could not open version 0 or higher of library "stdc.library".   (5x)
Exec Bootstrap Task: Could not open version 42 or higher of library "oop.library".
Exec Bootstrap Task: Could not open version 0 or higher of library "oop.library".    (2x)
Software Failure! Task : input.device, Function ProcessEvents +0xFA
```

The chain, each step measured:

  * **stdc.library is in no loaded package, and that is correct.**
    `rom/mmakefile.src:145` lists `BASE_LIBS := aros dos dos64 gadtools graphics
    intuition keymap layers oop utility`, and our package has exactly those 26
    members. stdc.library is built to `SYS/Libs/`, a file for a filesystem that
    does not exist yet.
  * **oop.library requires StdCBase**, so it goes down with it, and everything
    OOP-based follows: gfx.hidd, keyboard.hidd, mouse.hidd, inputclass.hidd,
    graphics, intuition, gameport.device, keyboard.device. `input.device` dying
    in ProcessEvents is the tail of that. Its version is not at issue --
    oop.conf states 43.1 against the requested 42.
  * **bootloader.resource, dosboot.resource and lddemon.resource require it
    too**, and those initialise before any filesystem exists:
    `rom/bootloader/bootloader.conf` sets `residentpri 100`, oop.conf 94.

**Why they require it, and it is not the link.** `bootloader_init.c:43` calls
`strlen`, `:54` calls `stpblk`. In `libstdc.a` those resolve to
`stdc_strlen_stub.c.obj`, which carries `U StdCBase` -- an undefined reference
to the base. The base is defined in `stdc_autoinit.c.obj`, so the linker must
pull that object in, and it carries
`__aros_set_LIBS___aros_libset_StdCBase`. LIBS is the set
`compiler/autoinit/libraries.c:18` defines and `_set_open_libraries_list` walks
at init, calling `OpenLibrary` and printing exactly the message above on
failure.

So: **one stdc call anywhere in a module means the module opens stdc.library
when it initialises.** Nothing about the call site matters, only that it exists.

**This is not our build.** Both objects are generated by genmodule from
`compiler/crt/stdc/stdc.conf`, the same source mmake uses, and the archive
structure follows from that rather than from how the link is driven. No linker
can take the stub without the base, and no build can take the base without the
LIBS entry. A comparison build under mmake would measure the same two objects.

That leaves the real question, which is about AROS rather than about us: a
resource that initialises at resident priority 100 cannot call into a library
that arrives with the filesystem. The same shape as point 41, where
`debug.library` called `qsort`, and the same fix shape -- either those call
sites use in-tree replacements (`<aros/crt_replacement.h>` already exists for
the string functions and covers `Strlen` but not `stpblk`), or the modules link
`-nostdc` and take `libstdc.static.a`.

Not attempted yet, and deliberately: point 41 was one call site in one module
with a fault to prove it. This is at least seven modules, the failure is a
diagnostic rather than a crash, and choosing between the two fix shapes is an
upstream design question, not a repair.
**Traced to the end, and one of my own theories was wrong.** I had assumed a
failed `OpenLibrary` at init leaves the module running with a null base. It does
not. `tools/genmodule/writestart.c:1126` emits, for every module that does not
say `noautolib`:

```c
if (set_open_libraries() && set_call_funcs(SETNAME(INIT), 1, 1) && ...)
```

so a failed open aborts that module's init, which is why the eight messages
appear. That path is correct.

The usbromstartup fault comes from the other kind of module. Its declaration is
`%build_module_simple mmake=kernel-usb-usbromstartup ... uselibs="amiga"`
(`rom/usb/poseidon/mmakefile.src:39`), and the built resource carries no
generated `InitLib` at all -- only its own `usbEarlyResident`, `usbLateResident`
and `usbromstartup_entry`. Nothing in it ever calls `set_open_libraries`, so
`StdCBase` is never anything but NULL, and there is no message either.

The chain, end to end:

  1. the resource is declared with `%build_module_simple` and `uselibs="amiga"`;
  2. `-lamiga` brings `GetDataStreamFromFormat` (`compiler/alib`);
  3. that calls `strncmp`, which in `libstdc.a` is a stub through `StdCBase`;
  4. the module has no autolib init, so the base stays NULL;
  5. the first `strncmp` jumps through `-0xb30` off zero and faults in user mode.

So there are two distinct situations, not one:

  * **modules with autolib** ask for stdc.library at init, fail, and are not
    initialised. Correct behaviour, wrong dependency -- fixed for bootloader and
    oop by taking the static C runtime.
  * **modules without a generated init** ask for nothing and fault on first use.
    `-nostdc` is the same remedy, but nothing warns beforehand, which makes this
    the more dangerous shape.

For usbromstartup the remedy has a complication worth stating: `USER_LDFLAGS` is
file-global in Make, and `rom/usb/poseidon/mmakefile.src` declares both
poseidon.library and usbromstartup.resource. `-nostdc` there would move both.
poseidon.library is an ordinary library with autolib, so it would take the static
runtime too -- defensible but broader than the fault requires.

**Tried on one module, and it works exactly as far as it should.**
`pr/bootloader-nostdc` adds `-nostdc` to `rom/bootloader/mmakefile.src`. After
it, `bootloader.resource` carries `strlen` and `stpblk` as real definitions out
of `libstdc.static.a`, with no `StdCBase` and no LIBS entry, and the boot log
loses exactly one of its five stdc complaints. Nothing else about it changes,
which is the point: the mechanism is per module.

Eleven of the 26 base-package members still carry
`__aros_set_LIBS___aros_libset_StdCBase`:

```
console.device  con-handler  hiddclass.hidd  gfx.hidd  gadtools.library
graphics.library  intuition.library  oop.library  dosboot.resource
lddemon.resource   (and one unnamed image)
```

`oop.library` is the one that matters most, because every OOP-based module fails
behind it.

The boot now gets further and stops on the same shape as point 41: a jump
through a null library base, this time in user mode.

```
[PF-DBG] CR2=fffffffffffff4d0 IP=0000000001ad15c1 CS=002b ERR=00000004
[PF-DBG] access=read mode=user present=not-present
```

`CR2` is -0xb30, another LVO offset on a null base. The byte pattern for that
jump is not unique this time -- five occurrences in the base package alone --
so naming the module needs the load address rather than a search, which the
boot check does not model for package modules yet.

**Tried on oop.library too, and the OOP chain is gone.**
`pr/oop-nostdc` does the same for `rom/oop/mmakefile.src`. oop.library uses
`strcmp`, `strcpy` and `strlen`; afterwards it has no `StdCBase`, no LIBS entry
and no undefined symbols at all.

The counts move the way the model predicts:

| | before | bootloader | + oop |
|---|---|---|---|
| `oop.library` complaints | 3 | 3 | **0** |
| `stdc.library` complaints | 5 | 4 | 8 |
| `acpica.library` complaints | 0 | 0 | 6 |

oop opening is what lets the modules behind it run, and each of those then
reaches *its own* stdc dependency -- which is why the stdc count rises rather
than falls. The eight are the ten remaining LIBS carriers minus the two that
never get that far. The six acpica complaints are new for the same reason: the
ACPI package's modules now initialise far enough to look for the port
(OPEN-POINTS 22).

So the rising number is progress, not regression. The measure of progress here
is which library is being asked for, not how often.

The stopping point is unchanged: `CR2 = -0xb30`, user mode, in a package module
(`IP=0x1acf8c1`, shifted from `0x1ad15c1` only because module sizes changed).
Naming that module needs load addresses the boot check does not model for
package modules yet, and that is now the thing in the way rather than any
particular library.

**What this settles and what it does not.** It settles that `-nostdc` is a
working fix shape for one module. It does not settle whether it is the right one
for eleven: `-nostdc` also drops `-lposixc` and `-lstdcio`, so each module has to
be checked for what else it takes from those, and a module that genuinely needs
a C library at runtime should get it a different way. That is an upstream design
question about which modules may be early, not a repair.


### 41. RESOLVED — the NULL library base was qsort in debug.library

The fault was `debug.library` calling `qsort()` while registering the
kickstart's own modules, which happens while exec is still coming up and long
before `stdc.library` is open.

The trace names it exactly:

```
0x0198f704: movabsq $0x17b0148, %r11   ; &StdCBase
0x0198f70e: movq    (%r11), %r11       ; StdCBase == NULL
0x0198f711: jmpq    *-0xa90(%r11)      ; the LVO for qsort
```

`CR2 = -0xa90` is that LVO offset applied to a null base, which is what point 41
predicted from the shape alone. Finding the rest took four steps, all
mechanical: the byte pattern of the jump (`41 ff a3 70 f5 ff ff`) occurs exactly
once in the loaded modules, in `aros-base.pkg`; the ELF image containing that
offset is `debug.library`; the nearest preceding text symbol is
`__qsort_StdCBase_wrapper`; and its caller resolves to `HandleModuleSegments`.

`rom/debug/registermodule.c` has called qsort since `42aae2fea1` (22 Jan 2026),
which replaced a hand-written sorter "instead of hard coded bubble/misc sorting
routines". The file already avoids the C library for the string functions
through `<aros/crt_replacement.h>`; sorting was not given the same treatment.

**Not our build.** `config/elf-specs.in:19` gives every module
`-lposixc -lstdcio -lstdc` unless it says `-nostdc`, and
`rom/debug/mmakefile.src` does not; `generated_targets.spec-switches.txt` shows
`kernel-debug` with no switch, so the link follows the spec. A ROM library that
runs before stdc.library simply cannot call into it.

Fixed on `pr/debug-registermodule-no-stdc`, branched off `master`: a local
iterative heapsort, which keeps what the qsort change was after -- O(n log n),
no degenerate case for already-sorted or reversed input -- and adds no stack
depth.

**What it bought.** The boot went from a page fault two lines after the kernel
banner to:

```
[Kernel:APIC-IA32] MSI Interrupts Allocatable
Exec Bootstrap Task: Could not open version 0 or higher of library "stdc.library".
...
Software Failure! Task : 0x13E0DA0 - input.device
Module input.device Segment 2 .text Offset 0x52A
Function ProcessEvents (0x17FED60) Offset 0xFA
Stack trace: 0x17C6F10 Kickstart ELF Function TaskExitStub
```

The milestone moved from "kickstart running" to "libraries being opened", and
the failures are now the system's own diagnostics rather than a fault. The
stack trace is itself evidence the fix worked: resolving a module, a segment and
a function is what debug.library does, and it is what the NULL-base jump was
preventing.

### 40. RESOLVED — the SIMD lanes compile, and each with its own flags

`arch=` is not always an architecture. `arch/i386-all/hidd/gfx` declares three
lanes for one module, and `x86_sse` and `x86_avx` are names: what attaches them is

```text
#MM- kernel-hidd-gfx-x86_64 : kernel-hidd-gfx-x86_sse kernel-hidd-gfx-x86_avx
```

CMake selected a lane by matching its tag against the target's tags, so those two
matched nothing and their sources were dropped. The dispatcher then referenced 18
implementations that were never compiled.

Both halves were needed, and the second turned out to constrain the first.

**Selection.** The rule is structural and closed over the declarations at hand:
when a `#MM` edge attaches `<mainmmake>-<a>` to `<mainmmake>-<b>` and both are
tags of lanes of that mainmmake, lane `a` is also a lane of `b`. Retagged in the
transpiler, because CMake reads the declarations before the meta edges exist.
Seven attachments in the tree, all reported in
`generated_targets.arch-lane-attachments.txt`: gfx's two, exec's `riscv64` into
`opensbi-riscv64`, the kernel's `native-ppc` into three ppc boards and
`unix-support` into `unix`.

**Flags.** Two problems, one after the other. The lane's flags were read
file-wide, and one file holds three lanes with three different `USER_CFLAGS`, so
they had to be read at the declaration's own line -- which needed the declaration
to record its line, and needed the sources to be collected from the *joined* text,
because `scope` is built from that and a raw-file line number drifts with every
continuation. Then `-msse2` and `-mavx2` were being rejected by the flag
classifier, which kept `-march=` for exactly the reason it should have kept these.

And once retagged, the flags could no longer be per tag: applying a lane's
options to the whole target would put `-mavx2` on the baseline dispatcher whose
own comment forbids it, and after attachment two lanes with different flags share
one tag. So an option is keyed by (tag, directory, file) and applied where the
file is resolved. Verified in the ninja file: `-mavx2` only on
`rgbconv_avx.c.obj`, `-msse2` only on `rgbconv_sse.c.obj`, nothing on
`rgbconv_arch.c.obj`.

Failed build steps 1066 -> 1064; the audit 40 -> 39 per mille and 376 -> 358
symbols with no provider. The boot goes on to point 41.

### 39. RESOLVED — DEFAULT_MODTYPE was read but never declared

`aros_add_library` reads `ARG_DEFAULT_MODTYPE`, so it looked declared. It was not
in the function's `oneValueArgs`, and CMake extends the previous multi-value
argument with a word it does not recognise: `DEFAULT_MODTYPE mcc` from
`aros_add_mcc` landed inside `SOURCES`.

Each of the 41 gadget, mcc and datatype declarations therefore gained two sources
named `DEFAULT_MODTYPE` and its own modtype, and lost the modtype itself. Their
scaffolding was generated as `library`, which for a Zune class is not a modtype:
`busy.conf:5: error superclass specified when not a BOOPSI class`.

Two things about how it was found are worth keeping. The error only appeared once
point 38's fix made the config findable -- before that the scaffolding was
skipped entirely, which is the same defect one step quieter. And what named it
was the missing-sources report of point 37, which listed `DEFAULT_MODTYPE` as a
source outright. This is the second time this exact CMake trap has cost a day's
worth of symptom: the first was `DRIVER_LINK_OPTIONS` extending `DEFINES`.

### 38. RESOLVED — the boot's work list was two modules, not 42

The framing here was too broad, and the correction matters more than the fix. The
audit's 42 modules include freetype2, acpica's tests, the Zune classes, Wanderer
and Prefs -- none of which any booted package contains. What the ELF loader can
refuse a boot over is the members of the packages actually passed to the
kickstart, and there were exactly two:

```
con-handler: 1  -> con_LibName
gfx.hidd:   18  -> convert_*_SSE2 / _SSE3 / _AVX
```

`con-handler` is closed: 81 of the 83 declarations with `conffile=` name a config
whose stem is not modname, both CMake lookups derived `<modname>.conf`, and
finding nothing is not an error -- so the scaffolding was skipped in silence and
`con_handler.c:50`'s `extern const char GM_UNIQUENAME(LibName)[]` stayed
undefined. Carrying `conffile=` fixed it and, in doing so, uncovered point 39.

`gfx.hidd` is point 40.

The lesson for the audit: its number is a build measure, and the boot needs the
*intersection* of that number with the loaded packages. Both are worth having,
and they are not the same list.

### 34. RESOLVED — the release collector adds first-pass-discovered inputs

`collect_extra` (`tools/collect-aros/backend-generic.c:117`) reads the first
pass's symbols and adds `OBJLIBDIR`-relative inputs to the second: the C++
pure-virtual object when `__cxa_pure_virtual` is left weak, and `libpthread.a`
when a `pthread_*` symbol is left undefined -- libgcc's emulated TLS pulls those
in and they are in no auto-linked set, so they never reach the command line.

The Rust collector now performs the same measurement after its first pass.
When `__cxa_pure_virtual` remains weak undefined it adds the sysroot's C++
pure-virtual object; when a global undefined `pthread_*` remains it adds
`libpthread.a`. Both are resupplied with the other sysroot libraries for the
scripted second pass, and the following undefined-symbol audit fails closed.
Unit tests cover both detections and their absence.

### 35. WORK — `aros/config.h` is hand-authored, and 15 of its 20 values are absent

`cmake/BootstrapSDK.cmake:170` writes the header from a string literal.
`config/config.h.in` substitutes 20 values; ours states five, and one of those
was wrong for every target (point 27i). A macro that is absent is silently zero
in `#if`, so each of the following is a branch nobody chose:

| absent macro | configure derivation | what it decides |
|---|---|---|
| `AROS_NESTING_SUPERVISOR` | `aros_nesting_supervisor=0` | whether Supervisor/Disable nest |
| `@PLATFORM_EXECSMP@` | `#define __AROSPLATFORM_SMP__` for x86_64 and aarch64 | SMP-capable platform code |
| `@ENABLE_EXECSMP@` | `#define __AROSEXEC_SMP__` only for the `smp` variant | the SMP scheduler |
| `@PLATFORM_EXECWXSEG@` | aarch64/darwin only | W^X seglist allocation |
| `@CLASSIC_VARIANT_DEFINE@` | `classic` variant only | `AROS_VARIANT_CLASSIC` |
| `USE_MMU` | `aros_enable_mmu` defaults to yes, so 1 | MMU support |
| `AROS_MUNGWALL_DEBUG`, `AROS_STACK_DEBUG` | `--enable-*` options | allocation and stack checks |
| `AROS_PALM_DEBUG_HACK` | 0 | palm-only |
| `USE_XSHM`, `USE_VIDMODE`, `ENABLE_DBUS`, `ENABLE_X11` | hosted only, 0 for pc | hosted display and dbus |

Three of the five values we do state also disagree with what configure would
produce for pc-x86_64, and each needs its own check rather than a bulk
correction: `AROS_NOMINAL_DEPTH` is 8 here and 4 there; `AROS_SERIAL_DEBUG` is 1
here and 0 there, and turning it off may be what silences the boot console this
branch debugs with; `USE_MMU` is absent here and 1 there, which changes memory
management.

The shape of the fix is not a longer literal. Substitute `config/config.h.in`
itself, so the set of macros comes from the reference and a new one cannot go
missing, and fail the configure on any placeholder without a value. The values
then come from one readable table with the configure line each is taken from,
the way `dirs.rs` handles `config/make.cfg.in`.

### 33. RESOLVED — the library-version markers are published as data

`AROS_LIBREQ` emits `__aros_libreq_<base>.<version>` as a weak absolute whose
*value* is the version (`symbolsets.h:158`), and the code never reads that
symbol. genmodule's generated `InitLib` reads the *unversioned* name as memory:

```
223a6: movzwl 0x26(%rdx), %eax          ; SysBase->lib_Version
223aa: cmpl   %eax, (%rip)              ; 0x223ac R_X86_64_PC32
                                        ;   __aros_libreq_SysBase - 4
```

Nothing defined it, so the operand address was 0 and the read faulted with
CR2=0. 1210 of 1238 built artefacts reference a marker.

`collect_libs` (`backend-generic.c:64`) and `emit_libs` (`gensets.c:167`) are
what connect the two, in the same second pass as the sets, and `aros-collect`
now does it. The reference's `nm` filter is reproduced exactly, including the
part that is easy to miss: a *local* absolute is not accepted. A kickstart
member's markers are local by the time the kickstart is linked and each member
already carries its own definition from its own pass, so publishing them again
at kickstart level would bind one member's requirement to another's.

The decided divergence: where several requirements for one base meet -- exec's
member has SysBase at 0, 33, 36, 39, 45 and 50 -- the reference's `PROVIDE`
binds the name to whichever node its reversed `nm` order put first. This takes
the maximum, because the check has to satisfy every requirement. 478 links have
two or more *stated* requirements and each is reported; the ordinary `[0, N]`
pair is not, because `AROS_LIBREQ(base, 0)` is what genmodule emits for a caller
naming no minimum and reporting it buried the real cases 5:1.

The symbol audit's weak references fall from 3689 to 121: the markers were most
of them.

### 32. RESOLVED — the symbol sets are collected

This was the boot blocker and it was not confined to the boot: 527 source files
use an `ADD2*` macro, and 313 of 381 sampled built artefacts carried
`.aros.set.*` sections that nothing read.

`ADD2INITLIB(cpu_Init, 10)` puts a pointer to `cpu_Init` into a section named
`.aros.set.INITLIB.10`. `DEFINESET` declares the set itself as a *weak*
two-pointer array, `__INITLIB_LIST__[] = {0, 0}`
(`compiler/include/aros/symbolsets.h:39`), and nothing in the compiler or the
linker connects the two. The connection is the linker's: for an AROS target the
linker the spec names is `collect-aros` (`scripts/aros-ld.in:5`), and it links
twice -- `ld -r` over the inputs, then `ld -r -T <generated script>` over that
result, the script laying each set out as `[count][entries by priority][0]`
between `__X_LIST__` and `__X_END__` (`tools/collect-aros/gensets.c:69`).

Our rule was `ld.lld -r` (`cmake/AROS.cmake:244`), which is exactly the mode
collect-aros stops early in (`collect-aros.c:184`). `-Ur`, which the kickstart
member and the kickstart link pass and which we had read as a GNU-ld spelling of
`-r`, is the mode that does both passes (`:188`) -- half a mechanism, not a
dialect. Measured before the fix: the three `__INITLIB_LIST__` symbols in the
kickstart were 16 bytes of zero each with no relocation touching them, and
`graphics.library` had five set sections and not one relocation landing on a set
array.

`aros-collect` is that second pass, and every AROS link now goes through it. The
fork recorded here is decided: rather than making collect-aros releasable
(point 4), the layout is ported, because the mechanism is one script and the
tool it lives in carries build-local absolute paths we would have to unpick
first. The `ld.lld -r -T` question that made the choice risky was settled by
experiment before any code: lld accepts data commands in a relocatable link,
resolves the forward reference to `__X_END__`, and lets a script assignment
override the weak array.

What it changed on pc-x86_64: the kickstart's `.aros.sets` holds kernel's
INITLIB with `Platform_Init` and `cpu_Init`, its `KERNEL__ACPISUPPORT` with
three entries, exec's PREINITLIB and INITLIB, and task's INITLIB. `cpu_Init`
runs, so `KrnCreateContext` no longer returns NULL and 27g's dead-end alert is
gone; the trap handlers install, so a fault is reported by `core_IRQHandle`
instead of triple-faulting, which confirms the missing IDT gate was the same
cause. The boot now reaches `ictl_Initialize`, which is point 27i.

The release-facing Rust collector now also covers the extra-input job recorded
in point 34. Point 33's library-requirement publication was already part of
this second pass.

### 22. WORK — ACPICA is a fetched Port that kernel-kernel needs

    GENINCDIR/libraries/acpica.h:47:10:
        fatal error: 'acpica/actypes.h' file not found

Three `arch/all-pc/kernel` sources need it, so `kernel-kernel` does not build
without it. Same class of problem as Boost in point 1, and the same three
routes apply. This is now the only thing between the three boot fixes and a
building kernel.

### 23. DONE — compiler-posixc include order

The 179-object failure cluster was one include-precedence defect, not missing
headers. `compiler-posixc` links the `stdc_rel` client archive. Its
`AROS_CLIENT_NAMESPACE_INCLUDES` property was propagated by
`_aros_bind_link_libraries()` with `BEFORE`, after the target had already
prepended its own POSIX namespace. CMake therefore moved `aros/stdc` ahead of
`aros/posixc`; bare `<limits.h>`, `<errno.h>` and `<sys/types.h>` selected the
C99 subset rather than the POSIX superset.

Commit `841884dd1ad` fixed the provider at its source: propagated client
namespaces append to the target's established include order. The global LLVM
contract remains the upstream compiler-spec order `aros/posixc`, `aros/stdc`,
then the common SDK root. The deferred-link fixture now also asserts that a
provider namespace cannot outrank a consumer's own include directory.

Fresh measurement on 27 August 2026:

    compiler-posixc target            2,837/2,837 steps, exit 0
    complete pc-x86_64 build         14,052/14,295 steps attempted
    POSIXC missing-name failures                       0

The unqualified build now advances to unrelated Port/SDK boundaries. Its
largest current diagnostics are `lzma/version.h` (330), `dbus/dbus.h` (223),
C++ standard headers (255 across the observed header names) and
`src/webp/config.h` (72). These belong to points 24 and 25, not POSIXC.

### 23b. DONE — original posixc symptom groups, for the record

    __posixc_intbase.h:55:21   undeclared identifier 'PASS_MAX'     65
    __stdio.h:38:37            unknown type name 'off_t'            24
    aros/posixc/dirent.h:52:20 undeclared identifier 'PATH_MAX'     11

Plus single instances of `EBADF`, `locale_t` and an implicit `wcwidth`. The
shape correctly indicated one shared include-order problem. All are absent
from the fresh targeted and unqualified builds.

### 24. WORK — the C++ standard headers are not in the SDK

`cstdint` 64, `cinttypes` 47, `cstddef` 33, `deque` 22, `memory` 14,
`algorithm` 14, `string` 11. The libc++ headers the release toolchain builds
are not reaching the consumers that need them. Mostly affects datatypes and
ports rather than the boot path.

### 25. WORK — third-party media and compression Ports dominate the failure count

`lzma/version.h` 129, `src/webp/config.h` 72, plus heic/heif 118, jpegxl 82,
de265 32, nouveau 24. None of these is on the boot path; together they are
roughly half of the 887 failed steps. Worth separating from the boot work when
reading any build number.

### 26. RESOLVED — the instrument exists, and it names one dominant cause

`ninja symbol-audit`, added in cde7251f9c. First measurement on pc-x86_64:
1011 artefacts, 998 of them with undefined symbols, 25006 references, 2710
distinct symbols, 77 weak. Pinned as a ratchet in
scripts/symbols/baseline-pc-x86_64.json.

What it says is that Tor 2 is essentially one problem. The commonest undefined
symbols are CloseLibrary 431, OpenLibrary 422, __posixc_printf 345, FreeVec 281,
AllocVec 275, FindTask 260 -- the AROS API and the C runtime, referenced by
almost every module and provided by the per-module stubs that genmodule writes
into a link library. Those stubs are not generated, so nothing defines the
symbols and every module carries them as holes.

2166 of the 2710 distinct symbols have no provider among the built artefacts at
all; only 544 are defined somewhere and merely not linked. So this is not
several hundred separate omissions. It is the link-library generator, and it is
the same 94 modules and 3960 generated files recorded earlier as a weeks-sized
item. The audit turns that from an assumption into a measured claim.

Calibration worth keeping: kernel-exec.library itself lists AllocMem as
undefined, because exec does not export its API as global ELF symbols. A reader
who takes the by-symbol report as "exec is missing" is misreading it.

### 26b. RESOLVED — load sets are modelled, and they explain almost nothing

`aros_record_load_set` records each package and the kickstart at configure
time, and the audit resolves against the union of a set (`6244923349`).
Measured effect: 10 references out of 9221. So the members do not in practice
resolve against each other, and the earlier expectation that this would "lower
the count somewhat" was wrong.

The useful part of that work was the KIND column, which forced the two loaders
to be read, and that refuted the blanket library-base excuse of `260e7a400d`:

  * `rom/dos/internalloadseg_elf.c:509` — every undefined symbol is fatal,
    `ERROR_BAD_HUNK`, no exception.
  * `bootstrap/elfloader.c:157` — a kickstart member may leave `SysBase`
    undefined and the loader substitutes `DefSysBase`; anything else fails.

So `DOSBase`, `IntuitionBase` and `UtilityBase` left undefined are defects, and
removing the excuse raised the honest count from 7330 to 9221 references.

### 26c. RESOLVED — the dominant cause is the compiler spec, not the generator

Point 26 named "the link-library generator" as the single cause. That was half
right. The generator works; what was missing is that nothing applied the
default link set the target compiler's spec appends to every link, because our
rule is `ld.lld -r` invoked directly (`cmake/AROS.cmake:244`).

  * `config/elf-specs.in:19` — `*lib:` is `%(autolib)`, then the C runtime,
    then `%{!nosysbase:-lexec}`.
  * `compiler/autoinit/auto` — `*autolib:` names 28 archives, `-ldos` and
    `-lutility` among them.
  * `compiler/include/aros/symbolsets.h:118` — `AROS_LIBSET` in
    `<mod>_autoinit.c` is what *defines* a library base; that object lives in
    `lib<mod>.a`.
  * `rom/exec/exec_autoinit.c:22` — `struct ExecBase *SysBase;`, archived into
    `libexec.a` via `linklibfiles=exec_autoinit`.
  * `configure.in:3468` — modules link with `-nostartfiles`, which suppresses
    `*startfile:` only, so a module gets the same set a program does.

Two of our defects followed from never modelling this. The client archive was
keyed on `linklibname=` instead of on `<mod>_LINKLIBFILES` being non-empty, so
88 of 101 archives were never built (`7c5fec1f97`). And because nothing in the
mmakefile tree links `-lamiga`, `linklibs-amiga` was never promoted to its
canonical name and produced `liblinklibs-amiga.a` instead of `libamiga.a`.

`aros-transpiler` now reads the spec (`default_link_set.rs`) and resolves all
33 items to concrete archives; `cmake/DefaultLinkSet.cmake` applies them.

Open within this: `rom/timer` states `options autoinit` without being
`modtype=library`, so upstream builds `libtimer.a` for it and we do not. It is
reported in `generated_targets.skipped-client-archives.txt`.

### 26d. RESOLVED — fetched source inventories are materialised at configure time

`freetype2.library` and `acpica.library` obtain their implementation lists from
Make expressions over `$(wildcard $(PORTSDIR)/.../*.c)`. The evaluator must see
the unpacked trees before it can apply the following substitution,
`filter-out`, and `addprefix` operations.

The first transpiler pass now writes an exact source-inventory manifest naming
only the fetch declarations that own unresolved Ports globs. CMake materialises
those archives at configure time, reruns the transpiler against `AROS_PORTS_DIR`,
and refuses to include the generated graph if the second pass still reports an
unresolved inventory. This is intentionally bounded: it is not a general
configure-time build of Ports.

A cold production configure proved the two current inventories (ACPICA and
FreeType), and `SourceInventoryReconfigureTest.cmake` covers extraction,
re-evaluation, and fail-closed behaviour. The second generated graph contains
the concrete source lists rather than an opaque deferred marker.

### 26f. RESOLVED — every module with a config gets its scaffolding

Done in `de38eaba51`. Generated start files went from 88 to 359.
`_aros_generate_module_support` accepts every genmodule module type now, with a
SOURCES_ONLY mode that leaves the SDK headers to the Rust generator's scan, and
`aros_module_scaffolding` wires it into the resource, device, hidd, custom and
gadget/mcc/datatype paths.

Two things learned, both worth keeping:

`%build_module_simple` has no genmodule step at all (config/make.tmpl:1974), and
the transpiler said so at parser.rs:7978 before I wired it anyway.
workbench/libs/gl is an ABI shell whose implementation lives in the Mesa port,
so its generated function table appeared as 463 undefined references. The
measurement caught it; reading the macro first would have been cheaper.

Our own genmodule named generated symbols after the module name, where the
reference names them after the basename (writeinclibdefs.c:82, config.c:1333).
That was invisible while our tool was the only generator on both sides.

### 26f-old. WORK — the original survey, for the record

Only `aros_add_library` and `aros_add_module_abi` call
`_aros_generate_module_support` (`cmake/AROS.cmake:3415`, `:3335`), so the
generated `<mod>_start.c`, `<mod>_end.c` and function table exist for the 100
library targets and for nobody else:

  | builder                  | targets | gets the generated sources |
  |--------------------------|--------:|----------------------------|
  | `aros_add_library`       |     100 | yes                        |
  | `aros_add_hidd`          |      80 | no                         |
  | `aros_add_device`        |      58 | no                         |
  | `aros_add_resource`      |      32 | no                         |
  | `aros_add_module_simple` |      28 | no                         |
  | `aros_add_gadget`        |      24 | no                         |
  | `aros_add_datatype`      |      21 | no                         |
  | `aros_add_mcc`           |      15 | no                         |

Measured, not inferred. `muimaster.library` defines `MUIMaster_Copyright`,
`MUIMaster_End`, `MUIMaster_FuncTable`, `MUIMaster_InitLib` and
`MUIMaster_InitTable`; `kernel-task.resource` defines no counterpart of any of
them. Its LVO wrappers (`Task_10_AddTaskHook` and the like) come from its own
sources, so their presence says nothing about the scaffolding.

This is not a symbol-count problem. `<mod>_start.c` carries the romtag and the
init entry (`tools/genmodule/writestart.c`), and `<mod>_end.c` the `End` marker
the romtag scanner leaps to (`tools/genmodule/writeend.c:44`). A module without
them has no entry point, whatever its symbol table looks like. It is how
`kernel_End` and `kernel_FuncTable` come to be undefined in
`kernel.resource`: `rom/kernel/kernel_init.c` references its own romtag end
marker, and nothing generates it.

Scope note before anyone starts: the machinery already exists and is used by
the library path, so this is plumbing seven builders into it rather than new
generation. What needs deciding is the module type each builder passes and
whether the ABI/includes half applies too.

### 26e. PARTLY RESOLVED — kernel.resource is down from 33 undefined to 4

Two of the three groups are closed by `a33237bffa`.

The boot console and ACPICA came from `arch/all-pc/kernel/make.opts:1`,
`USER_LDFLAGS := -L$(GENDIR)/lib -lbootconsole -lacpica`, which the make.opts
reader dropped: it took defines, compile options and include paths and ignored
link options. `print_crash_info` was a different fault in the same file:
`arch/x86_64-pc/kernel/mmakefile.src` sets `KERNEL_USE_EARLYTRAP=` empty on its
own line 5, so the reference build never compiles `kernel_early.c`, and the
arch collector applied the `ifneq` branch anyway.

What remains, both real work:

  * `kernel_End`, `kernel_FuncTable` — point 26f. Not a kickstart-link
    artefact, as previously assumed: they are genmodule's romtag scaffolding,
    which no resource gets.
  * `_binary_smpbootstrap_start`, `_binary_smpbootstrap_size` — the objcopy'd
    blob from `%rule_link_binary` at
    `arch/x86_64-pc/kernel/mmakefile.src:87`, which is not modelled.

Also settled, for the record: the kickstart link is
`$(TARGET_CC) ... $(KOBJS) $(LDFLAGS) $(LDLIBS)` (config/make.tmpl:3904), so
the compiler spec applies there too, with `-lexec` suppressed by `-nosysbase`.
Its `uselibs=` is empty for pc-x86_64, so it contributes no libraries of its
own.

### 27a. RESOLVED — the kickstart links, with no undefined symbols

`94cfb7c9f6`. 367 KB, ELF64 relocatable, zero undefined symbols, zero
SHN_COMMON, all three members' romtag scaffolding present. That is the
threshold `bootstrap/elfloader.c:157` sets.

The reading that got there, in order: `$(USER_LDFLAGS)` applies to the member
object too (36 undefined -> 16), the kickstart link itself uses `$(TARGET_CC)`
so the compiler spec's default set applies there with `-nosysbase` (16 -> 2),
and the wrapped SMP binary had to be carried past `$<TARGET_OBJECTS:>` (2 -> 0).

### 27a-old. WORK — a kickstart member is a different artefact from a module

The blocker for a boot image, and the reason the kickstart link fails with
`duplicate symbol: LibNextTagItem` and `set_call_libfuncs`.

`config/make.tmpl:2166` builds a kickstart member as its own object, not as the
loadable module:

```
$(KOBJ) : $(OBJS) $(ENDOBJS)
    $(AROS_LD) -Ur $(KOBJ_LDFLAGS) $(KERNEL_KOBJ_LDSCRIPT) -o $@ $^ \
        $(USER_LDFLAGS) -L$(AROS_LIB) $(addprefix -l,$(LINKLIBS))
    $(OBJCOPY) $@ $(FILTBASES) `... -L <set list symbols>`
```

Four differences from the module link, each load-bearing:

  * `$(AROS_LD)` directly, not the compiler driver, so the spec's default link
    set does **not** apply to a kickstart member.
  * `KLIB := hiddstubs amiga arossupport autoinit libinit` are filtered out of
    `uselibs` (make.tmpl:2161).
  * a kernel linker script, `KERNEL_KOBJ_LDSCRIPT`.
  * `objcopy -L` makes the library bases local -- `DOSBase IntuitionBase
    LayersBase GfxBase OOPBase UtilityBase ExpansionBase KeymapBase KernelBase`
    (make.tmpl:2156) -- along with every `__*_LIST__`, `__*_END__` and
    `__aros_lib*`. That localisation is exactly what lets several members be
    linked into one image.

We build one artefact per module and hand it to both purposes, so the members
carry the default link set and their bases stay global. A second artefact per
member is the work; the localisation step is the part that cannot be skipped.

### 27j. WORK — the kickstart is complete; the boot needs the packages

The kickstart now runs end to end:

```
AROS64 - The AROS Research OS
64-bit build. Compiled Aug 23 2026
[Kernel:APIC-IA32] MSI Interrupts Allocatable
[Kernel:APIC-IA32]     start = 16
[Kernel:APIC-IA32]     total = 198

+------------------------------------------+
|           Critical boot failure          |
|            System Boot Failed!           |
+------------------------------------------+
```

`arch/x86_64-pc/kernel/kernel_startup.c:638`, reached because
`InitCode(RTF_COLDSTART, 0)` returned, and the comment above it says it must
not. kernel.resource, exec.library and task.resource all initialise, the APIC is
up, privileges drop to user mode, and the coldstart chain runs out of residents
without anyone taking over -- which is what a kickstart-only boot does when
there is no dos.library to hand to.

So this is not a new defect but the end of what the kickstart alone can do. Going
further needs the packages as multiboot modules, and that is blocked on point
27h: `serialmouse.hidd` in `aros-legacy.pkg` has a dangling
`HIDD_Serial_NewUnit`, and the ELF loader refuses the whole boot over it. 27h is
therefore the next step in this chain, not an aside.

### 27i. RESOLVED — the APIC panic was a wrong AROS_FLAVOUR

With the symbol sets collected the boot gets through `Exec_init`, through
`InitCode(RTF_COLDSTART)`, and into the interrupt-controller setup:

```
AROS64 - The AROS Research OS
64-bit build. Compiled Aug 23 2026

+------------------------------------------+
|           Critical boot failure          |
|      Failed to allocate APIC descriptor. |
+------------------------------------------+
```

`arch/all-pc/kernel/ictl.c:112`. The `in_asm` trace resolved it without
guesswork: `core_APIC_Probe` allocated its descriptor, called `SuperState`
through LVO 25, and got back a function that was eight bytes long --
`push rbp; mov rsp,rbp; xor eax,eax; pop rbp; ret`. So it freed the descriptor
and returned NULL (`arch/all-pc/kernel/apic.c:41`).

`rom/exec/superstate.c` has its whole body inside
`#if (AROS_FLAVOUR & AROS_FLAVOUR_STANDALONE)`, and
`cmake/BootstrapSDK.cmake` wrote `AROS_FLAVOUR_NATIVE` into `aros/config.h` for
every target. 1 & 2 = 0, so the body was gone. configure derives the flavour per
platform case -- `pc)` at `configure:10727` and `r*pi)` at `:11213` both set
standalone -- and NATIVE is what it picks for classic Amiga-like ports. The
value was wrong for all three presets. The same `#if` also gates the XSAVE/AVX
context path (`arch/x86_64-all/kernel/cpu_init.c:26`), which is why `cpu_Init`
was 21 bytes rather than 182.

With the flavour right the boot gets an APIC:

```
[Kernel:APIC-IA32] MSI Interrupts Allocatable
[Kernel:APIC-IA32]     start = 16
[Kernel:APIC-IA32]     total = 198
```

and the next stop is point 33, with the evidence recorded there. The rest of
`aros/config.h` is point 35.

Two things worth keeping from the way this was found. The trap handlers, the
boot console and `krnPanic` all work, so a panic now reaches the screen and says
what it is. And the full build never relinks the kickstart -- neither the
kickstart target nor its `-file` companion is in `all`, so the recompiled
members sat there while the old image kept booting. The 1083-failed-step figure
has never covered the kickstart; it has to be asked for by name.

### 27h. RESOLVED — the HIDD stub archive exists, and the packages load

Booting with the packages used to stop before the kernel ran:

```
[ELF Loader] Undefined symbol 'HIDD_Serial_NewUnit'
serialmouse.hidd: Relocation error in section 2!
Failed to load the kickstart
*** SYSTEM PANIC!!! ***
```

The symbol is a HIDD stub. `%make_hidd_stubs` (`config/make.tmpl:3551`) compiles
each declaration's `$(STUBS)` into `$(GENDIR)/lib/hidd/`, and
`compiler/libhiddstubs/mmakefile.src` archives that directory into
`libhiddstubs.a`. Nothing modelled the macro, so the 61 declarations that state
`uselibs=hiddstubs` had no archive -- which
`generated_targets.unresolved-uselibs.txt` had been saying all along, unread.

The wildcard needed no modelling: its inputs are exactly the `$(STUBS)` of the
six `%make_hidd_stubs` declarations, known once the tree is parsed. Three
details decide whether the result is the same artefact, and each is in the code:
the source comes from `$(STUBS)` and not from `hidd=` (`hidd=mstorage` has
`STUBS := storage_stubs`); the macro applies no `$(USER_INCLUDES)`, because it
calls `%compile_q` directly instead of the `%(mmake)_CFLAGS` lane that would add
it; and the archive is public, which `compiler/libhiddstubs` states as
`$(AROS_LIB)/libhiddstubs.a`.

`unresolved-uselibs` falls from 91 lines to 30 with no hiddstubs left,
`libhiddstubs.a` exports 81 HIDD entry points, and
`kernel-hidd-serialmouse.hidd` has no undefined symbol at all. The audit reads
42 modules with undefined symbols where it read 50, 41 per mille where it read
48.

All five buildable packages now load, and the boot task says what it needs:

```
Exec Bootstrap Task: Could not open version 36 or higher of library "utility.library".
Exec Bootstrap Task: Could not open version 0 or higher of library "oop.library".
Exec Bootstrap Task: Could not open version 0 or higher of library "stdc.library".
Exec Bootstrap Task: Could not open version 36 or higher of library "intuition.library".
```

Those version numbers are point 33's markers being read. The libraries are in
`aros-base.pkg`, which is point 36.

### 27g. PARTLY RESOLVED — the MemList has a fourth node that is not a MemHeader

Two of the three original findings are settled by point 32 (`cpu_Init` runs, the
trap handlers install). The fault itself is now read out of guest memory rather
than guessed at, because `aros test` backs the guest's RAM with a file in the
evidence directory.

`FindMem` walks `SysBase->MemList` (`rom/exec/memory.c:33`), and with
`SysBase = 0x1002870` taken from the fault's own R15 the walk reads:

```
node 0x1000050  succ 0x100050    pred 0x1002ae0  type 10   <- &MemList, correct
node 0x100050   succ 0x1050      pred 0x1000050  type 10   <- correct
node 0x1050     succ 0x10037b0   pred 0x100050   type 10   <- correct backlink
node 0x10037b0  succ 0x48003004708a8b48  pred 0x8548ffffffffc0c7  type 224
```

So the three real memory headers are intact and doubly linked, and the third one
should end the walk: `&MemList.lh_Tail` is `0x1002ae8` and the value there is 0,
which is exactly what `while (mh->mh_Node.ln_Succ != NULL)` needs. Instead its
`ln_Succ` is `0x10037b0`, which is `SysBase + 0xf40` and holds four pointers into
the loaded kickstart:

```
+0  0x17be300   +8  0x17c39d0   +16 0x17be5e0   +24 0x17c39a0
```

Following that takes the walk to `0x17be300`, inside the kickstart's `.text`,
where the eight bytes at the successor offset are the instruction
`48 8b 8a 70 04 30 00 48`. As a pointer that is non-canonical, which is why the
fault is #GP and not #PF, and why point 27g recorded "x86 code rather than a
node" without being able to say more.

**Who links it: measured with a watchpoint.** QEMU's gdbstub plus lldb gives
data watchpoints, which is what this needed. Watching the successor field of the
third MemHeader (`0x1050`) records six writes:

```
mmap_InitMemory+0x96, +0x31a, +0x420      the memory map builds headers
krnCreateMemHeader+0x64
krnConvertMemHeaderToTLSF+0xf7
Exec_45_Enqueue+0x2f    rdi=0x1002ae0 (&MemList)  rsi=0x1050
```

The last write is `Enqueue` linking `0x1050` in, and the value it stores as that
node's successor is `0x10037b0` -- so the bad node was *already* in the list.
Enqueue is not at fault.

Watching `&MemList.lh_Head` (`0x1002ae0`) shows the head is sound: `memset+0xfd`
clears it, `PrepareExecBase+0x181` writes `0x1002ae8` (NEWLIST, an empty list
pointing at its own tail), `PrepareExecBase+0x5e3` links the first header. No
later writes.

Watching the bad node itself (`0x10037b0`) is what names it:

```
tlsf_malloc+0x307          rdi=0x1000050  rsi=0x10
tlsf_malloc+0x35a          rdi=0x1000050  rsi=0x10
Exec_45_Enqueue+0x2f       rdi=0x1002ae0  rsi=0x10037b0
Exec_15_MakeFunctions+0xb8 rdi=0x1002870  rsi=0
Exec_15_MakeFunctions+0xc7 rdi=0x1002870  rsi=0
```

So the block is allocated out of the first MemHeader's pool, linked into
`SysBase->MemList` by `Enqueue` as though it were a MemHeader, and then written
over by `MakeFunctions` -- which explains the contents exactly: the four values
at that address are pointers into the kickstart's `.text`, because they are LVO
jump-table entries.

`rsi` at the malloc hits reads `0x10`, and if that is still the size argument the
block is 16 bytes, where a `struct MemHeader` is far larger. That would make the
node's own fields collateral damage rather than the primary defect. Registers at
a watchpoint hit are not guaranteed to still hold the entry arguments, so this
one is an indication, not a measurement; the Enqueue arguments are trustworthy
because that hit is 0x2f into the function.

**The caller, and what it overturns.** Reading the stack at that Enqueue hit
names it:

```
Exec_45_Enqueue+0x2f      rdi=0x1002ae0 (&MemList)  rsi=0x10037b0
  <- krnCreateROMHeader+0x71
     <- kernel_cstart+0x6b3
```

So `0x10037b0` is not a foreign node at all. It is the ROM MemHeader, created
and linked deliberately by `krnCreateROMHeader` to describe the kickstart's own
memory. That also explains the contents this point earlier read as suspicious:
a header describing the ROM *should* hold pointers into the kickstart, because
`mh_Lower` and `mh_Upper` bracket it.

The defect is therefore not the linking but what happens afterwards. Two writes
land on the same address once it is linked:

```
Exec_15_MakeFunctions+0xb8  rdi=0x1002870 (SysBase)
Exec_15_MakeFunctions+0xc7
```

`MakeFunctions` builds an LVO jump table. It writes over the ROM MemHeader's
node fields, which is what the memory dump showed: `ln_Type` reading 224 instead
of 10, and four `.text` addresses where the list pointers belong -- jump-table
entries, not header fields. The third MemHeader's successor pointing at
`0x10037b0` was correct all along; the node it points at is destroyed after the
fact, so `FindMem` walks into wreckage.

Two corrections to what this point said before: the successor was never wrong,
and `Enqueue` was never the writer of a bad value.

**The extent, measured -- and the cause.** `MakeFunctions` documents `target` as
"the highest byte +1 of the jumptable", and `__AROS_GETJUMPVEC(lib,n)` is
`&((struct JumpVec *)lib)[-n]`, so the table grows *downwards* from the base. At
the write, `r12` held -71 and `r14` held `0x10039e8`, and `0x10039e8 - 71*8`
is exactly `0x10037b0`. So the base being built is `0x10039e8` and the ROM
MemHeader sits under it, at vector 71. `rdi` reading `SysBase` was the library
function's own base argument, not `target`.

The stack names the base: `Kernel_Init+0x43`, so `0x10039e8` is kernel.resource
-- consistent with the node there reading `ln_Type` 8 (NT_RESOURCE) and `ln_Pri`
127. `AllocKernelBase` is sound; it allocates
`FUNCTIONS_COUNT * LIB_VECTSIZE + sizeof(struct KernelBase)` and then steps the
pointer past the table, so vector 71 would be inside the allocation if the count
were right.

It is not:

```
kernel.conf function list   59 functions, 7 `.skip` lines reserving 12 LVOs
highest LVO                 71
Kernel_FuncTable            71 entries before the -1 terminator (symbol size 576)
FUNCTIONS_COUNT             59
```

`MakeFunctions` walks the table to its terminator, so it writes 71 slots into
space allocated for 59: an overrun of 12 slots, 0x60 bytes, below `0x1003810`,
which puts vector 71 at `0x10037b0`. Every number matches the observation.

The rule the reference uses is the highest LVO, taken from the last list entry
(`writeinclibdefs.c:20`), because a `.skip N` reserves vectors without declaring
a function. Our genmodule used `functions.len()`. Fixed, with tests.

**Two things had to go wrong together.** The build's authoritative
`kernel_libdefs.h` comes from `hosttools/genmodule`, the C tool, into
`genmodule/rom/kernel/kernel_kernel/gen/`, and it says 71. The file our Rust
genmodule left in `gen/rom/kernel/` on 23 August says 59. Since
`LC_LIBDEFS_FILE` is `"kernel_libdefs.h"` -- a quoted include -- `-iquote` wins
over `-I`, and the first `-iquote` on the kernel's compile line is
`gen/rom/kernel`. The stale file shadowed the correct one. It is not a ninja
target, so nothing ever refreshed it.

Moving it aside and rebuilding, the MemList walks clean:

```
0x1000050  type=10  pri=0
0x100050   type=10  pri=-5
0x1050     type=10  pri=-6
0x10037b0  type=10  pri=-128     <- the ROM header, intact
terminates at 0x1002ae8 == &lh_Tail
```

Four headers, all NT_MEMORY, ROM last at priority -128, and the list ends where
it should. `FindMem` runs through. The boot now reaches `Exec_12_InitCode` ->
`Exec_17_InitResident` and faults in usbromstartup.resource, which is point 48's
`%build_module_simple` case and was the visible blocker before this too. So the
MemList damage was latent rather than the current stopping point; it would have
bitten as soon as anything walked past the third header.

The shadowing is a defect in its own right and is now point 50.

The 147 repeats and the eventual double fault are downstream: the panic path
calls `TypeOfMem`, which calls `FindMem` again.

### 27g-old. WORK — exec raises a dead-end alert, and the alert path faults

With the section ordering in place the boot reaches user mode and raises an
alert. QEMU reports no exception until the alert is being *formatted*:

```
check_exception old: 0xffffffff new 0xd
  v=0d e=0000 cpl=3 IP=002b:00000000013adfa3
  RAX=48003004708a8b48
check_exception old: 0xd new 0xb
  v=08 (double fault)
```

Read from the `in_asm` trace with the kickstart's `.text` at `0x1391000`, the
call chain is

    Exec_12_InitCode -> Exec_17_InitResident -> Exec_init
      Exec_33_AllocMem            (twice, both succeed)
      Kernel_18_KrnCreateContext  -> Exec_33_AllocMem
      Exec_18_Alert -> Exec_ExtAlert -> Exec_SystemAlert
        FormatAlert -> FormatLocation -> FormatAlertExtra
          Exec_89_TypeOfMem -> FindMem -> tlsf_in_bounds -> #GP

so two separate failures, and the first is the one that matters.

**The alert.** `KrnCreateContext()` returned NULL, so `Exec_init` took
`goto execfatal` and raised `Alert(AT_DeadEnd | AG_NoMemory | AN_ExecLib)`
(`rom/exec/exec_init.c:159` and `:296`). The context allocation is
`AllocMem(KernelBase->kb_ContextSize, MEMF_CLEAR)`
(`rom/kernel/kernel_objects.h:11`), and `kb_ContextSize` is set by `cpu_Init`
(`arch/x86_64-all/kernel/cpu_init.c:17`), which is an `ADD2INITLIB` entry. It
never ran, because point 32 means no INITLIB entry ever runs. `AllocMem(0)`
returns NULL. So 27g is a symptom of 32, not a defect of its own.

**The fault, which is a defect of its own.** `FormatAlertExtra` prints a stack
trace and calls `TypeOfMem` on each frame, which walks `SysBase->MemList`. The
faulting instruction is `.text+0x1cfa3` in `FindMem` (`rom/exec/memory.c:60`,
`mh = mh->mh_Node.ln_Succ`), and the pointer it dereferences holds
`48 8b 8a 70 04 30 00 48`, x86 code rather than a node. A TLSF header was
examined first, so `tlsf_in_bounds` ran and returned; the successor after it is
what is wrong. Whether the list is genuinely corrupt or `FindMem` is reached
with a SysBase that is not one needs guest memory, which the runner cannot read
yet — see point 31.

**And a third.** `check_exception ... new 0xb` is #NP, so the IDT gate for
vector 13 has its present bit clear. `IDT=0x1400100 limit=0xfff` is the full
256 entries, so the table is sized and installed but entry 13 is not filled in.
A #GP in a user task must become an alert, never a triple fault. Very likely
another consequence of 32, since the trap handlers are installed from an
INITLIB entry, but worth confirming once the sets work.

### 27f. RESOLVED — every kickstart module's sections are ordered, not only m68k's

The scan found kernel.resource and nothing else. Upstream `ac31689b11` moved
the Resident tags into `.text.romtag` and the End markers into
`.text.moduleend`, and wired the ordering script that makes `rt_EndSkip` mean
"module end" for amiga-m68k alone. Everywhere else a link merges sections by
name, so all three tags landed in one block and all three markers in a block
above it:

```
.text.romtag     Kernel_resident +0x00  Exec_resident +0x48  Task_ROMTag +0x90
.text.moduleend  Kernel_End     +0x00  Exec_End      +0x01  Task_End    +0x02
```

The loader packs read-only sections in section-index order, so
`.text.moduleend` sits above every tag. The scanner reads kernel.resource,
leaps to `Kernel_End`, and is past the end of the image.

`config/kobj-romtag.ld` is the same mechanism for every target, and the
transpiler now reads `KERNEL_KOBJ_LDSCRIPT` out of `config/make.cfg.in` instead
of leaving it unmodelled. Each module became one contiguous block in `.text`
with its tag first and its marker last, every leap lands in front of the next
module's tag, and the boot goes on to point 27g.

The second fault recorded here, `v=0e IP=0008:000000000139e621
CR2=fffffffffffffef8`, was the panic path and went away with the panic.

### 27e. RESOLVED — the kickstart link is a nostdc link

`kernel_cstart` called `strstr(cmdline, "vesahack")`
(`arch/x86_64-pc/kernel/kernel_startup.c:358`) and faulted:

```
movabsq $0x138efa0, %r11 ; movq (%r11), %r11 ; jmpq *-0xb70(%r11)
v=0e CR2=fffffffffffff490
```

That is `__strstr_StdCBase_wrapper`: load StdCBase, jump through its LVO table.
StdCBase is necessarily NULL in `kernel_cstart`, which is the first code to run.

`libstdc.a` is the client stub archive and its `strstr` is that wrapper;
`libstdc.static.a` holds the real one. The spec offers exactly this choice --
`%{!nostdc:... -lstdc} %{nostdc:-lstdc.static}` (`config/elf-specs.in:19`) --
and `%link_kickstart` passes only `-static -nosysbase`
(`config/make.tmpl:3899`).

Passing `nostdc` too is a reading of the reference, not a transcription of it,
and it is stated as such at the call site. The justification is the one that
already justifies `-nosysbase`: a kickstart runs before any library exists, so
it cannot call one. `rom/exec` makes the same choice one level down, with
`uselibs="stdc.static"` for its own object.

Found while testing it: the switch lists in the default-link-set record are
comma-separated inside a pipe-separated record, and neither consumer split
them. A single-switch item was unaffected, so only `-lposixc`, the one item
with two switches, was wrong -- and it was wrong everywhere, staying in links
that asked for `nostdc` or `noposixc`.

### 27e-old. WORK — a page fault inside the kernel entry

`start64` runs -- the trace shows `cmpl $0x41524f53, %esi` at its first
instruction, so the magic handshake with the bootstrap works -- and then:

```
v=0e e=0000 cpl=0 IP=0008:00000000013b3de1 SP=0010:000000000138e6c8
            CR2=fffffffffffff490
v=08 e=0000 cpl=0 IP=0008:00000000013b3de1  EAX=0000000000308030
```

`CR2` is -0xb70 as a signed value, so this is a null base plus a negative
field offset rather than a wild address. The #DF follows because there is still
no IDT at that point. Next step is mapping 0x13b3de1 to a source line, for
which the load base is now known from the trace: `start64` sits at 0x13b8370.

### 27d. RESOLVED — the entry point is the startup section, not the first code

Fixed on `fix/elf-loader-startup-section-entry`, off the weak-symbol branch and
so off `upstream/master`.

`bootstrap/elfloader.c:676` took the first `SHF_EXECINSTR` section as the entry.
That is a guess, and a module's generated start file breaks it: for a resource
the start file holds only the Resident structure, so its `.text` is present and
empty, which puts `.text` first in the linked image while `start64` stays in
`.aros.startup` at section index 7. The bootstrap jumped to whatever was first
in `.text` -- on x86_64 the file-scope `asm()` `delay` of
`arch/x86_64-pc/kernel/kernel_startup.c:642`, which clang emits ahead of every
function. It is `jmp`/`retq`, so the kernel returned to a stack slot holding no
address and ran through zeroed memory to a stray `0x2f`.

`.aros.startup` is not a guess: `__startup`
(`compiler/arossupport/include/system.h:258`) exists to mark the startup code.
A file without that section keeps the old behaviour.

Found alongside: `config/make.tmpl:2681` puts the start files at the *head* of a
module's object list and `:2712` passes the end object separately for the tail.
We appended both. The end-last half is required by
`tools/genmodule/writeend.c:44`, where the romtag's `rt_EndSkip` points at the
marker, so the order is now stated explicitly in
`aros_place_module_scaffolding`.

### 27d-old. WORK — the kernel hits an invalid opcode after the kickstart loads

With the loader fix the kickstart loads and the kernel runs. It then faults:

```
v=06 e=0000 cpl=0 IP=0008:000000000031052f EAX=0000000080000001   #UD
v=0d e=0032 cpl=0 IP=0008:000000000031052f                        #GP
v=08 e=0000 cpl=0 IP=0008:000000000031052f                        #DF
```

`qemu-system-x86_64 ... -d int`. Established so far:

  * Not a missing CPU feature: `-cpu max` faults identically, so the bytes at
    that address are not a valid instruction rather than an unsupported one.
  * The repeated IP across all three vectors means the #UD handler faults too,
    so no usable IDT is in place yet.
  * `EAX=0x80000001` is a CPUID leaf, so the fault is at or just after a CPUID
    sequence.
  * Not an unhandled relocation: the kickstart contains only R_X86_64_64,
    _PLT32, _PC32, _32 and _32S, and `bootstrap/elfloader.c:239` handles all
    five.

What has not been done: mapping 0x31052f back to a kickstart offset, which
needs the load base the bootstrap chose. That is the next step, not more
guessing.

### 27c. RESOLVED — an unresolved weak symbol has the value zero

Fixed in both loaders on `fix/elf-loader-weak-undefined-symbols`, off
`upstream/master`, since both files were byte-identical to it.

They treated every `SHN_UNDEF` as an error. ELF does not: the link editor
leaves an unresolved weak symbol undefined on purpose and its value is zero.
`__aros_libreq_<base>` is the case -- every module's generated start file reads
it weakly to compare the library version it needs
(`tools/genmodule/writestart.c:788`), and only a module using `ADD2LIBS`
(`symbolsets.h:149`) defines it, so zero is the intended answer for "no version
required".

Worth recording: this only became reachable because the generated start files
started being built at all (`de38eaba51`). The reference has always put
`<mod>_start.o` in the kickstart object (`config/make.tmpl:2681` folds
`_STARTFILES` into `_OBJS`, and `:2756` takes `_OBJS`), so upstream carries the
same weak-undefined reference and the same loader would refuse it. Nothing in
either file differs from upstream.

### 27c-old. WORK — the kickstart fails to load on one weak undefined symbol

The first QEMU run got this far, which is the first AROS-NG code to execute:

```
Booting from ROM..[ELF Loader] Undefined symbol '__aros_libreq_SysBase'
Kickstart ELF: Relocation error in section 2!
Failed to load the kickstart
*** SYSTEM PANIC!!! ***
```

`qemu-system-x86_64 -kernel SYS/boot/pc/bootstrap -initrd SYS/boot/pc/kernel
-append "aros debug=serial" -m 1024`. The serial console needs the leading
space: `arch/all-native/bootconsole/common.c:81` looks for `" debug"`. With
`-m 256` the bootstrap reports needing 268 MB and panics before loading, so the
kickstart's working area is what wants the memory.

The symbol is weak in the image and the loader does not care:
`bootstrap/elfloader.c:157` fails on any `SHN_UNDEF`, weak or not.

Where the two spellings part ways:

  * `compiler/include/aros/symbolsets.h:158` -- `AROS_LIBREQ(bname, ver)`
    emits `__aros_libreq_<bname>.<ver>`, with a version suffix, and its comment
    says why: lld rejects repeated absolute definitions where GNU ld tolerates
    them.
  * `compiler/include/aros/symbolsets.h:151` -- `AROS_LIBSET` declares
    `extern const LONG __aros_libreq_##bname __attribute__((weak))`, without
    the suffix, and `rom/exec/exec_autoinit.c:23` reads that name.

Both spellings are upstream's; our only change to that file is a
`CONST_STRPTR` cast. The kickstart accordingly holds
`__aros_libreq_SysBase w` (weak, undefined) next to a dozen
`__aros_libreq_SysBase.<n> a` (absolute, defined). What has not been
established is how upstream resolves the unsuffixed reference, and that is the
thing to read next -- not the loader, which is unambiguous.

### 27b. RESOLVED — the PC bootstrap links and boots

2.1 MB ELF32 i386 executable, entry 0x100270, multiboot magic 0x1BADB002 at
file offset 4096. QEMU loads it and it runs.

Three pieces, all reported at their call sites:

  * a declaration-scoped ISA override, from the `TARGET_ISA_LDFLAGS` assignment
    to a global (`arch/all-pc/bootstrap/mmakefile.src:32`);
  * a standalone-executable link (`cmake/StandaloneLink.cmake`), triggered by
    the declaration carrying `-Wl,-T,<script>`;
  * the 32-bit archives in `gen/lib32`, which were built 64-bit because
    `ISA_FLAGS := $(ISA_32_FLAGS)` is an Autoconf value with no counterpart
    here. CMake now substitutes the 32-bit form of the triple it already picks
    per CPU, which is the same substitution `cmake/AROS.cmake:301` makes for
    the 64-bit case.

Four host-toolchain additions the reference recipe does not state, each
commented where it is applied: `--image-base` and `-z norelro` on the flat
binary link, `--ld-path` and `-no-pie` on the standalone link. All four are
lld/clang defaults differing from GNU ld's, not choices about AROS.

### 27b-old. WORK — the PC bootstrap is the last gate to a QEMU attempt

Verified prerequisites, so this is link work and not a dependency hunt:

  * `gen/lib32/` already holds `libbootstrap.a`, `libbootconsole.a` and
    `libstdc.static.a`, all built 32-bit by the `linklibs-*32` declarations.
  * `arch/all-pc/bootstrap/ldscript.lds` is present.

What is missing is the link kind. The bootstrap is a standalone multiboot ELF
executable at a fixed address, not an AROS relocatable module, and our
`CMAKE_C_LINK_EXECUTABLE` is globally `ld.lld -r`. The declaration's own
comment (`arch/all-pc/bootstrap/mmakefile.src:25`) says why it must be clang
driving the system linker: the AROS triple links via collect-aros, which emits
relocatable modules and ignores the linker script.

Two pieces:

  1. A declaration-scoped ISA override. `TARGET_ISA_LDFLAGS :=
     --target=i386-pc-linux-gnu -march=i486` and `TARGET_C_LIBS :=
     $(TARGET_32_C_LIBS)` are assignments to *global* variables inside an
     `ifeq` on the toolchain, which is why the flag collector, which reads
     `USER_*` only, does not see them.
  2. A standalone-executable link for a program declaration that carries
     `-Wl,-T,<script>`: an object library at the declared ISA plus a custom
     command linking through clang with `-m32 -Wl,-N -Wl,-e,kernel_bootstrap`
     and the script. CMake has no per-target link rule, so a custom command is
     the honest model, and it mirrors the reference having a distinct recipe.

### 27b-old. WORK — what we carry of the bootstrap today

`kernel-bootstrap-pc` fails at its vesa blob with

    ld.lld: error: ... vesa.c.obj is incompatible with elf_i386

because the whole declaration is 32-bit and almost none of that is modelled.
`arch/all-pc/bootstrap/mmakefile.src` sets

  * `TARGET_ISA_LDFLAGS := --target=i386-pc-linux-gnu -march=i486` (line 32),
    an assignment to a global rather than to a `USER_*` variable, which is why
    the flag collector does not see it;
  * `USER_LDFLAGS := -m32 -Wl,-N,-e,kernel_bootstrap -Wl,-T,.../ldscript.lds
    -static-libgcc` (line 19);
  * `TARGET_C_LIBS := $(TARGET_32_C_LIBS)` (line 35).

Of that we carry only `-DMULTIBOOT_64BIT` and `-L$(GENDIR)/lib32`. Needed: a
per-declaration ISA/target override, the linker script, and the 32-bit
compiler-rt.

### 27. RESOLVED — `scripts/boot/qemu-pc-x86_64.sh`

`boot-iso` still has no loader, because `grub` is one of the nine untranspiled
`%build_with_configure` declarations from point 10. It is not needed: the
bootstrap is a multiboot image, so QEMU loads it the way GRUB would, with
`-kernel` the bootstrap and `-initrd` the module list.

The runner writes the boot console to `<out>.serial` and the VGA screen to
`<out>.png`, and takes extra QEMU arguments after `--`, which is how the traces
in 27c through 27g were taken. Two of its choices are worth knowing:

  * `" debug=serial"` is what turns the console on at all
    (`arch/all-native/bootconsole/common.c:79` reads it with
    `strstr(cmdline, " debug")`, leading space included). Without it a failing
    boot is a black screen and nothing else.
  * only the kickstart is passed as a module, for the reason in 27h.

### 29. RESOLVED — release producers share the toolchain provisioning boundary

`fc2aac81b2` declares `crosstools-libunwind-release`,
`crosstools-compiler-rt-release` and `crosstools-compiler-rt32-release` beside
their non-release siblings. All six provision the host compiler this build
consumes, but only the three originals are in
`LLVM_PROVISIONING_DECLARATIONS`, so the three `-release` ones are counted in
the target inventory as things the target tree owes.

The release and ordinary runtime declarations have the same source roots,
host compiler, `CROSSTOOLSDIR` prefix and CMake option owners. The release
variants add only their producer package names and the explicit temporary SDK
dependencies. They therefore belong to the same external toolchain
provisioning boundary and are now classified by exact declaration contracts.

The GCC `tools-crosstools-gcc-libatomic` lane is included for the same reason:
although it compiles target code, its source and object roots live below the
host-side GCC producer and its output provisions that compiler installation;
it is not a product of the AROS target tree. Structural source checks plus the
exact declaration make both classifications fail closed. Any relevant drift
returns the declaration to the ordinary missing-target gate.

### 28. WRONG — the four `fix/*` branches held fixes this branch needed

Three of the four were still missing from `feat/cmake-build-propagation` and
were breaking `kernel-kernel`, `kernel-aros` and `kernel-exec`, three of the
most boot-critical modules. Applied as `db28a8940a`, `9657524044`,
`ee1b2546d0`.

Two lessons recorded because both cost time here: a branch created for
upstreaming is not a branch that has been applied, and re-deriving an edit
instead of cherry-picking the branch put `#include <proto/exec.h>` inside
`#if defined(DEBUG_TIMESTAMP)`, where it fixed nothing. The branch had it
right.

The remaining branch, `fix/ahci-posix-errno`, did not appear in this census;
whether it is still needed is unchecked.

---

## Quality gates

### 56. RESOLVED — `aros` has one enterprise diagnostic and logging boundary

`aros` no longer relies on Miette's implicit `main -> Result` renderer or a
direct process exit. Stable `AR0001`–`AR0999` families and typed stages cover
the complete top-level command surface; each failure has an actionable hint
and deterministic command context. Human output and the versioned
`aros-tool-diagnostics-v1` JSON document are selected globally or through the
`AROS_DIAGNOSTIC_FORMAT` environment variable.

The policy-neutral renderer and logger now live in `aros-common`. Collector,
AHI runner and CLI policies select their own code, stage, hint and log schema
without maintaining three implementations. CLI logs use
`aros-cli-log-v1`, are disabled by default, require an explicit local file, and
never add timestamps, hostnames or CI metadata.

Child exit codes and signals survive as structured context. JSON mode captures
non-interactive child streams into temporary files, includes at most 64 KiB of
each failed stream in the diagnostic, and does not emit raw child errors ahead
of the JSON document. Successful output is replayed. Integration coverage
proves invocation, observability, repository and command boundaries, separate
JSONL logging, child stderr isolation/status context, help outside a checkout,
and fail-closed clean-preset validation.

The audit found real silent failures rather than only presentation debt:
`sync` ignored both Git statuses, `ccache` ignored every cache-tool status, and
`clean --preset` formed its deletion path without the existing preset
validator. All three now fail closed. Formatting, strict workspace Clippy and
the complete Rust workspace pass, as do all 25 CMake fixtures including the
real GRUB and native AHI builds.

### 55. RESOLVED — the complete Rust workspace is warning-free under Clippy

`cargo clippy --workspace --all-targets -- -D warnings` passes on Rust 1.96.
All findings in `aros-genmodule`, `aros-transpiler` and `aros-cli` were fixed
without crate-wide or workspace-wide lint suppressions. Formatting and the
complete workspace test suite pass.

The release generator and transpiler were rebuilt before exercising the real
AHI target for `pc-x86_64`, `arm-raspi` and `rpi-aarch64`. All three builds
pass, their immediate repeats are Ninja no-ops, and all 73/85/85 declared
products remain byte-identical to the pre-change baseline.

### 54. RESOLVED — the AHI contract has one typed native executor

The closed AHI lane no longer evaluates a generated contract as arbitrary
CMake or carries a second implementation of its staging/configure/make logic.
The checkout-local Rust `aros-ahi-runner` parses exactly 44 allowlisted literal
assignments into typed architecture, product, path, hash and flag values. It
rejects missing, duplicate and unknown fields; validates the complete
filesystem and input identity before mutation; executes child tools with a
cleared, explicit environment; validates installed products including ELF
class/machine; and re-hashes all source inputs after the build. The former
622-line `cmake/RunAhiBuild.cmake` has been deleted.

Failures use stable `AH0001`–`AH0901` codes and the shared
`aros-tool-diagnostics-v1` human/JSON schema. Opt-in local logs have a separate
stable `aros-ahi-runner-log-v1` human/JSONL contract and contain no ambient
timestamps, hostnames or CI metadata. Process diagnostics are bounded. The
runner is part of `aros hosttools build/check`, not a tool a user must discover
and build separately after configuration.

The focused fixture executes all three modes under a hostile environment and
covers collector dispatch, missing tools, no-op/repair behaviour, whitespace,
source immutability and symlink rejection. The typed contract and CLI tests,
strict workspace-wide Clippy and full Rust workspace pass. Real native AHI
rebuilds pass for `pc-x86_64`, `arm-raspi` and `rpi-aarch64`, followed by true
Ninja no-ops.
All 73, 85 and 85 declared products are byte-identical to the pre-runner
baseline. No upstream AHI source is changed.

### 53. RESOLVED — the closed AHI lane cannot bypass `aros-collect`

The generated AHI compiler adapter previously sent final links straight to
`ld.lld`, despite the top-level invariant that AROS links pass through the
collector. It now invokes `aros-collect --ld <audited-ld.lld> -- <arguments>`.
Compile-only and probe calls still use Clang. The collector is an explicit,
validated member of the CMake/runner contract and a dependency of the AHI
build edge; omission fails closed during configuration.

The fixture executes a mock collector in all three architecture modes and has
a dedicated missing-collector failure case. Real rebuilds of
`workbench-devs-AHI-subsystem` pass for `pc-x86_64`, `arm-raspi` and
`rpi-aarch64`; the following builds are no-ops. Product counts remain exactly
73, 85 and 85. Only the 13, 19 and 19 ELF outputs differ from the direct-link
baseline, while all other products are byte-identical. All of those ELF files
contain `.aros.sets` and none contains an uncollected `.aros.set.*` section.

This resolves the link-path defect. Point 54 records the subsequent typed Rust
runner refactor, which preserves this product, section, failure and no-op
evidence.

### 52. RESOLVED — transpiler diagnostics and output publication fail closed

The worst failure mode is closed: directory-walk, fetch-discovery and parse
errors are no longer discarded through `.ok()`, and recognised capability
drift no longer survives only in `unmodelled-declarations.txt`. Parallel
failures are aggregated, sorted and deduplicated, and capability fingerprints
name the expected and observed value plus the required transpiler update.

All five gates are implemented:

1. fatal diagnostics use typed stages/severity, optional file/line/column
   locations and stable `AT0001`–`AT0007` codes;
2. the graph and every sidecar/report are staged first and committed through a
   rollback-capable publication, with the CMake graph replaced last;
3. report writes and stale-report removals are part of that transaction and a
   failure is fatal;
4. `--diagnostic-format json` emits the versioned
   `aros-tool-diagnostics-v1` schema without progress/tracing contamination;
5. the embedded capability-fingerprint registry is completely validated by a
   non-panicking API before scanning starts.

Coverage reports now have their own versioned
`aros-transpiler-coverage-v1` index. `AT1001`–`AT1032` identify the current
categories with `info` or `warning` severity and zero-count entries remain in
the index. There is no accepted-count baseline or suppression list. Adding an
unregistered report category is an internal error and stops publication.

The regression gates cover stable human/JSON rendering, checkout-independent
paths, text-independent capability classification, registry validation,
staging failure, injected mid-commit rollback, stale report removal and the
coverage schema. Direct x86_64, ARM hard-float and AArch64 runs pass with the
new error model.

### 47. WORK — `parse_mmakefile_impl` is the last thing in the way

The decomposition took `parser.rs` from 12 415 lines to 5 250, in eleven
commits, each of them verified byte-identical on all three presets by the point
13 harness. What came out:

| module | lines | what it owns |
|---|---|---|
| `capability/` (nine files) | 4 219 | declarations modelled by semantic contracts or narrow fingerprints |
| `make_vars.rs` | 788 | variables per line, and the three-valued conditional |
| `sources.rs` | 464 | argument text to four language lanes |
| `module_paths.rs` | 379 | output directory by module type, implied `#MM` edges |
| `copy_directories.rs` | 339 | `%copy_dir_recursive`, both ends checked |
| `collector.rs` | 263 | includes inlined for the collectors, port scope |
| `make_deps.rs` | 190 | which variables an expression reads |

What is left in `parser.rs` is 2 367 lines of code and 2 883 of tests, and
1 380 of that code is one function. `parse_mmakefile_impl` is a single pass with
five phases and a great deal of state carried between them:

  1. the fetch collector and the port scope it proves (85 lines);
  2. the variable scope and the conditional line states (20);
  3. the file-global properties -- includes, flags, packages, arch sources,
     option files -- which are file-level in Make and therefore cannot be read
     per declaration (110);
  4. **the declaration loop**, about 1 250 lines over one `for invocation in
     invocations`, which builds every target kind and is where the state
     accumulates;
  5. the after-pass: FlexCat rules, host-generated headers, HIDD stubs, binary
     objects (115).

Phases 1, 2, 3 and 5 would extract the way everything else did. The declaration
loop would not: it is not a family that can be lifted out, it is one long
sequence whose steps read and write a shared set of locals. Splitting it means
naming that state -- deciding what a "declaration under construction" is -- and
that is a design step, not a move. The harness makes it safe to attempt but does
not make the design.

Worth doing, not urgent. `parser.rs` is now the file its name says it is, and
the argument for going further is readability rather than a blocked change.

### 46. SUPERSEDED 2026-08-26 — package pins removed; 14 narrow capability fingerprints remain

The design recorded below was an intermediate state and is no longer the
current contract. The transpiler no longer embeds archive hashes for Mesa,
Mako, MarkupSafe, CUnit or libaom, and it no longer hashes repository drivers,
patches, whole AHI/GRUB/Nouveau recipes, or redundant outer manifests.

The current rules are documented in
`tools/aros-tools/crates/aros-transpiler/README.md`. In short:

- package identity comes from the upstream `%fetch` declaration;
- repository files and patches are direct dependencies;
- explicit source manifests contain paths only; CMake watches their files and
  passes transient configure-time content hashes to the runner;
- `capability-fingerprints.pins` has 14 entries, restricted to opaque Mesa
  recipe fragments and versioned source inventories expanded into fixed jobs;
- GRUB 2.12 retains one fixed archive SHA-256 in `cmake/GrubSourceLock.cmake`
  because CMake downloads it directly and therefore needs an integrity anchor.

Fingerprint drift now stops the transpiler with the affected input, expected
and observed fingerprints, and the instruction to review and update the
capability. It cannot silently fall through to a partial graph. Expected
architecture exclusions, such as the x86-only GRUB host lanes on ARM, remain
non-fatal.

The following text is retained as investigation history for the superseded
26-digest design.

#### Historical intermediate design

26 `*_SHA256` constants left `parser.rs` for
`aros-transpiler/pinned-digests.pins`, and they turned out to be 24 distinct
values: the mesa-20.0.8 archive digest was spelled three times in the same file,
once at module level and twice as a function-local constant.

Reading them apart mattered more than moving them. They are two kinds of pin:

  * **20 in-tree inputs of a modelled capability.** Manifests, mmakefiles, a
    driver script, a patch, and four digests of a *text block* rather than a
    whole file. Checked against the tree being transpiled; a change means the
    capability is not recognised and the declaration lands in the unmodelled
    report. Three are also emitted into the generated CMake, so the build
    re-checks the same bytes.
  * **4 upstream artefacts a capability fetches** (mesa-20.0.8, Mako,
    MarkupSafe, CUnit). Never checked here: they are emitted so the fetch can
    verify a download. A new value there is a deliberately different artefact,
    not a re-pin after an edit, which is the opposite of what a stale value
    means in the first class. The file states that distinction, because as
    neighbouring `const` declarations the two were indistinguishable.

The lookup is shared: `aros_common::pins` holds the reader used by the remaining
transpiler capability registry. Two safety nets, because a pin name is a string
and a typo would otherwise surface as a panic on whichever run first reaches
that capability:

  * the file is checked as a whole -- every value a sha256, every name unique
    and kebab-case;
  * `pins::NAMES` lists every name the crate looks up and a test resolves all
    of them, which covers the capabilities no test exercises.

`parser.rs` is 59 lines shorter (-108/+49).

**The proof is the point 13 harness, on its first real use:**
`aros golden verify` reports all three presets byte-identical across the change.
36 call sites moved and 24 values changed file, and the generated output for
pc-x86_64, arm-raspi and rpi-aarch64 is the same to the byte. That is the check
the decomposition will run after every step.

### 45. RESOLVED — the CMake fixture suite was in no gate, and a third of it was red

`cmake/tests/` holds 21 `cmake -P …Test.cmake` fixtures. Nothing runs them.
`toolchains/HANDOFF.md`'s five-check gate does not, and neither does anything
else, so they were only ever run by hand. Seven were red, from five causes, and
every one of them was introduced by this branch's own commits:

  * `AROS_COLLECT_BIN` had a default only in the top-level `CMakeLists.txt`,
    while the requirement lives in `AROS.cmake`'s linker rule. Six fixtures
    include that module directly and got
    `AROS-NG requires the executable Rust aros-collect at .` The default now
    sits next to the requirement, derived from the module's own location,
    because in a fixture `CMAKE_SOURCE_DIR` is the fixture.
  * `aros_add_program` calls `aros_standalone_link_wanted`, which
    `StandaloneLink.cmake` defines and only the top-level included:
    `Unknown CMake command`. `AROS.cmake` includes it now; `include_guard`
    makes the top-level include a no-op.
  * `always-cxx-link` pinned the locked-release link rule as starting with
    `<toolchain>/bin/ld.lld -r`. Every link goes through `aros-collect` since
    point 32. Re-pinned on what the fixture is actually about: own linker, own
    sysroot, partial link.
  * `private-linklib-output` links a host executable, so AppleClang's
    `-Wl,-search_paths_first -Wl,-headerpad_max_install_names` reached ld.lld,
    which rejects both. A real build never sees them because it configures with
    a cross toolchain; the fixture drops the host defaults.
  * `ahi-build` and `configure-build` staged their link-library archives as
    files, which stopped being enough when points 42 and 44 made the helpers
    ask the target. Both declare imported archives now, which is what a fixture
    with a mock C compiler can offer honestly.

Two of those are today's own work (`1b22815bc5` broke `AhiBuildTest` and the
session reported "all tests green" on the strength of `cargo test` alone), and
four had been red for longer without anyone knowing.

All 21 pass now, measured: 300 seconds for the sweep, 254 of them
`GrubBuildTest` and 21 `AhiBuildTest`; fourteen of the remaining nineteen take
under three seconds each. That cost is worth naming, because a five-minute gate
gets skipped: GrubBuildTest is the one to run separately, the other twenty take
45 seconds together. The sweep belongs in the gate with `cargo fmt --check`
(point 8) and `cargo test -p aros-verify` (point 7).

### 44. RESOLVED — WirelessManager pinned the same archive name, in three places

Point 42 was not the only consumer that spelled a link library's archive out.
The configure-style declaration for `workbench-network-wirelessmanager` named
`${AROS_BUILD_DIR}/liblinklibs-mui.a` as its build dependency, and it linked
against it: `RunConfigureBuild.cmake` passes it as `LIBS=` to the wpa_supplicant
Makefile, which replaces that Makefile's own `LIBS += -lmui` (line 67).

`linklibs-mui` is canonical, so its archive is `SYS/Developer/lib/libmui.a`.
The pinned path existed anyway, as a leftover: 9 444 bytes dated 10:11 next to
the canonical one of the same size dated 22:23. Removing the leftover gives

```
ninja: error: 'liblinklibs-mui.a', needed by
       'gen/configure/workbench/network/WirelessManager/.aros-...-installed',
       missing and no known rule to make it
```

which is worse than point 42's case: no rule produces that path at all, so the
declaration had no working edge, only a stale file.

The same string was pinned three times: the transpiler's declaration,
`ConfigureBuild.cmake`'s independent audit of the "audited capability", and the
`cmake/tests/configure-build` fixture. All three went stale together, and the
audit could not catch the declaration because both said the same wrong thing.

Fixed by asking the target, as in point 42, and by putting that question in one
place:

  * `cmake/LinklibArchive.cmake` is new and holds `aros_linklib_archive_path`,
    used by `AhiBuild.cmake`, `ConfigureBuild.cmake` and the two fixtures. It
    also handles an imported archive, which is what a fixture can offer when
    its C compiler is a mock.
  * `aros_build_configure` takes `DEPENDENCY_TARGETS`; the `DEPENDENCY_PRODUCTS`
    keyword is gone, because nothing needed a bare path once the fixture
    declared a target. The runner contract still carries resolved paths under
    the old name.
  * the audit now checks *which* link library is linked, not where its archive
    sits, plus that exactly one archive resolved.
  * `RunConfigureBuild.cmake` checks the count, existence and size instead of
    taking element 0 of an unchecked list.
  * the declaration is emitted after the concrete targets, in its own block,
    because `aros_build_configure` cannot ask a target that does not exist yet.
    A configure build that publishes an archive interface still has to precede
    its consumers, so the generator splits the list; if one declaration ever
    needs both orderings it writes a `message(FATAL_ERROR)` into the generated
    file rather than guessing.

`SYS/C/WirelessManager` (1 487 016 bytes) now builds after
`Linking C static library SYS/Developer/lib/libmui.a`, in that order. Before
this it had never been built from a working edge.

### 43. RESOLVED — the ARM and AArch64 BSP package lanes build cleanly

Rechecked from the direct CMake graph on 25 August 2026. Both full Raspberry Pi
package lanes now compile, link and package without an error:

```text
arm-raspi:
  aros-arm-bsp.rom       55 modules, 3,002,864 payload bytes
  aros-arm-bcm2708.rom   10 modules,   353,288 payload bytes

rpi-aarch64:
  aros-aarch64-bsp.rom   60 modules, 4,052,872 payload bytes
```

The second invocation of both named build commands reports `no work to do`.
The blockers found by the first complete package run were generic rather than
source workarounds:

* `hidd-gallium` and `workbench-libs-gallium` are in-tree modules which include
  `mesa.cfg`. The transpiler's pinned Mesa-20 compile contract had only been
  applied in its linklib/program loop, not its `%build_module` loop, so both
  architectures lost `src/gallium/include`, the Mesa defines and
  `-fno-strict-aliasing`. The exact contract now covers both module declarations
  and has profile/parser tests.
* Existing build trees could retain m68k's `asm/cpu.h` in `GENINCDIR` from the
  old foreign-header staging bug. That root precedes the correct SDK header, so
  ARM and AArch64 both saw no `dmb`/`dsb` declarations. Bootstrap now refreshes
  the common dispatcher in both roots, matching `compiler-includes` semantics.
* `usb2otg_intern.h` used `memset` without including its declaration. It now
  includes `<string.h>` and `usb2otg.device` builds in both lanes.

This closes the named BSP build/package obligation. It does **not** close point
25's unqualified build of every third-party application, nor does it assert a
hardware boot; Pi/UART runtime evidence is the next architecture gate.

The payload figures above were refreshed on 27 August after point 50 forced a
consistent rebuild from exact private ABI headers. The earlier smaller figures
were produced from a build tree containing stale generated headers.

#### Earlier baseline (superseded)

Checked after a session of pc-x86_64-only work, because several changes were
target-shaped: the flavour mapping, `aros/config.h`, and the lane attachments
touched riscv, ppc and unix lanes.

`arm-raspi` configures and builds: 1077 failed steps out of 17106, and the top of
the list is the same ports as on pc-x86_64 (dbus 221, lzma 200, arostcp 34). No
sign of a regression from this session's work: no genmodule modtype error, no
missing-config error, and the 490 `aros-collect` lines are all the ordinary
multi-version reports. Its flavour is `AROS_FLAVOUR_STANDALONE`, as configure
derives for `r*pi`.

One pre-existing failure there is worth naming, because it is already reported
and still built: `kernel-bootstrap-pc-objs` is compiled on an arm target with the
ARM global options *and* its own `--target=i386-pc-linux-gnu`, so clang refuses
`-mcpu=cortex-a7`. It is listed in
`generated_targets.foreign-arch-targets.txt`, which is the report saying a target
declared under `arch/all-pc` could not be gated off. Seven steps.

`rpi-aarch64` configures and, once point 42 was fixed, builds: 1669 failed steps
of 18848. Not comparable with the 1026 of the last recorded run, which stopped at
4052 of 4703 steps and never reached most of the tree. The failures concentrate
the same way as elsewhere: 932 of the 1669 are `workbench-libs-gl-linklib` in its
two flavours, then dbus 221 and lzma 200, so about 1350 in five targets, all
ports and GL.

### 42. RESOLVED — the AHI archives are asked of their targets

`rpi-aarch64` no longer configures into a buildable graph:

```
ninja: error: 'liblinklibs-amiga.a', needed by 'SYS/Prefs/AHI',
       missing and no known rule to make it
```

The then-current `cmake/AhiBuild.cmake` and former
`cmake/RunAhiBuild.cmake` both pinned three archive paths literally, as an
audited contract compared on each side:

```
<build root>/liblinklibs-amiga.a
<build root>/liblinklibs-libm.a
<build root>/liblinklibs-mui.a
```

`liblinklibs-<mmake>.a` is what a link library is called when it is *not*
canonical. A linklib becomes canonical, and so moves to
`SYS/Developer/lib/lib<name>.a`, the moment any consumer names it -- that is
`promote_canonical` in the transpiler's graph. So the contract pins a filename
that depends on whether anything happens to use the library.

Today it changed, and the chain is established rather than guessed:

  1. point 38 carried `conffile=`, so declarations whose config stem is not
     modname finally get their genmodule scaffolding;
  2. `workbench-prefs-network-module-ipv4` (`ipv4.conf` for modname `net4`),
     `workbench-system-vmm-handler` (`VMM_Handler.conf`) and the SysExplorer
     modules (`ahci.conf`, `ata.conf`) became real targets instead of empty
     ones;
  3. each of them states `uselibs=amiga`, so `linklibs-amiga` was promoted;
  4. its archive is now `SYS/Developer/lib/libamiga.a`, and the pinned
     `liblinklibs-amiga.a` has no rule.

`pc-x86_64` is broken the same way and has not noticed: a stale
`liblinklibs-amiga.a` from earlier the same day still sits in its build root and
satisfies the edge. A clean build would fail identically. `arm-raspi` does not
declare the target at all.

The fix is to resolve the three archives from their targets and pass the real
paths, and to check them by *alias mapping* rather than by pinned filename --
the runner already copies each into a staging directory under a fixed alias
(`libamiga.a`, `libm.a`, `libmui.a`) and already requires each to be a regular
non-empty file inside the build root. That keeps every substantive part of the
audit and drops only the assumption that broke.

Done that way. Two things about the scope are worth recording, because the phrase
"audited contract" made it sound heavier than it was.

Every file involved was ours: `cmake/AhiBuild.cmake`, the since-deleted
`cmake/RunAhiBuild.cmake`, and the transpiler's emission point, all created on
this branch in `e1cb119e39`. No AROS content is touched -- the AHI sources and their
`mmakefile.src` are upstream and unchanged, and the only thing our branch ever
added under `workbench/devs/AHI/` is the sha256 input manifest we generate
ourselves. So this was not a relaxation of anything upstream relies on; it was a
correction of an assumption we wrote a few days ago.

And asking the target means the declaration has to come after the targets exist,
so the transpiler emits it there rather than with the other capability-checked
builds.

`pc-x86_64` now builds `SYS/Prefs/AHI` for the first time instead of riding on a
stale archive, and `rpi-aarch64` configures into a graph that builds.

### 30. RESOLVED — `aros-cli test` no longer reports a boot it never looked at

Replaced by the implementation of point 31: the verdict comes from the serial log
and the exception trace, the three non-existent boot paths are gone, and
`" debug=serial"` is passed so the boot console prints at all. There is no
interactive mode any more, because a run nobody reads cannot assert anything.

The original text follows.

### 30-old. WRONG — `aros-cli test` reports a verified boot it never looked at

`main.rs:736` builds `boot-iso`, starts QEMU, sleeps for `--timeout`, kills the
process and prints:

```
✓ VERIFIED: QEMU boot execution finished cleanly without crashes!
```

Nothing between the sleep and that line reads anything. The message is printed
for a guest that triple-faulted in the first millisecond exactly as for one
that reached Workbench, so the command cannot fail. It is worse than no boot
test, because it produces a green result on demand.

The three paths it boots from do not exist either:

| what it uses                                  | what the build writes            |
|-----------------------------------------------|----------------------------------|
| `build/<preset>/aros-x86_64-pc.iso`, `-cdrom` | never built, and El Torito-less  |
| `build/<preset>/bootstrap`                    | `SYS/boot/pc/bootstrap`          |
| `SYS/Libs/kernel-exec.library` as `-initrd`   | exec is a kickstart member, so the module is `SYS/boot/pc/kernel` |

The ISO name is hardcoded for x86_64-pc whatever `--preset` says, `boot-iso`
has no bootloader (point 10), and it passes no `" debug=serial"`, so even a
correct image would boot to a black screen. Fix or remove; a command that
cannot fail must not stay.

### 31. RESOLVED — `aros test` reads the boot instead of waiting for it

Every requirement below is implemented. What the first run of the finished tool
found is the best argument for having built it:

```
reached: kickstart running
  failure: the kernel panicked: System Boot Failed!
  failure: an exception was taken while delivering another, so the guest double-faulted
  read-only block loaded at 0x1391000 (258 traced blocks agree)
  v=08 cpl=0 IP=0x13ae183 = .text+0x1d063 = FindMem+0x43
  v=0d cpl=0 IP=0x13ae183 = .text+0x1d063 = FindMem+0x43, 147 times
  v=0d cpl=3 IP=0x139e4d0 = .text+0xd3b0 = krnPanic+0x90
  not tested: only the kickstart was passed as a multiboot module
```

Two findings came out of the first two runs. AROS enters supervisor mode with
`int 0xfe` and QEMU logs software interrupts in the same stream, so KrnSchedule,
KrnSwitch and Supervisor were being reported as faults five times a run; `i=1`
separates them. And the fault that ends a boot with packages loaded is at an
address outside the kickstart, so it is inside a package module, each of which
is its own relocatable ELF -- the report says that rather than guessing.

The load base is derived, not assumed: traced instruction bytes are matched
against the modelled read-only block and the majority wins, with 197 to 258
blocks agreeing per run. Doing that by hand three times in one session produced
one wrong answer, a base 0x80 out, which named `Exec_89_TypeOfMem` where the code
was `Exec_25_SuperState`, with complete confidence.

The original text follows.

### 31-old. WORK — make the boot a deterministic, asserting check in `aros-cli`

`scripts/boot/qemu-pc-x86_64.sh` reproduces a boot, and that is all it does:
the reading is still by eye and the interpretation by hand. Twice in one day
the expensive part was not finding the fault but locating it — deriving the
kickstart's load base from a byte pattern in an `in_asm` trace, then mapping an
IP to a section and a symbol. That is mechanical work and belongs in the tool.

What the command has to do that neither the script nor point 30's version
does:

  * **Assert, from what it observed.** A verdict comes from the serial log and
    the QEMU trace, never from a timer. Fail on `*** SYSTEM PANIC!!! ***`, on
    `[ELF Loader] Undefined symbol`, on any `v=` exception record, on
    `check_exception`, and on a run that reaches its timeout without the next
    expected milestone.
  * **Name the milestones, and report which one it reached.** Bootstrap
    entered, kickstart loaded, banner printed, romtag scan complete, ExecBase
    created, user mode (`cpl=3`), dos.library opened, Startup-Sequence,
    Workbench. Then the boot has a number, comparable across commits, instead
    of an impression. Today's build reaches "user mode" and stops at point
    27g.
  * **Resolve a fault to a symbol.** Given the faulting IP, the section base
    the loader assigned, and the kickstart ELF, print
    `<section>+<offset> <symbol>+<offset>` and the source line. The base is
    recoverable from the first traced block by matching its bytes against the
    image, which is what was done by hand for 27e and 27g.
  * **Be deterministic.** A fixed CPU model, fixed memory and CPU count, a
    fixed RTC base, and no dependence on host timing. `-icount` is worth
    trying, because an instruction-exact run makes two traces diffable, which
    is the only cheap way to see what a build change did to a boot.
  * **Keep its evidence.** One directory per run holding the serial log, the
    screen, the trace and the verdict, so a regression is a diff and not a
    memory.
  * **Say what it did not test.** Only the kickstart is passed as a module
    today because of point 27h; a run that skips the packages must report that
    it skipped them, the way the transpiler's reports do.

Then `aros-cli test` is a gate the HANDOFF checklist can hold, and the answer
to "how far does it boot" stops being a matter of who last watched the screen.

### 7. SUPERSEDED 2026-08-26 — the broad provisioning digests were removed

The earlier resolution below made the three hashes visible and stopped their
failure from masking independent inventory checks, but it did not answer the
more important question: none of the three whole-input hashes was necessary.

`c513bf311d` deletes `aros-verify/toolchain-provisioning.pins`. The verifier
already matches each of the five excluded `%build_with_cmake` declarations by
its complete semantic argument list. Its surrounding context now checks only
the structural facts that make that exclusion sound: the LLVM tools install
under `$(CROSSTOOLSDIR)`, the default sysroot remains relocatable, configure
owns the unresolved toolchain prefix, and the CMake target is selected as
Generic before `project()`. Mutating any of those facts fails closed and
returns the five declarations to ordinary target coverage. An unrelated LLVM,
MetaMake or CMake edit no longer asks for a digest refresh.

The text below is retained as the history of the intermediate state.

Both halves of this are fixed and both are measured.

**The values left the source file.** The three semantic fingerprints live in
`tools/aros-tools/crates/aros-verify/toolchain-provisioning.pins`, embedded with
`include_str!`, so cargo rebuilds the crate when they change and the binary and
the tests read the same bytes. Re-pinning is now a data edit; it used to be a
code edit in the file the refactor has to be free to move.

**A stale pin no longer masks anything.** `current_architecture_denominators_are_pinned`
asserted the provisioning context first and the eight counts after, so while the
digest was stale the counts were never evaluated -- and they had been wrong by
71 or 72 for that whole time. The four counts that do not depend on the
provisioning classification are their own test now; the four that do, plus the
set memberships, are `toolchain_provisioning_splits_the_target_obligations`.

Measured, by setting one pin to `000000…`:

```
test tests::llvm_provisioning_contract_mutations_fail_closed ... FAILED
test tests::llvm_provisioning_context_is_semantically_fingerprinted ... FAILED
test tests::toolchain_provisioning_splits_the_target_obligations ... FAILED
test tests::current_architecture_denominators_are_pinned ... ok
```

Three tests that genuinely depend on the pin, and the inventory denominators
still evaluated. 23 tests in the crate now, up from 22, and the suite is faster
(3.9 s against 5.6 s) because the two halves run in parallel.

Both failures say what to do rather than only that something is wrong:

```
provisioning fingerprints changed: mmake=451406c6… config=00554cab… cmake=5c2d0de1…
the audited LLVM provisioning context drifted; re-pin
crates/aros-verify/toolchain-provisioning.pins from the digests that
llvm_provisioning_context_is_semantically_fingerprinted prints
```

**The gate.** `toolchains/HANDOFF.md` now has a "Gate before committing"
section. The five commands it listed were a record of one change and were read
as a gate; three checks were missing, each of which had let a red thing through:
`cargo test --workspace` (this point), `cargo fmt --all --check` (point 8) and
the `cmake/tests` sweep (point 45).

### 8. RESOLVED — clippy compiles the workspace again

`685247143c`. The three deny-level errors are gone and
`cargo clippy --workspace --all-targets` compiles for the first time since they
appeared.

What they were hiding is the point. cargo stops dependent crates once one
fails, so `aros-cli` was never linted at all; fixing the three surfaced a
fourth (`trim()` before `split_whitespace()` in `boot.rs`) that no run had ever
reported. That is the same masking as point 7, in a different gate.

  * `flexcat.rs:9` documented a Make recipe with the tab Make requires. Spelled
    with spaces now, with the tab named in the text.
  * `flexcat.rs` `catalog_outputs` returned four `Option`s in a tuple that the
    caller immediately flattened; a named `CatalogOutputs` with `Default` says
    it.
  * `parser.rs` `Err(format!("<literal>"))`.
  * `boot.rs` `rest.trim().split_whitespace()`.

The generated CMake is byte-identical across the change: two distinct release
binaries (`17e475d2` before, `6b003710` after) produce the same 3 153 981
bytes, sha256
`75d280ed88f4cf7b0dc01386f61706f529d1f8d55b63c4e48286c845ac9320c3`.

This earlier intermediate state is superseded by point 9: formatting and the
complete strict workspace lint are now part of the verified gate.

### 9. RESOLVED — the complete Rust workspace is Clippy-clean

`32950fcafd` resolves the remaining findings across `aros-genmodule`,
`aros-transpiler` and `aros-cli` without crate-wide or workspace-wide lint
suppressions. The three `suspicious_operation_groupings` findings in
`parser.rs` were removed by making the intended grouping explicit rather than
accepting Clippy's non-compiling field-name suggestion.

On Rust 1.96, both `cargo fmt --all -- --check` and
`cargo clippy --workspace --all-targets -- -D warnings` pass, followed by the
complete workspace test suite.

---

## Transpiler and parity

### 10. RESOLVED — target parity excludes explicit producers and inactive lanes

The toolchain's own build is an external input boundary, not part of the AROS
target graph. `aros-verify` keeps every applicable LLVM runtime/toolchain lane
and GCC libatomic in a visible `toolchain-provisioning-targets.txt` inventory,
but excludes them from target coverage only while their structural context and
complete declaration arguments match the audited producer contract. This
includes the release variants resolved in point 29; there is no digest of the
complete files and unrelated edits do not require a pin update.

Bootloader selection is equally explicit. Every preset now pins
`AROS_TARGET_BOOTLOADER`; PC selects upstream's `grub2gfx` default and the Pi
profiles select none. The legacy GRUB 0.97 configure declaration is recorded
in `inactive-profile-targets.txt` for a non-`grub` profile. Selecting `grub`, or
changing that exact declaration, immediately makes it an ordinary target
obligation again.

`compiler/libhiddstubs` is not a `%build_*` declaration at all: it is a
handwritten `#MM` archive over the six `%make_hidd_stubs` producers. The
verifier now admits that one manual target through its exact upstream archive
contract, so the generated `linklibs-hiddstubs` is independently declared.
The transpiler's safe local-fragment handling also reads the literal shared
Mesa configuration without mistaking an indented compiler `-include` option
for a Make include. This restores the fetched V3D sources and materialises
`linklibs-gallium_v3d` as a real CMake target.

Fresh full gates are green on all current release profiles:

| profile | target coverage | emitted realised | provisioning | inactive |
|---|---:|---:|---:|---:|
| `pc-x86_64` | 1,078/1,078 | 1,078/1,078 | 10 | 1 legacy GRUB lane |
| `arm-raspi` | 1,075/1,075 | 1,075/1,075 | 8 | 0 |
| `rpi-aarch64` | 1,075/1,075 | 1,075/1,075 | 8 | 0 |

This closes declaration/target/realisation parity, not output-byte parity.
Point 12 remains the explicit limit on that claim. The follow-up V3D closure
now models all twelve V3DX wrapper sources and all three CLE packet headers as
output-tracked, fail-closed generator jobs for every current profile. The real
`libgallium_v3d.a` builds pass on x86_64, ARM and AArch64, immediate repeats are
Ninja no-ops, and the V3D entries have disappeared from the missing-source,
partial-source and unmodelled generated-file reports. Mesa's `qpu_pack.c` also
receives its missing `ffs` declaration through the visible AROS Mesa patch and
Mesa's own `util/bitscan.h`. None of this is a byte comparison with an upstream
MetaMake archive, so it does not change point 12's broader warning.

### 11. WORK — two mmakefiles genmf cannot expand

Reported by `aros-verify` as `verify/genmf-errors.txt`. Not investigated.

### 12. WRONG — the parity claim in circulation overstates what is measured

`aros-verify` compares declaration inventory and shape against the genmf
expansion. Its own `--profile` help says only architecture eligibility is
evidence-backed and that core/distribution reachability needs verified roots.
Nothing measures parity of build *outputs*, so a "bit-for-bit parity with
upstream build outputs" claim has no gate behind it today.

---

## Refactor readiness

### 13. RESOLVED — the golden-output harness, and what it found immediately

`aros golden capture` and `aros golden verify`. The baseline is captured on
demand into `build/golden/`, which is ignored, and belongs to the refactor that
captured it. It is deliberately not a digest committed to the tree: the output
changes with every intended transpiler change, so a committed pin would be
stale almost always, and a check that is nearly always red is not a check. That
is the coupling points 7 and 46 record in two other places.

**The precondition claim in this point was wrong.** Capture runs the transpiler
twice and compares, because a baseline from a producer that varies reports noise
as regression forever. The first capture failed:

```
changed  generated_targets.unresolved-uselibs.txt (+0 bytes, +0 lines,
         first differs at line 14)
24 identical, 1 changed
```

Same bytes, same line count, different content: an ordering difference. The
cause is `resolve_use_libs` (`graph.rs`), which builds its provider index while
iterating `self.targets`, a `HashMap`. Rust seeds that hasher per process, so
the candidate list of an ambiguous `uselibs=` came out in a different order each
run. `write_report` sorts its lines, which is why this survived: the *set* of
lines was stable, only one line's contents moved. Sorting the candidate list
fixes it. The earlier "three runs gave the same sha256" measurement did not
catch it because it compared the main file, not the reports.

A test was pinned on the unsorted order
(`cunit_external_cmake.rs:285`), so it had been asserting whatever the HashMap
iteration happened to produce.

**The "one golden file covers all presets" claim was also wrong.** The scoped
arguments are derived during configuration and they change the output:

| preset | generated_targets.cmake |
|---|---|
| pc-x86_64 | 3 419 144 bytes, 83 373 lines |
| arm-raspi | 3 252 031 bytes, 82 845 lines |
| rpi-aarch64 | 3 417 460 bytes, 83 294 lines |

An unscoped run produces something else again: 873 concrete targets and no
configure, GRUB2, AHI or Python groups, against 901 and all four for pc-x86_64.
So the harness is per preset, and CMake now records the argv it used in
`generated_targets.cmake.invocation` beside its output, which `golden` replays
rather than re-deriving. Capture compares its own first run against the file the
build tree holds, so a record that has drifted from the call is reported rather
than trusted; that check is what confirmed the record end to end, and it also
reports a build tree that predates a source change.

25 products per preset, one generated file and 24 reports. Verified end to end
by changing one line of the generated header on purpose:

```
❌ pc-x86_64: differs from build/golden/pc-x86_64
  changed  generated_targets.cmake (+72 bytes, +1 lines, first differs at line 32)
  24 identical, 1 changed
```

The remaining sequence for the decomposition: point 46 is done, so no pinned
value has to travel with the code; capture a baseline, then decompose one piece
at a time with `verify` between steps. Point 46 was the first thing checked this
way, and it came out byte-identical.

---

## MetaMake findings

### 14. RISK — 22 `#MM` lines inside Make conditionals contribute unconditionally

MetaMake scans for `#MM` with a plain `strncmp` (`tools/MetaMake/dirnode.c:126`)
and never evaluates `ifeq`. Its variable reader ignores conditionals too
(`tools/MetaMake/project.c:116-145`). `workbench/devs/mmakefile.src:44`
documents this and works around it with a `#M%(...)` prefix trick inside a
genmf macro.

22 `#MM` lines in 5 mmakefiles sit inside conditionals today, among them
`arch/arm-native/exec` and `arch/aarch64-native/exec`. Every one of them
contributes in both branches. Anyone reading those files as conditional is
reading them wrong.

Variables in `#MM` names *are* substituted (`tools/MetaMake/cache.c:600`), but
only from the two files `mmake.config` lists as `globalvarfile`: `host.cfg` and
`target.cfg`. `config/make.cfg` is not one of them.

### 15. WORK — `AROS_DIR__TOOLS` is a typo

`images/IconSets/Gorilla/Icons/Small/AROS/Tools/mmakefile.src:26` writes
`$(AROS_DIR__TOOLS)` where line 23 has `$(AROS_DIR_TOOLS)`. An undefined Make
variable expands to nothing, so those icons install one directory too high.
Upstream candidate.

---

## Upstream contribution hygiene

### 16. WORK — the four `fix/*` branches are not upstreamable as they stand

`fix/ahci-posix-errno`, `fix/arosinquirea-kickstartbase-cast`,
`fix/exec-vlog-missing-exec-proto` and `fix/kernel-early-missing-stdbool` each
sit on `main`, seven commits over `master`, so a PR from any of them proposes
32 files and 3188 lines of build system next to a one-line fix. Three are
otherwise clean one-liners.

`fix/kernel-early-missing-stdbool` additionally rewrote
`arch/x86_64-pc/kernel/kernel_early.c` from CRLF to LF: 431 CRs removed,
+432/-431 for one added line.

Redo as `pr/<topic>` branched directly off `master`, which is the convention
`origin/pr/*` already follows.

### 17. WORK — `origin/pr/*` needs a pass

`pr/aarch64-startup64`, `pr/aarch64-darwin-cocoa`, `pr/crosstools-libcody-fix`
and `pr/rpi5-pcie0-nvme` are each 44 commits over `master` and carry unrelated
work; `pr/aarch64-startup64` is 63 files and +3203/-284 where only the tip
commit is the change. `pr/genet`, `pr/m68kemu` and `pr/mbedtls` are fully
contained in `master` and can be deleted.

### 18. WORK — `master` is 46 commits behind `upstream/master`

`git fetch upstream && git branch -f master upstream/master`.

### 19. WORK — the sancov fix is an upstream candidate

`8dec8d4547` stops building `sancov` and `sanstats`, because LLVM 11.0.0's
`sancov.cpp:514` does not compile against current libc++. That breaks
`make crosstools` on any current macOS host, not only the release lane, so it
is worth sending on.

### 20. RISK — `git remote` push URL for upstream is writable

`upstream` currently has a push URL pointing at
`aros-development-team/AROS`. `git remote set-url --push upstream no_push`.

---

## Stale records

### 21. RESOLVED — the stale dirty-tree handoff was replaced

The old handoff stated that the tree was intentionally dirty and built its
resume procedure around an overlay snapshot. That record was stale: the code
was committed, and isolation is useful because work is concurrent, not because
release inputs may be dirty.

`toolchains/HANDOFF.md` is now a current release handoff with the exact
commit/tree/recipe tuple, active clean build roots, completed gates and the
remaining matrix scope. `configure~` and Python `__pycache__` by-products have
been ignored since `13cd9faf62`.
