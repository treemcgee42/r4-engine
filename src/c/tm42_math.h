#ifndef TM42_MATH_H
#define TM42_MATH_H

#ifdef TM42_MATH_DEBUG_PRINT
#include <stdio.h>
#endif

struct Tm42Point3 {
    float x;
    float y;
    float z;
};

struct Tm42Vec3 {
    float x;
    float y;
    float z;
};

struct Tm42Vec4 {
    float x;
    float y;
    float z;
    float w;
};

struct Tm42Quaternion {
    // Represents s + xi + yj + zk

    float s;
    float x;
    float y;
    float z;
};

struct Tm42Mat4 {
    union {
        float m[4][4];
        float a[16];
    };
};

float tm42_deg_to_rad( float degrees );

float tm42_point3_distance( const float* p1, const float* p2 );

struct Tm42Vec3 tm42_vec3_add( const float* v1, const float* v2 );
struct Tm42Vec3 tm42_vec3_sub( const float* v1, const float* v2 );
float tm42_vec3_dot( const float* v1, const float* v2 );
struct Tm42Vec3 tm42_vec3_cross( const float* v1, const float* v2 );
void tm42_vec3_normalize( float* v );
#ifdef TM42_MATH_DEBUG_PRINT
void tm42_vec3_fprint( FILE* f, const float* v );
#endif

/// Divides the vector by the last coordinate.
void tm42_vec4_homogeneize( float* v );

struct Tm42Quaternion tm42_quaternion_create_identity();
void tm42_quaternion_normalize( float* q );
struct Tm42Vec3 tm42_quaternion_rotate_vec3( const float* q, const float* v );
/// Returns the (normalized) quaternion representing the rotation to go from `src` to `dst`. Both
/// `src` and `dst` vectors MUST be normalized.
struct Tm42Quaternion tm42_quaternion_rotation_between_vec3s( const float* src, const float* dst );
#ifdef TM42_MATH_DEBUG_PRINT
void tm42_quaternion_fprint( FILE* f, const float* q );
#endif

struct Tm42Mat4 tm42_mat4_create_identity();
struct Tm42Mat4 tm42_mat4_mul_mat4( const float* m1, const float* m2 );
struct Tm42Mat4 tm42_mat4_from_quaternion( const float* q );
void tm42_mat4_apply_translation( float* m, const float* v );
/// Assumes right handed coordinate system, depth mapping [0,1].
///
/// Parameters:
/// - vertical_fov: vertical field of view in radians
/// - aspect_ratio: aspect ratio, e.g. screen_width / screen_height
/// - z_near: near clipping plane
/// - z_far: far clipping plane, where a negative value indicates an infinitely far away plane
struct Tm42Mat4 tm42_mat4_create_projection( float vertical_fov, float aspect_ratio, float z_near,
                                             float z_far );
/// Regarding the matrix as a transformation, applies it to a Vec3.
struct Tm42Vec3 tm42_mat4_transform_vec3( const float* m, const float* v );
#ifdef TM42_MATH_DEBUG_PRINT
void tm42_mat4_fprint( FILE* f, const float* m );
#endif

#endif // TM42_MATH_H

#ifdef TM42_MATH_IMPLEMENTATION

#include <math.h>

float tm42_deg_to_rad( float degrees ) { return ( degrees * M_PI / 180.f ); }

// [[ Point3 ]]

float tm42_point3_distance( const float* p1, const float* p2 ) {
    const float dx = p2[0] - p1[0];
    const float dy = p2[1] - p1[1];
    const float dz = p2[2] - p1[2];

    return sqrt( dx * dx + dy * dy + dz * dz );
}

// [[ Vec3 ]]

struct Tm42Vec3 tm42_vec3_add( const float* v1, const float* v2 ) {
    struct Tm42Vec3 to_return = {
        .x = v1[0] + v2[0],
        .y = v1[1] + v2[1],
        .z = v1[2] + v2[2],
    };
    return to_return;
}

struct Tm42Vec3 tm42_vec3_sub( const float* v1, const float* v2 ) {
    struct Tm42Vec3 to_return = {
        .x = v1[0] - v2[0],
        .y = v1[1] - v2[1],
        .z = v1[2] - v2[2],
    };
    return to_return;
}

float tm42_vec3_dot( const float* v1, const float* v2 ) {
    float to_return = v1[0] * v2[0] + v1[1] * v2[1] + v1[2] * v2[2];
    return to_return;
}

struct Tm42Vec3 tm42_vec3_cross( const float* v1, const float* v2 ) {
    struct Tm42Vec3 to_return = {
        .x = v1[1] * v2[2] - v1[2] * v2[1],
        .y = v1[2] * v2[0] - v1[0] * v2[2],
        .z = v1[0] * v2[1] - v1[1] * v2[0],
    };
    return to_return;
}

void tm42_vec3_normalize( float* v ) {
    float length = sqrt( v[0] * v[0] + v[1] * v[1] + v[2] * v[2] );
    v[0] /= length;
    v[1] /= length;
    v[2] /= length;
}

