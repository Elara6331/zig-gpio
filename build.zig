const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var gpio_module = b.createModule(.{ .source_file = .{ .path = "index.zig" } });
    try b.modules.put(b.dupe("gpio"), gpio_module);

    const examples_step = b.step("examples", "build all the examples");

    inline for ([_]struct { name: []const u8, src: []const u8 }{
        .{ .name = "blinky", .src = "_examples/blinky.zig" },
        .{ .name = "multi", .src = "_examples/multi.zig" },
    }) |cfg| {
        const desc = try std.fmt.allocPrint(b.allocator, "build the {s} example", .{cfg.name});
        const step = b.step(cfg.name, desc);

        const exe = b.addExecutable(.{
            .name = cfg.name,
            .root_source_file = .{ .path = cfg.src },
            .target = target,
            .optimize = optimize,
        });
        exe.addModule("gpio", gpio_module);

        const build_step = b.addInstallArtifact(exe, .{});
        step.dependOn(&build_step.step);
        examples_step.dependOn(&build_step.step);
    }
}
