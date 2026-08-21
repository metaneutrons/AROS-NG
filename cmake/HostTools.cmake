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
#                [INCLUDES <dir>...] [LIBS <l>...]
#                [RAW_CFLAGS <flag>...] [RAW_LDFLAGS <flag>...])
#
# Builds one host executable in a single compiler call and exports its path as
# AROS_HOST_<NAME> in the caller's scope. Recompiles when a source changes;
# header changes are not tracked, which is acceptable for vendored tools that
# do not change between builds.
function(aros_host_tool)
    set(oneValueArgs NAME)
    set(multiValueArgs SOURCES DEFINES INCLUDES LIBS RAW_CFLAGS RAW_LDFLAGS)
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

    # RAW_CFLAGS / RAW_LDFLAGS carry what a discovery step produced verbatim --
    # pkg-config's -I/-L/-l set for libpng, for instance, which cannot be
    # reduced to a bare library name because the header and the library live
    # outside the default search paths on a Homebrew host.
    add_custom_command(
        OUTPUT "${_exe}"
        COMMAND "${AROS_HOST_CC}" -O2 -w ${_flags} ${HT_RAW_CFLAGS} ${HT_SOURCES}
                ${_libs} ${HT_RAW_LDFLAGS} -o "${_exe}"
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
# ilbmtoicon
# -----------------------------------------------------------------------------
#
# Turns an icon description plus a PNG into an Amiga Workbench .info file, which
# is what %build_icons produces (config/make.tmpl:3117). Unlike the other host
# tools it has external dependencies: libpng and zlib
# (tools/ilbmtoicon/Makefile:9,27).
#
# Discovery is pkg-config first, because on a Homebrew host neither png.h nor
# libpng16 is on the default search path, then CMake's FindPNG/FindZLIB modules.
# The compiler is invoked directly, so imported targets such as PNG::PNG cannot
# be passed as link flags; the module fallback converts its library variables
# to actual paths or -l arguments. Without both dependencies, icon output rules
# stay in the graph and fail with a direct diagnostic when requested.
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
    pkg_check_modules(AROS_HOST_PNG QUIET libpng)
    pkg_check_modules(AROS_HOST_ZLIB QUIET zlib)
endif()

set(_host_png_ready FALSE)
if(PKG_CONFIG_FOUND AND AROS_HOST_PNG_FOUND AND AROS_HOST_ZLIB_FOUND)
    # CFLAGS/LDFLAGS retain non-directory flags advertised by the .pc files;
    # rebuilding them from INCLUDE_DIRS/LIBRARIES alone would silently lose
    # those usage requirements.
    set(_png_cflags ${AROS_HOST_PNG_CFLAGS} ${AROS_HOST_ZLIB_CFLAGS})
    set(_png_ldflags ${AROS_HOST_PNG_LDFLAGS} ${AROS_HOST_ZLIB_LDFLAGS})
    set(_host_png_ready TRUE)
else()
    # Force module mode: a package config is allowed to expose only PNG::PNG,
    # which is meaningful to target_link_libraries() but not to our raw `cc`
    # custom command.
    find_package(ZLIB QUIET MODULE)
    find_package(PNG QUIET MODULE)
    if(PNG_FOUND AND ZLIB_FOUND)
        set(_png_cflags ${PNG_DEFINITIONS})
        foreach(d IN LISTS PNG_INCLUDE_DIRS)
            list(APPEND _png_cflags "-I${d}")
        endforeach()

        # FindPNG's list may contain absolute paths, bare system libraries
        # (notably `m` for a static libpng), or optimized/debug selectors.
        # Host tools are always built -O2, so select the non-debug entries.
        set(_png_ldflags "")
        set(_use_library TRUE)
        foreach(l IN LISTS PNG_LIBRARIES)
            if(l STREQUAL "optimized" OR l STREQUAL "general")
                set(_use_library TRUE)
            elseif(l STREQUAL "debug")
                set(_use_library FALSE)
            elseif(_use_library)
                if(IS_ABSOLUTE "${l}" OR l MATCHES "^-" OR l MATCHES "[/\\\\]")
                    list(APPEND _png_ldflags "${l}")
                else()
                    list(APPEND _png_ldflags "-l${l}")
                endif()
            endif()
        endforeach()
        set(_host_png_ready TRUE)
    endif()
endif()

if(_host_png_ready)
    list(REMOVE_DUPLICATES _png_cflags)
    list(REMOVE_DUPLICATES _png_ldflags)
    aros_host_tool(NAME ilbmtoicon
        SOURCES "${CMAKE_SOURCE_DIR}/tools/ilbmtoicon/ilbmtoicon.c"
        RAW_CFLAGS ${_png_cflags}
        RAW_LDFLAGS ${_png_ldflags})
    set(AROS_HOST_HAVE_ILBMTOICON TRUE)
else()
    set(AROS_HOST_HAVE_ILBMTOICON FALSE)
    message(STATUS
        "⏭️  AROS-NG: libpng and/or zlib not found on the build machine; "
        "unavailable icon rules will be reported after target transpilation")
endif()

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
