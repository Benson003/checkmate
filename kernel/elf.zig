// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const uefi = std.os.uefi;
const BootServices = uefi.tables.BootServices;

pub const ElfHeader = extern struct {
    e_ident: [16]u8,
    e_type: enum(u16) {
        ET_NONE = 0,
        ET_REL = 1,
        ET_EXEC = 2,
        ET_DYN = 3,
        ET_CORE = 4,
        _,
    },
    e_machine: enum(u16) {
        X86_32 = 0x03,
        X86_64 = 0x3E,
        _,
    },
    e_version: u32,
    e_entry: u64,
    e_phoff: u64,
    e_shoff: u64,
    e_flags: u32,
    e_ehsize: u16,
    e_phentsize: u16,
    e_phnum: u16,
    e_shentsize: u16,
    e_shnum: u16,
    e_shstrndx: u16,
};

pub const ProgramHeader = extern struct {
    type: enum(u32) {
        PT_NULL = 0,
        PT_LOAD = 1,
        PT_DYNAMIC = 2,
        PT_INTERP = 3,
        PT_NOTE = 4,
        PT_SHLIB = 5,
        PT_PHDR = 6,
        PT_TLS = 7,
        _,
    },
    flags: u32,
    offset: u64,
    vaddr: u64,
    paddr: u64,
    filesz: u64,
    memsz: u64,
    @"align": u64,
};

comptime {
    if (@sizeOf(ElfHeader) != 64) @compileError("ElfHeader must be 64 bytes");
    if (@offsetOf(ElfHeader, "e_ident") != 0) @compileError("ElfHeader.e_ident offset mismatch");
    if (@offsetOf(ElfHeader, "e_type") != 16) @compileError("ElfHeader.e_type offset mismatch");
    if (@offsetOf(ElfHeader, "e_machine") != 18) @compileError("ElfHeader.e_machine offset mismatch");
    if (@offsetOf(ElfHeader, "e_version") != 20) @compileError("ElfHeader.e_version offset mismatch");
    if (@offsetOf(ElfHeader, "e_entry") != 24) @compileError("ElfHeader.e_entry offset mismatch");
    if (@offsetOf(ElfHeader, "e_phoff") != 32) @compileError("ElfHeader.e_phoff offset mismatch");
    if (@offsetOf(ElfHeader, "e_shoff") != 40) @compileError("ElfHeader.e_shoff offset mismatch");
    if (@offsetOf(ElfHeader, "e_flags") != 48) @compileError("ElfHeader.e_flags offset mismatch");
    if (@offsetOf(ElfHeader, "e_ehsize") != 52) @compileError("ElfHeader.e_ehsize offset mismatch");
    if (@offsetOf(ElfHeader, "e_phentsize") != 54) @compileError("ElfHeader.e_phentsize offset mismatch");
    if (@offsetOf(ElfHeader, "e_phnum") != 56) @compileError("ElfHeader.e_phnum offset mismatch");
    if (@offsetOf(ElfHeader, "e_shentsize") != 58) @compileError("ElfHeader.e_shentsize offset mismatch");
    if (@offsetOf(ElfHeader, "e_shnum") != 60) @compileError("ElfHeader.e_shnum offset mismatch");
    if (@offsetOf(ElfHeader, "e_shstrndx") != 62) @compileError("ElfHeader.e_shstrndx offset mismatch");

    if (@sizeOf(ProgramHeader) != 56) @compileError("ProgramHeader must be 56 bytes");
    if (@offsetOf(ProgramHeader, "type") != 0) @compileError("ProgramHeader.type offset mismatch");
    if (@offsetOf(ProgramHeader, "flags") != 4) @compileError("ProgramHeader.flags offset mismatch");
    if (@offsetOf(ProgramHeader, "offset") != 8) @compileError("ProgramHeader.offset offset mismatch");
    if (@offsetOf(ProgramHeader, "vaddr") != 16) @compileError("ProgramHeader.vaddr offset mismatch");
    if (@offsetOf(ProgramHeader, "paddr") != 24) @compileError("ProgramHeader.paddr offset mismatch");
    if (@offsetOf(ProgramHeader, "filesz") != 32) @compileError("ProgramHeader.filesz offset mismatch");
    if (@offsetOf(ProgramHeader, "memsz") != 40) @compileError("ProgramHeader.memsz offset mismatch");
    if (@offsetOf(ProgramHeader, "align") != 48) @compileError("ProgramHeader.align offset mismatch");

    if (@sizeOf(Rela) != 24) @compileError("Rela must be 24 bytes");
    if (@offsetOf(Rela, "r_offset") != 0) @compileError("Rela.r_offset offset mismatch");
    if (@offsetOf(Rela, "r_info") != 8) @compileError("Rela.r_info offset mismatch");
    if (@offsetOf(Rela, "r_addend") != 16) @compileError("Rela.r_info offset mismatch");

    if (@sizeOf(Rel) != 16) @compileError("Rel must be 16 bytes");
    if (@offsetOf(Rela, "r_offset") != 0) @compileError("Rel.r_offset offset mismatch");
    if (@offsetOf(Rela, "r_info") != 8) @compileError("Rel.r_info offset mismatch");

    if (@sizeOf(Dyn) != 16) @compileError("Dyn must be 16 bytes");
    if (@offsetOf(Dyn, "d_tag") != 0) @compileError("Dyn.d_tag offset mismatch");
    if (@offsetOf(Dyn, "d_un") != 8) @compileError("Dyn.d_un offset mismatch");
}

