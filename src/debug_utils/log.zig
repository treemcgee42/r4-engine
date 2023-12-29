const std = @import("std");
const builtin = @import("builtin");
const dbg_compiled = builtin.mode == std.builtin.OptimizeMode.Debug;

pub const LogLevel = enum(u8) {
    err = 10,
    warn = 20,
    info = 30,
    debug = 40,
};

pub const BasicLogger = struct {
    // All logs with level above this will be dropped.
    level_cutoff: u8 = @intFromEnum(LogLevel.debug),

    pub fn debug_log(
        self: *const BasicLogger,
        comptime identifier: []const u8,
        comptime level: LogLevel,
        comptime format: []const u8,
        args: anytype,
    ) void {
        if (dbg_compiled) {
            self.log(identifier, level, format, args);
        }
    }

    pub fn production_log(
        self: *const BasicLogger,
        comptime identifier: []const u8,
        comptime level: LogLevel,
        comptime format: []const u8,
        args: anytype,
    ) void {
        self.log(identifier, level, format, args);
    }

    pub fn log(
        self: *const BasicLogger,
        comptime identifier: []const u8,
        comptime level: LogLevel,
        comptime format: []const u8,
        args: anytype,
    ) void {
        if (@intFromEnum(level) > self.level_cutoff) {
            return;
        }

        const prefix = "(" ++ identifier ++ ") ";

        std.debug.getStderrMutex().lock();
        defer std.debug.getStderrMutex().unlock();

        const stderr = std.io.getStdErr().writer();
        nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
    }
};

// `zig test ./test.zig -O ReleaseFast`
// `zig build test -Doptimize=ReleaseFast`
test {
    std.debug.print("\n", .{});

    const logger = BasicLogger{
        .level_cutoff = 100,
    };

    logger.debug_log("debug", .err, "err", .{});
    logger.debug_log("debug", .warn, "warn", .{});
    logger.debug_log("debug", .info, "debug", .{});
    logger.production_log("prod", .debug, "debug", .{});
}
