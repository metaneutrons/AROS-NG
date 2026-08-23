# Open points

Status date: 2026-08-23. Everything here is either undecided, unfinished, or a
finding nobody has acted on yet. Each entry names the evidence, so none of it
has to be rediscovered.

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

### 2. RISK — genmodule is run while it is still being written

A lane failed with `Bus error: 10` on
`gen/compiler/crt/stdc/stdc/include/.stdc.library-includes`. genmodule run by
hand with the same arguments succeeds, and the log shows genmodule's own
sources (`functionhead.c`, `muisupport.c`, `writefd.c`, `writelinkentries.c`)
being compiled immediately before. Under `-j 8` the recipe executes a
partially written binary.

The tree-wide `includes` used to act as a barrier that hid this. Whether the
ordinary build has another barrier is unchecked, so this may affect
`make crosstools -j` as well.

### 3. WORK — the non-release include form is untested

`compiler/include/mmakefile.src` now offers `sdk-includes-0` and
`sdk-includes-1`. Only the release form has been exercised; this tree is
configured with `--enable-toolchain-release`. `sdk-includes-0` is a faithful
copy of what the three call sites had, except that `compiler/atomic` and
`compiler/libinit` now also name `includes-copy`, which `includes` already
implied through `includes-generate-deps`.

### 4. WORK — the collector is not releasable

Untouched from `toolchains/HANDOFF.md`. The four-item design there still
stands, and the diagnosis is confirmed:

- `tools/collect-aros/env.h.in` `_CROSS_` bakes in absolute producer paths:
  `LD_NAME "@aros_toolchain_ld@"`, `STRIP_NAME`/`NM_NAME`/`OBJDUMP_NAME` as
  `@AROS_CROSSTOOLSDIR@/@aros_target_cpu@-aros-*`. The `_STANDALONE_` branch
  uses bare names, so PATH resolution.
- `OBJLIBDIR` is compiled in via `-DOBJLIBDIR="$(AROS_LIB)"`
  (`tools/collect-aros/mmakefile:24` and `:34`), used at
  `backend-generic.c:139,140,154,155` and `backend-bfd.c:130,131,144,145`.
- `misc.c:52` `set_compiler_path()` prepends `COMPILER_PATH` to `PATH`.
- No runtime self-location anywhere: no `/proc/self/exe`, no
  `_NSGetExecutablePath`.
- `producer.py` never mentions `collect-aros`, so no collector is packaged,
  which is consistent with the intent. `cmake/AROS.cmake:246` documents the
  deliberate bypass.

Until this is done, the release prefix promises the locked CMake partial-link
contract and not arbitrary standalone linking through `clang`/`clang++`.

### 5. WORK — the Linux lane and the reproducibility matrix

The `linux-x86_64` lane has not been run; it needs the other machine. The
complete v1 matrix requires each host/profile pair built twice and
byte-compared before publication, which has not started.

### 6. DECIDE — job count for the byte-comparison

Lanes here ran with `--jobs 8`, where `toolchains/HANDOFF.md` uses 2. The
producer sets `SOURCE_DATE_EPOCH`, `ZERO_AR_DATE` and the prefix maps itself,
so the job count should not affect the output, but that has not been verified
by comparing two runs at different parallelism.

---

## The path to a graphical boot

A full CMake build of pc-x86_64 on 2026-08-23 after the Boost staging fix:
16378 of 16611 steps completed, 887 steps failed, 1496 errors.

### 37. WORK — 94 declared sources resolve to no file

`aros_resolve_sources` used to drop a missing in-tree source with a bare
`continue`, so a target quietly built with fewer objects than its declaration
names. Now reported in `generated_targets.missing-sources.txt`, and there are 94.

Two are worth naming. `linklibs-udis86`'s generated `itab` was one, which is why
the failure showed up as a missing *header* one step away from the cause; that
one is closed. The largest group is the reaction classes, each dropping
`DEFAULT_MODTYPE` and `gadget`: `DEFAULT_MODTYPE` is an unexpanded Make variable
reaching a source list, so something in the variable handling is passing a name
through instead of a value. That is a defect, not a missing file, and it is worth
reading before the other 90.

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

### 38. WORK — the audit's 42 modules are the boot's work list

With `aros-base.pkg` loading, the boot stops here:

```
[ELF Loader] Undefined symbol 'con_LibName'
con-handler: Relocation error in section 3!
Failed to load the kickstart
*** SYSTEM PANIC!!! ***
```

`con_LibName` is a genmodule symbol, and `kernel-fs-con-handler` is one of the 42
modules the symbol audit lists with an undefined symbol
(`symbol-audit/by-module.txt`, `by-symbol.txt` calls it `no-provider`). So the
audit is no longer an abstract measure of build completeness: because the ELF
loader refuses a whole boot over one unresolved symbol, that list of 42 is
exactly the list of things standing between here and a boot that reaches
dos.library.

