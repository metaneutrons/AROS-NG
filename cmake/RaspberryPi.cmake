# =============================================================================
# Raspberry Pi AArch64 boot payload
# =============================================================================
#
# The mmake-era Pi 4 path has two hand-written links which are intentionally
# outside the generic module graph:
#
#   kernel/resource + exec + task -> core.elf
#   Pi bootstrap + core.bin.o     -> aros-aarch64-raspi.img
#
# The generic CMake transpilation already builds the Pi BSP package.  This
# module brings the two remaining links into the modern graph and stages a
# deterministic *AROS payload* bundle under boot/raspi.  Raspberry Pi firmware
# itself is not part of this target: provisioning it is a separate, pinned
# operation and a normal AROS build must never download it implicitly.

if(NOT (AROS_TARGET_CPU STREQUAL "aarch64" AND
        AROS_TARGET_PLATFORM STREQUAL "raspi"))
    return()
endif()

set(AROS_RPI4_ARTIFACT_DIR "${CMAKE_BINARY_DIR}/boot/raspi"
    CACHE PATH "Directory for the Raspberry Pi 4 AROS debug payload bundle")
set(AROS_RPI4_DTB ""
    CACHE FILEPATH
    "Pinned bcm2711-rpi-4-b.dtb to stage in the Pi 4 payload bundle (not downloaded by CMake)")
set(AROS_RPI4_CORE_KOBJ_DIR ""
    CACHE PATH
    "Legacy raspi-aarch64 KOBJSDIR containing kernel_resource.o, exec_library.o, and task_resource.o")

set(_rpi4_bootstrap_dir "${CMAKE_BINARY_DIR}/rpi4-bootstrap")
set(_rpi4_bundle_dir "${AROS_RPI4_ARTIFACT_DIR}")
set(_rpi4_core_debug_elf "${_rpi4_bootstrap_dir}/core.debug.elf")
set(_rpi4_core_elf "${_rpi4_bootstrap_dir}/core.elf")
set(_rpi4_core_map "${_rpi4_bootstrap_dir}/core.map")
set(_rpi4_core_bin "${_rpi4_bootstrap_dir}/core.bin")
set(_rpi4_core_obj "${_rpi4_bootstrap_dir}/core.bin.o")
set(_rpi4_boot_elf "${_rpi4_bootstrap_dir}/aros-aarch64-raspi.debug.elf")
set(_rpi4_boot_map "${_rpi4_bootstrap_dir}/aros-aarch64-raspi.map")
set(_rpi4_boot_img "${_rpi4_bootstrap_dir}/aros-aarch64-raspi.img")
set(_rpi4_bsp_rom "${CMAKE_BINARY_DIR}/aros-aarch64-bsp.rom")
set(_rpi4_config "${_rpi4_bootstrap_dir}/config.txt")
set(_rpi4_bundle_stamp "${_rpi4_bundle_dir}/.rpi-artifacts.stamp")
set(_rpi4_verify_script "${CMAKE_SOURCE_DIR}/cmake/scripts/VerifyRpiBundle.cmake")

# A normal host objcopy can normally create an ELF binary-input wrapper, but
# llvm-objcopy is deliberately preferred: it is part of the pinned LLVM
# toolchain and understands the AArch64 ELF target on every supported host.
find_program(AROS_RPI_OBJCOPY
    NAMES llvm-objcopy objcopy
    HINTS "$ENV{HOME}/.aros/toolchain/bin"
          "/opt/homebrew/opt/llvm/bin"
          "/opt/homebrew/bin"
    DOC "objcopy used to turn the Pi core ELF into an AArch64 binary object")
find_program(AROS_RPI_STRIP
    NAMES llvm-strip strip
    HINTS "$ENV{HOME}/.aros/toolchain/bin"
          "/opt/homebrew/opt/llvm/bin"
          "/opt/homebrew/bin"
    DOC "strip used for the embedded Raspberry Pi core ELF")

