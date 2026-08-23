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

### 27c. WORK — the kickstart fails to load on one weak undefined symbol

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

### 27. WORK — no reproducible boot attempt exists

No QEMU runner in the tree, and no boot has been attempted. `boot-iso` exists
as a target and packages `${CMAKE_BINARY_DIR}/SYS`, but `grub` is one of the
nine untranspiled `%build_with_configure` declarations from point 10, so the
image has no loader yet.

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

### 7. DECIDE — a pinned digest of a live file sits in Rust source

`aros-verify` fails 3 of its 22 tests, all with "the audited LLVM provisioning
context drifted": `llvm_provisioning_contract_mutations_fail_closed`,
`llvm_provisioning_context_is_semantically_fingerprinted`,
`current_architecture_denominators_are_pinned`.

`LLVM_PROVISIONING_MMAKE_SHA256` at `aros-verify/src/main.rs:269` is a semantic
digest of `tools/crosstools/llvm/mmakefile.src`. That file changed twice on
2026-08-23 alone. The drift predates those changes: reverting the file to
`7560a51df1` leaves the same three tests red.

This is the coupling that blocks the refactor, see point 13. Whatever replaces
it, the value does not belong in a `.rs` constant; the refactor plan's own
principle 4 says as much.

Note also that `toolchains/HANDOFF.md`'s five-check gate does not include
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
