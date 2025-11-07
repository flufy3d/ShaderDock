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
    
    Buffer D contains two types of lighting data (and normal vectors) for the 
    edges of the cutouts in the pumpkins. This data is indexed by values found 
    in Buffer A. The data is really two 1D textures, but they are arranged in 
    2D to make them fit in the buffer and make computation more GPU-friendly.
        
    The first type of data is ambient occlusion for the edges. The same data is 
    used for AO in both directions (occlusion of diffuse illumination from 
    inside the pumpkin, and occlusion of indirect illumination from outside the 
    pumpkin). 4 samples are taken and they are packed into x and y of the 
    output vec4 value. z and w are used to store the normal vector (using 
    octahedral encoding). To get the ambient occlusion, it essentially finds a 
    convex polygon with 32 corners that approximates the unoccluded region, and 
    analytically integrates light over this polygon. 3D ray marching (using 
    Buffer A data, as in the Image shader) is used to find the horizons in the 
    32 directions.
        
    The second type of data is the fraction of the area light that is shadowed 
    at each point along the cutout edge (actual irradiance divided by maximum 
    possible irradiance). This data is represented as Hermite splines that 
    approximate the function in the depth direction. To figure out what curves 
    to use, it needs to take many samples of the shadowed lighting at different 
    points in the depth direction so it can find the extent of the partially 
    shadowed region and get slopes of the curve (for Hermite spline encoding). 
    At each sampled point, the irradiance is computed analytically by finding 
    the polygon for the unoccluded part of the area light. Using analytical 
    integration gives exact values, which makes approximation by Hermite 
    splines much easier (sampled data is smooth, with no noise). Unlike Buffer 
    B, it doesn't store data for each quadrant of the area light.
        
    For the analytic integration, we uses data about the vertices of the shapes 
    that was precomputed in Buffer A. Shadowing data is only computed for a 
    small section of the shape edges (because it is expensive), and similarly 
    it only considers a small nearby section of the edge when looking for 
    potentially occluding edges. Getting this to work, and finding a way to 
    encode the data compactly so it could be interpolated smoothly, was 
    probably the most difficult part of the entire shader, but it was necessary 
    because sampling the area light in Image required too many samples and was 
    much too expensive.
    

*/

// Constants used for the direct light sampling
const float INITIAL_P1 = 0.9995;
const float P_LOW = 0.43;
const float P_HIGH = 0.82;
const float SLOPE_TEST_GAP = 0.002;

// Constants used for encoding the direct light curves
// These ranges are for values that have been multiplied by (p_low - p0), (p_high - p_low), (p_high - p_low), (p1 - p_high)
// (need to divide by those scales during decoding)
const float MAX_M0 = 0.4;
const float MAX_M1 = 1.;
const float MAX_M_LOW = 0.6;
const float MAX_M_HIGH = 0.5;
            
// Offset of place in Buffer A where the 3D coordinates for the cutout vertices are stored
const ivec2 TX_OFFSET = ivec2(32 + 3*MESH_DIM, 2*SPHERE_UV_DIM);

vec2 read_point(int point_index, int data_start, vec2 decode_scale, vec2 decode_offset) {
    int data = get_cutout_data(data_start + (point_index>>1));
    
    if ((point_index&1) != 0) data >>= 16;
    
    return decode_scale * vec2(data & 0xff, (data >> 8) & 0xff) + decode_offset;
}

const float MIN_DISTANCE = 1e-3;

// Function used during ray marching to check for an intersection with line segments in a particular grid cell
// xy is coordinate in [0,1) x [0,1)
bool intersect_test_cutout_grid_cell(ivec2 tex_coord, vec2 xy, vec2 d, float max_t, out float edge_t) {
    edge_t = 1e20;

    vec4 tex_data = texelFetch(iChannel0, tex_coord, 0);
    
    bool op_and = tex_data.x < 0.;
    bool inside = false;
    
    if (tex_data.y >= 0.) {
        inside = op_and;
    } else {
        vec4 tex_data2 = texelFetch(iChannel0, tex_coord + ivec2(32,0), 0);
        ivec2 params_packed1 = (floatBitsToInt(tex_data.xy) >> 13) & 0x3fff;
        
        vec2 p1 = cutout_unpack_point(params_packed1.x), p2 = cutout_unpack_point(params_packed1.y), p3, p4;
        bool have_segB = tex_data.z < 0., inside2;
        float t2 = 1e20;

        if (have_segB) {
            ivec2 params_packed2 = (floatBitsToInt(tex_data.zw) >> 13) & 0x3fff;
            
            p4 = cutout_unpack_point(params_packed2.y);
            
            if (((params_packed1.x ^ params_packed1.y) & 3) != 0) {
                p3 = cutout_unpack_point(params_packed2.x);
            } else {
                p2 = 1./CUTOUT_SUBGRID_SIZE * vec2(ivec2(params_packed1.y >> 2, params_packed2.x >> 2));
                p3 = p2;
            }
            
            float A2 = tri_area(xy, p3, p4);
            
            inside2 = A2 < 0.;
            t2 = A2 / dot(d, vec2(p4.y - p3.y, p3.x - p4.x));
            
            if (t2 < 0.) t2 = 1e20;
        }
        
        float t1;
        bool inside1;

        {
            float A = tri_area(xy, p1, p2);

            inside1 = A < 0.;
            
            t1 = A / dot(d, vec2(p2.y - p1.y, p1.x - p2.x));
        }
        
        if (t1 < 0.) t1 = 1e20;
        
        if (have_segB) {
            if (op_and) {
                inside = inside1 && inside2;
            } else {
                inside = inside1 || inside2;
                
                inside1 = ! inside1;
                inside2 = ! inside2;
            }
            
            if (inside1 && inside2) {
                if (inside) edge_t = min(t1, t2);
            } else if (inside1) {
                edge_t = t1 < t2 ? 1e20 : inside ? t2 : t1;
            } else if (inside2) {
                edge_t = t2 < t1 ? 1e20 : inside ? t1 : t2;
            } else {
                if (inside) edge_t = max(t1, t2);
            }
        } else {
            if (inside1) edge_t = t1;
            inside = inside1;
        }
        
        if (edge_t > max_t) edge_t = 1e20;
    }
    
    return inside;
}