function(_aros_rpi4_unavailable target reason)
    add_custom_target(${target}
        COMMAND "${CMAKE_COMMAND}" -E echo
                "${target} is unavailable for this configuration: ${reason}"
        COMMAND "${CMAKE_COMMAND}" -E echo
                "Set -DAROS_RPI4_DTB=/path/to/bcm2711-rpi-4-b.dtb. In a separate configured legacy raspi-aarch64 build, run: make kernel-raspi-aarch64"
        COMMAND "${CMAKE_COMMAND}" -E echo
                "Then configure with -DAROS_RPI4_CORE_KOBJ_DIR=<legacy-build>/bin/raspi-aarch64/gen/kobjs (same source revision/toolchain). Expected: kernel_resource.o, exec_library.o, task_resource.o; never SYS/Libs/kernel-*.{resource,library}."
        COMMAND "${CMAKE_COMMAND}" -E false
        VERBATIM)
endfunction()

# The CMake transpiler currently builds loadable module ELFs, while the legacy
# Pi core link deliberately consumes the partially linked KOBJs emitted by
# `kernel-raspi-aarch64`.  They are not interchangeable: the KOBJs contain
# genmodule's resident/start/end glue and expose the unprefixed kernel API that
# core.elf needs.  Keep this bridge explicit until CMake models that KOBJ rule.
function(_aros_rpi4_validate_kobj path label out_problem)
    if(NOT EXISTS "${path}")
        set(${out_problem} "missing legacy ${label}: ${path}" PARENT_SCOPE)
        return()
    endif()

    file(SIZE "${path}" _rpi4_kobj_size)
    if(_rpi4_kobj_size LESS 20)
        set(${out_problem} "legacy ${label} is too small to be an AArch64 ELF object: ${path}" PARENT_SCOPE)
        return()
    endif()

    # ELF64 little-endian AArch64 relocatable object:
    # e_ident[EI_CLASS] == 2, e_ident[EI_DATA] == 1,
    # e_type == ET_REL (1), and e_machine == EM_AARCH64 (183 / 0x00b7).
    file(READ "${path}" _rpi4_kobj_header OFFSET 0 LIMIT 20 HEX)
    string(TOLOWER "${_rpi4_kobj_header}" _rpi4_kobj_header)
    string(SUBSTRING "${_rpi4_kobj_header}" 0 8 _rpi4_kobj_magic)
    string(SUBSTRING "${_rpi4_kobj_header}" 8 2 _rpi4_kobj_class)
    string(SUBSTRING "${_rpi4_kobj_header}" 10 2 _rpi4_kobj_data)
    string(SUBSTRING "${_rpi4_kobj_header}" 32 4 _rpi4_kobj_type)
    string(SUBSTRING "${_rpi4_kobj_header}" 36 4 _rpi4_kobj_machine)
    if(NOT _rpi4_kobj_magic STREQUAL "7f454c46" OR
       NOT _rpi4_kobj_class STREQUAL "02" OR
       NOT _rpi4_kobj_data STREQUAL "01" OR
       NOT _rpi4_kobj_type STREQUAL "0100" OR
       NOT _rpi4_kobj_machine STREQUAL "b700")
        set(${out_problem}
            "legacy ${label} is not an ELF64 little-endian AArch64 relocatable object: ${path}"
            PARENT_SCOPE)
        return()
    endif()

    set(${out_problem} "" PARENT_SCOPE)
endfunction()

# Configure must remain useful while bootstrap host tools are absent.  Define
# the public targets anyway, but make an attempt to build them fail with the
# exact missing prerequisite instead of a confusing Ninja rule error.
set(_rpi4_problems "")
if(NOT AROS_LLD_BIN)
    list(APPEND _rpi4_problems "ld.lld was not found")
endif()
if(NOT AROS_RPI_OBJCOPY)
    list(APPEND _rpi4_problems "llvm-objcopy (or a compatible objcopy) was not found")
endif()
if(NOT AROS_RPI_STRIP)
    list(APPEND _rpi4_problems "llvm-strip (or a compatible strip) was not found")
