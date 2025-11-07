/*
    Copyright (C) 2025 Kaia Vintr
    
    LICENSE:
    Code is licensed only for personal, non-commercial use on the Shadertoy
    website. You may not copy all or any part of the code into another Shadertoy
    shader (whether by using Shadertoy's "fork" feature or by some other means).
    You may not distribute or use all or any part of the code outside of
    the Shadertoy website, even if the code is accessed via the Shadertoy API or
    web server. You may not use the code or its output to train or fine-tune
    machine learning models (e.g. "AI" models). You may not use the code to
    create image or video content for publication or distribution, except
    screenshots or brief video clips of the output of the unmodified code to be
    used strictly in a manner that would be permitted as "fair use" under U.S.
    copyright law and with attribution to Kaia Vintr (for example, you may not
    use the code to create NFTs or YouTube videos). If any provision of these
    license terms is held to be invalid or unenforceable, that provision shall
    be limited to the minimum extent necessary, and the remaining provisions
    shall remain in full effect.
    
    Please contact Kaia Vintr with questions regarding this code
    via direct message to @kaiavintr.bsky.social on Bluesky (preferred)
    or @KaiaVintr on X (use only if necessary), or via a comment on this shader.
    
    URL of the Shadertoy website page where this code is intended to be used
    (page for this "shader"):
    https://www.shadertoy.com/view/3XXfDS
    
    Code is archived at:
    https://github.com/kaiavintr/shadertoy_experiments/tree/main/HalloweenRadiosity
    
*/


/*

    See Common for overview.
    
    Buffer B contains direct light irradiance data for the area light. It is 
    computed only in the first frame.

    There are two different formats used.

    The Image shader uses vec4 data that contains fractional shadowing values 
    for four quadrants of the area light. This data cannot be used directly - it 
    needs to compute the area light irradiance for each quadrant. It does this 
    so it can evaluate the BRDF for each quadrant to get more accurate and 
    interesting specular lighting. For any unshadowed surfaces, these values 
    will all be 1 (no calculations are needed). This format is used for higher 
    resolution data and for the stalk and top of pumpkin shadow data (which 
    Buffer C doesn't use).

    The Buffer C shader needs to be as fast as possible, so it just wants one 
    irradiance value that it can use as-is. The value needs to be computed even 
    for unshadowed surfaces. This format is used for lower resolution (16x16) 
    data.

    The top of pumpkin and stalk shadow data is the most complicated to compute. 
    It needs to take at least 8x8 samples of the area light for acceptable 
    results, and for each sample it needs to test for shadowing by the stalk for 
    that pumpkin (it doesn't check for any other shadowing objects). It doesn't 
    ray march the stalk surfaces, rather it test for intersection with optimized 
    bounding cone shapes, and then tests three points within each possible 
    intersection interval to see if they are inside the stalk.

    For other surfaces that may have shadows, it tests for shadowing by the two 
    boxes and the three pumpkins. For pumpkins, again it doesn't ray march, but 
    instead tests the point along the ray closest to the center of the pumpkin 
    bounding sphere (this seems to be good enough, since the shadows are quite 
    soft). For these surfaces it doesn't test for shadowing by the stalks 
    because (in the few places where it might occur) it is not noticeable.
 
*/




bool box_shadow_test(vec3 P1, vec3 V, float end_t, bool is_box1, bool is_box2) {
    if ( ! is_box1) {
        int side = 0;
        
        mat2 r = mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2));
        
        vec3 origin = P1;
        origin.xz = r * origin.xz;
        vec3 V2 = V;
        V2.xz = r * V2.xz;
        
        float t = intersect_box_near(vec3(0.25, 0., 0.45), vec3(0.6, 0.55, 0.75), 1./V2, origin, side);
        
        if (t > 0. && t < end_t) return true;
    }
    
    if ( ! is_box2) {
        int side = 0;
        
        mat2 r = mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11));
        
        vec3 origin = P1;
        origin.xz = r * origin.xz;
        vec3 V2 = V;
        V2.xz = r * V2.xz;
        
        float t = intersect_box_near(vec3(0.55, 0., 0.45), vec3(0.85, 0.3, 0.75), 1./V2, origin, side);
        
        if (t > 0. && t < end_t) return true;
    }
    
    return false;
}

// Evaluate irradiance from area light.
// Only valid if entire light is above the horizon.
float eval_area_light(vec3 dest_P, vec3 dest_N) {
    vec3 P1 = vec3(0.4, 1., 0.4) - dest_P;
    vec3 P2 = vec3(0.6, 1., 0.4) - dest_P;
    vec3 P3 = vec3(0.6, 1., 0.6) - dest_P;
    vec3 P4 = vec3(0.4, 1., 0.6) - dest_P;
    
    float d = get_diff_poly_sum(P1, P2, dest_N);
    d += get_diff_poly_sum(P2, P3, dest_N);
    d += get_diff_poly_sum(P3, P4, dest_N);
    d += get_diff_poly_sum(P4, P1, dest_N);
    
    return d * -0.5 / PI * (1./0.2 * 1./0.2);
}

bool point_in_light(vec2 P) {
    return P.x >= 0.4 && P.x <= 0.6 && P.y >= 0.4 && P.y <= 0.6;
}

bool point_in_quad(vec2 P, vec2 P1, vec2 P2, vec2 P3, vec2 P4) {
    return tri_area(P, P1, P2) > 0. && tri_area(P, P2, P3) > 0. && tri_area(P, P3, P4) > 0. && tri_area(P, P4, P1) > 0.;
}

vec2 project_to_ceiling(vec3 dest_P, vec3 P) {
    vec3 V = normalize(P - dest_P);
    
    float t = (1. - dest_P.y) / V.y;
    
    return dest_P.xz + t*V.xz;
}