pub const ElfAllocInfo = struct {
    entry_point: u64,
    segments: []ProgramHeader,
};

pub const Dyn = extern struct {
    d_tag: enum(i64) {
        DT_NULL = 0,
        DT_NEEDED = 1,
        DT_PLTRELSZ = 2,
        DT_HASH = 4,
        DT_STRTAB = 5,
        DT_SYMTAB = 6,
        DT_RELA = 7,
        DT_RELASZ = 8,
        DT_RELAENT = 9,
        DT_STRSZ = 10,
        DT_SYMENT = 11,
        DT_INIT = 12,
        DT_FINI = 13,
        DT_SONAME = 14,
        DT_RPATH = 15,
        DT_SYMBOLIC = 16,
        DT_REL = 17,
        DT_RELSZ = 18,
        DT_RELENT = 19,
        DT_PLTREL = 20,
        DT_DEBUG = 21,
        DT_TEXTREL = 22,
        DT_JMPREL = 23,
        DT_BIND_NOW = 24,
        DT_RUNPATH = 29,
        _,
    },
    d_un: extern union {
        d_val: u64,
        d_ptr: u64,
    },
};

pub const Rela = extern struct {
    r_offset: u64,
    r_info: u64,
    r_addend: i64,
};

pub const Rel = extern struct {
    r_offset: u64,
    r_info: u64,
};

pub const ElfAllocError = error{
    BufferTooSmallForHeader,
    InvalidMagicBytes,
    InvalidArchBitWidth,
    InvalidEndianness,
    InvalidIdentVersionOrAbi,
    InvalidProgramHeaderEntrySize,
    ZeroProgramHeaders,
    InvalidMachineType,
    InvalidHeaderVersion,
    OutOfMemory,
    ProgramHeaderTableOutOfBounds,
};
const MAGIC = "\x7fELF";
const ARCH_BIT_WIDTH = 2;
const ENDIANNESS = 1;

pub const PF_X: u32 = 1 << 0;
pub const PF_W: u32 = 1 << 1;
pub const PF_R: u32 = 1 << 2;

pub fn loadElf(
    allocator: std.mem.Allocator,
    buff: []u8,
) ElfAllocError!ElfAllocInfo {
    if (buff.len < @sizeOf(ElfHeader)) return ElfAllocError.BufferTooSmallForHeader;
    if (!std.mem.eql(u8, buff[0..4], MAGIC)) return ElfAllocError.InvalidMagicBytes;
    if (buff[4] != ARCH_BIT_WIDTH) return ElfAllocError.InvalidArchBitWidth;
    if (buff[5] != ENDIANNESS) return ElfAllocError.InvalidEndianness;
    if (!std.mem.eql(u8, buff[6..9], &.{ 1, 0, 0 })) return ElfAllocError.InvalidIdentVersionOrAbi;

    const header = std.mem.bytesToValue(ElfHeader, buff[0..@sizeOf(ElfHeader)]);

    if (header.e_phentsize != @sizeOf(ProgramHeader)) return ElfAllocError.InvalidProgramHeaderEntrySize;
    if (header.e_phnum == 0) return ElfAllocError.ZeroProgramHeaders;
    if (header.e_machine != .X86_64) return ElfAllocError.InvalidMachineType;
    if (header.e_version != 1) return ElfAllocError.InvalidHeaderVersion;

    var count: u64 = 0;
    const poff: u64 = header.e_phoff;
    const psize: u64 = header.e_phentsize;
    const pnum: u64 = header.e_phnum;
    const table_bytes = std.math.mul(u64, psize, pnum) catch return ElfAllocError.ProgramHeaderTableOutOfBounds;
    const table_size = std.math.add(u64, poff, table_bytes) catch return ElfAllocError.ProgramHeaderTableOutOfBounds;
    if (buff.len < table_size) return ElfAllocError.ProgramHeaderTableOutOfBounds;

    var segment_alloc_info: std.ArrayList(ProgramHeader) = .empty;
    errdefer segment_alloc_info.deinit(allocator);
    segment_alloc_info.ensureTotalCapacity(allocator, header.e_phnum) catch return ElfAllocError.OutOfMemory;

    while (count < pnum) : (count += 1) {
        const t_addr = poff + (count * psize);
        const pheader = std.mem.bytesToValue(ProgramHeader, buff[t_addr .. t_addr + @sizeOf(ProgramHeader)]);
        segment_alloc_info.appendAssumeCapacity(pheader);
    }

    return .{
        .entry_point = header.e_entry,
        .segments = segment_alloc_info.toOwnedSlice(allocator) catch return ElfAllocError.OutOfMemory,
    };
}
