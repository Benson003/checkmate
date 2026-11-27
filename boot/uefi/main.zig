// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const uefi = std.os.uefi;
const kernel = @import("kernel");

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
fn shutdown(status: uefi.Status, msg: []const u8) noreturn {
    if (uefi.system_table.con_out) |con_out| {
        con_out.setAttribute(.{ .background = .blue, .foreground = .lightgreen }) catch {};

        var utf16_buf: [256:0]u16 = @splat(0);
        const len = std.unicode.utf8ToUtf16Le(&utf16_buf, msg) catch 0;
        utf16_buf[len] = 0;

        _ = con_out.outputString(&utf16_buf) catch {};
    }

    uefi.system_table.runtime_services.resetSystem(.shutdown, status, null);
}
fn drainKeyStroke(con_in: *uefi.protocol.SimpleTextInput) void {
    _ = con_in.readKeyStroke() catch |err| switch (err) {
        error.NotReady => {},
        else => shutdown(.aborted, "failed to drain key"),
    };
}

pub fn main() noreturn {
    const string1: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Checkmate!\r\n");
    const string2: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Checkmate Confirmed.\r\n");
    const string3: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Press any key to shutdown (or wait to exit)\r\n");
    const string4: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("No Kernel Yet\r\n");

    const con_out = uefi.system_table.con_out orelse shutdown(.aborted, "failed to find con out");
    const con_in = uefi.system_table.con_in orelse shutdown(.aborted, "failed to find con in");
    const boot_services = uefi.system_table.boot_services orelse shutdown(.aborted, "failed to find boot boot_services");

    con_out.setAttribute(.{
        .background = .black,
        .foreground = .lightgray,
    }) catch shutdown(.aborted, "failed to set set attribute");
    con_out.clearScreen() catch shutdown(.aborted, "failed to clear screen");
    _ = con_out.outputString(string1) catch shutdown(.aborted, "failed to output string");
    _ = boot_services.stall(1_000_000) catch shutdown(.aborted, "failed to stall");
    _ = con_out.outputString(string2) catch shutdown(.aborted, "failed to output string");
    _ = boot_services.stall(3_000_000) catch shutdown(.aborted, "failed to stall");

    con_out.setAttribute(.{ .background = .blue, .foreground = .lightgreen }) catch shutdown(.aborted, "failed to set attribute");
    con_out.clearScreen() catch shutdown(.aborted, "failed to clear screen");
    _ = con_out.outputString(string3) catch shutdown(.aborted, "failed to print text");

    const timeout = boot_services.createEvent(.{ .timer = true }, .{}) catch shutdown(.aborted, "failed to create event");
    boot_services.setTimer(timeout, .relative, 30_000_000) catch shutdown(.aborted, "failed to set timer");

    const res = boot_services.waitForEvent(&.{ con_in.wait_for_key, timeout }) catch shutdown(.aborted, "failed to wait for event");
    if (res.@"1" == 0) {
        // Key was pressed: consume it if ready, show the "No Kernel Yet" screen, and shut down.
        drainKeyStroke(con_in);
        _ = boot_services.closeEvent(timeout) catch {};

        con_out.setAttribute(.{
            .background = .black,
            .foreground = .white,
        }) catch shutdown(.aborted, "failed to set attribute");
        con_out.clearScreen() catch shutdown(.aborted, "failed to clear screen");
        _ = con_out.outputString(string4) catch shutdown(.aborted, "failed to output string");
        _ = boot_services.stall(2_000_000) catch shutdown(.aborted, "failed to stall");
        shutdown(.aborted, "key pressed shuting down");
    }

    // Timer fired (or proceed to exitBootServices test): close timer first so no timer event stays open.
    _ = boot_services.closeEvent(timeout) catch {};

    const loaded_kernel = handleKernel(uefi.system_table, uefi.handle);

    // 1. Allocate ALL resources BEFORE starting the EBS retry loop
    const stack_pages = boot_services.allocatePages(.any, .loader_data, 8) catch shutdown(.out_of_resources, "failed to allocate stack");
    const stack_base: u64 = @intFromPtr(stack_pages.ptr);
    const stack_size: u64 = stack_pages.len * 4096;
    const stack_top: u64 = std.mem.alignBackward(u64, stack_base + stack_size, 16);

    const alloc_boot_info = boot_services.allocatePool(.loader_data, @sizeOf(kernel.BootParams)) catch shutdown(.out_of_resources, "failed to allocate boot info");
    const boot_params: *kernel.BootParams = @ptrCast(@alignCast(alloc_boot_info));
    boot_params.* = std.mem.zeroes(kernel.BootParams);

    boot_params.acpi_rsp_addr = findAcpiRsdp(
        uefi.system_table.configuration_table[0..uefi.system_table.number_of_table_entries],
    );

    if (boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch shutdown(.aborted, "failed to locate protocol")) |g| {
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

    // Allocate the kernel heap pool ONCE before the loop
    const pool = boot_services.allocatePages(.any, .loader_data, 256) catch shutdown(.out_of_resources, "failed to allocate heap pool");
    boot_params.pool_base_ptr = @intFromPtr(pool.ptr);
    boot_params.pool_len = pool.len * 4096;

    _ = con_out.outputString(comptime std.unicode.utf8ToUtf16LeStringLiteral("Before EBS\r\n")) catch {};
    boot_services.stall(1_000_000) catch {};

    // 2. The Retry Loop: Only fetch map and attempt exit
    var exited = false;
    var attempt: usize = 0;
    while (attempt < 4) : (attempt += 1) {
        const map_info = boot_services.getMemoryMapInfo() catch shutdown(.aborted, "failed to get memory map info");

        // Add padding to account for the buffer allocation itself
        const padded_len = map_info.len + 32;
        const buf_bytes = padded_len * map_info.descriptor_size;
        const DescAlign = @alignOf(uefi.tables.MemoryDescriptor);

        const raw_bytes = boot_services.allocatePool(.loader_data, buf_bytes) catch shutdown(.out_of_resources, "failed to get pool allocation");
        const mmap_buffer: []align(DescAlign) u8 = @alignCast(raw_bytes);

        const memory_map = boot_services.getMemoryMap(mmap_buffer) catch {
            boot_services.freePool(raw_bytes.ptr) catch {};
            continue;
        };

        // Parse the map into BootParams
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

        con_out.setAttribute(.{ .background = .black, .foreground = .lightgray }) catch {};
        con_out.clearScreen() catch {};
        // Do not call conn_out or conn_in or any boot_services after this do not even try,
        // I spent a good one hour banging my head against the wall we may or may not leak memory the kenrle will dertarmine what it can reclaim
        //
        boot_services.exitBootServices(uefi.handle, memory_map.info.key) catch {
            boot_services.freePool(raw_bytes.ptr) catch {};
            continue;
        };
        @constCast(&boot_services).* = undefined;

        exited = true;
        break;
    }

    if (!exited) shutdown(.aborted, "failed to exit boot services after 4 attempts");

    const entry: u64 = loaded_kernel.entry_point;
    const boot_info_addr: u64 = @intFromPtr(boot_params);

    asm volatile (
        \\mov %[stack_top], %%rsp
        \\xor %%rbp, %%rbp
        \\mov %[boot_info], %%rdi
        \\jmp *%[entry]
        :
        : [stack_top] "r" (stack_top),
          [entry] "r" (entry),
          [boot_info] "r" (boot_info_addr),
        : .{
          .memory = true,
          .rbp = true,
          .rdi = true,
        });
    unreachable;
}

pub fn handleKernel(
    boot: *uefi.tables.SystemTable,
    handle: uefi.Handle,
) struct {
    base_address: u64,
    entry_point: u64,
    span_bytes: u64,
} {
    const path: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("\\EFI\\CHECKMATE.BIN");
    const boot_services = boot.boot_services orelse shutdown(
        .aborted,
        "failed to find boot_services for kernel",
    );
    const loaded_image = (boot_services.handleProtocol(
        uefi.protocol.LoadedImage,
        handle,
    ) catch shutdown(
        .protocol_unreachable,
        "failed loaded image protocol",
    )) orelse shutdown(
        .protocol_error,
        "loaded image not available",
    );
    const dev_handle = loaded_image.device_handle orelse shutdown(
        .protocol_error,
        "missing device handle",
    );
    const fs = (boot_services.handleProtocol(uefi.protocol.SimpleFileSystem, dev_handle) catch shutdown(
        .protocol_unreachable,
        "failed device file protocol",
    )) orelse shutdown(
        .protocol_error,
        "device file protocol not available",
    );
    const root_dir = fs.openVolume() catch shutdown(
        .protocol_error,
        "failed to open open volume",
    );
    defer root_dir.close() catch shutdown(
        .protocol_error,
        "failed to close root dir",
    );
    const file = root_dir.open(path, .read, .{ .read_only = true }) catch shutdown(.protocol_error, "failed to read file");
    defer file.close() catch shutdown(.protocol_error, "failed to close file");
    var info_buf: [512]u8 align(@alignOf(uefi.protocol.File.Info.File)) = undefined;
    const file_info = file.getInfo(
        .file,
        &info_buf,
    ) catch shutdown(.protocol_error, "failed to get size of file");
    const size: usize = @intCast(file_info.file_size);

    if (size == 0) shutdown(.aborted, "file size is zero");

    const buff = boot_services.allocatePages(.any, .loader_data, 512) catch shutdown(.out_of_resources, "failed to allocate pages for fixed buffer");

    var fixed_buffer_alloc: std.heap.FixedBufferAllocator = .init(std.mem.sliceAsBytes(buff));

    const allocator = fixed_buffer_alloc.allocator();
    const file_buff = allocator.alloc(u8, size) catch shutdown(.out_of_resources, "failed to allocate on fixed buffer");

    const bytes_read = file.read(file_buff) catch shutdown(.aborted, "failed to read the bytes from the file");

    if (size != bytes_read) shutdown(.aborted, "file may be truncated");

    const kernel_elf = kernel.Elf.loadElf(allocator, file_buff) catch |err| switch (err) {
        error.BufferTooSmallForHeader => shutdown(.aborted, "buffer to small for header"),
        error.InvalidMagicBytes => shutdown(.aborted, "invalid elf magic bytee"),
        error.InvalidArchBitWidth => shutdown(.aborted, "invalid bit width"),
        error.InvalidEndianness => shutdown(.aborted, "invalid endianness"),
        error.InvalidIdentVersionOrAbi => shutdown(.aborted, "invalid abi and/or ident"),
        error.InvalidProgramHeaderEntrySize => shutdown(.aborted, "invalid program header entry size"),
        error.ZeroProgramHeaders => shutdown(.aborted, "zero program headers"),
        error.InvalidMachineType => shutdown(.aborted, "invalid machine type"),
        error.InvalidHeaderVersion => shutdown(.aborted, "invalid header version"),
        error.OutOfMemory => shutdown(.aborted, "out of memory"),
        error.ProgramHeaderTableOutOfBounds => shutdown(.aborted, "program header table OOB"),
    };
    // 1. Generate a random offset for ASLR (e.g., up to 1GB)
    const uefi_rng = (boot_services.locateProtocol(uefi.protocol.Rng, null) catch shutdown(
        .protocol_unreachable,
        "failed to locate rng protocol",
    )) orelse shutdown(.protocol_error, "rng protocol not found");

    var rng_buff: [8]u8 = undefined;
    uefi_rng.getRNG(null, &rng_buff) catch shutdown(.protocol_error, "failed to generate rng");

    // Create a random offset between 0 and 1GB, page-aligned
    const random_offset = (std.mem.readInt(u64, &rng_buff, .little) % (1024 * 1024 * 1024)) & ~@as(u64, 0xFFF);

    // Add it to a safe baseline (e.g., 256MB) to avoid low-memory firmware reservations
    const desired_phys_addr: u64 = 0x10000000 + random_offset;

    // 2. Calculate required pages
    var min_vaddr: ?u64 = null;
    var max_end: ?u64 = null;
    for (kernel_elf.segments) |s| {
        if (s.type != .PT_LOAD) continue;
        const seg_end = std.math.add(u64, s.vaddr, s.memsz) catch shutdown(.aborted, "segment size overflow");
        if (min_vaddr == null or s.vaddr < min_vaddr.?) min_vaddr = s.vaddr;
        if (max_end == null or seg_end > max_end.?) max_end = seg_end;
    }

    const base_vaddr = min_vaddr orelse shutdown(.aborted, "no PT_LOAD segments");
    const end_vaddr = max_end orelse shutdown(.aborted, "no PT_LOAD segments");
    const span_bytes = end_vaddr - base_vaddr;
    const aligned_span = std.mem.alignForward(u64, span_bytes, 4096);
    const page_count = aligned_span / 4096;
    if (page_count == 0) shutdown(.aborted, "zero pages required");

    // 3. Try to allocate at our random address. If firmware reserves it, fall back to .any
    const kernel_mem = boot_services.allocatePages(.{ .address = @ptrFromInt(desired_phys_addr) }, .loader_data, page_count) catch boot_services.allocatePages(.any, .loader_data, page_count) catch
        shutdown(.out_of_resources, "failed to allocate pages for kernel");

    const kernel_bytes: []u8 = @as([*]u8, @ptrCast(kernel_mem))[0 .. page_count * 4096];
    // 4. Calculate the REAL load bias based on where it ACTUALLY ended up
    const phys_base: u64 = @intFromPtr(kernel_bytes.ptr);
    const load_bias: u64 = phys_base - base_vaddr; // This is the true slide

    // 5. Copy segments (Your logic here was already perfect)
    for (kernel_elf.segments) |s| {
        if (s.type != .PT_LOAD) continue;
        if (s.memsz < s.filesz) shutdown(.aborted, "PT_LOAD memsz smaller than filesz");

        const src_end = std.math.add(u64, s.offset, s.filesz) catch shutdown(.aborted, "PT_LOAD file range overflow");
        if (src_end > file_buff.len) shutdown(.aborted, "PT_LOAD file range out of bounds");

        const rel_offset = s.vaddr - base_vaddr;
        const seg_end = std.math.add(u64, rel_offset, s.memsz) catch shutdown(.aborted, "PT_LOAD span overflow");
        if (seg_end > kernel_bytes.len) shutdown(.aborted, "PT_LOAD segment exceeds image span");

        const raw_dst = kernel_bytes[@intCast(rel_offset)..@intCast(seg_end)];
        const dst: []u8 = @as([*]u8, @ptrCast(raw_dst.ptr))[0..raw_dst.len];
        const fsz: usize = @intCast(s.filesz);

        if (s.filesz > 0) {
            const src = file_buff[@intCast(s.offset)..@intCast(src_end)];
            @memcpy(dst[0..fsz], src);
        }
        if (s.memsz > s.filesz) {
            @memset(dst[fsz..], 0); // Zero out .bss
        }
    }

    // 6. Apply Relocations (Your logic here was also excellent, just cleaned up slightly)
    const R_X86_64_RELATIVE: u32 = 8;
    var dyn_phdr: ?kernel.Elf.ProgramHeader = null;
    for (kernel_elf.segments) |s| {
        if (s.type == .PT_DYNAMIC) {
            if (dyn_phdr != null) shutdown(.aborted, "multiple PT_DYNAMIC segments");
            dyn_phdr = s;
        }
    }

    var rela_vaddr: ?u64 = null;
    var rela_size: u64 = 0;
    var rela_entsize: u64 = @sizeOf(kernel.Elf.Rela);

    if (dyn_phdr) |dyn_seg| {
        const dyn_end = std.math.add(u64, dyn_seg.offset, dyn_seg.filesz) catch shutdown(.aborted, "PT_DYNAMIC file range overflow");
        if (dyn_end > file_buff.len) shutdown(.aborted, "PT_DYNAMIC out of bounds");

        const dyn_bytes = file_buff[@intCast(dyn_seg.offset)..@intCast(dyn_end)];
        const dyn_count = dyn_bytes.len / @sizeOf(kernel.Elf.Dyn);

        var i: usize = 0;
        while (i < dyn_count) : (i += 1) {
            const entry = std.mem.bytesToValue(kernel.Elf.Dyn, dyn_bytes[i * @sizeOf(kernel.Elf.Dyn) ..][0..@sizeOf(kernel.Elf.Dyn)]);
            switch (entry.d_tag) {
                .DT_NULL => break,
                .DT_RELA => rela_vaddr = entry.d_un.d_ptr,
                .DT_RELASZ => rela_size = entry.d_un.d_val,
                .DT_RELAENT => {
                    if (entry.d_un.d_val != 0) rela_entsize = entry.d_un.d_val;
                },
                else => {},
            }
        }
    }

    if (rela_vaddr) |rv| {
        if (rv < base_vaddr) shutdown(.aborted, "DT_RELA below base_vaddr");
        const rela_rel_off = rv - base_vaddr;
        const rela_end = std.math.add(u64, rela_rel_off, rela_size) catch shutdown(.aborted, "DT_RELA range overflow");
        if (rela_end > kernel_bytes.len) shutdown(.aborted, "DT_RELA out of kernel_bytes bounds");

        const rela_bytes = kernel_bytes[@intCast(rela_rel_off)..@intCast(rela_end)];
        const entsz: usize = @intCast(rela_entsize);
        const count = rela_bytes.len / entsz;

        // This is the true slide (load_bias)
        const phys_slide: i64 = @bitCast(load_bias);

        var idx: usize = 0;
        while (idx < count) : (idx += 1) {
            const entry_slice = rela_bytes[idx * entsz ..][0..@sizeOf(kernel.Elf.Rela)];
            const rela = std.mem.bytesToValue(kernel.Elf.Rela, entry_slice);
            const r_type: u32 = @truncate(rela.r_info);

            if (r_type == R_X86_64_RELATIVE) {
                if (rela.r_offset < base_vaddr) shutdown(.aborted, "relocation target below base_vaddr");
                const slot_rel_off = rela.r_offset - base_vaddr;
                const slot_end = std.math.add(u64, slot_rel_off, @sizeOf(u64)) catch shutdown(.aborted, "relocation slot overflow");
                if (slot_end > kernel_bytes.len) shutdown(.aborted, "relocation target out of bounds");

                const patched_signed: i64 = phys_slide +% rela.r_addend;
                const patched_val: u64 = @bitCast(patched_signed);
                std.mem.writeInt(u64, kernel_bytes[@intCast(slot_rel_off)..][0..8], patched_val, .little);
            } else if (r_type != 0) {
                shutdown(.aborted, "unsupported relocation type");
            }
        }
    }

    // 7. RETURN THE CORRECT VALUES
    return .{
        .base_address = phys_base,
        .entry_point = kernel_elf.entry_point + load_bias, // Crucial: bias the entry point!
        .span_bytes = aligned_span,
    };
}
