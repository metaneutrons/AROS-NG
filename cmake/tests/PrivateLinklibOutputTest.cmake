cmake_minimum_required(VERSION 3.22)

if(DEFINED ENV{TMPDIR} AND NOT "$ENV{TMPDIR}" STREQUAL "")
    set(_temp_root "$ENV{TMPDIR}")
else()
    set(_temp_root "/tmp")
endif()
string(RANDOM LENGTH 16 ALPHABET 0123456789abcdef _suffix)
set(_root "${_temp_root}/aros-private-linklib-${_suffix}")
set(_source "${CMAKE_CURRENT_LIST_DIR}/private-linklib-output")

function(_configure case expect_success expected_message)
    set(_build "${_root}/${case}")
    execute_process(
        COMMAND "${CMAKE_COMMAND}" -S "${_source}" -B "${_build}" -G Ninja
            "-DPRIVATE_LINKLIB_CASE=${case}"
        RESULT_VARIABLE _result
        OUTPUT_VARIABLE _stdout
        ERROR_VARIABLE _stderr)
    if(expect_success AND NOT _result EQUAL 0)
        message(FATAL_ERROR
            "private-linklib ${case} configure failed (${_result})\n"
            "${_stdout}\n${_stderr}")
    elseif(NOT expect_success AND _result EQUAL 0)
        message(FATAL_ERROR
            "private-linklib ${case} configure unexpectedly succeeded")
    endif()
    if(NOT "${expected_message}" STREQUAL "")
        set(_log "${_stdout}\n${_stderr}")
        string(FIND "${_log}" "${expected_message}" _found)
        if(_found LESS 0)
            message(FATAL_ERROR
                "private-linklib ${case} missed diagnostic '${expected_message}':\n${_log}")
        endif()
    endif()
endfunction()

_configure(success TRUE "")

set(_success_build "${_root}/success")
execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${_success_build}" --target first-provider
    RESULT_VARIABLE _build_result
    OUTPUT_VARIABLE _build_stdout
    ERROR_VARIABLE _build_stderr)
if(NOT _build_result EQUAL 0)
    message(FATAL_ERROR
        "private-linklib build failed (${_build_result})\n"
        "${_build_stdout}\n${_build_stderr}")
endif()
set(_archive "${_success_build}/private/mesa20.0.8/libgallium_i915.a")
if(NOT EXISTS "${_archive}" OR IS_DIRECTORY "${_archive}")
    message(FATAL_ERROR "private archive was not created at ${_archive}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${_success_build}" --target first-provider
    RESULT_VARIABLE _noop_result
    OUTPUT_VARIABLE _noop_stdout
    ERROR_VARIABLE _noop_stderr)
if(NOT _noop_result EQUAL 0)
    message(FATAL_ERROR
        "private-linklib no-op build failed (${_noop_result})\n"
        "${_noop_stdout}\n${_noop_stderr}")
endif()
set(_noop_log "${_noop_stdout}\n${_noop_stderr}")
string(FIND "${_noop_log}" "ninja: no work to do." _noop_found)
if(_noop_found LESS 0)
    message(FATAL_ERROR "second private-linklib build was not a no-op:\n${_noop_log}")
endif()

_configure(collision FALSE "is already owned by first-provider")
_configure(escape FALSE "private linklib output escapes the build tree")
_configure(conflicting-modes FALSE "CANONICAL_OUTPUT and OUTPUT_DIR")
_configure(unsafe-dollar FALSE "private linklib output contains unsafe syntax")
_configure(unsafe-semicolon FALSE "contains unsafe syntax")
_configure(unsafe-backslash FALSE "private linklib output contains unsafe syntax")

file(REMOVE_RECURSE "${_root}")
message(STATUS "private linklib output test passed")
