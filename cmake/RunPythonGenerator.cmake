cmake_minimum_required(VERSION 3.22)

foreach(_required IN ITEMS OWNER PYTHON_EXECUTABLE SOURCE_ROOT BUILD_ROOT
        SOURCE_ARCHIVE SOURCE_SHA256 GENERATOR_SCRIPT OUTPUT SOURCE_INPUT_COUNT
        PACKAGE_COUNT GENERATOR_ARGUMENT_COUNT)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
        message(FATAL_ERROR
            "RunPythonGenerator.cmake requires ${_required}")
    endif()
endforeach()
if(NOT SOURCE_INPUT_COUNT MATCHES "^[0-9]+$" OR
   NOT PACKAGE_COUNT MATCHES "^[0-9]+$" OR
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

set(_driver "")
if((DEFINED DRIVER_SCRIPT AND NOT "${DRIVER_SCRIPT}" STREQUAL "") OR
   (DEFINED DRIVER_SHA256 AND NOT "${DRIVER_SHA256}" STREQUAL ""))
    if(NOT DEFINED DRIVER_SCRIPT OR "${DRIVER_SCRIPT}" STREQUAL "" OR
       NOT DEFINED DRIVER_SHA256 OR "${DRIVER_SHA256}" STREQUAL "")
        message(FATAL_ERROR
            "${OWNER}: generator driver path and SHA-256 must be declared together")
    endif()
    string(LENGTH "${DRIVER_SHA256}" _driver_sha256_length)
    if(NOT _driver_sha256_length EQUAL 64 OR
       NOT DRIVER_SHA256 MATCHES "^[0-9A-Fa-f]+$")
        message(FATAL_ERROR
            "${OWNER}: invalid generator driver SHA-256")
    endif()
    string(TOLOWER "${DRIVER_SHA256}" _expected_driver_sha256)
    cmake_path(ABSOLUTE_PATH DRIVER_SCRIPT NORMALIZE OUTPUT_VARIABLE _driver)
    if(NOT EXISTS "${_driver}" OR IS_DIRECTORY "${_driver}")
        message(FATAL_ERROR
            "${OWNER}: pinned generator driver is missing: ${_driver}")
    endif()
    file(SHA256 "${_driver}" _actual_driver_sha256)
    if(NOT _actual_driver_sha256 STREQUAL _expected_driver_sha256)
        message(FATAL_ERROR
            "${OWNER}: generator driver SHA-256 mismatch: expected ${_expected_driver_sha256}, got ${_actual_driver_sha256}")
    endif()
    foreach(_tool IN ITEMS FLEX_EXECUTABLE BISON_EXECUTABLE)
        if(NOT DEFINED ${_tool} OR "${${_tool}}" STREQUAL "" OR
           NOT EXISTS "${${_tool}}" OR IS_DIRECTORY "${${_tool}}")
            message(FATAL_ERROR
                "${OWNER}: pinned host tool ${_tool} is missing")
        endif()
    endforeach()
endif()

set(_package_python_paths "")
if(PACKAGE_COUNT GREATER 0)
    math(EXPR _last_package "${PACKAGE_COUNT} - 1")
    foreach(_index RANGE 0 ${_last_package})
        foreach(_field IN ITEMS SOURCE_ROOT SOURCE_ARCHIVE SOURCE_SHA256
                PYTHON_PATH)
            set(_field_name "PACKAGE_${_field}_${_index}")
            if(NOT DEFINED ${_field_name} OR "${${_field_name}}" STREQUAL "")
                message(FATAL_ERROR
                    "${OWNER}: missing Python package ${_field} declaration ${_index}")
            endif()
        endforeach()
        set(_package_root_name "PACKAGE_SOURCE_ROOT_${_index}")
        set(_package_archive_name "PACKAGE_SOURCE_ARCHIVE_${_index}")
        set(_package_sha256_name "PACKAGE_SOURCE_SHA256_${_index}")
        set(_python_path_name "PACKAGE_PYTHON_PATH_${_index}")
        set(_package_root "${${_package_root_name}}")
        set(_package_archive "${${_package_archive_name}}")
        set(_package_sha256 "${${_package_sha256_name}}")
        set(_python_path "${${_python_path_name}}")
        cmake_path(ABSOLUTE_PATH _package_root NORMALIZE
            OUTPUT_VARIABLE _package_root)
        cmake_path(ABSOLUTE_PATH _package_archive NORMALIZE
            OUTPUT_VARIABLE _package_archive)
        cmake_path(ABSOLUTE_PATH _python_path NORMALIZE
            OUTPUT_VARIABLE _python_path)
        cmake_path(IS_PREFIX _package_root "${_python_path}" NORMALIZE
            _python_path_is_owned)
        if(NOT EXISTS "${_package_root}" OR NOT IS_DIRECTORY "${_package_root}" OR
           NOT _python_path_is_owned OR NOT EXISTS "${_python_path}" OR
           NOT IS_DIRECTORY "${_python_path}")
            message(FATAL_ERROR
                "${OWNER}: Python package or import root is missing after fetch: ${_package_root} / ${_python_path}")
        endif()
        if(NOT EXISTS "${_package_archive}" OR IS_DIRECTORY "${_package_archive}")
            message(FATAL_ERROR
                "${OWNER}: pinned Python package archive is missing: ${_package_archive}")
        endif()
        string(LENGTH "${_package_sha256}" _package_sha256_length)
        if(NOT _package_sha256_length EQUAL 64 OR
           NOT _package_sha256 MATCHES "^[0-9A-Fa-f]+$")
            message(FATAL_ERROR
                "${OWNER}: invalid Python package SHA-256 at index ${_index}")
        endif()
        string(TOLOWER "${_package_sha256}" _expected_package_sha256)
        file(SHA256 "${_package_archive}" _actual_package_sha256)
        if(NOT _actual_package_sha256 STREQUAL _expected_package_sha256)
            message(FATAL_ERROR
                "${OWNER}: Python package archive SHA-256 mismatch at index ${_index}: expected ${_expected_package_sha256}, got ${_actual_package_sha256}")
        endif()
        list(APPEND _package_python_paths "${_python_path}")
    endforeach()
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

cmake_path(CONVERT "${_package_python_paths}" TO_NATIVE_PATH_LIST
    _native_python_path)
set(_generator_environment
    "PYTHONDONTWRITEBYTECODE=1"
    "PYTHONHASHSEED=0"
    "PYTHONNOUSERSITE=1"
    "PYTHONPATH=${_native_python_path}")
if(_driver)
    list(APPEND _generator_environment
        "AROS_FLEX_EXECUTABLE=${FLEX_EXECUTABLE}"
        "AROS_BISON_EXECUTABLE=${BISON_EXECUTABLE}")
    set(_generator_command
        "${PYTHON_EXECUTABLE}" -s -B "${_driver}"
        "${_source_root}" "${_build_root}" "${_script}" "${_output}"
        ${_generator_arguments})
else()
    set(_generator_command
        "${PYTHON_EXECUTABLE}" -s -B "${_script}" ${_generator_arguments})
endif()

execute_process(
    # Fetched source trees are immutable build inputs.  In particular, imports
    # from beside the generator must not leave __pycache__ files behind there.
    COMMAND "${CMAKE_COMMAND}" -E env ${_generator_environment}
        ${_generator_command}
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
