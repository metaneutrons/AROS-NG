# AROS-NG Core CMake Module (v0.1.0)
# Modern Multi-Platform Build System for AROS

include(CMakeParseArguments)
# The arch/ subdirectories this configuration may build from. Directory names
# there are <cpu>-<platform> with "all" as a wildcard, plus "native" as a
# pseudo-platform shared by every non-hosted target.
#
# A CPU also admits the ones it is backward compatible with, because AROS
# relies on that: compiler/include/asm/io.h forwards to <asm/i386/io.h> for
# __x86_64__ as well, and arch/x86_64-pc/boot lists kernel-pc-i386-serial and
# kernel-pc-i386-parallel among its BSP modules. Ordered least to most
# specific, since header staging copies in this order and the last write wins.
#
# The same set is used for header staging, the per-target gate, package
# declarations and genmodule's --arch-dirs, so they cannot drift apart.
set(AROS_ARCH_COMPATIBLE_CPUS "${AROS_TARGET_CPU}")
if(AROS_TARGET_CPU STREQUAL "x86_64")
    list(PREPEND AROS_ARCH_COMPATIBLE_CPUS "i386")
elseif(AROS_TARGET_CPU STREQUAL "aarch64")
    list(PREPEND AROS_ARCH_COMPATIBLE_CPUS "arm")
elseif(AROS_TARGET_CPU STREQUAL "riscv64")
    list(PREPEND AROS_ARCH_COMPATIBLE_CPUS "riscv")
endif()

set(AROS_ARCH_SOURCE_DIRS "all-native")
foreach(_cpu IN LISTS AROS_ARCH_COMPATIBLE_CPUS)
    list(APPEND AROS_ARCH_SOURCE_DIRS
        "${_cpu}-all"
        "${_cpu}-native"
        "all-${AROS_TARGET_PLATFORM}"
        "${_cpu}-${AROS_TARGET_PLATFORM}")
endforeach()
list(REMOVE_DUPLICATES AROS_ARCH_SOURCE_DIRS)

# Packages need the narrower set. Sources and headers may come from a
# compatible CPU, but a package belongs to exactly one architecture:
# arch/i386-pc and arch/x86_64-pc both declare $(AROSARCHDIR)/aros-bsp.pkg,
# and only one of them may write it.
set(AROS_ARCH_PACKAGE_DIRS
    "all-native"
    "${AROS_TARGET_CPU}-all"
    "${AROS_TARGET_CPU}-native"
    "all-${AROS_TARGET_PLATFORM}"
    "${AROS_TARGET_CPU}-${AROS_TARGET_PLATFORM}")
list(REMOVE_DUPLICATES AROS_ARCH_PACKAGE_DIRS)

include("${CMAKE_SOURCE_DIR}/cmake/BootstrapSDK.cmake")

# Target output directories
set(AROS_BUILD_DIR "${CMAKE_BINARY_DIR}")
set(AROS_LIBS_DIR "${AROS_BUILD_DIR}/SYS/Libs")
set(AROS_DEVS_DIR "${AROS_BUILD_DIR}/SYS/Devs")
set(AROS_C_DIR "${AROS_BUILD_DIR}/SYS/C")
set(AROS_CLASSES_DIR "${AROS_BUILD_DIR}/SYS/Classes")

file(MAKE_DIRECTORY "${AROS_LIBS_DIR}")
file(MAKE_DIRECTORY "${AROS_DEVS_DIR}")
file(MAKE_DIRECTORY "${AROS_C_DIR}")
file(MAKE_DIRECTORY "${AROS_CLASSES_DIR}")

# Bootstrap SDK Includes
aros_bootstrap_sdk_includes()

# Canonical AROS ELF Linker Rules using ld.lld
find_program(AROS_LLD_BIN ld.lld HINTS "$ENV{HOME}/.aros/toolchain/bin" "/opt/homebrew/bin" "/usr/bin")
if(AROS_LLD_BIN)
    set(CMAKE_C_LINK_EXECUTABLE "${AROS_LLD_BIN} -r <OBJECTS> -o <TARGET>")
    set(CMAKE_CXX_LINK_EXECUTABLE "${AROS_LLD_BIN} -r <OBJECTS> -o <TARGET>")
    set(CMAKE_C_CREATE_SHARED_MODULE "${AROS_LLD_BIN} -r <OBJECTS> -o <TARGET>")
    set(CMAKE_CXX_CREATE_SHARED_MODULE "${AROS_LLD_BIN} -r <OBJECTS> -o <TARGET>")
endif()

# Target architecture compilation options
if(AROS_TARGET_CPU STREQUAL "x86_64")
    add_compile_options(-target x86_64-unknown-elf)
elseif(AROS_TARGET_CPU STREQUAL "aarch64")
    add_compile_options(-target aarch64-unknown-elf)
elseif(AROS_TARGET_CPU STREQUAL "arm")
    # The legacy build takes the ISA flags from Autoconf (ISA_ARM_FLAGS), which
    # has no counterpart here, so clang fell back to its arm-none-eabi default.
    # That default predates ARMv7 and rejects the data barriers and other
    # instructions arch/arm-native uses.
    #
    # Fixed at ARMv7 (Pi 2 and later). The tree's raspi BSP is bcm2835, i.e.
    # Pi 1, whose ARMv6 core cannot run this code; covering it would need
    # per-BSP flags and three source sites reworked. Anything from Pi 3 on runs
    # the rpi-aarch64 target instead, so no supported board is lost.
    add_compile_options(-target arm-none-eabi -mcpu=cortex-a7 -mfpu=neon-vfpv4)
endif()

add_compile_definitions(
    __AROS__=1
    __AROS_VERSION__=1
)

# Build-date stamps. 52 mmakefiles put the current date into a define via
# $(shell date '+<fmt>'); the transpiler maps those two formats onto these
# variables. Evaluated once per configure rather than per compile, so a build
# is at least consistent within itself.
string(TIMESTAMP AROS_BUILD_DATE_DMY "%d.%m.%Y")
string(TIMESTAMP AROS_BUILD_DATE_ISO "%Y-%m-%d")

add_compile_options(
    -ffreestanding
    -fno-builtin
    -fno-strict-aliasing
    -fno-common
    -Wall
    -Wextra
    -Wno-unused-parameter
)

# The generated trees come first. The historic build has no -I into the source
# tree at all: compiler/include is staged into the SDK by %copy_includes, and
# genmodule then writes over what it supersedes, so the generated header is the
# one that gets found. Keeping compiler/include ahead of the SDK inverted that,
# and the hand-written clib/input_protos.h -- which predates genmodule and
# still declares PeekQualifier through AROS_LP0 -- shadowed the generated one.
include_directories(
    "${CMAKE_BINARY_DIR}/GENINCDIR"
    "${CMAKE_BINARY_DIR}/SDK/include"
    "${CMAKE_SOURCE_DIR}/compiler/include"
    "${CMAKE_SOURCE_DIR}/arch/all-native/include"
)

# =============================================================================
# SDK header staging
# =============================================================================
#
# Modules publish public headers via %copy_includes. The historic macro copies
# them into two include roots: the target SDK ($(AROS_INCLUDES)) and the host
# tool tree ($(GENINCDIR)). Headers referenced with a category prefix such as
# <oop/oop.h> or <hidd/hidd.h> can only be found this way, because the prefix
# is part of the #include and no search path supplies it.
#
# The transpiler turns each declaration into an aros_copy_includes() call; the
# glob is resolved here rather than in the transpiler, so adding a header needs
# no regeneration by hand.

set(AROS_SDK_INCLUDE_DIR "${CMAKE_BINARY_DIR}/SDK/include")
set(AROS_GENINC_DIR "${CMAKE_BINARY_DIR}/GENINCDIR")

# Counters so the configure output states what was staged.
set_property(GLOBAL PROPERTY AROS_STAGED_HEADERS 0)
set_property(GLOBAL PROPERTY AROS_STAGED_RULES_EMPTY 0)

# aros_copy_includes(DEST <subdir> SOURCE <src-relative dir> PATTERNS <globs...> [FLATTEN])
#
# FLATTEN mirrors the macro's $(notdir ...) behaviour, which applies when the
# declaration passes dir=. Without it the listed relative path is preserved.

