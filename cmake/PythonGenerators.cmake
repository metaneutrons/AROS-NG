include(CMakeParseArguments)

# aros_bind_python_output_consumers(
#     OWNER <python-generator-owner>
#     CONSUMERS <compile-targets...>)
#
# Binds an already declared Python-output owner to compile targets. This is a
# separate operation because generated sources must be registered before a
# concrete target is declared, while that target can only be named as a
# dependency afterwards.
function(aros_bind_python_output_consumers)
    set(oneValueArgs OWNER)
    set(multiValueArgs CONSUMERS)
    cmake_parse_arguments(PB "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if(PB_UNPARSED_ARGUMENTS OR PB_KEYWORDS_MISSING_VALUES OR
       NOT PB_OWNER OR NOT PB_CONSUMERS)
        message(FATAL_ERROR
            "aros_bind_python_output_consumers requires OWNER and CONSUMERS")
    endif()
    if(NOT PB_OWNER MATCHES "^[A-Za-z0-9_.+-]+$" OR
       NOT TARGET "${PB_OWNER}")
        message(FATAL_ERROR
            "${PB_OWNER}: missing Python-generator owner target")
    endif()
    get_target_property(_is_python_owner "${PB_OWNER}"
        AROS_PYTHON_OUTPUT_OWNER)
    if(NOT _is_python_owner)
        message(FATAL_ERROR
            "${PB_OWNER}: target is not a Python-generator owner")
    endif()

    list(REMOVE_DUPLICATES PB_CONSUMERS)
    foreach(_consumer IN LISTS PB_CONSUMERS)
        if(NOT TARGET "${_consumer}")
            message(FATAL_ERROR
                "${PB_OWNER}: missing Python-generator consumer ${_consumer}")
        endif()
        get_target_property(_consumer_type "${_consumer}" TYPE)
        if(NOT _consumer_type MATCHES
           "^(EXECUTABLE|STATIC_LIBRARY|SHARED_LIBRARY|MODULE_LIBRARY|OBJECT_LIBRARY)$")
            message(FATAL_ERROR
                "${PB_OWNER}: Python-generator consumer ${_consumer} does not compile")
        endif()
        add_dependencies("${_consumer}" "${PB_OWNER}")
    endforeach()
endfunction()

