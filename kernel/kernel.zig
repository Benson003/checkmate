// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const MemoryType = std.os.uefi.tables.MemoryType;
pub const Elf = @import("elf.zig");
pub const E820_MAX_ENTRIES = 512;

pub const BootParams = extern struct {
    e820_table: [E820_MAX_ENTRIES]BootE820Entries,
    screen_info: ScreenInfo,
    acpi_rsp_addr: u64,
    e820_entries: u32,
    pool_base_ptr: u64,
    pool_len: u64,
};

pub const BootE820Entries = extern struct {
    address: u64,
    size: u64,
    type: MemoryType,
};

pub const ScreenInfo = extern struct {
    lfb_base: u64,
    lfb_size: u64,
    lfb_width: u32,
    lfb_height: u32,
    lfb_linelength: u32,
    lfb_depth: u16,
    red_size: u8,
    red_pos: u8,
    green_size: u8,
    green_pos: u8,
    blue_size: u8,
    blue_pos: u8,
    rsvd_size: u8,
    rsvd_pos: u8,
};
fn getPixelAddress(x: u32, y: u32, bpp: u32) ?u64 {
    const si = boot_params_ptr.?.screen_info;
    if (x >= si.lfb_width or y >= si.lfb_height) return null;
    const byte_offset = @as(u64, y) * si.lfb_linelength + @as(u64, x) * bpp;
    if (byte_offset + bpp > si.lfb_size) return null;
    return si.lfb_base + byte_offset;
}

var boot_params_ptr: ?*BootParams = null;
pub export fn _start() callconv(.c) noreturn {
    boot_params_ptr = @ptrFromInt(asm ("mov %%rdi, %[r]"
        : [r] "=r" (-> u64),
    ));

    const bpp = boot_params_ptr.?.screen_info.lfb_depth / 8;
    //const pitch_pixels = boot_params_ptr.?.screen_info.lfb_linelength / bpp;

    const addr = getPixelAddress(0, 0, bpp) orelse @panic("bad pixel");
    const ptr: *volatile u32 = @ptrFromInt(addr);
    ptr.* = 0x00FF0000; // if rsvd_pos=24 and RGB order; adjust to your channel layout
    asm volatile ("hlt");

    unreachable;
}
