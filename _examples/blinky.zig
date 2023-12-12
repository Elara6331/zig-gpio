const std = @import("std");
const gpio = @import("gpio");

pub fn main() !void {
    var chip = try gpio.getChip("/dev/gpiochip2");
    defer chip.close();
    try chip.setConsumer("blinky");

    std.debug.print("Chip Name: {s}\n", .{chip.name});

    var line = try chip.requestLine(22, .{ .output = true });
    defer line.close();
    while (true) {
        try line.setHigh();
        std.time.sleep(std.time.ns_per_s);
        try line.setLow();
        std.time.sleep(std.time.ns_per_s);
    }
}
