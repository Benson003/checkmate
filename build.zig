const std = @import("std");
const fmt = std.fmt.comptimePrint;
const DISK_NAME = "disk";
const DISK_EXT = "img";

pub fn build(b: *std.Build) void {
    const boot_uefi_target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });

    const optimize = b.standardOptimizeOption(.{});

    const boot_uefi = b.createModule(.{
        .root_source_file = b.path("boot/uefi/main.zig"),
        .target = boot_uefi_target,
        .optimize = optimize,
    });

    const efi = b.addExecutable(.{
        .root_module = boot_uefi,
        .name = "BOOTX64",
        .use_llvm = true,
        .linkage = .static,
    });

    const make_image = b.addSystemCommand(&.{
        "dd",
        "if=/dev/zero",
        fmt("of={s}.{s}", .{ DISK_NAME, DISK_EXT }),
        "bs=1M",
        "count=64",
    });

    make_image.step.dependOn(&efi.step);
    const mkfs = b.addSystemCommand(&.{
        "mkfs.fat",
        "-F",
        "32",
        fmt("{s}.{s}", .{ DISK_NAME, DISK_EXT }),
    });
    mkfs.step.dependOn(&make_image.step);
    const mmd = b.addSystemCommand(&.{
        "mmd",
        "-i",
        fmt("{s}.{s}", .{ DISK_NAME, DISK_EXT }),
        "::/EFI",
        "::/EFI/BOOT",
    });

    mmd.step.dependOn(&mkfs.step);
    const mcopy = b.addSystemCommand(&.{
        "mcopy",
        "-i",
        fmt("{s}.{s}", .{ DISK_NAME, DISK_EXT }),
    });
    mcopy.addFileArg(efi.getEmittedBin());
    mcopy.addArg("::/EFI/BOOT/BOOTX64.EFI");

    mcopy.step.dependOn(&mmd.step);

    b.getInstallStep().dependOn(&mcopy.step);

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
    qemu_run.step.dependOn(&mcopy.step);

    const run_step = b.step("run", "Boot disk.img in QEMU with OVMF");
    run_step.dependOn(&qemu_run.step);
}