vec4 compute_AO(int point_index, int texel_num) {
    int data_offset, point_count, loop_counts, loop_count_shift;
    vec2 decode_scale, decode_offset;
    
    int pk_index;
    float scale;
    vec2 offset;
    vec2 tex_dim;
    ivec2 tex_offset;
    
    if (point_index < 2*CUTOUT_DATA_OFFSET_PACKED2) {
        data_offset = CUTOUT_DATA_OFFSET_PACKED1;
        point_count = CUTOUT_POINT_COUNT1;
        loop_counts = CUTOUT_LOOP_COUNTS1;
        loop_count_shift = CUTOUT_LOOP_COUNT_SHIFT1;
        decode_scale = CUTOUT_DECODE_SCALE1;
        decode_offset = CUTOUT_DECODE_OFFSET1;
        
        pk_index = 0;
        scale = CUTOUT_SCALE_PK1;
        offset = -CUTOUT_OFFSET_PK1;
        tex_dim = CUTOUT_TEX_DIM_PK1;
        tex_offset = CUTOUT_TEX_OFFSET_PK1;
    } else if (point_index < 2*CUTOUT_DATA_OFFSET_PACKED3) {
        data_offset = CUTOUT_DATA_OFFSET_PACKED2;
        point_count = CUTOUT_POINT_COUNT2;
        loop_counts = CUTOUT_LOOP_COUNTS2;
        loop_count_shift = CUTOUT_LOOP_COUNT_SHIFT2;
        decode_scale = CUTOUT_DECODE_SCALE2;
        decode_offset = CUTOUT_DECODE_OFFSET2;

        pk_index = 1;
        scale = CUTOUT_SCALE_PK2;
        offset = -CUTOUT_OFFSET_PK2;
        tex_dim = CUTOUT_TEX_DIM_PK2;
        tex_offset = CUTOUT_TEX_OFFSET_PK2;
    } else {
        data_offset = CUTOUT_DATA_OFFSET_PACKED3;
        point_count = CUTOUT_POINT_COUNT3;
        loop_counts = CUTOUT_LOOP_COUNTS3;
        loop_count_shift = CUTOUT_LOOP_COUNT_SHIFT3;
        decode_scale = CUTOUT_DECODE_SCALE3;
        decode_offset = CUTOUT_DECODE_OFFSET3;
        
        pk_index = 2;
        scale = CUTOUT_SCALE_PK3;
        offset = -CUTOUT_OFFSET_PK3;
        tex_dim = CUTOUT_TEX_DIM_PK3;
        tex_offset = CUTOUT_TEX_OFFSET_PK3;
    }
    
    
    point_index -= 2*data_offset;
    
    int point_index_next;
    int point_index_adjacent;
    
    // get indices of next and previous points along the edge
    {
        int start=0, end=0, loop_count_mask = (1 << loop_count_shift) - 1;
        
        for (int i = 0; i < CUTOUT_MAX_LOOPS_PER_PUMPKIN && point_index >= end; i++, loop_counts >>= loop_count_shift) {
            int path_len = loop_counts & loop_count_mask;
            
            start = end;
            end = path_len == 0 ? point_count : start + path_len;
        }
        
        point_index_next = point_index == end - 1 ? start : point_index + 1;
                                              
        point_index_adjacent = texel_num == 0 ? (point_index == start ? end - 1 : point_index - 1)
                                              : (point_index_next == end - 1 ? start : point_index_next + 1);
                                              
    }
    
    vec4 depths;
    vec3 ray_O_3d;
    vec2 ray_O_2d;

    vec3 N_local;
    float plane_D_local;
    vec2 V2d_edge;
    vec2 N2d_edge;
    vec3 dest_N;

    float min_rel_angle = 0.;
    float max_rel_angle = PI;
    
    {
        vec2 p1 = read_point(point_index, data_offset, decode_scale, decode_offset);
        vec2 p2 = read_point(point_index_next, data_offset, decode_scale, decode_offset);
        
        V2d_edge = normalize(p2 - p1);
        
        N2d_edge = vec2(V2d_edge.y, -V2d_edge.x);
        
        ray_O_2d = mix(p1, p2, 1./15. * float(texel_num));
        
        // Find distances to the two surfaces at projected point ray_O_2d
        float t_inside, t_outside;
        
        {
            vec2 dist = distance_to_pumpkin_shape(normalize(vec3(ray_O_2d + offset, -scale)), pk_index);
            
            t_inside = INNER_SHAPE_SCALE * dist.x;
            t_outside = dist.y;
        }
        
        depths = vec4(0.1, 0.3, 0.7, 0.9)*(t_outside - t_inside);
        
        {
            vec2 p1_scaled = (p1 + offset) / scale;
            vec3 p1_3d;
            
            {
                vec3 dir = normalize(vec3(p1_scaled, 1));
                
                t_inside = INNER_SHAPE_SCALE * distance_to_pumpkin_shape(dir*vec3(1,1,-1), pk_index).x;
                
                p1_3d = t_inside*dir;
            }

            vec2 p2_scaled = (p2 + offset) / scale;
            vec3 p2_3d;
            
            {
                vec3 dir = normalize(vec3(p2_scaled, 1));
                
                t_inside = INNER_SHAPE_SCALE * distance_to_pumpkin_shape(dir*vec3(1,1,-1), pk_index).x;
                
                p2_3d = t_inside*dir;
            }

            {
                vec3 V1 = vec3(p1_scaled, 1.);
                vec3 V2 = vec3(p2_scaled, 1.);
                
                dest_N = normalize(cross(V2, V1));
            }
            
            vec3 edge_dir_3d = normalize(p2_3d - p1_3d);
            
            N_local = normalize(cross(dest_N, edge_dir_3d));
            
            plane_D_local = 0.5*dot(N_local, p1_3d + p2_3d);
            
            {
                vec2 orig_2d = (ray_O_2d + offset) / scale;
                
                ray_O_3d.z = plane_D_local / dot(vec3(orig_2d, 1), N_local);
                
                ray_O_3d.xy = ray_O_3d.z * orig_2d;
            }
        }
        
        // Use the plane defined by ray_O_3d and N_local
        // Can use any 2D vectors for the angle sweep
        
        if (texel_num == 0 || texel_num == 15) {
            vec2 dir = read_point(point_index_adjacent, data_offset, decode_scale, decode_offset);
            
            dir -= texel_num == 0 ? p1 : p2;
            
            if (dot(dir, N2d_edge) > 0.) {
                float a = atan(dot(dir, N2d_edge), -dot(dir, V2d_edge));
                
                if (texel_num == 0) {
                    min_rel_angle = max(0., a);
                } else {
                    max_rel_angle = min(PI, a);
                }
            }
        }
    }

    vec2 V_2d;
    
    {
        float a = min_rel_angle + 1./float(AO_DIR_SAMPLE_COUNT) * 0.5 * (max_rel_angle - min_rel_angle);
        
        V_2d = -cos(a)*V2d_edge + sin(a)*N2d_edge;
    }

    float t = 0.;
    float angle_num = 0.;
    vec4 total = vec4(0); // computing 4 sums (maybe switch to 3 later)
    
    // Initial value is the point for the vector pointing straight towards the opening ("straight up")
    vec3 prev_point = ray_O_3d;
    
    const float EPS = 1e-6;
    
    float max_dist = 0.;
    
    int itr_max = min(0, iFrame) + AO_DIR_SAMPLE_COUNT*32;
    
    // Use a single loop that iterates over both the 32 sampled directions and the grid cells
    // (might help avoid performance issues due to divergence, but I haven't actually tested it with nested
    //   loops, and anyway performance isn't really a concern here since it's only done in the first frame)
    
    for (int i = 0; i < itr_max; i++) {
        vec2 uv = ray_O_2d + t*V_2d;
        bool end = false;

        if (uv.x < -EPS || uv.y < -EPS || uv.x > tex_dim.x+EPS || uv.y > tex_dim.y+EPS) {
            end = true;
            t = 0.;
        }
        
        if ( ! end) { // continue 2D ray marching over the grid cells
            float min_dist = max(0., MIN_DISTANCE - t);
            
            vec2 xy = fract(uv);
            float t_next;
            
            {
                vec2 sd = vec2(V_2d.x < 0. ? -1. : 1., V_2d.y < 0. ? -1. : 1.); // sign(V_2d) doesn't work because we need it to be non-zero
                vec2 s = (0.5 + sd*0.5 - xy) / V_2d;
                
                t_next = min(s.x, s.y) + 0.0001;
            }

            float t2;
            
            bool inside = intersect_test_cutout_grid_cell(tex_offset + ivec2(uv), xy, V_2d, t_next, t2);
            
            if (t2 < min_dist) t2 = 1e20;

            if ( ! inside && min_dist == 0.) {
                end = true;
                t = 0.;
            } else if (t2 < 1e18) {
                t += t2;
                end = true;
            } else {
                t += t_next;
            }
        }
        
        if (end) { // finished ray marching for one direction
            if (t < 0. || t > 1e18) {
                t = 0.;
            }
        
            vec3 P;
            
            if (t > 0.) {
                vec2 P_end = 1./scale*(ray_O_2d + t*V_2d + offset); // Could use "uv" here but that probably costs registers
                
                // Get 3D coordinate for this point restricting it to the local plane
                
                P.z = plane_D_local / dot(N_local, vec3(P_end, 1.));
                P.xy = P.z * P_end;
            } else {
                P = ray_O_3d;
            }
            
            // Perform a step of the analytical integration (for this polygon edge)
            // Do it 4 times since we are computing irradiance for 4 different depths.
            
            if (P != prev_point) {
                vec3 P0 = ray_O_3d + depths.x*N_local;
                total.x += get_diff_poly_sum(prev_point - P0, P - P0, dest_N);
                P0 = ray_O_3d + depths.y*N_local;
                total.y += get_diff_poly_sum(prev_point - P0, P - P0, dest_N);
                P0 = ray_O_3d + depths.z*N_local;
                total.z += get_diff_poly_sum(prev_point - P0, P - P0, dest_N);
                P0 = ray_O_3d + depths.w*N_local;
                total.w += get_diff_poly_sum(prev_point - P0, P - P0, dest_N);
                
                prev_point = P;
            }
            
            if (angle_num == float(AO_DIR_SAMPLE_COUNT) - 1.) break;
            
            angle_num += 1.;
            
            {
                float a = min_rel_angle + 1./float(AO_DIR_SAMPLE_COUNT) * (angle_num + 0.5) * (max_rel_angle - min_rel_angle);
                
                V_2d = -cos(a)*V2d_edge + sin(a)*N2d_edge;
            }
            
            t = 0.;
        }
    }
    
    // Finish analytical integration for the 4 depths
    
    if (ray_O_3d != prev_point) {
        // handle last line segment as prev_point -> ray_O_3d
        vec3 P0 = ray_O_3d + depths.x*N_local;
        total.x += get_diff_poly_sum(prev_point - P0, ray_O_3d - P0, dest_N);
        P0 = ray_O_3d + depths.y*N_local;
        total.y += get_diff_poly_sum(prev_point - P0, ray_O_3d - P0, dest_N);
        P0 = ray_O_3d + depths.z*N_local;
        total.z += get_diff_poly_sum(prev_point - P0, ray_O_3d - P0, dest_N);
        P0 = ray_O_3d + depths.w*N_local;
        total.w += get_diff_poly_sum(prev_point - P0, ray_O_3d - P0, dest_N);
    }
    
    total *= -0.5 / PI;

    // Encode the irradiance and the surface normal
    
    // Maximum value is 0.5, so we multiply by 2 during encoding
    
    {
        ivec4 v = ivec4(clamp(floor(256.*total), 0., 127.));
        
        int enc0 = encode_14bits(v.x | (v.y<<7));
        int enc1 = encode_14bits(v.z | (v.w<<7));
        
        vec2 noct = octahedral_encode(dest_N*vec3(1,1,-1));
        
        return vec4(intBitsToFloat(enc0), intBitsToFloat(enc1), noct);
    }
}

