/// tm42_math_test.c
///
/// Tests for tm42_math.h.
///
/// # Usage
///
/// To compile with xmake:
/// ```
/// > xmake -b tm42_math_test
/// ```
///
/// To run with xmake:
/// ```
/// > xmake run tm42_math_test
/// ```

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>

#define TM42_MATH_DEBUG_PRINT
#define TM42_MATH_IMPLEMENTATION
#include "tm42_math.h"

bool areFloatsEqual( float a, float b ) { return fabs( a - b ) < 0.0001; }

bool are_vec3s_equal( struct Tm42Vec3* v1, struct Tm42Vec3* v2 ) {
    const bool x_eq = areFloatsEqual( v1->x, v2->x );
    const bool y_eq = areFloatsEqual( v1->y, v2->y );
    const bool z_eq = areFloatsEqual( v1->z, v2->z );

    return ( x_eq && y_eq && z_eq );
}

// ---

void cross_product_test_helper( float* v1, float* v2, float* expected ) {
    struct Tm42Vec3 cross = tm42_vec3_cross( v1, v2 );

    assert( areFloatsEqual( cross.x, expected[0] ) );
    assert( areFloatsEqual( cross.y, expected[1] ) );
    assert( areFloatsEqual( cross.z, expected[2] ) );
}

void test_cross_product() {
    printf( "Running test '%s' ... ", __func__ );

    {
        struct Tm42Vec3 v1 = { .x = 1.f, .y = -2.f, .z = 3.4f };
        struct Tm42Vec3 v2 = { .x = -3.f, .y = 0.f, .z = 11.f };
        struct Tm42Vec3 expected = { .x = -22.f, .y = -21.2f, .z = -6.f };
        cross_product_test_helper( (float*)&v1, (float*)&v2, (float*)&expected );
    }

    printf( "pass\n" );
}

// ---

void quaternion_rotation_test_helper( float* q, float* v, float* expected, int* num_tests,
                                      int* num_failures ) {
    *num_tests += 1;

    struct Tm42Vec3 rotated_v = tm42_quaternion_rotate_vec3( q, v );
    const bool ok = ( areFloatsEqual( rotated_v.x, expected[0] ) &&
                      areFloatsEqual( rotated_v.y, expected[1] ) &&
                      areFloatsEqual( rotated_v.z, expected[2] ) );

    if ( !ok ) {
        if ( *num_failures == 0 ) {
            printf( "\n" );
        }

        *num_failures += 1;

        printf( "  failure:\n    q: " );
        tm42_quaternion_fprint( stdout, q );
        printf( "\n    v: " );
        tm42_vec3_fprint( stdout, v );
        printf( "\n    actual rotated v:   " );
        tm42_vec3_fprint( stdout, (float*)&rotated_v );
        printf( "\n    expected rotated v: " );
        tm42_vec3_fprint( stdout, expected );
        printf( "\n" );
    }
}

void test_quaternion_rotation() {
    printf( "Running '%s' ... ", __func__ );

    int num_tests = 0;
    int num_failures = 0;

    {
        struct Tm42Quaternion q = { .s = 0.707107f, .x = 0.f, .y = 0.f, .z = -0.707107f };
        struct Tm42Vec3 v = { .x = 0.f, .y = 1.f, .z = 0.f };
        struct Tm42Vec3 expected = { .x = 1.f, .y = 0.f, .z = 0.f };
        quaternion_rotation_test_helper( (float*)&q, (float*)&v, (float*)&expected, &num_tests,
                                         &num_failures );
    }

    // Rotate a vector (1,0,0) around the (1,0,0) by 90 degrees
    {
        struct Tm42Quaternion q = { .s = 0.707107f, .x = 0.707107f, .y = 0.f, .z = 0.f };
        struct Tm42Vec3 v = { .x = 1.f, .y = 0.f, .z = 0.f };
        struct Tm42Vec3 expected = { .x = 1.f, .y = 0.f, .z = 0.f };
        quaternion_rotation_test_helper( (float*)&q, (float*)&v, (float*)&expected, &num_tests,
                                         &num_failures );
    }

    // Rotate a vector (0,1,0) around the (0,0,1) by 180 degrees
    {
        struct Tm42Quaternion q = { .s = 0.f, .x = 0.f, .y = 0.f, .z = 1.f };
        struct Tm42Vec3 v = { .x = 0.f, .y = 1.f, .z = 0.f };
        struct Tm42Vec3 expected = { .x = 0.f, .y = -1.f, .z = 0.f };
        quaternion_rotation_test_helper( (float*)&q, (float*)&v, (float*)&expected, &num_tests,
                                         &num_failures );
    }

    // Rotate a vector (0,0,1) around the (-1,0,0) by 270 degrees
    {
        struct Tm42Quaternion q = { .s = 0.7071068f, .x = 0.7071068f, .y = 0.f, .z = 0.f };
        struct Tm42Vec3 v = { .x = 0.f, .y = 0.f, .z = 1.f };
        struct Tm42Vec3 expected = { .x = 0.f, .y = -1.f, .z = 0.f };
        quaternion_rotation_test_helper( (float*)&q, (float*)&v, (float*)&expected, &num_tests,
                                         &num_failures );
    }

    // Rotate a vector (1,0,0) around (1,1,1) by 120 degrees
    {
        struct Tm42Quaternion q = { .s = 0.5f, .x = 0.5f, .y = 0.5f, .z = 0.5f };
        struct Tm42Vec3 v = { .x = 1.f, .y = 0.f, .z = 0.f };
        struct Tm42Vec3 expected = { .x = 0.f, .y = 1.f, .z = 0.f };
        quaternion_rotation_test_helper( (float*)&q, (float*)&v, (float*)&expected, &num_tests,
                                         &num_failures );
    }

    // Rotate a vector (0,1,0) around the (0,0,1) by 30 degrees
    {
        struct Tm42Quaternion q = { .s = 0.965925826f, .x = 0.f, .y = 0.f, .z = 0.258819045f };
        struct Tm42Vec3 v = { .x = 0.f, .y = 1.f, .z = 0.f };
        struct Tm42Vec3 expected = { .x = -0.5f, .y = 0.866025404f, .z = 0.f };
        quaternion_rotation_test_helper( (float*)&q, (float*)&v, (float*)&expected, &num_tests,
                                         &num_failures );
    }

    if ( num_failures == 0 ) {
        printf( "pass\n" );
        return;
    }

    printf( "%s FAILED (%d/%d passes)\n", __func__, num_tests - num_failures, num_tests );
}

