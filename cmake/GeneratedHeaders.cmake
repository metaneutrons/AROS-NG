# =============================================================================
# Hand-written generator rules from the mmakefiles
# =============================================================================
#
# The transpiler reports every Make rule that produces a header but cannot be
# expressed generically, because its recipe is arbitrary Make (see
# AROS_ADHOC_HEADERS_UNKNOWN). Those rules need a counterpart here. Each one
# below names the mmakefile line it stands for.
#
# Destinations follow the module's own USER_INCLUDES, so a source file's
# #include "..." resolves the way it does in the historic build.

set(_gen "${CMAKE_BINARY_DIR}/gen")
set_property(GLOBAL PROPERTY AROS_GENERATED_HEADER_DEPS "")

# _aros_needs_header(<target> <header>)
#
# Records that <target> cannot compile before <header> exists. Resolved after
# generated_targets.cmake has created the targets.
function(_aros_needs_header target header)
    get_property(_deps GLOBAL PROPERTY AROS_GENERATED_HEADER_DEPS)
    list(APPEND _deps "${target}|${header}")
    set_property(GLOBAL PROPERTY AROS_GENERATED_HEADER_DEPS "${_deps}")
endfunction()

# -----------------------------------------------------------------------------
# dos.library message strings
# -----------------------------------------------------------------------------
#
#   rom/dos/mmakefile.src:90  -> errorlist.h via genstrings.py
#   config/make.tmpl:3051     -> strings.h via %build_catalogs' default
#                                source="../strings.h"
#
# Both read rom/dos/catalogs/dos.cd, which lives in a git submodule. Without it
# checked out the rules are skipped; the submodule warning in CMakeLists.txt
# says what to do.
set(_dos_cd "${CMAKE_SOURCE_DIR}/rom/dos/catalogs/dos.cd")
if(EXISTS "${_dos_cd}")
    set(_dos_gen "${_gen}/rom/dos/dos")

    aros_catalog_header(
        CD "${_dos_cd}"
        SD "${CMAKE_SOURCE_DIR}/tools/flexcat/src/sd/C_h_aros.sd"
        OUTPUT "${_dos_gen}/strings.h")

    aros_script_header(
        SCRIPT "${CMAKE_SOURCE_DIR}/rom/dos/genstrings.py"
        INPUT "${_dos_cd}"
        OUTPUT "${_dos_gen}/errorlist.h")

    _aros_needs_header(kernel-dos "${_dos_gen}/strings.h")
    _aros_needs_header(kernel-dos "${_dos_gen}/errorlist.h")
else()
    message(STATUS
        "⏭️  rom/dos/catalogs/dos.cd absent (submodule not checked out); "
        "dos.library string tables not generated")
endif()

# -----------------------------------------------------------------------------
# Boot images
# -----------------------------------------------------------------------------
#
#   rom/dosboot/mmakefile.src:39    -> nomedia_image.h
#   rom/cgxbootpic/mmakefile.src:19 -> bootpic_image.h
#
# ilbmtoc emits chunky pixels by default and planar bitplanes with -p. The
# mmakefile picks planar for m68k only, since native Amiga hardware has a
# planar display and chunky-to-planar conversion on a 7 MHz 68000 is too slow.
if(AROS_TARGET_CPU STREQUAL "m68k")
    set(_ilbm_flags -p)
else()
    set(_ilbm_flags "")
endif()

aros_ilbm_header(
    ILBM "${CMAKE_SOURCE_DIR}/rom/dosboot/nomedia.ilbm"
    OUTPUT "${_gen}/rom/dosboot/dosboot/nomedia_image.h"
    FLAGS ${_ilbm_flags})
_aros_needs_header(kernel-dosboot "${_gen}/rom/dosboot/dosboot/nomedia_image.h")

# cgxbootpic asks for -I$(GENDIR)/$(CURDIR), without the extra segment.
aros_ilbm_header(
    ILBM "${CMAKE_SOURCE_DIR}/rom/cgxbootpic/bootpic.ilbm"
    OUTPUT "${_gen}/rom/cgxbootpic/bootpic_image.h")
_aros_needs_header(kernel-cgxbootpic "${_gen}/rom/cgxbootpic/bootpic_image.h")

# -----------------------------------------------------------------------------
# libraries/mui.h
# -----------------------------------------------------------------------------
#
# workbench/libs/muimaster/mmakefile.src:459-465. muimaster does not ship this
# header; it generates one from mui.h, macros.h and every class header. Missing,
# it was the largest single gap in the build: 215 compile failures plus the
# undeclared identifiers that follow.
#
# Generated at configure time rather than as a build step, the same way the SDK
# headers are bootstrapped. Every consumer includes it as <libraries/mui.h>, so
# it has to exist before the first compile; making several hundred targets
# depend on one custom command would express that far more expensively. The
# trade-off is the same one BootstrapSDK.cmake makes: editing a muimaster class
# header needs a re-configure.
set(_mui_header "${CMAKE_BINARY_DIR}/GENINCDIR/libraries/mui.h")
set(_mui_dir "${CMAKE_SOURCE_DIR}/workbench/libs/muimaster")
if(EXISTS "${_mui_dir}/buildincludes.c" AND NOT EXISTS "${_mui_header}")
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/GENINCDIR/libraries")
    set(_mui_tool "${AROS_HOST_TOOL_DIR}/buildincludes")
    execute_process(
        COMMAND "${AROS_HOST_CC}" -O2 -w "${_mui_dir}/buildincludes.c" -o "${_mui_tool}"
        RESULT_VARIABLE _mui_cc_res
        ERROR_VARIABLE _mui_cc_err)
    if(_mui_cc_res EQUAL 0)
        execute_process(
            COMMAND "${_mui_tool}"
            WORKING_DIRECTORY "${_mui_dir}"
            OUTPUT_FILE "${_mui_header}"
            RESULT_VARIABLE _mui_res
            ERROR_VARIABLE _mui_err)
        if(NOT _mui_res EQUAL 0)
            message(WARNING "buildincludes failed, libraries/mui.h not generated: ${_mui_err}")
        endif()
    else()
        message(WARNING "cannot build buildincludes: ${_mui_cc_err}")
    endif()
endif()
if(EXISTS "${_mui_header}")
    file(STRINGS "${_mui_header}" _mui_lines)
    list(LENGTH _mui_lines _n_mui)
    message(STATUS "🧵 AROS-NG: generated libraries/mui.h (${_n_mui} lines)")
endif()
