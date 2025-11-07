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
    
    Buffer C contains irradiance data for indirect illumination from the main 
    area light (not candles). The data is split into multiple meshes, most of 
    them square (e.g. 16x16 for low resolution data). For most surfaces, the 
    output is just a single RGB value. For pumpkins, three values are computed, 
    for three different directions (stored in different sections of the texture).

    Buffer C uses direct light irradiance data from Buffer B, and indirect 
    irradiance data from the previous frame's Buffer C. It is only updated during 
    the first 12 frames (after that it has negligible effect).

    Buffer C is the slowest pass (it's really quite bad). Part of the problem is 
    that it doesn't have enough invocations for GPU parallelism to really work 
    (only a small section of the buffer is used) and some pixels require a huge 
    amount of work (thousands of iterations of the loop) so there's likely a long 
    tail for the execution in which the GPU is barely utilized. Solving this 
    would probably require breaking up the work further (not trying to do a 
    complete Jacobi iteration in each frame) which would add a lot of complexity.

    The strategy used for the shader is to have a single loop that integrates 
    bounced light for an arbitrary number of surfaces, each of which can 
    contribute bounced direct or indirect light. It first computes a bitmask 
    indicating which surfaces are applicable, so it can keep choosing the next 
    surface by finding the next set bit. The main reasons for using a single loop 
    are to reduce compilation time (in Windows especially) and to avoid crashes 
    that I have seen on an Nvidia GPU when there are nested variable-length loops.

    Somewhat counterintuitively, Buffer C needs to use more accurate tests for 
    intersection with the pumpkins than were used in Buffer B (for shadows), in 
    order for the occlusion near the bottom of the pumpkins to look acceptable. 
    The indirect light at the top of the pumpkins may have slightly noticeable 
    occlusion by stalks - this is subtle, and could be omitted, but it doesn't 
    seem to have a major impact on performance, despite being complicated to 
    test. Similar to Buffer B, it doesn't ray march the stalks here (that would 
    likely be too expensive) but instead tests intersection with bounding cones 
    and tests at most one point for each cone to see if it's actually inside the 
    shape (I originally used just the cones, without the final test, but this 
    blocked too much light I think).
    
    
    

*/



bool intersects_box(vec3 origin, vec3 V, float dist, mat2 r, vec3 corner1, vec3 corner2) {
    origin.xz = r * origin.xz;
    V.xz = r * V.xz;
    
    int side = 0;
    float t = intersect_box_near(corner1, corner2, 1./V, origin, side);
    
    return t > 0. && t < dist;
}