# aros_generate_python_outputs(
#     OWNER <target>
#     SOURCE_ROOT <fetched-source-root>
#     BUILD_ROOT <private-generated-root>
#     FETCH_TARGET <fetch-owner>
#     SOURCE_ARCHIVE <downloaded-archive>
#     SOURCE_SHA256 <digest>
#     [SOURCE_INPUTS <source-relative-files...>]
#     [CONSUMERS <compile-targets...>]
#     JOB
#       SCRIPT <source-relative-python-file>
#       OUTPUT <build-relative-product>
#       [ARGUMENTS <generator-arguments...>]
#     [JOB ...])
#
# Declares one output-tracked command per Python/stdout generator and groups all
# products under OWNER.  The source scripts and shared inputs are side effects
# of FETCH_TARGET, so the fetch completion stamp is the only file dependency:
# naming not-yet-unpacked files directly would make a fresh Ninja graph fail
# before the fetch rule can create them.  The runner verifies those inputs once
# the stamp is current and replaces each product only after Python succeeds.
function(aros_generate_python_outputs)
    set(_raw_arguments ${ARGN})
    list(FIND _raw_arguments "JOB" _first_job)
    if(_first_job LESS 0)
        message(FATAL_ERROR
            "aros_generate_python_outputs requires at least one JOB")
    endif()

    list(SUBLIST _raw_arguments 0 ${_first_job} _common_arguments)
    set(oneValueArgs OWNER SOURCE_ROOT BUILD_ROOT FETCH_TARGET
        SOURCE_ARCHIVE SOURCE_SHA256)
    set(multiValueArgs SOURCE_INPUTS CONSUMERS)
    cmake_parse_arguments(PG "" "${oneValueArgs}" "${multiValueArgs}"
        ${_common_arguments})
    if(PG_UNPARSED_ARGUMENTS OR PG_KEYWORDS_MISSING_VALUES)
        message(FATAL_ERROR
            "aros_generate_python_outputs received malformed common arguments")
    endif()
    foreach(_required IN ITEMS OWNER SOURCE_ROOT BUILD_ROOT FETCH_TARGET
            SOURCE_ARCHIVE SOURCE_SHA256)
        if(NOT PG_${_required})
            message(FATAL_ERROR
                "aros_generate_python_outputs requires ${_required}")
        endif()
    endforeach()
    foreach(_name IN ITEMS PG_OWNER PG_FETCH_TARGET)
        if(NOT "${${_name}}" MATCHES "^[A-Za-z0-9_.+-]+$")
            message(FATAL_ERROR
                "${PG_OWNER}: invalid Python-generator target name '${${_name}}'")
        endif()
    endforeach()
    if(TARGET "${PG_OWNER}")
        message(FATAL_ERROR
            "${PG_OWNER}: Python-generator owner target was already declared")
    endif()
    if(NOT TARGET "${PG_FETCH_TARGET}")
        message(FATAL_ERROR
            "${PG_OWNER}: missing Python-generator fetch target ${PG_FETCH_TARGET}")
    endif()

    string(LENGTH "${PG_SOURCE_SHA256}" _source_sha256_length)
    if(NOT _source_sha256_length EQUAL 64 OR
       NOT PG_SOURCE_SHA256 MATCHES "^[0-9A-Fa-f]+$")
        message(FATAL_ERROR
            "${PG_OWNER}: invalid Python-generator source SHA-256")
    endif()
    string(TOLOWER "${PG_SOURCE_SHA256}" _source_sha256)

    get_property(_fetch_destination TARGET "${PG_FETCH_TARGET}"
        PROPERTY AROS_FETCH_DESTINATION)
    get_property(_fetch_stamp TARGET "${PG_FETCH_TARGET}"
        PROPERTY AROS_FETCH_COMPLETION_STAMP)
    if(NOT _fetch_destination OR NOT _fetch_stamp)
        message(FATAL_ERROR
            "${PG_OWNER}: ${PG_FETCH_TARGET} is not a complete fetch owner")
    endif()

    # Python is a host tool even in a cross build. Resolve and execute it while
    # configuring, so a missing or unusable interpreter never becomes a late,
    # opaque custom-command failure.
    find_package(Python3 COMPONENTS Interpreter QUIET)
    if(NOT Python3_Interpreter_FOUND OR NOT Python3_EXECUTABLE)
        message(FATAL_ERROR
            "${PG_OWNER}: a working Python 3 interpreter is required; install python3 or set Python3_EXECUTABLE")
    endif()
    execute_process(
        COMMAND "${Python3_EXECUTABLE}" -c
            "import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)"
        RESULT_VARIABLE _python_probe_result
        OUTPUT_QUIET
        ERROR_QUIET
        TIMEOUT 10)
    if(NOT "${_python_probe_result}" STREQUAL "0")
        message(FATAL_ERROR
            "${PG_OWNER}: Python3_EXECUTABLE is not a usable Python 3 interpreter: ${Python3_EXECUTABLE}")
    endif()

    foreach(_path_var IN ITEMS PG_SOURCE_ROOT PG_BUILD_ROOT PG_SOURCE_ARCHIVE
            _fetch_destination _fetch_stamp)
        if("${${_path_var}}" MATCHES "[;\"$\\\r\n]")
            message(FATAL_ERROR
                "${PG_OWNER}: unsafe Python-generator path '${${_path_var}}'")
        endif()
    endforeach()
    cmake_path(ABSOLUTE_PATH _fetch_destination
        BASE_DIRECTORY "${CMAKE_BINARY_DIR}" NORMALIZE
        OUTPUT_VARIABLE _fetch_destination)
    cmake_path(ABSOLUTE_PATH PG_SOURCE_ROOT
        BASE_DIRECTORY "${_fetch_destination}" NORMALIZE
        OUTPUT_VARIABLE _source_root)
    cmake_path(IS_PREFIX _fetch_destination "${_source_root}" NORMALIZE
        _source_is_fetched)
    if(NOT _source_is_fetched OR _source_root STREQUAL _fetch_destination)
        message(FATAL_ERROR
            "${PG_OWNER}: SOURCE_ROOT must be a private child of the fetch destination: ${_source_root}")
    endif()

    cmake_path(ABSOLUTE_PATH AROS_PORTS_SOURCE_DIR NORMALIZE
        OUTPUT_VARIABLE _archive_root)
    cmake_path(ABSOLUTE_PATH PG_SOURCE_ARCHIVE
        BASE_DIRECTORY "${_archive_root}" NORMALIZE
        OUTPUT_VARIABLE _source_archive)
    cmake_path(IS_PREFIX _archive_root "${_source_archive}" NORMALIZE
        _archive_is_cached)
    if(NOT _archive_is_cached OR _source_archive STREQUAL _archive_root)
        message(FATAL_ERROR
            "${PG_OWNER}: SOURCE_ARCHIVE must be a file below AROS_PORTS_SOURCE_DIR: ${_source_archive}")
    endif()

    cmake_path(ABSOLUTE_PATH CMAKE_BINARY_DIR NORMALIZE
        OUTPUT_VARIABLE _binary_root)
    set(_generated_root "${_binary_root}/gen")
    cmake_path(NORMAL_PATH _generated_root)
    cmake_path(ABSOLUTE_PATH PG_BUILD_ROOT
        BASE_DIRECTORY "${_generated_root}" NORMALIZE
        OUTPUT_VARIABLE _build_root)
    cmake_path(IS_PREFIX _generated_root "${_build_root}" NORMALIZE
        _build_is_generated)
    if(NOT _build_is_generated OR _build_root STREQUAL _generated_root)
        message(FATAL_ERROR
            "${PG_OWNER}: BUILD_ROOT must be a private child of ${_generated_root}: ${_build_root}")
    endif()
    cmake_path(IS_PREFIX _source_root "${_build_root}" NORMALIZE
        _source_contains_build)
    cmake_path(IS_PREFIX _build_root "${_source_root}" NORMALIZE
        _build_contains_source)
    if(_source_contains_build OR _build_contains_source)
        message(FATAL_ERROR
            "${PG_OWNER}: SOURCE_ROOT and BUILD_ROOT must not overlap")
    endif()

    # Keep fetched compile sources stable across cold and warm configures. On a
    # cold configure they need proxy translation units because the archive is
    # still absent; after fetch, resolving the same stems directly would change
    # object identities and archive members merely because CMake was rerun.
    get_property(_stable_source_roots GLOBAL PROPERTY
        AROS_STABLE_PORT_SOURCE_ROOTS)
    list(APPEND _stable_source_roots "${_source_root}")
    list(REMOVE_DUPLICATES _stable_source_roots)
    set_property(GLOBAL PROPERTY AROS_STABLE_PORT_SOURCE_ROOTS
        "${_stable_source_roots}")

    set(_source_inputs "")
    foreach(_raw_input IN LISTS PG_SOURCE_INPUTS)
        if("${_raw_input}" MATCHES "[;\"$\\\r\n]")
            message(FATAL_ERROR
                "${PG_OWNER}: unsafe Python-generator source input '${_raw_input}'")
        endif()
        set(_source_input "${_raw_input}")
        cmake_path(ABSOLUTE_PATH _source_input
            BASE_DIRECTORY "${_source_root}" NORMALIZE
            OUTPUT_VARIABLE _source_input)
        cmake_path(IS_PREFIX _source_root "${_source_input}" NORMALIZE
            _input_is_owned)
        if(NOT _input_is_owned OR _source_input STREQUAL _source_root)
            message(FATAL_ERROR
                "${PG_OWNER}: SOURCE_INPUT escapes SOURCE_ROOT: ${_source_input}")
        endif()
        list(APPEND _source_inputs "${_source_input}")
    endforeach()
    list(REMOVE_DUPLICATES _source_inputs)

    set(_runner "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/RunPythonGenerator.cmake")
    list(LENGTH _source_inputs _source_input_count)
    set(_source_input_definitions
        "-DSOURCE_INPUT_COUNT=${_source_input_count}")
    if(_source_input_count GREATER 0)
        math(EXPR _last_source_input "${_source_input_count} - 1")
        foreach(_index RANGE 0 ${_last_source_input})
            list(GET _source_inputs ${_index} _source_input)
            list(APPEND _source_input_definitions
                "-DSOURCE_INPUT_${_index}=${_source_input}")
        endforeach()
    endif()

    set(_outputs "")
    list(LENGTH _raw_arguments _argument_count)
    set(_job_marker ${_first_job})
    while(_job_marker LESS _argument_count)
        math(EXPR _job_start "${_job_marker} + 1")
        if(_job_start GREATER_EQUAL _argument_count)
            message(FATAL_ERROR
                "${PG_OWNER}: empty Python-generator JOB")
        endif()
        list(SUBLIST _raw_arguments ${_job_start} -1 _job_tail)
        list(FIND _job_tail "JOB" _relative_next_job)
        if(_relative_next_job LESS 0)
            math(EXPR _job_length "${_argument_count} - ${_job_start}")
            set(_next_job ${_argument_count})
        else()
            set(_job_length ${_relative_next_job})
            math(EXPR _next_job "${_job_start} + ${_relative_next_job}")
        endif()
        if(_job_length EQUAL 0)
            message(FATAL_ERROR
                "${PG_OWNER}: empty Python-generator JOB")
        endif()
        list(SUBLIST _raw_arguments ${_job_start} ${_job_length}
            _job_arguments)
        cmake_parse_arguments(PJ "" "SCRIPT;OUTPUT" "ARGUMENTS"
            ${_job_arguments})
        if(PJ_UNPARSED_ARGUMENTS OR PJ_KEYWORDS_MISSING_VALUES OR
           NOT PJ_SCRIPT OR NOT PJ_OUTPUT)
            message(FATAL_ERROR
                "${PG_OWNER}: malformed Python-generator JOB; SCRIPT and OUTPUT are required")
        endif()

        foreach(_path_var IN ITEMS PJ_SCRIPT PJ_OUTPUT)
            if("${${_path_var}}" MATCHES "[;\"$\\\r\n]")
                message(FATAL_ERROR
                    "${PG_OWNER}: unsafe Python-generator job path '${${_path_var}}'")
            endif()
        endforeach()
        set(_script "${PJ_SCRIPT}")
        cmake_path(ABSOLUTE_PATH _script
            BASE_DIRECTORY "${_source_root}" NORMALIZE
            OUTPUT_VARIABLE _script)
        cmake_path(IS_PREFIX _source_root "${_script}" NORMALIZE
            _script_is_owned)
        if(NOT _script_is_owned OR _script STREQUAL _source_root)
            message(FATAL_ERROR
                "${PG_OWNER}: generator SCRIPT escapes SOURCE_ROOT: ${_script}")
        endif()

        set(_output "${PJ_OUTPUT}")
        cmake_path(ABSOLUTE_PATH _output
            BASE_DIRECTORY "${_build_root}" NORMALIZE
            OUTPUT_VARIABLE _output)
        cmake_path(IS_PREFIX _build_root "${_output}" NORMALIZE
            _output_is_owned)
        if(NOT _output_is_owned OR _output STREQUAL _build_root)
            message(FATAL_ERROR
                "${PG_OWNER}: generator OUTPUT escapes BUILD_ROOT: ${_output}")
        endif()
        if(_output IN_LIST _outputs)
            message(FATAL_ERROR
                "${PG_OWNER}: duplicate Python-generator OUTPUT: ${_output}")
        endif()
        string(SHA256 _output_key "${_output}")
        get_property(_previous_owner GLOBAL PROPERTY
            "AROS_PYTHON_OUTPUT_OWNER_${_output_key}")
        if(_previous_owner)
            message(FATAL_ERROR
                "${PG_OWNER}: ${_output} is already owned by ${_previous_owner}")
        endif()

        foreach(_argument IN LISTS PJ_ARGUMENTS)
            if("${_argument}" MATCHES "[;$\\\r\n]")
                message(FATAL_ERROR
                    "${PG_OWNER}: unsafe Python-generator argument '${_argument}'")
            endif()
        endforeach()

        list(LENGTH PJ_ARGUMENTS _generator_argument_count)
        set(_generator_argument_definitions
            "-DGENERATOR_ARGUMENT_COUNT=${_generator_argument_count}")
        if(_generator_argument_count GREATER 0)
            math(EXPR _last_generator_argument
                "${_generator_argument_count} - 1")
            foreach(_index RANGE 0 ${_last_generator_argument})
                list(GET PJ_ARGUMENTS ${_index} _argument)
                list(APPEND _generator_argument_definitions
                    "-DGENERATOR_ARGUMENT_${_index}=${_argument}")
            endforeach()
        endif()

        add_custom_command(
            OUTPUT "${_output}"
            COMMAND "${CMAKE_COMMAND}"
                "-DOWNER=${PG_OWNER}"
                "-DPYTHON_EXECUTABLE=${Python3_EXECUTABLE}"
                "-DSOURCE_ROOT=${_source_root}"
                "-DBUILD_ROOT=${_build_root}"
                "-DSOURCE_ARCHIVE=${_source_archive}"
                "-DSOURCE_SHA256=${_source_sha256}"
                "-DGENERATOR_SCRIPT=${_script}"
                "-DOUTPUT=${_output}"
                ${_source_input_definitions}
                ${_generator_argument_definitions}
                -P "${_runner}"
            DEPENDS "${_fetch_stamp}" "${_runner}"
            COMMENT "Generating ${_output} with Python"
            VERBATIM)

        list(APPEND _outputs "${_output}")
        set_property(GLOBAL PROPERTY
            "AROS_PYTHON_OUTPUT_OWNER_${_output_key}" "${PG_OWNER}")
        set(_job_marker ${_next_job})
    endwhile()

    add_custom_target("${PG_OWNER}" DEPENDS ${_outputs})
    add_dependencies("${PG_OWNER}" "${PG_FETCH_TARGET}")
    set_property(TARGET "${PG_OWNER}" PROPERTY
        AROS_PYTHON_OUTPUT_OWNER TRUE)
    set_property(TARGET "${PG_OWNER}" PROPERTY
        AROS_PYTHON_OUTPUTS "${_outputs}")

    if(PG_CONSUMERS)
        aros_bind_python_output_consumers(
            OWNER "${PG_OWNER}"
            CONSUMERS ${PG_CONSUMERS})
    endif()
endfunction()
