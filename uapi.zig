const std = @import("std");

/// The maximum size of name and label arrays
pub const MAX_NAME_SIZE = 32;

/// Information about a certain GPIO chip
pub const ChipInfo = extern struct {
    /// The Linux kernel name of this GPIO chip
    name: [MAX_NAME_SIZE]u8,
    /// A functional name for this GPIO chip, such as a product
    /// number, may be empty (i.e. `label[0] == '\0'`)
    label: [MAX_NAME_SIZE]u8,
    /// The number of GPIO lines on this chip
    lines: u32,
};

/// The maximum number of configuration attributes associated with a line request.
pub const MAX_LINE_NUM_ATTRS = 10;

/// Information about a certain GPIO line
pub const LineInfo = extern struct {
    /// The name of this GPIO line, such as the output pin of the line on
    /// the chip, a rail or a pin header name on a board, as specified by the
    /// GPIO chip, may be empty (i.e. `name[0] == '\0'`)
    name: [MAX_NAME_SIZE]u8,
    /// a functional name for the consumer of this GPIO line as set
    /// by whatever is using it, will be empty if there is no current user,
    /// but may also be empty if the consumer doesn't set this up
    consumer: [MAX_NAME_SIZE]u8,
    /// The local offset on this GPIO chip, fill this in when
    /// requesting the line information from the kernel
    offset: u32,
    /// The number of attributes in `attrs`
    num_attrs: u32,
    /// Configuration flags for this GPIO line
    flags: LineFlags,
    /// The configuration attributes associated with the line
    attrs: [MAX_LINE_NUM_ATTRS]LineAttribute,
    /// Reserved for future use
    _padding: [4]u32,

    /// Returns the line's name as a slice without any null characters
    pub fn nameSlice(self: *const LineInfo) []const u8 {
        return std.mem.sliceTo(&self.name, 0);
    }

    /// Returns the line's consumer as a slice without any null characters
    pub fn consumerSlice(self: *const LineInfo) []const u8 {
        return std.mem.sliceTo(&self.consumer, 0);
    }
};

/// LineAttribute ID values
pub const LineAttributeId = enum(u32) {
    /// Indicates that the line attribute contains flags
    Flags = 1,
    /// Indicates that the line attribute contains output values
    OutputValues = 2,
    /// Indicates that the line attribute contains a debounce period
    Debounce = 3,
};

/// A configurable attribute of a line
pub const LineAttribute = extern struct {
    id: LineAttributeId,
    _padding: u32 = 0,
    data: extern union {
        flags: LineFlags,
        values: u64,
        debounce_period_us: u32,
    },
};

/// A configuration attribute
pub const LineConfigAttribute = extern struct {
    attr: LineAttribute,
    mask: LineValueBitset = .{ .mask = 0 },
};

/// Maximum number of requested lines
pub const MAX_LINES = 64;

/// Information about a request for GPIO lines
pub const LineRequest = extern struct {
    offsets: [MAX_LINES]u32,
    consumer: [MAX_NAME_SIZE]u8,
    config: LineConfig,
    num_lines: u32,
    event_buffer_size: u32,
    _padding: [5]u32 = [5]u32{ 0, 0, 0, 0, 0 },
    fd: i32,
};

/// Configuration flags for GPIO lines
pub const LineFlags = packed struct {
    /// Line is not available for request
    used: bool = false,
    /// Line active state is physical low
    active_low: bool = false,
    /// Line is an input
    input: bool = false,
    /// Line is an output
    output: bool = false,
    /// Line detects rising (inactive to active) edges
    edge_rising: bool = false,
    /// Line detects falling (active to inactive) edges
    edge_falling: bool = false,
    /// Line is an open drain output
    open_drain: bool = false,
    /// Line is an open source output
    open_source: bool = false,
    /// Line has pull-up bias enabled
    bias_pull_up: bool = false,
    /// Line has pull-down bias enabled
    bias_pull_down: bool = false,
    /// Line has bias disabled
    bias_disabled: bool = false,
    /// Line events contain REALTIME timestamps
    event_clock_real_time: bool = false,
    /// Line events contain timestamps from hardware timestamp engine
    event_clock_hte: bool = false,
    /// Reserved for future use
    _padding: u51 = 0,
};

/// Configuration for GPIO lines
pub const LineConfig = extern struct {
    /// Configuration flags for the GPIO lines. This is the default for
    /// all requested lines but may be overridden for particular lines
    /// using `attrs`.
    flags: LineFlags,
    /// The number of attributes in `attrs`
    num_attrs: u32,
    /// Reserved for future use and must be zero-filled
    _padding: [5]u32 = [5]u32{ 0, 0, 0, 0, 0 },
    /// The configuration attributes associated with the requested lines
    attrs: [MAX_LINE_NUM_ATTRS]LineConfigAttribute,
};