That reframes what to do next. Rather than chase one symbol per boot attempt,
read `symbol-audit/by-symbol.txt` for the shapes: how many of the 42 are a
genmodule symbol like this one, how many a missing link library like point 27h's,
and how many a real absence. The first two are systematic.

### 34. WORK — collect-aros adds inputs the first pass turns out to need

`collect_extra` (`tools/collect-aros/backend-generic.c:117`) reads the first
pass's symbols and adds `OBJLIBDIR`-relative inputs to the second: the C++
pure-virtual object when `__cxa_pure_virtual` is left weak, and `libpthread.a`
when a `pthread_*` symbol is left undefined -- libgcc's emulated TLS pulls those
in and they are in no auto-linked set, so they never reach the command line.

Not ported with point 32. Whether it matters here is measurable rather than
arguable: the symbol audit already lists what our links leave undefined, so the
question is whether `__cxa_pure_virtual` or a `pthread_*` is among them.

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

Two of collect-aros's other jobs are not ported: points 33 and 34.

### 22. WORK — ACPICA is a fetched Port that kernel-kernel needs

    GENINCDIR/libraries/acpica.h:47:10:
        fatal error: 'acpica/actypes.h' file not found

Three `arch/all-pc/kernel` sources need it, so `kernel-kernel` does not build
without it. Same class of problem as Boost in point 1, and the same three
routes apply. This is now the only thing between the three boot fixes and a
building kernel.

### 23. WORK — compiler-posixc, 179 failed steps from one cause, location unfound

All of them come from include order, not from missing headers. The 28 posixc
headers are staged correctly. The problem is that
`SDK/include/aros/stdc` precedes `SDK/include/aros/posixc` on the include path,
so a bare `<limits.h>`, `<errno.h>` or `<sys/types.h>` resolves to the C99
variant and the POSIX superset is shadowed. That is why `PASS_MAX`, `PATH_MAX`,
`off_t`, `__off64_t`, `EBADF`, `EISDIR` and `locale_t` all read as undeclared.

`aros/posixc/limits.h` opens with `#include <aros/stdc/limits.h>` and adds the
POSIX names, so the chain works from the SDK root alone and `aros/stdc` does
not need to be on the search path at all.

Verified by taking one `-I` off one command:

    the command from compile_commands.json for compiler/crt/posixc/__fseeko.c
    minus -I<build>/SDK/include/aros/stdc      ->  0 errors
    unchanged                                  ->  3 errors

What has not been found is what puts it there, and the search so far excludes
the obvious places. Removing all five code sites in `cmake/AROS.cmake` that
name `aros/stdc` leaves it first on the path; the transpiled declaration for
`compiler-posixc` does not mention it; `AhiBuild.cmake`, `ConfigureBuild.cmake`
and `BootstrapSDK.cmake` name it only for their own subsystems. The remaining
candidate is an INTERFACE include directory arriving through
`USELIBS stdc_rel stdcio_rel`, which is untested.

The AROS.cmake edits were reverted because they changed nothing measurable.

### 23b. WORK — three original guesses at the posixc cause, for the record

    __posixc_intbase.h:55:21   undeclared identifier 'PASS_MAX'     65
    __stdio.h:38:37            unknown type name 'off_t'            24
    aros/posixc/dirent.h:52:20 undeclared identifier 'PATH_MAX'     11

Plus single instances of `EBADF`, `locale_t` and an implicit `wcwidth`. The
shape says a small number of missing header sets rather than 179 problems.
posixc is a core link library, so this is on the boot path.

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

### 26d. WORK — the two Ports source globs, and why they are not a quick fix

`freetype2.library` (200 undefined) and `acpica.library` (108) are the two
modules still missing their own implementation, and both for the same reason:
their source lists come from `$(wildcard $(PORTSDIR)/.../*.c)`, which the
transpiler drops. The error text used to say "deferred to CMake", which is
wrong and misled me; nothing expands it.

An opaque marker handed to CMake does not work either, because the glob result
feeds further Make functions in the same expression (`:%.c=%`, `filter-out`,
`addprefix`), which only the transpiler's evaluator can apply. So the glob has
to be resolved during transpilation, against the build tree.

That is the real blocker, and it is ordering, not evaluation: the globs cover
Ports content a build step fetches, and the source list is needed at configure
time. Any fix has to decide one of

  * fetch at configure time, or
  * let the fetch trigger a reconfigure, so the second configure sees the files.

Reported in `generated_targets.partial-source-lists.txt`.

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

### 27g. PARTLY RESOLVED — the alert is gone; the MemList walk still faults

Two of the three findings below are settled by point 32. `cpu_Init` runs, so
`KernelBase->kb_ContextSize` is set, `KrnCreateContext` returns a context and
`Exec_init` no longer takes `goto execfatal`. And the trap handlers install, so
the #GP is delivered and reported by `core_IRQHandle` rather than escalating
through a missing IDT gate -- confirming that the absent gate for vector 13 was
the same cause, not a defect of its own.