// Clip a 3D line to the pyramid (?) formed by the destination surface point and the area light
// return the 2D end points for the line segment projected onto the light.
// We remember which sides of the pyramid the line was clipped to.
// This is similar to clipping during 3D rasterization.
// In some cases, also test if the line crosses the extra shadow-casting "fin" that we need to consider

bool clip_line3d(bool fin_applicable, bool fin_shadow_backward, vec3 N_fin, vec3 p_dest, vec3 p1, vec3 p2, out int clip_p1, out int clip_p2, out vec2 proj1, out vec2 proj2,
                 out bool crossed_plane, inout vec3 p_plane) {
            
    clip_p1 = 0;
    clip_p2 = 0;
    crossed_plane = false;
    
    if (fin_applicable) {
        vec3 gap = p2 - p1;
        
        float d = dot(gap, N_fin);
        
        float t = dot(p_dest - p1, N_fin) / d;
        
        if ( ! fin_shadow_backward) {
            if (d >= -1e-8) return false;
            
            if (t >= 1.) return false;
            
            crossed_plane = true;
            p_plane = p1 + t*gap;

            p1 = p_plane;
        } else {
            
            if (t > 0. && t < 1.) {
                crossed_plane = true;
                p_plane = p1 + t*gap;

                p2 = p_plane;
            }
        }
    }
    
    if (p1.y < p_dest.y + 0.0001 && p2.y < p_dest.y + 0.0001) {
        return false;
    }
    
    {
        const float CLIP_Y = 0.;
        
        float m = p1.y - p2.y;
        
        if (abs(m) > 1e-8) {
            float ytest = p1.y - p_dest.y - CLIP_Y;
            float y_inter = ytest / m;
            
            if (ytest < 0.) {
                p1.xz = p1.xz + y_inter * (p2.xz - p1.xz);
                //p1.y = p_dest.y + CLIP_Y;
                p1.y = p_dest.y;
            } else if (p2.y - p_dest.y < CLIP_Y) {
                p2.xz = p1.xz + y_inter * (p2.xz - p1.xz);
                //p2.y = p_dest.y + CLIP_Y;
                p2.y = p_dest.y;
            }
        }
    }
    
    float t1 = 0.;
    float t2 = 1.;
    vec3 d = p2 - p1;

    {
        float A = 1. - p_dest.y;
        float B = p_dest.x - 0.4;
        float C = 0.4*p_dest.y - p_dest.x;
        
        float m = A*d.x + B*d.y;
        
        if (abs(m) > 1e-8) {
            float t = -(A*p1.x + B*p1.y + C) / m;

            if (dot(d.xy, vec2(A,B)) > 0.) {
                if (t > t1) {
                    clip_p1 = 1;
                    t1 = t;
                }
            } else {
                if (t < t2) {
                    clip_p2 = 1;
                    t2 = t;
                }
            }
        }
    }

    {
        float A = 1. - p_dest.y;
        float B = p_dest.x - 0.6;
        float C = 0.6*p_dest.y - p_dest.x;
        
        float m = A*d.x + B*d.y;
        
        if (abs(m) > 1e-8) {
            float t = -(A*p1.x + B*p1.y + C) / m;

            if (dot(d.xy, vec2(A,B)) < 0.) {
                if (t > t1) {
                    clip_p1 = 3;
                    t1 = t;
                }
            } else {
                if (t < t2) {
                    clip_p2 = 3;
                    t2 = t;
                }
            }
        }
    }

    {
        float A = 1. - p_dest.y;
        float B = p_dest.z - 0.4;
        float C = 0.4*p_dest.y - p_dest.z;
        
        float m = A*d.z + B*d.y;
        
        if (abs(m) > 1e-8) {
            float t = -(A*p1.z + B*p1.y + C) / m;

            if (dot(d.zy, vec2(A,B)) > 0.) {
                if (t > t1) {
                    clip_p1 = 4;
                    t1 = t;
                }
            } else {
                if (t < t2) {
                    clip_p2 = 4;
                    t2 = t;
                }
            }
        }
    }
    
    {
        float A = 1. - p_dest.y;
        float B = p_dest.z - 0.6;
        float C = 0.6*p_dest.y - p_dest.z;
        
        float m = A*d.z + B*d.y;
        
        if (abs(m) > 1e-8) {
            float t = -(A*p1.z + B*p1.y + C) / m;

            if (dot(d.zy, vec2(A,B)) < 0.) {
                if (t > t1) {
                    clip_p1 = 2;
                    t1 = t;
                }
            } else {
                if (t < t2) {
                    clip_p2 = 2;
                    t2 = t;
                }
            }
        }
    }
    
    if (t1 >= t2) return false;
    
    p2 = p1 + t2*d;
    p1 = p1 + t1*d;
    
    proj1 = p_dest.xz;
    proj2 = p_dest.xz;
    
    if (abs(p1.y - p_dest.y) > 1e-8) proj1 += (1. - p_dest.y) / (p1.y - p_dest.y) * (p1.xz - p_dest.xz);
    if (abs(p2.y - p_dest.y) > 1e-8) proj2 += (1. - p_dest.y) / (p2.y - p_dest.y) * (p2.xz - p_dest.xz);
    
    return true;
}