# aros_arch_path_matches(<out-var> <path>)
#
# Whether a path under arch/ belongs to this configuration. A path outside
# arch/ is architecture-neutral and always matches.
#
# Used by everything that consumes a source location: header staging, the
# per-target gate and the package declarations. Without it the SDK ends up
# holding another architecture's headers, and which one wins depends on parse
# order: arch/m68k-amiga/include/asm/cpu.h replaced the x86_64 one, so every
# kernel source using rdmsri, wrcr or struct PML4E stopped compiling.
function(aros_arch_path_matches out_var path)
    # Works on the raw string: staging sources arrive relative to the source
    # tree, target directories absolute, and file(RELATIVE_PATH) rejects a
    # relative input.
    string(REPLACE "${CMAKE_SOURCE_DIR}/" "" _rel "${path}")
    if(NOT _rel MATCHES "^arch/([^/]+)")
        set(${out_var} TRUE PARENT_SCOPE)
        return()
    endif()
    if(CMAKE_MATCH_1 IN_LIST AROS_ARCH_SOURCE_DIRS)
        set(${out_var} TRUE PARENT_SCOPE)
    else()
        set(${out_var} FALSE PARENT_SCOPE)
    endif()
endfunction()

function(aros_copy_includes)
    set(options FLATTEN)
    set(oneValueArgs DEST SOURCE)
    set(multiValueArgs PATTERNS)
    cmake_parse_arguments(CI "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT CI_DEST OR NOT CI_SOURCE OR NOT CI_PATTERNS)
        return()
    endif()

    # Headers from another architecture must not reach the SDK: they land under
    # the same name as the right ones and whichever is copied last wins.
    aros_arch_path_matches(_arch_ok "${CI_SOURCE}")
    if(NOT _arch_ok)
        get_property(_skipped GLOBAL PROPERTY AROS_STAGING_FOREIGN_ARCH)
        list(APPEND _skipped "${CI_SOURCE} -> ${CI_DEST}")
        set_property(GLOBAL PROPERTY AROS_STAGING_FOREIGN_ARCH "${_skipped}")
        return()
    endif()

    # A source directory is normally relative to the source tree, but a module
    # may also stage headers out of a fetched port, which lives under the build
    # tree. Those arrive already absolute.
    if(IS_ABSOLUTE "${CI_SOURCE}")
        set(SRC_ABS "${CI_SOURCE}")
    else()
        set(SRC_ABS "${CMAKE_SOURCE_DIR}/${CI_SOURCE}")
    endif()
    if(NOT IS_DIRECTORY "${SRC_ABS}")
        # A port that has not been fetched yet; `ninja fetch-ports` provides it.
        return()
    endif()

    set(FOUND "")
    foreach(pat IN LISTS CI_PATTERNS)
        file(GLOB matches RELATIVE "${SRC_ABS}" "${SRC_ABS}/${pat}")
        list(APPEND FOUND ${matches})
    endforeach()
    if(NOT FOUND)
        get_property(n GLOBAL PROPERTY AROS_STAGED_RULES_EMPTY)
        math(EXPR n "${n} + 1")
        set_property(GLOBAL PROPERTY AROS_STAGED_RULES_EMPTY ${n})
        return()
    endif()
    list(REMOVE_DUPLICATES FOUND)

    get_property(count GLOBAL PROPERTY AROS_STAGED_HEADERS)
    foreach(rel IN LISTS FOUND)
        if(CI_FLATTEN)
            get_filename_component(name "${rel}" NAME)
        else()
            set(name "${rel}")
        endif()

        # configure_file(COPYONLY) copies only on change and registers the
        # source as a configure dependency, so editing a public header
        # re-stages it on the next build.
        foreach(root "${AROS_SDK_INCLUDE_DIR}" "${AROS_GENINC_DIR}")
            configure_file("${SRC_ABS}/${rel}" "${root}/${CI_DEST}/${name}" COPYONLY)
        endforeach()
        math(EXPR count "${count} + 1")
    endforeach()
    set_property(GLOBAL PROPERTY AROS_STAGED_HEADERS ${count})
endfunction()

# aros_stage_header(SOURCE <src-relative file> DEST <root-relative file>)
#
# Stages a single header, optionally under a different name. A handful of
# modules publish headers through a hand-written Make rule rather than
# %copy_includes; those rules are arbitrary Make and cannot be transpiled
# generically, so the ones that matter are listed explicitly below.
function(aros_stage_header)
    set(oneValueArgs SOURCE DEST)
    cmake_parse_arguments(SH "" "${oneValueArgs}" "" ${ARGN})
    if(NOT SH_SOURCE OR NOT SH_DEST)
        return()
    endif()
    set(src "${CMAKE_SOURCE_DIR}/${SH_SOURCE}")
    if(NOT EXISTS "${src}")
        return()
    endif()
    foreach(root "${AROS_SDK_INCLUDE_DIR}" "${AROS_GENINC_DIR}")
        configure_file("${src}" "${root}/${SH_DEST}" COPYONLY)
    endforeach()
    get_property(count GLOBAL PROPERTY AROS_STAGED_HEADERS)
    math(EXPR count "${count} + 1")
    set_property(GLOBAL PROPERTY AROS_STAGED_HEADERS ${count})
endfunction()

# --- Hand-written staging rules ---------------------------------------------
#
# Some mmakefiles stage headers with a plain Make rule targeting
# `$(AROS_INCLUDES)/...` instead of %copy_includes. Those recipes are arbitrary
# Make (renames, generator tools, pattern rules), so they get a static
# counterpart here. The transpiler detects every such rule in the tree and
# declares it via aros_adhoc_header_rule(); anything not listed as handled or
# deliberately out of scope below is reported at configure time, so a rule
# added upstream is noticed here and not as a missing header much later.

# Rules with a counterpart in this file. Keys are the rule's target path
# relative to the include root.
set(AROS_ADHOC_HEADERS_HANDLED
    "hidd/pci.h"
    "hidd/thunderbolt.h"
    # Counterparts in cmake/GeneratedHeaders.cmake.
    "$(CURDIR)/dos/errorlist.h"
    "$(CURDIR)/dosboot/nomedia_image.h"
    "$(CURDIR)/bootpic_image.h"
    # libraries/mui.h is generated there by buildincludes; these are the three
    # rules that build it, copy it into the SDK and create its directory.
    "libraries/mui.h"
    "libraries/mui.h $(AROS_INCLUDES)/libraries"
    "libraries $(AROS_INCLUDES)/libraries"
    # The BSD socket header tree, staged there as well.
    "%"
)

# Rules deliberately out of scope, with the reason. Same key format; a trailing
# "*" matches a prefix.
set(AROS_ADHOC_HEADERS_OUT_OF_SCOPE
    # Bootstrapped directly by BootstrapSDK.cmake from compiler/include.
    "%.h" "%.hpp" "exec/execbase.h"
    # Host-tool generated, and only for architectures we do not build.
    "aros/m68k/*" "aros/i386/*" "aros/%.h" "asm/%.h" "exec/%.h" "aros/$(CPU)/asm.h"
    # Directory-creation rule, not a header (compiler/include/mmakefile.src:177).
    "aros/$(CPU)"
    "clib/cia_protos.h" "defines/cia.h" "proto/cia.h"
    # Hosted ports only.
    "sigcore.h"
    # Third-party libraries, not part of a bootable kickstart.
    "zconf.h" "pnglibconf.h" "tiffconf.h" "tifftypes.h" "tiffinline.h"
    "freetype/*" "libraries"
    # A pattern rule whose destination is a directory category, not a file.
    "hidd/%.h"
    # Datatypes are not part of a bootable kickstart, and these three rules
    # only substitute a version number into a port's config header.
    "$(CURDIR)/libde265/de265-version.h"
    "$(CURDIR)/libheif/heif_version.h"
    "$(CURDIR)/src/webp/config.h"
    # softfloat is only built for targets without an FPU, none of which are
    # buildable yet; isapnp is x86 legacy and in no package.
    "$(CURDIR)/platform.h"
    "$(CURDIR)/version.h"
    # libtiff's config header, substituted from a template in the port.
    "$(CURDIR)/tif_config.h"
)

# Files whose rules are ignored wholesale, because the whole subtree is out of
# scope for a bootable target.
#
# workbench/libs/ used to be listed here and should not have been: it hid the
# rules for libraries/mui.h, which 215 compile failures depended on, and for
# reqtools.h with another 62. Ignoring a subtree wholesale silences exactly the
# reports this mechanism exists for.
set(AROS_ADHOC_HEADER_FILES_IGNORED
    "arch/.unmaintained/"
    "tools/"
)

set_property(GLOBAL PROPERTY AROS_ADHOC_HEADERS_UNKNOWN "")

# aros_adhoc_header_rule(FILE <mmakefile> LINE <n> ROOT <root> DEST <path>
#                        PREREQS <text>)
#
# Called from the generated target file for every hand-written header rule the
# transpiler found. Records the ones nobody has accounted for.
#
# ROOT is the generated root the target sits in. $(AROS_INCLUDES) and
# $(GENINCDIR) mean the header is staged into the SDK; $(GENDIR) means it is
# private to its own module. The allowlists below key on DEST alone, which
# stays unambiguous because a $(GENDIR) destination is always prefixed with
# $(CURDIR).
function(aros_adhoc_header_rule)
    set(oneValueArgs FILE LINE ROOT DEST PREREQS)
    cmake_parse_arguments(AR "" "${oneValueArgs}" "" ${ARGN})
    if(NOT AR_DEST)
        return()
    endif()

    foreach(prefix IN LISTS AROS_ADHOC_HEADER_FILES_IGNORED)
        if(AR_FILE MATCHES "^${prefix}")
            return()
        endif()
    endforeach()

    if(AR_DEST IN_LIST AROS_ADHOC_HEADERS_HANDLED)
        return()
    endif()

    foreach(pat IN LISTS AROS_ADHOC_HEADERS_OUT_OF_SCOPE)
        if(AR_DEST STREQUAL pat)
            return()
        endif()
        if(pat MATCHES "\\*$")
            string(REGEX REPLACE "\\*$" "" stem "${pat}")
            if(AR_DEST MATCHES "^${stem}")
                return()
            endif()
        endif()
    endforeach()

    get_property(unknown GLOBAL PROPERTY AROS_ADHOC_HEADERS_UNKNOWN)
    list(APPEND unknown
         "${AR_ROOT}${AR_DEST} <- ${AR_PREREQS}  (${AR_FILE}:${AR_LINE})")
    set_property(GLOBAL PROPERTY AROS_ADHOC_HEADERS_UNKNOWN "${unknown}")
endfunction()

# Counterparts for the handled rules above. Both rename on the way in.
#   rom/hidds/pci/mmakefile.src:17
aros_stage_header(SOURCE "rom/hidds/pci/include/pci_hidd.h" DEST "hidd/pci.h")
#   rom/hidds/thunderbolt/mmakefile.src:8
aros_stage_header(SOURCE "rom/hidds/thunderbolt/include/thunderbolt_hidd.h"
                  DEST "hidd/thunderbolt.h")

# =============================================================================
# Include path propagation
# =============================================================================
#
# The historic build feeds each module's USER_INCLUDES into its CFLAGS. The
# transpiler resolves those into an INCLUDES list, plus an ARCH_INCLUDES list of
# "<tag>|<path>" pairs coming from %set_archincludes declarations in the arch/
# tree. The tags that apply to this configuration are computed once here.
#
# AROS_TARGET_FAMILY groups related platforms (arch/all-<family>/...). For the
# bare-metal targets we build it equals the platform; hosted ports would use
# "unix" and are out of scope.
if(NOT DEFINED AROS_TARGET_FAMILY)
    set(AROS_TARGET_FAMILY "${AROS_TARGET_PLATFORM}")
endif()

# Tag forms used by %set_archincludes across the tree, most specific first:
# "<platform>-<cpu>", "<platform>", "<cpu>", then the bare-metal group "native".
set(AROS_ARCH_INCLUDE_TAGS
    "${AROS_TARGET_PLATFORM}-${AROS_TARGET_CPU}"
    "${AROS_TARGET_PLATFORM}"
    "${AROS_TARGET_CPU}"
    "native"
)


# aros_gate_arch(<target> <directory>)
#
# Keeps a target out of `all` when its sources live under an arch/ directory
# belonging to a different architecture. The transpiler is target-agnostic and
# emits every declaration it finds, so without this `ninja all` tries to build
# the PowerPC and Windows-hosted kernels against an x86 SDK. 45 objects failed
# that way, with errors that look like missing headers.
#
# Excluded rather than dropped: the target stays in the build graph and can be
# named explicitly, which is what makes it possible to check whether it would
# build at all.
function(aros_gate_arch target directory)
    if(NOT directory OR NOT TARGET ${target})
        return()
    endif()
    file(RELATIVE_PATH _rel "${CMAKE_SOURCE_DIR}" "${directory}")
    if(NOT _rel MATCHES "^arch/([^/]+)")
        return()
    endif()
    set(_arch_dir "${CMAKE_MATCH_1}")
    if(_arch_dir IN_LIST AROS_ARCH_SOURCE_DIRS)
        return()
    endif()
    set_target_properties(${target} PROPERTIES EXCLUDE_FROM_ALL TRUE)
    get_property(_n GLOBAL PROPERTY AROS_FOREIGN_ARCH_TARGETS)
    list(APPEND _n "${target} (arch/${_arch_dir})")
    set_property(GLOBAL PROPERTY AROS_FOREIGN_ARCH_TARGETS "${_n}")
endfunction()

# aros_apply_includes(<target> [MODULE_DIR <dir>] INCLUDES <dirs...>
#                     ARCH_INCLUDES <tag|dir...>)
#
# Adds the include directories the transpiler resolved. Non-existent
# directories are dropped: an unmapped Make variable or a stale path then shows
# up as a missing header rather than as a confusing CMake include entry.
#
# MODULE_DIR is the module's own source directory. config/make.tmpl:31 passes it
# to every compile, and modules rely on it: a `##begin cdefprivate` block
# typically does `#include "<mod>_intern.h"`, and that block ends up in
# <mod>_libdefs.h under the SDK, from where the private header is only reachable
# through the search path.
function(aros_apply_includes target_name)
    set(oneValueArgs MODULE_DIR)
    set(multiValueArgs INCLUDES ARCH_INCLUDES)
    cmake_parse_arguments(INC "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # A header name can exist at several levels, and the first match wins, so
    # order matters:
    #
    #   1. the module's generated tree (its private <mod>_libdefs.h)
    #   2. ARCH_INCLUDES from %set_archincludes
    #   3. INCLUDES, i.e. the mmakefile's USER_INCLUDES
    #   4. MODULE_DIR last
    #
    # Step 2 precedes step 3 because that is where the reference puts it:
    # rom/exec writes
    #   PRIV_EXEC_INCLUDES = $(TARGET_EXEC_INCLUDES) -I$(SRCDIR)/rom/exec ...
    # with the architecture variable first, and the transpiler emits that
    # variable separately as ARCH_INCLUDES, losing its position in the list.
    # With rom/exec first, rom/exec/exec_platform.h would shadow
    # arch/all-pc/exec/exec_platform.h and the kernel headers it pulls in would
    # never be reached.
    #
    # MODULE_DIR is only the implicit fallback that lets `#include "x_intern.h"`
    # resolve; the reference build passes it as an -iquote path, which does not
    # take part in `<...>` lookup at all. Putting it first would let
    # rom/timer/timer_platform.h shadow arch/all-pc/timer/timer_platform.h,
    # and the platform struct would come out missing its fields.
    set(GEN_DIRS "")
    set(ARCH_DIRS "")
    set(GENERIC_DIRS "")
    set(FALLBACK_DIRS "")

    if(INC_MODULE_DIR AND IS_DIRECTORY "${INC_MODULE_DIR}")
        file(RELATIVE_PATH _rel "${CMAKE_SOURCE_DIR}" "${INC_MODULE_DIR}")
        if(_rel AND NOT _rel MATCHES "^\\.\\.")
            set(_gen "${CMAKE_BINARY_DIR}/gen/${_rel}")
            if(IS_DIRECTORY "${_gen}")
                list(APPEND GEN_DIRS "${_gen}")
            endif()
        endif()
        list(APPEND FALLBACK_DIRS "${INC_MODULE_DIR}")
    endif()

    foreach(d IN LISTS INC_INCLUDES)
        # A path inside the build tree holds generated files, so it may not
        # exist yet at configure time: rom/dos asks for
        # -I$(GENDIR)/$(CURDIR)/dos, which only appears once its catalog
        # headers are built. Create it and keep it. Source-tree paths are still
        # checked, so a stale USER_INCLUDES does not add a dead -I.
        string(FIND "${d}" "${CMAKE_BINARY_DIR}" _in_build)
        if(_in_build EQUAL 0)
            file(MAKE_DIRECTORY "${d}")
            list(APPEND GENERIC_DIRS "${d}")
        elseif(IS_DIRECTORY "${d}")
            list(APPEND GENERIC_DIRS "${d}")
        endif()
    endforeach()

    foreach(pair IN LISTS INC_ARCH_INCLUDES)
        # Split "<tag>|<path>"; a path may not contain "|".
        string(FIND "${pair}" "|" sep)
        if(sep LESS 0)
            continue()
        endif()
        string(SUBSTRING "${pair}" 0 ${sep} tag)
        math(EXPR rest "${sep} + 1")
        string(SUBSTRING "${pair}" ${rest} -1 path)

        if(NOT tag IN_LIST AROS_ARCH_INCLUDE_TAGS)
            continue()
        endif()
        if(IS_DIRECTORY "${path}")
            list(APPEND ARCH_DIRS "${path}")
        endif()
    endforeach()

    set(DIRS ${GEN_DIRS} ${ARCH_DIRS} ${GENERIC_DIRS} ${FALLBACK_DIRS})

    if(DIRS)
        list(REMOVE_DUPLICATES DIRS)
        target_include_directories(${target_name} PRIVATE ${DIRS})
    endif()

    # A generated header can share its name with a system header: rom/dos
    # generates strings.h, and the SDK also stages the POSIX strings.h. The
    # historic build has no conflict, because %build_catalogs writes the
    # generated one next to the sources, where `#include "strings.h"` finds it
    # before any -I path.
    #
    # -iquote reproduces that without writing into the source tree: it applies
    # only to the quoted form and is searched ahead of every -I, so `<strings.h>`
    # still reaches the POSIX header.
    #
    # The order has to be the same as for -I, ARCH_DIRS included. Leaving them
    # out put every -iquote path ahead of every architecture path, so
    # `#include "kernel_debug.h"` in arch/x86_64-pc/kernel resolved to
    # rom/kernel's header instead of arch/all-pc's, and __cli went missing.
    set(QUOTE_DIRS ${GEN_DIRS} ${ARCH_DIRS} ${GENERIC_DIRS} ${FALLBACK_DIRS})
    if(QUOTE_DIRS)
        list(REMOVE_DUPLICATES QUOTE_DIRS)
        foreach(d IN LISTS QUOTE_DIRS)
            target_compile_options(${target_name} PRIVATE "-iquote${d}")
        endforeach()
    endif()
endfunction()

# aros_apply_flags(<target> DEFINES <d...> UNDEFINES <u...> COMPILE_OPTIONS <o...>)
#
# Applies the preprocessor state the transpiler resolved from USER_CPPFLAGS and
# USER_CFLAGS. Modules depend on these for semantics: rom/devs/ahci declares the
# method-base fields of its library base only under
# `#if defined(__OOP_NOMETHODBASES__)`, so the define decides whether the module
# compiles at all.
#
# Only simple defines and an allowlisted set of codegen options arrive here;
# warning bundles and shell-built defines are reported by the transpiler and
# deliberately not passed on.
function(aros_apply_flags target_name)
    set(multiValueArgs DEFINES UNDEFINES COMPILE_OPTIONS
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(FL "" "" "${multiValueArgs}" ${ARGN})

    # Architecture-conditional flags come from an `arch/.../make.opts` pulled in
    # with `-include`. arch/all-pc/timer/make.opts sets -DUSE_VBLANK_EMU, which
    # is what makes rom/timer/timer_intern.h declare tb_vblank_timerequest.
    set(_arch_defines "")
    foreach(pair IN LISTS FL_ARCH_DEFINES)
        string(FIND "${pair}" "|" sep)
        if(sep LESS 0)
            continue()
        endif()
        string(SUBSTRING "${pair}" 0 ${sep} tag)
        math(EXPR rest "${sep} + 1")
        string(SUBSTRING "${pair}" ${rest} -1 value)
        if(tag IN_LIST AROS_ARCH_INCLUDE_TAGS)
            list(APPEND _arch_defines "${value}")
        endif()
    endforeach()
    if(_arch_defines)
        list(REMOVE_DUPLICATES _arch_defines)
        target_compile_definitions(${target_name} PRIVATE ${_arch_defines})
    endif()

    set(_arch_opts "")
    foreach(pair IN LISTS FL_ARCH_COMPILE_OPTIONS)
        string(FIND "${pair}" "|" sep)
        if(sep LESS 0)
            continue()
        endif()
        string(SUBSTRING "${pair}" 0 ${sep} tag)
        math(EXPR rest "${sep} + 1")
        string(SUBSTRING "${pair}" ${rest} -1 value)
        if(tag IN_LIST AROS_ARCH_INCLUDE_TAGS)
            list(APPEND _arch_opts "${value}")
        endif()
    endforeach()
    if(_arch_opts)
        list(REMOVE_DUPLICATES _arch_opts)
        target_compile_options(${target_name} PRIVATE ${_arch_opts})
    endif()

    if(FL_DEFINES)
        target_compile_definitions(${target_name} PRIVATE ${FL_DEFINES})
    endif()
    foreach(u IN LISTS FL_UNDEFINES)
        target_compile_options(${target_name} PRIVATE "-U${u}")
    endforeach()
    if(FL_COMPILE_OPTIONS)
        target_compile_options(${target_name} PRIVATE ${FL_COMPILE_OPTIONS})
    endif()
endfunction()

# Helper to filter CMake keyword collisions in link libraries
function(aros_link_libraries target_name)
    set(CLEAN_LIBS "")
    foreach(lib ${ARGN})
        if(lib STREQUAL "debug" OR lib STREQUAL "optimized" OR lib STREQUAL "general")
            # Avoid CMake build-type keywords
        elseif(TARGET ${lib})
            list(APPEND CLEAN_LIBS "${lib}")
        endif()
    endforeach()
    if(CLEAN_LIBS)
        target_link_libraries(${target_name} PRIVATE ${CLEAN_LIBS})
    endif()
endfunction()

# Helper to resolve source files with or without extensions (.c, .cpp, .S)
function(aros_resolve_sources out_var dir)
    set(RESOLVED "")
    foreach(src ${ARGN})
        if(EXISTS "${dir}/${src}")
            list(APPEND RESOLVED "${dir}/${src}")
        elseif(EXISTS "${dir}/${src}.c")
            list(APPEND RESOLVED "${dir}/${src}.c")
        elseif(EXISTS "${dir}/${src}.cpp")
            list(APPEND RESOLVED "${dir}/${src}.cpp")
        elseif(EXISTS "${dir}/${src}.S")
            list(APPEND RESOLVED "${dir}/${src}.S")
        elseif(EXISTS "${dir}/${src}.s")
            list(APPEND RESOLVED "${dir}/${src}.s")
        endif()
    endforeach()
    set(${out_var} "${RESOLVED}" PARENT_SCOPE)
endfunction()

# =============================================================================
# Third-party source fetching
# =============================================================================
#
# Some modules build against sources that are not in the tree; ACPICA is the one
# that matters here, since libraries/acpica.h pulls headers out of the unpacked
# archive. The transpiler turns each %fetch declaration into an
# aros_fetch_archive() call.
#
# Downloading is delegated to the tree's own scripts/fetch.sh, which already
# handles the origin flavours in use (plain mirrors, GNU, SourceForge, GitHub and
# a local cache://). These targets are deliberately NOT part of `all`: fetching
# reaches out to the network, so it stays an explicit step.
#
#   ninja fetch-ports          # everything
#   ninja acpica-fetch         # one archive

set(AROS_PORTS_DIR "${CMAKE_BINARY_DIR}/Ports"
    CACHE PATH "Where fetched third-party sources are unpacked")
set(AROS_PORTS_SOURCE_DIR "${CMAKE_BINARY_DIR}/portssources"
    CACHE PATH "Where downloaded third-party archives are kept")

find_program(AROS_FETCH_SCRIPT fetch.sh
    HINTS "${CMAKE_SOURCE_DIR}/scripts" NO_DEFAULT_PATH)

set_property(GLOBAL PROPERTY AROS_FETCH_TARGETS "")

# aros_fetch_archive(NAME <t> ARCHIVE <a> SUFFIXES <s> ORIGINS <o>
#                    LOCATION <l> DESTINATION <d>
#                    PATCH_ORIGINS <po> PATCHES <p>)
#
# Declares a fetch target. The recipe mirrors the %fetch macro's invocation of
# scripts/fetch.sh, including the `.<archive>-fetched` stamp that marks a
# completed download.
function(aros_fetch_archive)
    set(oneValueArgs NAME ARCHIVE SUFFIXES ORIGINS LOCATION DESTINATION
        PATCH_ORIGINS PATCHES)
    cmake_parse_arguments(FA "" "${oneValueArgs}" "" ${ARGN})

    if(NOT FA_NAME OR NOT FA_ARCHIVE)
        return()
    endif()
    if(NOT AROS_FETCH_SCRIPT)
        return()
    endif()
    if(TARGET ${FA_NAME})
        return()
    endif()

    # The macro falls back to the unpack directory when no location is given.
    set(_loc "${FA_LOCATION}")
    if(NOT _loc)
        set(_loc "${FA_DESTINATION}")
    endif()
    set(_stamp "${_loc}/.${FA_ARCHIVE}-fetched")

    add_custom_command(
        OUTPUT "${_stamp}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${_loc}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${FA_DESTINATION}"
        COMMAND "${AROS_FETCH_SCRIPT}"
                -ao "${FA_ORIGINS}"
                -a "${FA_ARCHIVE}"
                -s "${FA_SUFFIXES}"
                -l "${_loc}"
                -d "${FA_DESTINATION}"
                -po "${FA_PATCH_ORIGINS}"
                -p "${FA_PATCHES}"
        COMMAND ${CMAKE_COMMAND} -E touch "${_stamp}"
        COMMENT "🌐 Fetching ${FA_ARCHIVE}"
        VERBATIM
    )
    add_custom_target(${FA_NAME} DEPENDS "${_stamp}")

    get_property(_all GLOBAL PROPERTY AROS_FETCH_TARGETS)
    list(APPEND _all "${FA_NAME}")
    set_property(GLOBAL PROPERTY AROS_FETCH_TARGETS "${_all}")
endfunction()

# aros_mark_preprocessed_asm(<sources...>)
#
# AROS assembly sources use preprocessor directives regardless of case, e.g.
# arch/x86_64-all/exec/execstubs.s opens with `#define PUSH ...`. CMake hands
# `.s` to the assembler without running the preprocessor, so those files must
# be compiled as `assembler-with-cpp` explicitly. `.S` already implies it.
function(aros_mark_preprocessed_asm)
    foreach(src ${ARGN})
        if(src MATCHES "\\.s$")
            set_source_files_properties("${src}" PROPERTIES
                LANGUAGE ASM
                COMPILE_OPTIONS "-x;assembler-with-cpp"
            )
        endif()
    endforeach()
endfunction()

# aros_resolve_arch_sources(<out_sources> <out_dropped> <module_dir>
#                           SOURCES <names...> ARCH_SOURCES <tag|dir|files...>)
#
# Applies architecture-specific source overrides. For every declaration whose
# tag applies to this target, the named files are taken from the architecture
# directory and the same-named generic sources are dropped.
#
# This mirrors config/make.tmpl:1661, where the generic list is filtered against
# the architecture object names. Overriding by base name is what lets
# arch/x86_64-all/exec/stackswap.S replace rom/exec/stackswap.c, whose generic
# body is only an `#error`.
function(aros_resolve_arch_sources out_sources out_dropped module_dir)
    set(multiValueArgs SOURCES ARCH_SOURCES)
    cmake_parse_arguments(AS "" "" "${multiValueArgs}" ${ARGN})

    set(OVERRIDE_NAMES "")
    set(ARCH_FILES "")
    set(CLAIMED_NAMES "")

    # Two architecture directories can declare the same file, and both tags can
    # apply: for raspi-aarch64, arch/aarch64-all/exec (arch=aarch64) and
    # arch/aarch64-native/exec (arch=raspi-aarch64) both provide cachecleare and
    # preparecontext. Taking both yields duplicate symbols at link time.
    #
    # Walk the tags most specific first -- that is the order
    # AROS_ARCH_INCLUDE_TAGS is built in -- and let the first declaration to
    # claim a base name keep it.
    foreach(want_tag IN LISTS AROS_ARCH_INCLUDE_TAGS)
        foreach(entry IN LISTS AS_ARCH_SOURCES)
            # "<tag>|<dir>|<f1>,<f2>,..."
            string(REPLACE "|" ";" parts "${entry}")
            list(LENGTH parts n)
            if(NOT n EQUAL 3)
                continue()
            endif()
            list(GET parts 0 tag)
            list(GET parts 1 dir)
            list(GET parts 2 names)

            if(NOT tag STREQUAL want_tag)
                continue()
            endif()

            set(abs_dir "${CMAKE_SOURCE_DIR}/${dir}")
            if(NOT IS_DIRECTORY "${abs_dir}")
                continue()
            endif()

            string(REPLACE "," ";" name_list "${names}")
            foreach(nm IN LISTS name_list)
                # Record the name regardless of whether the file resolves: a
                # declared override means the generic version is not wanted.
                list(APPEND OVERRIDE_NAMES "${nm}")
                if(nm IN_LIST CLAIMED_NAMES)
                    continue()
                endif()
                list(APPEND CLAIMED_NAMES "${nm}")
                aros_resolve_sources(RESOLVED "${abs_dir}" "${nm}")
                foreach(f IN LISTS RESOLVED)
                    list(APPEND ARCH_FILES "${f}")
                endforeach()
            endforeach()
        endforeach()
    endforeach()

    if(NOT OVERRIDE_NAMES)
        set(${out_sources} "" PARENT_SCOPE)
        set(${out_dropped} "" PARENT_SCOPE)
        return()
    endif()
    list(REMOVE_DUPLICATES OVERRIDE_NAMES)

    set(KEPT "")
    set(DROPPED "")
    foreach(src IN LISTS AS_SOURCES)
        get_filename_component(base "${src}" NAME_WE)
        if(base IN_LIST OVERRIDE_NAMES)
            list(APPEND DROPPED "${base}")
        else()
            list(APPEND KEPT "${src}")
        endif()
    endforeach()

    # Architecture objects come first in the link, as in the reference build.
    set(${out_sources} "${ARCH_FILES};${KEPT}" PARENT_SCOPE)
    set(${out_dropped} "${DROPPED}" PARENT_SCOPE)
endfunction()

# Macro: aros_add_library
function(aros_add_library)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    if(RESOLVED_SOURCES)
        add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
        target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
            LC_LIBDEFS_FILE="${ARG_TARGET}_libdefs.h"
            __AROS_LIBNAME__=${ARG_TARGET}
            __AROS_MODNAME__=${ARG_TARGET}
        )
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            OUTPUT_NAME "${ARG_MMAKE_ID}.library"
            RUNTIME_OUTPUT_DIRECTORY "${AROS_LIBS_DIR}"
            LINKER_LANGUAGE C
        )
        aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
        aros_apply_includes(${ARG_MMAKE_ID}
            MODULE_DIR "${ARG_DIRECTORY}"
            INCLUDES ${ARG_INCLUDES}
            ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
        )
        aros_apply_flags(${ARG_MMAKE_ID}
            DEFINES ${ARG_DEFINES}
            UNDEFINES ${ARG_UNDEFINES}
            COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
            ARCH_DEFINES ${ARG_ARCH_DEFINES}
            ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
        )
        if(ARG_LIBS)
            aros_link_libraries(${ARG_MMAKE_ID} ${ARG_LIBS})
        endif()
    endif()
endfunction()

# Macro: aros_add_device
function(aros_add_device)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    if(RESOLVED_SOURCES)
        add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
        target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
            LC_LIBDEFS_FILE="${ARG_TARGET}_libdefs.h"
            __AROS_DEVNAME__=${ARG_TARGET}
            __AROS_MODNAME__=${ARG_TARGET}
        )
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            OUTPUT_NAME "${ARG_MMAKE_ID}.device"
            RUNTIME_OUTPUT_DIRECTORY "${AROS_DEVS_DIR}"
            LINKER_LANGUAGE C
        )
        aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
        aros_apply_includes(${ARG_MMAKE_ID}
            MODULE_DIR "${ARG_DIRECTORY}"
            INCLUDES ${ARG_INCLUDES}
            ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
        )
        aros_apply_flags(${ARG_MMAKE_ID}
            DEFINES ${ARG_DEFINES}
            UNDEFINES ${ARG_UNDEFINES}
            COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
            ARCH_DEFINES ${ARG_ARCH_DEFINES}
            ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
        )
        if(ARG_LIBS)
            aros_link_libraries(${ARG_MMAKE_ID} ${ARG_LIBS})
        endif()
    endif()