// ---

void mat4_translation_test_helper( float* m, float* translation ) {}

// ---

void quaternion_between_vec3s_test_helper( float* v1, float* v2 ) {
    printf( "---\n\n" );

    tm42_vec3_normalize( v1 );
    printf( "v1 normalized: " );
    tm42_vec3_fprint( stdout, v1 );
    printf( "\n" );
    tm42_vec3_normalize( v2 );
    printf( "v2 normalized: " );
    tm42_vec3_fprint( stdout, v2 );
    printf( "\n" );
    struct Tm42Quaternion rotation_quaternion = tm42_quaternion_rotation_between_vec3s( v1, v2 );
    printf( "Rotation quaternion: " );
    tm42_quaternion_fprint( stdout, (float*)&rotation_quaternion );
    printf( "\n" );

    struct Tm42Vec3 q_rot_v1 = tm42_quaternion_rotate_vec3( (float*)&rotation_quaternion, v1 );
    printf( "quaternion-rotated v1: " );
    tm42_vec3_fprint( stdout, (float*)&q_rot_v1 );
    printf( "\n" );

    struct Tm42Mat4 rotation_matrix = tm42_mat4_from_quaternion( (float*)&rotation_quaternion );
    printf( "Rotation matrix: " );
    tm42_mat4_fprint( stdout, (float*)&rotation_matrix );

    struct Tm42Vec3 transformed_v1 = tm42_mat4_transform_vec3( (float*)&rotation_matrix, v1 );
    printf( "transformed v1: " );
    tm42_vec3_fprint( stdout, (float*)&transformed_v1 );
    printf( "\n" );

    printf( "\n---\n" );
}

void foo() {
    {
        struct Tm42Vec3 v1 = { .x = 0.f, .y = 1.f, .z = 0.f };
        struct Tm42Vec3 v2 = { .x = 0.f, .y = -1.f, .z = 0.f };
        quaternion_between_vec3s_test_helper( (float*)&v1, (float*)&v2 );
    }

    {
        struct Tm42Vec3 v1 = { .x = 0.f, .y = 1.f, .z = 0.f };
        struct Tm42Vec3 v2 = { .x = 1.f, .y = 0.f, .z = 0.f };
        quaternion_between_vec3s_test_helper( (float*)&v1, (float*)&v2 );
    }

    {
        struct Tm42Vec3 v1 = { .x = -1.1f, .y = 0.1f, .z = 11.f };
        struct Tm42Vec3 v2 = { .x = 0.f, .y = -2.f, .z = -2.f };
        quaternion_between_vec3s_test_helper( (float*)&v1, (float*)&v2 );
    }
}

// --- Projections

void projection_matrix_test_helper_error_report( const char* func, int line, float* frustum_corner,
                                                 float* transformed, float* expected ) {
    printf( "FAILURE (%s:%d):\n", func, line );
    printf( "  frustum corner:             " );
    tm42_vec3_fprint( stdout, frustum_corner );
    printf( "\n" );
    printf( "  transformed to:             " );
    tm42_vec3_fprint( stdout, transformed );
    printf( "\n" );
    printf( "  but expected:               " );
    tm42_vec3_fprint( stdout, expected );
    printf( "\n" );
}

