# zig-gpio

**zig-gpio** is a Zig library for controlling GPIO lines on Linux systems

This library can be used to access GPIO on devices such as [Raspberry Pis](https://www.raspberrypi.com/) or the [Milk-V Duo](https://milkv.io/duo) (which is the board I created it for and tested it with).

This is my first public Zig project, so I'm open to any suggestions!

## Compatibility

**zig-gpio** uses the v2 character device API, which means it will work on any Linux system running kernel 5.10 or above. All you need to do is find out which `gpiochip` device controls which pin and what the offsets are, which you can do by either finding documentation online, or using the `gpiodetect` and `gpioinfo` tools from `libgpiod`.

I plan to eventually write a Zig replacement for `gpiodetect` and `gpioinfo`. 

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