endfunction()

# Macro: aros_add_resource
function(aros_add_resource)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    if(RESOLVED_SOURCES)
        add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
        target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
            LC_LIBDEFS_FILE="${ARG_TARGET}_libdefs.h"
            __AROS_RESNAME__=${ARG_TARGET}
            __AROS_MODNAME__=${ARG_TARGET}
        )
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            OUTPUT_NAME "${ARG_MMAKE_ID}.resource"
            RUNTIME_OUTPUT_DIRECTORY "${AROS_LIBS_DIR}"
            LINKER_LANGUAGE C
        )
        aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
        aros_apply_includes(${ARG_MMAKE_ID}
            MODULE_DIR "${ARG_DIRECTORY}"
            INCLUDES ${ARG_INCLUDES}
            ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
        )
        aros_apply_flags(${ARG_MMAKE_ID}
            DEFINES ${ARG_DEFINES}
            UNDEFINES ${ARG_UNDEFINES}
            COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
            ARCH_DEFINES ${ARG_ARCH_DEFINES}
            ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
        )
        if(ARG_LIBS)
            aros_link_libraries(${ARG_MMAKE_ID} ${ARG_LIBS})
        endif()
    endif()
endfunction()

# Macro: aros_add_hidd
function(aros_add_hidd)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    if(RESOLVED_SOURCES)
        add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
        target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
            LC_LIBDEFS_FILE="${ARG_TARGET}_libdefs.h"
            __AROS_HIDDNAME__=${ARG_TARGET}
            __AROS_MODNAME__=${ARG_TARGET}
        )
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            OUTPUT_NAME "${ARG_MMAKE_ID}.hidd"
            RUNTIME_OUTPUT_DIRECTORY "${AROS_CLASSES_DIR}"
            LINKER_LANGUAGE C
        )
        aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
        aros_apply_includes(${ARG_MMAKE_ID}
            MODULE_DIR "${ARG_DIRECTORY}"
            INCLUDES ${ARG_INCLUDES}
            ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
        )
        aros_apply_flags(${ARG_MMAKE_ID}
            DEFINES ${ARG_DEFINES}
            UNDEFINES ${ARG_UNDEFINES}
            COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
            ARCH_DEFINES ${ARG_ARCH_DEFINES}
            ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
        )
        if(ARG_LIBS)
            aros_link_libraries(${ARG_MMAKE_ID} ${ARG_LIBS})
        endif()
    endif()
