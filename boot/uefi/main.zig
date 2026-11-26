// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const kernel = @import("kernel");
const KElf = kernel.Elf;
const uefi = std.os.uefi;

fn bytesFromBitmask(mask_info: uefi.protocol.GraphicsOutput.PixelBitmask) u32 {
    const combined = mask_info.red_mask |
        mask_info.green_mask |
        mask_info.blue_mask |
        mask_info.reserved_mask;
    if (combined == 0) return 0;

    const highest_bit: u32 = @bitSizeOf(@TypeOf(combined)) - @clz(combined);
    return (highest_bit + 7) / 8;
}

fn findAcpiRsdp(config_tables: []const uefi.tables.ConfigurationTable) u64 {
    var rsdp_10: u64 = 0;

    for (config_tables) |entry| {
        const addr: u64 = @intFromPtr(entry.vendor_table);
        if (uefi.Guid.eql(entry.vendor_guid, acpi_20_guid)) {
            return addr; // Prefer ACPI 2.0 RSDP right away
        }
        if (uefi.Guid.eql(entry.vendor_guid, acpi_10_guid)) {
            rsdp_10 = addr;
        }
    }

    return rsdp_10;
}

const acpi_20_guid = uefi.Guid{
    .time_low = 0x8868e871,
    .time_mid = 0xe4f1,
    .time_high_and_version = 0x11d3,
    .clock_seq_high_and_reserved = 0xbc,
    .clock_seq_low = 0x22,
    .node = .{ 0x00, 0x80, 0xc7, 0x3c, 0x88, 0x81 },
};

const acpi_10_guid = uefi.Guid{
    .time_low = 0xeb9d2d30,
    .time_mid = 0x2d88,
    .time_high_and_version = 0x11d3,
    .clock_seq_high_and_reserved = 0x9a,
    .clock_seq_low = 0x16,
    .node = .{ 0x00, 0x90, 0x27, 0x3f, 0xc1, 0x4d },
};

fn channelBits(mask: u32) struct { pos: u8, size: u8 } {
    if (mask == 0) return .{ .pos = 0, .size = 0 };
    return .{
        .pos = @intCast(@ctz(mask)),
        .size = @intCast(@popCount(mask)),
    };
}

inline fn shutdown(status: uefi.Status) noreturn {
    uefi.system_table.runtime_services.resetSystem(.shutdown, status, null);
}

fn drainKeyStroke(con_in: *uefi.protocol.SimpleTextInput) void {
    _ = con_in.readKeyStroke() catch |err| switch (err) {
        error.NotReady => {},
        else => shutdown(.aborted),
    };
}