// For a point on the pumpkin surface, find a nearby point that is definitely outside the stalk
//      so we can use it as the destination point when testing for shadowing by the stalk
vec3 find_P_outside_stalk(vec3 P0, int pk_index, vec3 dir0) {
    vec3 offset;
    float scale, shift, radius;
    mat3 mtx;
    
    if (pk_index==0) {
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
    
    vec3 P = mtx * (1./scale*(P0 - offset));

    // Skip points that are outside the bounding sphere for the stalk.
    
    if (distance(P, vec3(0,shift,0)) > radius) return P0;
    
    if (stalk_val_and_deriv_fn(P, pk_index).w > 0.) return P0;
    
    vec3 dir = mtx * dir0;
    
    float t_inside = 0., t_outside = 0.4;
    
    for (int i = 0; i < 4; i++) {
        float t = 0.5*(t_inside + t_outside);
        
        vec3 P2 = P + 0.4 * dir;
    
        if (stalk_val_and_deriv_fn(P2, pk_index).w < 0.) {
            t_inside = t;
        } else {
            t_outside = t;
        }
    }
    
    return P0 + scale*t_outside * dir0;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Quickly skip unused portion of the buffer
    if (fragCoord.y >= 160. || fragCoord.x >= 320.) {
        fragColor = vec4(0);
        return;
    }
    
    // The radiosity takes up to 30 frames to converge, but the difference is not noticeable after the first 12 frames
    if (iFrame >= 12) {
        fragColor = texelFetch(iChannel2, ivec2(fragCoord), 0);
        return;
    }
    
    // Get the index of the mesh we're generating data for, and the fractional coordinates within the mesh
    
    ivec2 icoord = ivec2(fragCoord);
    
    int dest_surface_index = -1;

    if (icoord.y >= 2*MESH_DIM && icoord.y < 2*MESH_DIM + 2*SPHERE_UV_DIM && icoord.x < 5*SPHERE_UV_DIM) {
        dest_surface_index = INDEX_PUMPKIN1_UV + (icoord.x >> SPHERE_UV_DIM_SHIFT);
        dest_surface_index += 5*((icoord.y - 2*MESH_DIM) >> SPHERE_UV_DIM_SHIFT);
        icoord.y -= 2*MESH_DIM;
        icoord &= SPHERE_UV_DIM - 1;
        
        if (dest_surface_index == INDEX_PUMPKIN1_UV + 9) {
            dest_surface_index = INDEX_PUMPKIN1_UV + 8;
        } else if (dest_surface_index == INDEX_PUMPKIN1_UV + 8) {
            if (icoord.y >= 3*16 || icoord.x >= 40) return;
            dest_surface_index = INDEX_STALK1 + (icoord.y >> 4);
            icoord.y &= 16 - 1;
        }
    } else {
        dest_surface_index = map_icoord_to_surface_index(icoord);
        
        if (dest_surface_index == INDEX_FLOOR) {
            dest_surface_index = -1;
        } else {
            icoord &= (MESH_DIM-1);
        }
    }
    
    if (dest_surface_index == -1) {
        fragColor = vec4(0);
        return;
    }
    
    // Get relevant data about the point on the surface that we're computing indirect irradiance for.
    
    vec3 dest_P; // Location in world space
    vec3 dest_N; // surface normal
    
    // I don't know if this is really necessary or a good idea, but I'm using separate normals for shadowing
    //      and irradiance computation for the directional irradiance on the pumpkins
    vec3 dest_N2 = vec3(0); 
    bool have_N2 = false;
    
    bool dest_is_pumpkin = false;
    bool is_first_bounce = iFrame == 0;
    
    if (dest_surface_index >= INDEX_PUMPKIN1 && dest_surface_index <= INDEX_PUMPKIN3) {
        // Low resolution data for pumpkins

        ivec2 base = CHOOSE3(dest_surface_index==INDEX_PUMPKIN1, dest_surface_index==INDEX_PUMPKIN2, 
                             ivec2(32, 2*SPHERE_UV_DIM), ivec2(32 + MESH_DIM, 2*SPHERE_UV_DIM), ivec2(32 + 2*MESH_DIM, 2*SPHERE_UV_DIM));
        vec4 data = texelFetch(iChannel0, base + icoord, 0);
        
        dest_N = normalize(data.xyz);
        
        {
            vec2 coord = 1. / float(MESH_DIM) * (vec2(icoord) + 0.5);
            
            coord.y = pumpkin_map_01_to_squished(coord.y);
        
            float phi = 2.*PI * (coord.x - 0.5);
            float theta = PI*(coord.y - 0.5);
            float cos_theta = cos(theta);
            
            dest_P = data.w * vec3(cos(phi)*cos_theta, sin(theta), sin(phi)*cos_theta);
        }
        
        vec3 offset;
        
        if (dest_surface_index == INDEX_PUMPKIN1) {
            offset = PUMPKIN1_OFFSET;
        } else if (dest_surface_index == INDEX_PUMPKIN2) {
            offset = PUMPKIN2_OFFSET;
        } else {
            offset = PUMPKIN3_OFFSET;
        }
        
        dest_P += offset;
        dest_is_pumpkin = true;
    } else if (dest_surface_index >= INDEX_PUMPKIN1_UV && dest_surface_index <= INDEX_PUMPKIN3_UV_RIGHT) {
        // High resolution data for pumpkins
        // This has three separate meshes for each pumpkin (for three different surface normals)
        
        int set_index = 0;
        
        if (dest_surface_index >= INDEX_PUMPKIN1_UV_RIGHT) {
            set_index = 2;
            dest_surface_index -= 6;
        } else if (dest_surface_index >= INDEX_PUMPKIN1_UV_LEFT) {
            set_index = 1;
            dest_surface_index -= 3;
        }
        
        float d;
        
        {
            ivec2 base = CHOOSE3(dest_surface_index==INDEX_PUMPKIN1_UV, dest_surface_index==INDEX_PUMPKIN2_UV, 
                                 ivec2(0, SPHERE_UV_DIM), ivec2(SPHERE_UV_DIM, SPHERE_UV_DIM), ivec2(SPHERE_UV_DIM, 0));
                                 
            vec4 data = texelFetch(iChannel0, base + (icoord & (SPHERE_UV_DIM-1)), 0);
            
            dest_N = data.xyz;
            d = data.w;
        }
    
        vec2 coord = 1./float(SPHERE_UV_DIM) * (vec2(icoord & (SPHERE_UV_DIM-1)) + 0.5);
        
        coord.y = pumpkin_map_01_to_squished(coord.y);
        
        vec3 offset;
        
        if (dest_surface_index == INDEX_PUMPKIN1_UV) {
            offset = PUMPKIN1_OFFSET;
        } else if (dest_surface_index == INDEX_PUMPKIN2_UV) {
            offset = PUMPKIN2_OFFSET;
        } else {
            offset = PUMPKIN3_OFFSET;
        }
        
        vec3 V;

        {
            float theta = PI*(coord.y - 0.5);
            float y = sin(theta);
            
            float cos_theta = cos(theta);
            
            float phi = 2.*PI * (coord.x - 0.5);

            V = vec3(cos(phi)*cos_theta, y, sin(phi)*cos_theta);
            
            if (set_index != 0) {
                vec3 B = vec3(sin(phi), 0., -cos(phi));
                
                B = normalize(B - dot(B, dest_N)*dest_N);

                dest_N2 = dest_N;
                dest_N = (set_index == 1 ? -0.5956993 : 0.5956993)*B + 0.8032075*dest_N;
                
                have_N2 = true;
            }
        }
        
        dest_P = d*V + offset;
        dest_is_pumpkin = true;
        
        dest_P = find_P_outside_stalk(dest_P, dest_surface_index - INDEX_PUMPKIN1_UV, normalize(vec3(V.x, 0., V.z)));
    } else if (dest_surface_index >= INDEX_STALK1 && dest_surface_index <= INDEX_STALK3) {
        // Stalk end cap is handled specially (as a single mesh point)
        
        bool is_endcap = icoord.y==15 && icoord.x == 2 + 8;
        
        int pk_index = dest_surface_index - INDEX_STALK1;
        
        // Each longitude coordinate on the stalk's uv cylinder mesh has a different range of y values.
        // Look that up in the Buffer A data first (using linear interpolation)

        float y;
        
        {
            vec4 data0 = texelFetch(iChannel0, ivec2((icoord.x & 7) + pk_index*8, (icoord.x >> 3) + 2*SPHERE_UV_DIM), 0);
            
            y = mix(data0.x, data0.y, 1./15. * float(icoord.y));
        }
        
        float phi = (2.*PI / 40.) * float(icoord.x);
        
        float x = cos(phi);
        float z = sin(phi);
        
        vec3 offset;
        float scale, warp, modscale, radius, shift;
        mat3 mtx;

        if (pk_index == 0) {
            offset = STALK1_OFFSET;
            scale = STALK1_SCALE;
            mtx = STALK1_RMTX;
            warp = STALK1_WARP;
            modscale = STALK1_MODSCALE;
            radius = STALK1_BOUND_RADIUS;
            shift = STALK1_BOUND_Y;
        } else if (pk_index == 1) {
            offset = STALK2_OFFSET;
            scale = STALK2_SCALE;
            mtx = STALK2_RMTX;
            warp = STALK2_WARP;
            modscale = STALK2_MODSCALE;
            radius = STALK2_BOUND_RADIUS;
            shift = STALK2_BOUND_Y;
        } else {
            offset = STALK3_OFFSET;
            scale = STALK3_SCALE;
            mtx = STALK3_RMTX;
            warp = STALK3_WARP;
            modscale = STALK3_MODSCALE;
            radius = STALK3_BOUND_RADIUS;
            shift = STALK3_BOUND_Y;
        }
        
        {
            float phiN = STALK_FREQ1 * phi;
            float m = sin(phiN) + 1.001;
            float s = sqrt(m);

            float dist_base = modscale * s - STALK_BIAS;

            float q = y + 1.;
            float r = exp(-STALK_FLARE_FACTOR * q*q*q);

            float dist = is_endcap ? 0. : dist_base + r;
            
            dest_P = vec3(x*dist - warp * y*y, y, z*dist) * mtx;
            
            if ( ! is_endcap) {
                float scaled_cos_phi = STALK_FREQ1 * modscale * 0.5 / (dist*dist * s) * cos(phiN);
                
                vec3 Df = vec3(x, 0, z) + vec3(
                        dist * z * scaled_cos_phi,
                        STALK_FLARE_POW*STALK_FLARE_FACTOR*q*q * r,
                        -dist * x * scaled_cos_phi
                    );
                
                dest_N = normalize(vec3(Df.x, 2.*warp*y*Df.x + Df.y, Df.z) * mtx);
            } else {
                dest_N = normalize(dest_P - vec3(0,shift,0));
                
                dest_P = vec3(0,shift,0) + radius*dest_N;
            }
        }
            
        dest_P = scale * dest_P + offset;
    } else {
        vec2 coord = map_coords_to_linear_lowres(dest_surface_index, 1./float(MESH_DIM) * vec2(icoord));
    
        map_coord_to_P_and_N(dest_surface_index, coord, dest_P, dest_N);
        
        dest_is_pumpkin = dest_surface_index >= INDEX_PUMPKIN1 && dest_surface_index <= INDEX_PUMPKIN3;
    }

    // First compute a bitmask indicating which surfaces can be sources of radiosity for this destination point
    
    int surface_mask;

    switch(dest_surface_index) {
        case INDEX_FLOOR:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_LEFT | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_LBLOCK_RIGHT | M_RBLOCK_RIGHT | M_LBLOCK_BACK | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_LEFT_WALL:
            surface_mask = M_FLOOR_HIGHRES | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_TOP | M_RBLOCK_TOP | M_LBLOCK_LEFT | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_LBLOCK_BACK | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_RIGHT_WALL:
            surface_mask = M_FLOOR_HIGHRES | M_LEFT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_TOP | M_RBLOCK_TOP | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_LBLOCK_RIGHT | M_RBLOCK_RIGHT | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_BACK_WALL:
            surface_mask = M_FLOOR_HIGHRES | M_LEFT_WALL | M_RIGHT_WALL | M_CEILING | M_LBLOCK_TOP | M_RBLOCK_TOP | M_RBLOCK_LEFT | M_LBLOCK_RIGHT | M_RBLOCK_RIGHT | M_LBLOCK_BACK | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_CEILING:
            surface_mask = M_FLOOR_HIGHRES | M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_LBLOCK_TOP | M_RBLOCK_TOP | M_LBLOCK_LEFT | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_LBLOCK_RIGHT | M_RBLOCK_RIGHT | M_LBLOCK_BACK | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_LBLOCK_TOP:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_PUMPKIN2;
            break;
        case INDEX_RBLOCK_TOP:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_FRONT | M_LBLOCK_RIGHT | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_LBLOCK_LEFT:
            surface_mask = M_FLOOR00 | M_FLOOR10 | M_LEFT_WALL | M_BACK_WALL | M_CEILING | M_PUMPKIN1;
            break;
        case INDEX_RBLOCK_LEFT:
            surface_mask = M_FLOOR_HIGHRES | M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_FRONT | M_LBLOCK_RIGHT | M_PUMPKIN1 | M_PUMPKIN2;
            break;
        case INDEX_LBLOCK_FRONT:
            surface_mask = M_FLOOR_HIGHRES | M_LEFT_WALL | M_RIGHT_WALL | M_CEILING | M_RBLOCK_TOP | M_RBLOCK_LEFT | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN3;
            break;
        case INDEX_RBLOCK_FRONT:
            surface_mask = M_FLOOR00 | M_FLOOR01 | M_LEFT_WALL | M_RIGHT_WALL | M_CEILING | M_PUMPKIN1;
            break;
        case INDEX_LBLOCK_RIGHT:
            surface_mask = (M_FLOOR_HIGHRES&~M_FLOOR00) | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_RBLOCK_TOP | M_RBLOCK_LEFT | M_RBLOCK_BACK | M_PUMPKIN3;
            break;
        case INDEX_RBLOCK_RIGHT:
            surface_mask = M_FLOOR01 | M_FLOOR11 | M_RIGHT_WALL | M_BACK_WALL | M_CEILING;
            break;
        case INDEX_LBLOCK_BACK:
            surface_mask = M_FLOOR10 | M_FLOOR11 | M_LEFT_WALL | M_BACK_WALL | M_CEILING;
            break;
        case INDEX_RBLOCK_BACK:
            surface_mask = M_FLOOR10 | M_FLOOR11 | M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_RIGHT | M_PUMPKIN2;
            break;
        case INDEX_PUMPKIN1:
        case INDEX_PUMPKIN1_UV:
            surface_mask = M_FLOOR_HIGHRES | M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_LEFT | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_STALK1:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_LEFT | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_PUMPKIN2:
        case INDEX_PUMPKIN2_UV:
            surface_mask = (M_FLOOR_HIGHRES&~M_FLOOR10) | M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_TOP | M_RBLOCK_TOP | M_RBLOCK_LEFT | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN3;
            break;
        case INDEX_STALK2:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_RBLOCK_TOP | M_RBLOCK_LEFT | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_PUMPKIN3:
        case INDEX_PUMPKIN3_UV:
            surface_mask = M_FLOOR_HIGHRES | M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_RBLOCK_TOP | M_LBLOCK_FRONT | M_LBLOCK_RIGHT | M_PUMPKIN1 | M_PUMPKIN2;
            break;
        case INDEX_STALK3:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_FRONT | M_LBLOCK_RIGHT | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_FLOOR00:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_LEFT | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_FLOOR01:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_RBLOCK_FRONT | M_LBLOCK_RIGHT | M_RBLOCK_RIGHT | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;
        case INDEX_FLOOR10:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_LBLOCK_LEFT | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_LBLOCK_RIGHT | M_LBLOCK_BACK | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN3;
            break;
        //case INDEX_FLOOR11:
        default:
            surface_mask = M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING | M_RBLOCK_LEFT | M_LBLOCK_FRONT | M_LBLOCK_RIGHT | M_RBLOCK_RIGHT | M_LBLOCK_BACK | M_RBLOCK_BACK | M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
            break;

    }
    
    // Some surfaces have no direct light, so skip them during the first pass
    
    if (is_first_bounce) {
        surface_mask &= ~(M_CEILING | M_LBLOCK_LEFT | M_RBLOCK_RIGHT | M_RBLOCK_FRONT | M_LBLOCK_BACK | M_RBLOCK_BACK);
    }
    
    int total_iterations = 0;
    
    for (int i=0; i<SURFACE_COUNT; i++) if ((surface_mask&SURF_MASK(i)) != 0) total_iterations += MESH_DIM*MESH_DIM;
    
    int current_surface_index = -1;
    surface_mask <<= 1;
    
    // Start i and j at high values to force beginning a new mesh
    int i = MESH_DIM;
    int j = MESH_DIM;
    
    vec3 source_diffuse_color = vec3(0);
    vec3 source_point_offset = vec3(0);
    vec3 source_N = vec3(0);
    vec3 i_multiplier = vec3(0);
    vec3 j_multiplier = vec3(0);
    vec3 total = vec3(0);
    bool src_is_box1 = false;
    bool src_is_box2 = false;
    bool src_is_pumpkin = false;
    
    bool need_box1_shadow_check_base = true;
    
    if (dest_surface_index==INDEX_STALK1 
            || dest_surface_index==INDEX_LBLOCK_LEFT
            || dest_surface_index==INDEX_LBLOCK_RIGHT
            || dest_surface_index==INDEX_LBLOCK_FRONT
            || dest_surface_index==INDEX_LBLOCK_BACK
            || dest_surface_index==INDEX_LBLOCK_TOP
            || dest_surface_index==INDEX_RBLOCK_FRONT
            || dest_surface_index==INDEX_RBLOCK_RIGHT
            ) {
        need_box1_shadow_check_base = false;
    }

    bool need_box2_shadow_check_base = true;
    
    if (dest_surface_index==INDEX_STALK2 
            || dest_surface_index==INDEX_RBLOCK_LEFT
            || dest_surface_index==INDEX_RBLOCK_RIGHT
            || dest_surface_index==INDEX_RBLOCK_FRONT
            || dest_surface_index==INDEX_RBLOCK_BACK
            || dest_surface_index==INDEX_RBLOCK_TOP
            || dest_surface_index==INDEX_LBLOCK_BACK
            || dest_surface_index==INDEX_LBLOCK_TOP
            || dest_surface_index==INDEX_LBLOCK_LEFT
            ) {
        need_box2_shadow_check_base = false;
    }
    
    bool need_box1_shadow_check, need_box2_shadow_check;
    
    total_iterations += min(0, int(iTime));

    for (int itr=0; itr < total_iterations; itr++) {
        j++;
        
        if (j >= MESH_DIM) {
            j = 0;
            i++;
        }
        
        if (i >= MESH_DIM) {
            // Get the next source mesh index by shifting the bit mask left until the low bit is set and
            //      remembering how many times we have done this
        
            surface_mask >>= 1; // or could do this immediately afterwards since it's not used in the main work of the loop
            current_surface_index++;
            
            if ((surface_mask&0xffff) == 0) { // Shouldn't be needed (except when testing a single source surface)
                surface_mask >>= 16;
                current_surface_index += 16;
            }
            
            if ((surface_mask&0xff) == 0) { // Could avoid if there's never a gap of 8
                surface_mask >>= 8;
                current_surface_index += 8;
            }
            
            if ((surface_mask&0xf) == 0) { // Could avoid if there's never a gap of 4
                surface_mask >>= 4;
                current_surface_index += 4;
            }
            
            if ((surface_mask&0x3) == 0) {
                surface_mask >>= 2;
                current_surface_index += 2;
            }
            
            if ((surface_mask&0x1) == 0) {
                surface_mask >>= 1;
                current_surface_index++;
            }
            
            // Set everything up for processing the next source mesh

            i = 0;
            j = 0;
            i_multiplier = vec3(0);
            j_multiplier = vec3(0);
            source_N = vec3(0);
            src_is_pumpkin = false;
            source_diffuse_color = DEFAULT_DIFFUSE_COLOR;

            if (current_surface_index <= INDEX_BACK_WALL || current_surface_index == INDEX_CEILING) {
                source_point_offset = vec3(0,0,0);
                src_is_box1 = false;
                src_is_box2 = false;
                
                switch(current_surface_index) {
                    case INDEX_FLOOR:
                        source_N.y = 1.;
                        i_multiplier.z = 1.;
                        j_multiplier.x = 1.;
                        break;
                    case INDEX_LEFT_WALL:
                        source_diffuse_color = LEFT_WALL_DIFFUSE_COLOR;
                        
                        source_N.x = 1.;
                        i_multiplier.y = 1.;
                        j_multiplier.z = 1.;
                        break;
                    case INDEX_RIGHT_WALL:
                        source_diffuse_color = RIGHT_WALL_DIFFUSE_COLOR;
                        
                        source_point_offset.x = 1.;
                        source_N.x = -1.;
                        i_multiplier.y = 1.;
                        j_multiplier.z = 1.;
                        break;
                    case INDEX_BACK_WALL:
                        source_point_offset.z = 1.;
                        source_N.z = -1.;
                        i_multiplier.y = 1.;
                        j_multiplier.x = 1.;
                        break;
                    default:
                    //case INDEX_CEILING:
                        source_point_offset.y = 1.;
                        source_N.y = -1.;
                        i_multiplier.z = 1.;
                        j_multiplier.x = 1.;
                        break;
                }
            } else if (current_surface_index >= INDEX_FLOOR00 && current_surface_index <= INDEX_FLOOR11) {
                source_point_offset = vec3(0,0,0);
                src_is_box1 = false;
                src_is_box2 = false;
                source_N.y = 1.;
                i_multiplier.z = 0.5;
                j_multiplier.x = 0.5;
                
                if (current_surface_index == INDEX_FLOOR01 || current_surface_index == INDEX_FLOOR11) source_point_offset.x += 0.5;
                if (current_surface_index == INDEX_FLOOR10 || current_surface_index == INDEX_FLOOR11) source_point_offset.z += 0.5;
            } else if (current_surface_index >= INDEX_PUMPKIN1 && current_surface_index <= INDEX_PUMPKIN3) {
                src_is_box1 = false;
                src_is_box2 = false;
                src_is_pumpkin = true;
            } else {
                src_is_box2 = (current_surface_index&1) != 0;
                src_is_box1 = ! src_is_box2;
                
                mat2 M;
                vec3 corner1;
                vec3 corner2;
                
                if (src_is_box1) {
                    M = mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2));
                    corner1 = vec3(0.25, 0., 0.45);
                    corner2 = vec3(0.6, 0.55, 0.75);
                } else {
                    M = mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11));
                    corner1 = vec3(0.55, 0., 0.45);
                    corner2 = vec3(0.85, 0.3, 0.75);
                }
                
                source_point_offset = corner1;
                vec3 dcorner = corner2 - corner1;
                
                switch (current_surface_index&~1) {
                    case INDEX_LBLOCK_TOP:
                        source_point_offset.y = corner2.y;
                        source_N.y = 1.;
                        i_multiplier.z = dcorner.z;
                        j_multiplier.x = dcorner.x;
                        break;
                    case INDEX_LBLOCK_LEFT:
                        source_N.x = -1.;
                        i_multiplier.y = dcorner.y;
                        j_multiplier.z = dcorner.z;
                        break;
                    case INDEX_LBLOCK_FRONT:
                        source_N.z = -1.;
                        i_multiplier.y = dcorner.y;
                        j_multiplier.x = dcorner.x;
                        break;
                    case INDEX_LBLOCK_RIGHT:
                        source_point_offset.x = corner2.x;
                        source_N.x = 1.;
                        i_multiplier.y = dcorner.y;
                        j_multiplier.z = dcorner.z;
                        break;
                    case INDEX_LBLOCK_BACK:
                        source_point_offset.z = corner2.z;
                        source_N.z = 1.;
                        i_multiplier.y = dcorner.y;
                        j_multiplier.x = dcorner.x;
                        break;
                }
                
                i_multiplier.xz = i_multiplier.xz * M;
                j_multiplier.xz = j_multiplier.xz * M;
                source_N.xz = source_N.xz * M;
                source_point_offset.xz = source_point_offset.xz * M;
            }
            
            need_box1_shadow_check = (need_box1_shadow_check_base && ! src_is_box1
                                            && current_surface_index != INDEX_RBLOCK_FRONT
                                            && current_surface_index != INDEX_RBLOCK_RIGHT
                                            && current_surface_index != INDEX_STALK1
                                            && ! ((dest_surface_index==INDEX_STALK1 || dest_surface_index==INDEX_PUMPKIN1) && current_surface_index==INDEX_PUMPKIN3)
                                            && ! ((dest_surface_index==INDEX_STALK3 || dest_surface_index==INDEX_PUMPKIN3) && current_surface_index==INDEX_PUMPKIN1));
            
            need_box2_shadow_check = (need_box2_shadow_check_base && ! src_is_box2
                                            && current_surface_index != INDEX_LBLOCK_TOP
                                            && current_surface_index != INDEX_LBLOCK_BACK
                                            && current_surface_index != INDEX_LBLOCK_LEFT
                                            && current_surface_index != INDEX_STALK2
                                            && ! ((dest_surface_index==INDEX_STALK1 || dest_surface_index==INDEX_PUMPKIN1) && current_surface_index==INDEX_PUMPKIN2)
                                            && ! ((dest_surface_index==INDEX_STALK2 || dest_surface_index==INDEX_PUMPKIN3) && current_surface_index==INDEX_PUMPKIN1));
                                            
        }
        
        vec3 source_P;
        
        bool is_shadowed = false;
        
        
        if (dest_is_pumpkin) {
            if (dest_surface_index==INDEX_PUMPKIN2 || dest_surface_index==INDEX_PUMPKIN2_UV) {
                is_shadowed = dest_P.y < 0.55 + 0.0005;
            } else if (dest_surface_index==INDEX_PUMPKIN3 || dest_surface_index==INDEX_PUMPKIN3_UV) {
                is_shadowed = dest_P.y < 0.3 + 0.0005;
            }
        }            
        
        if ( ! is_shadowed && src_is_pumpkin) {
            // For pumpkins, we need to fetch the displacement and surface normal from Buffer A data
        
            ivec2 base = CHOOSE3(current_surface_index==INDEX_PUMPKIN1, current_surface_index==INDEX_PUMPKIN2, 
                                 ivec2(32, 2*SPHERE_UV_DIM), ivec2(32 + MESH_DIM, 2*SPHERE_UV_DIM), ivec2(32 + 2*MESH_DIM, 2*SPHERE_UV_DIM));
            
            vec4 data = texelFetch(iChannel0, base + ivec2(j, i), 0);
            
            // source_N is not normalized. Magnitude of vector should be area of the source patch.
            source_N = data.xyz; 
            
            {
                vec2 coord = 1./float(MESH_DIM) * (vec2(j, i) + 0.5);
                
                coord.y = pumpkin_map_01_to_squished(coord.y);
            
                float phi = 2.*PI * (coord.x - 0.5);
                float theta = PI*(coord.y - 0.5);
                float cos_theta = cos(theta);
                
                // Convert distance from center into 3D point
                source_P = data.w * vec3(cos(phi)*cos_theta, sin(theta), sin(phi)*cos_theta);
            }
            
            vec3 offset;
            
            if (current_surface_index == INDEX_PUMPKIN1) {
                offset = PUMPKIN1_OFFSET;
            } else if (current_surface_index == INDEX_PUMPKIN2) {
                offset = PUMPKIN2_OFFSET;
            } else {
                offset = PUMPKIN3_OFFSET;
            }
            
            source_P += offset;
            
            is_shadowed = dot(source_N, source_P - dest_P) >= 0. || dot(dest_N, source_P - dest_P) <= 0.;
            
            if ( have_N2 && ! is_shadowed) is_shadowed = dot(dest_N2, source_P - dest_P) <= 0.;
        } else {
            vec2 c = map_coords_to_linear_lowres(current_surface_index, vec2(j, i) * (1./float(MESH_DIM)));
            
            source_P = source_point_offset + c.x*j_multiplier + c.y*i_multiplier;
        }
        
        vec3 V = normalize(source_P - dest_P); // In the rare case where source_P == dest_P, V will be vec3(NaN), but result won't be added to total

        float t_inter = distance(source_P, dest_P);
        
        // Get bounds of the ray (for very rough AABB tests)
        vec3 low = min(source_P, dest_P);
        vec3 high = max(source_P, dest_P);
        
        // Test for shadowing by boxes
        
        {
            if ( ! is_shadowed && need_box1_shadow_check && bound_overlap(low, high, BOX1_BOUND_LOW, BOX1_BOUND_HIGH)) {
                is_shadowed = intersects_box(dest_P, V, t_inter, mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2)), vec3(0.25, 0., 0.45), vec3(0.6, 0.55, 0.75));
            }
                
            if ( ! is_shadowed && need_box2_shadow_check && bound_overlap(low, high, BOX2_BOUND_LOW, BOX2_BOUND_HIGH)) {
                is_shadowed = intersects_box(dest_P, V, t_inter, mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11)), vec3(0.55, 0., 0.45), vec3(0.85, 0.3, 0.75));
            }
        }

        // Test for shadowing by pumpkins
        
        if ( ! is_shadowed ) {
            vec2 bound = vec2(0);
            bool inter = false;
            
            bool need_pk;
            
            if (dest_surface_index == INDEX_STALK1) {
                need_pk = current_surface_index != INDEX_PUMPKIN1 && V.y < 0.;
            } else {
                need_pk = current_surface_index != INDEX_PUMPKIN1 && dest_surface_index != INDEX_PUMPKIN1 && dest_surface_index != INDEX_PUMPKIN1_UV;
                
                // This is not ideal, but might help speed it up
                // could add INDEX_RBLOCK_FRONT
                // could add INDEX_PUMPKIN3
                // could add INDEX_PUMPKIN2
                if (
                            dest_surface_index != INDEX_FLOOR00 
                            && dest_surface_index != INDEX_FLOOR01 
                            && dest_surface_index != INDEX_FLOOR10 // could remove
                            && dest_surface_index != INDEX_FLOOR11 // could remove
                            && dest_surface_index != INDEX_LEFT_WALL
                            && dest_surface_index != INDEX_LBLOCK_FRONT
                            && dest_surface_index != INDEX_RBLOCK_LEFT) {
                    need_pk = false;
                }
            }
            
            if (need_pk) {
                int pk_index = 0;
                
                mat3 mtx;
                vec3 offset;
                float scale;
                float bound_radius;
                vec3 C;
                
                mtx = RMTX_PK1;
                offset = PUMPKIN1_OFFSET;
                scale = PUMPKIN1_SCALE;
                bound_radius = BOUND_RADIUS_PK1;
                C = vec3(-0.14849257729044624, 0.23896602776846423, 0.17849038653186586);
            
                vec3 use_V = mtx * V;
                vec3 use_O = mtx * (1./scale * (dest_P - offset));
                
                float t = -dot(use_O, use_V);
                
                if (t > 0. && t < 1./scale * t_inter) {
                    vec3 P = use_O + t * use_V;
                    
                    float distance = length(P);
                    vec3 N = normalize(P);
                        
                    float y = N.y;
                
                    float step = dot(C, vec3(y, (y*y)*y, (y*y)*y*(y*y)));
                        
                    vec3 P0 = bound_radius*N;
                    
                    {
                        vec3 P = P0 + step*use_V;
                        
                        if (pumpkin_val_fn(distance / (dot(P, N)) * P, false, pk_index) < 0.) {
                            is_shadowed = true;
                        }
                    }
                    
                    {
                        vec3 P = P0 - step*use_V;
                        
                        if (pumpkin_val_fn(distance / (dot(P, N)) * P, false, pk_index) < 0.) {
                            is_shadowed = true;
                        }
                    }
                }
            }
            
            if ( ! is_shadowed) {
                if (dest_surface_index == INDEX_STALK2) {
                    need_pk = current_surface_index != INDEX_PUMPKIN2 && V.y < 0.;
                } else {
                    need_pk = current_surface_index != INDEX_PUMPKIN2 && dest_surface_index != INDEX_PUMPKIN2 && dest_surface_index != INDEX_PUMPKIN2_UV;
                
                    // This is not ideal, but might help speed it up
                    if (
                                dest_surface_index != INDEX_CEILING
                                && dest_surface_index != INDEX_LEFT_WALL
                                && dest_surface_index != INDEX_BACK_WALL
                                && dest_surface_index != INDEX_LBLOCK_TOP
                                && dest_surface_index != INDEX_STALK1
                                && dest_surface_index != INDEX_PUMPKIN3_UV
                                ) {
                        need_pk = false;
                    }
                }
            } else {
                need_pk = false;
            }
            
            if (need_pk) {
                int pk_index = 1;
                mat3 mtx = RMTX_PK2;
                vec3 offset = PUMPKIN2_OFFSET;
                float scale = PUMPKIN2_SCALE;
                float bound_radius = BOUND_RADIUS_PK2;
                vec3 C = vec3(-0.16231354703313422, 0.27299906675996666, 0.11028883816076998);
            
                vec3 use_V = mtx * V;
                vec3 use_O = mtx * (1./scale * (dest_P - offset));
                
                float t = -dot(use_O, use_V);
                
                if (t > 0. && t < 1./scale * t_inter) {
                    vec3 P = use_O + t * use_V;
                    
                    float distance = length(P);
                    vec3 N = normalize(P);
                        
                    float y = N.y;
                
                    float step = dot(C, vec3(y, (y*y)*y, (y*y)*y*(y*y)));
                        
                    vec3 P0 = bound_radius*N;
                    
                    {
                        vec3 P = P0 + step*use_V;
                        
                        if (pumpkin_val_fn(distance / (dot(P, N)) * P, false, pk_index) < 0.) {
                            is_shadowed = true;
                        }
                    }
                    
                    {
                        vec3 P = P0 - step*use_V;
                        
                        if (pumpkin_val_fn(distance / (dot(P, N)) * P, false, pk_index) < 0.) {
                            is_shadowed = true;
                        }
                    }
                }
            }
                
            if ( ! is_shadowed) {
                if (dest_surface_index == INDEX_STALK3) {
                    need_pk = current_surface_index != INDEX_PUMPKIN3 && V.y < 0.;
                } else {
                    need_pk = current_surface_index != INDEX_PUMPKIN3 && dest_surface_index != INDEX_PUMPKIN3 && dest_surface_index != INDEX_PUMPKIN3_UV;
                
                    // This is not ideal, but might help speed it up
                    if (
                                dest_surface_index != INDEX_BACK_WALL
                                && dest_surface_index != INDEX_RIGHT_WALL
                                && dest_surface_index != INDEX_RBLOCK_TOP
                                && dest_surface_index != INDEX_LBLOCK_FRONT
                                && dest_surface_index != INDEX_LBLOCK_RIGHT
                                && dest_surface_index != INDEX_PUMPKIN1_UV
                                && dest_surface_index != INDEX_FLOOR00 
                                ) {
                        need_pk = false;
                    }
                }
            } else {
                need_pk = false;
            }
            
            if (need_pk) {
                int pk_index = 2;
                mat3 mtx = RMTX_PK3;
                vec3 offset = PUMPKIN3_OFFSET;
                float scale = PUMPKIN3_SCALE;
                float bound_radius = BOUND_RADIUS_PK3;
                vec3 C = vec3(-0.18457466605225648, 0.3245144467907586, 0.11583038336017015);
            
                vec3 use_V = mtx * V;
                vec3 use_O = mtx * (1./scale * (dest_P - offset));
                
                float t = -dot(use_O, use_V);
                
                if (t > 0. && t < 1./scale * t_inter) {
                    vec3 P = use_O + t * use_V;
                    
                    float distance = length(P);
                    vec3 N = normalize(P);
                        
                    float y = N.y;
                
                    float step = dot(C, vec3(y, (y*y)*y, (y*y)*y*(y*y)));
                        
                    vec3 P0 = bound_radius*N;
                    
                    {
                        vec3 P = P0 + step*use_V;
                        
                        if (pumpkin_val_fn(distance / (dot(P, N)) * P, false, pk_index) < 0.) {
                            is_shadowed = true;
                        }
                    }
                    
                    {
                        vec3 P = P0 - step*use_V;
                        
                        if (pumpkin_val_fn(distance / (dot(P, N)) * P, false, pk_index) < 0.) {
                            is_shadowed = true;
                        }
                    }
                }
            }
        }
        
        // Test for shadowing by a stalk (we assume we only need to test one)
        
        if ( ! is_shadowed 
                && ((dest_surface_index >= INDEX_PUMPKIN1_UV && dest_surface_index <= INDEX_PUMPKIN3_UV && dest_N.y > 0.5)
                    || (dest_surface_index >= INDEX_STALK1 && dest_surface_index <= INDEX_STALK3))) {
            vec3 dest_P_shadow;
            float shift, radius;
            bool is_stalk = dest_surface_index >= INDEX_STALK1;
            int pk_index = dest_surface_index - (is_stalk ? INDEX_STALK1 : INDEX_PUMPKIN1_UV);
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
        
            vec2 t_outer = intersect_sphere_both(vec3(0, shift, 0), radius, V, dest_P_shadow);

            t_outer.x = max(t_outer.x, is_stalk ? 0.01 : 0.2);
            
            //is_stalk = false;
            
            if (t_outer.x < t_outer.y) {
                vec2 split = vec2((-0.25 - dest_P_shadow.y)  * 1./V.y, ((pk_index == 2 ? 0.05 : 0.1) - dest_P_shadow.y)  * 1./V.y);
                
                vec2 interval = V.y >= 0. ? vec2(t_outer.x, min(t_outer.y, split.x)) : vec2(max(t_outer.x, split.x), t_outer.y);
                
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
                        if (is_stalk) {
                            is_shadowed = stalk_val_and_deriv_fn(mtx * (dest_P_shadow + 0.5*(interval2.x + interval2.y)*V), pk_index).w < 0.;
                        } else {
                            is_shadowed = true;
                        }
                    }
                }
                
                if ( ! is_shadowed) {
                    vec2 interval2 = vec2(max(t_outer.x, V.y >= 0. ? split.x : split.y), min(t_outer.y, V.y >= 0. ? split.y : split.x));
                    
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
                            if (is_stalk) {
                                is_shadowed = stalk_val_and_deriv_fn(mtx * (dest_P_shadow + 0.5*(interval2.x + interval2.y)*V), pk_index).w < 0.;
                            } else {
                                is_shadowed = true;
                            }
                        }
                    }
                }
                
                bool split_dir = V.y >= 0.;
                
                if ( ! is_shadowed && pk_index == 2) {
                    bool split3_side;
                    float split3;
                    
                    {
                        float k = dot(V.xy, normalize(vec2(1,1.5)));
                    
                        split3 = (0.3 - dot(dest_P_shadow.xy, normalize(vec2(1,1.5)))) / k;
                        split3_side = k >= 0.;
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
                                if (is_stalk) {
                                    is_shadowed = stalk_val_and_deriv_fn(mtx * (dest_P_shadow + 0.5*(interval2.x + interval2.y)*V), pk_index).w < 0.;
                                } else {
                                    is_shadowed = true;
                                }
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
                            if (is_stalk) {
                                is_shadowed = stalk_val_and_deriv_fn(mtx * (dest_P_shadow + 0.5*(interval2.x + interval2.y)*V), pk_index).w < 0.;
                            } else {
                                is_shadowed = true;
                            }
                        }
                    }
                }
            }
        }
        
        // For unshadowed points, compute the differential form factor multiplied by the area of the source patch
        // We treat the source patch as an actual polygon (not some vague area) so we can handle patches that
        //      are near the horizon correctly.
        // Try to use simpler code if the source patch is definitely above the horizon.

        float d = 0.; // This will contain the form factor
        
        if ( ! is_shadowed) {
            // Values added here are still multiplied by PI
            
            vec2 src_coord1 = map_coords_to_linear(current_surface_index, vec2(j, i) * (1./float(MESH_DIM)));
            vec2 src_coord2 = map_coords_to_linear(current_surface_index, (vec2(j, i) + 1.) * (1./float(MESH_DIM)));
            
            if (t_inter > 0.1 && src_is_pumpkin) {
                // Magnitude of source_N is area of patch, so no separate area factor is needed
                // value must be negated because sign of the two dot products is opposite, obviously
                d = -dot(dest_N, V) * dot(source_N, V) / (t_inter*t_inter);
            } else if (t_inter > 0.1) {
                float d1 = dot(dest_N, V);
                float d2 = dot(source_N, V);
                
                if (d1 > 0. && d2 < 0.) {
                    d = -d1 * d2 / (t_inter * t_inter);
                    
                    d *= (src_coord2.y - src_coord1.y) * (src_coord2.x - src_coord1.x) * length(j_multiplier) * length(i_multiplier);
                } else {
                    d = 0.;
                }
            } else if (src_is_pumpkin) {
                vec3 P1, P2, P3, P4;
                
                {
                    ivec2 icoord = ivec2(j, i);
                    
                    vec2 coord = 1./float(MESH_DIM) * (vec2(icoord) + 0.5);
                    
                    float k0 = coord.y - 0.5/float(MESH_DIM);
                    float k1 = coord.y + 0.5/float(MESH_DIM);
                        
                    k0 = pumpkin_map_01_to_squished(k0);
                    k1 = pumpkin_map_01_to_squished(k1);
                    
                    if (icoord.y == MESH_DIM - 1) k1 = 1.; // should probably never happen

                    float theta0 = PI*(k0 - 0.5);
                    float theta1 = PI*(k1 - 0.5);
                    
                    float y0 = sin(theta0);
                    float y1 = sin(theta1);
                    
                    float cos_theta0 = cos(theta0);
                    float cos_theta1 = cos(theta1);
                    
                    float phi0 = 2.*PI * (coord.x - 0.5/float(MESH_DIM) - 0.5);
                    float phi1 = 2.*PI * (coord.x + 0.5/float(MESH_DIM) - 0.5);
                    
                    float c0 = cos(phi0);
                    float c1 = cos(phi1);
                    float s0 = sin(phi0);
                    float s1 = sin(phi1);

                    P1 = vec3(c0*cos_theta0, y0, s0*cos_theta0);
                    P2 = vec3(c0*cos_theta1, y1, s0*cos_theta1);
                    P3 = vec3(c1*cos_theta1, y1, s1*cos_theta1);
                    P4 = vec3(c1*cos_theta0, y0, s1*cos_theta0);
                }
                
                vec3 offset;
                
                if (current_surface_index == INDEX_PUMPKIN1) {
                    offset = PUMPKIN1_OFFSET;
                } else if (current_surface_index == INDEX_PUMPKIN2) {
                    offset = PUMPKIN2_OFFSET;
                } else {
                    offset = PUMPKIN3_OFFSET;
                }

                vec3 P0 = dest_P - offset;

                float t_M = dot(source_P - offset, source_N);
                
                P1 *= t_M / dot(P1, source_N);
                P2 *= t_M / dot(P2, source_N);
                P3 *= t_M / dot(P3, source_N);
                P4 *= t_M / dot(P4, source_N);
                
                d = get_diff_poly_sum(P2 - P0, P1 - P0, dest_N);
                d += get_diff_poly_sum(P3 - P0, P2 - P0, dest_N);
                d += get_diff_poly_sum(P4 - P0, P3 - P0, dest_N);
                d += get_diff_poly_sum(P1 - P0, P4 - P0, dest_N);
                
                d *= 0.5;
            } else {
                vec3 P0 = dest_P;
                float gap = dot(source_P - P0, source_N);
            
                if (gap > -0.001 && gap < 0.001) {
                    P0 += (0.001-gap)*source_N;
                    gap = -0.001;
                }

                vec3 P1 = source_point_offset + src_coord1.y*i_multiplier + src_coord1.x*j_multiplier;
                vec3 P2 = source_point_offset + src_coord1.y*i_multiplier + src_coord2.x*j_multiplier;
                vec3 P3 = source_point_offset + src_coord2.y*i_multiplier + src_coord2.x*j_multiplier;
                vec3 P4 = source_point_offset + src_coord2.y*i_multiplier + src_coord1.x*j_multiplier;
                
                P1 -= P0;
                P2 -= P0;
                P3 -= P0;
                P4 -= P0;
                
                bool P1inside = dot(P1, dest_N) > 0.;
                bool P2inside = dot(P2, dest_N) > 0.;
                bool P3inside = dot(P3, dest_N) > 0.;
                bool P4inside = dot(P4, dest_N) > 0.;

                d = 0.;
                
                if (gap < 0. && (P1inside || P2inside || P3inside || P4inside)) {
                    vec3 P_0 = vec3(0);
                    vec3 P_1 = vec3(0);
                    vec3 P_2 = vec3(0);
                    vec3 P_3 = vec3(0);
                    vec3 P_4 = vec3(0);
                    int c = 0;
                    
                    if (P1inside) {
                        P_0 = P1;
                        c = 1;
                    }
                        
                    if (P1inside != P2inside) {
                        vec3 W = P2 - P1;
                        
                        float t = dot(P1, dest_N) / dot(W, dest_N);
                        
                        P_1 = P_0;
                        P_0 = P1 - t * W;
                        c += 1;
                    }
                    
                    if (P2inside) {
                        P_1 = P_0;
                        P_0 = P2;
                        c += 1;
                    }
                        
                    if (P2inside != P3inside) {
                        vec3 W = P3 - P2;
                        
                        float t = dot(P2, dest_N) / dot(W, dest_N);
                        
                        P_2 = P_1;
                        P_1 = P_0;
                        P_0 = P2 - t * W;
                        c += 1;
                    }
                    
                    if (P3inside) {
                        P_3 = P_2;
                        P_2 = P_1;
                        P_1 = P_0;
                        P_0 = P3;
                        c += 1;
                    }

                    if (P3inside != P4inside) {
                        vec3 W = P4 - P3;
                        
                        float t = dot(P3, dest_N) / dot(W, dest_N);
                        
                        // P_4 = P_3; // Previous part can have at most 4 vertices
                        P_3 = P_2;
                        P_2 = P_1;
                        P_1 = P_0;
                        P_0 = P3 - t * W;
                        c += 1;
                    }
                    
                    if (P4inside) {
                        P_4 = P_3;
                        P_3 = P_2;
                        P_2 = P_1;
                        P_1 = P_0;
                        P_0 = P4;
                        c += 1;
                    }
                        
                    if (P4inside != P1inside) {
                        vec3 W = P1 - P4;
                        
                        float t = dot(P4, dest_N) / dot(W, dest_N);
                        
                        P_4 = P_3;
                        P_3 = P_2;
                        P_2 = P_1;
                        P_1 = P_0;
                        P_0 = P4 - t * W;
                        c += 1;
                    }
                    
                    // put the last vertex in P_2
                    
                    d += get_diff_poly_sum(P_1, P_0, dest_N);
                    d += get_diff_poly_sum(P_2, P_1, dest_N);

                    if (c >= 4) {
                        d += get_diff_poly_sum(P_3, P_2, dest_N);

                        if (c == 5) {
                            d += get_diff_poly_sum(P_4, P_3, dest_N);
                            P_2 = P_4;
                        } else {
                            P_2 = P_3;
                        }
                    }
                    
                    d += get_diff_poly_sum(P_0, P_2, dest_N);
                    
                    if (current_surface_index == INDEX_RIGHT_WALL || current_surface_index == INDEX_CEILING
                            || current_surface_index == INDEX_LBLOCK_LEFT || current_surface_index == INDEX_LBLOCK_BACK
                            || current_surface_index == INDEX_RBLOCK_LEFT || current_surface_index == INDEX_RBLOCK_BACK
                            ) {
                        d *= -0.5;
                    } else {
                        d *= 0.5;
                    }
                }
            }
        }
        
        if (d > 0.000001) {
            // If the ray is unshadowed and the form factor is not close to zero, get the total radiosity for the source patch
            
            float sample_scale = d;
            
            ivec2 tex_offset = ivec2(MESH_DIM*current_surface_index, 0);
            
            if (current_surface_index >= INDEX_FLOOR10) {
                tex_offset.y = MESH_DIM;
                tex_offset.x -= 2*MESH_DIM;
            }
            
            ivec2 tex_i = tex_offset + ivec2(j,i);
            
            vec3 source_val = vec3(0);
            
            if (current_surface_index != INDEX_CEILING && current_surface_index != INDEX_LBLOCK_LEFT && current_surface_index != INDEX_RBLOCK_RIGHT
                    && current_surface_index != INDEX_RBLOCK_FRONT && current_surface_index != INDEX_LBLOCK_BACK && current_surface_index != INDEX_RBLOCK_BACK) {
                // Fetch direct irradiance for the source patch from Buffer B
                source_val = vec3(texelFetch(iChannel1, tex_i, 0).r);
            }
            
            if ( ! is_first_bounce) {
                // Fetch indirect irradiance for the source patch from previous frame's Buffer C
                source_val += texelFetch(iChannel2, tex_i, 0).rgb;
            }
            
            // Compensate for the fact that the BRDFs are not Lambertian
            // (using approximations fitted to Monte Carlo simulation data)
            
            if ( ! src_is_pumpkin) {
                float d = -dot(source_N, V);
                float t = 1. - d;
                float spec = 0.0272 + 0.0928*t*t;
                float diff = 0.875 - 0.219*d*d;
                
                source_val *= diff * source_diffuse_color + spec;
            } else {
                float d = -dot(source_N, V);
                
                float w = evaluate_diffuse_curve(d, vec3(0.04344538, 0.04786321, 0.14475393));
                source_val *= (1. - w) + 0.9341 * w * PUMPKIN_DIFFUSE_COLOR;
            }
            
            total += sample_scale * source_val;
        }
    }
    
    // Finally divide by PI
    
    fragColor = vec4(1./PI * total, 0.);
}

