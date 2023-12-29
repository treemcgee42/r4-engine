const std = @import("std");
const dutil = @import("debug_utils");
const entity_lib = @import("./entities.zig");
pub const Entity = entity_lib.Entity;
const EntityManager = entity_lib.EntityManager;
const component_lib = @import("./components.zig");
const ComponentManager = component_lib.ComponentManager;

pub const EcsError = error{
    adding_unregistered_component,
    removing_unregistered_component,
    component_not_assigned_to_entity,
} || std.mem.Allocator.Error;

pub const Ecs = struct {
    entity_manager: EntityManager,
    component_manager: ComponentManager,

    pub fn init(allocator: std.mem.Allocator) Ecs {
        const entity_manager = EntityManager.init();
        const component_manager = ComponentManager.init(allocator);

        dutil.log("ecs", .info, "initialized ecs", .{});

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

    /// Registering a component allows one to assign an instance of the component to an entity.
    pub fn register_component(
        self: *Ecs,
        comptime component_ty: type,
    ) !void {
        return self.component_manager.register_component(component_ty);
    }

    /// Adds a component to an entity. The component must be registered.
    ///
    /// Returns:
    /// - `void` on success
    /// - `.adding_unregistered_component` if the component is not registered
    pub fn add_component_for_entity(
        self: *Ecs,
        entity: Entity,
        component: anytype,
    ) EcsError!void {
        return self.component_manager.add_component_for_entity(entity, component);
    }

    /// Removes a component from an entity. The component must be registered
    /// and have an instance assigned to the entity.
    pub fn remove_component_for_entity(
        self: *Ecs,
        entity: Entity,
        comptime component_ty: type,
    ) !void {
        return self.component_manager.remove_component_for_entity(entity, component_ty);
    }

    pub fn get_component_for_entity(
        self: *Ecs,
        entity: Entity,
        comptime component_ty: type,
    ) ?*component_ty {
        return self.component_manager.get_component_for_entity(entity, component_ty);
    }
};