endfunction()

# Macro: aros_add_datatype
function(aros_add_datatype)
    aros_add_library(${ARGN})
endfunction()

# Macro: aros_add_gadget
function(aros_add_gadget)
    aros_add_library(${ARGN})
endfunction()

# Macro: aros_add_mcc
function(aros_add_mcc)
    aros_add_library(${ARGN})
endfunction()

# Macro: aros_add_linklib
function(aros_add_linklib)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    if(RESOLVED_SOURCES)
        add_library(${ARG_MMAKE_ID} STATIC ${RESOLVED_SOURCES})
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            LINKER_LANGUAGE C
        )
        aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
        aros_apply_includes(${ARG_MMAKE_ID}
            MODULE_DIR "${ARG_DIRECTORY}"
            INCLUDES ${ARG_INCLUDES}
            ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
        )
        aros_apply_flags(${ARG_MMAKE_ID}
            DEFINES ${ARG_DEFINES}
            UNDEFINES ${ARG_UNDEFINES}
            COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
            ARCH_DEFINES ${ARG_ARCH_DEFINES}
            ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
        )
    endif()
endfunction()

# Macro: aros_add_program
function(aros_add_program)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    if(RESOLVED_SOURCES)
        add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
        target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
            LC_LIBDEFS_FILE="${ARG_TARGET}_libdefs.h"
            __AROS_PROGNAME__=${ARG_TARGET}
            __AROS_MODNAME__=${ARG_TARGET}
        )
        aros_program_output_dir(_prog_outdir "${ARG_DIRECTORY}")
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            # progname, not the mmake id: the reference installs
            # aros-tcpip-apps-syslog as SysLog. The per-directory output
            # location mirrors targetdir="$(AROSDIR)/$(CURDIR)"; a flat one
            # collides, since two mmakefiles both build `testboot`.
            OUTPUT_NAME "${ARG_TARGET}"
            RUNTIME_OUTPUT_DIRECTORY "${_prog_outdir}"
            LINKER_LANGUAGE C
        )
        aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
        aros_apply_includes(${ARG_MMAKE_ID}
            MODULE_DIR "${ARG_DIRECTORY}"
            INCLUDES ${ARG_INCLUDES}
            ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
        )
        aros_apply_flags(${ARG_MMAKE_ID}
            DEFINES ${ARG_DEFINES}
            UNDEFINES ${ARG_UNDEFINES}
            COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
            ARCH_DEFINES ${ARG_ARCH_DEFINES}
            ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
        )
        if(ARG_LIBS)
            aros_link_libraries(${ARG_MMAKE_ID} ${ARG_LIBS})
        endif()
    endif()
