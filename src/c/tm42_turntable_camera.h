#ifndef TM42_CAMERA_H
#define TM42_CAMERA_H

#include <stddef.h>

typedef void* Tm42AllocatorFn( size_t bytes );

struct Tm42TurntableCamera;

struct Tm42CameraCreateInfo {
    float* look_at;
    float* look_from;
    /// In degrees.
    float vertical_fov;
    /// E.g. screen_width / screen_height.
    float aspect_ratio;
    float z_near;
    float z_far;
};

struct Tm42TurntableCamera* tm42_create_turntable_camera( struct Tm42CameraCreateInfo create_info );
float* tm42_turntable_camera_get_view_matrix( struct Tm42TurntableCamera* self );
float* tm42_turntable_camera_get_projection_matrix( struct Tm42TurntableCamera* self );

#endif // TM42_CAMERA_H

#ifdef TM42_CAMERA_IMPLEMENTATION

#include "tm42_math.h"
#include <stdbool.h>
#include <stdlib.h>

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
    struct Tm42Mat4 view_matrix;
};

struct Tm42Mat4 tm42_build_view_matrix_from_rotation_and_offset( float* rotation, float* offset ) {
    const struct Tm42Mat4 rotation_matrix = tm42_mat4_from_quaternion( rotation );

    const struct Tm42Vec3 negative_offset = { .x = -offset[0], .y = -offset[1], .z = -offset[2] };
    struct Tm42Mat4 negative_offset_matrix = tm42_mat4_create_identity();
    tm42_mat4_apply_translation( &negative_offset_matrix, &negative_offset );

    //    return tm42_mat4_mul_mat4( &negative_offset_matrix, &rotation_matrix );
    return tm42_mat4_mul_mat4( (float*)&rotation_matrix, (float*)&negative_offset_matrix );
}

struct Tm42ViewInfo tm42_create_viewinfo( float* look_at, float* look_from ) {
    // We seek a transformation into coordinates where look_from is the origin and look_at lies
    // in the forward direction. That is, applying this transformation to look_from should yield
    // (0,0,0), and applying this transformation to look_at should result in a point on the ray
    // (0,0,0)+(0,0,-1)t.
    //
    // It should also preserve the distance between look_at and look_from, in the sense that the
    // transformed look_at and look_from is the same as the distance between the original look_at
    // and look_from.

    // --- Rotation
    //
    // In terms of the rotation, it is characterized by rotating, from the perspective of the
    // look_from point, the look_at point so that it lies in the "forward" direction.  In the
    // right-handed coordinate system, the normalized forward vector is (0,0,-1). The vector
    // pointing to the look_at point, from the look_from point, is look_at-look_from. Thus we seek
    // the rotation from normalized(look_at-look_from) to (0,0,-1).

    const struct Tm42Vec3 normalized_forward = { .x = 0.f, .y = 0.f, .z = -1.f };

    struct Tm42Vec3 normalized_at_minus_from = tm42_vec3_sub( look_at, look_from );
    tm42_vec3_normalize( (float*)&normalized_at_minus_from );

    const struct Tm42Quaternion current_rotation = tm42_quaternion_rotation_between_vec3s(
        (float*)&normalized_at_minus_from, (float*)&normalized_forward );

    // --- Offset
    //
    // The offset should transform the look_from point to the origin. Thus it is -look_from.

    const struct Tm42Vec3 offset = { .x = -look_from[0], .y = -look_from[1], .z = -look_from[2] };

    // --- Construct transformation matrix
    //
    // First translate, then rotate.

    const struct Tm42Mat4 rotation_matrix = tm42_mat4_from_quaternion( (float*)&current_rotation );

    struct Tm42Mat4 offset_matrix = tm42_mat4_create_identity();
    tm42_mat4_apply_translation( (float*)&offset_matrix, (float*)&offset );

    struct Tm42Mat4 view_matrix = tm42_mat4_mul_mat4( rotation_matrix.a, offset_matrix.a );

    // ---

    struct Tm42ViewInfo to_return = {
        .z_offset = { .x = 0.f, .y = 0.f, .z = 0.f },
        .look_at = { .x = look_at[0], .y = look_at[1], .z = look_at[2] },
        .current_rotation = current_rotation,
        .rotation_modifier = tm42_quaternion_create_identity(),
        .should_reverse = false,
        .view_matrix = view_matrix,
    };
    return to_return;
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
    struct Tm42Mat4 proj_matrix;
};

struct Tm42ProjectionInfo tm42_create_projectioninfo( float vertical_fov, float aspect_ratio,
                                                      float z_near, float z_far ) {
    float fov_radians = vertical_fov * (float)( M_PI / 180.0 );
    struct Tm42Mat4 proj_matrix =
        tm42_mat4_create_projection( fov_radians, aspect_ratio, z_near, z_far );

    struct Tm42ProjectionInfo to_return = {
        .vertical_fov = vertical_fov,
        .aspect_ratio = aspect_ratio,
        .z_near = z_near,
        .z_far = z_far,
        .proj_matrix = proj_matrix,
    };
    return to_return;
}

struct Tm42TurntableCamera {
    struct Tm42ViewInfo view_info;
    struct Tm42ProjectionInfo proj_info;
    struct Tm42Mat4 view_proj_matrix;
};

struct Tm42TurntableCamera*
tm42_create_turntable_camera( struct Tm42CameraCreateInfo create_info ) {
    struct Tm42TurntableCamera* to_return = malloc( sizeof( struct Tm42TurntableCamera ) );
    if ( to_return == NULL ) {
        return NULL;
    }

    struct Tm42ViewInfo view_info =
        tm42_create_viewinfo( create_info.look_at, create_info.look_from );

    struct Tm42ProjectionInfo proj_info = tm42_create_projectioninfo(
        create_info.vertical_fov, create_info.aspect_ratio, create_info.z_near, create_info.z_far );

    struct Tm42Mat4 view_proj_matrix =
        tm42_mat4_mul_mat4( proj_info.proj_matrix.a, view_info.view_matrix.a );

    to_return->view_info = view_info;
    to_return->proj_info = proj_info;
    to_return->view_proj_matrix = view_proj_matrix;
    return to_return;
}

void tm42_destroy_turntable_camera( struct Tm42TurntableCamera* self ) { free( self ); }

float* tm42_turntable_camera_get_view_matrix( struct Tm42TurntableCamera* self ) {
    return self->view_info.view_matrix.a;
}

float* tm42_turntable_camera_get_projection_matrix( struct Tm42TurntableCamera* self ) {
    return self->proj_info.proj_matrix.a;
}

#endif // TM42_CAMERA_IMPLEMENTATION
