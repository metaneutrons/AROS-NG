cmake_minimum_required(VERSION 3.22)

set(_AROS_AHI_MMAKE_ID "workbench-devs-AHI-subsystem")
set(_AROS_AHI_SOURCE_MANIFEST_SHA256
    "08825cf192261fa90da1a959a8e7ee8a5223953a8533df17f7766fcfc233c75e")
set(_AROS_AHI_X86_64_PRODUCT_MANIFEST_SHA256
    "76ec82653cc7b2715eefbf8c7dab813acab99aece10b5772dd3f8a59f5687ca2")
set(_AROS_AHI_ARM_PRODUCT_MANIFEST_SHA256
    "dcbba66c6b84f7b581edbb28540d2c8523f8afe0a0c3c4ecb2f57db8b33cb2ce")
set(_AROS_AHI_AARCH64_PRODUCT_MANIFEST_SHA256
    "dcbba66c6b84f7b581edbb28540d2c8523f8afe0a0c3c4ecb2f57db8b33cb2ce")

function(_aros_ahi_real_path path output)
    set(_candidate "${path}")
    cmake_path(ABSOLUTE_PATH _candidate NORMALIZE OUTPUT_VARIABLE _candidate)
    set(_tail "")
    while(NOT EXISTS "${_candidate}" AND NOT IS_SYMLINK "${_candidate}")
        cmake_path(GET _candidate FILENAME _part)
        cmake_path(GET _candidate PARENT_PATH _parent)
        if(_part STREQUAL "" OR _parent STREQUAL _candidate)
            message(FATAL_ERROR "AHI runner: cannot resolve ${path}")
        endif()
        list(PREPEND _tail "${_part}")
        set(_candidate "${_parent}")
    endwhile()
    if(IS_SYMLINK "${_candidate}" AND NOT EXISTS "${_candidate}")
        message(FATAL_ERROR "AHI runner: refusing dangling symlink in ${path}")
    endif()
    file(REAL_PATH "${_candidate}" _resolved)
    foreach(_part IN LISTS _tail)
        set(_resolved "${_resolved}/${_part}")
    endforeach()
    cmake_path(NORMAL_PATH _resolved)
    set(${output} "${_resolved}" PARENT_SCOPE)
endfunction()

function(_aros_ahi_child root path label)
    set(_root_value "${root}")
    cmake_path(IS_PREFIX _root_value "${path}" NORMALIZE _inside)
    if(NOT _inside OR "${root}" STREQUAL "${path}")
        message(FATAL_ERROR "AHI runner: ${label} escaped its owning tree")
    endif()
endfunction()

function(_aros_ahi_regular path label)
    if(NOT EXISTS "${path}" OR IS_DIRECTORY "${path}" OR IS_SYMLINK "${path}")
        message(FATAL_ERROR "AHI runner: ${label} is missing, a directory or a symlink")
    endif()
endfunction()

function(_aros_ahi_executable path label)
    _aros_ahi_regular("${path}" "${label}")
    if(NOT IS_EXECUTABLE "${path}")
        message(FATAL_ERROR "AHI runner: ${label} is not executable")
    endif()
endfunction()

# Autoconf records these paths in generated Makefiles.  Make recipes cannot
# preserve a literal path separator as a single shell word without bespoke
# escaping, so the closed runner rejects whitespace consistently with its
# CMake-side contract builder.
function(_aros_ahi_require_make_path label path)
    if("${path}" MATCHES "[ \t\r\n]")
        message(FATAL_ERROR
            "AHI runner: ${label} cannot contain whitespace for configure/Make")
    endif()
endfunction()

if(NOT DEFINED CONTRACT OR NOT EXISTS "${CONTRACT}" OR IS_DIRECTORY "${CONTRACT}" OR
   IS_SYMLINK "${CONTRACT}")
    message(FATAL_ERROR "RunAhiBuild requires a regular existing CONTRACT")
endif()
include("${CONTRACT}")

set(_required
    AHI_MMAKE_ID AHI_MODE AHI_SOURCE_ROOT AHI_BUILD_ROOT AHI_SOURCE_DIR
    AHI_SOURCE_MANIFEST AHI_SOURCE_MANIFEST_SHA256
    AHI_PRODUCT_MANIFEST AHI_PRODUCT_MANIFEST_SHA256
    AHI_BINARY_DIR AHI_STAGE_SOURCE AHI_STAGE_BUILD AHI_STAGE_LINKLIBS
    AHI_INSTALL_PREFIX AHI_HOST_SFDC AHI_HOST_PERL AHI_HOST_FLEXCAT AHI_FLEXCAT AHI_MAKE
    AHI_CC AHI_AS AHI_AR AHI_RANLIB AHI_OBJCOPY AHI_STRIP AHI_LLD AHI_SDK_INCLUDE
    AHI_GEN_INCLUDE AHI_FEATURE_HEADERS
    AHI_BUILD_TRIPLET AHI_TARGET_TRIPLE AHI_ELF_CLASS AHI_ELF_MACHINE_HEX
    AHI_TARGET_CFLAGS AHI_TARGET_CPPFLAGS AHI_TARGET_ASFLAGS AHI_TARGET_LDFLAGS
    AHI_INPUT_RELATIVE AHI_INPUT_SHA256 AHI_PRODUCT_RELATIVE AHI_PRODUCT_KINDS
    AHI_INSTALL_PRODUCTS AHI_DEPENDENCY_PRODUCTS)
