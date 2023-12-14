const std = @import("std");
const gpio = @import("gpio");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    var dir = try std.fs.openDirAbsolute("/dev", .{});
    defer dir.close();

    var args = std.process.args();
    _ = args.skip(); // Skip the program name

    // Iterate over each argument
    while (args.next()) |arg| {
        const fl = try dir.openFileZ(arg, .{});
        var chip = try gpio.getChipByFd(fl.handle);
        defer chip.close(); // This will close the fd

        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s} - {d} lines:\n", .{ chip.nameSlice(), chip.lines });

        var offset: u32 = 0;
        while (offset < chip.lines) : (offset += 1) {
            const lineInfo = try chip.getLineInfo(offset);

            // Create an arraylist to store all the flag strings
            var flags = std.ArrayList([]const u8).init(alloc);
            defer flags.deinit();

            // Appand any relevant flag strings to the array list
            if (lineInfo.flags.input) try flags.append("input");
            if (lineInfo.flags.output) try flags.append("output");
            if (lineInfo.flags.used) try flags.append("used");
            if (lineInfo.flags.active_low) try flags.append("active_low");
            if (lineInfo.flags.edge_rising) try flags.append("edge_rising");
            if (lineInfo.flags.edge_falling) try flags.append("edge_falling");
            if (lineInfo.flags.open_drain) try flags.append("open_drain");
            if (lineInfo.flags.open_source) try flags.append("open_source");
            if (lineInfo.flags.bias_pull_up) try flags.append("bias_pull_up");
            if (lineInfo.flags.bias_pull_down) try flags.append("bias_pull_down");

            // Join the array list into a string
            const flagStr = try std.mem.join(alloc, ", ", flags.items);
            defer alloc.free(flagStr);

            const name = if (lineInfo.name[0] != 0) lineInfo.nameSlice() else "<unnamed>";
            const consumer = if (lineInfo.flags.used) lineInfo.consumerSlice() else "<unused>";

            try stdout.print("    line {d}: {s} {s} [{s}]\n", .{ offset, name, consumer, flagStr });
        }
    }
}
