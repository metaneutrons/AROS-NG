# =============================================================================
# Host tools
# =============================================================================
#
# Some headers are produced by programs that have to run on the build machine:
# flexcat turns a catalog description into #defines, ilbmtoc turns an IFF image
# into a C array. The historic build expects both in $(TOOLDIR) and never says
# who puts them there (config/make.cfg.in:177 for FLEXCAT), so they are built
# here.
#
# They cannot be plain add_executable() targets. This build cross-compiles:
# add_compile_options() has already put -target <cpu>-unknown-elf and
# -ffreestanding on everything in this directory scope, and a host tool needs
# neither. add_custom_command invokes the compiler directly and so inherits
# none of it.

set(AROS_HOST_CC "cc" CACHE STRING "C compiler for tools that run on the build machine")
set(AROS_HOST_TOOL_DIR "${CMAKE_BINARY_DIR}/hosttools")
file(MAKE_DIRECTORY "${AROS_HOST_TOOL_DIR}")

# aros_host_tool(NAME <name> SOURCES <file>... [DEFINES <d>...]
#                [INCLUDES <dir>...] [LIBS <l>...])
#
# Builds one host executable in a single compiler call and exports its path as
# AROS_HOST_<NAME> in the caller's scope. Recompiles when a source changes;
# header changes are not tracked, which is acceptable for vendored tools that
# do not change between builds.
function(aros_host_tool)
    set(oneValueArgs NAME)
    set(multiValueArgs SOURCES DEFINES INCLUDES LIBS)
    cmake_parse_arguments(HT "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT HT_NAME OR NOT HT_SOURCES)
        message(FATAL_ERROR "aros_host_tool: NAME and SOURCES are required")
    endif()

    set(_exe "${AROS_HOST_TOOL_DIR}/${HT_NAME}")

    set(_flags "")
    foreach(d IN LISTS HT_DEFINES)
        list(APPEND _flags "-D${d}")
    endforeach()
    foreach(i IN LISTS HT_INCLUDES)
        list(APPEND _flags "-I${i}")
    endforeach()
    set(_libs "")
    foreach(l IN LISTS HT_LIBS)
        list(APPEND _libs "-l${l}")
    endforeach()

    add_custom_command(
        OUTPUT "${_exe}"
        COMMAND "${AROS_HOST_CC}" -O2 -w ${_flags} ${HT_SOURCES} ${_libs} -o "${_exe}"
        DEPENDS ${HT_SOURCES}
        COMMENT "Building host tool ${HT_NAME}"
        VERBATIM)

    string(TOUPPER "${HT_NAME}" _upper)
    set(AROS_HOST_${_upper} "${_exe}" PARENT_SCOPE)
endfunction()

# -----------------------------------------------------------------------------
# flexcat
# -----------------------------------------------------------------------------
#
# Source selection follows what the tree provides for non-Amiga hosts:
# locale_other.c replaces locale.c, openlibs.c opens Amiga libraries and is not
# needed, vastubs.c refuses to compile off m68k, and getft.c is replaced by
# cmake/hosttools/flexcat_getft.c.
file(GLOB _flexcat_all "${CMAKE_SOURCE_DIR}/tools/flexcat/src/*.c")
set(_flexcat_srcs "")
foreach(f IN LISTS _flexcat_all)
    get_filename_component(_n "${f}" NAME)
    if(NOT _n MATCHES "^(locale|openlibs|vastubs|getft)\\.c$")
        list(APPEND _flexcat_srcs "${f}")
    endif()
endforeach()
list(APPEND _flexcat_srcs "${CMAKE_SOURCE_DIR}/cmake/hosttools/flexcat_getft.c")

aros_host_tool(NAME flexcat
    SOURCES ${_flexcat_srcs}
    DEFINES _GNU_SOURCE NO_INLINE_STDARG
    INCLUDES "${CMAKE_SOURCE_DIR}/tools/flexcat/src"
    LIBS iconv)

aros_host_tool(NAME ilbmtoc
    SOURCES "${CMAKE_SOURCE_DIR}/tools/ilbmtoc/ilbmtoc.c")

# -----------------------------------------------------------------------------
# Generated header rules
# -----------------------------------------------------------------------------

# aros_catalog_header(CD <file> SD <file> OUTPUT <file>)
#
# flexcat renders a catalog description through a source description template.
# C_h_aros.sd emits the message ids as #defines, which is what compile-time
# code needs; the .catalog files themselves are a runtime concern.
function(aros_catalog_header)
    set(oneValueArgs CD SD OUTPUT)
    cmake_parse_arguments(CH "" "${oneValueArgs}" "" ${ARGN})

    get_filename_component(_dir "${CH_OUTPUT}" DIRECTORY)
    file(MAKE_DIRECTORY "${_dir}")

    add_custom_command(
        OUTPUT "${CH_OUTPUT}"
        COMMAND "${AROS_HOST_FLEXCAT}" "${CH_CD}" "${CH_OUTPUT}=${CH_SD}"
        DEPENDS "${AROS_HOST_FLEXCAT}" "${CH_CD}" "${CH_SD}"
        COMMENT "Generating ${CH_OUTPUT} from ${CH_CD}"
        VERBATIM)
endfunction()

# aros_script_header(SCRIPT <py> INPUT <file> OUTPUT <file>)
#
# For generators the tree ships as Python. rom/dos/genstrings.py builds the
# error-code index table, a format its own comment calls impossible to express
# in FlexCat.
function(aros_script_header)
    set(oneValueArgs SCRIPT INPUT OUTPUT)
    cmake_parse_arguments(SH "" "${oneValueArgs}" "" ${ARGN})

    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(NOT Python3_EXECUTABLE)
        message(WARNING "python3 not found; cannot generate ${SH_OUTPUT}")
        return()
    endif()

    get_filename_component(_dir "${SH_OUTPUT}" DIRECTORY)
    file(MAKE_DIRECTORY "${_dir}")

    add_custom_command(
        OUTPUT "${SH_OUTPUT}"
        COMMAND "${Python3_EXECUTABLE}" "${SH_SCRIPT}" "${SH_INPUT}" > "${SH_OUTPUT}"
        DEPENDS "${SH_SCRIPT}" "${SH_INPUT}"
        COMMENT "Generating ${SH_OUTPUT} from ${SH_INPUT}"
        VERBATIM)
endfunction()

# aros_ilbm_header(ILBM <file> OUTPUT <file> [FLAGS <f>...])
function(aros_ilbm_header)
    set(oneValueArgs ILBM OUTPUT)
    set(multiValueArgs FLAGS)
    cmake_parse_arguments(IH "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    get_filename_component(_dir "${IH_OUTPUT}" DIRECTORY)
    file(MAKE_DIRECTORY "${_dir}")

    add_custom_command(
        OUTPUT "${IH_OUTPUT}"
        COMMAND "${AROS_HOST_ILBMTOC}" ${IH_FLAGS} "${IH_ILBM}" > "${IH_OUTPUT}"
        DEPENDS "${AROS_HOST_ILBMTOC}" "${IH_ILBM}"
        COMMENT "Generating ${IH_OUTPUT} from ${IH_ILBM}"
        VERBATIM)
endfunction()

# aros_tool_header(TOOL <target> OUTPUT <file> [WORKDIR <dir>] [DEPENDS <f>...])
#
# For a generator that writes to stdout and reads its inputs from the current
# directory rather than from arguments. workbench/libs/muimaster/buildincludes
# is built that way: it walks the class headers next to it and prints one
# combined libraries/mui.h.
function(aros_tool_header)
    set(oneValueArgs TOOL OUTPUT WORKDIR)
    set(multiValueArgs DEPENDS)
    cmake_parse_arguments(TH "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    get_filename_component(_dir "${TH_OUTPUT}" DIRECTORY)
    file(MAKE_DIRECTORY "${_dir}")

    set(_wd "${TH_WORKDIR}")
    if(NOT _wd)
        set(_wd "${CMAKE_SOURCE_DIR}")
    endif()

    add_custom_command(
        OUTPUT "${TH_OUTPUT}"
        COMMAND "${CMAKE_COMMAND}" -E chdir "${_wd}" "${TH_TOOL}" > "${TH_OUTPUT}"
        DEPENDS "${TH_TOOL}" ${TH_DEPENDS}
        COMMENT "Generating ${TH_OUTPUT}"
        VERBATIM)
endfunction()

# -----------------------------------------------------------------------------
# buildincludes: libraries/mui.h
# -----------------------------------------------------------------------------
#
# muimaster does not ship libraries/mui.h; it generates one from mui.h,
# macros.h and every class header (workbench/libs/muimaster/mmakefile.src:463).
# Missing, it was the single largest gap in the build: 215 compile failures,
# and the undeclared identifiers that follow from them.
# Built and run at configure time by GeneratedHeaders.cmake, not declared as a
# build target: its output has to exist before the first compile.