/// A bitset representing GPIO line values
pub const LineValueBitset = std.bit_set.IntegerBitSet(MAX_LINES);

/// Values of GPIO lines
pub const LineValues = extern struct {
    /// A bitmap containing the value of the lines, set to 1 for active
    /// and 0 for inactive.
    bits: LineValueBitset = .{ .mask = 0 },

    /// A bitmap identifying the lines to get or set, with each bit
    /// number corresponding to the index in LineRequest.offsets
    mask: LineValueBitset = .{ .mask = 0 },
};

/// `LineInfoChanged.type` values
pub const ChangeType = enum(u32) {
    /// Line has been requested
    Requested = 1,
    /// Line has been released
    Released = 2,
    /// Line has been reconfigured
    Config = 3,
};

/// Information about a change in status of a GPIO line
pub const LineInfoChanged = extern struct {
    /// Updated line information
    info: LineInfo,
    /// Estimate of the time when the status change occurred, in nanoseconds
    timestamp_ns: u64,
    /// The type of change
    type: ChangeType,
    /// Reserved for future use
    _padding: [5]u32 = [5]u32{ 0, 0, 0, 0, 0 },
};

/// Returns an error based on the given return code
fn handleErrno(ret: usize) !void {
    if (ret == 0) return;
    return switch (std.os.errno(ret)) {
        .BUSY => error.DeviceIsBusy,
        .INVAL => error.InvalidArgument,
        .BADF => error.BadFileDescriptor,
        .NOTTY => error.InappropriateIOCTLForDevice,
        .IO => error.IOError,
        .FAULT => unreachable,
        else => |err| return std.os.unexpectedErrno(err),
    };
}

/// Executes `GPIO_GET_CHIPINFO_IOCTL` on the given fd and returns the resulting
/// `ChipInfo` value
pub fn getChipInfo(fd: std.os.fd_t) !ChipInfo {
    const req = std.os.linux.IOCTL.IOR(0xB4, 0x01, ChipInfo);
    var info = std.mem.zeroes(ChipInfo);
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(&info)));
    return info;
}

/// Executes `GPIO_V2_GET_LINEINFO_IOCTL` on the given fd and returns the resulting
/// `LineInfo` value
pub fn getLineInfo(fd: std.os.fd_t, offset: u32) !LineInfo {
    const req = std.os.linux.IOCTL.IOWR(0xB4, 0x05, LineInfo);
    var info = std.mem.zeroes(LineInfo);
    info.offset = offset;
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(&info)));
    return info;
}

/// Executes `GPIO_V2_GET_LINEINFO_WATCH_IOCTL` on the given fd and returns the resulting
/// `LineInfo` value
pub fn watchLineInfo(fd: std.os.fd_t, offset: u32) !LineInfo {
    const req = std.os.linux.IOCTL.IOWR(0xB4, 0x06, LineInfo);
    var info = std.mem.zeroes(LineInfo);
    info.offset = offset;
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(&info)));
    return info;
}

/// Executes `GPIO_GET_LINEINFO_UNWATCH_IOCTL` on the given fd
pub fn unwatchLineInfo(fd: std.os.fd_t, offset: u32) !void {
    const req = std.os.linux.IOCTL.IOWR(0xB4, 0x0C, u32);
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(&offset)));
}

/// Executes `GPIO_V2_GET_LINE_IOCTL` on the given fd and returns the resulting
/// line descriptor
pub fn getLine(fd: std.os.fd_t, lr: LineRequest) !std.os.fd_t {
    const lrp = &lr;
    const req = std.os.linux.IOCTL.IOWR(0xB4, 0x07, LineRequest);
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(lrp)));
    return lrp.fd;
}

/// Executes `GPIO_V2_LINE_GET_VALUES_IOCTL` on the given fd and returns the resulting
/// `LineValues` value
pub fn getLineValues(fd: std.os.fd_t) !LineValues {
    const req = std.os.linux.IOCTL.IOWR(0xB4, 0x0E, LineValues);
    var values = std.mem.zeroes(LineValues);
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(&values)));
    return values;
}

/// Executes `GPIO_V2_LINE_SET_VALUES_IOCTL` on the given fd
pub fn setLineValues(fd: std.os.fd_t, lv: LineValues) !void {
    const req = std.os.linux.IOCTL.IOWR(0xB4, 0x0F, LineValues);
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(&lv)));
}

/// Executes `GPIO_V2_LINE_SET_CONFIG_IOCTL` on the given fd
pub fn setLineConfig(fd: std.os.fd_t, lc: LineConfig) !void {
    const req = std.os.linux.IOCTL.IOWR(0xB4, 0x0D, LineConfig);
    try handleErrno(std.os.linux.ioctl(fd, req, @intFromPtr(&lc)));
}
