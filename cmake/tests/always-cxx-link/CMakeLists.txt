cmake_minimum_required(VERSION 3.22)
project(AlwaysCxxLinkFixture LANGUAGES C CXX)

set(AROS_TARGET_CPU x86_64)
set(AROS_TARGET_PLATFORM pc)
if(TEST_LOCKED_TOOLCHAIN)
    set(AROS_CROSS_TOOLCHAIN_ROOT "${CMAKE_BINARY_DIR}/release-toolchain")
    set(AROS_TARGET_PROFILE pc-x86_64)
    set(AROS_TARGET_TRIPLE x86_64-unknown-aros)
    set(AROS_LLD_BIN "${AROS_CROSS_TOOLCHAIN_ROOT}/bin/ld.lld")
endif()
include("${CMAKE_CURRENT_LIST_DIR}/../../AROS.cmake")

if(TEST_LOCKED_TOOLCHAIN)
    if(NOT CMAKE_C_LINK_EXECUTABLE MATCHES
            "^${AROS_CROSS_TOOLCHAIN_ROOT}/bin/ld[.]lld -r" OR
       NOT CMAKE_C_LINK_EXECUTABLE MATCHES
            "--sysroot=.*/SYS/Developer" OR
       NOT CMAKE_CXX_LINK_EXECUTABLE MATCHES
            "^<CMAKE_CXX_COMPILER> --target=x86_64-unknown-aros" OR
       NOT CMAKE_CXX_LINK_EXECUTABLE MATCHES
            "--sysroot=.*/SYS/Developer" OR
       NOT CMAKE_CXX_LINK_EXECUTABLE MATCHES "-nostartfiles -r")
        message(FATAL_ERROR
            "locked release did not select exact C/C++ partial-link rules\n"
            "C: ${CMAKE_C_LINK_EXECUTABLE}\nCXX: ${CMAKE_CXX_LINK_EXECUTABLE}")
    endif()
    get_directory_property(_locked_compile_options COMPILE_OPTIONS)
    if(NOT "--sysroot=${AROS_DEVELOPER_DIR}" IN_LIST _locked_compile_options)
        message(FATAL_ERROR
            "locked release did not pass its consumer-owned Developer sysroot")
    endif()
else()
    if(CMAKE_CXX_LINK_EXECUTABLE MATCHES "<CMAKE_CXX_COMPILER>")
        message(FATAL_ERROR
            "development fallback unexpectedly selected the AROS C++ driver")
    endif()
endif()

# These use plain C source on purpose.  The `alwayscxxlink` contract must set
# the linker language independently of CMake's source-language inference.
aros_add_hidd(
    TARGET softpipe
    MMAKE_ID hidd-softpipe
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    ALWAYS_CXX_LINK
    SOURCES module)
aros_add_hidd(
    TARGET nouveau
    MMAKE_ID hidd-nouveau
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    ALWAYS_CXX_LINK
    SOURCES module)
aros_add_hidd(
    TARGET c-default
    MMAKE_ID hidd-c-default
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    SOURCES module)

# Cover the shared full-module, custom-module and simple-module paths too.
aros_add_library(
    TARGET mesa
    MMAKE_ID mesa-module
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    ALWAYS_CXX_LINK
    SOURCES module)
aros_add_device(
    TARGET device
    MMAKE_ID device-module
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    ALWAYS_CXX_LINK
    SOURCES module)
aros_add_resource(
    TARGET resource
    MMAKE_ID resource-module
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    ALWAYS_CXX_LINK
    SOURCES module)
aros_add_custom_target(
    TARGET custom
    MMAKE_ID custom-module
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    MODTYPE hook
    ALWAYS_CXX_LINK
    SOURCES module)
aros_add_module_simple(
    TARGET simple
    MMAKE_ID simple-module
    DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    MODTYPE library
    ALWAYS_CXX_LINK
    SOURCES module)

function(_assert_linker_language target expected)
    get_target_property(_actual "${target}" LINKER_LANGUAGE)
    if(NOT "${_actual}" STREQUAL "${expected}")
        message(FATAL_ERROR
            "${target}: expected linker language ${expected}, got ${_actual}")
    endif()
endfunction()

foreach(_target IN ITEMS
        hidd-softpipe hidd-nouveau mesa-module device-module resource-module
        custom-module simple-module)
    _assert_linker_language("${_target}" CXX)
endforeach()
_assert_linker_language(hidd-c-default C)
