#ifndef TM42_CAMERA_H
#define TM42_CAMERA_H

#include <stddef.h>

typedef void* Tm42AllocatorFn( size_t bytes );

struct Tm42TurntableCamera;

struct Tm42CameraCreateInfo {
    float* look_at;
    float* look_from;
    /// E.g. screen_width / screen_height.
    float aspect_ratio;
};

struct Tm42TurntableCamera* tm42_create_turntable_camera( struct Tm42CameraCreateInfo create_info,
                                                          Tm42AllocatorFn allocator );

#endif // TM42_CAMERA_H

#ifdef TM42_CAMERA_IMPLEMENTATION

#include "tm42_math.h"

// ---

struct Tm42ViewInfo {
    /// How far the camera is from the `look_at` point, without accounting for rotation.
    struct Tm42Vec3 z_offset;
    /// The point the camera is pointing at (the center point).
    struct Tm42Point3 look_at;
    /// Represents the rotation needed to get to the last set camera rotation.  A camera rotation is
    /// set, for example, after releasing the keybind that allowed for a turntable rotation.
    struct Tm42Quaternion current_rotation;
    /// The total rotation for the camera is current_rotation * rotation_modifier.
    struct Tm42Quaternion rotation_modifier;
    /// Whether the horizontal mouse input should be reversed in the turntable camera. This makes it
    /// so that the expected controls aren't reversed when viewing the scene upside down.
    bool should_reverse;
    /// Transformation for world -> camera space.
    struct Tm42Matrix4 view_matrix;
};

struct Tm42ViewInfo tm42_create_viewinfo( float* look_at, float* look_from ) {
    float distance_at_from = tm42_point3_distance( look_at, look_from );
    struct Tm42Vec3 z_offset = {
        .x = look_at[0],
        .y = look_at[1],
        .z = look_at[2] - distance_at_from,
    };

    struct Tm42Point3 look_at_copy = { .x = look_at[0], .y = look_at[1], .z = look_at[2] };

    struct Tm42Vec3 normalized_z_offset = z_offset;
    tm42_vec3_normalize( &normalizex_z_offset );
    struct Tm42Vec3 normalized_look_from = {
        .x = look_from[0],
        .y = look_from[1],
        .z = look_from[2],
    };
    tm42_vec3_normalize( &normalized_look_from );
    struct Tm42Quaternion current_rotation =
        tm42_quaternion_rotation_between_vec3s( &z_offset, look_from );

    struct Tm42Mat4 view_matrix; // TODO

    struct Tm42ViewInfo to_return = {
        .z_offset = z_offset,
        .look_at = look_at_copy,
        .current_rotation = current_rotation,
        .rotation_modifier = tm42_quaternion_create_identity(),
        .should_reverse = false,
        .view_matrix = view_matrix,
    };
    return to_return;
}

struct Tm42Mat4 tm42_build_view_matrix_from_rotation_and_offset( float* rotation, float* offset ) {
    const struct Tm42Mat4 rotation_matrix = tm42_mat4_from_quaternion( rotation );

    const struct Tm42Vec3 negative_offset = { .x = -offset[0], .y = -offset[1], .z = -offset[2] };
    struct Tm42Mat4 negative_offset_matrix = tm42_mat4_create_identity();
    tm42_mat4_apply_translation( &negative_offset_matrix, &negative_offset );

    return tm42_mat4_mul_mat4( &negative_offset_matrix, &rotation_matrix );
}

struct Tm42ProjectionInfo {
    /// in degrees
    float vertical_fov;
    float aspect_ratio;
    /// Distance to near clipping plane.
    float z_near;
    /// Distance to far clipping plane. A negative value is interpreted as an infinitely-far-away
    /// clipping plane.
    float z_far;
    struct Tm42Matrix4 proj_matrix;
};

struct Tm42TurntableCamera {
    struct Tm42ViewInfo view_info;
    struct Tm42ProjectionInfo proj_info;
    struct Tm42Matrix4 view_proj_matrix;
};

struct Tm42TurntableCamera* tm42_create_turntable_camera( struct Tm42CameraCreateInfo create_info,
                                                          Tm42AllocatorFn alloc_fn ) {
    struct Tm42TurntableCamera* to_return = alloc_fn( sizeof( struct Tm42TurntableCamera ) );
    if ( to_return == NULL ) {
        return NULL;
    }

    // init view info.
}

#endif // TM42_CAMERA_IMPLEMENTATION