pub fn main() noreturn {
    const string1: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Checkmate!\r\n");
    const string2: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Checkmate Confirmed.\r\n");
    const string3: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Press any key to shutdown (or wait to exit)\r\n");
    const string4: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("No Kernel Yet\r\n");

    const con_out = uefi.system_table.con_out orelse shutdown(.aborted);
    const con_in = uefi.system_table.con_in orelse shutdown(.aborted);
    const boot_services = uefi.system_table.boot_services orelse shutdown(.aborted);

    con_out.setAttribute(.{
        .background = .black,
        .foreground = .lightgray,
    }) catch shutdown(.aborted);
    con_out.clearScreen() catch shutdown(.aborted);
    _ = con_out.outputString(string1) catch shutdown(.aborted);
    _ = boot_services.stall(1_000_000) catch shutdown(.aborted);
    _ = con_out.outputString(string2) catch shutdown(.aborted);
    _ = boot_services.stall(3_000_000) catch shutdown(.aborted);

    con_out.setAttribute(.{ .background = .blue, .foreground = .lightgreen }) catch shutdown(.aborted);
    con_out.clearScreen() catch shutdown(.aborted);
    _ = con_out.outputString(string3) catch shutdown(.aborted);

    const timeout = boot_services.createEvent(.{ .timer = true }, .{}) catch shutdown(.aborted);
    boot_services.setTimer(timeout, .relative, 30_000_000) catch shutdown(.aborted);

    const res = boot_services.waitForEvent(&.{ con_in.wait_for_key, timeout }) catch shutdown(.aborted);
    if (res.@"1" == 0) {
        // Key was pressed: consume it if ready, show the "No Kernel Yet" screen, and shut down.
        drainKeyStroke(con_in);
        _ = boot_services.closeEvent(timeout) catch {};

        con_out.setAttribute(.{
            .background = .black,
            .foreground = .white,
        }) catch shutdown(.aborted);
        con_out.clearScreen() catch shutdown(.aborted);
        _ = con_out.outputString(string4) catch shutdown(.aborted);
        _ = boot_services.stall(2_000_000) catch shutdown(.aborted);
        shutdown(.aborted);
    }

    // Timer fired (or proceed to exitBootServices test): close timer first so no timer event stays open.
    _ = boot_services.closeEvent(timeout) catch {};

    // Allocate BootParams *before* taking the final memory map so we don't mutate the map after.
    const alloc_boot_info = boot_services.allocatePool(.loader_data, @sizeOf(kernel.BootParams)) catch shutdown(.out_of_resources);
    const boot_params: *kernel.BootParams = @ptrCast(@alignCast(alloc_boot_info));
    boot_params.* = std.mem.zeroes(kernel.BootParams);

    boot_params.acpi_rsp_addr = findAcpiRsdp(
        uefi.system_table.configuration_table[0..uefi.system_table.number_of_table_entries],
    );

    if (boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch shutdown(.aborted)) |g| {
        boot_params.screen_info.lfb_base = g.mode.frame_buffer_base;
        boot_params.screen_info.lfb_size = g.mode.frame_buffer_size;
        boot_params.screen_info.lfb_height = g.mode.info.vertical_resolution;
        boot_params.screen_info.lfb_width = g.mode.info.horizontal_resolution;

        const bytes_per_pixel: u32 = switch (g.mode.info.pixel_format) {
            .red_green_blue_reserved_8_bit_per_color,
            .blue_green_red_reserved_8_bit_per_color,
            => 4,
            .bit_mask => bytesFromBitmask(g.mode.info.pixel_information),
            .blt_only => 0,
        };
        boot_params.screen_info.lfb_linelength = g.mode.info.pixels_per_scan_line * bytes_per_pixel;
        boot_params.screen_info.lfb_depth = @intCast(bytes_per_pixel * 8);

        const blue_chan = channelBits(g.mode.info.pixel_information.blue_mask);
        const red_chan = channelBits(g.mode.info.pixel_information.red_mask);
        const green_chan = channelBits(g.mode.info.pixel_information.green_mask);
        const rsvd_chan = channelBits(g.mode.info.pixel_information.reserved_mask);

        boot_params.screen_info.blue_pos = blue_chan.pos;
        boot_params.screen_info.blue_size = blue_chan.size;
        boot_params.screen_info.red_pos = red_chan.pos;
        boot_params.screen_info.red_size = red_chan.size;
        boot_params.screen_info.green_pos = green_chan.pos;
        boot_params.screen_info.green_size = green_chan.size;
        boot_params.screen_info.rsvd_pos = rsvd_chan.pos;
        boot_params.screen_info.rsvd_size = rsvd_chan.size;
    }

    // Retry getMemoryMap + exitBootServices in case firmware updates the map key between calls.
    var exited = false;
    var attempt: usize = 0;
    while (attempt < 4) : (attempt += 1) {
        var memory_map = boot_services.getMemoryMap(&.{}) catch shutdown(.aborted);
        const buf_bytes = (memory_map.info.len + 8) * memory_map.info.descriptor_size;
        const DescAlign = @alignOf(uefi.tables.MemoryDescriptor);
        const raw_bytes = boot_services.allocatePool(.loader_data, buf_bytes) catch shutdown(.out_of_resources);
        const mmap_buffer: []align(DescAlign) u8 = @alignCast(raw_bytes);

        const pool = boot_services.allocatePages(.any, .loader_data, 256) catch shutdown(.out_of_resources);
        boot_params.pool_base_ptr = @intFromPtr(pool.ptr);
        boot_params.pool_len = pool.len * 4096;

        memory_map = boot_services.getMemoryMap(mmap_buffer) catch shutdown(.aborted);

        var count: u32 = 0;
        var descriptor_iterator = memory_map.iterator();
        while (descriptor_iterator.next()) |descriptor| : (count += 1) {
            if (count >= kernel.E820_MAX_ENTRIES) break;
            boot_params.e820_table[count] = .{
                .address = descriptor.physical_start,
                .size = descriptor.number_of_pages * 4096,
                .type = descriptor.type,
            };
        }
        boot_params.e820_entries = count;

        if (boot_services.exitBootServices(uefi.handle, memory_map.info.key)) |_| {
            exited = true;
            break;
        } else |_| {
            // Free/ignore failed attempt and loop to fetch a fresh memory map & key.
        }
    }

    if (!exited) {
        shutdown(.aborted);
    }

    // Boot services are now exited; runtime services remain available until resetSystem.
    shutdown(.success);
    unreachable;
}

fn handleKernel(boot: *uefi.tables.SystemTable, handle: uefi.Handle) kernel.Elf.ElfAllocInfo {
    const path: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("\\EFI\\CHECKMATE.BIN");
    const boot_services = boot.boot_services orelse shutdown(.aborted);
    const file_protocol = boot_services.handleProtocol(uefi.protocol.File, handle) catch shutdown(.protocol_unreachable);
    const filep = file_protocol orelse shutdown(.protocol_error);
    const file = filep.open(path, .read, .{ .read_only = true }) catch shutdown(.protocol_error);
    defer file.close() catch shutdown(.protocol_error);
    const size = file.readSize() catch shutdown(.protocol_error);

    if (size == 0) shutdown(.aborted);

    const buff = boot_services.allocatePages(.any, .loader_data, 512) catch shutdown(.out_of_resources);

    var fixed_buffer_alloc: std.heap.FixedBufferAllocator = .init(std.mem.sliceAsBytes(buff));

    const allocator = fixed_buffer_alloc.allocator();
    const file_buff = allocator.alloc(u8, size) catch shutdown(.out_of_resources);

    const bytes_read = file.read(file_buff) catch shutdown(.aborted);

    if (size != bytes_read) shutdown(.aborted);

    return kernel.Elf.loadMinimal(allocator, file_buff, buff) catch shutdown(.aborted);
}
