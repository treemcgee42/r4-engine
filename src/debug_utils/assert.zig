const BasicLogger = @import("log.zig").BasicLogger;

pub const AssertConfig = struct {
    debug_action_on_failure: enum {
        panic,
        log,
    },
    production_action_on_failure: enum {
        panic,
        log,
    },
    logger: ?*BasicLogger,

    const Self = @This();

    pub fn comptime_assert(comptime cond: bool) void {
        if (!cond) {
            @compileError("comptime assert failed");
        }
    }

    pub fn debug_assert(self: *const Self, cond: bool) void {
        if (!cond) {
            switch (self.debug_action_on_failure) {
                .panic => {
                    @panic("debug assert failed");
                },
                .log => {
                    self.logger.?.log("assertion", .err, "debug assert failed", .{});
                },
            }
        }
    }

    pub fn production_assert(self: *const Self, cond: bool) void {
        if (!cond) {
            switch (self.production_action_on_failure) {
                .panic => {
                    @panic("production assert failed");
                },
                .log => {
                    self.logger.?.log("assertion", .err, "production assert failed", .{});
                },
            }
        }
    }
};