#ifdef TM42_MATH_DEBUG_PRINT
void tm42_vec3_fprint( FILE* f, const float* v ) {
    fprintf( f, "Vec3: ( %f, %f, %f )", v[0], v[1], v[2] );
}
#endif

// [[ Vec4 ]]

void tm42_vec4_homogeneize( float* v ) {
    v[0] /= v[3];
    v[1] /= v[3];
    v[2] /= v[3];
    v[3] = 1;
}

#ifdef TM42_MATH_DEBUG_PRINT
void tm42_vec4_fprint( FILE* f, const float* v ) {
    fprintf( f, "Vec4: ( %f, %f, %f, %f )", v[0], v[1], v[2], v[3] );
}
#endif

// [[ Quaternion ]]

struct Tm42Quaternion tm42_quaternion_create_identity() {
    struct Tm42Quaternion to_return = {
        .s = 1.f,
        .x = 0.f,
        .y = 0.f,
        .z = 0.f,
    };
    return to_return;
}

void tm42_quaternion_normalize( float* q ) {
    float length = sqrt( q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3] );
    q[0] /= length;
    q[1] /= length;
    q[2] /= length;
    q[3] /= length;
}

struct Tm42Vec3 tm42_quaternion_rotate_vec3( const float* q, const float* v ) {
    // Quaternion components: q = [s, x, y, z]
    float s = q[0], qx = q[1], qy = q[2], qz = q[3];

    // Vector v treated as quaternion: v = [0, vx, vy, vz]
    float vx = v[0], vy = v[1], vz = v[2];

    // Compute q * v
    float rw = -qx * vx - qy * vy - qz * vz;
    float rx = s * vx + qy * vz - qz * vy;
    float ry = s * vy + qz * vx - qx * vz;
    float rz = s * vz + qx * vy - qy * vx;

    // Compute the above result * q^-1 (the conjugate, since q is normalized)
    struct Tm42Vec3 result;
    result.x = rx * s + rw * -qx + ry * -qz - rz * -qy; // Final x component
    result.y = ry * s + rw * -qy + rz * -qx - rx * -qz; // Final y component
    result.z = rz * s + rw * -qz + rx * -qy - ry * -qx; // Final z component

    return result;
}

struct Tm42Quaternion tm42_quaternion_rotation_between_vec3s( const float* src, const float* dst ) {
    struct Tm42Quaternion to_return;
    const float cos_theta = tm42_vec3_dot( src, dst );

    // If `cos_theta` is approximately `1`, then `src` and `dst` point in the same direction, so
    // there is no additional rotation needed.
    if ( cos_theta > 1 - 1e-6 ) {
        to_return = ( struct Tm42Quaternion ){
            .s = 1.f,
            .x = 0.f,
            .y = 0.f,
            .z = 0.f,
        };
        return to_return;
    }

    // If `cos_theta` is approximately `-1` then `src` and `dst` point in opposite directions. In
    // this case, there is no canonical perpindicular axis for rotation (usually this is the cross
    // product), but we can just pick any and use `PI/2` as the angle of rotation.
    if ( cos_theta < -1 + 1e-6 ) {
        struct Tm42Vec3 other_vec = { .x = 1.f, .y = 0.f, .z = 0.f };

        // Make sure not to accidentally pick another parallel vector.
        const float other_cos_theta = tm42_vec3_dot( src, (float*)&other_vec );
        if ( other_cos_theta > 1.f - 1e-6 || other_cos_theta < -1.f + 1e-6 ) {
            other_vec = ( struct Tm42Vec3 ){ .x = 0.f, .y = 1.f, .z = 0.f };
        }

        struct Tm42Vec3 rotation_axis = tm42_vec3_cross( (float*)&other_vec, src );
        tm42_vec3_normalize( &rotation_axis );

        // The rotation angle is PI/2, so the rotation quaternion is really easy to compute.
        // It is already normalized since there is no scalar component and we normalized the
        // rotation axis.
        to_return = ( struct Tm42Quaternion ){
            .s = 0.f,
            .x = rotation_axis.x,
            .y = rotation_axis.y,
            .z = rotation_axis.z,
        };
        return to_return;
    }

    // https://www.xarg.org/proof/quaternion-from-two-vectors/
    struct Tm42Vec3 cross_src_dst = tm42_vec3_cross( src, dst );
    to_return = ( struct Tm42Quaternion ){
        .s = 1.f + cos_theta,
        .x = cross_src_dst.x,
        .y = cross_src_dst.y,
        .z = cross_src_dst.z,
    };
    tm42_quaternion_normalize( &to_return );
    return to_return;
}

#ifdef TM42_MATH_DEBUG_PRINT
void tm42_quaternion_fprint( FILE* f, const float* q ) {
    fprintf( f, "Quaternion: ( %f + %fi + %fj + %fk )", q[0], q[1], q[2], q[3] );
}
#endif