foreach(_name IN LISTS _required)
    if(NOT DEFINED ${_name} OR "${${_name}}" STREQUAL "")
        message(FATAL_ERROR "AHI runner contract omits ${_name}")
    endif()
endforeach()
if(NOT AHI_MMAKE_ID STREQUAL _AROS_AHI_MMAKE_ID OR
   NOT AHI_MODE MATCHES "^(x86_64|arm|aarch64)$" OR
   NOT AHI_SOURCE_MANIFEST_SHA256 STREQUAL _AROS_AHI_SOURCE_MANIFEST_SHA256)
    message(FATAL_ERROR "AHI runner contract differs from audited identity")
endif()
if(AHI_MODE STREQUAL "x86_64")
    set(_expected_product_hash "${_AROS_AHI_X86_64_PRODUCT_MANIFEST_SHA256}")
    set(_expected_triple "x86_64-unknown-aros")
    set(_expected_class "02")
    set(_expected_machine "3e00")
elseif(AHI_MODE STREQUAL "arm")
    set(_expected_product_hash "${_AROS_AHI_ARM_PRODUCT_MANIFEST_SHA256}")
    set(_expected_triple "arm-unknown-aros")
    set(_expected_class "01")
    set(_expected_machine "2800")
else()
    set(_expected_product_hash "${_AROS_AHI_AARCH64_PRODUCT_MANIFEST_SHA256}")
    set(_expected_triple "aarch64-unknown-aros")
    set(_expected_class "02")
    set(_expected_machine "b700")
endif()
if(NOT AHI_PRODUCT_MANIFEST_SHA256 STREQUAL _expected_product_hash OR
   NOT AHI_TARGET_TRIPLE STREQUAL _expected_triple OR
   NOT AHI_ELF_CLASS STREQUAL _expected_class OR
   NOT AHI_ELF_MACHINE_HEX STREQUAL _expected_machine OR
   NOT AHI_BUILD_TRIPLET MATCHES "^[A-Za-z0-9_.+-]+$")
    message(FATAL_ERROR "AHI runner contract differs from audited mode identity")
endif()

foreach(_name IN ITEMS
        AHI_SOURCE_ROOT AHI_BUILD_ROOT AHI_SOURCE_DIR AHI_SOURCE_MANIFEST
        AHI_PRODUCT_MANIFEST AHI_BINARY_DIR AHI_STAGE_SOURCE AHI_STAGE_BUILD
        AHI_STAGE_LINKLIBS AHI_INSTALL_PREFIX AHI_HOST_SFDC AHI_HOST_PERL
        AHI_HOST_FLEXCAT AHI_FLEXCAT AHI_MAKE AHI_CC AHI_AS AHI_AR AHI_RANLIB
        AHI_OBJCOPY AHI_STRIP AHI_LLD AHI_SDK_INCLUDE)
    if(NOT IS_ABSOLUTE "${${_name}}" OR "${${_name}}" MATCHES "[;\"$\\\\\r\n]" OR
       "${${_name}}" MATCHES "==\\]")
        message(FATAL_ERROR "AHI runner contract has unsafe ${_name}")
    endif()
endforeach()
cmake_path(GET AHI_LLD FILENAME _lld_program_name)
if(NOT _lld_program_name STREQUAL "ld.lld")
    message(FATAL_ERROR "AHI runner contract must invoke ld.lld by that exact name")
endif()

foreach(_name IN ITEMS SOURCE_ROOT BUILD_ROOT SOURCE_DIR BINARY_DIR STAGE_SOURCE
        STAGE_BUILD STAGE_LINKLIBS INSTALL_PREFIX SDK_INCLUDE GEN_INCLUDE)
    _aros_ahi_real_path("${AHI_${_name}}" _${_name})
endforeach()
foreach(_name IN ITEMS SOURCE_MANIFEST PRODUCT_MANIFEST HOST_SFDC HOST_PERL
        HOST_FLEXCAT FLEXCAT MAKE CC AS AR RANLIB OBJCOPY STRIP LLD)
    _aros_ahi_real_path("${AHI_${_name}}" _${_name})
endforeach()
set(_source_root "${_SOURCE_ROOT}")
set(_build_root "${_BUILD_ROOT}")
set(_source_dir "${_SOURCE_DIR}")
set(_binary_dir "${_BINARY_DIR}")
set(_stage_source "${_STAGE_SOURCE}")
set(_stage_build "${_STAGE_BUILD}")
set(_stage_linklibs "${_STAGE_LINKLIBS}")
set(_install_prefix "${_INSTALL_PREFIX}")

