const std = @import("std");

pub fn Reactable(comptime T: type) type {
    return struct {
        pub const Callback = struct {
            extra_data: ?*anyopaque,
            callback_fn: *const fn (data: T, extra_data: ?*anyopaque) void,
            skip: bool = false,
        };

        pub const CallbackHandle = usize;

        const Self = @This();

        data: T,
        callbacks: std.ArrayList(Callback),
        empty_callbacks_indices: std.ArrayList(usize),

        pub fn init_with_data(allocator: std.mem.Allocator, data: T) Reactable(T) {
            return .{
                .data = data,
                .callbacks = std.ArrayList(Callback).init(allocator),
                .empty_callbacks_indices = std.ArrayList(usize).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.callbacks.deinit();
            self.empty_callbacks_indices.deinit();
        }

        pub fn add_callback(
            self: *Self,
            callback: Callback,
        ) !CallbackHandle {
            if (self.empty_callbacks_indices.items.len > 0) {
                const handle = self.empty_callbacks_indices.pop();
                self.callbacks.items[handle] = callback;
                return handle;
            }

            try self.callbacks.append(callback);
            return self.callbacks.items.len - 1;
        }

        pub fn remove_callback(self: *Self, handle: CallbackHandle) !void {
            try self.empty_callbacks_indices.append(handle);
            self.callbacks.items[handle].skip = true;
        }

        pub fn set(self: *Self, data: T) void {
            self.data = data;

            var i: usize = 0;
            while (i < self.callbacks.items.len) : (i += 1) {
                if (self.callbacks.items[i].skip) {
                    continue;
                }

                const callback_ptr = &self.callbacks.items[i];
                callback_ptr.callback_fn(self.data, callback_ptr.extra_data);
            }
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
    var reactable = Reactable(i32).init_with_data(std.testing.allocator, 0);
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
