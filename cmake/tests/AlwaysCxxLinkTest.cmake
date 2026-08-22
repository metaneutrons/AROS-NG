cmake_minimum_required(VERSION 3.22)

if(DEFINED ENV{TMPDIR} AND NOT "$ENV{TMPDIR}" STREQUAL "")
    set(_temp_root "$ENV{TMPDIR}")
else()
    set(_temp_root "/tmp")
endif()
string(RANDOM LENGTH 16 ALPHABET 0123456789abcdef _suffix)
set(_build "${_temp_root}/aros-always-cxx-link-${_suffix}")
set(_source "${CMAKE_CURRENT_LIST_DIR}/always-cxx-link")

foreach(_mode IN ITEMS development locked)
    if(_mode STREQUAL "locked")
        set(_locked ON)
    else()
        set(_locked OFF)
    endif()
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -S "${_source}"
            -B "${_build}-${_mode}" -G Ninja
            "-DTEST_LOCKED_TOOLCHAIN=${_locked}"
        RESULT_VARIABLE _result
        OUTPUT_VARIABLE _stdout
        ERROR_VARIABLE _stderr)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR
            "always-cxx-link ${_mode} fixture configure failed (${_result})\n"
            "${_stdout}\n${_stderr}")
    endif()
endforeach()

file(REMOVE_RECURSE "${_build}-development" "${_build}-locked")
message(STATUS "always C++ linker contract test passed")
