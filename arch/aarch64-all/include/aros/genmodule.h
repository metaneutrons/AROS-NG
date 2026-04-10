/*
    Copyright (C) 2016-2026, The AROS Development Team. All rights reserved.

    Desc: genmodule.h include file for aarch64-le systems
*/

#ifndef AROS_AARCH64_GENMODULE_H
#define AROS_AARCH64_GENMODULE_H

#include <exec/execbase.h>

/*
    AArch64 calling convention (AAPCS64):
    - x0-x7:  argument/result registers (caller-saved)
    - x8:     indirect result location register
    - x9-x15: temporary registers (caller-saved)
    - x16-x17: intra-procedure-call scratch (ip0/ip1, caller-saved)
    - x18:    platform register (reserved)
    - x19-x28: callee-saved registers
    - x29:    frame pointer (FP)
    - x30:    link register (LR)
    - sp:     stack pointer (must be 16-byte aligned)

    We use x16 (ip0) to hold the library base pointer, matching the
    ARM32 convention of using r12 (ip). x17 (ip1) is used as a
    secondary scratch for loading the function address from the
    jump table.
*/

/******************* Linklib Side Thunks ******************/

/* Macro: AROS_GM_LIBFUNCSTUB(functionname, libbasename, lvo)
   This macro will generate code for a stub function for
   the function 'functionname' of library with libbase
   'libbasename' and 'lvo' number of the function in the
   vector table. lvo has to be a constant value (not a variable)

   AArch64 sequence:
     ldr x16, 1f          // x16 = &libbasename
     ldr x16, [x16]       // x16 = libbasename (dereference pointer)
     ldr x17, [x16, #off] // x17 = function vector at negative offset
     br  x17              // tail-call to library function
     1: .quad libbasename  // literal pool: address of libbase global
*/
#define __AROS_GM_LIBFUNCSTUB(fname, libbasename, lvo)                     \
    void __ ## fname ## _ ## libbasename ## _wrapper(void)              \
    {                                                                   \
        asm volatile(                                                   \
            ".weak " #fname "\n"                                        \
            ".type " #fname ", %%function\n"                            \
            #fname " :\n"                                               \
            "\tadrp x16, " #libbasename "\n"                            \
            "\tldr  x16, [x16, #:lo12:" #libbasename "]\n"             \
            "\tmov  x17, #%c0\n"                                       \
            "\tldr  x17, [x16, x17]\n"                                 \
            "\tbr   x17\n"                                              \
            : : "i" ((-lvo*LIB_VECTSIZE))                               \
        );                                                              \
    }
#define AROS_GM_LIBFUNCSTUB(fname, libbasename, lvo) \
    __AROS_GM_LIBFUNCSTUB(fname, libbasename, lvo)

/* Macro: AROS_GM_RELLIBFUNCSTUB(functionname, libbasename, lvo)
   Same as AROS_GM_LIBFUNCSTUB but finds libbase at an offset in
   the current libbase (for relbase libraries).

   AArch64 sequence:
     Save x0-x7 (8 argument registers) and x30 (lr) on stack.
     Call __aros_getoffsettable() -> returns offset table in x0.
     Load rellib offset, index into offset table to get libbase in x16.
     Restore x0-x7 and x30.
     Load function vector from x16 and tail-call via x17.
*/
#define __AROS_GM_RELLIBFUNCSTUB(fname, libbasename, lvo)                  \
    void __ ## fname ## _ ## libbasename ## _relwrapper(IPTR args)      \
    {                                                                   \
        asm volatile(                                                   \
            ".weak " #fname "\n"                                        \
            ".type " #fname ", %%function\n"                            \
            #fname " :\n"                                               \
            /* Save argument registers and link register */             \
            "\tstp  x0, x1, [sp, #-80]!\n"                             \
            "\tstp  x2, x3, [sp, #16]\n"                               \
            "\tstp  x4, x5, [sp, #32]\n"                               \
            "\tstp  x6, x7, [sp, #48]\n"                               \
            "\tstr  x30,    [sp, #64]\n"                                \
            /* x0 = __aros_getoffsettable() */                          \
            "\tbl   __aros_getoffsettable\n"                            \
            /* x16 = libbase from offset table */                       \
            "\tadrp x1, __aros_rellib_offset_" #libbasename "\n"        \
            "\tldr  x1, [x1, #:lo12:__aros_rellib_offset_" #libbasename "]\n" \
            "\tldr  x16, [x0, x1]\n"                                   \
            /* Restore argument registers and link register */          \
            "\tldp  x2, x3, [sp, #16]\n"                               \
            "\tldp  x4, x5, [sp, #32]\n"                               \
            "\tldp  x6, x7, [sp, #48]\n"                               \
            "\tldr  x30,    [sp, #64]\n"                                \
            "\tldp  x0, x1, [sp], #80\n"                                \
            /* Load function address and tail-call */                   \
            "\tmov  x17, #%c0\n"                                       \
            "\tldr  x17, [x16, x17]\n"                                 \
            "\tbr   x17\n"                                              \
            : : "i" ((-lvo*LIB_VECTSIZE))                               \
        );                                                              \
    }
