const std = @import("std");
const gpio = @import("gpio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    const stdout = std.io.getStdOut().writer();

    if (args.len < 3) {
        try stdout.print("Usage: {s} <gpiochip> <line...>\n\n", .{args[0]});
        return error.InsufficientArguments;
    }

    var path: []const u8 = if (hasPrefix(args[1], "gpiochip"))
        try std.mem.concat(alloc, u8, &.{ "/dev/", args[1] })
    else
        try std.mem.concat(alloc, u8, &.{ "/dev/gpiochip", args[1] });
    defer alloc.free(path);

    var chip = try gpio.getChip(path);
    defer chip.close();
    try chip.setConsumer("gpioget");

    var offsets = std.ArrayList(u32).init(alloc);
    defer offsets.deinit();

    // Iterate over each argument starting from the second one
    for (args[2..args.len]) |argument| {
        // Parse each argument as an integer and add it to offsets
        var offset = try std.fmt.parseInt(u32, argument, 10);
        try offsets.append(offset);
    }

    var lines = try chip.requestLines(offsets.items, .{ .input = true });
    defer lines.close();
    const vals = try lines.getValues();

    var i: u32 = 0;
    while (i < args.len - 2) : (i += 1) {
        const value: u1 = if (vals.isSet(i)) 1 else 0;
        try stdout.print("{d} ", .{value});
    }

    try stdout.writeByte('\n');
}

fn hasPrefix(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return (std.mem.eql(u8, s[0..prefix.len], prefix));
}
