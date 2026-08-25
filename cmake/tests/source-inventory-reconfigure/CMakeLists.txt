cmake_minimum_required(VERSION 3.22)
project(SourceInventoryReconfigureFixture LANGUAGES NONE)

include("${CMAKE_CURRENT_LIST_DIR}/../../SourceInventory.cmake")

set(_destination "${CMAKE_BINARY_DIR}/Ports/fixture")
set(_stamp "${_destination}/.fixture-fetched")
set(_inventory "${_destination}/package/source.c")

set(AROS_FETCH_SCRIPT "${CMAKE_BINARY_DIR}/fake-fetch.sh")
file(WRITE "${AROS_FETCH_SCRIPT}" [=[#!/bin/sh
destination=
while test "$#" -gt 0; do
    if test "$1" = -d; then
        destination=$2
        shift 2
    else
        shift
    fi
done
mkdir -p "$destination/package"
: > "$destination/package/source.c"
]=])
file(CHMOD "${AROS_FETCH_SCRIPT}"
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)

aros_fetch_source_inventory(
    NAME fixture-fetch
    ARCHIVE fixture
    SUFFIXES tar.xz
    ORIGINS cache://
    LOCATION "${CMAKE_BINARY_DIR}/portssources"
    DESTINATION "${_destination}"
    BASE "${_destination}"
    PATCH_ORIGINS ""
    PATCHES "")
if(NOT EXISTS "${_inventory}" OR NOT EXISTS "${_stamp}")
    message(FATAL_ERROR "configure-time source inventory was not materialised")
endif()
file(WRITE "${CMAKE_BINARY_DIR}/reconfigured.txt" "complete source inventory\n")

add_custom_target(fixture)
