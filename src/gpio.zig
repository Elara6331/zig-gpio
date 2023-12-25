const std = @import("std");
const gpio = @import("index.zig");

/// Opens the file at path and uses the file descriptor to get the gpiochip.
pub fn getChip(path: []const u8) !Chip {
    var fl = try std.fs.openFileAbsolute(path, .{});
    return try getChipByFd(fl.handle);
}

/// Same as `getChip` but the `path` parameter is null-terminated.
pub fn getChipZ(path: [*:0]const u8) !Chip {
    var fl = try std.fs.openFileAbsoluteZ(path, .{});
    return try getChipByFd(fl.handle);
}

/// Returns a `chip` with the given file descriptor.
pub fn getChipByFd(fd: std.os.fd_t) !Chip {
    var info = try gpio.uapi.getChipInfo(fd);
    return Chip{
        .name = info.name,
        .label = info.label,
        .handle = fd,
        .lines = info.lines,
    };
}

/// Represents a single Linux `gpiochip` character device.
pub const Chip = struct {
    /// The name of the `gpiochip` device.
    name: [gpio.uapi.MAX_NAME_SIZE]u8,
    /// The label of the `gpiochip` device
    label: [gpio.uapi.MAX_NAME_SIZE]u8,
    /// An optional consumer value to use when requesting lines.
    /// Can be set using `set_consumer` or `set_consumer_z`.
    /// If it isn't set, "zig-gpio" will be used instead.
    consumer: ?[gpio.uapi.MAX_NAME_SIZE]u8 = null,
    /// The file descriptor of the `gpiochip` device.
    handle: std.os.fd_t,
    // The amount of lines available under this device.
    lines: u32,
    closed: bool = false,

    /// Returns the chip's name as a slice without any null characters
    pub fn nameSlice(self: *Chip) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    /// Returns the chip's label as a slice without any null characters
    pub fn labelSlice(self: *Chip) []const u8 {
        return std.mem.sliceTo(&self.label, 0);
    }

    /// Sets the chip's consumer value to `consumer`.
    pub fn setConsumer(self: *Chip, consumer: []const u8) !void {
        if (consumer.len > gpio.uapi.MAX_NAME_SIZE) return error.ConsumerTooLong;
        self.consumer = std.mem.zeroes([gpio.uapi.MAX_NAME_SIZE]u8);
        std.mem.copyForwards(u8, &self.consumer.?, consumer);
    }

    /// Same as setConsumer but the `consumer` parameter is null-terminated.
    pub fn setConsumerZ(self: *Chip, consumer: [*:0]const u8) !void {
        self.consumer = std.mem.zeroes([gpio.uapi.MAX_NAME_SIZE]u8);
        @memcpy(&self.consumer.?, consumer);
    }

    /// Returns information about the GPIO line at the given `offset`.
    pub fn getLineInfo(self: Chip, offset: u32) !gpio.uapi.LineInfo {
        if (self.closed) return error.ChipClosed;
        return gpio.uapi.getLineInfo(self.handle, offset);
    }

    /// Requests and returns a single line at the given `offset`, from the given `chip`.
    pub fn requestLine(self: Chip, offset: u32, flags: gpio.uapi.LineFlags) !Line {
        var l = try self.requestLines(&.{offset}, flags);
        return Line{ .lines = l };
    }

    /// Requests control of a collection of lines on the chip. If granted, control is maintained until
    /// the `lines` are closed.
    pub fn requestLines(self: Chip, offsets: []const u32, flags: gpio.uapi.LineFlags) !Lines {
        if (self.closed) return error.ChipClosed;
        if (offsets.len > gpio.uapi.MAX_LINES) return error.TooManyLines;

        var lr = std.mem.zeroes(gpio.uapi.LineRequest);
        lr.num_lines = @truncate(offsets.len);
        lr.config.flags = flags;

        if (self.consumer != null) {
            lr.consumer = self.consumer.?;
        } else {
            std.mem.copyForwards(u8, &lr.consumer, "zig-gpio");
        }

        for (0.., offsets) |i, offset| {
            if (offset >= self.lines) return error.OffsetOutOfRange;
            lr.offsets[i] = offset;
        }

        const line_fd = try gpio.uapi.getLine(self.handle, lr);
        return Lines{
            .handle = line_fd,
            .num_lines = lr.num_lines,
            .offsets = offsets,
        };
    }

    /// Releases all resources held by the `chip`.
    pub fn close(self: *Chip) void {
        if (self.closed) return;
        self.closed = true;
        std.os.close(self.handle);
    }
};

