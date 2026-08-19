# AROS-NG SDK Header Bootstrap

function(aros_bootstrap_sdk_includes)
    set(SDK_INC "${CMAKE_BINARY_DIR}/SDK/include")
    file(MAKE_DIRECTORY "${SDK_INC}/aros")

    # 1. Copy core system headers from compiler/include/
    file(COPY "${CMAKE_SOURCE_DIR}/compiler/include/"
         DESTINATION "${SDK_INC}"
    )
    if(EXISTS "${SDK_INC}/exec/execbase.inc")
        file(COPY_FILE "${SDK_INC}/exec/execbase.inc" "${SDK_INC}/exec/execbase.h")
    endif()

    # 2. Copy AROS support headers into aros/
    file(COPY "${CMAKE_SOURCE_DIR}/compiler/arossupport/include/"
         DESTINATION "${SDK_INC}/aros"
    )

    # 3. Copy CRT and POSIX headers (alloca.h, inttypes, etc.)
    if(EXISTS "${CMAKE_SOURCE_DIR}/compiler/crt/posixc/include/")
        file(COPY "${CMAKE_SOURCE_DIR}/compiler/crt/posixc/include/"
             DESTINATION "${SDK_INC}"
        )
    endif()
    if(EXISTS "${CMAKE_SOURCE_DIR}/compiler/crt/stdc/include/")
        file(COPY "${CMAKE_SOURCE_DIR}/compiler/crt/stdc/include/"
             DESTINATION "${SDK_INC}"
        )
    endif()

    # 4. Copy Architecture-specific headers into their expected subdirectories
    if(EXISTS "${CMAKE_SOURCE_DIR}/arch/x86_64-all/include/aros/")
        file(COPY "${CMAKE_SOURCE_DIR}/arch/x86_64-all/include/aros/"
             DESTINATION "${SDK_INC}/aros/x86_64"
        )
    endif()

    if(EXISTS "${CMAKE_SOURCE_DIR}/arch/aarch64-all/include/aros/")
        file(COPY "${CMAKE_SOURCE_DIR}/arch/aarch64-all/include/aros/"
             DESTINATION "${SDK_INC}/aros/aarch64"
        )
    endif()

    if(EXISTS "${CMAKE_SOURCE_DIR}/arch/arm-all/include/aros/")
        file(COPY "${CMAKE_SOURCE_DIR}/arch/arm-all/include/aros/"
             DESTINATION "${SDK_INC}/aros/arm"
        )
    endif()

    # IRQ types header
    if(AROS_TARGET_CPU STREQUAL "x86_64" OR AROS_TARGET_CPU STREQUAL "i386")
        if(EXISTS "${CMAKE_SOURCE_DIR}/arch/i386-all/include/irqtypes.h")
            file(COPY_FILE "${CMAKE_SOURCE_DIR}/arch/i386-all/include/irqtypes.h" "${SDK_INC}/aros/irqtypes.h")
        endif()
    else()
        file(WRITE "${SDK_INC}/aros/irqtypes.h"
"#ifndef AROS_IRQTYPES_H\n#define AROS_IRQTYPES_H\n#define IRQTYPE_STANDARD (1 << 0)\n#endif\n"
        )
    endif()

    # 5. Copy Boost preprocessor headers if available on host system
    if(EXISTS "/opt/homebrew/include/boost/preprocessor")
        file(MAKE_DIRECTORY "${SDK_INC}/boost")
        file(COPY "/opt/homebrew/include/boost/preprocessor" DESTINATION "${SDK_INC}/boost")
    elseif(EXISTS "/usr/include/boost/preprocessor")
        file(MAKE_DIRECTORY "${SDK_INC}/boost")
        file(COPY "/usr/include/boost/preprocessor" DESTINATION "${SDK_INC}/boost")
    endif()

    # 6. Generate aros/config.h
    set(CONFIG_H "${SDK_INC}/aros/config.h")
    file(WRITE "${CONFIG_H}"
"/* AROS-NG v0.1.0: Auto-generated aros/config.h */
#ifndef AROS_CONFIG_H
#define AROS_CONFIG_H

#define AROS_FLAVOUR_NATIVE             1
#define AROS_FLAVOUR_STANDALONE         2
#define AROS_FLAVOUR                    AROS_FLAVOUR_NATIVE
#define AROS_DOS_PACKETS                1
#define AROS_AMIGAOS_COMPLIANCE         1

#define AROS_NOMINAL_WIDTH              640
#define AROS_NOMINAL_HEIGHT             480
#define AROS_NOMINAL_DEPTH              8

#define AROS_SERIAL_DEBUG               1
#define AROS_MODULES_DEBUG              1

#endif /* AROS_CONFIG_H */
")

    # 7. Run pure-Rust aros-genmodule to generate proto/, clib/, defines/ headers from .conf files
    execute_process(
        COMMAND "${CMAKE_SOURCE_DIR}/tools/aros-tools/target/release/aros-genmodule"
                "--scan-dir" "${CMAKE_SOURCE_DIR}"
                "--output-inc" "${SDK_INC}"
        RESULT_VARIABLE GENMODULE_RES
    )

    message(STATUS "✅ AROS-NG SDK include tree populated at: ${SDK_INC}")
endfunction()
