include_guard(GLOBAL)
include(CMakeParseArguments)

# A few upstream modules derive their complete source inventory with a Make
# wildcard below PORTSDIR. The transpiler reports the exact owning fetches on
# its first cold pass; CMake materialises only those archives and runs the
# transpiler again before generated_targets.cmake is included.
function(aros_fetch_source_inventory)
    set(oneValueArgs NAME ARCHIVE SUFFIXES ORIGINS LOCATION DESTINATION BASE
        PATCH_ORIGINS PATCHES)
    cmake_parse_arguments(SI "" "${oneValueArgs}" "" ${ARGN})
    if(SI_UNPARSED_ARGUMENTS OR NOT SI_NAME OR NOT SI_ARCHIVE OR
       NOT SI_DESTINATION OR NOT AROS_FETCH_SCRIPT)
        message(FATAL_ERROR
            "aros_fetch_source_inventory received an incomplete fetch declaration")
    endif()
    set(_location "${SI_LOCATION}")
    if(NOT _location)
        set(_location "${SI_DESTINATION}")
    endif()
    set(_base "${SI_BASE}")
    if(NOT _base)
        set(_base "${SI_DESTINATION}")
    endif()
    file(MAKE_DIRECTORY "${_location}" "${_base}" "${SI_DESTINATION}")
    message(STATUS
        "🌐 AROS-NG: fetching ${SI_NAME} to determine its source inventory")
    execute_process(
        COMMAND "${AROS_FETCH_SCRIPT}"
            -ao "${SI_ORIGINS}"
            -a "${SI_ARCHIVE}"
            -s "${SI_SUFFIXES}"
            -l "${_location}"
            -d "${SI_DESTINATION}"
            -b "${_base}"
            -po "${SI_PATCH_ORIGINS}"
            -p "${SI_PATCHES}"
        RESULT_VARIABLE _result
        ERROR_VARIABLE _error)
    if(NOT _result EQUAL 0)
        message(FATAL_ERROR
            "${SI_NAME}: configure-time source-inventory fetch failed "
            "(${_result})\n${_error}")
    endif()
    file(TOUCH "${SI_DESTINATION}/.${SI_ARCHIVE}-fetched")
endfunction()
