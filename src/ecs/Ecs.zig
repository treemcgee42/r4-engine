const std = @import("std");
const entity_lib = @import("./entities.zig");
const Entity = entity_lib.Entity;
const EntityManager = entity_lib.EntityManager;
const component_lib = @import("./components.zig");
const ComponentManager = component_lib.ComponentManager;

pub const Ecs = struct {
    entity_manager: EntityManager,
    component_manager: ComponentManager,

    pub fn init(allocator: std.mem.Allocator) Ecs {
        const entity_manager = EntityManager.init();
        const component_manager = ComponentManager.init(allocator);

        return .{
            .entity_manager = entity_manager,
            .component_manager = component_manager,
        };
    }

    pub fn deinit(self: *Ecs) void {
        self.component_manager.deinit();
    }

    pub fn create_entity(self: *Ecs) Entity {
        return self.entity_manager.create();
    }

    // pub fn destroy_entity(self: *Ecs, entity: Entity) void {

    // }
};
