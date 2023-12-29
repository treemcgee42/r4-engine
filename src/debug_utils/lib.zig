pub const r4_log = @import("./log.zig");
pub const r4_assert = @import("./assert.zig");

var basic_logger = r4_log.BasicLogger{
    .level_cutoff = 100,
};

var assert_config = r4_assert.AssertConfig{
    .debug_action_on_failure = .log,
    .production_action_on_failure = .panic,
    .logger = &basic_logger,
};

pub fn log(
    comptime identifier: []const u8,
    comptime level: r4_log.LogLevel,
    comptime format: []const u8,
    args: anytype,
) void {
    basic_logger.log(identifier, level, format, args);
}

pub fn comptime_assert(comptime cond: bool) void {
    r4_assert.AssertConfig.comptime_assert(cond);
}

pub fn debug_assert(cond: bool) void {
    assert_config.debug_assert(cond);
}

pub fn production_assert(cond: bool) void {
    assert_config.production_assert(cond);
}
