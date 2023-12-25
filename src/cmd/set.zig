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
        try stdout.print("Usage: {s} <gpiochip> <line=value...>\n\n", .{args[0]});
        return error.InsufficientArguments;
    }

    var path: []const u8 = if (hasPrefix(args[1], "gpiochip"))
        try std.mem.concat(alloc, u8, &.{ "/dev/", args[1] })
    else
        try std.mem.concat(alloc, u8, &.{ "/dev/gpiochip", args[1] });
    defer alloc.free(path);

    var chip = try gpio.getChip(path);
    defer chip.close();
    try chip.setConsumer("gpioset");

    var values = std.AutoArrayHashMap(u32, bool).init(alloc);
    defer values.deinit();

    // Iterate over each argument starting from the second one
    for (args[2..args.len]) |argument| {
        // Get the index of the equals sign in the argument
        const eqIndex = std.mem.indexOf(u8, argument, "=") orelse return error.InvalidArgument;
        // Parse each argument's offset and value, and add it to the values map
        var offset = try std.fmt.parseUnsigned(u32, argument[0..eqIndex], 10);
        var value = try std.fmt.parseUnsigned(u1, argument[eqIndex + 1 .. argument.len], 10);
        try values.put(offset, value != 0);
    }

    var lines = try chip.requestLines(values.keys(), .{ .output = true });
    defer lines.close();

    var vals = gpio.uapi.LineValueBitset{ .mask = 0 };
    for (0.., values.values()) |i, val| vals.setValue(i, val);
    try lines.setAllValues(vals);
}

fn hasPrefix(s: []const u8, prefix: []const u8) bool {
    if (s.len < prefix.len) return false;
    return (std.mem.eql(u8, s[0..prefix.len], prefix));
}
