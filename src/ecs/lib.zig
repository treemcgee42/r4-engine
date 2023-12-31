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
    ///
    /// WARNING: simple type aliases are not considered distinct types! For example, trying
    /// to register components for the types
    /// ```
    /// const component_1 = f32;
    /// const componnent_2 = f32;
    /// ```
    /// will not work as expected, since `component_1` and `component_2` are the same type.
    /// There is some discussion on allowing this to define distinct types, see
    /// [this](https://github.com/ziglang/zig/issues/1595).
    /// In the meantime, a workaround is to use a struct type instead of a simple type alias:
    /// ```
    /// const component_1 = struct {
    ///   value: f32,
    /// };
    /// const component_2 = struct {
    ///   value: f32,
    /// };
    /// ```
    pub fn register_component(
        self: *Ecs,
        comptime component_ty: type,
    ) !void {
        return self.component_manager.register_component(component_ty);
    }

    /// Adds a component to an entity. The component must be registered. If the
    /// entity already has a component of the same type, it will be overwritten.
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

    /// Returns `null` if the component is not assigned to the entity.
    pub fn get_component_for_entity(
        self: *Ecs,
        entity: Entity,
        comptime component_ty: type,
    ) ?*component_ty {
        return self.component_manager.get_component_for_entity(entity, component_ty);
    }
};