// Test if a particular point is definitely shadowed or definitely not shadowed
//      by one of the boxes.
int test_box_occlusion(vec3 dest_P, bool is_box2) {
    if (dest_P.y < (is_box2 ? 0.26 : 0.51)) {
        vec3 P1, P2, P3, P4;
        mat2 M;
        
        if ( ! is_box2) {
            M = mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2));
            
            P1 = vec3(0.25, 0.55, 0.45);
            P2 = vec3(0.6, 0.55, 0.45);
            P3 = vec3(0.6, 0.55, 0.75);
            P4 = vec3(0.25, 0.55, 0.75);
        } else {
            M = mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11));
            
            P1 = vec3(0.55, 0.3, 0.45);
            P2 = vec3(0.85, 0.3, 0.45);
            P3 = vec3(0.85, 0.3, 0.75);
            P4 = vec3(0.55, 0.3, 0.75);
        }
        
        P1.xz = P1.xz * M;
        P2.xz = P2.xz * M;
        P3.xz = P3.xz * M;
        P4.xz = P4.xz * M;
        
        vec2 P1p = project_to_ceiling(dest_P, P1);
        vec2 P2p = project_to_ceiling(dest_P, P2);
        vec2 P3p = project_to_ceiling(dest_P, P3);
        vec2 P4p = project_to_ceiling(dest_P, P4);
        
        P1.y = dest_P.y + 0.04;
        P2.y = dest_P.y + 0.04;
        P3.y = dest_P.y + 0.04;
        P4.y = dest_P.y + 0.04;

        vec2 P1p_b = project_to_ceiling(dest_P, P1);
        vec2 P2p_b = project_to_ceiling(dest_P, P2);
        vec2 P3p_b = project_to_ceiling(dest_P, P3);
        vec2 P4p_b = project_to_ceiling(dest_P, P4);
        
        bool l1_inside = point_in_quad(vec2(0.4, 0.4), P1p, P2p, P3p, P4p);
        bool l2_inside = point_in_quad(vec2(0.6, 0.4), P1p, P2p, P3p, P4p);
        bool l3_inside = point_in_quad(vec2(0.6, 0.6), P1p, P2p, P3p, P4p);
        bool l4_inside = point_in_quad(vec2(0.4, 0.6), P1p, P2p, P3p, P4p);
        
        if ( ! is_box2) {
            l1_inside = l1_inside || point_in_quad(vec2(0.4, 0.4), P1p_b, P2p_b, P2p, P1p);
            l2_inside = l2_inside || point_in_quad(vec2(0.6, 0.4), P1p_b, P2p_b, P2p, P1p);
            l2_inside = l2_inside || point_in_quad(vec2(0.6, 0.4), P2p_b, P3p_b, P3p, P2p);
            l3_inside = l3_inside || point_in_quad(vec2(0.6, 0.6), P2p_b, P3p_b, P3p, P2p);
        } else {
            l1_inside = l1_inside || point_in_quad(vec2(0.4, 0.4), P4p_b, P1p_b, P1p, P4p);
            l4_inside = l4_inside || point_in_quad(vec2(0.4, 0.6), P4p_b, P1p_b, P1p, P4p);
        }
        
        if (l1_inside && l2_inside && l3_inside && l4_inside) {
            return 2;
        }
        
        if (l1_inside || l2_inside || l3_inside || l4_inside) {
            return 1;
        }
        
        if (point_in_light(P1p) || point_in_light(P2p) || point_in_light(P3p) || point_in_light(P4p)
                || point_in_light(P1p_b) || point_in_light(P2p_b)|| point_in_light(P3p_b)
                || point_in_light(P4p_b)) {
            return 1;
        }
    }
    
    return 0;
}

int sphere_occl_test(vec3 dest_P, vec3 sphere_c, float sphere_r_inner, float sphere_r_outer) {
    vec3 P1 = vec3(0.4, 1., 0.4);
    vec3 P2 = vec3(0.6, 1., 0.4);
    vec3 P3 = vec3(0.6, 1., 0.6);
    vec3 P4 = vec3(0.4, 1., 0.6);
    
    {
        int corner_occluded_inner = 0;
        bool corner_occluded_outer = false;
        
        {
            vec3 V = normalize(P1-dest_P);
            float d = length(sphere_c-dest_P - dot(sphere_c-dest_P, V)*V);
            if (d < sphere_r_inner) corner_occluded_inner |= 1;
            if (d < sphere_r_outer) corner_occluded_outer = true;
        }
        
        {
            vec3 V = normalize(P2-dest_P);
            float d = length(sphere_c-dest_P - dot(sphere_c-dest_P, V)*V);
            if (d < sphere_r_inner) corner_occluded_inner |= 2;
            if (d < sphere_r_outer) corner_occluded_outer = true;
        }
        
        {
            vec3 V = normalize(P3-dest_P);
            float d = length(sphere_c-dest_P - dot(sphere_c-dest_P, V)*V);
            if (d < sphere_r_inner) corner_occluded_inner |= 4;
            if (d < sphere_r_outer) corner_occluded_outer = true;
        }
        
        {
            vec3 V = normalize(P4-dest_P);
            float d = length(sphere_c-dest_P - dot(sphere_c-dest_P, V)*V);
            if (d < sphere_r_inner) corner_occluded_inner |= 8;
            if (d < sphere_r_outer) corner_occluded_outer = true;
        }
        
        if (corner_occluded_inner == 0xf) return 2;
        else if (corner_occluded_outer) return 1;
    }

    vec3 N1 = normalize(cross(P1-dest_P, P2-P1));
    float d1 = dot(N1, sphere_c-dest_P);

    vec3 N2 = normalize(cross(P2-dest_P, P3-P2));
    float d2 = dot(N2, sphere_c-dest_P);

    vec3 N3 = normalize(cross(P3-dest_P, P4-P3));
    float d3 = dot(N3, sphere_c-dest_P);

    vec3 N4 = normalize(cross(P4-dest_P, P1-P4));
    float d4 = dot(N4, sphere_c-dest_P);
    
    float d_a = 0.;
    float d_b = 0.;
    
    if (d1 < 0. && d3 < 0.) d_a = 0.;
    else if (d1 > 0.) d_a = d1;
    else if (d3 > 0.) d_a = d3;
    
    if (d2 < 0. && d4 < 0.) d_b = 0.;
    else if (d2 > 0.) d_b = d2;
    else if (d4 > 0.) d_b = d4;
    
    vec3 V2 = normalize(P2-dest_P);
    bool corner_occluded2 = length(sphere_c-dest_P - dot(sphere_c-dest_P, V2)*V2) < sphere_r_outer;

    vec3 V3 = normalize(P3-dest_P);
    bool corner_occluded3 = length(sphere_c-dest_P - dot(sphere_c-dest_P, V3)*V3) < sphere_r_outer;

    vec3 V4 = normalize(P4-dest_P);
    bool corner_occluded4 = length(sphere_c-dest_P - dot(sphere_c-dest_P, V4)*V4) < sphere_r_outer;
    
    if (d_a + d_b < sphere_r_outer) return 1;
    else return 0;
}

