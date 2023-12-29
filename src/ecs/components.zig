const std = @import("std");
const dutil = @import("debug_utils");
const Entity = @import("./entities.zig").Entity;
const EcsError = @import("./lib.zig").EcsError;

fn ComponentArray(comptime ty: type) type {
    return struct {
        components: std.ArrayList(ty),
        entity_to_idx_map: std.AutoHashMap(Entity, usize),
        idx_to_entity_map: std.AutoHashMap(usize, Entity),

        const Self = @This();

        fn init(allocator: std.mem.Allocator) Self {
            return .{
                .components = std.ArrayList(ty).init(allocator),
                .entity_to_idx_map = std.AutoHashMap(Entity, usize).init(allocator),
                .idx_to_entity_map = std.AutoHashMap(usize, Entity).init(allocator),
            };
        }

        fn deinit(self: *Self) void {
            self.components.deinit();
            self.entity_to_idx_map.deinit();
            self.idx_to_entity_map.deinit();
        }

        fn add_component_for_entity(
            self: *Self,
            entity: Entity,
            component: ty,
        ) !void {
            const component_idx = self.entity_to_idx_map.get(entity);
            if (component_idx != null) {
                dutil.log(
                    "ecs",
                    .warn,
                    "Component already exists for entity {d}, overriding",
                    .{entity.id},
                );
                self.components.items[component_idx.?] = component;
                return;
            }

            try self.components.append(component);
            try self.entity_to_idx_map.put(entity, self.components.items.len - 1);
            try self.idx_to_entity_map.put(self.components.items.len - 1, entity);
        }

        fn remove_component_for_entity(
            self: *Self,
            entity: Entity,
        ) EcsError!void {
            // Removes the item, move the last item in the array to the
            // position of the removed item, update the entity-index map
            // accordingly.

            std.debug.assert(self.entity_to_idx_map.contains(entity));
            const idx = self.entity_to_idx_map.get(entity) orelse {
                dutil.log(
                    "ecs",
                    .err,
                    "A component index was not assigned to the entity {d}",
                    .{entity.id},
                );
                return;
            };
            _ = self.entity_to_idx_map.remove(entity);
            std.debug.assert(self.idx_to_entity_map.contains(idx));
            _ = self.idx_to_entity_map.remove(idx);

            if (idx == self.components.items.len - 1) {
                _ = self.components.pop();
            } else {
                const idx_of_component_to_move = self.components.items.len - 1;
                self.components.items[idx] = self.components.items[idx_of_component_to_move];
                self.components.items.len -= 1;

                const moved_components_entity = self.idx_to_entity_map.get(
                    idx_of_component_to_move,
                );
                std.debug.assert(moved_components_entity != null);
                try self.entity_to_idx_map.put(moved_components_entity.?, idx);
                try self.idx_to_entity_map.put(idx, moved_components_entity.?);
            }
        }

        fn get_component_for_entity(
            self: *Self,
            entity: Entity,
        ) ?*ty {
            const idx = self.entity_to_idx_map.get(entity) orelse return null;
            return &self.components.items[idx];
        }
    };
}

const TypeErasedComponentArray = struct {
    component_array_ptr: *anyopaque,
    deinit_fn: *const fn (*TypeErasedComponentArray, allocator: std.mem.Allocator) void,

    fn init(allocator: std.mem.Allocator, comptime component_ty: type) !TypeErasedComponentArray {
        const component_array_ptr = try allocator.create(ComponentArray(component_ty));
        component_array_ptr.* = ComponentArray(component_ty).init(allocator);

        return .{
            .component_array_ptr = component_array_ptr,
            .deinit_fn = (struct {
                fn deinit(self: *TypeErasedComponentArray, allocator_: std.mem.Allocator) void {
                    const ptr: *ComponentArray(component_ty) = @ptrCast(@alignCast(
                        self.component_array_ptr,
                    ));
                    ptr.deinit();
                    allocator_.destroy(ptr);
                }
            }).deinit,
        };
    }

    fn cast(
        self: *TypeErasedComponentArray,
        comptime component_ty: type,
    ) *ComponentArray(component_ty) {
        return @ptrCast(@alignCast(self.component_array_ptr));
    }
};

