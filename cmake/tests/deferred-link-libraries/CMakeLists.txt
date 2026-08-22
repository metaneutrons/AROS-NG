cmake_minimum_required(VERSION 3.22)
project(DeferredLinkLibraries C)

set(AROS_TARGET_CPU x86_64)
set(AROS_TARGET_PLATFORM pc)
include("${CMAKE_CURRENT_LIST_DIR}/../../AROS.cmake")

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/consumer.c" "int consumer(void) { return 0; }\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/provider.c" "int provider(void) { return 0; }\n")
file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/late.c" "int late(void) { return 0; }\n")

# Reproduce generated_targets.cmake's lexical declaration order: the consumer
# is configured before the archive target named in its resolved LIBS lane.
add_library(consumer STATIC "${CMAKE_CURRENT_BINARY_DIR}/consumer.c")
aros_link_libraries(consumer debug provider vanished)

add_library(provider STATIC "${CMAKE_CURRENT_BINARY_DIR}/provider.c")
set(_provider_include "${CMAKE_CURRENT_BINARY_DIR}/provider-include")
file(MAKE_DIRECTORY "${_provider_include}")
set_property(TARGET provider PROPERTY
    AROS_CLIENT_NAMESPACE_INCLUDES "${_provider_include}")

aros_finalize_link_libraries()

get_target_property(_consumer_links consumer LINK_LIBRARIES)
set(_expected_links "--start-group;provider;--end-group")
if(NOT _consumer_links STREQUAL _expected_links)
    message(FATAL_ERROR
        "forward provider was not bound as one filtered group:\n"
        "expected=${_expected_links}\nactual=${_consumer_links}")
endif()
get_target_property(_consumer_includes consumer INCLUDE_DIRECTORIES)
if(NOT _provider_include IN_LIST _consumer_includes)
    message(FATAL_ERROR
        "forward provider client include was not propagated: ${_consumer_includes}")
endif()

# Calls made after the generated finalizer retain the immediate fast path.
add_library(late STATIC "${CMAKE_CURRENT_BINARY_DIR}/late.c")
aros_link_libraries(late provider)
get_target_property(_late_links late LINK_LIBRARIES)
if(NOT _late_links STREQUAL _expected_links)
    message(FATAL_ERROR
        "already-declared provider did not bind immediately: ${_late_links}")
endif()

# A scheduled directory-end finalizer must be harmless after the explicit
# generated call has emptied the queue.
aros_finalize_link_libraries()
