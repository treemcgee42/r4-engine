const std = @import("std");

pub const Entity = packed struct {
    id: u32,
};

pub const EntityManager = struct {
    next_id: u32 = 0,

    pub fn init() EntityManager {
        return .{};
    }

    pub fn create(self: *EntityManager) Entity {
        const entity = Entity{ .id = self.next_id };
        self.next_id += 1;
        return entity;
    }
};