foreach(_path IN ITEMS
        _source_root _build_root _source_dir _binary_dir _stage_source
        _stage_build _stage_linklibs _install_prefix _SOURCE_MANIFEST
        _PRODUCT_MANIFEST _HOST_SFDC _HOST_PERL _HOST_FLEXCAT _FLEXCAT _MAKE
        _CC _AS _AR _RANLIB _OBJCOPY _STRIP _LLD _SDK_INCLUDE _GEN_INCLUDE)
    _aros_ahi_require_make_path("${_path}" "${${_path}}")
endforeach()

foreach(_path IN ITEMS _source_root _build_root _source_dir _SDK_INCLUDE _GEN_INCLUDE)
    if(NOT EXISTS "${${_path}}" OR NOT IS_DIRECTORY "${${_path}}")
        message(FATAL_ERROR "AHI runner lacks directory ${_path}")
    endif()
endforeach()
set(_os_include "${_SDK_INCLUDE}/aros/posixc")
if(NOT EXISTS "${_os_include}" OR NOT IS_DIRECTORY "${_os_include}")
    message(FATAL_ERROR "AHI runner lacks SDK POSIX include directory")
endif()
_aros_ahi_real_path("${_os_include}" _os_include)
_aros_ahi_child("${_SDK_INCLUDE}" "${_os_include}" "SDK POSIX include")
_aros_ahi_regular("${_SOURCE_MANIFEST}" "source manifest")
_aros_ahi_regular("${_PRODUCT_MANIFEST}" "product manifest")
foreach(_tool IN ITEMS _HOST_SFDC _HOST_PERL _HOST_FLEXCAT _FLEXCAT _MAKE _CC _AS _AR _RANLIB _OBJCOPY _STRIP _LLD)
    _aros_ahi_executable("${${_tool}}" "${_tool}")
endforeach()

_aros_ahi_real_path("${_source_root}/workbench/devs/AHI" _expected_source)
_aros_ahi_real_path("${_expected_source}/ahi-build.inputs" _expected_source_manifest)
_aros_ahi_real_path("${_source_root}/cmake/manifests/ahi-${AHI_MODE}.install"
    _expected_product_manifest)
_aros_ahi_real_path("${_build_root}/gen/configure/workbench/devs/AHI/${AHI_MODE}"
    _expected_binary)
_aros_ahi_real_path("${_build_root}/SYS" _expected_prefix)
_aros_ahi_real_path("${_build_root}/hosttools/sfdc" _expected_sfdc)
_aros_ahi_real_path("${_build_root}/hosttools/flexcat" _expected_flexcat)
_aros_ahi_real_path("${_build_root}/SDK/include" _expected_sdk)
_aros_ahi_real_path("${_build_root}/GENINCDIR" _expected_gen_include)
_aros_ahi_real_path("${_binary_dir}/ahi-cc" _expected_cc)
_aros_ahi_real_path("${_binary_dir}/ahi-ar" _expected_ar)
_aros_ahi_real_path("${_binary_dir}/ahi-flexcat" _expected_flexcat_wrapper)
if(NOT _source_dir STREQUAL _expected_source OR
   NOT _SOURCE_MANIFEST STREQUAL _expected_source_manifest OR
   NOT _PRODUCT_MANIFEST STREQUAL _expected_product_manifest OR
   NOT _binary_dir STREQUAL _expected_binary OR
   NOT _install_prefix STREQUAL _expected_prefix OR
   NOT _HOST_SFDC STREQUAL _expected_sfdc OR
   NOT _HOST_FLEXCAT STREQUAL _expected_flexcat OR
   NOT _CC STREQUAL _expected_cc OR
   NOT _AR STREQUAL _expected_ar OR
   NOT _FLEXCAT STREQUAL _expected_flexcat_wrapper OR
   NOT _SDK_INCLUDE STREQUAL _expected_sdk OR
   NOT _GEN_INCLUDE STREQUAL _expected_gen_include)
    message(FATAL_ERROR "AHI runner contract differs from audited paths")
endif()
_aros_ahi_child("${_source_root}" "${_source_dir}" "source directory")
_aros_ahi_child("${_source_dir}" "${_SOURCE_MANIFEST}" "source manifest")
_aros_ahi_child("${_source_root}" "${_PRODUCT_MANIFEST}" "product manifest")
_aros_ahi_child("${_build_root}" "${_binary_dir}" "binary directory")
_aros_ahi_child("${_build_root}" "${_install_prefix}" "install prefix")
_aros_ahi_child("${_build_root}" "${_HOST_SFDC}" "host sfdc")
_aros_ahi_child("${_build_root}" "${_HOST_FLEXCAT}" "host flexcat")
_aros_ahi_child("${_build_root}" "${_SDK_INCLUDE}" "SDK include")
_aros_ahi_child("${_build_root}" "${_GEN_INCLUDE}" "generated include")
foreach(_path IN ITEMS _stage_source _stage_build _stage_linklibs)
    _aros_ahi_child("${_binary_dir}" "${${_path}}" "private stage")