endfunction()

# aros_add_custom_target(TARGET <name> MMAKE_ID <id> MODTYPE <type> ...)
#
# A module whose modtype the transpiler has no dedicated variant for. This was
# an empty stub, and 97 declarations with 313 source files routed into it:
# every filesystem handler, 30 USB classes, 40 Zune/MUI classes, 9 Reaction
# classes. No output and no report, which is why kernel-package-base could not
# find kernel-fs-con or kernel-fs-ram and kernel-package-fs was missing four of
# its five members.
#
# In the reference, modtype decides only the file suffix and the install
# directory (config/make.tmpl:2048-2095); the compilation is identical to
# modtype=library. So this builds like aros_add_library and differs only in
# where the result lands.
function(aros_add_custom_target)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY MODTYPE)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    # Install location per modtype, from make.tmpl:2048-2095.
    set(_moddir "${AROS_LIBS_DIR}")
    if(ARG_MODTYPE STREQUAL "handler")
        set(_moddir "${AROS_BUILD_DIR}/SYS/L")
    elseif(ARG_MODTYPE STREQUAL "mui" OR ARG_MODTYPE STREQUAL "mcc"
           OR ARG_MODTYPE STREQUAL "mcp")
        set(_moddir "${AROS_CLASSES_DIR}/Zune")
    elseif(ARG_MODTYPE STREQUAL "usbclass")
        set(_moddir "${AROS_CLASSES_DIR}/USB")
    elseif(ARG_MODTYPE STREQUAL "btclass")
        set(_moddir "${AROS_CLASSES_DIR}/Bluetooth")
    elseif(ARG_MODTYPE STREQUAL "image" OR ARG_MODTYPE STREQUAL "class")
        set(_moddir "${AROS_CLASSES_DIR}")
    elseif(ARG_MODTYPE STREQUAL "hook")
        set(_moddir "${AROS_BUILD_DIR}/SYS/Resources")
    endif()

    # A handler is named <name>-handler, everything else <name>.<modtype>; the
    # package declarations spell both out (make.tmpl:3745-3750). The mmake id
    # rather than the module name, as every module builder here does, since two
    # declarations can share a modname.
    if(ARG_MODTYPE STREQUAL "handler")
        set(_outname "${ARG_MMAKE_ID}-handler")
    elseif(ARG_MODTYPE)
        set(_outname "${ARG_MMAKE_ID}.${ARG_MODTYPE}")
    else()
        set(_outname "${ARG_MMAKE_ID}.library")
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    if(NOT RESOLVED_SOURCES)
        return()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
    target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
        LC_LIBDEFS_FILE="${ARG_TARGET}_libdefs.h"
        __AROS_MODNAME__=${ARG_TARGET}
    )
    set_target_properties(${ARG_MMAKE_ID} PROPERTIES
        OUTPUT_NAME "${_outname}"
        RUNTIME_OUTPUT_DIRECTORY "${_moddir}"
        LINKER_LANGUAGE C
    )
    aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
    aros_apply_includes(${ARG_MMAKE_ID}
        MODULE_DIR "${ARG_DIRECTORY}"
        INCLUDES ${ARG_INCLUDES}
        ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
    )
    aros_apply_flags(${ARG_MMAKE_ID}
        DEFINES ${ARG_DEFINES}
        UNDEFINES ${ARG_UNDEFINES}
        COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
        ARCH_DEFINES ${ARG_ARCH_DEFINES}
        ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
    )
    if(ARG_LIBS)
        aros_link_libraries(${ARG_MMAKE_ID} ${ARG_LIBS})
    endif()