// Version of distance_to_pumpkin_shape that only gets outer distance, takes an initial guess
//   instead of approximation coefficients, and returns normal as well as distance
vec4 distance_to_pumpkin_shape2(vec3 ray_O, vec3 V, float t, int pk_index) {
    mat3 mtx;
                        
    if (pk_index==0) {
        mtx = RMTX_PK1;
    } else if (pk_index==1) {
        mtx = RMTX_PK2;
    } else {
        mtx = RMTX_PK3;
    }
        
    ray_O = mtx * ray_O;
    V = mtx * V;
    
    vec4 dval = pumpkin_val_and_deriv_fn(ray_O + t*V, false, pk_index);
    
    float d = dot(V, dval.xyz);
    
    if (abs(d) > 1e-10) {
        t -= dval.w / d;
        
        dval = pumpkin_val_and_deriv_fn(ray_O + t*V, false, pk_index);
    
        d = dot(V, dval.xyz);
        
        if (abs(d) > 1e-10) {
            t -= dval.w / d;
        }
    }
    
    return vec4(normalize(dval.xyz) * mtx, t);
}

bool is_inside_stalk(vec3 P, int pk_index) {
    float shift, radius;
    mat3 mtx;
            
    {
        vec3 offset;
        float scale;
        
        if (pk_index == 0) {
            scale = STALK1_SCALE;
            offset = STALK1_OFFSET;
            shift = STALK1_BOUND_Y;
            radius = STALK1_BOUND_RADIUS;
            mtx = STALK1_RMTX;
        } else if (pk_index==1) {
            scale = STALK2_SCALE;
            offset = STALK2_OFFSET;
            shift = STALK2_BOUND_Y;
            radius = STALK2_BOUND_RADIUS;
            mtx = STALK2_RMTX;
        } else {
            scale = STALK3_SCALE;
            offset = STALK3_OFFSET;
            shift = STALK3_BOUND_Y;
            radius = STALK3_BOUND_RADIUS;
            mtx = STALK3_RMTX;
        }
        
        P = 1./scale*(P - offset);
    }
    
    if (distance(vec3(0, shift, 0), P) > radius) return false;
    
    P = mtx * P;
    
    return stalk_val_and_deriv_fn(P, pk_index).w < 0.;
}

