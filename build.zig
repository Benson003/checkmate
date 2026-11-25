// Copyright (c) 2026 Onyedika Nwankwo Benson
// All rights reserved.
//
// This source code is licensed under the BSD 3-Clause License found in the
// LICENSE file in the root directory of this source tree.
const std = @import("std");
const fmt = std.fmt.comptimePrint;
const DISK_NAME = "disk";
const DISK_EXT = "img";

pub fn build(b: *std.Build) void {
    // Target UEFI for BOOTX64.EFI
    const boot_uefi_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });

    // Target Freestanding for the Kernel
    const kernel_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
    });

    const optimize = b.standardOptimizeOption(.{});

    const boot_uefi_mod = b.createModule(.{
        .root_source_file = b.path("boot/uefi/main.zig"),
        .target = boot_uefi_target,
        .optimize = optimize,
    });

    const kernel_mod = b.createModule(.{
        .root_source_file = b.path("kernel/kernel.zig"),
        .optimize = optimize,
        .target = kernel_target,
    });
    boot_uefi_mod.addImport("kernel", kernel_mod);

    const efi = b.addExecutable(.{
        .root_module = boot_uefi_mod,
        .name = "BOOTX64",
        .use_llvm = true,
        .linkage = .static,
        .use_lld = true,
    });

    const kernel = b.addExecutable(.{
        .name = "checkmate",
        .root_module = kernel_mod,
        .use_llvm = true,
        .linkage = .static,
        .use_lld = true,
    });

    // These steps are there to build the img file QEMU will run
    // This creates a blank image of size 64 M
    const make_image = b.addSystemCommand(&.{
        "dd",
        "if=/dev/zero",
        fmt("of={s}.{s}", .{ DISK_NAME, DISK_EXT }),
        "bs=1M",
        "count=64",
    });
    make_image.step.dependOn(&efi.step);

    // This is to format the img file to FAT32
    const mkfs = b.addSystemCommand(&.{
        "mkfs.fat",
        "-F",
        "32",
        fmt("{s}.{s}", .{ DISK_NAME, DISK_EXT }),
    });
    mkfs.step.dependOn(&make_image.step);

    // This is to make the directory for the /EFI/BOOT
    const mmd = b.addSystemCommand(&.{
        "mmd",
        "-i",
        fmt("{s}.{s}", .{ DISK_NAME, DISK_EXT }),
        "::/EFI",
        "::/EFI/BOOT",
    });

    mmd.step.dependOn(&mkfs.step);

    // This is to copy the the efi binary to /EFI/BOOT/BOOTX64.EFI
    const emcopy = b.addSystemCommand(&.{
        "mcopy",
        "-i",
        fmt("{s}.{s}", .{ DISK_NAME, DISK_EXT }),
    });
    emcopy.addFileArg(efi.getEmittedBin());
    emcopy.addArg("::/EFI/BOOT/BOOTX64.EFI");
    emcopy.step.dependOn(&mmd.step);

    // This is to copy the the kernel binary to /EFI/CHECKMATE.BIN
    const kmcopy = b.addSystemCommand(&.{
        "mcopy",
        "-i",
        fmt("{s}.{s}", .{ DISK_NAME, DISK_EXT }),
    });

    kmcopy.addFileArg(kernel.getEmittedBin());
    kmcopy.addArg("::/EFI/CHECKMATE.BIN");
    kmcopy.step.dependOn(&mmd.step);

    b.getInstallStep().dependOn(&emcopy.step);
    b.installArtifact(efi);
    b.installArtifact(kernel);

    const qemu_run = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-machine",
        "q35",
        "-m",
        "256M",
        "-drive",
        fmt("if=ide,format=raw,file={s}.{s}", .{ DISK_NAME, DISK_EXT }),
        "-bios",
        "/usr/share/edk2/x64/OVMF.4m.fd",
        "-serial",
        "stdio",
        "-no-reboot",
    });
    qemu_run.step.dependOn(&emcopy.step);
    qemu_run.step.dependOn(&kmcopy.step);

    const run_step = b.step("run", "Boot disk.img in QEMU with OVMF");
    run_step.dependOn(&qemu_run.step);
}