endforeach()
if(IS_SYMLINK "${_binary_dir}" OR IS_SYMLINK "${_install_prefix}")
    message(FATAL_ERROR "AHI runner private output path escaped through a symlink")
endif()
file(MAKE_DIRECTORY "${_binary_dir}" "${_install_prefix}")
_aros_ahi_real_path("${_binary_dir}" _binary_after)
_aros_ahi_real_path("${_install_prefix}" _prefix_after)
if(NOT _binary_after STREQUAL _binary_dir OR NOT _prefix_after STREQUAL _install_prefix)
    message(FATAL_ERROR "AHI runner private output path escaped through a symlink")
endif()
foreach(_relative IN LISTS AHI_PRODUCT_RELATIVE)
    set(_preflight_product "${_install_prefix}/${_relative}")
    cmake_path(GET _preflight_product PARENT_PATH _preflight_parent)
    _aros_ahi_real_path("${_preflight_parent}" _preflight_parent_real)
    set(_prefix_value "${_install_prefix}")
    cmake_path(IS_PREFIX _prefix_value "${_preflight_parent_real}" NORMALIZE _parent_owned)
    if(NOT _parent_owned OR IS_SYMLINK "${_preflight_product}")
        message(FATAL_ERROR "AHI runner install product escaped through a symlink")
    endif()
endforeach()

file(SHA256 "${_SOURCE_MANIFEST}" _source_hash)
file(SHA256 "${_PRODUCT_MANIFEST}" _product_hash)
if(NOT _source_hash STREQUAL _AROS_AHI_SOURCE_MANIFEST_SHA256 OR
   NOT _product_hash STREQUAL _expected_product_hash)
    message(FATAL_ERROR "AHI runner manifest differs from audited SHA-256")
endif()
file(STRINGS "${_SOURCE_MANIFEST}" _source_lines ENCODING UTF-8)
set(_input_relative "")
set(_input_hashes "")
foreach(_line IN LISTS _source_lines)
    if(NOT _line MATCHES "^([0-9a-f]+)  (.+)$")
        message(FATAL_ERROR "AHI runner: malformed source manifest")
    endif()
    set(_digest "${CMAKE_MATCH_1}")
    set(_relative "${CMAKE_MATCH_2}")
    string(LENGTH "${_digest}" _digest_length)
    if(IS_ABSOLUTE "${_relative}" OR _relative MATCHES "(^|/)[.][.]?(/|$)" OR
       _relative MATCHES "[;\"$\\\\\r\n]" OR _relative MATCHES "==\\]" OR
       _relative IN_LIST _input_relative OR NOT _digest_length EQUAL 64)
        message(FATAL_ERROR "AHI runner: unsafe source manifest path")
    endif()
    list(APPEND _input_relative "${_relative}")
    list(APPEND _input_hashes "${_digest}")
endforeach()
if(NOT _input_relative STREQUAL AHI_INPUT_RELATIVE OR
   NOT _input_hashes STREQUAL AHI_INPUT_SHA256)
    message(FATAL_ERROR "AHI runner contract input identity differs from manifest")
endif()
file(STRINGS "${_PRODUCT_MANIFEST}" _product_lines ENCODING UTF-8)
set(_product_relative "")
set(_product_kinds "")
foreach(_line IN LISTS _product_lines)
    if(NOT _line MATCHES "^(elf|data|mode)  (.+)$")
        message(FATAL_ERROR "AHI runner: malformed product manifest")
    endif()
    set(_kind "${CMAKE_MATCH_1}")
    set(_relative "${CMAKE_MATCH_2}")
    if(IS_ABSOLUTE "${_relative}" OR _relative MATCHES "(^|/)[.][.]?(/|$)" OR
       _relative MATCHES "[;\"$\\\\\r\n]" OR _relative MATCHES "==\\]" OR
       _relative IN_LIST _product_relative)
        message(FATAL_ERROR "AHI runner: unsafe product manifest path")
    endif()
    list(APPEND _product_relative "${_relative}")
    list(APPEND _product_kinds "${_kind}")
endforeach()
if(NOT _product_relative STREQUAL AHI_PRODUCT_RELATIVE OR
   NOT _product_kinds STREQUAL AHI_PRODUCT_KINDS)
    message(FATAL_ERROR "AHI runner contract product identity differs from manifest")
endif()
list(LENGTH _product_relative _product_count)
if((AHI_MODE STREQUAL "x86_64" AND NOT _product_count EQUAL 73) OR
   ((AHI_MODE STREQUAL "arm" OR AHI_MODE STREQUAL "aarch64") AND
    NOT _product_count EQUAL 85))
    message(FATAL_ERROR "AHI runner product count differs from audited capability")
