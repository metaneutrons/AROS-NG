# Run one FlexCat catalog conversion while preserving the legacy warning
# contract. FlexCat returns values below 10 for non-fatal warnings; MetaMake's
# `%build_catalogs` accepts those and fails only on 10 or above.

foreach(_required TOOL DESCRIPTION TRANSLATION OUTPUT)
    if(NOT DEFINED ${_required} OR "${${_required}}" STREQUAL "")
        message(FATAL_ERROR "RunFlexCat.cmake: ${_required} is required")
    endif()
endforeach()

set(_arguments "")
if(DEFINED CONVERSION AND NOT "${CONVERSION}" STREQUAL "")
    list(APPEND _arguments "${CONVERSION}")
endif()
list(APPEND _arguments
    "${DESCRIPTION}"
    "${TRANSLATION}"
    "CATALOG=${OUTPUT}")

execute_process(
    COMMAND "${TOOL}" ${_arguments}
    RESULT_VARIABLE _result)

if(NOT "${_result}" MATCHES "^[0-9]+$")
    message(FATAL_ERROR
        "FlexCat could not create ${OUTPUT}: ${_result}")
endif()
if(_result GREATER_EQUAL 10)
    message(FATAL_ERROR
        "FlexCat failed creating ${OUTPUT} with status ${_result}")
endif()