/// Represents a collection of lines requested from a `chip`.
pub const Lines = struct {
    /// The file descriptor of the lines.
    handle: std.os.fd_t,
    /// The amount of lines being controlled.
    num_lines: u32,
    /// The offsets of the lines being controlled.
    offsets: []const u32,
    closed: bool = false,

    /// Sets the lines at the given indices as high (on).
    ///
    /// Note that this function takes indices and not offsets.
    /// The indices correspond to the index of the offset in your request.
    /// For example, if you requested `&.{22, 20, 23}`,
    /// `22` will correspond to `0`, `20` will correspond to `1`,
    /// and `23` will correspond to `2`.
    pub fn setHigh(self: Lines, indices: []const u32) !void {
        if (self.closed) return error.LineClosed;

        var vals = gpio.uapi.LineValues{};
        for (indices) |index| {
            if (index >= self.num_lines) return error.IndexOutOfRange;
            vals.bits.set(index);
            vals.mask.set(index);
        }

        try gpio.uapi.setLineValues(self.handle, vals);
    }

    /// Sets the lines at the given indices as low (off).
    ///
    /// Note that this function takes indices and not offsets.
    /// The indices correspond to the index of the offset in your request.
    /// For example, if you requested `&.{22, 20, 23}`,
    /// `22` will correspond to `0`, `20` will correspond to `1`,
    /// and `23` will correspond to `2`.
    pub fn setLow(self: Lines, indices: []const u32) !void {
        if (self.closed) return error.LineClosed;

        var vals = gpio.uapi.LineValues{};
        for (indices) |index| {
            if (index >= self.num_lines) return error.IndexOutOfRange;
            vals.mask.set(index);
        }

        try gpio.uapi.setLineValues(self.handle, vals);
    }

    /// Sets the configuration flags of the lines at the given indices.
    ///
    /// Note that this function takes indices and not offsets.
    /// The indices correspond to the index of the offset in your request.
    /// For example, if you requested `&.{22, 20, 23}`,
    /// `22` will correspond to `0`, `20` will correspond to `1`,
    /// and `23` will correspond to `2`.
    pub fn reconfigure(self: Lines, indices: []const u32, flags: gpio.uapi.LineFlags) !void {
        var lc = std.mem.zeroes(gpio.uapi.LineConfig);
        lc.attrs[0] = gpio.uapi.LineConfigAttribute{
            .attr = .{
                .id = .Flags,
                .data = .{ .flags = flags },
            },
        };

        for (indices) |index| {
            if (index >= self.num_lines) return error.IndexOutOfRange;
            lc.attrs[0].mask.set(index);
        }

        try gpio.uapi.setLineConfig(self.handle, lc);
    }

    /// Sets the debounce period of the lines at the given indices.
    ///
    /// Note that this function takes indices and not offsets.
    /// The indices correspond to the index of the offset in your request.
    /// For example, if you requested `&.{22, 20, 23}`,
    /// `22` will correspond to `0`, `20` will correspond to `1`,
    /// and `23` will correspond to `2`.
    pub fn setDebouncePeriod(self: Lines, indices: []const u32, duration_us: u32) !void {
        var lc = std.mem.zeroes(gpio.uapi.LineConfig);
        lc.attrs[0] = gpio.uapi.LineConfigAttribute{
            .attr = .{
                .id = .Debounce,
                .data = .{ .debounce_period_us = duration_us },
            },
        };

        for (indices) |index| {
            if (index >= self.num_lines) return error.IndexOutOfRange;
            lc.attrs[0].mask.set(index);
        }

        try gpio.uapi.setLineConfig(self.handle, lc);
    }

    /// Sets the values of the lines at the given indices.
    ///
    /// Note that this function takes indices and not offsets.
    /// The indices correspond to the index of the offset in your request.
    /// For example, if you requested `&.{22, 20, 23}`,
    /// `22` will correspond to `0`, `20` will correspond to `1`,
    /// and `23` will correspond to `2`.
    pub fn setValues(self: Lines, indices: []const u32, vals: gpio.uapi.LineValueBitset) !void {
        if (self.closed) return error.LineClosed;
        var lv = gpio.uapi.LineValues{ .bits = vals };
        for (indices) |index| {
            if (index >= self.num_lines) return error.IndexOutOfRange;
            lv.mask.set(index);
        }
        return try gpio.uapi.setLineValues(self.handle, lv);
    }

    /// Sets the values of all the controlled lines
    pub fn setAllValues(self: Lines, vals: gpio.uapi.LineValueBitset) !void {
        if (self.closed) return error.LineClosed;
        var lv = gpio.uapi.LineValues{ .bits = vals };

        // Add all the indices to the bitset of values to set
        var i: u32 = 0;
        while (i < self.num_lines) : (i += 1) lv.mask.set(i);

        return try gpio.uapi.setLineValues(self.handle, lv);
    }

    /// Gets the values of all the controlled lines as a bitset
    pub fn getValues(self: Lines) !gpio.uapi.LineValueBitset {
        if (self.closed) return error.LineClosed;
        var vals = gpio.uapi.LineValueBitset{ .mask = 0 };

        // Add all the indices to the bitset of values to get
        var i: u32 = 0;
        while (i < self.num_lines) : (i += 1) vals.set(i);

        return try gpio.uapi.getLineValues(self.handle, vals);
    }

    /// Releases all the resources held by the requested `lines`.
    pub fn close(self: *Lines) void {
        if (self.closed) return;
        self.closed = true;
        std.os.close(self.handle);
    }
};

/// Represents a single line requested from a `chip`.
pub const Line = struct {
    /// The `Lines` value containing the line.
    lines: Lines,

    /// Sets the line as high (on).
    pub fn setHigh(self: Line) !void {
        try self.lines.setHigh(&.{0});
    }

    /// Sets the line as low (off).
    pub fn setLow(self: Line) !void {
        try self.lines.setLow(&.{0});
    }

    // Sets the value of the line.
    pub fn setValue(self: Line, value: bool) !void {
        var vals = gpio.uapi.LineValueBitset{ .mask = 0 };
        vals.setValue(0, value);
        try self.lines.setValues(&.{0}, vals);
    }

    /// Sets the configuration flags of the line.
    pub fn reconfigure(self: Line, flags: gpio.uapi.LineFlags) !void {
        try self.lines.reconfigure(&.{0}, flags);
    }

    /// Sets the debounce period of the line.
    pub fn setDebouncePeriod(self: Line, duration_us: u32) !void {
        try self.lines.setDebouncePeriod(&.{0}, duration_us);
    }

    /// Gets the current value of the line as a boolean.
    pub fn getValue(self: Line) !bool {
        const vals = try self.lines.getValues();
        return vals.isSet(0);
    }

    /// Releases all the resources held by the `line`.
    pub fn close(self: *Line) void {
        self.lines.close();
    }
};