endif()
list(LENGTH _input_relative _input_count)
math(EXPR _last_input "${_input_count} - 1")
if(_last_input GREATER_EQUAL 0)
    foreach(_index RANGE 0 ${_last_input})
        list(GET _input_relative ${_index} _relative)
        list(GET _input_hashes ${_index} _expected_hash)
        set(_input "${_source_dir}/${_relative}")
        _aros_ahi_regular("${_input}" "source input ${_relative}")
        _aros_ahi_real_path("${_input}" _input_real)
        _aros_ahi_child("${_source_dir}" "${_input_real}" "source input")
        file(SHA256 "${_input_real}" _actual_hash)
        if(NOT _actual_hash STREQUAL _expected_hash)
            message(FATAL_ERROR "AHI runner: source input differs from manifest")
        endif()
    endforeach()
endif()

set(_expected_feature_headers "${_GEN_INCLUDE}/libraries/mui.h" "${_SDK_INCLUDE}/asm/io.h")
if(AHI_MODE STREQUAL "arm" OR AHI_MODE STREQUAL "aarch64")
    list(APPEND _expected_feature_headers
        "${_SDK_INCLUDE}/proto/dma.h" "${_SDK_INCLUDE}/proto/mbox.h")
endif()
if(NOT AHI_FEATURE_HEADERS STREQUAL _expected_feature_headers)
    message(FATAL_ERROR "AHI runner feature-header identity differs from audited contract")
endif()
foreach(_header IN LISTS AHI_FEATURE_HEADERS)
    _aros_ahi_regular("${_header}" "staged feature header")
    _aros_ahi_real_path("${_header}" _header_real)
    _aros_ahi_child("${_build_root}" "${_header_real}" "staged feature header")
    file(SIZE "${_header_real}" _header_size)
    if(_header_size LESS 1)
        message(FATAL_ERROR "AHI runner: staged feature header is empty")
    endif()
endforeach()

# The three link libraries, checked by what they are rather than by where they
# happen to sit.
#
# This used to compare the paths against `<build root>/liblinklibs-<mmake>.a`
# literally. That name is what a link library is called only while nothing names
# it: a consumer promotes it and it moves to `SYS/Developer/lib/lib<name>.a`.
# When that happened the comparison failed, and before it failed the caller could
# not find the file at all. The three are not even in one place today --
# linklibs-libm is private while linklibs-amiga and linklibs-mui are canonical.
#
# What the audit is actually about survives unchanged: exactly three inputs, each
# a regular non-empty file inside the build root, each copied into the private
# staging directory under a fixed alias. Only the assumption about their
# filenames is gone, and it is the caller that now derives them, from the targets
# that own them.
set(_aliases libamiga.a libm.a libmui.a)
list(LENGTH AHI_DEPENDENCY_PRODUCTS _dependency_count)
if(NOT _dependency_count EQUAL 3)
    message(FATAL_ERROR
        "AHI runner: expected 3 link-library dependencies, got ${_dependency_count}")
endif()
foreach(_index RANGE 0 2)
    list(GET AHI_DEPENDENCY_PRODUCTS ${_index} _dependency)
    _aros_ahi_regular("${_dependency}" "link-library dependency")
    _aros_ahi_real_path("${_dependency}" _dependency_real)
    _aros_ahi_child("${_build_root}" "${_dependency_real}" "link-library dependency")
    file(SIZE "${_dependency_real}" _size)
    if(_size LESS 1)
        message(FATAL_ERROR "AHI runner: empty link-library dependency")
    endif()
endforeach()

# The only recursive removals are three exact private children.  An injected
# symlink is rejected before either source staging or a repair can write.
foreach(_path IN ITEMS _stage_source _stage_build _stage_linklibs)
    if(IS_SYMLINK "${${_path}}")
        message(FATAL_ERROR "AHI runner private stage escaped through a symlink")
    endif()
    _aros_ahi_real_path("${${_path}}" _private_real)
    _aros_ahi_child("${_binary_dir}" "${_private_real}" "private stage")
    file(REMOVE_RECURSE "${${_path}}")
endforeach()
file(MAKE_DIRECTORY "${_stage_source}" "${_stage_build}" "${_stage_linklibs}")
foreach(_path IN ITEMS _stage_source _stage_build _stage_linklibs)
    _aros_ahi_real_path("${${_path}}" _private_real)
    _aros_ahi_child("${_binary_dir}" "${_private_real}" "private stage")
endforeach()