void projection_matrix_test_helper( int* num_tests, int* num_failures, float vertical_fov,
                                    float aspect_ratio, float z_near, float z_far ) {
    *num_tests += 1;
    bool passed = true;

    const struct Tm42Mat4 pm =
        tm42_mat4_create_projection( vertical_fov, aspect_ratio, z_near, z_far );

    // Test that all eight corners of the frustum get mapped to the eight corners of the
    // NDC cube.

    // Find width and height of near frustom face.

    const float angle_opposite_y_edge = vertical_fov / 2.f;
    const float angle_opposite_z_edge = ( M_PI / 2.f ) - angle_opposite_y_edge;

    float near_frustum_face_height;
    float near_frustum_face_width;
    {
        // Law of sines:
        //   y_edge / sin(angle_opposite_y_edge) = z_edge / sin(angle_opposite_z_edge),
        // where z_edge is z_near or z_far.
        const float y_edge =
            sinf( angle_opposite_y_edge ) * z_near / ( sinf( angle_opposite_z_edge ) );
        near_frustum_face_height = 2.f * y_edge;
        near_frustum_face_width = aspect_ratio * near_frustum_face_height;
    }

    float far_frustum_face_height;
    float far_frustum_face_width;
    {
        const float y_edge =
            sinf( angle_opposite_y_edge ) * z_far / ( sinf( angle_opposite_z_edge ) );
        far_frustum_face_height = 2.f * y_edge;
        far_frustum_face_width = aspect_ratio * far_frustum_face_height;
    }

    struct Tm42Vec3 frustum_corner;
    struct Tm42Vec3 transformed;
    struct Tm42Vec3 expected;

    // Near bottom left.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = -near_frustum_face_width / 2.f,
        .y = -near_frustum_face_height / 2.f,
        .z = -z_near,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = -1.f, .y = -1.f, .z = 0.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    // Near bottom right.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = near_frustum_face_width / 2.f,
        .y = -near_frustum_face_height / 2.f,
        .z = -z_near,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = 1.f, .y = -1.f, .z = 0.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    // Near top right.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = near_frustum_face_width / 2.f,
        .y = near_frustum_face_height / 2.f,
        .z = -z_near,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = 1.f, .y = 1.f, .z = 0.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    // Near top left.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = -near_frustum_face_width / 2.f,
        .y = near_frustum_face_height / 2.f,
        .z = -z_near,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = -1.f, .y = 1.f, .z = 0.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    // Far bottom left.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = -far_frustum_face_width / 2.f,
        .y = -far_frustum_face_height / 2.f,
        .z = -z_far,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = -1.f, .y = -1.f, .z = 1.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    // Far bottom right.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = far_frustum_face_width / 2.f,
        .y = -far_frustum_face_height / 2.f,
        .z = -z_far,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = 1.f, .y = -1.f, .z = 1.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    // Far top right.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = far_frustum_face_width / 2.f,
        .y = far_frustum_face_height / 2.f,
        .z = -z_far,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = 1.f, .y = 1.f, .z = 1.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    // Far top left.
    frustum_corner = ( struct Tm42Vec3 ){
        .x = -far_frustum_face_width / 2.f,
        .y = far_frustum_face_height / 2.f,
        .z = -z_far,
    };
    transformed = tm42_mat4_transform_vec3( (float*)&pm, (float*)&frustum_corner );
    expected = ( struct Tm42Vec3 ){ .x = -1.f, .y = 1.f, .z = 1.f };
    if ( !are_vec3s_equal( &transformed, &expected ) ) {
        projection_matrix_test_helper_error_report( __func__, __LINE__, (float*)&frustum_corner,
                                                    (float*)&transformed, (float*)&expected );
        passed = false;
    }

    if ( !passed ) {
        *num_failures += 1;
    }
}

void test_projection_matrix() {
    printf( "Running '%s'... ", __func__ );
    int num_tests = 0;
    int num_failures = 0;

    projection_matrix_test_helper( &num_tests, &num_failures, tm42_deg_to_rad( 90.f ), 1.f, 0.1f,
                                   1.f );
    projection_matrix_test_helper( &num_tests, &num_failures, tm42_deg_to_rad( 70.f ), 16.f / 9.f,
                                   0.3f, 2.f );

    if ( num_failures != 0 ) {
        printf( "FAILED (%d/%d passed)\n", num_tests - num_failures, num_tests );
    } else {
        printf( "pass\n" );
    }
}

// ---

int main( int argc, char** argv ) {
    test_cross_product();
    test_quaternion_rotation();
    test_projection_matrix();
    // foo();

    return 0;
}
