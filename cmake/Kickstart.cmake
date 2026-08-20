# =============================================================================
# Kickstart package definitions
# =============================================================================
#
# Included from CMakeLists.txt after generated_targets.cmake, so that the
# transpiled module targets referenced below already exist. The packaging
# function itself lives in cmake/AROS.cmake.

# --- aros-base.pkg: architecture-independent core libraries ------------------
# Mirrors rom/mmakefile.src (%make_package kernel-package-base). Names are the
# transpiled mmake IDs, not the AROS module names.
aros_make_package(
    NAME aros-base-pkg
    OUTPUT "${AROS_BOOT_DIR}/aros-base.pkg"
    MODULES
        kernel-aros
        kernel-dos
        kernel-graphics
        kernel-intuition
        kernel-keymap
        kernel-layers
        kernel-oop
        kernel-utility
        workbench-libs-gadtools
        kernel-bootloader
        kernel-dosboot
        kernel-filesystem
        kernel-lddemon
        kernel-console
        kernel-input
        kernel-gameport
        kernel-keyboard
)

# --- aros-bsp.pkg: x86_64-pc board support ----------------------------------
# Mirrors arch/x86_64-pc/boot/mmakefile.src (%make_package kernel-bsp-pc-x86_64).
if(AROS_TARGET_PLATFORM STREQUAL "pc")
    aros_make_package(
        NAME aros-bsp-pkg
        OUTPUT "${AROS_BOOT_ARCH_DIR}/aros-bsp.pkg"
        MODULES
            kernel-expansion
            kernel-processor
            kernel-battclock
            kernel-timer
            kernel-efi
            kernel-hpet
            kernel-log
            kernel-entropy
            kernel-pc-acpica
            kernel-ata
            kernel-ahci
            kernel-nvme
            kernel-virtio
            kernel-hidd-pci
            kernel-hidd-pci-pcipc
            kernel-hidd-i8042
            kernel-hidd-vgagfx
            kernel-hidd-vesagfx
    )
endif()

# Aggregate: everything the bootstrap needs as Multiboot modules.
set(KICKSTART_DEPS "")
foreach(pkg aros-base-pkg aros-bsp-pkg)
    if(TARGET ${pkg})
        list(APPEND KICKSTART_DEPS ${pkg})
    endif()
endforeach()
if(KICKSTART_DEPS)
    add_custom_target(kickstart DEPENDS ${KICKSTART_DEPS})
endif()