if(_last_input GREATER_EQUAL 0)
    foreach(_index RANGE 0 ${_last_input})
        list(GET _input_relative ${_index} _relative)
        set(_input "${_source_dir}/${_relative}")
        set(_staged "${_stage_source}/${_relative}")
        cmake_path(GET _staged PARENT_PATH _parent)
        file(MAKE_DIRECTORY "${_parent}")
        _aros_ahi_real_path("${_parent}" _parent_real)
        set(_stage_root_value "${_stage_source}")
        cmake_path(IS_PREFIX _stage_root_value "${_parent_real}" NORMALIZE _parent_owned)
        if(NOT _parent_owned)
            message(FATAL_ERROR "AHI runner: staged source escaped its owning tree")
        endif()
        if(IS_SYMLINK "${_staged}")
            message(FATAL_ERROR "AHI runner staged source escaped through a symlink")
        endif()
        file(COPY_FILE "${_input}" "${_staged}" ONLY_IF_DIFFERENT)
    endforeach()
endif()
foreach(_script IN ITEMS configure config.guess config.sub install-sh)
    if(EXISTS "${_stage_source}/${_script}")
        file(CHMOD "${_stage_source}/${_script}" PERMISSIONS
            OWNER_READ OWNER_WRITE OWNER_EXECUTE
            GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
    endif()
endforeach()
# The audited checkout carries Autoconf's generated configure and config.h.in.
# Staging intentionally gives every input a fresh timestamp; make would then
# consider a same-second configure.in newer and try to run unavailable host
# autoconf/autoheader.  Mark the two checked-in generated files newest within
# the private copy so the closed run uses exactly those audited artifacts.
file(TOUCH "${_stage_source}/configure" "${_stage_source}/config.h.in")
foreach(_index RANGE 0 2)
    list(GET AHI_DEPENDENCY_PRODUCTS ${_index} _dependency)
    list(GET _aliases ${_index} _alias)
    file(COPY_FILE "${_dependency}" "${_stage_linklibs}/${_alias}" ONLY_IF_DIFFERENT)
    _aros_ahi_regular("${_stage_linklibs}/${_alias}" "private link-library alias")
endforeach()

string(CONCAT _cache
    "ac_cv_search_NewList='-lamiga'\n"
    "ac_cv_search_floor='-lm'\n"
    "ac_cv_search_IntuitionBase=no\n"
    "ac_cv_search_LayoutBase=no\n"
    "ac_cv_search_MUI_NewObject='-lmui'\n"
    "ac_cv_header_asm_io_h=yes\n"
    "ac_cv_header_libraries_openpci_h=no\n"
    "ac_cv_header_proto_oss_h=no\n"
    "ac_cv_lib_alsa_bridge_ALSA_Init=no\n"
    "ac_cv_lib_pulseaudio_bridge_PULSEA_Init=no\n"
    "ac_cv_lib_WASAPI_bridge_WASAPI_Init=no\n"
    "ac_cv_c_const=yes\n"
    "ac_cv_c_inline=yes\n"
    "ac_cv_c_bigendian=no\n")
if(AHI_MODE STREQUAL "x86_64")
    string(APPEND _cache "ac_cv_header_proto_dma_h=no\n")
else()
    string(APPEND _cache "ac_cv_header_proto_dma_h=yes\n")
endif()
file(WRITE "${_stage_build}/config.cache" "${_cache}")
execute_process(
    COMMAND "${_HOST_PERL}" -c "${_HOST_SFDC}"
    RESULT_VARIABLE _perl_result OUTPUT_VARIABLE _perl_out ERROR_VARIABLE _perl_err)
if(NOT _perl_result EQUAL 0)
    message(FATAL_ERROR "AHI runner: HOST_SFDC failed HOST_PERL\n${_perl_out}${_perl_err}")
endif()

string(JOIN " " _cflags ${AHI_TARGET_CFLAGS})
string(JOIN " " _cppflags ${AHI_TARGET_CPPFLAGS})
string(JOIN " " _asflags ${AHI_TARGET_ASFLAGS})
string(JOIN " " _ldflags ${AHI_TARGET_LDFLAGS})
set(_environment
    "PATH=/usr/bin:/bin"
    "SHELL=/bin/sh" "LC_ALL=C"
    # Preserve configured command names.  Homebrew's llvm-ranlib and
    # llvm-strip are argv[0]-selecting symlinks, while the physical path used
    # above is retained solely for validation.
    "CC=${AHI_CC}" "AS=${AHI_AS}" "AR=${AHI_AR}" "RANLIB=${AHI_RANLIB}"
    "OBJCOPY=${AHI_OBJCOPY}" "STRIP=${AHI_STRIP}" "MAKE=${AHI_MAKE}"
    "SFDC=${_HOST_SFDC}" "FLEXCAT=${_FLEXCAT}" "PERL=${_HOST_PERL}"
    "RM=/bin/rm" "INSTALL=/usr/bin/install" "ROBODOC=/usr/bin/false"
    "LHA=/usr/bin/false" "AHI_MODE=${AHI_MODE}"
    "AHI_INSTALL_PREFIX=${_install_prefix}"
    "AHI_PRODUCT_MANIFEST=${_PRODUCT_MANIFEST}"
    # Keep compiler/package search and shell-startup state out of the
    # configure/Make boundary.  The explicitly supplied tools, SDK and
    # link-library stage are the complete supported inputs.
    "MFLAGS=" "CDPATH=" "ENV=" "BASH_ENV="
    "CPATH=" "C_INCLUDE_PATH=" "CPLUS_INCLUDE_PATH=" "LIBRARY_PATH="
    "SDKROOT=" "PKG_CONFIG_PATH=" "PKG_CONFIG_LIBDIR="
    "PKG_CONFIG_SYSROOT_DIR=")
set(_unset
    --unset=CFLAGS --unset=CPPFLAGS --unset=LDFLAGS --unset=ASFLAGS
    --unset=LIBS --unset=CPP --unset=MAKEFLAGS --unset=CONFIG_SITE --unset=CONFIG_SHELL
    --unset=AHI_BUILDHANDLER --unset=CPU --unset=ASCPPFLAGS --unset=ARFLAGS
    --unset=CFLAG_RESIDENT --unset=LDFLAG_RESIDENT --unset=STRIPFLAGS
    --unset=INSTALL_PROGRAM --unset=INSTALL_DATA --unset=INSTALL_SCRIPT
    --unset=DISTDIR)
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env ${_unset} ${_environment}
        "${_stage_source}/configure"
        "--build=${AHI_BUILD_TRIPLET}" "--host=${AHI_TARGET_TRIPLE}"
        "--target=${AHI_TARGET_TRIPLE}"
        "--cache-file=${_stage_build}/config.cache"
        "--prefix=${_install_prefix}" "--bindir=${_install_prefix}"
        "--sbindir=${_install_prefix}" "--libdir=${_install_prefix}/Libs"
        "--includedir=${_install_prefix}/Developer/include"
        "--oldincludedir=${_install_prefix}/Developer/include"
        "--with-os-includedir=${_os_include}"
        "--with-target-cflags=${_cflags}"
        "--with-target-cppflags=${_cppflags}"
        "--with-target-asflags=${_asflags}"
        "--with-target-ldflags=${_ldflags}"
        "--with-target-optflags=-O2"
    WORKING_DIRECTORY "${_stage_build}"
    RESULT_VARIABLE _configure_result
    OUTPUT_VARIABLE _configure_out ERROR_VARIABLE _configure_err)
