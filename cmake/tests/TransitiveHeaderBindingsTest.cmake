cmake_minimum_required(VERSION 3.22)

include("${CMAKE_CURRENT_LIST_DIR}/../TransitiveHeaderBindings.cmake")

set(_fixture "${CMAKE_CURRENT_LIST_DIR}/transitive-header-bindings")
set_property(GLOBAL PROPERTY AROS_STAGED_HEADER_BINDINGS
    "GL/gla.h|gl-owner||${_fixture}/gla.h"
    "GL/gl.h|mesa-owner|0123456789abcdef|${_fixture}/not-fetched/gl.h")

_aros_collect_transitive_header_bindings(
    _owners _hashes "${_fixture}/root.conf")

if(NOT _owners STREQUAL "gl-owner;mesa-owner")
    message(FATAL_ERROR "unexpected transitive owners: ${_owners}")
endif()
if(NOT _hashes STREQUAL "0123456789abcdef")
    message(FATAL_ERROR "unexpected deferred hashes: ${_hashes}")
endif()

message(STATUS "transitive staged-header binding test passed")