endif()
if(NOT AROS_RPI4_DTB OR NOT EXISTS "${AROS_RPI4_DTB}")
    list(APPEND _rpi4_problems
        "AROS_RPI4_DTB does not name a local, pinned bcm2711-rpi-4-b.dtb")
endif()

set(_rpi4_core_kobjs "")
if(NOT AROS_RPI4_CORE_KOBJ_DIR)
    list(APPEND _rpi4_problems
        "AROS_RPI4_CORE_KOBJ_DIR is not set (requires the legacy raspi-aarch64 KOBJSDIR)")
else()
    get_filename_component(_rpi4_kobj_dir
        "${AROS_RPI4_CORE_KOBJ_DIR}" ABSOLUTE BASE_DIR "${CMAKE_BINARY_DIR}")
    if(NOT IS_DIRECTORY "${_rpi4_kobj_dir}")
        list(APPEND _rpi4_problems
            "AROS_RPI4_CORE_KOBJ_DIR is not a directory: ${_rpi4_kobj_dir}")
    else()
        foreach(_rpi4_kobj_spec IN ITEMS
                "kernel_resource.o|kernel resource KOBJ"
                "exec_library.o|exec library KOBJ"
                "task_resource.o|task resource KOBJ")
            string(REPLACE "|" ";" _rpi4_kobj_parts "${_rpi4_kobj_spec}")
            list(GET _rpi4_kobj_parts 0 _rpi4_kobj_name)
            list(GET _rpi4_kobj_parts 1 _rpi4_kobj_label)
            set(_rpi4_kobj_path "${_rpi4_kobj_dir}/${_rpi4_kobj_name}")
            _aros_rpi4_validate_kobj("${_rpi4_kobj_path}" "${_rpi4_kobj_label}"
                _rpi4_kobj_problem)
            if(_rpi4_kobj_problem)
                list(APPEND _rpi4_problems "${_rpi4_kobj_problem}")
            else()
                list(APPEND _rpi4_core_kobjs "${_rpi4_kobj_path}")
            endif()
        endforeach()
    endif()
endif()

set(_rpi4_required_targets
    kernel-package-raspi-aarch64
    linklibs-arossupport
    linklibs-libinit
    linklibs-stdc-static)
foreach(_rpi4_target IN LISTS _rpi4_required_targets)
    if(NOT TARGET ${_rpi4_target})
        list(APPEND _rpi4_problems "CMake target '${_rpi4_target}' is absent")
    endif()
endforeach()

if(_rpi4_problems)
    list(JOIN _rpi4_problems "; " _rpi4_problem_text)
    message(STATUS "🍓 Raspberry Pi 4 debug payload is deferred: ${_rpi4_problem_text}")

    _aros_rpi4_unavailable(rpi-core-elf "${_rpi4_problem_text}")
    _aros_rpi4_unavailable(rpi-bootstrap-elf "${_rpi4_problem_text}")
    _aros_rpi4_unavailable(rpi-boot-image "${_rpi4_problem_text}")
    _aros_rpi4_unavailable(rpi-bsp-package "${_rpi4_problem_text}")
    _aros_rpi4_unavailable(rpi-artifacts "${_rpi4_problem_text}")
    _aros_rpi4_unavailable(rpi-boot-verify "${_rpi4_problem_text}")
    return()
endif()