endfunction()

# =============================================================================
# Bootable Image & Distribution Targets
# =============================================================================
find_program(MKISOFS_BIN mkisofs HINTS "/opt/homebrew/bin" "/usr/bin" "/usr/local/bin")
find_program(HDIUTIL_BIN hdiutil HINTS "/usr/bin")

set(AROS_BOOT_ISO "${CMAKE_BINARY_DIR}/aros-${AROS_TARGET_CPU}-${AROS_TARGET_PLATFORM}.iso")

if(MKISOFS_BIN)
    add_custom_target(boot-iso
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/SYS/S"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_SOURCE_DIR}/workbench/s/Startup-Sequence" "${CMAKE_BINARY_DIR}/SYS/S/Startup-Sequence"
        COMMAND ${MKISOFS_BIN} -o "${AROS_BOOT_ISO}"
                -V "AROS Live CD"
                -p "The AROS Dev Team"
                -iso-level 4 -l -J -r
                "${CMAKE_BINARY_DIR}/SYS"
        DEPENDS workbench-c
        COMMENT "💿 Packaging AROS-NG Bootable ISO Disk Image -> ${AROS_BOOT_ISO}"
    )
elseif(HDIUTIL_BIN)
    add_custom_target(boot-iso
        COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/SYS/S"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different "${CMAKE_SOURCE_DIR}/workbench/s/Startup-Sequence" "${CMAKE_BINARY_DIR}/SYS/S/Startup-Sequence"
        COMMAND ${HDIUTIL_BIN} makehybrid -iso -joliet -o "${AROS_BOOT_ISO}" "${CMAKE_BINARY_DIR}/SYS"
        DEPENDS workbench-c
        COMMENT "💿 Packaging AROS-NG Bootable ISO Disk Image via hdiutil -> ${AROS_BOOT_ISO}"
    )