if(NOT _configure_result EQUAL 0)
    message(FATAL_ERROR
        "AHI runner configure failed (${_configure_result})\n${_configure_out}${_configure_err}")
endif()
set(_config_header "${_stage_build}/config.h")
_aros_ahi_regular("${_config_header}" "configured config.h")
file(READ "${_config_header}" _config_header_content)
foreach(_define IN ITEMS HAVE_ASM_IO_H HAVE_LIBMUI)
    string(FIND "${_config_header_content}" "#define ${_define} 1" _define_at)
    if(_define_at LESS 0)
        message(FATAL_ERROR "AHI runner: configured feature ${_define} differs from contract")
    endif()
endforeach()
set(_drivers_makefile "${_stage_build}/Drivers/Makefile")
_aros_ahi_regular("${_drivers_makefile}" "configured Drivers/Makefile")
file(READ "${_drivers_makefile}" _drivers_content)
string(FIND "${_drivers_content}" "HAVE_ASMIO      = 1" _asmio_at)
if(_asmio_at LESS 0)
    message(FATAL_ERROR "AHI runner: configured driver feature HAVE_ASMIO differs from contract")
endif()
if(AHI_MODE STREQUAL "x86_64")
    string(FIND "${_config_header_content}" "#define HAVE_PROTO_DMA_H 1" _dma_at)
    if(_dma_at GREATER_EQUAL 0)
        message(FATAL_ERROR "AHI runner: x86_64 configured an unexpected DMA feature")
    endif()
    string(FIND "${_drivers_content}" "HAVE_DMA_H      = 1" _driver_dma_at)
    if(_driver_dma_at GREATER_EQUAL 0)
        message(FATAL_ERROR "AHI runner: x86_64 selected unexpected DMA drivers")
    endif()
else()
    string(FIND "${_config_header_content}" "#define HAVE_PROTO_DMA_H 1" _dma_at)
    if(_dma_at LESS 0)
        message(FATAL_ERROR "AHI runner: ARM configured DMA feature differs from contract")
    endif()
    string(FIND "${_drivers_content}" "HAVE_DMA_H      = 1" _driver_dma_at)
    if(_driver_dma_at LESS 0)
        message(FATAL_ERROR "AHI runner: ARM selected wrong DMA driver profile")
    endif()
endif()
foreach(_unexpected IN ITEMS HAVE_LIBRARIES_OPENPCI_H HAVE_PROTO_OSS_H)
    string(FIND "${_config_header_content}" "#define ${_unexpected} 1" _unexpected_at)
    if(_unexpected_at GREATER_EQUAL 0)
        message(FATAL_ERROR "AHI runner: configured unexpected feature ${_unexpected}")
    endif()
