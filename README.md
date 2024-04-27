# zig-gpio

**zig-gpio** is a Zig library for controlling GPIO lines on Linux systems

This library can be used to access GPIO on devices such as [Raspberry Pis](https://www.raspberrypi.com/) or the [Milk-V Duo](https://milkv.io/duo) (which is the board I created it for and tested it with).

This is my first Zig project, so I'm open to any suggestions!

_There's a companion article available on my website: https://www.elara.ws/articles/milkv-duo._

## Compatibility

**zig-gpio** uses the v2 character device API, which means it will work on any Linux system running kernel 5.10 or above. All you need to do is find out which `gpiochip` device controls which pin and what the offsets are, which you can do by either finding documentation online, or using the `gpiodetect` and `gpioinfo` tools from this repo or from `libgpiod`.

## Commands

**zig-gpio** provides replacements for some of the `libgpiod` tools, such as `gpiodetect` and `gpioinfo`. You can build all of them using `zig build commands` or specific ones using `zig build <command>` (for example: `zig build gpiodetect`).

## Try it yourself!

Here's an example of a really simple program that requests pin 22 from `gpiochip2` and makes it blink at a 1 second interval. That pin offset is the LED of a Milk-V Duo board, so if you're using a different board, make sure to change it.

```zig
const std = @import("std");
const gpio = @import("gpio");

pub fn main() !void {
    var chip = try gpio.getChip("/dev/gpiochip2");
    defer chip.close();
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
```

For more examples, see the [_examples](_examples) directory. You can build all the examples using the `zig build examples` command.

## Using zig-gpio in your project

If you don't have a zig project already, you can create one by running `zig init-exe` in a new folder.

To add `zig-gpio` as a dependency, there are two steps:

1. Add `zig-gpio` to your `build.zig.zon` file
2. Add `zig-gpio` to your `build.zig` file

If you don't have a `build.zig.zon` file, create one. If you do, just add `zig-gpio` as a dependency. Here's what it should look like:

```zig
.{
    .name = "my_project",
    .version = "0.0.1",

    .dependencies = .{
        .gpio = .{
            .url = "https://gitea.elara.ws/Elara6331/zig-gpio/archive/v0.0.2.tar.gz",
            .hash = "1220e3af3194d1154217423d60124ae3a46537c2253dbfb8057e9b550526d2885df1",
        }
    }
}
```

Then, in your `build.zig` file, add the following before `b.installArtifact(exe)`:

```zig
const gpio = b.dependency("gpio", .{
    .target = target,
    .optimize = optimize,
});
exe.addModule("gpio", gpio.module("gpio"));
```

And that's it! You should now be able to use `zig-gpio` via `@import("gpio");`