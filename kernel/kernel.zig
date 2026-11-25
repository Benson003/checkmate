// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const MemoryType = std.os.uefi.tables.MemoryType;
pub const E820_MAX_ENTRIES = 512;

pub const BootParams = extern struct {
    e820_table: [E820_MAX_ENTRIES]BootE820Entries,
    screen_info: ScreenInfo,
    acpi_rsp_addr: u64,
    e820_entries: u32,
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

pub export fn _start() callconv(.c) noreturn {
    unreachable;
}
