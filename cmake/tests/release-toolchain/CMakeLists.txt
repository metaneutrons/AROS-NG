cmake_minimum_required(VERSION 3.22)
project(release_toolchain_fixture NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../../ToolchainIdentity.cmake")
aros_lock_build_tree_toolchain()

foreach(_required IN ITEMS
        AROS_CROSS_TOOLCHAIN_ROOT AROS_TARGET_PROFILE AROS_TARGET_TRIPLE
        AROS_CROSS_TOOLCHAIN_RELEASE_ID AROS_CROSS_TOOLCHAIN_TREE_SHA256
        CMAKE_C_COMPILER CMAKE_CXX_COMPILER CMAKE_AR CMAKE_RANLIB AROS_LLD_BIN)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
        message(FATAL_ERROR "release toolchain did not define ${_required}")
    endif()
endforeach()
if(NOT AROS_TARGET_PROFILE STREQUAL EXPECTED_PROFILE OR
   NOT AROS_TARGET_TRIPLE STREQUAL EXPECTED_TRIPLE)
    message(FATAL_ERROR
        "release toolchain selected ${AROS_TARGET_PROFILE}/${AROS_TARGET_TRIPLE}, "
        "expected ${EXPECTED_PROFILE}/${EXPECTED_TRIPLE}")
endif()
if(NOT CMAKE_C_COMPILER STREQUAL "${AROS_CROSS_TOOLCHAIN_ROOT}/bin/clang" OR
   NOT CMAKE_CXX_COMPILER STREQUAL "${AROS_CROSS_TOOLCHAIN_ROOT}/bin/clang++" OR
   NOT CMAKE_AR STREQUAL "${AROS_CROSS_TOOLCHAIN_ROOT}/bin/llvm-ar")
    message(FATAL_ERROR "release toolchain did not select prefix-owned tools")
endif()
