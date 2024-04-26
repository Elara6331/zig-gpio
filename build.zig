const std = @import("std");

const Item = struct {
    name: []const u8,
    src: []const u8,
};

/// List of examples
const examples = [_]Item{
    .{ .name = "blinky", .src = "src/examples/blinky.zig" },
    .{ .name = "multi", .src = "src/examples/multi.zig" },
};

/// List of commands
const commands = [_]Item{
    .{ .name = "gpiodetect", .src = "src/cmd/detect.zig" },
    .{ .name = "gpioinfo", .src = "src/cmd/info.zig" },
    .{ .name = "gpioget", .src = "src/cmd/get.zig" },
    .{ .name = "gpioset", .src = "src/cmd/set.zig" },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add the gpio module so it can be used by the package manager
    const gpio_module = b.createModule(.{ .root_source_file = .{ .path = "src/index.zig" } });
    try b.modules.put(b.dupe("gpio"), gpio_module);

    // Create a step to build all the examples
    const examples_step = b.step("examples", "build all the examples");

    // Add all the examples
    inline for (examples) |cfg| {
        const desc = try std.fmt.allocPrint(b.allocator, "build the {s} example", .{cfg.name});
        const step = b.step(cfg.name, desc);

        const exe = b.addExecutable(.{
            .name = cfg.name,
            .root_source_file = .{ .path = cfg.src },
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("gpio", gpio_module);

        const build_step = b.addInstallArtifact(exe, .{});
        step.dependOn(&build_step.step);
        examples_step.dependOn(&build_step.step);
    }

    // Create a step to build all the commands
    const commands_step = b.step("commands", "build all the commands");

    // Add all the commands
    inline for (commands) |cfg| {
        const desc = try std.fmt.allocPrint(b.allocator, "build the {s} command", .{cfg.name});
        const step = b.step(cfg.name, desc);

        const exe = b.addExecutable(.{
            .name = cfg.name,
            .root_source_file = .{ .path = cfg.src },
            .target = target,
            .optimize = optimize,
        });
        exe.root_module.addImport("gpio", gpio_module);

        const build_step = b.addInstallArtifact(exe, .{});
        step.dependOn(&build_step.step);
        commands_step.dependOn(&build_step.step);
    }
}
