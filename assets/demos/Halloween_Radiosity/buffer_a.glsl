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

    Buffer A contains:
    - Four texels storing state for the view (updated when user drags with the 
      mouse or taps on a touchscreen)
    - Grids of cells representing the vector data for the cutout shapes in a form 
      that can be ray-marched quickly
    - 1D texture coordinates for the line segments in those cells
    - Distance (from center of pumpkin's bounding sphere) to inner and outer 
      surface at each of the vertices on the cutout shapes
    - Data used for mapping a x,y,z coordinates on the stalk surface to mesh 
      coordinates
    - Surface normals and displacements for points on the uv sphere mesh for the 
      pumpkins. For the low resolution mesh, the area of the patch of the mesh 
      corresponding to each mesh point is encoded in the magnitude of the normal.


*/


// Decode a vertex encoded in the low 16 bits of a given integer (straightforward)
vec2 decode_point(int data, vec2 decode_scale, vec2 decode_offset) {
    return decode_scale * vec2(ivec2(data, data >> 8) & 0xff) + decode_offset;
}

// Encode a quantized point as two integers
// (this encoding is used temporarily during processing - it's not necessarily the final encoding to be stored in the buffer)
// If it's on the edge of the grid cell, store a 2-bit value indicating which side of the square it's on
//      and a 12-bit position value (positions go clockwise around the square, with zeros at the corners).
// If it's in the interior of the cell, just negate the x value to signal this.
ivec2 get_edge_point(ivec2 q) {
    ivec2 r = ivec2(CUTOUT_SUBGRID_SIZE) - q;
    
    if (q.x*q.y == 0 || r.x*r.y == 0) {
        if (q.x == 0 && r.y != 0) {
            return ivec2(0, q.y);
        } else if (r.y == 0 && r.x != 0) {
            return ivec2(1, q.x);
        } else if (r.x == 0 && q.y != 0) {
            return ivec2(2, r.y);
        } else {
            return ivec2(3, r.x);
        }
    } else {
        return ivec2(-q.x, q.y);
    }
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Quickly skip unused portion of the buffer
    if (fragCoord.y >= 144. || fragCoord.x >= 128.) {
        fragColor = vec4(0);
        return;
    }

    // Update view state if user drags or taps.
    // This is the only thing in Buffer A that needs to be updated after the first frame
    if (fragCoord.y == float(VIEW_STATE_COORD.y) + 0.5 && fragCoord.x >= float(VIEW_STATE_COORD.x) + 0.5 && fragCoord.x <= float(VIEW_STATE_COORD.x) + 3.5) {
        
        bool is_drag = iMouse.z > 0. && iMouse.w < 0.;
        bool is_tap = iMouse.z < 0. && iMouse.w > 0.;
        
        #if 0
        // for debugging only
        is_drag = false;
        is_tap = iMouse.z < 0. && iMouse.w < 0.;
        #endif
        
        vec4 mouse = abs(iMouse);
    
        bool is_zoom = fragCoord.x == float(VIEW_STATE_COORD.x) + 1.5 || fragCoord.x == float(VIEW_STATE_COORD.x) + 3.5;
        
        vec4 state1 = iFrame == 0 ? (is_zoom ? vec4(ZOOM_DEFAULT, 0, 0, 0) : vec4(0))
            : texelFetch(iChannel0, ivec2(is_zoom ? VIEW_STATE_COORD.x + 1 : VIEW_STATE_COORD.x, VIEW_STATE_COORD.y), 0);
        vec4 state2 = iFrame == 0 ? vec4(65504, -65504, 65504, -65504) 
            : texelFetch(iChannel0, ivec2(is_zoom ? VIEW_STATE_COORD.x + 3 : VIEW_STATE_COORD.x + 2, VIEW_STATE_COORD.y), 0);
        
        if (state2.x==65504. && state2.y==-65504.) state2.xy = state1.xy;
        if (state2.z==65504. && state2.w==-65504.) state2.zw = state1.zw;
        
        if (is_drag || is_tap) {
            vec2 inc;
            
            if (is_drag) {
                inc = (mouse.xy - mouse.zw) / iResolution.xy;
            } else {
                inc.x = mouse.z < 0.5*iResolution.x ? -0.05 : 0.05;
                inc.y = mouse.w < 0.5*iResolution.y ? -0.05 : 0.05;        
            }

            if (mouse.z < VIEW_UI_DIVISION * iResolution.x && mouse.z < mouse.w) { // shift up/down
                if ( ! is_zoom) {
                    state1.w = state2.w - inc.y * VIEW_MOVE_MOUSE_SCALE;
                }
            } else if (mouse.w < VIEW_UI_DIVISION * iResolution.y && (iResolution.x - mouse.z) > mouse.w) { // shift left/right
                if ( ! is_zoom) {
                    state1.z = state2.z - inc.x * VIEW_MOVE_MOUSE_SCALE;
                }
            } else if (mouse.z > (1. - VIEW_UI_DIVISION) * iResolution.x) { // zoom
                if (is_zoom) {
                    state1.x = state2.x + inc.y * VIEW_ZOOM_MOUSE_SCALE;
                    
                    float dx = min(0., ZOOM_MAX - state1.x) + max(0., ZOOM_MIN - state1.x);
                    
                    state1.x += dx;
                    state2.x += dx;
                }
            } else { // rotate
                if ( ! is_zoom) {
                    if (is_tap) {
                        vec2 c = mouse.zw - vec2(0.5, 0.6) *iResolution.xy;
                        inc = abs(c.x) > abs(c.y) ? vec2(c.x < 0. ? -0.05 : 0.05, 0.) : vec2(0., c.y < 0. ? -0.05 : 0.05);
                    }
                
                    state1.xy = state2.xy + inc * VIEW_ROTATE_MOUSE_SCALE;
                
                    state1.x = mod(state1.x, 2.*PI);
                    
                    float dy = min(0., 0.499*PI - state1.y) + max(0., -0.499*PI - state1.y);
                    
                    state1.y += dy;
                    state2.y += dy;
                }
            }
        } else {
            state2 = vec4(65504, -65504, 65504, -65504);
        }
        
        fragColor = (fragCoord.x == float(VIEW_STATE_COORD.x) + 0.5 || fragCoord.x == float(VIEW_STATE_COORD.x) + 1.5) ? state1 : state2;
        
        return;
    }
    
    // Everything else is static and is only written during the first frame
    if (iFrame != 0) {
        fragColor = texelFetch(iChannel0, ivec2(fragCoord),0);
        return;
    }

    fragColor = vec4(0);
    
    if (fragCoord.x < float(SPHERE_UV_DIM) && fragCoord.y < float(SPHERE_UV_DIM)) {
        // Generate grids of cells containing one or two line segments for the cutout shapes
        // Data is split into two parts, one for the line segment data (point coordinates within the grid cell)
        //      and one for 1D positions along the edge (1D equivalent of vertex uv coordinates for texture mapping)
        
        bool write_1D_texture_coordinates = false;
        
        if (fragCoord.x >= 32.) {
            fragCoord.x -= 32.;
            write_1D_texture_coordinates = true;
        }

        int point_offset, point_count, loop_counts, loop_count_shift;
        vec2 decode_scale, decode_offset;
        
        // Figure out which pumpkin we're generating data for (and skip unused areas)
        if (fragCoord.y < CUTOUT_TEX_DIM_PK1.y) {
            if (fragCoord.x > CUTOUT_TEX_DIM_PK1.x) return;
            point_offset = CUTOUT_DATA_OFFSET_PACKED1;
            point_count = CUTOUT_POINT_COUNT1;
            loop_counts = CUTOUT_LOOP_COUNTS1;
            loop_count_shift = CUTOUT_LOOP_COUNT_SHIFT1;
            decode_scale = CUTOUT_DECODE_SCALE1;
            decode_offset = CUTOUT_DECODE_OFFSET1;
        } else if (fragCoord.y < CUTOUT_TEX_DIM_PK1.y + CUTOUT_TEX_DIM_PK2.y) {
            fragCoord.y -= CUTOUT_TEX_DIM_PK1.y;
            if (fragCoord.x > CUTOUT_TEX_DIM_PK2.x || fragCoord.y > CUTOUT_TEX_DIM_PK2.y) return;
            point_offset = CUTOUT_DATA_OFFSET_PACKED2;
            point_count = CUTOUT_POINT_COUNT2;
            loop_counts = CUTOUT_LOOP_COUNTS2;
            loop_count_shift = CUTOUT_LOOP_COUNT_SHIFT2;
            decode_scale = CUTOUT_DECODE_SCALE2;
            decode_offset = CUTOUT_DECODE_OFFSET2;
        } else {
            fragCoord.y -= CUTOUT_TEX_DIM_PK1.y + CUTOUT_TEX_DIM_PK2.y;
            if (fragCoord.x > CUTOUT_TEX_DIM_PK3.x || fragCoord.y > CUTOUT_TEX_DIM_PK3.y) return;
            point_offset = CUTOUT_DATA_OFFSET_PACKED3;
            point_count = CUTOUT_POINT_COUNT3;
            loop_counts = CUTOUT_LOOP_COUNTS3;
            loop_count_shift = CUTOUT_LOOP_COUNT_SHIFT3;
            decode_scale = CUTOUT_DECODE_SCALE3;
            decode_offset = CUTOUT_DECODE_OFFSET3;
        }
        
        int loop_count_mask = (1 << loop_count_shift) - 1;
        
        // Get coordinate of grid cell (grid size is 1 to make things simple)
        vec2 grid_cell_bottom_left = floor(fragCoord);
        
        vec2 p_center = vec2(0.5, 0.5); // For testing whether grid cell is inside the polygon if there were no intersections
        
        // Note: here "loop" refers to a closed loop of vertices, not to the "for" loop in the code.
        // Sorry that's confusing.
        
        // Get point index of start of next loop (first loop starts at 0)
        int next_start = loop_counts & loop_count_mask;
        
        // Figure out which pumpkin we're generating data for (and skip unused areas)
        int next_data = get_cutout_data(point_offset);
        
        // Decode first vertex (this is going to be p1 for the first edge and p2 for the last edge in the loop)
        vec2 p_loop_start = decode_point(next_data, decode_scale, decode_offset) - grid_cell_bottom_left;
        
        vec2 p1_next = p_loop_start;

        int c = 0; // used for testing if grid cell is inside polygon (typical "point in polygon" test)
        bool any_edges = false; // remember if there were any edges (otherwise we output a flag)
        
        // Data about the segments we've found
        ivec4 segA = ivec4(0);
        ivec4 segB = ivec4(0);
        
        // Data about the 1D texture coordinates of the segments we've found
        vec2 segA_t_range = vec2(0);
        vec2 segB_t_range = vec2(0);
        
        // prepare to decode the loop count of the next loop
        loop_counts >>= loop_count_shift;
        
        for (int i = 0; i < point_count; i++) {
            // get next 32 bits of data if necessary
            if ((i & 1) == 1) next_data = get_cutout_data(point_offset + ((i + 1) >> 1));
            else next_data >>= 16;
            
            // decode next point (unless we're at the end of the list of vertices)
            vec2 p2 = i < point_count - 1 ? decode_point(next_data, decode_scale, decode_offset) - grid_cell_bottom_left : vec2(0);
            vec2 p1;
            
            if (i == next_start) {
                // If we're at the start of the next loop, extract the vertex count for the loop.
                // We already put the first point for the loop in p_loop_start in the previous iteration.
                
                int path_len = loop_counts & loop_count_mask;
                
                next_start = path_len==0 ? point_count : next_start + path_len;
                loop_counts >>= loop_count_shift;
                
                p1 = p_loop_start;
            } else {
                // At end of loop, p2 is the first point in the loop, and the point we've just decoded is the first point in the next loop
                if (i == next_start - 1) swap(p2, p_loop_start);
                
                // p1 is usually p2 from the previous iteration
                p1 = p1_next;
            }
            
            p1_next = p2;
            
            if (p_center.x > min(p1.x, p2.x) && p_center.x < max(p1.x, p2.x)) {
                c += tri_area(p_center, p1, p2) < 0. ? -1 : 1;
            }

            const float EPS = 1e-6;
            
            if (max(min(p1.x, p2.x), min(p1.y, p2.y)) < 1. - EPS && min(max(p1.x, p2.x), max(p1.y, p2.y)) > EPS) {
                vec2 p1_orig = p1;
                vec2 t_dir_scaled;
                
                {
                    vec2 gap = p2 - p1;
                    
                    t_dir_scaled = gap / dot(gap, gap);
                    
                    vec2 slopes = gap / gap.yx;
                    
                    vec2 clip = p1 - p1.yx*slopes;
                    
                    if (p1.x < 0.) p1 = vec2(0., clip.y);
                    else if (p2.x < 0.) p2 = vec2(0., clip.y);

                    if (p1.y < 0.) p1 = vec2(clip.x, 0.);
                    else if (p2.y < 0.) p2 = vec2(clip.x, 0.);
                    
                    clip += slopes;
                        
                    if (p1.x > 1.) p1 = vec2(1., clip.y);
                    else if (p2.x > 1.) p2 = vec2(1., clip.y);
                    
                    if (p1.y > 1.) p1 = vec2(clip.x, 1.);
                    else if (p2.y > 1.) p2 = vec2(clip.x, 1.);
                }
                
                ivec2 q1 = ivec2(CUTOUT_SUBGRID_SIZE * p1 + 0.5);
                ivec2 q2 = ivec2(CUTOUT_SUBGRID_SIZE * p2 + 0.5);
                
                if (max(q1.x, q2.x) > 0 && max(q1.y, q2.y) > 0 && min(q1.x, q2.x) < int(CUTOUT_SUBGRID_SIZE) && min(q1.y, q2.y) < int(CUTOUT_SUBGRID_SIZE)
                        && (q1.x != q2.x || q1.y != q2.y)) {
                        
                    // Because we have prepared the list of points in advance and tested that it satisfies the constraints of the encoding
                    //      (at most two segments in any grid cell) we don't check for errors here.
                        
                    // Encoded the points as integers
                    ivec4 edge_points = ivec4(get_edge_point(q1), get_edge_point(q2));
                    
                    // Get 1D texture coordinates for the clipped line segment
                    vec2 t_range = 2.*float((point_offset<<1) + i) + vec2(dot(1./CUTOUT_SUBGRID_SIZE*vec2(q1) - p1_orig, t_dir_scaled), dot(1./CUTOUT_SUBGRID_SIZE*vec2(q2) - p1_orig, t_dir_scaled));
                   
                    if ( ! any_edges) { // If it's the first intersecting edge, just store the encoded line segment data
                        any_edges = true;
                        segA = edge_points;
                        segA_t_range = t_range;
                    } else {
                        if (segA.x < 0) { // If previous p1 was in the interior of the cell, reverse order of the segments
                            segB = segA;
                            segB_t_range = segA_t_range;
                            
                            segA = edge_points;
                            segA_t_range = t_range;
                        } else {
                            segB = edge_points;
                            segB_t_range = t_range;
                        }

                        // If the segments join at a point inside the grid cell, encode their shared point specially
                        if (segA.z < 0) {
                            // Should have segA.zw==segB.xy
                            
                            // We signal that there is a shared point by setting segA.z = segA.x (doesn't matter what the value is)
                            // This works because you can't have a segment that starts and ends on the same side of the grid cell.
                            // To encode the interior point coordinates, x is stored in segA.w, and y is stored in segB.y
                            // segB.x is not used, but we're setting it to non-zero to indicate that it's not a single-edge grid cell
                            
                            segB.xy = ivec2(1, segA.w);
                            segA.zw = ivec2(segA.x, -segA.z); // flip sign of segA.z back (could use abs instead)
                        }
                    }
                }
            }
        }
        
        if ( ! write_1D_texture_coordinates) {
            // We need to store a flag indicating whether the grid cell center is inside the polygon (if no edges in grid cell)
            //      or whether this piece of the polygon is concave or convex (if there are two edges in the cell)
            // In the later case, this information could be determined by the rasterizer/ray marcher, but we save time by computing it here.
            // If there's only one edge in the cell, the two points (and their order/direction) are all we need.
            float convex = 0.;
            
            if ( ! any_edges) {
                convex = float(c);
            } else if (segB != ivec4(0)) {
                // Decode two of the points
                vec2 p1 = cutout_unpack_point(segA.xy);
                vec2 p4 = cutout_unpack_point(segB.zw);
                
                if ((segA.x ^ segA.z) != 0) { // The two line segments are NOT connected at an interior point
                    // Decode the other two points
                    vec2 p2 = cutout_unpack_point(segA.zw);
                    vec2 p3 = cutout_unpack_point(segB.xy);
                    
                    // Test if the pair of line segments is considered "concave" or "convex" (as understood by the ray intersection code)
                    convex = -((p1.y*p2.x - p1.x*p2.y) + (p2.y*p3.x - p2.x*p3.y) + (p3.y*p4.x - p3.x*p4.y) + (p4.y*p1.x - p4.x*p1.y));
                } else {
                    // Test if the pair of line segments (with shared point (segA.w, segB.y)) is considered "concave" or "convex".
                    convex = tri_area(p1, 1./CUTOUT_SUBGRID_SIZE * vec2(segA.w, segB.y), p4);
                }
            }
            
            // Pack the data into four integers (14 bits each)
            ivec4 vpacked = ivec4(segA.xz, segB.xz) | (ivec4(segA.yw, segB.yw) << 2);
            
            // Encode the four integers safely as floats (compatible with 16-bit float buffers)
            fragColor = intBitsToFloat(ivec4(encode_14bits(vpacked.x), encode_14bits(vpacked.y), encode_14bits(vpacked.z), encode_14bits(vpacked.w)));
            
            // Encode some extra data in the signs of the values (which we did not use when encoding the 14 bits)
            if (convex < 0.) fragColor.x = -fragColor.x;
            if (any_edges) fragColor.y = -fragColor.y;
            if ((vpacked.z | vpacked.w) != 0) fragColor.z = -fragColor.z; // for performance, flag if second edge is used (otherwise we don't need to decode it)
            
        } else {
            // Just store the range of 1D texture coordinates for each line segment
            fragColor = vec4(segA_t_range, segB_t_range);
        }
        
        return;
    } else if (fragCoord.y >= float(2*SPHERE_UV_DIM) && fragCoord.y < float(2*SPHERE_UV_DIM + 16) 
                && fragCoord.x >= float(32 + 3*MESH_DIM) && fragCoord.x < float(32 + 3*MESH_DIM + 16)) {
        ivec2 c = ivec2(fragCoord);
        
        // coordinate gives index of point in full list (which possibly has some gaps for alignment reasons)
        int index = ((c.y - 2*SPHERE_UV_DIM) << 4) + (c.x - (32 + 3*MESH_DIM));
        
        // get data for point
        int data = get_cutout_data(index >> 1);
        
        if ((index & 1) != 0) data >>= 16;
        
        vec2 decode_scale, decode_offset;
            
        int pk_index;
        float proj_scale;
        vec2 proj_offset;
        
        if (index < 2*CUTOUT_DATA_OFFSET_PACKED2) {
            decode_scale = CUTOUT_DECODE_SCALE1;
            decode_offset = CUTOUT_DECODE_OFFSET1;
            
            pk_index = 0;
            proj_scale = CUTOUT_SCALE_PK1;
            proj_offset = -CUTOUT_OFFSET_PK1;
        } else if (index < 2*CUTOUT_DATA_OFFSET_PACKED3) {
            decode_scale = CUTOUT_DECODE_SCALE2;
            decode_offset = CUTOUT_DECODE_OFFSET2;

            pk_index = 1;
            proj_scale = CUTOUT_SCALE_PK2;
            proj_offset = -CUTOUT_OFFSET_PK2;
        } else {
            decode_scale = CUTOUT_DECODE_SCALE3;
            decode_offset = CUTOUT_DECODE_OFFSET3;
            
            pk_index = 2;
            proj_scale = CUTOUT_SCALE_PK3;
            proj_offset = -CUTOUT_OFFSET_PK3;
        }
        
        // get 2D point coordinates in grid
        vec2 ray_O_2d = decode_point(data, decode_scale, decode_offset);
        
        // Convert to projected coordinates
        vec2 orig_2d = (ray_O_2d + proj_offset) / proj_scale;
        
        // Each projected coordinate represents a set of possible points along a ray from the center of
        //      the pumpkin's bounding sphere. Find the direction vector for that ray.
        vec3 dir = normalize(vec3(orig_2d, -1));
        
        // Find distances to the two surfaces along the ray
        vec2 dist = distance_to_pumpkin_shape(dir, pk_index);
        
        // Store 3D point on outer surface, relative to bounding sphere center, and scaling factor needed to get the point on the inner surface.
        fragColor = vec4(dist.y * dir, INNER_SHAPE_SCALE * dist.x / dist.y);
    } else if (fragCoord.y >= float(2*SPHERE_UV_DIM) && fragCoord.y < float(2*SPHERE_UV_DIM + 5) && fragCoord.x < float(8*3)) {
        /* 
            We're using a uv cylinder for the stalk's mesh (for storing direct and indirect irradiance).
            The stalk's implicit surface function uses something like cylindrical coordinates internally, so it works well. Mapping from x,y,z (in each stalk's rotated coordinate space) to uv coordinate is trivial:
                u = atan(z, x), i.e. phi before multiplication by STALK_FREQ1
                v = y
            
            Trouble is the range of possible values for y will be different for each angle (for each u value). Because we want to keep the mesh small and use it optimally, we want to know the range as exactly as possible and map the mesh coordinates to this range.
            
            We precompute the range here, using two binary searches.
            The two searches are both done in the same loop (to reduce code duplication, and possibly reduce compilation time).
            
            Valid y values are simply y values for points on the implicit surface that are inside the stalk's bounding sphere (stalk is just implicit surface clipped to the bounding sphere).
            
            What's convenient is that we can easily find x and z for a given y on the surface of the stalk. I didn't plan ahead when designing the function, it was just luck.
        
        */
        
        ivec2 icoord = ivec2(fragCoord);
        
        int pk_index = icoord.x >> 3;
        int longitude = (icoord.y - (2*SPHERE_UV_DIM))*8 + (icoord.x & 7);
        
        float phi = (2.*PI / 40.) * float(longitude);
        
        float x0 = cos(phi);
        float z0 = sin(phi);
        
        float warp, modscale, radius2, shift;
        mat3 mtx;
        vec3 clip_bound_shift;

        if (pk_index == 0) {
            warp = STALK1_WARP;
            modscale = STALK1_MODSCALE;
            radius2 = STALK1_BOUND_RADIUS*STALK1_BOUND_RADIUS;
            shift = STALK1_BOUND_Y;
            mtx = STALK1_RMTX;
            clip_bound_shift = STALK1_RMTX * vec3(0, STALK1_BOUND_Y, 0);
        } else if (pk_index == 1) {
            warp = STALK2_WARP;
            modscale = STALK2_MODSCALE;
            radius2 = STALK2_BOUND_RADIUS*STALK2_BOUND_RADIUS;
            shift = STALK2_BOUND_Y;
            mtx = STALK2_RMTX;
            clip_bound_shift = STALK2_RMTX * vec3(0, STALK2_BOUND_Y, 0);
        } else {
            warp = STALK3_WARP;
            modscale = STALK3_MODSCALE;
            radius2 = STALK3_BOUND_RADIUS*STALK3_BOUND_RADIUS;
            shift = STALK3_BOUND_Y;
            mtx = STALK3_RMTX;
            clip_bound_shift = STALK3_RMTX * vec3(0, STALK3_BOUND_Y, 0);
        }
        
        // Precompute everything dependent on phi here.
        float dist_base = modscale * sqrt(sin(STALK_FREQ1 * phi) + 1.001) - STALK_BIAS;
        
        // We search for the lower y bound first, then the upper.
        
        // Binary search requires two values that bracket the edge being sought (it doesn't care what order they're in)
        // Set up the values bracketing the lower end of the possible y range
        float y_outside = -1.15;
        float y_inside = -0.42;
        
        float y_low;
        
        for (int i = 0; i < 32; i++) {
            float y = 0.5*(y_outside + y_inside);
            
            float a = y + 1.;
            
            float r = exp(-STALK_FLARE_FACTOR*a*a*a);
            float dist = dist_base + r;
            
            // Get point on implicit surface for this angle and y value, then shift
            //   so clipping sphere center is at zero.
            vec3 P = vec3(x0*dist - warp * y*y, y, z0*dist) - clip_bound_shift;
            
            // Test whether the point is inside the clipping sphere, and update
            // the values bracketing the edge.
            if (dot(P,P) < radius2) y_inside = y;
            else y_outside = y;
            
            if (i == 15) { // End of first binary search
                // Get result (estimate of position of low y value that gives a point on the bounding sphere)
                y_low = 0.5*(y_outside + y_inside); 
                
                // Set the bracketing values for second binary search
                y_outside = 0.68;
                y_inside = 0.52;
            }
        }

        // get result (estimate of position of high y value that gives a point on the bounding sphere)
        float y_high = 0.5*(y_outside + y_inside);
        
        fragColor = vec4(y_low, y_high, 0, 0);
    } else {
        // Compute and store surface normal and displacement for a point on the uv sphere mesh for a pumpkin
        // This is done for both low resolution and high resolution meshes
        
        // For the low resolution mesh, the area of the patch of the mesh corresponding to each mesh point is encoded in the magnitude of the normal.
        // (important for radiosity, to ensure energy conservation)
        // We don't need this value for the high resolution mesh because it isn't used as a source during radiosity passes.
        
        ivec2 icoord = ivec2(fragCoord);
        
        bool is_high_res = fragCoord.y < float(2*SPHERE_UV_DIM);
        
        int pk_index;
        
        if (is_high_res) {
            if (fragCoord.x >= float(2*SPHERE_UV_DIM) || (fragCoord.x < float(SPHERE_UV_DIM) && fragCoord.y < float(SPHERE_UV_DIM))) return;
            
            pk_index = fragCoord.y >= float(SPHERE_UV_DIM) ? (fragCoord.x < float(SPHERE_UV_DIM) ? 0 : 1) : 2;

            icoord &= (SPHERE_UV_DIM-1);
        } else {
            if (fragCoord.x < 32. || fragCoord.x >= float(32 + 3*MESH_DIM) || fragCoord.y >= float(2*SPHERE_UV_DIM + MESH_DIM)) return;
        
            pk_index = (icoord.x - 32) >> MESH_DIM_SHIFT;
            
            icoord &= (MESH_DIM-1);
        }

        mat3 mtx;
        float scale;
        vec4 C0; // coefficients for distance_to_pumpkin_shape
        float C1;
        
        if (pk_index==0) {
            C0 = vec4(0.51591536, 0.0366811, 0.13520878, -0.2999165);
            C1 = 0.067574354;
            mtx = RMTX_PK1;
            scale = PUMPKIN1_SCALE;
        } else if (pk_index==1) {
            C0 = vec4(0.53951799, 0.044976011, 0.11025531, -0.23711691);
            C1 = -0.049742672;
            mtx = RMTX_PK2;
            scale = PUMPKIN2_SCALE;
        } else {
            C0 = vec4(0.58844957, 0.075244936, 0.090307939, -0.26195241);
            C1 = -0.037918395;
            mtx = RMTX_PK3;
            scale = PUMPKIN3_SCALE;
        }
        
        if (is_high_res) {
            // High resolution is straightforward. Just find the distance, and get the surface normal from the partial derivatives of the pumpkin function
            vec2 coord = 1./float(SPHERE_UV_DIM) * (vec2(icoord) + 0.5);
            
            coord.y = pumpkin_map_01_to_squished(coord.y);
            
            vec3 V;
            
            {
                float theta = PI*(coord.y - 0.5);
                float y = sin(theta);
                
                float cos_theta = cos(theta);
                
                float phi = 2.*PI * (coord.x - 0.5);

                V = vec3(cos(phi)*cos_theta, y, sin(phi)*cos_theta);
            }
            
            V = mtx * V;
            
            float d = distance_to_pumpkin_shape(V, C0, C1, pk_index).x;

            vec3 N = normalize(pumpkin_val_and_deriv_fn(d*V, false, pk_index).xyz * mtx);
            
            fragColor = vec4(N, scale * d);
        } else {
            // For low resolution we have a sort of "virtual" mesh
            // We don't actually store vertices of the points on the mesh (they aren't needed by the radiosity passes)
            // We store offsets of points in the center of the mesh faces, and the normal vectors and areas of the faces.
            // The radiosity pass needs a point, a normal and an area (otherwise it doesn't care about the geometry of
            //   the mesh) and so we can fudge things a bit.
            
            vec2 coord = 1./float(MESH_DIM) * (vec2(icoord) + 0.5);
            
            float k0 = coord.y - 0.5/float(MESH_DIM);
            float k1 = coord.y + 0.5/float(MESH_DIM);
                
            coord.y = pumpkin_map_01_to_squished(coord.y);
            k0 = pumpkin_map_01_to_squished(k0);
            k1 = pumpkin_map_01_to_squished(k1);
            
            vec3 P1,P2,P3,P4;
            
            // Get directions to the four vertices and then scale them by distances to get points
            // This gives a quadrilateral (which might not be flat, but we assume it is)
            // We then get the normal from the cross product of the diagonals WITHOUT normalizing and divide by 2. This puts the area in the magnitude of the vector.
            
            {
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
                P4 = vec3(c1*cos_theta0, y0, s1*cos_theta0);
                P3 = vec3(c1*cos_theta1, y1, s1*cos_theta1);
                P2 = vec3(c0*cos_theta1, y1, s0*cos_theta1);
            }
            
            float d1 = scale * distance_to_pumpkin_shape(mtx * P1, C0, C1, pk_index).x;
            float d2 = scale * distance_to_pumpkin_shape(mtx * P2, C0, C1, pk_index).x;
            float d3 = scale * distance_to_pumpkin_shape(mtx * P3, C0, C1, pk_index).x;
            float d4 = scale * distance_to_pumpkin_shape(mtx * P4, C0, C1, pk_index).x;
                
            P1 *= d1;
            P2 *= d2;
            P3 *= d3;
            P4 *= d4;
            
            vec3 N = -0.5 * cross(P4-P2, P3-P1);
            
            // Get direction to center of mesh face (the direction that will be used by the shaders that read this data)
            vec3 N_ref;
            
            {
                float phi = 2.*PI * (coord.x - 0.5);
                float theta = PI*(coord.y - 0.5);
                float cos_theta = cos(theta);
                
                N_ref = vec3(cos(phi)*cos_theta, sin(theta), sin(phi)*cos_theta);
            }
            
            // Compromise between distance to mesh face center and average of distances to the four vertices
            float dist = 0.125 * (dot(P1 + P2 + P3 + P4, N_ref) + (d1 + d2 + d3 + d4));
            
            fragColor = vec4(N, dist);
            
            if (dot(N,N) < 1e-12) fragColor = vec4(0, 1e-12, 0, 0);
        }
    }
}

