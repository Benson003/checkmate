const std = @import("std");

const uefi = std.os.uefi;

pub fn main() noreturn {
    const string1: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Checkmate!\r\n");
    const string2: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Checkmate Confirmed.\r\n");
    const string3: [*:0]const u16 = comptime std.unicode.utf8ToUtf16LeStringLiteral("Press any key to shutdown\r\n");
    const con_out = uefi.system_table.con_out.?;
    const con_in = uefi.system_table.con_in.?;
    const boot_services = uefi.system_table.boot_services.?;
    var runtime_services = uefi.system_table.runtime_services.*;
    con_out.setAttribute(.{
        .background = .black,
        .foreground = .lightgray,
    }) catch unreachable;
    con_out.clearScreen() catch unreachable;
    _ = con_out.outputString(string1) catch unreachable;
    _ = boot_services.stall(1_000_000) catch unreachable;
    _ = con_out.outputString(string2) catch unreachable;
    _ = boot_services.stall(3_000_000) catch unreachable;
    con_out.clearScreen() catch unreachable;
    con_out.setAttribute(.{ .background = .blue, .foreground = .red }) catch unreachable;
    _ = con_out.outputString(string3) catch unreachable;
    _ = boot_services.waitForEvent(&.{con_in.wait_for_key}) catch unreachable;
    _ = con_in.readKeyStroke() catch unreachable;
    runtime_services.resetSystem(.shutdown, .success, null);
    // This should never return
}