endforeach()
set(_configured_content "")
foreach(_makefile IN ITEMS Include/Makefile Device/Makefile)
    set(_configured "${_stage_build}/${_makefile}")
    _aros_ahi_regular("${_configured}" "configured ${_makefile}")
    file(READ "${_configured}" _content)
    string(APPEND _configured_content "${_content}")
endforeach()
foreach(_bound IN ITEMS _HOST_SFDC _FLEXCAT _CC)
    string(FIND "${_configured_content}" "${${_bound}}" _at)
    if(_at LESS 0)
        message(FATAL_ERROR "AHI runner: configured Makefiles did not bind ${_bound}")
    endif()
endforeach()
# The upstream install target enters AHI before Include, whereas the source
# files already include the headers produced by Include/gcc-include.  The
# legacy top-level all target explicitly performs this same preparation first;
# do it in the private configure tree before the closed install pass.
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env ${_unset} ${_environment}
        "${_MAKE}" -C "${_stage_build}/Include" gcc-include
    RESULT_VARIABLE _include_result
    OUTPUT_VARIABLE _include_out ERROR_VARIABLE _include_err)
if(NOT _include_result EQUAL 0)
    message(FATAL_ERROR
        "AHI runner gcc-include preparation failed (${_include_result})\n${_include_out}${_include_err}")
endif()
foreach(_header IN ITEMS
        "${_stage_build}/Include/gcc/devices/ahi.h"
        "${_stage_build}/Include/gcc/libraries/ahi_sub.h"
        "${_stage_build}/Include/gcc/proto/ahi.h")
    _aros_ahi_regular("${_header}" "generated AHI include")
endforeach()
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env ${_unset} ${_environment}
        "${_MAKE}" -C "${_stage_build}" install
    RESULT_VARIABLE _make_result OUTPUT_VARIABLE _make_out ERROR_VARIABLE _make_err)
if(NOT _make_result EQUAL 0)
    message(FATAL_ERROR
        "AHI runner make install failed (${_make_result})\n${_make_out}${_make_err}")
endif()

file(MAKE_DIRECTORY "${_install_prefix}")
_aros_ahi_real_path("${_install_prefix}" _prefix_after)
if(NOT _prefix_after STREQUAL _install_prefix OR IS_SYMLINK "${_install_prefix}")
    message(FATAL_ERROR "AHI runner install prefix escaped through a symlink")
endif()
list(LENGTH AHI_INSTALL_PRODUCTS _installed_count)
if(NOT _installed_count EQUAL _product_count)
    message(FATAL_ERROR "AHI runner product path count differs from manifest")
endif()
math(EXPR _last_product "${_product_count} - 1")
if(_last_product GREATER_EQUAL 0)
    foreach(_index RANGE 0 ${_last_product})
        list(GET AHI_INSTALL_PRODUCTS ${_index} _product)
        list(GET _product_relative ${_index} _relative)
        list(GET _product_kinds ${_index} _kind)
        set(_expected "${_install_prefix}/${_relative}")
        _aros_ahi_real_path("${_expected}" _expected_real)
        if(NOT "${_product}" STREQUAL "${_expected_real}" OR IS_SYMLINK "${_product}")
            message(FATAL_ERROR "AHI runner install product escaped through a symlink")
        endif()
        _aros_ahi_regular("${_product}" "installed product ${_relative}")
        _aros_ahi_real_path("${_product}" _product_real)
        _aros_ahi_child("${_install_prefix}" "${_product_real}" "installed product")
        file(SIZE "${_product_real}" _size)
        if(_size LESS 1)
            message(FATAL_ERROR "AHI runner: installed product ${_relative} is empty")
        endif()
        if(_kind STREQUAL "elf")
            file(READ "${_product_real}" _header OFFSET 0 LIMIT 20 HEX)
            string(TOLOWER "${_header}" _header)
            string(LENGTH "${_header}" _header_len)
            if(_header_len LESS 40)
                message(FATAL_ERROR "AHI runner: ELF product ${_relative} is truncated")
            endif()
            string(SUBSTRING "${_header}" 0 8 _magic)
            string(SUBSTRING "${_header}" 8 2 _class)
            string(SUBSTRING "${_header}" 36 4 _machine)
            if(NOT _magic STREQUAL "7f454c46" OR NOT _class STREQUAL AHI_ELF_CLASS OR
               NOT _machine STREQUAL AHI_ELF_MACHINE_HEX)
                message(FATAL_ERROR "AHI runner: ELF product ${_relative} has wrong format")
            endif()
        endif()
    endforeach()
endif()
if(_last_input GREATER_EQUAL 0)
    foreach(_index RANGE 0 ${_last_input})
        list(GET _input_relative ${_index} _relative)
        list(GET _input_hashes ${_index} _expected_hash)
        file(SHA256 "${_source_dir}/${_relative}" _actual_hash)
        if(NOT _actual_hash STREQUAL _expected_hash)
            message(FATAL_ERROR "AHI runner modified source input ${_relative}")
        endif()
    endforeach()
endif()
