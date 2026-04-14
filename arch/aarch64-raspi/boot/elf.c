/*
    Copyright (C) 2026, The AROS Development Team. All rights reserved.
    Desc: ELF64 loader for AArch64 bootstrap.
          Loads core.elf into high memory, performs RELA relocations.
          Based on arch/arm-raspi/boot/elf.c, adapted for ELF64/AArch64.
*/
#include "elf.h"
#include "boot.h"
#include <dos/elf.h>
#include <string.h>
#define DELF(x) /* x */
/* AArch64 relocation types */
#define R_AARCH64_NONE          0
#define R_AARCH64_ABS64         257
#define R_AARCH64_ABS32         258
#define R_AARCH64_ABS16         259
#define R_AARCH64_PREL64        260
#define R_AARCH64_PREL32        261
#define R_AARCH64_CALL26        283
#define R_AARCH64_JUMP26        282
#define R_AARCH64_ADR_PREL_PG_HI21     275
#define R_AARCH64_ADD_ABS_LO12_NC      277
#define R_AARCH64_LDST64_ABS_LO12_NC   286
#define R_AARCH64_LDST32_ABS_LO12_NC   285
#define R_AARCH64_LDST16_ABS_LO12_NC   284
#define R_AARCH64_LDST8_ABS_LO12_NC    278
#define R_AARCH64_LDST128_ABS_LO12_NC  299
#define R_AARCH64_ADR_GOT_PAGE         311
#define R_AARCH64_LD64_GOT_LO12_NC     312
#define R_AARCH64_MOVW_UABS_G0_NC      264
#define R_AARCH64_MOVW_UABS_G1_NC      266
#define R_AARCH64_MOVW_UABS_G2_NC      268
#define R_AARCH64_MOVW_UABS_G3         271
static uint32_t int_shnum;
static uint32_t int_shstrndx;
static int checkHeader(struct elfheader *eh)
{
    if (eh->ident[0] != 0x7f || eh->ident[1] != 'E' ||
        eh->ident[2] != 'L'  || eh->ident[3] != 'F')
        return 0;
    int_shnum = eh->shnum;
    int_shstrndx = eh->shstrndx;
    if (int_shnum == 0 || int_shstrndx == SHN_XINDEX)
    {
        if (eh->shoff == 0) return 0;
        struct sheader *sh = (struct sheader *)((uintptr_t)eh + eh->shoff);
        if (int_shnum == 0) int_shnum = sh->size;
        if (int_shstrndx == SHN_XINDEX) int_shstrndx = sh->link;
        if (int_shnum == 0 || int_shstrndx == SHN_XINDEX) return 0;
    }
    if (eh->ident[EI_CLASS]   != ELFCLASS64  ||
        eh->ident[EI_VERSION] != EV_CURRENT  ||
        eh->ident[EI_DATA]    != ELFDATA2LSB ||
        eh->machine           != EM_AARCH64  ||
        !(eh->type == ET_REL || eh->type == ET_EXEC))
        return 0;
    return 1;
}
int getElfSize(void *elf_file, uint64_t *size_rw, uint64_t *size_ro)
{
    struct elfheader *eh = (struct elfheader *)elf_file;
    uint64_t s_ro = 0, s_rw = 0;
    if (checkHeader(eh))
    {
        struct sheader *sh = (struct sheader *)((uintptr_t)elf_file + eh->shoff);
        
        for (unsigned i = 0; i < int_shnum; i++)
        {
            /* Guard against bad addralign */
            uint64_t align = sh[i].addralign;
            if (align == 0) align = 1;

            if (sh[i].flags & SHF_ALLOC)
            {
                uint64_t size = (sh[i].size + align - 1) & ~(align - 1);
                if (sh[i].flags & SHF_WRITE)
                {
                    s_rw = (s_rw + align - 1) & ~(align - 1);
                    s_rw += size;
                }
                else
                {
                    s_ro = (s_ro + align - 1) & ~(align - 1);
                    s_ro += size;
                }
            }
        }
    }
    if (size_ro) *size_ro = s_ro;
    if (size_rw)
    {
        /*
         * Account for GOT slots that will be allocated during relocation.
         * Each R_AARCH64_ADR_GOT_PAGE relocation needs an 8-byte GOT entry.
         */
        uint64_t got_size = 0;
        if (!checkHeader(eh))
        {
            struct sheader *sh = (struct sheader *)((uintptr_t)elf_file + eh->shoff);
            for (unsigned i = 0; i < int_shnum; i++)
            {
                if (sh[i].type == SHT_RELA)
                {
                    struct relo *rel = (struct relo *)((uintptr_t)elf_file + sh[i].offset);
                    unsigned nrel = sh[i].size / sh[i].entsize;
                    for (unsigned j = 0; j < nrel; j++)
                    {
                        uint32_t rt = ELF64_R_TYPE(rel[j].info);
                        if (rt == R_AARCH64_ADR_GOT_PAGE || rt == R_AARCH64_LD64_GOT_LO12_NC)
                            got_size += 8;
                    }
                }
            }
            /* Align GOT area */
            got_size = (got_size + 15) & ~15;
        }
        *size_rw = s_rw + got_size;
    }
    return 1;
}
static uintptr_t ptr_ro;
static uintptr_t ptr_rw;
static uintptr_t virtoffset;
void initAllocator(uintptr_t addr_ro, uintptr_t addr_rw, uintptr_t virtoff)
{
    ptr_ro = addr_ro;
    ptr_rw = addr_rw;
    virtoffset = virtoff;
}
struct bss_tracker tracker[MAX_BSS_SECTIONS];
static struct bss_tracker *bss_tracker = &tracker[0];
static int load_hunk(void *file, struct sheader *sh)
{
    void *ptr = (void *)0;
    if (!sh->size) return 1;
    if (sh->flags & SHF_WRITE)
    {
        ptr_rw = (ptr_rw + sh->addralign - 1) & ~(sh->addralign - 1);
        ptr = (void *)ptr_rw;
        ptr_rw += sh->size;
    }
    else
    {
        ptr_ro = (ptr_ro + sh->addralign - 1) & ~(sh->addralign - 1);
        ptr = (void *)ptr_ro;
        ptr_ro += sh->size;
    }
    sh->addr = (void *)ptr;
    if (sh->type != SHT_NOBITS)
    {
        memcpy(ptr, (void *)((uintptr_t)file + sh->offset), sh->size);
    }
    else
    {
        bzero(ptr, sh->size);
        bss_tracker->addr = (void *)((uintptr_t)ptr + virtoffset);
        bss_tracker->length = sh->size;
        bss_tracker++;
        bss_tracker->addr = (void *)0;
        bss_tracker->length = 0;
    }
    return 1;
}
static int relocate(struct elfheader *eh, struct sheader *sh, long shrel_idx,
                    uintptr_t virt, uintptr_t *deltas)
{
    struct sheader *shrel    = &sh[shrel_idx];
    struct sheader *shsymtab = &sh[shrel->link];
    struct sheader *toreloc  = &sh[shrel->info];
    uintptr_t orig_addr = deltas[shrel->info];
    int is_exec = (eh->type == ET_EXEC);
    struct symbol *symtab = (struct symbol *)((uintptr_t)shsymtab->addr);
    struct relo *rel = (struct relo *)((uintptr_t)shrel->addr);
    char *section = (char *)((uintptr_t)toreloc->addr);
    unsigned numrel = shrel->size / shrel->entsize;
    struct symbol *SysBase_sym = (void *)0;
    for (unsigned i = 0; i < numrel; i++, rel++)
    {
        struct symbol *sym = &symtab[ELF64_R_SYM(rel->info)];
        uint32_t reltype = ELF64_R_TYPE(rel->info);
        uintptr_t p_addr = (uintptr_t)&section[rel->offset - orig_addr];
        int64_t s;
        uintptr_t voff = virt;
        if (reltype == R_AARCH64_NONE)
            continue;
        switch (sym->shindex)
        {
        case SHN_UNDEF:
            kprintf("[BOOT:ELF] Undefined symbol '%s'\n",
                    (char *)((uintptr_t)sh[shsymtab->link].addr) + sym->name);
            return 0;
        case SHN_COMMON:
            kprintf("[BOOT:ELF] COMMON symbol '%s'\n",
                    (char *)((uintptr_t)sh[shsymtab->link].addr) + sym->name);
            return 0;
        case SHN_ABS:
            if (SysBase_sym == (void *)0)
            {
                if (strncmp((char *)((uintptr_t)sh[shsymtab->link].addr) + sym->name,
                            "SysBase", 8) == 0)
                {
                    SysBase_sym = sym;
                    s = 4;
                    voff = 0;
                    break;
                }
            }
            else if (SysBase_sym == sym)
            {
                s = 4;
                voff = 0;
                break;
            }
            s = sym->value;
            break;
        default:
            s = (int64_t)((uintptr_t)sh[sym->shindex].addr + sym->value - deltas[sym->shindex]);
            break;
        }
        s += rel->addend;
        switch (reltype)
        {
        case R_AARCH64_ABS64:
            if (is_exec)
                *(uint64_t *)p_addr += (uintptr_t)sh[sym->shindex].addr - deltas[sym->shindex] + voff;
            else
                *(uint64_t *)p_addr = s + voff;
            break;
        case R_AARCH64_ABS32:
            if (is_exec)
                *(uint32_t *)p_addr += (uint32_t)((uintptr_t)sh[sym->shindex].addr - deltas[sym->shindex] + voff);
            else
                *(uint32_t *)p_addr = (uint32_t)(s + voff);
            break;
        case R_AARCH64_CALL26:
        case R_AARCH64_JUMP26:
        {
            int64_t offset;
            if (is_exec)
            {
                if (shrel->info != sym->shindex)
                {
                    int64_t expected = deltas[sym->shindex] - deltas[shrel->info];
                    int64_t actual = (uintptr_t)sh[sym->shindex].addr - (uintptr_t)sh[shrel->info].addr;
                    offset = (int64_t)(int32_t)((*(uint32_t *)p_addr & 0x03FFFFFF) << 6) >> 4;
                    offset += actual - expected;
                    *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFC000000) | ((offset >> 2) & 0x03FFFFFF);
                }
            }
            else
            {
                offset = (s + voff) - (int64_t)p_addr;
                *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFC000000) | ((offset >> 2) & 0x03FFFFFF);
            }
            break;
        }
        case R_AARCH64_ADR_PREL_PG_HI21:
        {
            int64_t page_s = (s + voff) & ~0xFFFLL;
            int64_t page_p = (int64_t)p_addr & ~0xFFFLL;
            int64_t offset = page_s - page_p;
            uint32_t immlo = (offset >> 12) & 0x3;
            uint32_t immhi = (offset >> 14) & 0x7FFFF;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0x9F00001F) | (immlo << 29) | (immhi << 5);
            break;
        }
        case R_AARCH64_ADD_ABS_LO12_NC:
        case R_AARCH64_LDST8_ABS_LO12_NC:
        {
            uint32_t imm12 = (s + voff) & 0xFFF;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFFC003FF) | (imm12 << 10);
            break;
        }
        case R_AARCH64_LDST16_ABS_LO12_NC:
        {
            uint32_t imm12 = ((s + voff) & 0xFFF) >> 1;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFFC003FF) | (imm12 << 10);
            break;
        }
        case R_AARCH64_LDST32_ABS_LO12_NC:
        {
            uint32_t imm12 = ((s + voff) & 0xFFF) >> 2;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFFC003FF) | (imm12 << 10);
            break;
        }
        case R_AARCH64_LDST64_ABS_LO12_NC:
        {
            uint32_t imm12 = ((s + voff) & 0xFFF) >> 3;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFFC003FF) | (imm12 << 10);
            break;
        }
        case R_AARCH64_LDST128_ABS_LO12_NC:
        {
            uint32_t imm12 = ((s + voff) & 0xFFF) >> 4;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFFC003FF) | (imm12 << 10);
            break;
        }
        /*
         * GOT relocations: The code expects to load a pointer from a GOT
         * entry, then dereference it. We allocate GOT slots in the RW area
         * and store the symbol address there.
         */
        case R_AARCH64_ADR_GOT_PAGE:
        {
            /* Allocate a GOT slot and store the symbol address */
            uint64_t *got_slot = (uint64_t *)ptr_rw;
            ptr_rw = (ptr_rw + 7) & ~7;
            got_slot = (uint64_t *)ptr_rw;
            ptr_rw += 8;
            *got_slot = (uint64_t)(s + voff);

            int64_t off = ((int64_t)(uintptr_t)got_slot & ~0xFFF) - ((int64_t)p_addr & ~0xFFF);
            uint32_t immlo = (off >> 12) & 0x3;
            uint32_t immhi = (off >> 14) & 0x7FFFF;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0x9F00001F) | (immlo << 29) | (immhi << 5);

            /* Peek ahead for the paired LD64_GOT_LO12_NC */
            if (i + 1 < numrel)
            {
                struct relo *next = rel + 1;
                if (ELF64_R_TYPE(next->info) == R_AARCH64_LD64_GOT_LO12_NC)
                {
                    uintptr_t np = (uintptr_t)&section[next->offset - orig_addr];
                    uint32_t imm12 = ((uintptr_t)got_slot & 0xFFF) >> 3;
                    *(uint32_t *)np = (*(uint32_t *)np & 0xFFC003FF) | (imm12 << 10);
                    rel++;
                    i++;
                }
            }
            break;
        }
        case R_AARCH64_LD64_GOT_LO12_NC:
        {
            /* Standalone LD64_GOT_LO12_NC (not paired) — allocate GOT slot */
            uint64_t *got_slot = (uint64_t *)((ptr_rw + 7) & ~7);
            ptr_rw = (uintptr_t)got_slot + 8;
            *got_slot = (uint64_t)(s + voff);
            uint32_t imm12 = ((uintptr_t)got_slot & 0xFFF) >> 3;
            *(uint32_t *)p_addr = (*(uint32_t *)p_addr & 0xFFC003FF) | (imm12 << 10);
            break;
        }
        default:
            kprintf("[BOOT:ELF] Unknown relocation %d\n", reltype);
            return 0;
        }
    }
    return 1;
}
uintptr_t loadElf(void *elf_file)
{
    struct elfheader *eh = (struct elfheader *)elf_file;
    
    if (checkHeader(eh))
    {
        struct sheader *sh = (struct sheader *)((uintptr_t)elf_file + eh->shoff);
        uintptr_t deltas[int_shnum];
        
        for (unsigned i = 0; i < int_shnum; i++)
        {
            if (sh[i].type == SHT_SYMTAB || sh[i].type == SHT_STRTAB)
            {
                sh[i].addr = (void *)((uintptr_t)elf_file + sh[i].offset);
            }
            else if (sh[i].flags & SHF_ALLOC)
            {
                deltas[i] = (uintptr_t)sh[i].addr;
                if (!load_hunk(elf_file, &sh[i]))
                    return 0;
                DELF(if (sh[i].size)
                    kprintf("[BOOT:ELF] %s loaded at %p (virt %p)\n",
                            sh[i].flags & SHF_WRITE ? "RW" : "RO",
                            sh[i].addr, (void *)((uintptr_t)sh[i].addr + virtoffset)));
            }
        }
        for (unsigned i = 0; i < int_shnum; i++)
        {
            if (sh[i].type == SHT_RELA && sh[sh[i].info].addr)
            {
                sh[i].addr = (void *)((uintptr_t)elf_file + sh[i].offset);
                if (!sh[i].addr || !relocate(eh, sh, i, virtoffset, deltas))
                    return 0;
            }
        }
        /* Return address of _start symbol */
    for (unsigned i = 0; i < int_shnum; i++)
    {
        if (sh[i].type == SHT_SYMTAB)
        {
            struct symbol *sym = (struct symbol *)sh[i].addr;
            unsigned nsyms = sh[i].size / sizeof(struct symbol);
            char *strtab = (char *)sh[sh[i].link].addr;
            for (unsigned j = 0; j < nsyms; j++)
            {
                if (sym[j].name && strtab)
                {
                    char *name = strtab + sym[j].name;
                    if (name[0]=='_' && name[1]=='s' && name[2]=='t' &&
                        name[3]=='a' && name[4]=='r' && name[5]=='t' && name[6]==0)
                    {
                        /* sym[j].value = offset within section */
                        uintptr_t entry = (uintptr_t)sh[sym[j].shindex].addr + sym[j].value;
                        kprintf("[BOOT:ELF] _start at %p\n", (void*)entry);
                        return entry;
                    }
                }
            }
        }
    }
    } /* checkHeader */
    return 0;
}