endif()

# =============================================================================
# Kickstart Packages (PKG containers)
# =============================================================================
#
# The 32-bit bootstrap (arch/all-pc/bootstrap/bootstrap.c, AddModule) accepts a
# Multiboot module in one of three shapes: a bare relocatable ELF, an ar(1)
# archive, or a PKG container. PKG is what the boot configuration in
# arch/x86_64-pc/boot/modules.default lists, and aros-romtool builds it.
#
# Note on naming: upstream's /boot/pc/kernel is NOT a PKG. config/make.tmpl
# builds it with %link_kickstart, which links kernel_resource.o + exec + task
# into a single relocatable ELF. That first module supplies the kickstart entry
# point, because elfloader.c takes the first executable section of the first
# module it sees (see `need_entry` in bootstrap/elfloader.c). Only the driver
# and library collections (aros-bsp, aros-acpi, aros-base, aros-fs, poseidon)
# are PKG containers. Load order therefore matters: the kernel ELF must come
# first, packages after it.

find_program(AROS_ROMTOOL_BIN aros-romtool
    HINTS "${CMAKE_SOURCE_DIR}/tools/aros-tools/target/release"
          "${CMAKE_SOURCE_DIR}/tools/aros-tools/target/debug"
    NO_DEFAULT_PATH
)

set(AROS_BOOT_DIR "${AROS_BUILD_DIR}/boot")
set(AROS_BOOT_ARCH_DIR "${AROS_BOOT_DIR}/${AROS_TARGET_PLATFORM}")

# aros_make_package(NAME <target> OUTPUT <file> MODULES <targets...>)
#
# Packs the build products of the given CMake targets into a PKG container, in
# the order given. Targets that do not exist in this configuration are skipped
# and reported, so a partial module tree still produces a usable package rather
# than a configure-time error.

# aros_package_arch_matches(<arch-dir>)
#
# Whether a package declared under arch/<arch-dir> belongs to this
# configuration. Same rule as AROS_ARCH_SOURCE_DIRS: three architectures
# declare $(AROSARCHDIR)/aros-bsp.pkg, and all three render to the same path,
# so only one of them may build it.
function(aros_package_arch_matches out_var arch_dir)
    if(NOT arch_dir)
        set(${out_var} TRUE PARENT_SCOPE)
        return()
    endif()
    if(arch_dir IN_LIST AROS_ARCH_PACKAGE_DIRS)
        set(${out_var} TRUE PARENT_SCOPE)
    else()
        set(${out_var} FALSE PARENT_SCOPE)
    endif()
endfunction()

function(aros_make_package)
    set(oneValueArgs NAME OUTPUT ARCH)
    set(multiValueArgs MODULES)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    aros_package_arch_matches(_arch_ok "${ARG_ARCH}")
    if(NOT _arch_ok)
        return()
    endif()

    if(NOT ARG_NAME OR NOT ARG_OUTPUT)
        message(FATAL_ERROR "aros_make_package: NAME and OUTPUT are required")
    endif()

    if(NOT AROS_ROMTOOL_BIN)
        message(STATUS "📦 ${ARG_NAME}: skipped, aros-romtool not built yet")
        return()
    endif()

    # Only targets that actually produce a file can be packaged. Meta-targets
    # created by the transpiler for #MM rules are UTILITY targets and have no
    # TARGET_FILE, so they are reported as not configured rather than breaking
    # the generate step.
    set(PRESENT "")
    set(MISSING "")
    foreach(mod IN LISTS ARG_MODULES)
        set(has_file FALSE)
        if(TARGET ${mod})
            get_target_property(mod_type ${mod} TYPE)
            if(mod_type STREQUAL "EXECUTABLE"
               OR mod_type STREQUAL "STATIC_LIBRARY"
               OR mod_type STREQUAL "SHARED_LIBRARY"
               OR mod_type STREQUAL "MODULE_LIBRARY")
                set(has_file TRUE)
            endif()
        endif()
        if(has_file)
            list(APPEND PRESENT ${mod})
        else()
            list(APPEND MISSING ${mod})
        endif()
    endforeach()

    if(NOT PRESENT)
        message(STATUS "📦 ${ARG_NAME}: skipped, none of its modules are configured")
        return()
    endif()

    # Report what is not in the package, so an incomplete kickstart is visible
    # at configure time instead of failing mysteriously at boot.
    if(MISSING)
        list(LENGTH MISSING n_missing)
        list(LENGTH PRESENT n_present)
        message(STATUS
            "📦 ${ARG_NAME}: ${n_present} module(s) packaged, ${n_missing} not configured: ${MISSING}")
    endif()

    set(MODULE_FILES "")
    foreach(mod IN LISTS PRESENT)
        list(APPEND MODULE_FILES "$<TARGET_FILE:${mod}>")
    endforeach()

    get_filename_component(OUT_DIR "${ARG_OUTPUT}" DIRECTORY)

    add_custom_command(
        OUTPUT "${ARG_OUTPUT}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${OUT_DIR}"
        COMMAND "${AROS_ROMTOOL_BIN}" pkg create --basename
                -o "${ARG_OUTPUT}" ${MODULE_FILES}
        DEPENDS ${PRESENT}
        COMMENT "📦 Packing kickstart package ${ARG_NAME}"
        VERBATIM
        COMMAND_EXPAND_LISTS
    )

    # The mmake name is usually also a metatarget from the #MM rules, so a
    # target under that name may already exist. Attach to it rather than
    # declaring a second one.
    if(TARGET ${ARG_NAME})
        add_custom_target(${ARG_NAME}-file DEPENDS "${ARG_OUTPUT}")
        add_dependencies(${ARG_NAME} ${ARG_NAME}-file)
    else()
        add_custom_target(${ARG_NAME} DEPENDS "${ARG_OUTPUT}")
    endif()

    get_property(_pkgs GLOBAL PROPERTY AROS_PACKAGE_TARGETS)
    list(APPEND _pkgs ${ARG_NAME})
    set_property(GLOBAL PROPERTY AROS_PACKAGE_TARGETS "${_pkgs}")
endfunction()

# The kickstart aggregate lives in cmake/Kickstart.cmake, which is
# included from CMakeLists.txt AFTER generated_targets.cmake, because
# aros_make_package() needs the module targets to already exist.

# aros_program_output_dir(<out-var> <source-directory>)
#
# Programs go into a directory mirroring their source location, which is what
# targetdir="$(AROSDIR)/$(CURDIR)" does in the reference. A single flat
# directory does not work: two %build_progs groups both build a program called
# `version`, and ninja refuses two rules writing the same output.
function(aros_program_output_dir out_var directory)
    file(RELATIVE_PATH _rel "${CMAKE_SOURCE_DIR}" "${directory}")
    if(NOT _rel OR _rel MATCHES "^\\.\\.")
        set(${out_var} "${AROS_C_DIR}" PARENT_SCOPE)
    else()
        set(${out_var} "${AROS_C_DIR}/${_rel}" PARENT_SCOPE)
    endif()
endfunction()

# =============================================================================
# The remaining link kinds
# =============================================================================