# The legacy image uses these sources verbatim.  It is an OBJECT library so
# the final link retains the bootstrap's special order and linker script.
set(_rpi4_bootstrap_sources
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/boot.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/mmu.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/kprintf.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/support.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/vc_mb.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/serialdebug.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/elf.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/devicetree.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/vc_fb.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/bc/vars.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/bc/font8x14.c"
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/bc/screen_fb.c")

add_library(rpi-bootstrap-objects OBJECT ${_rpi4_bootstrap_sources})
target_include_directories(rpi-bootstrap-objects PRIVATE
    "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/include"
    "${CMAKE_SOURCE_DIR}/rom/openfirmware")
target_compile_definitions(rpi-bootstrap-objects PRIVATE
    "TARGET_SECTION_COMMENT=\"\""
    USE_UBOOT)
target_compile_options(rpi-bootstrap-objects PRIVATE
    -O2
    -fno-stack-protector
    -fno-pic)

# The transpiler does not yet model compiler/autoinit/%build_linklib.  The
# core link needs its static archive, so keep this local shim deliberately
# small and remove it once the generic target graph learns that declaration.
set(_rpi4_autoinit_sources
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/functions.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/libraries_nolibs.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/libraries.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/__showerror.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/commandline.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/commandname.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/_programname.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/__stdiowin.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/stdiowin.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/fromwb.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/initexitsets.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/startupvars.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/programentries.c"
    "${CMAKE_SOURCE_DIR}/compiler/autoinit/detach.c")
add_library(rpi-autoinit STATIC ${_rpi4_autoinit_sources})
target_include_directories(rpi-autoinit PRIVATE
    "${CMAKE_SOURCE_DIR}/compiler/autoinit"
    "${CMAKE_SOURCE_DIR}/rom/exec")
target_compile_options(rpi-autoinit PRIVATE
    -fno-stack-protector)

# This is arch/aarch64-native/kernel/mmakefile.src's core.elf rule translated
# to explicit target files.  Its three inputs are the validated legacy KOBJs,
# never the similarly named CMake runtime module executables.
add_custom_command(
    OUTPUT "${_rpi4_core_debug_elf}" "${_rpi4_core_elf}" "${_rpi4_core_map}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_rpi4_bootstrap_dir}"
    COMMAND "${AROS_LLD_BIN}" --emit-relocs
            -Map "${_rpi4_core_map}"
            -T "${CMAKE_SOURCE_DIR}/arch/aarch64-native/kernel/ldscript.lds"
            -o "${_rpi4_core_debug_elf}"
            ${_rpi4_core_kobjs}
            "$<TARGET_FILE:linklibs-arossupport>"
            "$<TARGET_FILE:rpi-autoinit>"
            "$<TARGET_FILE:linklibs-libinit>"
            "$<TARGET_FILE:linklibs-stdc-static>"
    # Preserve the legacy payload behaviour (a stripped core is embedded),
    # while retaining the unstripped ELF next to the image for symbolization.
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_core_debug_elf}" "${_rpi4_core_elf}"
    COMMAND "${AROS_RPI_STRIP}" --strip-debug -R .note -R .comment
            "${_rpi4_core_elf}"
    DEPENDS
            ${_rpi4_core_kobjs}
            linklibs-arossupport
            rpi-autoinit
            linklibs-libinit
            linklibs-stdc-static
            "${CMAKE_SOURCE_DIR}/arch/aarch64-native/kernel/ldscript.lds"
    COMMENT "🍓 Linking Raspberry Pi AArch64 core ELF"
    VERBATIM
    COMMAND_EXPAND_LISTS)
add_custom_target(rpi-core-elf
    DEPENDS "${_rpi4_core_debug_elf}" "${_rpi4_core_elf}" "${_rpi4_core_map}")

# ldscript.lds selects the embedded kernel by the literal `core.bin.o` object
# name, matching the old make rule.  Preserve that name even though it lives
# in a CMake-private working directory.
add_custom_command(
    OUTPUT "${_rpi4_core_bin}" "${_rpi4_core_obj}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_core_elf}" "${_rpi4_core_bin}"
    COMMAND "${AROS_RPI_OBJCOPY}"
            -I binary -O elf64-littleaarch64 -B aarch64
            "${_rpi4_core_bin}" "${_rpi4_core_obj}"
    DEPENDS "${_rpi4_core_elf}"
    COMMENT "🍓 Wrapping Raspberry Pi core ELF for the bootstrap"
    VERBATIM)

