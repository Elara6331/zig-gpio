const std = @import("std");
const gpio = @import("gpio");

pub fn main() !void {
    var iter_dir = try std.fs.openDirAbsolute("/dev", .{ .iterate = true });
    defer iter_dir.close();

    const stdout = std.io.getStdOut().writer();

    var iter = iter_dir.iterate();
    while (try iter.next()) |entry| {
        if (!hasPrefix(entry.name, "gpiochip")) continue;

        const fl = try iter_dir.openFile(entry.name, .{});
        var chip = try gpio.getChipByFd(fl.handle);
        defer chip.close(); // This will close the fd

        try stdout.print("{s} [{s}] ({d} lines)\n", .{ chip.nameSlice(), chip.labelSlice(), chip.lines });
    }
}

fn hasPrefix(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return (std.mem.eql(u8, s[0..prefix.len], prefix));
}
