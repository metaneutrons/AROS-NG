cmake_minimum_required(VERSION 3.22)

# Detect and configure hermetic or modern LLVM toolchain if present
if(EXISTS "$ENV{HOME}/.aros/toolchain/bin/clang" AND NOT DEFINED CMAKE_C_COMPILER)
    set(CMAKE_C_COMPILER "$ENV{HOME}/.aros/toolchain/bin/clang")
    set(CMAKE_CXX_COMPILER "$ENV{HOME}/.aros/toolchain/bin/clang++")
elseif(EXISTS "/opt/homebrew/opt/llvm/bin/clang" AND NOT DEFINED CMAKE_C_COMPILER)
    set(CMAKE_C_COMPILER "/opt/homebrew/opt/llvm/bin/clang")
    set(CMAKE_CXX_COMPILER "/opt/homebrew/opt/llvm/bin/clang++")
endif()

project(AROS-NG
    VERSION 0.1.0
    LANGUAGES C CXX ASM
)

message(STATUS "🚀 Initializing AROS-NG (v0.1.0) Build Engine...")
message(STATUS "Target: ${AROS_TARGET_CPU}-${AROS_TARGET_PLATFORM}")

# 1. Compiler Cache Integration (sccache / ccache)
include("${CMAKE_SOURCE_DIR}/cmake/CompilerCache.cmake")

# 2. Target Platform Setup & Core Macros
include("${CMAKE_SOURCE_DIR}/cmake/AROS.cmake")

# 3. Dynamic Target Transpilation
set(TRANSPILER_BIN "${CMAKE_SOURCE_DIR}/tools/aros-tools/target/release/aros-transpiler")
set(GENERATED_TARGETS_CMAKE "${CMAKE_BINARY_DIR}/generated_targets.cmake")

if(EXISTS "${TRANSPILER_BIN}")
    message(STATUS "⚡ AROS-NG: Running Rust aros-transpiler on mmakefile tree...")
    execute_process(
        COMMAND "${TRANSPILER_BIN}"
                "--source-dir" "${CMAKE_SOURCE_DIR}"
                "--output" "${GENERATED_TARGETS_CMAKE}"
        RESULT_VARIABLE TRANSPILER_RES
    )
    if(TRANSPILER_RES EQUAL 0 AND EXISTS "${GENERATED_TARGETS_CMAKE}")
        include("${GENERATED_TARGETS_CMAKE}")
    endif()
endif()

# 4. Report what SDK header staging produced (populated while including
#    generated_targets.cmake above).
get_property(_staged GLOBAL PROPERTY AROS_STAGED_HEADERS)
get_property(_empty GLOBAL PROPERTY AROS_STAGED_RULES_EMPTY)
message(STATUS "📥 AROS-NG: staged ${_staged} SDK header(s); ${_empty} staging rule(s) matched nothing")

# Hand-written header staging rules nobody has accounted for. Treated as a
# warning rather than a note: an unhandled rule means a header silently never
# reaches the SDK, which surfaces far away from its cause.
get_property(_adhoc_unknown GLOBAL PROPERTY AROS_ADHOC_HEADERS_UNKNOWN)
if(_adhoc_unknown)
    list(LENGTH _adhoc_unknown _n_adhoc)
    string(REPLACE ";" "\n    " _adhoc_pretty "${_adhoc_unknown}")
    message(WARNING
        "${_n_adhoc} hand-written header staging rule(s) have no static CMake counterpart.\n"
        "Add an aros_stage_header() call and list the target in "
        "AROS_ADHOC_HEADERS_HANDLED, or record it in "
        "AROS_ADHOC_HEADERS_OUT_OF_SCOPE (both in cmake/AROS.cmake):\n"
        "    ${_adhoc_pretty}")
endif()

# 5. Aggregate target for the third-party fetches declared via %fetch. Not part
#    of `all`: fetching reaches out to the network and stays explicit.
get_property(_fetch_targets GLOBAL PROPERTY AROS_FETCH_TARGETS)
if(_fetch_targets)
    add_custom_target(fetch-ports DEPENDS ${_fetch_targets})
    list(LENGTH _fetch_targets _n_fetch)
    message(STATUS "🌐 AROS-NG: ${_n_fetch} third-party fetch target(s); run 'ninja fetch-ports' to download")
endif()

# 6. Kickstart packages. Must come after generated_targets.cmake, because the
#    package definitions reference the transpiled module targets.
include("${CMAKE_SOURCE_DIR}/cmake/Kickstart.cmake")

message(STATUS "✅ AROS-NG (v0.1.0) Configuration Complete.")