// Function for summing values for integrating the irradiance
float seg_irradiance(vec2 p1, vec2 p2, vec3 p_dest, vec3 N_dest) {
    return get_diff_poly_sum(vec3(p1.x, 1, p1.y) - p_dest, vec3(p2.x, 1, p2.y) - p_dest, N_dest);
}

float encode_14_bits(uint u) {
    u = (u << 13) & 0x7ffe000u;
    u += u <= 0x007fe000u ? 0x40000000u : 0x38000000u;
        
    return uintBitsToFloat(u);
}

float encode_30_bits(uint u) {
    if (u <= 0x7fffffu) u += 0x40000000u;
        
    return uintBitsToFloat(u);
}

/*
    This function does all the work of sampling (including bisection to find 0 and 1 points, and
    extra samples to estimate slopes) and walking along the cutout edge points to get analytical
    area. It also encodes the final Hermite spline approximation for the shadow fraction function.
*/

vec4 area_light_cutout_shadow_frac(vec3 P_dest0, vec3 P_dest1, vec3 N_dest, vec3 center, float scale, 
                                   float unshadowed_cutoff, ivec2 loop, int point_index, int fin_index, bool backward) {
    vec3 p_fin;
    bool fin_shadow_backward = false;
    bool fin_shadow_forward = false;
    
    // If this part of the edge has a "fin" (a concave vertex that may cast a shadow) get some data about it.
    if (fin_index >= 0) {
        p_fin = center + scale * texelFetch(iChannel0, TX_OFFSET + ivec2(fin_index & 15, fin_index >> 4), 0).xyz;
        
        int i = backward ? fin_index - 1 : fin_index + 1;
        vec3 p = center + scale * texelFetch(iChannel0, TX_OFFSET + ivec2(i & 15, i >> 4), 0).xyz;
        
        vec3 N = normalize(cross(backward ? p - center : center - p_fin, p_fin - p));
        vec3 V = normalize(p_fin - 0.5*(P_dest0 + P_dest1));
        
        bool b = dot(N, V) > 0.;
        
        if (backward) fin_shadow_backward = b;
        else fin_shadow_forward = b;
    } else {
        p_fin = vec3(0);
    }
    
    // Need to remember positions for at most two intersection points on each side of the area light square.

    bool any_found;
    
    float irradiance;
    float lefta_1 = 1.;
    float lefta_2 = 0.;
    float leftb_1 = 1.;
    float leftb_2 = 0.;

    float righta_1 = 1.;
    float righta_2 = 0.;
    float rightb_1 = 1.;
    float rightb_2 = 0.;

    float topa_1 = 1.;
    float topa_2 = 0.;
    float topb_1 = 1.;
    float topb_2 = 0.;

    float bottoma_1 = 1.;
    float bottoma_2 = 0.;
    float bottomb_1 = 1.;
    float bottomb_2 = 0.;

    vec3 next_p;
    int index = -1;
    int state = 0;
    float p_current = INITIAL_P1;
    vec3 P_dest;

    float final_p0, final_v0, final_m0;
    float final_p1=1., final_v1=1., final_m1 = 0.;
    float p_lower_bound;
    float p_upper_bound;
    float p1_lower_bound;
    float final_v_low, final_m_low;
    float final_v_high, final_m_high;
    
    bool fin_applicable, crossed_plane;
    bool blocking;
    vec3 N_fin, p_plane;
    
    for (int itr = min(0, iFrame); itr < 250; itr++) {
        if (index < 0) {
            // Set up for restarting integration (traversing the edge points)
            
            P_dest = mix(P_dest0, P_dest1, p_current);
            N_fin = normalize(cross(p_fin-P_dest, p_fin-center));

            irradiance = 0.;
            lefta_1 = 1.;
            lefta_2 = 0.;
            leftb_1 = 1.;
            leftb_2 = 0.;

            righta_1 = 1.;
            righta_2 = 0.;
            rightb_1 = 1.;
            rightb_2 = 0.;

            topa_1 = 1.;
            topa_2 = 0.;
            topb_1 = 1.;
            topb_2 = 0.;

            bottoma_1 = 1.;
            bottoma_2 = 0.;
            bottomb_1 = 1.;
            bottomb_2 = 0.;

            any_found = false;
            fin_applicable = fin_shadow_backward;
            crossed_plane = false;
            blocking = false;
            
            index = loop.x;
        }
        
        // If we crossed the plane for a "fin" in the previous iteration, we process the fin's projected
        //      line segment here instead of getting the next edge segment
        
        bool skip;
        vec3 p, prev_p;
        
        if ( ! crossed_plane) {
            {
                int i = index;
                
                if (i == loop.y && (loop.x == 3 || loop.x == 2*21 + 92 + 59)) i = loop.x;
                
                // Fetch the 3D coordinate of the next edge vertex
                
                p = center + scale * texelFetch(iChannel0, TX_OFFSET + ivec2(i & 15, i >> 4), 0).xyz;
            }
            
            prev_p = next_p;
            next_p = p;
            
            skip = index == loop.x;
            
            if ( ! skip) {
                if (fin_shadow_forward) {
                    if (index == fin_index + 1) {
                        fin_applicable = true;
                        skip = true;
                    }
                } else if (fin_shadow_backward) {
                    if (index == fin_index) {
                        blocking = false;
                        fin_applicable = false;
                        skip = true;
                    }
                    
                    if (blocking) skip = true;
                }
            }
        } else {
            skip = false;
            prev_p = fin_shadow_backward ? p_plane : p_fin;
            p = fin_shadow_backward ? p_fin : p_plane;
        }
        
        if ( ! skip) {
            {
                int clip1, clip2;
                vec2 p1, p2;
                
                bool ok = clip_line3d(fin_applicable && ! crossed_plane, fin_shadow_backward, N_fin, P_dest, prev_p, p, clip1, clip2, p1, p2, crossed_plane, p_plane);
                
                if (ok) {
                    any_found = true;
                    
                    if (clip1 != 0) {
                        if (clip1 == 1) {
                            float k = 1./0.2 * (p1.y - 0.4);
                            lefta_1 = min(lefta_1, k);
                            lefta_2 = max(lefta_2, k);
                            p1.x = 0.4;
                        } else if (clip1 == 2) {
                            float k = 1./0.2 * (p1.x - 0.4);
                            topa_1 = min(topa_1, k);
                            topa_2 = max(topa_2, k);
                            p1.y = 0.6;
                        } else if (clip1 == 3) {
                            float k = 1. - 1./0.2 * (p1.y - 0.4);
                            righta_1 = min(righta_1, k);
                            righta_2 = max(righta_2, k);
                            p1.x = 0.6;
                        } else {
                            float k = 1. - 1./0.2 * (p1.x - 0.4);
                            bottoma_1 = min(bottoma_1, k);
                            bottoma_2 = max(bottoma_2, k);
                            p1.y = 0.4;
                        }
                    }
                    
                    if (clip2 != 0) {
                        if (clip2 == 1) {
                            float k = 1./0.2 * (p2.y - 0.4);
                            leftb_1 = min(leftb_1, k);
                            leftb_2 = max(leftb_2, k);
                            p2.x = 0.4;
                        } else if (clip2 == 2) {
                            float k = 1./0.2 * (p2.x - 0.4);
                            topb_1 = min(topb_1, k);
                            topb_2 = max(topb_2, k);
                            p2.y = 0.6;
                        } else if (clip2 == 3) {
                            float k = 1. - 1./0.2 * (p2.y - 0.4);
                            rightb_1 = min(rightb_1, k);
                            rightb_2 = max(rightb_2, k);
                            p2.x = 0.6;
                        } else {
                            float k = 1. - 1./0.2 * (p2.x - 0.4);
                            bottomb_1 = min(bottomb_1, k);
                            bottomb_2 = max(bottomb_2, k);
                            p2.y = 0.4;
                        }
                    }
                    
                    // perform integration step
                    
                    irradiance += seg_irradiance(p1, p2, P_dest, N_dest);
                }
            }
                
            if (crossed_plane) {
                fin_applicable = false;
                blocking = fin_shadow_backward;
                index--;
            }
        }
        
        if (++index > loop.y) {
            // After finishing the loop, check if any segments were found
            // Process any (projected) intersections with the bounding square of the area light.
            
            float v_final = 0.;
        
            if ( ! fin_applicable && ! any_found) {
                v_final = p_current < unshadowed_cutoff ? 0. : 1.;
            } else if (! fin_applicable) {
                // AT MOST 4 EDGES ARE ADDED HERE, OUT OF 12 (OR 8) POSSIBLE

                if (lefta_1 < leftb_1) irradiance += seg_irradiance(vec2(0.4, 0.4), vec2(0.4, 0.4 + 0.2*lefta_1), P_dest, N_dest);
                if (leftb_1 < 1.) irradiance += seg_irradiance(vec2(0.4, 0.4 + 0.2*leftb_1), vec2(0.4, 0.4 + 0.2*(lefta_1 > leftb_1 ? lefta_1 : lefta_2 > leftb_1 ? lefta_2 : 1.)), P_dest, N_dest);
                //if (leftb_2 > leftb_1) irradiance += seg_irradiance(vec2(0.4, 0.4 + 0.2*leftb_2), vec2(0.4, 0.4 + 0.2*(lefta_2 > leftb_2 ? lefta_2 : 1.)), P_dest, N_dest); // not needed

                if (righta_1 < rightb_1) irradiance += seg_irradiance(vec2(0.6, 0.6), vec2(0.6, 0.6 - 0.2*righta_1), P_dest, N_dest); // not needed
                if (rightb_1 < 1.) irradiance += seg_irradiance(vec2(0.6, 0.6 - 0.2*rightb_1), vec2(0.6, 0.6 - 0.2*(righta_1 > rightb_1 ? righta_1 : righta_2 > rightb_1 ? righta_2 : 1.)), P_dest, N_dest);
                //if (rightb_2 > rightb_1) irradiance += seg_irradiance(vec2(0.6, 0.6 - 0.2*rightb_2), vec2(0.6, 0.6 - 0.2*(righta_2 > rightb_2 ? righta_2 : 1.)), P_dest, N_dest); // not needed

                if (topa_1 < topb_1) irradiance += seg_irradiance(vec2(0.4, 0.6), vec2(0.4 + 0.2*topa_1, 0.6), P_dest, N_dest);
                if (topb_1 < 1.) irradiance += seg_irradiance(vec2(0.4 + 0.2*topb_1, 0.6), vec2(0.4 + 0.2*(topa_1 > topb_1 ? topa_1 : topa_2 > topb_1 ? topa_2 : 1.), 0.6), P_dest, N_dest);
                //if (topb_2 > topb_1) irradiance += seg_irradiance(vec2(0.4 + 0.2*topb_2, 0.6), vec2(0.4 + 0.2*(topa_2 > topb_2 ? topa_2 : 1.), 0.6), P_dest, N_dest); // not needed

                if (bottoma_1 < bottomb_1) irradiance += seg_irradiance(vec2(0.6, 0.4), vec2(0.6 - 0.2*bottoma_1, 0.4), P_dest, N_dest);
                if (bottomb_1 < 1.) irradiance += seg_irradiance(vec2(0.6 - 0.2*bottomb_1, 0.4), vec2(0.6 - 0.2*(bottoma_1 > bottomb_1 ? bottoma_1 : bottoma_2 > bottomb_1 ? bottoma_2 : 1.), 0.4), P_dest, N_dest);
                if (bottomb_2 > bottomb_1) irradiance += seg_irradiance(vec2(0.6 - 0.2*bottomb_2, 0.4), vec2(0.6 - 0.2*(bottoma_2 > bottomb_2 ? bottoma_2 : 1.), 0.4), P_dest, N_dest); // needed in one tiny area
                
                int missing = 0;

                if (lefta_1 == 1. && leftb_1 == 1.) missing |= 1;
                if (topa_1 == 1. && topb_1 == 1.) missing |= 2;
                if (righta_1 == 1. && rightb_1 == 1.) missing |= 4;
                if (bottoma_1 == 1. && bottomb_1 == 1.) missing |= 8;

                int propagate = 0;

                if (leftb_2 > lefta_2) propagate |= 2;
                if (topb_2 > topa_2) propagate |= 4;
                if (rightb_2 > righta_2) propagate |= 8;
                if (bottomb_2 > bottoma_2) propagate |= 1;

                propagate &= missing;
                propagate |= ((propagate << 1) | (propagate >> 3)) & missing;
                propagate |= ((propagate << 1) | (propagate >> 3)) & missing;

                // THERE IS ONE TINY PLACE WHERE 3 EDGES ARE ADDED HERE
                if ((propagate & 1) != 0) irradiance += seg_irradiance(vec2(0.4, 0.4), vec2(0.4, 0.6), P_dest, N_dest);
                //if ((propagate & 2) != 0) irradiance += seg_irradiance(vec2(0.4, 0.6), vec2(0.6, 0.6), P_dest, N_dest); // NOT NEEDED
                if ((propagate & 4) != 0) irradiance += seg_irradiance(vec2(0.6, 0.6), vec2(0.6, 0.4), P_dest, N_dest);
                if ((propagate & 8) != 0) irradiance += seg_irradiance(vec2(0.6, 0.4), vec2(0.4, 0.4), P_dest, N_dest);

                v_final = max(0., 0.5 / PI * (1./0.2 * 1./0.2) * irradiance);
            
                if (v_final != 0.) {
                    float irr_max = eval_area_light_clipped(P_dest, N_dest);
                    
                    v_final = irr_max > 0. ? clamp(v_final / irr_max, 0., 1.) : 0.;
                }
            }
            
            // Process final value and switch to new state for sampling if necessary
            //  (put next depth for sampling in p_current)

            bool state_ready = false;
            
            if (state == 0) {
                //return vec4(v_final, 0., 0., 0.);
            
                if (v_final < 0.001) {
                    final_v1 = 0.;
                    final_p1 = 1.;
                    final_v0 = 0.;
                    final_p0 = 1.;
                    
                    final_v_low = 0.;
                    final_v_high = 0.;
                    final_m_low = 0.;
                    final_m_high = 0.;
                    break;
                }
                
                final_v1 = v_final;
                final_p1 = 1.;
            } else if (state == 1) {
                final_v0 = v_final;
                final_p0 = 0.;
            } else if (state == 2) {
                final_m0 = (v_final - final_v0) / SLOPE_TEST_GAP;
            } else if (state == 3) {
                final_m1 = (final_v1 - v_final) / SLOPE_TEST_GAP;
            } else if (state == 4) {
                if (v_final <= 0.0001) {
                    p_lower_bound = p_current;
                } else {
                    p_upper_bound = p_current;
                }
            } else if (state == 5) {
                if (v_final < 0.9999) {
                    p_lower_bound = p_current;
                } else {
                    p_upper_bound = p_current;
                }
            } else if (state == 6) {
                final_v_low = v_final;
                state = 7;
                p_current = mix(final_p0, final_p1, P_LOW) + 0.5*SLOPE_TEST_GAP;
                state_ready = true;
            } else if (state == 7) {
                final_m_low = (v_final - final_v_low) / SLOPE_TEST_GAP;
                final_v_low = 0.5*(v_final + final_v_low);
                state = 8;
                p_current = mix(final_p0, final_p1, P_HIGH) - 0.5*SLOPE_TEST_GAP;
                state_ready = true;
            } else if (state == 8) {
                final_v_high = v_final;
                state = 9;
                p_current = mix(final_p0, final_p1, P_HIGH) + 0.5*SLOPE_TEST_GAP;
                state_ready = true;
            } else {
                final_m_high = (v_final - final_v_high) / SLOPE_TEST_GAP;
                final_v_high = 0.5*(v_final + final_v_high);
                break;
            }
            
            if (state == 4 || state == 5) {
                float p = 0.5*(p_lower_bound + p_upper_bound);
                
                if (p_upper_bound - p_lower_bound < 0.005) {
                    if (state == 4) {
                        final_v0 = 0.;
                        final_m0 = 0.;
                        final_p0 = min(0.98, p);
                    } else {
                        final_v1 = 1.;
                        final_m1 = 0.;
                        final_p1 = p;
                    }
                } else {
                    p_current = p;
                    state_ready = true;
                }
            }
            
            if (state_ready) {
                // keep state
            } else if (state == 0) {
                state = 1;
                p_current = 0.;
            } else if (state == 1 && final_v0 > 0.001) {
                state = 2;
                p_current = SLOPE_TEST_GAP;
            } else if (state <= 2 && final_v1 < 0.999) {
                state = 3;
                p_current = INITIAL_P1 - SLOPE_TEST_GAP;
            } else if (state <= 3 && final_v0 <= 0.001) {
                final_m0 = 0.;
                state = 4;
                p_lower_bound = 0.;
                p_upper_bound = 1.;
                p_current = 0.5;
            } else if (state <= 4 && final_v1 >= 0.9995) {
                state = 5;
                p_lower_bound = 0.;
                p_upper_bound = 1.;
                p_current = 0.5;
            } else {
                state = 6;
                p_current = mix(final_p0, final_p1, P_LOW) - 0.5*SLOPE_TEST_GAP;
            }
            
            index = -1;
        }
    }
    
    // Encode the Hermite spline approximation
    
    {
        float p0 = final_p0;
        float p1 = final_p1;
        float v0 = final_v0;
        float v1 = final_v1;
        float v_low = final_v_low;
        float v_high = final_v_high;
        
        bool start_at_0 = p0 == 0.;
        bool end_at_1 = p1 == 1.;
        
        vec4 encoded = vec4(encode_14_bits(uint(clamp(128.*(start_at_0 ? v0 : p0), 0., 127.)) | (uint(clamp(128.*(end_at_1 ? v1 : p1), 0., 127.)) << 7)),
                            encode_14_bits(uint(clamp(128.*v_low, 0., 127.)) | (uint(clamp(128.*v_high, 0., 127.)) << 7)), 0, 0);
        
        if (start_at_0) encoded.x = -encoded.x;
        if (end_at_1) encoded.y = -encoded.y;
    
        float p_low = mix(final_p0, final_p1, P_LOW);
        float p_high = mix(final_p0, final_p1, P_HIGH);
        
        float m0 = (p_low - final_p0) * final_m0;
        float m1 = (p_high - p_low) * final_m1;
        float m_low = (p_high - p_low) * final_m_low;
        float m_high = (final_p1 - p_high) * final_m_high;
        
        {
            uint bits3, bits4;
            
            if (start_at_0 && end_at_1) {
                bits3 = uint(clamp(128./MAX_M0 * m0, 0., 127.)) | (uint(clamp(128./MAX_M1 * m1, 0., 127.)) << 7);
                bits4 = uint(clamp(128./MAX_M_LOW * m_low, 0., 127.)) | (uint(clamp(128./MAX_M_HIGH * m_high, 0., 127.)) << 7);
            } else {
                uint b = uint(clamp(512./MAX_M_LOW * m_low, 0., 511.));
                
                bits3 = uint(clamp(start_at_0 ? 512./MAX_M0 * m0 : 512./MAX_M1 * m1, 0., 511.)) | ((b << 9) & 0x3e00u);
                bits4 = (b >> 5) | (uint(clamp(512./MAX_M_HIGH * m_high, 0., 511.)) << 4);
            }
            
            encoded.z = encode_14_bits(bits3);
            encoded.w = encode_14_bits(bits4);

            bool w_high_bit = false;

            {
                uint u = uint(clamp(256.*(start_at_0 ? v0 : p0), 0., 255.)) | (uint(clamp(128.*(end_at_1 ? v1 : p1), 0., 127.)) << 8);
                
                encoded.x = encode_14_bits(u);
                
                if (start_at_0) encoded.x = -encoded.x;
                
                w_high_bit = (u & 0x4000u) != 0u;
            }
            
            if (w_high_bit) encoded.z = -encoded.z;
        }
        
        return encoded;
    }
}

