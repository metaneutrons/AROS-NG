cmake_minimum_required(VERSION 3.22)

project(AROS-NG
    VERSION 0.1.0
    LANGUAGES C CXX ASM
    DESCRIPTION "AROS Research Operating System — Next Generation Build System"
)

message(STATUS "🚀 Initializing AROS-NG (v0.1.0) Build Engine...")
message(STATUS "Target: ${AROS_TARGET_CPU}-${AROS_TARGET_PLATFORM}")

# Include Compiler Caching (sccache / ccache)
include(cmake/CompilerCache.cmake)

# Include Core AROS CMake Engine
include(cmake/AROS.cmake)

# Generate / Refresh dynamic targets via aros-transpiler
set(GENERATED_TARGETS_FILE "${CMAKE_BINARY_DIR}/generated_targets.cmake")
if(NOT EXISTS "${GENERATED_TARGETS_FILE}")
    message(STATUS "⚡ AROS-NG: Running Rust aros-transpiler on mmakefile tree...")
    execute_process(
        COMMAND "${CMAKE_SOURCE_DIR}/tools/aros-tools/target/release/aros-transpiler"
                "--source-dir" "${CMAKE_SOURCE_DIR}"
                "--output" "${GENERATED_TARGETS_FILE}"
        RESULT_VARIABLE TRANSPILER_RES
    )
    if(NOT TRANSPILER_RES EQUAL 0)
        message(FATAL_ERROR "Transpiler failed with code ${TRANSPILER_RES}")
    endif()
endif()

# Include generated targets
if(EXISTS "${GENERATED_TARGETS_FILE}")
    include("${GENERATED_TARGETS_FILE}")
endif()

message(STATUS "✅ AROS-NG (v0.1.0) Configuration Complete.")