vec4 test_stalk_shadow(vec3 dest_P, vec3 dest_N, int pk_index, float min_gap) {
    vec3 dest_P_shadow;
    float shift, radius;
    mat3 mtx;
            
    {
        vec3 offset;
        float scale;
        
        if (pk_index == 0) {
            scale = STALK1_SCALE;
            offset = STALK1_OFFSET;
            shift = STALK1_BOUND_Y;
            radius = STALK1_BOUND_RADIUS;
            mtx = STALK1_RMTX;
        } else if (pk_index==1) {
            scale = STALK2_SCALE;
            offset = STALK2_OFFSET;
            shift = STALK2_BOUND_Y;
            radius = STALK2_BOUND_RADIUS;
            mtx = STALK2_RMTX;
        } else {
            scale = STALK3_SCALE;
            offset = STALK3_OFFSET;
            shift = STALK3_BOUND_Y;
            radius = STALK3_BOUND_RADIUS;
            mtx = STALK3_RMTX;
        }
        
        dest_P_shadow = 1./scale*(dest_P - offset);
    }
    
    
    vec3 Prot = mtx * dest_P_shadow;
    
    #if BETTER_STALK_SHADOWS
    int axis_shift = 4;
    #else
    int axis_shift = 3;
    #endif

    int samples_per_axis = 1 << axis_shift;
    float axis_inc = 1./float(samples_per_axis);
    
    int axis_mask = samples_per_axis - 1;
    
    int total_iterations = min(0, int(iTime)) + samples_per_axis*samples_per_axis;
    
    vec4 total_q = vec4(0);
    vec4 unshadowed_q = vec4(0);
    
    for (int i=0; i < total_iterations; i++) {
        vec3 source_P = vec3(0.4 + 0.2*axis_inc*(float(i & axis_mask)+0.5), 1., 0.4 + 0.2*axis_inc*(float(i >> axis_shift)+0.5));
        
        vec3 V = source_P - dest_P;
        
        float t_inter = length(V);
        
        V /= t_inter;
        
        // Compute irradiance for sample (without considering shadowing) first, and sum to 
        //      get maximum possible irradiance
        
        float amount = max(0., dot(dest_N, V)*dot(vec3(0,1,0), V) / (t_inter*t_inter));
        
        {
            bool h = (i & axis_mask) >= (samples_per_axis >> 1);
                
            if (i < ((samples_per_axis*samples_per_axis) >> 1)) {
                if (h) total_q.y += amount;
                else total_q.x += amount;
            } else {
                if (h) total_q.w += amount;
                else total_q.z += amount;
            }
        }
        
        // Test for interection with outer bounding sphere, and then test each bounding cone.
        // For any cone that the ray passes through, test three points to see if they are
        //      actually inside the stalk.
        
        bool is_shadowed = false;
        
        vec2 t_outer = intersect_sphere_both(vec3(0, shift, 0), radius, V, dest_P_shadow);

        t_outer.x = max(t_outer.x, min_gap);
        
        if (t_outer.x < t_outer.y) {
            vec3 Vrot = mtx * V;
            
            vec2 split = vec2((-0.25 - dest_P_shadow.y)  * 1./V.y, ((pk_index == 2 ? 0.05 : 0.1) - dest_P_shadow.y)  * 1./V.y);
            
            vec2 interval = V.y > 0. ? vec2(t_outer.x, min(t_outer.y, split.x)) : vec2(max(t_outer.x, split.x), t_outer.y);
            
            if (interval.x < interval.y) {
                vec2 C;
                vec3 dir;
                vec2 ab;
                
                if (pk_index == 0) {
                    C = vec2(0.039, -0.0128);
                    dir = vec3(0.10724786, 0.99200483, -0.06651555);
                    ab = vec2(-1.0556, 0.018);
                } else if (pk_index == 1) {
                    C = vec2(0., -0.02406);
                    dir = vec3(-0.043933547, 0.9937135086, -0.1029723564);
                    ab = vec2(-1.205, -0.05);
                } else {
                    C = vec2(0.0356, 0.0336);
                    dir = vec3(0.13460465, 0.9787172159, 0.154900611);
                    ab = vec2(-1.068, -0.053);
                }
            
                vec2 c = cone_intersection(dest_P_shadow - vec3(C.x, 0., C.y), V, dir, ab.x, ab.y);
                
                vec2 interval2 = vec2(max(interval.x, c.x), min(interval.y, c.y));
                
                if (interval2.x < interval2.y) {
                    is_shadowed = stalk_val_and_deriv_fn(Prot + 0.5*(interval2.x + interval2.y)*Vrot, pk_index).w < 0.;
                    
                    if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.25)*Vrot, pk_index).w < 0.;
                    if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.75)*Vrot, pk_index).w < 0.;
                }
            }
            
            if ( ! is_shadowed) {
                vec2 interval2 = vec2(max(t_outer.x, V.y > 0. ? split.x : split.y), min(t_outer.y, V.y > 0. ? split.y : split.x));
                
                if (interval2.x < interval2.y) {
                    vec2 C;
                    vec3 dir;
                    vec2 ab;
                    
                    if (pk_index == 0) {
                        C = vec2(0);
                        dir = vec3(0.06394869, 0.99519016, -0.07420986);
                        ab = vec2(-0.0967, 0.27);
                    } else if (pk_index == 1) {
                        C = vec2(0);
                        dir = vec3(-0.0239166536, 0.992620526, -0.11888013);
                        ab = vec2(-0.0852, 0.24);
                    } else {
                        C = vec2(0.01467, 0);
                        dir = vec3(0.166831952, 0.9678368388, 0.188305478);
                        ab = vec2(-0.047, 0.235);
                    }
                
                    vec2 c = cone_intersection(dest_P_shadow - vec3(C.x, 0., C.y), V, dir, ab.x, ab.y);
                    
                    interval2.x = max(interval2.x, c.x);
                    interval2.y = min(interval2.y, c.y);
                    
                    if (interval2.x < interval2.y) {
                        is_shadowed = stalk_val_and_deriv_fn(Prot + 0.5*(interval2.x + interval2.y)*Vrot, pk_index).w < 0.;
                    
                        if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.25)*Vrot, pk_index).w < 0.;
                        if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.75)*Vrot, pk_index).w < 0.;
                    }
                }
            }
            
            bool split_dir = V.y > 0.;
            
            if ( ! is_shadowed && pk_index == 2) {
                bool split3_side;
                float split3;
                
                {
                    float k = dot(V.xy, normalize(vec2(1,1.5)));
                
                    split3 = (0.3 - dot(dest_P_shadow.xy, normalize(vec2(1,1.5)))) / k;
                    split3_side = k > 0.;
                }

                {
                    vec2 interval2 = t_outer;
                    
                    if (V.y < 0.) interval2.y = min(split.y, interval2.y);
                    else interval2.x = max(split.y, interval2.x);
                    
                    if (split3_side) interval2.y = min(split3, interval2.y);
                    else interval2.x = max(split3, interval2.x);
                    
                    if (interval2.x < interval2.y) {
                        vec2 c = cone_intersection(dest_P_shadow - vec3(-0.0148, 0, 0), V, vec3(0.5512425069, 0.8208679389, 0.14935704035), 0., 0.195);
                        
                        interval2.x = max(interval2.x, c.x);
                        interval2.y = min(interval2.y, c.y);
                    
                        if (interval2.x < interval2.y) {
                            is_shadowed = stalk_val_and_deriv_fn(Prot + 0.5*(interval2.x + interval2.y)*Vrot, pk_index).w < 0.;
                    
                            if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.25)*Vrot, pk_index).w < 0.;
                            if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.75)*Vrot, pk_index).w < 0.;
                        }
                    }
                }
                
                split.y = split3;
                split_dir = split3_side;
            }
            
            if ( ! is_shadowed) {
                vec2 interval2 =split_dir ? vec2(max(t_outer.x, split.y), t_outer.y) : vec2(t_outer.x, min(t_outer.y, split.y));

                if (interval2.x < interval2.y) {
                    vec2 C;
                    vec3 dir;
                    vec2 ab;
                    
                    if (pk_index == 0) {
                        C = vec2(0.03, 0);
                        dir = vec3(-0.2251491, 0.97432137, 0.002398482);
                        ab = vec2(0., 0.27);
                    } else if (pk_index == 1) {
                        C = vec2(-0.02458, 0);
                        dir = vec3(0.19769171, 0.9717108475, -0.12921307);
                        ab = vec2(0, 0.218);
                    } else {
                        C = vec2(-0.274, -0.011);
                        dir = vec3(0.86995770021, 0.479405447566, 0.115516304861);
                        ab = vec2(0., 0.1875);
                    }
                    
                    vec2 c = cone_intersection(dest_P_shadow - vec3(C.x, 0., C.y), V, dir, ab.x, ab.y);
                    
                    interval2.x = max(interval2.x, c.x);
                    interval2.y = min(interval2.y, c.y);
                    
                    if (interval2.x < interval2.y) {
                        is_shadowed = stalk_val_and_deriv_fn(Prot + 0.5*(interval2.x + interval2.y)*Vrot, pk_index).w < 0.;
                        if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.25)*Vrot, pk_index).w < 0.;
                        if ( ! is_shadowed) is_shadowed = stalk_val_and_deriv_fn(Prot + mix(interval2.x, interval2.y, 0.75)*Vrot, pk_index).w < 0.;
                    }
                }
            }
        }
        
        // Get sum of unshadowed irradiance values
        
        if ( ! is_shadowed) {
            bool h = (i & axis_mask) >= (samples_per_axis >> 1);
            
            if (i < ((samples_per_axis*samples_per_axis) >> 1)) {
                if (h) unshadowed_q.y += amount;
                else unshadowed_q.x += amount;
            } else {
                if (h) unshadowed_q.w += amount;
                else unshadowed_q.z += amount;
            }
        }
    }
    
    // Compute unshadowed fraction
    
    return unshadowed_q / (total_q + 1e-10);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Quickly skip unused portion of the buffer
    if (fragCoord.y >= 160. || fragCoord.x >= 320.) {
        fragColor = vec4(0);
        return;
    }
    
    if (iFrame != 0) {
        fragColor = texelFetch(iChannel1, ivec2(fragCoord),0);
        return;
    }
    
    // First figure out which data we're generating, based on fragCoord,
    //      and get the fractional coordinates within the mesh.
    // Each mesh is identified by a different integer index (surface_index)
    // For some meshes we need to further transform (warp) the coordinates.
    
    ivec2 icoord = ivec2(fragCoord);
    
    int surface_index = -1;
    bool is_highres = false;
    int use_dim = 0;
    
    if (icoord.y >= HIGH_RES_Y_OFFSET + HIGH_RES_DIM_WALL && icoord.y < HIGH_RES_Y_OFFSET + 2*HIGH_RES_DIM_WALL
            && icoord.x >= HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL && icoord.x < HIGH_RES_DIM_FLOOR + 2*HIGH_RES_DIM_WALL) {
        icoord -= ivec2(HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL, HIGH_RES_Y_OFFSET + HIGH_RES_DIM_WALL);
        
        if (icoord.x < 40 && icoord.y < 3*16) {
            surface_index = INDEX_STALK1 + (icoord.y >> 4);
            icoord.y &= 16 - 1;
        }
    } else if (icoord.y >= HIGH_RES_Y_OFFSET+HIGH_RES_DIM_FLOOR-32 && icoord.y < HIGH_RES_Y_OFFSET+HIGH_RES_DIM_FLOOR
                && icoord.x < TOP_SHADOW_MAP_DIM) {
        surface_index = INDEX_PUMPKIN3_UV;
        icoord.y -= HIGH_RES_Y_OFFSET+HIGH_RES_DIM_FLOOR-32;
    } else if (icoord.y < 32 && icoord.x >= 11*MESH_DIM && icoord.x < 11*MESH_DIM + 2*TOP_SHADOW_MAP_DIM) {
        if (icoord.x < 11*MESH_DIM + TOP_SHADOW_MAP_DIM) {
            surface_index = INDEX_PUMPKIN1_UV;
            icoord.x -= 11*MESH_DIM;
        } else {
            surface_index = INDEX_PUMPKIN2_UV;
            icoord.x -= 11*MESH_DIM + TOP_SHADOW_MAP_DIM;
        }
    } else if (icoord.y >= HIGH_RES_Y_OFFSET) {
        icoord.y -= HIGH_RES_Y_OFFSET;
        is_highres = true;
        int can_inc = 0;
        
        if (icoord.x < HIGH_RES_DIM_FLOOR) {
            if (icoord.y >= HIGH_RES_DIM_FLOOR-48 && icoord.x < 48) {
                surface_index = -1;
            } else {
                use_dim = HIGH_RES_DIM_FLOOR;
                surface_index = INDEX_FLOOR;
            }
        } else if (icoord.x < HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL) {
            icoord.x -= HIGH_RES_DIM_FLOOR;
            use_dim = HIGH_RES_DIM_WALL;
            surface_index = INDEX_LEFT_WALL;
            can_inc = 1;
        } else if (icoord.x < HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL + HIGH_RES_DIM_BACK_WALL) {
            icoord.x -= HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL;
            use_dim = HIGH_RES_DIM_BACK_WALL;
            surface_index = INDEX_BACK_WALL;
        } else if (icoord.x < HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL + HIGH_RES_DIM_BACK_WALL + HIGH_RES_DIM_BLOCK_TOP) {
            icoord.x -= HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL + HIGH_RES_DIM_BACK_WALL;
            use_dim = HIGH_RES_DIM_BLOCK_TOP;
            surface_index = INDEX_LBLOCK_TOP;
            can_inc = 1;
        }
        
        if (can_inc > 0 && icoord.y >= use_dim) {
            surface_index++;
            icoord.y -= use_dim;
            
            if (can_inc > 1 && icoord.y >= use_dim) {
                surface_index++;
                icoord.y -= use_dim;
            }
        }
        
        if (icoord.y >= use_dim) surface_index = -1;
    } else {
        surface_index = map_icoord_to_surface_index(icoord);
    }
    
    if (surface_index == -1 || surface_index == INDEX_CEILING || surface_index == INDEX_LBLOCK_LEFT || surface_index == INDEX_RBLOCK_RIGHT
                || surface_index == INDEX_RBLOCK_FRONT || surface_index == INDEX_LBLOCK_BACK || surface_index == INDEX_RBLOCK_BACK) {
        fragColor = vec4(0);
        return;
    }
    
    // Shadow data for the top of the pumpkins and the stalks is a special case, handled separately.
    //      (pumpkins also have low-res direct irradiance data, which is handled later)
    if ((surface_index >= INDEX_PUMPKIN1_UV && surface_index <= INDEX_PUMPKIN3_UV) || (surface_index >= INDEX_STALK1 && surface_index <= INDEX_STALK3)) {
        vec3 dest_P, dest_N;
        int pk_index;
        float min_gap;
        
        if (surface_index >= INDEX_PUMPKIN1_UV && surface_index <= INDEX_PUMPKIN3_UV) {
            pk_index = surface_index - INDEX_PUMPKIN1_UV;
        
            vec3 offset;
            float scale;
            vec4 shadow_rect;
            vec3 bound_center;
            float r_guess;

            if (pk_index==0) {
                offset = PUMPKIN1_OFFSET;
                scale = PUMPKIN1_SCALE;
                shadow_rect = vec4(0.24,0.32, 0.235,0.3);
                bound_center = vec3(-0.590122, -8.2405638, -0.33518434);
                r_guess = 8.665;
            } else if (pk_index==1) {
                offset = PUMPKIN2_OFFSET;
                scale = PUMPKIN2_SCALE;
                shadow_rect = vec4(0.615, 0.75, 0.24, 0.365);
                bound_center = vec3(-0.01911406, -0.0471726, 0.029867);
                r_guess = 0.545;
            } else {
                offset = PUMPKIN3_OFFSET;
                scale = PUMPKIN3_SCALE;
                shadow_rect = vec4(0.76,0.865,0.503,0.588);
                bound_center = vec3(0.1314638, 0.088935, 0.001076);
                r_guess = 0.45;
            }
            
            dest_P.x = mix(shadow_rect.x, shadow_rect.y, 1. / float(TOP_SHADOW_MAP_DIM+1) * float(icoord.x + 1));
            dest_P.z = mix(shadow_rect.z, shadow_rect.w, 1. / float(TOP_SHADOW_MAP_DIM+1) * float(icoord.y + 1));
            
            if (pk_index==1) { // The texture map for the second pumpkin is rotated
                float a = 0.25*PI;
                dest_P.xz = dest_P.xz * mat2(cos(a), -sin(a), sin(a), cos(a));
            }
            
            dest_P.xz -= offset.xz;
            dest_P.xz *= 1./scale;
            dest_P.y = 0.;
            
            // get point and normal on simplified (without ripples) surface
            {
                vec2 d_xz = dest_P.xz - bound_center.xz;
                
                float y_guess = bound_center.y + sqrt(r_guess*r_guess - dot(d_xz, d_xz));
                
                vec4 d = distance_to_pumpkin_shape2(dest_P, vec3(0,1,0), y_guess, pk_index);
                
                dest_P.y = d.w;
                dest_N = d.xyz;
            }
            
            dest_P *= scale;
            dest_P += offset;
            
            if (is_inside_stalk(dest_P, pk_index)) {
                fragColor = vec4(0);
                return;
            }
            
            min_gap = 0.;
        } else {
            pk_index = surface_index - INDEX_STALK1;
        
            float y;
            
            {
                vec4 data0 = texelFetch(iChannel0, ivec2((icoord.x & 7) + pk_index*8, (icoord.x >> 3) + (2*SPHERE_UV_DIM)), 0);
                
                y = mix(data0.x, data0.y, 1./15. * float(icoord.y));
            }
            
            float phi = (2.*PI / 40.) * float(icoord.x);
            
            float x = cos(phi);
            float z = sin(phi);
            
            vec3 offset;
            float scale, warp, modscale, radius2, shift;
            mat3 mtx;

            if (pk_index == 0) {
                offset = STALK1_OFFSET;
                scale = STALK1_SCALE;
                mtx = STALK1_RMTX;
                warp = STALK1_WARP;
                modscale = STALK1_MODSCALE;
                radius2 = STALK1_BOUND_RADIUS*STALK1_BOUND_RADIUS;
                shift = STALK1_BOUND_Y;
            } else if (pk_index == 1) {
                offset = STALK2_OFFSET;
                scale = STALK2_SCALE;
                mtx = STALK2_RMTX;
                warp = STALK2_WARP;
                modscale = STALK2_MODSCALE;
                radius2 = STALK2_BOUND_RADIUS*STALK2_BOUND_RADIUS;
                shift = STALK2_BOUND_Y;
            } else {
                offset = STALK3_OFFSET;
                scale = STALK3_SCALE;
                mtx = STALK3_RMTX;
                warp = STALK3_WARP;
                modscale = STALK3_MODSCALE;
                radius2 = STALK3_BOUND_RADIUS*STALK3_BOUND_RADIUS;
                shift = STALK3_BOUND_Y;
            }
            
            float phiN = STALK_FREQ1 * phi;
            float m = sin(phiN) + 1.001;
            float s = sqrt(m);

            float dist_base = modscale * s - STALK_BIAS;

            float q = y + 1.;
            float r = exp(-STALK_FLARE_FACTOR * q*q*q);

            float dist = dist_base + r;
            
            dest_P = vec3(x*dist, y, z*dist);
            
            dest_P = scale * (dest_P - vec3(warp * y*y, 0, 0)) * mtx + offset;
            
            {
                float scaled_cos_phi = STALK_FREQ1 * modscale * 0.5 / (dist*dist * s) * cos(phiN);
                
                vec3 Df = vec3(x, 0, z) + vec3(
                        dist * z * scaled_cos_phi,
                        STALK_FLARE_POW*STALK_FLARE_FACTOR*q*q * r,
                        -dist * x * scaled_cos_phi
                    );
                
                dest_N = normalize(vec3(Df.x, 2.*warp*y*Df.x + Df.y, Df.z) * mtx);
            }
            
            min_gap = 0.01;
        }
        
        fragColor = test_stalk_shadow(dest_P, dest_N, pk_index, min_gap);
        
        return;
    }
    
    vec2 coord;
    
    if ( ! is_highres) {
        icoord &= (MESH_DIM-1);
        
        if (surface_index >= INDEX_PUMPKIN1 && surface_index <= INDEX_PUMPKIN3) {
            coord = 1./float(MESH_DIM) * (vec2(icoord) + 0.5);
        } else {
            coord = map_coords_to_linear_lowres(surface_index, 1./float(MESH_DIM) * vec2(icoord));
        }
    } else {
        coord = 1./float(use_dim-1) * vec2(icoord);
    }
    
    vec3 dest_P;
    vec3 dest_N;
    bool is_pumpkin = false;
    
    if (surface_index >= INDEX_PUMPKIN1 && surface_index <= INDEX_PUMPKIN3) {
        ivec2 base = CHOOSE3(surface_index==INDEX_PUMPKIN1, surface_index==INDEX_PUMPKIN2, 
                             ivec2(32, 2*SPHERE_UV_DIM), ivec2(32 + MESH_DIM, 2*SPHERE_UV_DIM), ivec2(32 + 2*MESH_DIM, 2*SPHERE_UV_DIM));
        
        vec4 data = texelFetch(iChannel0, base + icoord, 0);
        
        dest_N = normalize(data.xyz);
        
        {
            coord.y = pumpkin_map_01_to_squished(coord.y);
        
            float phi = 2.*PI * (coord.x - 0.5);
            float theta = PI*(coord.y - 0.5);
            float cos_theta = cos(theta);
            
            dest_P = data.w * vec3(cos(phi)*cos_theta, sin(theta), sin(phi)*cos_theta);
        }
        
        vec3 offset;
        
        if (surface_index == INDEX_PUMPKIN1) {
            offset = PUMPKIN1_OFFSET;
        } else if (surface_index == INDEX_PUMPKIN2) {
            offset = PUMPKIN2_OFFSET;
        } else {
            offset = PUMPKIN3_OFFSET;
        }
        
        dest_P += offset;
        is_pumpkin = true;
    
    } else {
        // Most of the surfaces are handled here
        
        map_coord_to_P_and_N(surface_index, coord, dest_P, dest_N);

        if (dest_P.y > 0.999) {
            fragColor = vec4(0);
            return;
        }
        
        is_pumpkin = false;
    }
    
    // Many (most?) points are completely shadowed or completely unshadowed.
    // We want to identify those points so we can avoid expensive sampling of the area light.
    
    bool need_sample = false;
    
    // Test for possible shadowing by boxes
    if ( ! is_pumpkin && (surface_index < INDEX_LBLOCK_TOP || surface_index > INDEX_RBLOCK_BACK)) {
        int occl_box1 = (surface_index == INDEX_RIGHT_WALL) ? 0 : test_box_occlusion(dest_P, false);
        int occl_box2 = (surface_index == INDEX_LEFT_WALL || surface_index == INDEX_BACK_WALL) ? 0 : test_box_occlusion(dest_P, true);
        
        if (occl_box1 == 2 || occl_box2 == 2) {
            fragColor = vec4(0);
            return;
        } else if (occl_box1 == 1 || occl_box2 == 1) {
            need_sample = true;
        }
    }
    
    // Test for possible shadowing by pumpkins
    if ( ! is_pumpkin) {
        bool is_box = surface_index >= INDEX_LBLOCK_TOP && surface_index <= INDEX_RBLOCK_BACK;
        bool is_box2 = is_box && (surface_index & 1) != 0;
        
        int occl_sphere1 = (is_box || (surface_index>=INDEX_LEFT_WALL && surface_index<=INDEX_BACK_WALL)) ? 0 
            : sphere_occl_test(dest_P, PUMPKIN1_OFFSET, 1.0*0.48*PUMPKIN1_SCALE, 1.15*0.48*PUMPKIN1_SCALE);
        int occl_sphere2 = (is_box2 || surface_index == INDEX_RIGHT_WALL || surface_index == INDEX_LBLOCK_FRONT || surface_index == INDEX_LBLOCK_RIGHT) ? 0 
            : sphere_occl_test(dest_P, PUMPKIN2_OFFSET, 1.0*0.48*PUMPKIN2_SCALE, 1.1*0.48*PUMPKIN2_SCALE);
        int occl_sphere3 = ((is_box && !is_box2) || surface_index == INDEX_LEFT_WALL || surface_index == INDEX_BACK_WALL || surface_index == INDEX_RBLOCK_LEFT) ? 0 
            : sphere_occl_test(dest_P, PUMPKIN3_OFFSET, 1.1*0.48*PUMPKIN3_SCALE, 1.3*0.48*PUMPKIN3_SCALE);
        
        if (occl_sphere1 == 2 || occl_sphere2 == 2 || occl_sphere3 == 2) {
            fragColor = vec4(0);
            return;
        } else if (occl_sphere1 == 1 || occl_sphere2 == 1 || occl_sphere3 == 1) {
            need_sample = true;
        }
    }
    
    vec4 final_color = vec4(0);

    if ( ! need_sample) {
        if (is_highres) {
            final_color = vec4(1);
        } else {
            // For unshadowed points we can use simpler area light integration if we know that the light is entirely above the horizon.
            // (it might not be worth using a special case for this though - might just increase compile time)
        
            float value;
            
            if ( ! is_pumpkin && surface_index != INDEX_LBLOCK_FRONT && surface_index != INDEX_LBLOCK_RIGHT && surface_index != INDEX_RBLOCK_LEFT) {
                value = eval_area_light(dest_P, dest_N);
            } else {
                value = eval_area_light_clipped(dest_P, dest_N);
            }
            
            final_color = vec4(value, value, 1, 0);
        }
    } else {
        // Need to sample the area light and check shadowing for each sample
    
        int axis_shift = (surface_index == INDEX_FLOOR || surface_index == INDEX_LBLOCK_TOP || surface_index == INDEX_RBLOCK_TOP) ? 4 : 3;
    
        int samples_per_axis = 1 << axis_shift;
        float axis_inc = 1./float(samples_per_axis);
        
        int axis_mask = samples_per_axis - 1;
        
        vec4 total_q = vec4(0);
        vec4 unshadowed_q = vec4(0);

        bool is_box = surface_index >= INDEX_LBLOCK_TOP && surface_index <= INDEX_RBLOCK_BACK;
        bool is_box2 = is_box && (surface_index & 1) != 0;
        bool is_box1 = is_box && ! is_box2;
        
        for (int i=min(0, int(iTime)); i < samples_per_axis*samples_per_axis; i++) {
            vec3 source_P = vec3(0.4 + 0.2*axis_inc*(float(i & axis_mask)+0.5), 1., 0.4 + 0.2*axis_inc*(float(i >> axis_shift)+0.5));
            
            vec3 V = source_P - dest_P;
            
            float t_inter = length(V);
            
            V /= t_inter;
            
            // Compute irradiance for the sample without considering shadowing
            
            float amount = max(0., dot(dest_N, V)*dot(vec3(0,1,0), V) / (t_inter*t_inter));
            
            // Sum these values to get maximum possible irradiance for each quadrant
            
            {
                bool h = (i & axis_mask) >= (samples_per_axis >> 1);
                    
                if ((i >> axis_shift) < (samples_per_axis >> 1)) {
                    if (h) total_q.y += amount;
                    else total_q.x += amount;
                } else {
                    if (h) total_q.w += amount;
                    else total_q.z += amount;
                }
            }
            
            {
                // Check for shadowing by boxes
                bool is_shadowed = box_shadow_test(dest_P, V, t_inter, is_box1, is_box2);
                
                // Check for shadowing by pumpkins
                // We use a cheap test here (no ray marching!)
                // Find closest point along the ray to the sphere center and then check the function.
                
                if ( ! is_shadowed) {
                    int pk_index = 0;
                    mat3 mtx = RMTX_PK1;
                    vec3 offset = PUMPKIN1_OFFSET;
                    float scale = PUMPKIN1_SCALE;
                
                    vec3 use_V = mtx * V;
                    vec3 use_O = mtx * (1./scale * (dest_P - offset));
                    
                    float t = -dot(use_O, use_V);
                    
                    vec3 P = use_O + t * use_V;
                    
                    if (pumpkin_val_fn(P, false, pk_index) < 0.) {
                        is_shadowed = true;
                    }
                }
                
                if ( ! is_shadowed) {
                    int pk_index = 1;
                    mat3 mtx = RMTX_PK2;
                    vec3 offset = PUMPKIN2_OFFSET;
                    float scale = PUMPKIN2_SCALE;
                
                    vec3 use_V = mtx * V;
                    vec3 use_O = mtx * (1./scale * (dest_P - offset));
                    
                    float t = -dot(use_O, use_V);
                    
                    vec3 P = use_O + t * use_V;
                    
                    if (pumpkin_val_fn(P, false, pk_index) < 0.) {
                        is_shadowed = true;
                    }
                }
                
                if ( ! is_shadowed) {
                    int pk_index = 2;
                    mat3 mtx = RMTX_PK3;
                    vec3 offset = PUMPKIN3_OFFSET;
                    float scale = PUMPKIN3_SCALE;
                
                    vec3 use_V = mtx * V;
                    vec3 use_O = mtx * (1./scale * (dest_P - offset));
                    
                    float t = -dot(use_O, use_V);
                    
                    vec3 P = use_O + t * use_V;
                    
                    if (pumpkin_val_fn(P, false, pk_index) < 0.) {
                        is_shadowed = true;
                    }
                }
                
                // We don't check for shadowing by stalks because it's expensive, and almost unnoticeable

                if ( ! is_shadowed) {

                    // sum values to get unshadowed irradiance for each quadrant
                
                    bool h = (i & axis_mask) >= (samples_per_axis >> 1);
                        
                    if ((i >> axis_shift) < (samples_per_axis >> 1)) {
                        if (h) unshadowed_q.y += amount;
                        else unshadowed_q.x += amount;
                    } else {
                        if (h) unshadowed_q.w += amount;
                        else unshadowed_q.z += amount;
                    }
                }
            }
        }
        
        if (is_highres) {
            // For high res data, we want the unshadowed fraction for each quadrant
            
            final_color = unshadowed_q / (total_q + 1e-10);
        } else {
            // For low res data (used by the radiosity passes) we just want the total irradiance
            // But the final render may need to use this data (if high res data is unavailable) so we also store the unshadowed fraction.
            
            float unshadowed = dot(unshadowed_q, vec4(1));
            final_color = vec4(1./PI * axis_inc * axis_inc * unshadowed, 0, unshadowed / (dot(total_q, vec4(1)) + 1e-10), 0);
        }
    }
    
    fragColor = final_color;
}