What is left is the fault itself, unchanged and still unexplained: `FindMem`
dereferences a MemList successor holding `48 8b 8a 70 04 30 00 48`, x86 code
rather than a node. It now repeats about 150 times from supervisor mode before a
double fault ends the run, because the panic path keeps calling `TypeOfMem`.
Reading it needs guest memory, which the runner cannot do yet (point 31).

The original entry follows.

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

### 29. WORK — the release producers count as target obligations

`fc2aac81b2` declares `crosstools-libunwind-release`,
`crosstools-compiler-rt-release` and `crosstools-compiler-rt32-release` beside
their non-release siblings. All six provision the host compiler this build
consumes, but only the three originals are in
`LLVM_PROVISIONING_DECLARATIONS`, so the three `-release` ones are counted in
the target inventory as things the target tree owes.

Either they belong in the provisioning list, which is a statement that the
release lane is part of the same boundary, or the inventory is right and the
boundary is narrower than the lane. A decision, not a defect.

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

### 30. WRONG — `aros-cli test` reports a verified boot it never looked at

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

### 31. WORK — make the boot a deterministic, asserting check in `aros-cli`

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

### 7. DECIDE — a pinned digest of a live file sits in Rust source

The three red tests are green as of `71a6d046f1`, and what they turned out to
be hiding is the reason this point stays open. `LLVM_PROVISIONING_MMAKE_SHA256`
at `aros-verify/src/main.rs:269` is a semantic digest of
`tools/crosstools/llvm/mmakefile.src`, and every deliberate change to that file
makes the suite red until someone re-pins by hand. Worse, the digest assertion
runs first, so while it was red the eight inventory counts behind it were never
evaluated at all: they had been wrong by 71 or 72 for as long as the digest was
stale, and nothing said so.

Two lessons for whatever replaces this:

  * the value does not belong in a `.rs` constant; the refactor plan's own
    principle 4 says as much, and this is the coupling that blocks the
    refactor, see point 13;
  * a gate must not be able to mask another gate. Independent facts belong in
    independent tests, so a stale pin costs one red test rather than every
    assertion after it.

`toolchains/HANDOFF.md`'s five-check gate still does not include
`cargo test -p aros-verify`, which is how a red suite passed for a green state.

### 8. WORK — three clippy deny-level errors

    error: using tabs in doc comments      crates/aros-transpiler/src/flexcat.rs:9
    error: very complex type used          crates/aros-transpiler/src/flexcat.rs:273
    error: useless use of `format!`        crates/aros-transpiler/src/parser.rs:2953

`cargo clippy --workspace --all-targets` does not compile until these are
fixed. Roughly 44 further warn-level lints exist; the workspace sets
`clippy::all = deny` with `pedantic`, `nursery` and `cargo` at warn.

### 9. WORK — three clippy warnings are false positives

`suspicious_operation_groupings` at `parser.rs:3870`, `:4051` and `:5040`
suggests `expected_flags.include_dirs`. The field really is `includes`
(`parser.rs:3296`), so the suggestion would not compile. These need an
`#[allow]` with a reason, and any task worded "resolve all clippy warnings"
has to say so, because the code sits in comparisons the parity tests use.

---

## Transpiler and parity

### 10. DECIDE — should the toolchain's own build be transpiled?

Whole-tree coverage is 1178/1195, architecture-scoped 1067/1076. Of the nine
missing in the x86_64-pc scope, seven are `crosstools-*` from
`tools/crosstools/llvm/mmakefile.src` and the other two are `grub` and
`tools-crosstools-gcc-libatomic`. The producer covers that ground by a
different route, so whether these should become CMake targets at all is an
open question, and it has to be answered before "zero missing targets" can be
a gate.

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

### 13. WORK — the golden-output harness

The precondition is met: the transpiler is deterministic. Three runs on an
unchanged tree gave 3 133 008 bytes with the same sha256, and all 19 report
files were byte-identical. `aros-transpiler` takes no target arguments, so one
golden `generated_targets.cmake` covers all presets and the per-preset
variation lives in the CMake step and the verify reports.

Not built yet. Until it exists, "without altering a single byte of generated
CMake output" is an intention rather than a gate.

Sequence that follows from point 7: fix the gates first, then capture the
baseline, then decompose.

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

### 21. WRONG — `toolchains/HANDOFF.md` assumes a dirty working tree

Its opening states the tree is intentionally dirty and must not be cleaned,
and its resume sequence builds a snapshot-and-overlay procedure on that. The
tree is committed. The snapshot step is still worth doing for isolation from
concurrent work, but not for the reason given.

The `configure~` and `__pycache__` by-products that step 3 works around are
ignored as of `13cd9faf62`.
