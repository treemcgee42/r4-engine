
#include <math.h>
#include <stdbool.h>
#include <stdio.h>

#define TM42_MATH_IMPLEMENTATION
#define TM42_MATH_DEBUG_PRINT
#include "tm42_math.h"
#undef TM42_MATH_DEBUG_PRINT
#undef TM42_MATH_IMPLEMENTATION

#define TM42_CAMERA_IMPLEMENTATION
#include "tm42_turntable_camera.h"

bool float_eq( float f1, float f2 ) { return fabs( f1 - f2 ) < 0.000001; }

void create_viewinfo_test_helper( float* look_at, float* look_from, int* num_tests,
                                  int* num_failures ) {
    *num_tests += 1;
    bool failed = false;

    const struct Tm42ViewInfo view_info = tm42_create_viewinfo( look_at, look_from );

    const struct Tm42Vec3 look_at_in_view_space_coords =
        tm42_mat4_transform_vec3( (float*)&view_info.view_matrix, look_at );
    const struct Tm42Vec3 look_from_in_view_space_coords =
        tm42_mat4_transform_vec3( (float*)&view_info.view_matrix, look_from );

    // The look_from should be at the origin.

    if ( !( float_eq( look_from_in_view_space_coords.x, 0.f ) &&
            float_eq( look_from_in_view_space_coords.y, 0.f ) &&
            float_eq( look_from_in_view_space_coords.z, 0.f ) ) ) {
        failed = true;

        printf( "ERROR\n" );
        printf( "  look_at: " );
        tm42_vec3_fprint( stdout, look_at );
        printf( "\n" );
        printf( "  look_from: " );
        tm42_vec3_fprint( stdout, look_from );
        printf( "\n" );
        printf( "  view matrix: " );
        tm42_mat4_fprint( stdout, (float*)&view_info.view_matrix );
        printf( "  transformed look_from was not at origin\n" );
        printf( "    got: " );
        tm42_vec3_fprint( stdout, (float*)&look_from_in_view_space_coords );
        printf( "\n" );
    }

    // The look_at should be along the forward ray (0,0,0)+(0,0,-1)t.

    if ( !( float_eq( look_at_in_view_space_coords.x, 0.f ) &&
            float_eq( look_at_in_view_space_coords.y, 0.f ) &&
            look_at_in_view_space_coords.z < 0.f ) ) {
        failed = true;

        printf( "ERROR\n" );
        printf( "  look_at: " );
        tm42_vec3_fprint( stdout, look_at );
        printf( "\n" );
        printf( "  look_from: " );
        tm42_vec3_fprint( stdout, look_from );
        printf( "\n" );
        printf( "  transformed look_at did not align with forward ray\n" );
        printf( "    got: " );
        tm42_vec3_fprint( stdout, (float*)&look_at_in_view_space_coords );
        printf( "\n" );
        printf( "    expected something along ray (0,0,-t)\n" );
    }

    // The distance between look_at and look_from should be the same before and after
    // transformation.

    const float distance_before = tm42_point3_distance( look_at, look_from );
    const float distance_after = tm42_point3_distance( (float*)&look_at_in_view_space_coords,
                                                       (float*)&look_from_in_view_space_coords );
    if ( !float_eq( distance_before, distance_after ) ) {
        failed = true;

        printf( "ERROR\n" );
        printf( "  look_at:   " );
        tm42_vec3_fprint( stdout, look_at );
        printf( "\n" );
        printf( "    transformed: " );
        tm42_vec3_fprint( stdout, (float*)&look_at_in_view_space_coords );
        printf( "\n" );
        printf( "  look_from: " );
        tm42_vec3_fprint( stdout, look_from );
        printf( "\n" );
        printf( "    transformed: " );
        tm42_vec3_fprint( stdout, (float*)&look_from_in_view_space_coords );
        printf( "\n" );
        printf( "  distance between look_at and look_from changed after transformation\n" );
        printf( "    got (after transformation):       %f\n", distance_after );
        printf( "    expected (before transformation): %f\n", distance_before );
    }

    if ( failed ) {
        *num_failures += 1;
    }
}

void test_create_viewinfo() {
    int num_tests = 0;
    int num_failures = 0;

    {
        const struct Tm42Point3 look_at = { .x = 1.f, .y = -1.f, .z = 1.f };
        const struct Tm42Point3 look_from = { .x = 0.f, .y = 0.f, .z = 0.f };

        create_viewinfo_test_helper( (float*)&look_at, (float*)&look_from, &num_tests,
                                     &num_failures );
    }

    {
        const struct Tm42Point3 look_at = { .x = 0.f, .y = -1.f, .z = 0.f };
        const struct Tm42Point3 look_from = { .x = 0.f, .y = 1.f, .z = 0.f };

        create_viewinfo_test_helper( (float*)&look_at, (float*)&look_from, &num_tests,
                                     &num_failures );
    }

    printf( "%s: ", __func__ );
    if ( num_failures == 0 ) {
        printf( "PASSED\n" );
    } else {
        printf( "FAILED (%d/%d ok)\n", num_tests - num_failures, num_tests );
    }
}

int main( int argc, char** argv ) {
    printf( "Hello, world!\n" );

    test_create_viewinfo();

    return 0;
}