vec4 compute_direct_light_shadow(int point_index, float edge_texture_pos) {
    // Figure out whether this particular edge segment can have direct light,
    //   and which other edge segments we need to traverse to compute the shadowing
    
    int pk_index;
    
    if (point_index < CUTOUT_POINT_COUNT1) {
        pk_index = 0;
    } else if (point_index < 2*CUTOUT_DATA_OFFSET_PACKED2 + CUTOUT_POINT_COUNT2) {
        pk_index = 1;
    } else {
        pk_index = 2;
    }
    
    // TODO: use point_index instead, to avoid wasting a register 
    int index = point_index;
    
    {
        bool skip = false;
        
        if (pk_index == 0) {
            skip = index < 3 || index >= 6;
        } else if (pk_index == 1) {
            index -= 2*21;
            
            if (index >= 0 && index < 92) {
                skip = ((index < 32 ? 263443401 : index < 64 ? 15902 : 377344) & (1 << (index&31))) == 0;
            } else {
                skip = true;
            }
        } else {
            index -= 2*21 + 92;
            skip = true;
            if ((index >= 8 && index < 16) || index==59 || (index >= 81 && index < 93)) skip = false;
        }
            
        if (skip) return uintBitsToFloat(uvec4(1075830784u, 3221225472u, 1073741824u, 1073741824u));
    }
    
    ivec2 loop;
    vec3 center;
    float scale;
    
    if (pk_index == 0) {
        loop = ivec2(3, 6);
        
        center = PUMPKIN1_OFFSET;
        scale = PUMPKIN1_SCALE;
    } else if (pk_index == 1) {
        if (index < 9) {
            loop = ivec2(0, 9);
        } else if (index < 18) {
            loop = ivec2(9, 18);
        } else if (index < 28) {
            loop = ivec2(18, 28);
        } else if (index < 37) {
            loop = ivec2(28, 37);
        } else if (index < 46) {
            loop = ivec2(37, 46);
        } else {
            loop = ivec2(64, 92);
        }
        
        loop += 2*21;
        
        center = PUMPKIN2_OFFSET;
        scale = PUMPKIN2_SCALE;
    } else {
        if (index < 59) loop = 2*21 + 92 + ivec2(0, 16);
        else loop = 2*21 + 92 + ivec2(59, 93);
        
        center = PUMPKIN3_OFFSET;
        scale = PUMPKIN3_SCALE;
    }
    
    vec3 N, P0, P1;
    
    {
        int point_index2 = point_index + 1 >= loop.y ? loop.x : point_index + 1;
        
        vec4 data1 = texelFetch(iChannel0, TX_OFFSET + ivec2(point_index & 15, point_index >> 4), 0);
        vec4 data2 = texelFetch(iChannel0, TX_OFFSET + ivec2(point_index2 & 15, point_index2 >> 4), 0);
        
        N = normalize(cross(data1.xyz, data2.xyz - data1.xyz));
        
        vec4 data = mix(data1, data2, fract(edge_texture_pos));
        
        P0 = center + scale * data.w * data.xyz;
        P1 = center + scale * data.xyz;
    }
    
    int fin_index = -1000;
    bool backward = false;
    
    if (pk_index == 1) {
        loop.y -= 1;
        
        if (loop.x == 2*21 + 0) {
            loop = 2*21 + ivec2(1, 7);
            
            if (index==7 || index==8) fin_index = 2*21 + 3;
        } else if (loop.x == 2*21 + 9) {
            loop = 2*21 + ivec2(9, 16);
            if (index==9+7 || index==9+8) fin_index = 2*21 + 9 + 3;
        } else if (loop.x == 2*21 + 2*9) {
            loop = 2*21 + ivec2(18, 25);
            
            if (index==2*9 + 6 || index==2*9 + 5) {
                fin_index = 2*21 + 2*9 + 4;
                backward = true;
            }
        } else if (loop.x == 2*21 + 6*9 + 10) {
            loop = 2*21 + ivec2(72, 82);
            
            if (index == 6*9 + 10 + 18) {
                backward = edge_texture_pos <= 0.5;
                fin_index = backward ? 2*21 + 6*9+10 + 17 : 2*21 + 6*9 + 10 + 9;
            }
        }
    } else if (pk_index == 2) {
        if (loop.x == 2*21 + 92) {
            loop = 2*21 + 92 + ivec2(0, 8);
        } else {
            if (index == 59 || index == 90 || index == 91 || index == 92) loop = 2*21 + 92 + ivec2(60, 63);
            else loop = 2*21 + 92 + ivec2(62, 67);
        }
    }
    
    float unshadowed_cutoff = 2.;
    
    if (pk_index == 1) {
        if (index==9+6 || index==9+7 || index==9+8) unshadowed_cutoff = 0.;
        else if (index==2*9+10 + 5 || index==2*9+10 + 6) unshadowed_cutoff = index==2*9+10 + 5 ? 1. - 0.1*edge_texture_pos : 0.9;
    } else if (pk_index == 2) {
        if (index >= 10 && index < 16) {
            unshadowed_cutoff = index == 15 ? 1. - 0.5*(1. - edge_texture_pos) : 0.8;
        } else if (index == 90) {
            unshadowed_cutoff = 0.95;
        }
    }
    
    return area_light_cutout_shadow_frac(P0, P1, N, center, scale, unshadowed_cutoff, loop, index, fin_index, backward);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Quickly skip unused portion of the buffer
    if (fragCoord.y >= 32. || fragCoord.x >= 256.) {
        fragColor = vec4(0);
        return;
    }
    
    if (iFrame != 0) {
        fragColor = texelFetch(iChannel1, ivec2(fragCoord),0);
        return;
    }
    
    // Determine which edge point we're generating data for, and
    //   which type of data we're generating
    
    int point_index, texel_num;
    
    {
        ivec2 c = ivec2(fragCoord);
        
        point_index = (c.x >> 1) + ((c.y & 8) << 4);
        texel_num = (c.y & 7) + 8 * (c.x & 1);
    }
    
    if (point_index == CUTOUT_POINT_COUNT1 || point_index == 2*CUTOUT_DATA_OFFSET_PACKED3 + CUTOUT_POINT_COUNT3) {
        fragColor = vec4(0);
        return;
    }

    if (fragCoord.y < 16.) {
        fragColor = compute_AO(point_index, texel_num);
    } else {
        fragColor = compute_direct_light_shadow(point_index, 0.005 + 1./15.15 * float(texel_num));
    }
}