// const EntityWithComponentsIterator = struct {
//     component_manager: *ComponentManager,
//     components: []const type,
//     entity_iterator: @TypeOf(comptime std.hash_map.AutoHashMap(Entity, u32).KeyIterator),

//     const Self = @This();

//     fn init(
//         component_manager: *const ComponentManager,
//         comptime components: []const type,
//     ) EntityWithComponentsIterator {
//         std.debug.assert(components.len > 0);

//         const first_component_entity_hash_map = component_manager
//             .component_arrays.get(@typeName(components[0])).?
//             .cast(components[0])
//             .entity_to_idx_map;
//         const first_compononent_iterator = first_component_entity_hash_map.keyIterator();

//         return .{
//             .component_manager = component_manager,
//             .components = components,
//             .entity_iterator = first_compononent_iterator,
//         };
//     }

//     fn next(self: *Self) ?Entity {
//         while (true) {
//             const next_entity = self.entity_iterator.next();
//             if (next_entity == null or self.components.len == 1) {
//                 return next_entity;
//             }

//             // Check if the entity has all the components.

//             const it = next_entity.?;
//             var i: usize = 1;
//             var has_all_components = true;
//             while (i < self.components.len) : (i += 1) {
//                 if (!self.component_manager
//                     .component_arrays
//                     .get(@typeName(self.components[i])).?
//                     .cast(self.components[i])
//                     .entity_to_idx_map
//                     .contains(it))
//                 {
//                     has_all_components = false;
//                     break;
//                 }
//             }

//             if (has_all_components) {
//                 return it;
//             }
//         }
//     }
// };

