// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const uefi = std.os.uefi;
const BootServices = uefi.tables.BootServices;
const elf = std.elf;
const Elf64 = elf.Elf64;

pub fn loadElf(boot_services: *BootServices) void {
    _ = boot_services;
}
