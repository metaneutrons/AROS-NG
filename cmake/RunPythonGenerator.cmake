cmake_minimum_required(VERSION 3.22)

foreach(_required IN ITEMS OWNER PYTHON_EXECUTABLE SOURCE_ROOT BUILD_ROOT
        SOURCE_ARCHIVE SOURCE_SHA256 GENERATOR_SCRIPT OUTPUT SOURCE_INPUT_COUNT
        GENERATOR_ARGUMENT_COUNT)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
        message(FATAL_ERROR
            "RunPythonGenerator.cmake requires ${_required}")
    endif()
endforeach()
if(NOT SOURCE_INPUT_COUNT MATCHES "^[0-9]+$" OR
   NOT GENERATOR_ARGUMENT_COUNT MATCHES "^[0-9]+$")
    message(FATAL_ERROR
        "${OWNER}: invalid Python-generator input/argument count")
endif()
string(LENGTH "${SOURCE_SHA256}" _source_sha256_length)
if(NOT _source_sha256_length EQUAL 64 OR
   NOT SOURCE_SHA256 MATCHES "^[0-9A-Fa-f]+$")
    message(FATAL_ERROR
        "${OWNER}: invalid Python-generator source SHA-256")
endif()
string(TOLOWER "${SOURCE_SHA256}" _expected_source_sha256)

cmake_path(ABSOLUTE_PATH SOURCE_ROOT NORMALIZE OUTPUT_VARIABLE _source_root)
cmake_path(ABSOLUTE_PATH BUILD_ROOT NORMALIZE OUTPUT_VARIABLE _build_root)
cmake_path(ABSOLUTE_PATH GENERATOR_SCRIPT NORMALIZE OUTPUT_VARIABLE _script)
cmake_path(ABSOLUTE_PATH OUTPUT NORMALIZE OUTPUT_VARIABLE _output)
cmake_path(ABSOLUTE_PATH SOURCE_ARCHIVE NORMALIZE
    OUTPUT_VARIABLE _source_archive)
cmake_path(IS_PREFIX _source_root "${_script}" NORMALIZE _script_is_owned)
if(NOT _script_is_owned OR _script STREQUAL _source_root)
    message(FATAL_ERROR
        "${OWNER}: generator script escapes the declared source root: ${_script}")
endif()
cmake_path(IS_PREFIX _build_root "${_output}" NORMALIZE _output_is_owned)
if(NOT _output_is_owned OR _output STREQUAL _build_root)
    message(FATAL_ERROR
        "${OWNER}: generator output escapes the declared build root: ${_output}")
endif()

if(NOT EXISTS "${PYTHON_EXECUTABLE}" OR IS_DIRECTORY "${PYTHON_EXECUTABLE}")
    message(FATAL_ERROR
        "${OWNER}: Python 3 interpreter disappeared before generation: ${PYTHON_EXECUTABLE}")
endif()
if(NOT EXISTS "${_source_archive}" OR IS_DIRECTORY "${_source_archive}")
    message(FATAL_ERROR
        "${OWNER}: pinned source archive is missing before Python generation: ${_source_archive}")
endif()
file(SHA256 "${_source_archive}" _actual_source_sha256)
if(NOT _actual_source_sha256 STREQUAL _expected_source_sha256)
    message(FATAL_ERROR
        "${OWNER}: source archive SHA-256 mismatch before Python generation: expected ${_expected_source_sha256}, got ${_actual_source_sha256}")
endif()
if(NOT EXISTS "${_script}" OR IS_DIRECTORY "${_script}")
    message(FATAL_ERROR
        "${OWNER}: Python generator script is missing after fetch: ${_script}")
endif()

if(SOURCE_INPUT_COUNT GREATER 0)
    math(EXPR _last_source_input "${SOURCE_INPUT_COUNT} - 1")
    foreach(_index RANGE 0 ${_last_source_input})
        set(_input_name "SOURCE_INPUT_${_index}")
        if(NOT DEFINED ${_input_name} OR "${${_input_name}}" STREQUAL "")
            message(FATAL_ERROR
                "${OWNER}: missing Python-generator source input declaration ${_index}")
        endif()
        set(_source_input "${${_input_name}}")
        cmake_path(ABSOLUTE_PATH _source_input NORMALIZE
            OUTPUT_VARIABLE _source_input)
        cmake_path(IS_PREFIX _source_root "${_source_input}" NORMALIZE
            _input_is_owned)
        if(NOT _input_is_owned OR _source_input STREQUAL _source_root OR
           NOT EXISTS "${_source_input}" OR IS_DIRECTORY "${_source_input}")
            message(FATAL_ERROR
                "${OWNER}: required source input is missing or outside SOURCE_ROOT: ${_source_input}")
        endif()
    endforeach()
endif()

set(_generator_arguments "")
if(GENERATOR_ARGUMENT_COUNT GREATER 0)
    math(EXPR _last_generator_argument "${GENERATOR_ARGUMENT_COUNT} - 1")
    foreach(_index RANGE 0 ${_last_generator_argument})
        set(_argument_name "GENERATOR_ARGUMENT_${_index}")
        if(NOT DEFINED ${_argument_name})
            message(FATAL_ERROR
                "${OWNER}: missing Python-generator argument declaration ${_index}")
        endif()
        list(APPEND _generator_arguments "${${_argument_name}}")
    endforeach()
endif()

get_filename_component(_output_dir "${_output}" DIRECTORY)
file(MAKE_DIRECTORY "${_output_dir}")
string(SHA256 _temporary_key "${_output}")
set(_temporary "${_output}.${_temporary_key}.tmp")
if(IS_DIRECTORY "${_temporary}")
    message(FATAL_ERROR
        "${OWNER}: Python-generator temporary path is a directory: ${_temporary}")
endif()
file(REMOVE "${_temporary}")

execute_process(
    # Fetched source trees are immutable build inputs.  In particular, imports
    # from beside the generator must not leave __pycache__ files behind there.
    COMMAND "${PYTHON_EXECUTABLE}" -B "${_script}" ${_generator_arguments}
    RESULT_VARIABLE _generator_result
    OUTPUT_FILE "${_temporary}"
    ERROR_VARIABLE _generator_stderr)
if(NOT "${_generator_result}" STREQUAL "0")
    file(REMOVE "${_temporary}")
    message(FATAL_ERROR
        "${OWNER}: Python generator failed for ${_output} with status ${_generator_result}\n${_generator_stderr}")
endif()
if(NOT EXISTS "${_temporary}" OR IS_DIRECTORY "${_temporary}")
    file(REMOVE "${_temporary}")
    message(FATAL_ERROR
        "${OWNER}: Python generator produced no regular output for ${_output}")
endif()

# The temporary file is in the destination directory, so a successful rename
# is an atomic replacement on the supported filesystems. A failed generator or
# rename leaves the last known-good output untouched.
file(RENAME "${_temporary}" "${_output}" RESULT _rename_result)
if(NOT _rename_result STREQUAL "0")
    file(REMOVE "${_temporary}")
    message(FATAL_ERROR
        "${OWNER}: could not atomically install generated output ${_output}: ${_rename_result}")
endif()