add_custom_command(
    OUTPUT "${_rpi4_boot_elf}" "${_rpi4_boot_map}" "${_rpi4_boot_img}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_rpi4_bootstrap_dir}"
    COMMAND "${AROS_LLD_BIN}" --emit-relocs
            -Map "${_rpi4_boot_map}"
            --entry=bootstrap
            --script="${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/ldscript.lds"
            $<TARGET_OBJECTS:rpi-bootstrap-objects>
            "${_rpi4_core_obj}"
            "$<TARGET_FILE:linklibs-stdc-static>"
            -o "${_rpi4_boot_elf}"
    COMMAND "${AROS_RPI_OBJCOPY}" -O binary
            "${_rpi4_boot_elf}" "${_rpi4_boot_img}"
    DEPENDS
            rpi-bootstrap-objects
            "${_rpi4_core_obj}"
            linklibs-stdc-static
            "${CMAKE_SOURCE_DIR}/arch/aarch64-raspi/boot/ldscript.lds"
    COMMENT "🍓 Linking Raspberry Pi 4 AROS bootstrap image"
    VERBATIM
    COMMAND_EXPAND_LISTS)
add_custom_target(rpi-bootstrap-elf
    DEPENDS "${_rpi4_boot_elf}" "${_rpi4_boot_map}")
add_custom_target(rpi-boot-image DEPENDS "${_rpi4_boot_img}")
add_custom_target(rpi-bsp-package DEPENDS kernel-package-raspi-aarch64)

# Keep the content identical to the legacy Pi 4 config.  It intentionally
# names only AROS-owned payload files; start4.elf/fixup4.dat are provisioned
# separately and never fetched during an ordinary build.
file(GENERATE OUTPUT "${_rpi4_config}" CONTENT
"kernel=aros-aarch64-raspi.img\nkernel_address=0x80000\ninitramfs aros-aarch64-bsp.rom 0x00800000\nenable_uart=1\narm_64bit=1\ngpu_mem=128\n")

add_custom_command(
    OUTPUT "${_rpi4_bundle_stamp}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${_rpi4_bundle_dir}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_boot_img}"
            "${_rpi4_bundle_dir}/aros-aarch64-raspi.img"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_boot_elf}"
            "${_rpi4_bundle_dir}/aros-aarch64-raspi.debug.elf"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_boot_map}"
            "${_rpi4_bundle_dir}/aros-aarch64-raspi.map"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_core_debug_elf}"
            "${_rpi4_bundle_dir}/core.debug.elf"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_core_map}"
            "${_rpi4_bundle_dir}/core.map"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_bsp_rom}"
            "${_rpi4_bundle_dir}/aros-aarch64-bsp.rom"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${_rpi4_config}"
            "${_rpi4_bundle_dir}/config.txt"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
            "${AROS_RPI4_DTB}"
            "${_rpi4_bundle_dir}/bcm2711-rpi-4-b.dtb"
    COMMAND "${CMAKE_COMMAND}"
            -DBUNDLE_DIR="${_rpi4_bundle_dir}"
            -DWRITE_MANIFEST=ON
            -P "${_rpi4_verify_script}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${_rpi4_bundle_stamp}"
    DEPENDS
            "${_rpi4_boot_img}"
            "${_rpi4_boot_elf}"
            "${_rpi4_boot_map}"
            "${_rpi4_core_debug_elf}"
            "${_rpi4_core_elf}"
            "${_rpi4_core_map}"
            "${_rpi4_bsp_rom}"
            "${_rpi4_config}"
            "${AROS_RPI4_DTB}"
            "${_rpi4_verify_script}"
    COMMENT "🍓 Staging reproducible Raspberry Pi 4 debug payload"
    VERBATIM)
add_custom_target(rpi-artifacts DEPENDS "${_rpi4_bundle_stamp}")
add_custom_target(rpi-boot-verify
    COMMAND "${CMAKE_COMMAND}"
            -DBUNDLE_DIR="${_rpi4_bundle_dir}"
            -DWRITE_MANIFEST=OFF
            -P "${_rpi4_verify_script}"
    DEPENDS rpi-artifacts
    COMMENT "🍓 Verifying Raspberry Pi 4 debug payload"
    VERBATIM)

message(STATUS "🍓 Raspberry Pi 4 debug payload: rpi-artifacts -> ${_rpi4_bundle_dir}")
