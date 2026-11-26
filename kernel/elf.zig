// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const uefi = std.os.uefi;
const BootServices = uefi.tables.BootServices;

pub const ElfHeader = extern struct {
    e_ident: [16]u16,
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

pub const ElfAllocInfo = struct {
    entry_point: u64,
    segments: []SegmentAllocInfo,
    backing_pages: []align(4096) [4096]u8,
};

pub const SegmentAllocInfo = struct {
    flags: u32,
    addr: u64,
    memsz: u64,
    @"align": u64,
};

const ElfAllocError = error{
    OutOfMemory,
    FailedToFindSegments,
    FailedToReadSegmentHeaders,
    InvalidArchBitWidth,
    InvalidEndianness,
    InvalidProgramHeaders,
    NoSegmentsFound,
    FileNotExcutable,
    InvalidMachineType,
    InvalidELFFile,
};

const MAGIC = "\x7fELF";
const ARCH_BIT_WIDTH = 2;
const ENDIANNESS = 1;

pub fn loadMinimal(
    allocator: std.mem.Allocator,
    buff: []u8,
    backing_pages: []align(4096) [4096]u8,
) ElfAllocError!ElfAllocInfo {
    if (buff.len < @sizeOf(ElfHeader)) return ElfAllocError.InvalidELFFile;
    if (!std.mem.eql(u8, buff[0..4], MAGIC)) return ElfAllocError.InvalidELFFile;
    if (buff[4] != ARCH_BIT_WIDTH) return ElfAllocError.InvalidArchBitWidth;
    if (buff[5] != ENDIANNESS) return ElfAllocError.InvalidEndianness;
    if (!std.mem.eql(u8, buff[6..9], &.{ 1, 0, 0 })) return ElfAllocError.InvalidELFFile;

    const header = std.mem.bytesToValue(ElfHeader, buff[0..@sizeOf(ElfHeader)]);

    if (header.e_phentsize != @sizeOf(ProgramHeader)) return ElfAllocError.InvalidProgramHeaders;
    if (header.e_phnum == 0) return ElfAllocError.NoSegmentsFound;
    if (header.e_type != .ET_EXEC) return ElfAllocError.FileNotExcutable;
    if (header.e_machine != .X86_64) return ElfAllocError.InvalidMachineType;
    if (header.e_version != 1) return ElfAllocError.InvalidELFFile;

    var segment_alloc_info: std.ArrayList(SegmentAllocInfo) = .empty;
    segment_alloc_info.ensureTotalCapacity(allocator, header.e_phnum) catch return ElfAllocError.OutOfMemory;
    errdefer segment_alloc_info.deinit(allocator);

    var count: u64 = 0;
    const poff: u64 = header.e_phoff;
    const psize: u64 = header.e_phentsize;
    const pnum: u64 = header.e_phnum;
    if (buff.len < poff + (psize * pnum)) return ElfAllocError.FailedToReadSegmentHeaders;

    while (count < pnum) : (count += 1) {
        const t_addr = poff + (count * psize);
        const pheader = std.mem.bytesToValue(ProgramHeader, buff[t_addr .. t_addr + @sizeOf(ProgramHeader)]);
        if (pheader.type != .PT_LOAD) continue;
        segment_alloc_info.appendAssumeCapacity(.{
            .memsz = pheader.memsz,
            .addr = pheader.vaddr,
            .flags = pheader.flags,
            .@"align" = pheader.@"align",
        });
    }

    return .{
        .entry_point = header.e_entry,
        .segments = segment_alloc_info.toOwnedSliceAssert(),
        .backing_pages = backing_pages,
    };
}