#define AROS_GM_RELLIBFUNCSTUB(fname, libbasename, lvo) \
    __AROS_GM_RELLIBFUNCSTUB(fname, libbasename, lvo)

/* Macro: AROS_GM_LIBFUNCALIAS(functionname, alias)
   This macro will generate an alias 'alias' for function
   'functionname'
*/
#define __AROS_GM_LIBFUNCALIAS(fname, alias) \
    asm(".weak " #alias "\n" \
        "\t.set " #alias "," #fname \
    );
#define AROS_GM_LIBFUNCALIAS(fname, alias) \
    __AROS_GM_LIBFUNCALIAS(fname, alias)

/******************* Library Side Thunks ******************/

/* This macro relies upon the fact that the
 * caller to a stack function will have passed in
 * the base in x16, since the caller will
 * have used the AROS_LIBFUNCSTUB() macro.
 *
 * AArch64 sequence:
 *   Save x0-x7 and x30 on stack.
 *   Move x16 (libbase) to x0 for __aros_setoffsettable().
 *   Call __aros_setoffsettable().
 *   Restore x0-x7 and x30.
 *   Branch to the actual implementation function.
 */
#define __GM_STRINGIZE(x) #x
#define __AROS_GM_STACKCALL(fname, libbasename, libfuncname)               \
    void libfuncname(void);                                             \
    void __ ## fname ## _stackcall(void)                                \
    {                                                                   \
        asm volatile(                                                   \
            "\t" __GM_STRINGIZE(libfuncname) " :\n"                     \
            "\tstp  x0, x1, [sp, #-80]!\n"                             \
            "\tstp  x2, x3, [sp, #16]\n"                               \
            "\tstp  x4, x5, [sp, #32]\n"                               \
            "\tstp  x6, x7, [sp, #48]\n"                               \
            "\tstr  x30,    [sp, #64]\n"                                \
            "\tmov  x0, x16\n"                                          \
            "\tbl   __aros_setoffsettable\n"                            \
            "\tldp  x2, x3, [sp, #16]\n"                               \
            "\tldp  x4, x5, [sp, #32]\n"                               \
            "\tldp  x6, x7, [sp, #48]\n"                               \
            "\tldr  x30,    [sp, #64]\n"                                \
            "\tldp  x0, x1, [sp], #80\n"                                \
            "\tb    " #fname "\n"                                       \
        );                                                              \
    }

#define AROS_GM_STACKCALL(fname, libbasename, lvo) \
     __AROS_GM_STACKCALL(fname, libbasename, AROS_SLIB_ENTRY(fname, libbasename, lvo))

/* Macro: AROS_GM_STACKALIAS(functionname, libbasename, lvo)
   This macro will generate an alias 'alias' for function
   'functionname'
*/
#define __AROS_GM_STACKALIAS(fname, alias) \
    void alias(void); \
    asm(".weak " __GM_STRINGIZE(alias) "\n" \
        "\t.set " __GM_STRINGIZE(alias) "," #fname \
    );
#define AROS_GM_STACKALIAS(fname, libbasename, lvo) \
    __AROS_GM_STACKALIAS(fname, AROS_SLIB_ENTRY(fname, libbasename, lvo))

#endif /* AROS_AARCH64_GENMODULE_H */
