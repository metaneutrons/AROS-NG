# AROS-NG 2.0: Core Target Definitions & Macro Library

include(CMakeParseArguments)

# Library directory layout
set(AROS_SDK_DIR "${CMAKE_BINARY_DIR}/SDK")
set(AROS_GENINCDIR "${CMAKE_BINARY_DIR}/GENINCDIR")
set(AROS_SYS_DIR "${CMAKE_BINARY_DIR}/SYS")
set(AROS_LIBS_DIR "${AROS_SYS_DIR}/Libs")
set(AROS_DEVS_DIR "${AROS_SYS_DIR}/Devs")
set(AROS_C_DIR "${AROS_SYS_DIR}/C")
set(AROS_CLASSES_DIR "${AROS_SYS_DIR}/Classes")

file(MAKE_DIRECTORY "${AROS_SDK_DIR}/include")
file(MAKE_DIRECTORY "${AROS_GENINCDIR}")
file(MAKE_DIRECTORY "${AROS_LIBS_DIR}")
file(MAKE_DIRECTORY "${AROS_DEVS_DIR}")
file(MAKE_DIRECTORY "${AROS_C_DIR}")
include(cmake/BootstrapSDK.cmake)
aros_bootstrap_sdk_includes()

# Global AROS compilation flags
if(CMAKE_C_COMPILER_ID MATCHES "Clang")
    if(AROS_TARGET_CPU STREQUAL "x86_64")
        add_compile_options(-target x86_64-unknown-elf)
        add_link_options(-target x86_64-unknown-elf -nostdlib -r)
    elseif(AROS_TARGET_CPU STREQUAL "aarch64")
        add_compile_options(-target aarch64-unknown-elf)
        add_link_options(-target aarch64-unknown-elf -nostdlib -r)
    elseif(AROS_TARGET_CPU STREQUAL "arm")
        add_compile_options(-target arm-none-eabi)
        add_link_options(-target arm-none-eabi -nostdlib -r)
    endif()
endif()

add_compile_definitions(
    __AROS__=1
    __AROS_VERSION__=1
)

add_compile_options(
    -ffreestanding
    -fno-builtin
    -fno-strict-aliasing
    -fno-common
    -Wall
    -Wextra
    -Wno-unused-parameter
)

include_directories(
    "${CMAKE_SOURCE_DIR}/compiler/include"
    "${CMAKE_SOURCE_DIR}/arch/all-native/include"
    "${AROS_GENINCDIR}"
    "${AROS_SDK_DIR}/include"
)

# Macro: aros_add_library
function(aros_add_library)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS INCLUDES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    set(RESOLVED_SOURCES "")
    foreach(src ${ARG_SOURCES})
        if(EXISTS "${ARG_DIRECTORY}/${src}")
            list(APPEND RESOLVED_SOURCES "${ARG_DIRECTORY}/${src}")
        endif()
    endforeach()

    if(RESOLVED_SOURCES)
        add_library(${ARG_MMAKE_ID} MODULE ${RESOLVED_SOURCES})
        target_compile_definitions(${ARG_MMAKE_ID} PRIVATE
            LC_LIBDEFS_FILE="${ARG_TARGET}_libdefs.h"
            __AROS_LIBNAME__=${ARG_TARGET}
            __AROS_MODNAME__=${ARG_TARGET}
        )
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            PREFIX ""
            SUFFIX ""
            OUTPUT_NAME "${ARG_TARGET}.library"
            LIBRARY_OUTPUT_DIRECTORY "${AROS_LIBS_DIR}"
        )
        if(ARG_LIBS)
            target_link_libraries(${ARG_MMAKE_ID} PRIVATE ${ARG_LIBS})
        endif()
    endif()
endfunction()

# Macro: aros_add_device
function(aros_add_device)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS INCLUDES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    set(RESOLVED_SOURCES "")
    foreach(src ${ARG_SOURCES})
        if(EXISTS "${ARG_DIRECTORY}/${src}")
            list(APPEND RESOLVED_SOURCES "${ARG_DIRECTORY}/${src}")
        endif()
    endforeach()

    if(RESOLVED_SOURCES)
        add_library(${ARG_MMAKE_ID} MODULE ${RESOLVED_SOURCES})
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            PREFIX ""
            SUFFIX ""
            OUTPUT_NAME "${ARG_TARGET}.device"
            LIBRARY_OUTPUT_DIRECTORY "${AROS_DEVS_DIR}"
        )
    endif()
endfunction()

# Macro: aros_add_resource
function(aros_add_resource)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS INCLUDES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    set(RESOLVED_SOURCES "")
    foreach(src ${ARG_SOURCES})
        if(EXISTS "${ARG_DIRECTORY}/${src}")
            list(APPEND RESOLVED_SOURCES "${ARG_DIRECTORY}/${src}")
        endif()
    endforeach()

    if(RESOLVED_SOURCES)
        add_library(${ARG_MMAKE_ID} MODULE ${RESOLVED_SOURCES})
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            PREFIX ""
            SUFFIX ""
            OUTPUT_NAME "${ARG_TARGET}.resource"
            LIBRARY_OUTPUT_DIRECTORY "${AROS_DEVS_DIR}"
        )
    endif()
endfunction()

# Macro: aros_add_hidd
function(aros_add_hidd)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS INCLUDES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    set(RESOLVED_SOURCES "")
    foreach(src ${ARG_SOURCES})
        if(EXISTS "${ARG_DIRECTORY}/${src}")
            list(APPEND RESOLVED_SOURCES "${ARG_DIRECTORY}/${src}")
        endif()
    endforeach()

    if(RESOLVED_SOURCES)
        add_library(${ARG_MMAKE_ID} MODULE ${RESOLVED_SOURCES})
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            PREFIX ""
            SUFFIX ""
            OUTPUT_NAME "${ARG_TARGET}.hidd"
            LIBRARY_OUTPUT_DIRECTORY "${AROS_CLASSES_DIR}"
        )
    endif()
endfunction()

# Macro: aros_add_program
function(aros_add_program)
    set(options)
    set(oneValueArgs TARGET MMAKE_ID DIRECTORY)
    set(multiValueArgs SOURCES LIBS INCLUDES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if(NOT ARG_SOURCES OR NOT ARG_MMAKE_ID)
        return()
    endif()

    set(RESOLVED_SOURCES "")
    foreach(src ${ARG_SOURCES})
        if(EXISTS "${ARG_DIRECTORY}/${src}")
            list(APPEND RESOLVED_SOURCES "${ARG_DIRECTORY}/${src}")
        endif()
    endforeach()

    if(RESOLVED_SOURCES)
        add_executable(${ARG_MMAKE_ID} ${RESOLVED_SOURCES})
        set_target_properties(${ARG_MMAKE_ID} PROPERTIES
            OUTPUT_NAME "${ARG_TARGET}"
            RUNTIME_OUTPUT_DIRECTORY "${AROS_C_DIR}"
        )
    endif()
endfunction()

# Stubs for remaining module types
function(aros_add_datatype)
    aros_add_hidd(${ARGN})
endfunction()

function(aros_add_gadget)
    aros_add_hidd(${ARGN})
endfunction()

function(aros_add_mcc)
    aros_add_hidd(${ARGN})
endfunction()

function(aros_add_linklib)
endfunction()

function(aros_add_custom_target)
endfunction()
