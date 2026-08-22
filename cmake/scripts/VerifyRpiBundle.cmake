# Verify (and optionally manifest) an AROS Raspberry Pi 4 debug payload.
#
# Called from RaspberryPi.cmake after staging, so it deliberately performs no
# firmware discovery and makes no network request.

if(NOT DEFINED BUNDLE_DIR OR BUNDLE_DIR STREQUAL "")
    message(FATAL_ERROR "VerifyRpiBundle.cmake requires -DBUNDLE_DIR=<directory>")
endif()

set(_required_files
    aros-aarch64-raspi.img
    aros-aarch64-raspi.debug.elf
    aros-aarch64-raspi.map
    core.debug.elf
    core.map
    aros-aarch64-bsp.rom
    bcm2711-rpi-4-b.dtb
    config.txt)

foreach(_name IN LISTS _required_files)
    set(_path "${BUNDLE_DIR}/${_name}")
    if(NOT EXISTS "${_path}")
        message(FATAL_ERROR "Raspberry Pi bundle is missing ${_name}: ${_path}")
    endif()
    file(SIZE "${_path}" _size)
    if(_size EQUAL 0)
        message(FATAL_ERROR "Raspberry Pi bundle contains an empty ${_name}: ${_path}")
    endif()
endforeach()

function(_rpi_require_elf name)
    file(READ "${BUNDLE_DIR}/${name}" _magic OFFSET 0 LIMIT 4 HEX)
    string(TOLOWER "${_magic}" _magic)
    if(NOT _magic STREQUAL "7f454c46")
        message(FATAL_ERROR "${name} is not an ELF file (expected 7f454c46, got ${_magic})")
    endif()
endfunction()

_rpi_require_elf("aros-aarch64-raspi.debug.elf")
_rpi_require_elf("core.debug.elf")

file(READ "${BUNDLE_DIR}/bcm2711-rpi-4-b.dtb" _dtb_magic OFFSET 0 LIMIT 4 HEX)
string(TOLOWER "${_dtb_magic}" _dtb_magic)
if(NOT _dtb_magic STREQUAL "d00dfeed")
    message(FATAL_ERROR
        "bcm2711-rpi-4-b.dtb does not have the flattened-device-tree magic "
        "d00dfeed (got ${_dtb_magic})")
endif()

file(READ "${BUNDLE_DIR}/config.txt" _config)
set(_config_lines
    "kernel=aros-aarch64-raspi.img"
    "kernel_address=0x80000"
    "initramfs aros-aarch64-bsp.rom 0x00800000"
    "enable_uart=1"
    "arm_64bit=1"
    "gpu_mem=128")
foreach(_line IN LISTS _config_lines)
    string(FIND "${_config}" "${_line}" _found)
    if(_found LESS 0)
        message(FATAL_ERROR "config.txt is missing the required line: ${_line}")
    endif()
endforeach()

set(_manifest "# AROS-NG Raspberry Pi 4 debug payload SHA-256\n")
foreach(_name IN LISTS _required_files)
    file(SHA256 "${BUNDLE_DIR}/${_name}" _sha256)
    string(APPEND _manifest "${_sha256}  ${_name}\n")
endforeach()

set(_manifest_path "${BUNDLE_DIR}/manifest.sha256")
if(WRITE_MANIFEST)
    file(WRITE "${_manifest_path}" "${_manifest}")
elseif(NOT EXISTS "${_manifest_path}")
    message(FATAL_ERROR "Raspberry Pi bundle is missing manifest.sha256")
else()
    file(READ "${_manifest_path}" _actual_manifest)
    if(NOT "${_actual_manifest}" STREQUAL "${_manifest}")
        message(FATAL_ERROR
            "manifest.sha256 does not match the staged Raspberry Pi payload; "
            "run the rpi-artifacts target again")
    endif()
endif()

message(STATUS "Raspberry Pi 4 debug payload verified: ${BUNDLE_DIR}")
