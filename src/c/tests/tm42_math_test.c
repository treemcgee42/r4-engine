#include <assert.h>
#include <stdbool.h>
#include <stdio.h>

#define TM42_MATH_DEBUG_PRINT
#define TM42_MATH_IMPLEMENTATION
#include "tm42_math.h"

bool areFloatsEqual( float a, float b ) { return fabs( a - b ) < 0.0001; }

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

void projection_matrix_text_helper( float vertical_fov, float aspect_ratio, float z_near,
                                    float z_far ) {
    const struct Tm42Mat4 pm =
        tm42_mat4_create_projection( vertical_fov, aspect_ratio, z_near, z_far );

    // Test that all eight corners of the frustum get mapped to the eight corners of the
    // NDC cube.
}

// ---

int main( int argc, char** argv ) {
    test_cross_product();
    test_quaternion_rotation();
    // foo();

    printf( "Hello, world!\n" );
    return 0;
}
