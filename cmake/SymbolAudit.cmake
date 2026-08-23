# =============================================================================
# Symbol audit: does a built module have any chance of loading?
# =============================================================================
#
# Every link here is `ld.lld -r`, partial, so a missing link library or a
# missing stub never fails a link. It produces a relocatable object with
# dangling externals that fails when AROS loads it. A green build therefore says
# nothing about loadability, and until this target existed nothing measured it.
#
# Not part of `all`: it walks every built artefact with llvm-nm, which is only
# meaningful once a build has actually produced them.
#
#   ninja symbol-audit            measure, and fail if a pinned number rose
#   ninja symbol-audit-baseline   re-pin deliberately after an intended change

find_program(AROS_AUDIT_PYTHON3 NAMES python3)
set(AROS_SYMBOL_AUDIT_SCRIPT "${CMAKE_SOURCE_DIR}/scripts/symbols/audit-symbols.py")
# Written by aros-genmodule at configure time. A relocatable module leaves its
# library bases undefined on purpose, so without this list the audit conflates
# "the loader will fill this in" with "nothing provides this": 1882 of 9268
# references were library bases.
set(AROS_SYMBOL_AUDIT_LIBBASES "${CMAKE_BINARY_DIR}/symbol-audit/libbases.txt")
set(AROS_SYMBOL_AUDIT_BASELINE
    "${CMAKE_SOURCE_DIR}/scripts/symbols/baseline-${AROS_TARGET_PLATFORM}-${AROS_TARGET_CPU}.json")

# llvm-nm has to be one that understands the target objects. Searched rather
# than derived: deriving it from CMAKE_C_COMPILER's directory produced
# /usr/bin/llvm-nm, which does not exist, and the failure surfaced as a Python
# traceback from inside the script.
get_filename_component(_cc_dir "${CMAKE_C_COMPILER}" DIRECTORY)
find_program(AROS_AUDIT_NM
    NAMES llvm-nm
    HINTS "${AROS_CROSS_TOOLCHAIN_ROOT}/bin" "${_cc_dir}"
          "/opt/homebrew/opt/llvm/bin" "/usr/local/opt/llvm/bin")
set(_audit_nm "${AROS_AUDIT_NM}")

if(AROS_AUDIT_PYTHON3 AND AROS_AUDIT_NM AND EXISTS "${AROS_SYMBOL_AUDIT_SCRIPT}")
    add_custom_target(symbol-audit
        COMMAND "${AROS_AUDIT_PYTHON3}" -B "${AROS_SYMBOL_AUDIT_SCRIPT}"
                --root "${CMAKE_BINARY_DIR}/SYS"
                --nm "${_audit_nm}"
                --report-dir "${CMAKE_BINARY_DIR}/symbol-audit"
                --libbases "${AROS_SYMBOL_AUDIT_LIBBASES}"
                --baseline "${AROS_SYMBOL_AUDIT_BASELINE}"
        COMMENT "Auditing undefined symbols in the built modules"
        USES_TERMINAL
        VERBATIM)
    add_custom_target(symbol-audit-baseline
        COMMAND "${AROS_AUDIT_PYTHON3}" -B "${AROS_SYMBOL_AUDIT_SCRIPT}"
                --root "${CMAKE_BINARY_DIR}/SYS"
                --nm "${_audit_nm}"
                --report-dir "${CMAKE_BINARY_DIR}/symbol-audit"
                --libbases "${AROS_SYMBOL_AUDIT_LIBBASES}"
                --baseline "${AROS_SYMBOL_AUDIT_BASELINE}"
                --update-baseline
        COMMENT "Re-pinning the symbol audit baseline"
        USES_TERMINAL
        VERBATIM)
else()
    message(STATUS
        "⏭️  AROS-NG: symbol audit unavailable (python3, llvm-nm or the script is missing)")
endif()
