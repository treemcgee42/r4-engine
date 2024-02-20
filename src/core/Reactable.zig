const std = @import("std");
const dutil = @import("debug_utils");

pub const CallbackHandle = usize;

pub fn Reactable(comptime T: type) type {
    return struct {
        pub const Callback = struct {
            extra_data: ?*anyopaque,
            /// Sorted by priority, higher priorities are sorted first.
            callback_fn: *const fn (data: T, extra_data: ?*anyopaque) void,
            /// Lower number means lower priority.
            priority: u8 = 0,
            name: []const u8,
        };

        const Self = @This();

        name: []const u8,
        data: T,
        callbacks: std.ArrayList(Callback),

        pub fn init_with_data(
            allocator: std.mem.Allocator,
            data: T,
            name: []const u8,
        ) Reactable(T) {
            return .{
                .name = name,
                .data = data,
                .callbacks = std.ArrayList(Callback).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.callbacks.deinit();
        }

        pub fn add_callback(
            self: *Self,
            callback: Callback,
        ) !CallbackHandle {
            const priority = callback.priority;
            try self.callbacks.append(callback);

            const num_callbacks = self.callbacks.items.len;
            var handle = num_callbacks - 1;

            var i: usize = 0;
            while (i < num_callbacks - 1) : (i += 1) {
                const this_callback = self.callbacks.items[i];
                const this_priority = this_callback.priority;
                if (this_priority < priority) {
                    self.callbacks.items[num_callbacks - 1] = this_callback;
                    self.callbacks.items[i] = callback;
                    handle = i;
                    break;
                }
            }

            return handle;
        }

        pub fn remove_callback(self: *Self, handle: CallbackHandle) void {
            _ = self.callbacks.orderedRemove(handle);
        }

        pub fn set(self: *Self, data: T) void {
            dutil.log(
                "reactable",
                .info,
                "BEGIN calling callbacks for '{s}'",
                .{self.name},
            );

            self.data = data;

            var i: usize = 0;
            while (i < self.callbacks.items.len) : (i += 1) {
                const callback_ptr = &self.callbacks.items[i];
                dutil.log(
                    "reactable",
                    .info,
                    "'{s}' reactable calling '{s}'",
                    .{ self.name, callback_ptr.name },
                );
                callback_ptr.callback_fn(self.data, callback_ptr.extra_data);
            }

            dutil.log(
                "reactable",
                .info,
                "END calling callbacks for '{s}'",
                .{self.name},
            );
        }
    };
}

// --- Testing

const TestExtraData = struct {
    num_hits: usize,
    expected_data_value: i32,
};

fn test_callback(data: i32, extra_data: ?*anyopaque) void {
    const extra_data_typed_ptr: *TestExtraData = @ptrCast(@alignCast(extra_data));
    std.testing.expect(data == extra_data_typed_ptr.expected_data_value) catch unreachable;
    extra_data_typed_ptr.num_hits += 1;
}

test "Reactable" {
    var reactable = Reactable(i32).init_with_data(
        std.testing.allocator,
        0,
    );
    defer reactable.deinit();

    var extra_data = TestExtraData{
        .num_hits = 0,
        .expected_data_value = 0,
    };

    const handle_1 = try reactable.add_callback(.{
        .extra_data = @ptrCast(&extra_data),
        .callback_fn = test_callback,
    });
    const handle_2 = try reactable.add_callback(.{
        .extra_data = @ptrCast(&extra_data),
        .callback_fn = test_callback,
    });

    extra_data.expected_data_value = 1;
    reactable.set(1);
    try std.testing.expect(extra_data.num_hits == 2);

    try reactable.remove_callback(handle_1);
    extra_data.expected_data_value = 2;
    extra_data.num_hits = 0;
    reactable.set(2);
    try std.testing.expect(extra_data.num_hits == 1);

    const handle_3 = try reactable.add_callback(.{
        .extra_data = @ptrCast(&extra_data),
        .callback_fn = test_callback,
    });

    extra_data.expected_data_value = 3;
    extra_data.num_hits = 0;
    reactable.set(3);
    try std.testing.expect(extra_data.num_hits == 2);

    try reactable.remove_callback(handle_2);
    extra_data.expected_data_value = 4;
    extra_data.num_hits = 0;
    reactable.set(4);
    try std.testing.expect(extra_data.num_hits == 1);

    try reactable.remove_callback(handle_3);
    extra_data.expected_data_value = 5;
    extra_data.num_hits = 0;
    reactable.set(5);
    try std.testing.expect(extra_data.num_hits == 0);
}

// TODO: test for priorities