pub const ComponentManager = struct {
    allocator: std.mem.Allocator,
    component_arrays: std.StringHashMap(TypeErasedComponentArray),

    pub fn init(allocator: std.mem.Allocator) ComponentManager {
        return .{
            .allocator = allocator,
            .component_arrays = std.StringHashMap(TypeErasedComponentArray).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentManager) void {
        var it = self.component_arrays.iterator();
        while (it.next()) |kv| {
            const array_ptr = kv.value_ptr;
            @call(.auto, array_ptr.deinit_fn, .{ array_ptr, self.allocator });
        }
        self.component_arrays.deinit();
    }

    pub fn register_component(
        self: *ComponentManager,
        comptime component_ty: type,
    ) !void {
        dutil.log("ecs", .debug, "in {s}", .{@src().fn_name});
        const component_array = try TypeErasedComponentArray.init(self.allocator, component_ty);
        dutil.log(
            "ecs",
            .debug,
            "{s} - created component array for type {s}",
            .{ @src().fn_name, @typeName(component_ty) },
        );
        try self.component_arrays.put(@typeName(component_ty), component_array);
    }

    fn get_component_array(
        self: *ComponentManager,
        comptime component_ty: type,
    ) ?*ComponentArray(component_ty) {
        var type_erased_array = self.component_arrays.get(@typeName(component_ty)) orelse return null;
        return type_erased_array.cast(component_ty);
    }

    pub fn add_component_for_entity(
        self: *ComponentManager,
        entity: Entity,
        component: anytype,
    ) EcsError!void {
        var component_array = self.get_component_array(@TypeOf(component)) orelse {
            return EcsError.adding_unregistered_component;
        };
        try component_array.add_component_for_entity(entity, component);
    }

    pub fn remove_component_for_entity(
        self: *ComponentManager,
        entity: Entity,
        comptime component_ty: type,
    ) !void {
        var component_array = self.get_component_array(component_ty) orelse {
            return .removing_unregistered_component;
        };
        try component_array.remove_component_for_entity(entity);
    }

    pub fn get_component_for_entity(
        self: *ComponentManager,
        entity: Entity,
        comptime component_ty: type,
    ) ?*component_ty {
        var component_array = self.get_component_array(component_ty) orelse return null;
        return component_array.get_component_for_entity(entity);
    }

    // fn entities_with_components_iterator(
    //     self: *const ComponentManager,
    //     comptime components: []const type,
    // ) EntityWithComponentsIterator {
    //     return EntityWithComponentsIterator.init(self, components);
    // }
};

// ---

test {
    const allocator = std.testing.allocator;

    var cm = ComponentManager.init(allocator);
    defer cm.deinit();

    const Health = struct {
        hp: u32,
    };

    const Position = struct {
        x: f32,
        y: f32,
    };

    try cm.register_component(Health);

    const entity1 = Entity{ .id = 1 };
    const entity1_health = Health{ .hp = 100 };
    const entity1_position = Position{ .x = 10, .y = 20 };
    const entity2 = Entity{ .id = 2 };
    const entity2_health = Health{ .hp = 200 };
    const entity3 = Entity{ .id = 3 };
    const entity3_health = Health{ .hp = 300 };

    try cm.add_component_for_entity(entity1, entity1_health);
    try cm.add_component_for_entity(entity2, entity2_health);

    // Check that the components were added correctly.
    {
        const health1 = cm.get_component_for_entity(entity1, Health);
        const health2 = cm.get_component_for_entity(entity2, Health);
        try std.testing.expect(health1.?.hp == 100);
        try std.testing.expect(health2.?.hp == 200);
    }

    // Try removing a component and accessing the remaining one.
    try cm.remove_component_for_entity(entity1, Health);
    {
        const health2 = cm.get_component_for_entity(entity2, Health);
        try std.testing.expect(health2.?.hp == 200);
    }

    // Add another entity and access its component.
    try cm.add_component_for_entity(entity3, entity3_health);
    {
        const health3 = cm.get_component_for_entity(entity3, Health);
        try std.testing.expect(health3.?.hp == 300);
    }

    // Add a position component for the first entity.
    try cm.register_component(Position);
    try cm.add_component_for_entity(entity1, entity1_position);
    {
        const position1 = cm.get_component_for_entity(entity1, Position);
        try std.testing.expect(position1.?.x == 10);
        try std.testing.expect(position1.?.y == 20);
    }
}

// test {
//     const allocator = std.testing.allocator;

//     var cm = ComponentManager.init(allocator);
//     defer cm.deinit();

//     const Component1 = struct {
//         hp: u32,
//     };

//     const Component2 = struct {
//         x: f32,
//         y: f32,
//     };

//     const Component3 = struct {
//         x: f32,
//         y: f32,
//         z: f32,
//     };

//     try cm.register_component(Component1);
//     try cm.register_component(Component2);
//     try cm.register_component(Component3);

//     const entity1 = Entity{ .id = 1 };
//     const entity2 = Entity{ .id = 2 };
//     const entity3 = Entity{ .id = 3 };
//     const entity4 = Entity{ .id = 4 };
//     _ = entity4;
//     const entity5 = Entity{ .id = 5 };
//     _ = entity5;

//     // We will give:
//     // - entity1: Component1
//     // - entity2: Component1, Component2
//     // - entity3: Component1, Component2, Component3

//     try cm.add_component_for_entity(entity1, Component1{ .hp = 100 });

//     try cm.add_component_for_entity(entity2, Component1{ .hp = 200 });
//     try cm.add_component_for_entity(entity2, Component2{ .x = 10, .y = 20 });

//     try cm.add_component_for_entity(entity3, Component1{ .hp = 300 });
//     try cm.add_component_for_entity(entity3, Component2{ .x = 30, .y = 40 });
//     try cm.add_component_for_entity(entity3, Component3{ .x = 50, .y = 60, .z = 70 });

//     // So:
//     // - Iterating over entities with component 1 should yield entity1, entity2, entity3.
//     // - Iterating over entities with components 1 and 2 should yield entity2, entity3.
//     // - Iterating over entities with components 1, 2, and 3 should yield entity3.

//     {
//         const components = comptime [_]type{Component1};
//         var it = cm.entities_with_components_iterator(&components);

//         var found_entities = std.AutoHashMap(Entity, void).init(allocator);
//         defer found_entities.deinit();

//         while (it.next()) |entity| {
//             try found_entities.put(entity, {});
//         }

//         try std.testing.expect(found_entities.count() == 3);
//         try std.testing.expect(found_entities.contains(entity1));
//         try std.testing.expect(found_entities.contains(entity2));
//         try std.testing.expect(found_entities.contains(entity3));
//     }
// }