# aros_add_programs(MMAKE_ID <id> DIRECTORY <dir> SOURCES <file>... ...)
#
# %build_progs: one executable per source file, all under a single mmake name
# (make.tmpl:1850). %build_prog, by contrast, links one executable from all its
# sources. Both were previously treated as the second case, which produced one
# binary where the tree wants several.
#
# Each file gets its own CMake target, named "<mmake-id>-<stem>" so the ids stay
# unique, with the plain stem as the output name. A phony target under the mmake
# id ties them together, which is what the historic build's metatarget does.
function(aros_add_programs)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    set(_members "")
    foreach(src IN LISTS ARG_SOURCES)
        aros_resolve_sources(_resolved "${ARG_DIRECTORY}" "${src}")
        if(NOT _resolved)
            continue()
        endif()
        get_filename_component(_stem "${src}" NAME_WE)
        set(_tgt "${ARG_MMAKE_ID}-${_stem}")
        if(TARGET ${_tgt})
            continue()
        endif()

        aros_mark_preprocessed_asm(${_resolved})
        add_executable(${_tgt} ${_resolved})
        aros_program_output_dir(_outdir "${ARG_DIRECTORY}")
        set_target_properties(${_tgt} PROPERTIES
            OUTPUT_NAME "${_stem}"
            RUNTIME_OUTPUT_DIRECTORY "${_outdir}"
            LINKER_LANGUAGE C
        )
        aros_gate_arch(${_tgt} "${ARG_DIRECTORY}")
        aros_apply_includes(${_tgt}
            MODULE_DIR "${ARG_DIRECTORY}"
            INCLUDES ${ARG_INCLUDES}
            ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
        )
        aros_apply_flags(${_tgt}
            DEFINES ${ARG_DEFINES}
            UNDEFINES ${ARG_UNDEFINES}
            COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
            ARCH_DEFINES ${ARG_ARCH_DEFINES}
            ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
        )
        if(ARG_LIBS)
            aros_link_libraries(${_tgt} ${ARG_LIBS})
        endif()
        list(APPEND _members ${_tgt})
    endforeach()

    if(_members AND NOT TARGET ${ARG_MMAKE_ID})
        add_custom_target(${ARG_MMAKE_ID} DEPENDS ${_members})
    endif()
endfunction()

# aros_add_module_simple(TARGET <name> MODTYPE <type> ...)
#
# %build_module_simple links a module without the genmodule chain: no .conf, so
# no generated libdefs header and no LC_LIBDEFS_FILE. Defining it anyway would
# point the module at a header that is never generated.
#
# The extension follows modtype, which is a required argument there. The 28
# declarations in the tree use mcc, resource, library, mcp, hook and printer.
function(aros_add_module_simple)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY MODTYPE)
    set(multiValueArgs SOURCES LIBS USELIBS INCLUDES ARCH_INCLUDES
        DEFINES UNDEFINES COMPILE_OPTIONS ARCH_SOURCES
        ARCH_DEFINES ARCH_COMPILE_OPTIONS)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    aros_resolve_sources(RESOLVED_SOURCES "${ARG_DIRECTORY}" ${ARG_SOURCES})
    if(ARG_ARCH_SOURCES)
        aros_resolve_arch_sources(_ARCH_RESOLVED _ARCH_DROPPED "${ARG_DIRECTORY}"
            SOURCES ${RESOLVED_SOURCES}
            ARCH_SOURCES ${ARG_ARCH_SOURCES}
        )
        if(_ARCH_RESOLVED)
            set(RESOLVED_SOURCES "${_ARCH_RESOLVED}")
            list(REMOVE_ITEM RESOLVED_SOURCES "")
        endif()
    endif()
    if(NOT RESOLVED_SOURCES)
        return()
    endif()
    aros_mark_preprocessed_asm(${RESOLVED_SOURCES})

    set(_ext "${ARG_MODTYPE}")
    if(NOT _ext)
        set(_ext "library")
    endif()

    add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
    target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
        __AROS_MODNAME__=${ARG_TARGET}
    )
    set_target_properties(${ARG_MMAKE_ID} PROPERTIES
        # Named after the mmake id, as every other module builder here does:
        # two declarations can share a modname (usbromstartup appears twice)
        # and would then write the same file.
        OUTPUT_NAME "${ARG_MMAKE_ID}.${_ext}"
        RUNTIME_OUTPUT_DIRECTORY "${AROS_LIBS_DIR}"
        LINKER_LANGUAGE C
    )
    aros_gate_arch(${ARG_MMAKE_ID} "${ARG_DIRECTORY}")
    aros_apply_includes(${ARG_MMAKE_ID}
        MODULE_DIR "${ARG_DIRECTORY}"
        INCLUDES ${ARG_INCLUDES}
        ARCH_INCLUDES ${ARG_ARCH_INCLUDES}
    )
    aros_apply_flags(${ARG_MMAKE_ID}
        DEFINES ${ARG_DEFINES}
        UNDEFINES ${ARG_UNDEFINES}
        COMPILE_OPTIONS ${ARG_COMPILE_OPTIONS}
        ARCH_DEFINES ${ARG_ARCH_DEFINES}
        ARCH_COMPILE_OPTIONS ${ARG_ARCH_COMPILE_OPTIONS}
    )
    if(ARG_LIBS)
        aros_link_libraries(${ARG_MMAKE_ID} ${ARG_LIBS})
    endif()
endfunction()

# aros_link_kickstart(NAME <id> OUTPUT <file> MODULES <target>... [USELIBS <l>...])
#
# %link_kickstart, from config/make.tmpl:3850. A few modules cannot be loaded
# from a package: the bootstrap takes its entry point from the first executable
# section of the first module it sees (arch/all-pc/bootstrap/elfloader.c:662),
# so kernel, exec and task are linked into one relocatable ELF that the
# bootstrap loads directly.
#
# MODULES arrives in declaration order with the startup module first, which is
# the order the reference links them in and the reason the entry point lands
# where the bootstrap expects it.
function(aros_link_kickstart)
    set(oneValueArgs NAME OUTPUT ARCH)
    set(multiValueArgs MODULES USELIBS)
    cmake_parse_arguments(ARG "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    aros_package_arch_matches(_arch_ok "${ARG_ARCH}")
    if(NOT _arch_ok)
        return()
    endif()

    if(NOT ARG_NAME OR NOT ARG_OUTPUT OR NOT ARG_MODULES)
        return()
    endif()

    set(PRESENT "")
    set(MISSING "")
    foreach(mod IN LISTS ARG_MODULES)
        set(has_file FALSE)
        if(TARGET ${mod})
            get_target_property(mod_type ${mod} TYPE)
            if(mod_type STREQUAL "EXECUTABLE" OR mod_type STREQUAL "STATIC_LIBRARY")
                set(has_file TRUE)
            endif()
        endif()
        if(has_file)
            list(APPEND PRESENT ${mod})
        else()
            list(APPEND MISSING ${mod})
        endif()
    endforeach()

    if(MISSING)
        # A kickstart missing a module links but does not boot, so say so now.
        message(WARNING
            "🧩 ${ARG_NAME}: cannot link, module(s) not configured: ${MISSING}")
        return()
    endif()

    set(_objs "")
    foreach(mod IN LISTS PRESENT)
        list(APPEND _objs "$<TARGET_FILE:${mod}>")
    endforeach()

    set(_libs "")
    foreach(l IN LISTS ARG_USELIBS)
        list(APPEND _libs "-l${l}")
    endforeach()

    get_filename_component(_dir "${ARG_OUTPUT}" DIRECTORY)

    # Linked with lld directly, as every module target here is: the reference
    # passes -Wl,-Ur, but that is a GNU-ld option and driving clang would hand
    # the job to the host linker, which rejects it. -r does what is needed,
    # keeping the output relocatable so the bootstrap can load it, and the
    # modules are already relocatable objects.
    add_custom_command(
        OUTPUT "${ARG_OUTPUT}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${_dir}"
        COMMAND "${AROS_LLD_BIN}" -r
                -o "${ARG_OUTPUT}" ${_objs} ${_libs}
        DEPENDS ${PRESENT}
        COMMENT "Kickstart ${ARG_NAME} -> ${ARG_OUTPUT}"
        VERBATIM
        COMMAND_EXPAND_LISTS)

    # The mmake name is usually also a metatarget from the #MM rules, so a
    # target under that name may already exist. Attach to it rather than
    # declaring a second one.
    if(TARGET ${ARG_NAME})
        add_custom_target(${ARG_NAME}-file DEPENDS "${ARG_OUTPUT}")
        add_dependencies(${ARG_NAME} ${ARG_NAME}-file)
    else()
        add_custom_target(${ARG_NAME} DEPENDS "${ARG_OUTPUT}")
    endif()

    get_property(_ks GLOBAL PROPERTY AROS_KICKSTART_TARGETS)
    list(APPEND _ks ${ARG_NAME})
    set_property(GLOBAL PROPERTY AROS_KICKSTART_TARGETS "${_ks}")
endfunction()