// [[ Mat4 ]]

struct Tm42Mat4 tm42_mat4_create_identity() {
    struct Tm42Mat4 matrix = { 0 }; // Initialize all elements to 0

    matrix.m[0][0] = 1.0f;
    matrix.m[1][1] = 1.0f;
    matrix.m[2][2] = 1.0f;
    matrix.m[3][3] = 1.0f;

    return matrix;
}

struct Tm42Vec4 tm42_mat4_mul_vec4( const float* m, const float* v ) {
    struct Tm42Vec4 result;

    result.x = m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12] * v[3];
    result.y = m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13] * v[3];
    result.z = m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14] * v[3];
    result.w = m[3] * v[0] + m[7] * v[1] + m[11] * v[2] + m[15] * v[3];

    return result;
}

struct Tm42Mat4 tm42_mat4_mul_mat4( const float* m1, const float* m2 ) {
    struct Tm42Mat4 result;

    for ( int i = 0; i < 4; ++i ) {
        for ( int j = 0; j < 4; ++j ) {
            result.m[j][i] = m1[0 * 4 + i] * m2[j * 4 + 0] + m1[1 * 4 + i] * m2[j * 4 + 1] +
                             m1[2 * 4 + i] * m2[j * 4 + 2] + m1[3 * 4 + i] * m2[j * 4 + 3];
        }
    }

    return result;
}

struct Tm42Mat4 tm42_mat4_from_quaternion( const float* q ) {
    struct Tm42Mat4 matrix = { 0 }; // Initialize all elements to 0

    float s = q[0];
    float x = q[1];
    float y = q[2];
    float z = q[3];

    // Diagonal elements
    matrix.m[0][0] = 1 - 2 * y * y - 2 * z * z;
    matrix.m[1][1] = 1 - 2 * x * x - 2 * z * z;
    matrix.m[2][2] = 1 - 2 * x * x - 2 * y * y;
    matrix.m[3][3] = 1;

    // Off-diagonal elements, adjusted for column-major order
    matrix.m[1][0] = 2 * x * y - 2 * s * z;
    matrix.m[2][0] = 2 * x * z + 2 * s * y;
    matrix.m[0][1] = 2 * x * y + 2 * s * z;
    matrix.m[2][1] = 2 * y * z - 2 * s * x;
    matrix.m[0][2] = 2 * x * z - 2 * s * y;
    matrix.m[1][2] = 2 * y * z + 2 * s * x;

    // Last column and row are already set to 0, except matrix.m[3][3] which is set to 1.

    return matrix;
}

void tm42_mat4_apply_translation( float* m, const float* v ) {
    // Assuming m is in column-major order and represents a 4x4 matrix
    // and v is a 3-element array representing the translation vector (x, y, z).

    // Apply translation to the fourth column of the matrix
    m[12] += v[0]; // m[3,0] in 2D, but m[12] in 1D array representation
    m[13] += v[1]; // m[3,1] in 2D, but m[13] in 1D array representation
    m[14] += v[2]; // m[3,2] in 2D, but m[14] in 1D array representation

    // The fourth element of the fourth column (m[15] or m[3,3] in 2D) should already be 1 and
    // remains unchanged
}

struct Tm42Mat4 tm42_mat4_create_projection( float vertical_fov, float aspect_ratio, float z_near,
                                             float z_far ) {
    struct Tm42Mat4 result = { { { 0 } } };

    const float f = 1.f / tanf( vertical_fov / 2.f );
    const float fn = 1.f / ( z_near - z_far );

    result.m[0][0] = f / aspect_ratio;
    result.m[1][1] = f;
    result.m[2][2] = z_far * fn;
    result.m[2][3] = -1.f;
    result.m[3][2] = z_near * z_far * fn;

    return result;
}

struct Tm42Vec3 tm42_mat4_transform_vec3( const float* m, const float* v ) {
    struct Tm42Vec4 v4 = { .x = v[0], .y = v[1], .z = v[2], .w = 1.f };

    struct Tm42Vec4 transformed_v4 = tm42_mat4_mul_vec4( m, (float*)&v4 );
    tm42_vec4_homogeneize( (float*)&transformed_v4 );

    return ( struct Tm42Vec3 ){
        .x = transformed_v4.x,
        .y = transformed_v4.y,
        .z = transformed_v4.z,
    };
}

#ifdef TM42_MATH_DEBUG_PRINT
void tm42_mat4_fprint( FILE* f, const float* m ) {
    fprintf( f, "Matrix 4x4:\n" );
    for ( int row = 0; row < 4; ++row ) {
        // Print each row
        fprintf( f, "| %7.2f %7.2f %7.2f %7.2f |\n", m[row + 0 * 4], m[row + 1 * 4], m[row + 2 * 4],
                 m[row + 3 * 4] );
    }
}
#endif

#endif // TM42_MATH_IMPLEMENTATION
