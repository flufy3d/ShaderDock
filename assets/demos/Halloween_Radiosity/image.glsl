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
    
    This shader performs ray tracing (or ray casting at least) and ray 
    marching to find the surface for each pixel, and uses data from Buffers 
    A-D to compute lighting outside the pumpkins.
        
    For the pumpkins and stalks, it uses a ray marcher somewhat similar to a 
    typical SDF ray marcher, but it uses a fixed minimum step size and takes 
    larger steps when safe. It also uses second order data (directional 
    derivative) to detect when it needs to take smaller steps to avoid 
    stepping over a possible intersection. After finding a point inside the 
    shape, it uses bisection to find a point close to the surface, with a 
    final regula falsi step. It ray marches the shapes sequentially, one shape 
    at a time (unlike a typical Shadertoy ray marcher), using a single loop 
    with more state information that a typical ray marching loop. I don't know 
    if this is really a good idea - maybe at least keeping stalk and pumpkin 
    ray marching separate would be better.
        
    To find intersections with the cutout edges, it uses a 2D ray marcher. 3D 
    points (or 3D rays) are projected into 2D using a transformation similar 
    to perspective projection (the lines through the corners of the shapes 
    converge at the center of the pumpkin). 2D ray marching is done on a grid 
    of cells that was prepared in Buffer A. Each cell can contain at most two 
    line segments. The complicated part about the ray marching is that it also 
    finds the distance to the closest point on the edge (for the initial 
    intersection with the pumpkin surface), which potentially requires 
    checking multiple adjacent cells. (Maybe this is a bad idea and it should 
    be done separately.) Originally I was using this distance information to 
    construct an SDF which I then modulated with noise to make the edges of 
    the cutouts irregular. I think this probably made the image more 
    realistic, but it caused too much aliasing when zoomed out, and it looked 
    worse than clean edges when zoomed in, so I took it out. Now the distance 
    data is used only for antialiasing (only for some of the edges, but it 
    helps).
        
    Inside the pumpkins, the lighting is fairly simple and is approximated by 
    polynomials or rational functions. Ambient occlusion data from Buffer D is 
    used for lighting on the edges of the cutout shapes.
        
    The code in mainImage tries to unify the lighting lookup and computations 
    for direct and indirect light as much as possible (use same code for all 
    surfaces) to reduce divergence and compilation time.
        
    Direct lighting on the edges of the cutouts is special (requires using the 
    shadowing fraction functions in Buffer D). This lighting is anti-aliased 
    by integrating sections of the Hermite spine multiplied by a cheap 
    quadratic kernel, which helped reduce some of the most annoying aliasing 
    when zoomed out.
        
    The edges of the area light are antialiased but nothing else (aside from 
    the cutout edges as mentioned above). Box corners could all be antialiased 
    in the Image shader, but this would probably make the code a lot more 
    complicated because (among other things) the lighting would need to be 
    evaluated for multiple surface normals and blended, and I didn't want to 
    increase the compilation time further. (I could also free up a buffer and 
    use something like FXAA or TAA, but I don't want to do that, for various 
    reasons.)
        
    
    
*/

const float VIEW_ANGLE_FACTOR = 2.; // Lower value means wider FOV
const float CAMERA_Z = -2.;         // Values >= 0. are not supported. Values > -0.5 may cause unexpected clipping


vec3 LINEAR_TO_SRGB(vec3 C) {
    // Note: this is a direct translation of the sRGB definition into branch-less GLSL (other people's code likely looks similar)
    return mix(12.92*C, 1.055*pow(C, vec3(1./2.4)) - 0.055, step(0.0031308, C));
}

float rgb_to_luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// tone map luminance while preserving hue
vec3 tone_map_and_gamut_clip(vec3 rgb) {
    float a = max(rgb_to_luminance(rgb), 0.);
    
    // "boring" tone mapper that tries to keep the lower values linear
    {
        float k = (log(exp(TONE_MAP_BETA) - 1.)) / TONE_MAP_BETA;
    
        a = 1. - log(1. + exp(TONE_MAP_BETA*(k - a))) / TONE_MAP_BETA;
    }
    
    if (a < 0.001) return vec3(0);
    
    rgb = max(rgb, vec3(0));
    
    rgb /= max(max(rgb.r, rgb.g), rgb.b); // can't be all 0s, because then a < 0.001
    
    float b = min(rgb_to_luminance(rgb), 0.9999);
    
    return max((rgb - b) * (a <= b ? a / b : (1. - a) / (1. - b)) + a, vec3(0));
}

// Hash function used for animating the candle flames

#define HASH_SEED 0x584419acu
#define HASH_EXTRACT_VEC4(H) (1./255. * vec4(uvec4((H), (H)>>8, (H)>>16, (H)>>24) & 0xffu))

uint hash_fn1(uint h) { // fmix32 with added constant for seed
    h ^= h >> 16; 
    
    h = h*0x85ebca6bu + HASH_SEED;
    
    h ^= h >> 13;
    
    h = h*0xc2b2ae35u;
    
    return h ^ (h >> 16);
}

mat3 make_camera_rotation_matrix(vec2 angles) {
    float sin_xz = sin(angles.x);
    float cos_xz = cos(angles.x);
    float cos_yz = cos(angles.y);
    float sin_yz = sin(angles.y);
    
    // (normalize is for precision loss only)
    vec3 dir_x = normalize(vec3(cos_xz, 0, -sin_xz));
    vec3 dir_y = normalize(vec3(-sin_yz*sin_xz, cos_yz, -sin_yz*cos_xz));
    vec3 dir_z = normalize(vec3(sin_xz*cos_yz, sin_yz, cos_xz*cos_yz)); 

    return mat3(dir_x, dir_y, dir_z);
}

float intersect_sphere(vec3 C, float r, vec3 V, vec3 ray_O) {
    ray_O -= C;

    float a = dot(V, ray_O);

    float d = a*a - dot(ray_O, ray_O) + r*r;

    return d >= 0. ? -sqrt(d) - a : 1e20;
}

vec2 intersect_box(vec3 P1, vec3 P2, vec3 rV, vec3 ray_O) {
    P1 -= ray_O;
    P2 -= ray_O;
    
    vec2 tx = slab_nearfar(P1.x, P2.x, rV.x);
    vec2 ty = slab_nearfar(P1.y, P2.y, rV.y);
    vec2 tz = slab_nearfar(P1.z, P2.z, rV.z);
    
    return vec2(max(tx.r, max(ty.r, tz.r)), min(tx.g, min(ty.g, tz.g)));
}

bool test_intersect_box(vec3 P1, vec3 P2, vec3 rV, vec3 ray_O) {
    vec2 b = intersect_box(P1, P2, rV, ray_O);
    
    return b.x <= b.y;
}

// For anti-aliasing an edge, given two points on the edge, the coordinate of the pixel, and a distance
float get_edge_antialias_alpha(vec2 fragCoord, vec2 P1, vec2 P2, float blur_dist) {
    vec2 gap = fragCoord - P1.xy;
    vec2 V = normalize(P2.xy-P1.xy);
    
    return smoothstep(0., blur_dist, length(gap - dot(gap, V)*V));
}

// for finding closest point on an edge during ray marching
// returns square of distance and fractional position along the line segment
vec2 distsq_to_line_segment_and_fraction(vec2 p, vec2 p1, vec2 p2) {
    vec2 g = p2 - p1;
    
    float f = clamp(dot(p - p1, g) / dot(g, g), 0., 1.);
    
    vec2 d = p - p1 - f * g;
    
    return vec2(dot(d, d), f);
}

// Decodes the line segment(s) from the cell data
// Tests if starting point is considered "inside" the shape
// Gets relevant intersection of ray if any
// Gets closest point of ray_O to line segment, and 1D texture coordinate for that point
bool intersect_test_cutout_grid_cell(ivec2 tex_coord, vec2 ray_O, vec2 V, float min_t, float max_t, 
                                     bool need_edge_inter, inout float edge_t, inout float edge_texture_pos,
                                     bool need_closest, inout float closest_d2, inout float closest_tex_pos) {
    vec4 tex_data = texelFetch(iChannel0, tex_coord, 0);
    
    bool op_and = tex_data.x < 0.;
    bool inside = false;
    
    if (tex_data.y >= 0.) {
        inside = op_and;
    } else {
        ivec2 params_packed1 = (floatBitsToInt(tex_data.xy) >> 13) & 0x3fff;
        
        vec2 p1 = cutout_unpack_point(params_packed1.x), p2 = cutout_unpack_point(params_packed1.y), p3, p4;
        bool have_segB = tex_data.z < 0.;
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
        }
        
        bool use_t2 = false;
        
        if (need_edge_inter) {
            vec2 xy = ray_O + min_t*V;
            
            float t1;
            bool inside1;
            
            {
                float A = tri_area(xy, p1, p2);

                inside1 = A < 0.;
                
                t1 = A / dot(V, vec2(p2.y - p1.y, p1.x - p2.x));
            }
            
            if (t1 < 0.) t1 = 1e20;
        
            if (have_segB) {
                bool inside2;
                
                {
                    float A2 = tri_area(xy, p3, p4);
                    
                    inside2 = A2 < 0.;
                    
                    t2 = A2 / dot(V, vec2(p4.y - p3.y, p3.x - p4.x));
                    
                    if (t2 < 0.) t2 = 1e20;
                }
                
                if (op_and) {
                    inside = inside1 && inside2;
                } else {
                    inside = inside1 || inside2;
                    
                    inside1 = ! inside1;
                    inside2 = ! inside2;
                }
                
                if (inside1 && inside2) {
                    edge_t = min(t1, t2);
                } else if (inside1) {
                    edge_t = t1 < t2 ? 1e20 : t2;
                } else if (inside2) {
                    edge_t = t2 < t1 ? 1e20 : t1;
                } else {
                    edge_t = max(t1, t2);
                }
            } else {
                edge_t = t1;
                inside = inside1;
            }
            
            use_t2 = edge_t == t2;
            
            edge_t += min_t;
        
            if (edge_t > max_t) edge_t = 1e20;
        }
        
        if ((edge_t < 1e18 && need_edge_inter) || need_closest) {
            vec4 tex_data2 = texelFetch(iChannel0, tex_coord + ivec2(32,0), 0);
        
            if (need_closest) {
                {
                    vec2 dfrac = distsq_to_line_segment_and_fraction(ray_O, p1, p2);
                    
                    if (dfrac.x < closest_d2) {
                        closest_d2 = dfrac.x;
                        closest_tex_pos = mix(tex_data2.x, tex_data2.y, dfrac.y);
                    }
                }
                
                if (have_segB) {
                    vec2 dfrac = distsq_to_line_segment_and_fraction(ray_O, p3, p4);
                    
                    if (dfrac.x < closest_d2) {
                        closest_d2 = dfrac.x;
                        closest_tex_pos = mix(tex_data2.z, tex_data2.w, dfrac.y);
                    }
                }
            }
            
            if (edge_t < 1e18 && need_edge_inter) {
                if (use_t2) {
                    p1 = p3;
                    p2 = p4;
                    tex_data2.xy = tex_data2.zw;
                }
                
                vec2 g = p2 - p1;
                
                edge_texture_pos = mix(tex_data2.x, tex_data2.y, clamp(dot(ray_O + edge_t*V - p1, g) / dot(g, g), 0., 1.));
            }
        }
    }
    
    return inside;
}

// Ray march the 2D grid of line segments and return intersection and closest point to starting coordinate
bool ray_march_cutout_inner(vec2 tex_dim, ivec2 tex_coord_offset, vec2 ray_O, vec2 V,
                            out float t_cutout, out float texture_pos,
                            out float closest_d2, out float closest_tex_pos
                            ) {
    t_cutout = 1e20;
    texture_pos = 1e20;

    closest_d2 = 1e20;
    closest_tex_pos = 1e20;
    
    const float EPS = 1e-6;

    if (ray_O.y > tex_dim.y + (1. + EPS) || ray_O.y < -(1. + EPS) || ray_O.x < -(1. + EPS) || ray_O.x > tex_dim.x + (1. + EPS)) {
        return false;
    }
    
    // First compute a bitmask of cells that we need to visit
    
    int neighbor_mask, path_mask;
    
    {
        vec2 xy = fract(ray_O);
    
        neighbor_mask = (xy.x < 0.5 ? 0xc7 : 0xf8) & (xy.y < 0.5 ? 0x5b : 0xb6);
    
        vec2 sd = vec2(V.x < 0. ? -1. : 1., V.y < 0. ? -1. : 1.); // sign(V) doesn't work because we need it to be non-zero
        vec2 s = (0.5 + sd*0.5 - xy) / V;
        
        float next = min(s.x, s.y);
        
        float k = next + 0.0001;
        
        if (k < 1. - EPS) {
            // low 8 bits:  mask for first cell
            // next 8 bits: excluded bits for second cell
            // next 8 bits: x value mask for second cell
            // next 8 bits: y value mask for second cell
            int mask = next == s.x ? 0x123fc012 : 0xedc012c0;
            
            xy = fract(ray_O + k*V);
        
            sd = vec2(V.x < 0. ? -1. : 1., V.y < 0. ? -1. : 1.); // sign(V) doesn't work because we need it to be non-zero
            s = (0.5 + sd*0.5 - xy) / V;
            
            next = min(s.x, s.y);
            
            path_mask = mask & 0xff;
            
            if (k + next + 0.0001 < 1. - EPS) {
                // update excluded bits, possible x values and possible y values for second cell
                mask |= next == s.x ? 0x123fc000 : 0xedc01200;
                
                // compute possible values for second cell using the three masks
                path_mask |= ~mask & (mask >> 8) & (mask >> 16) & 0xff00;
            }
            
            // exclude neighbors in wrong direction
            path_mask &= V.x < 0. ? 0xc7c7 : 0xf8f8;
            path_mask &= V.y < 0. ? 0x5353 : 0xb6b6;
        }
    }
        
    neighbor_mask &= ~(path_mask | (path_mask >> 8));

    float t = 0.;
    int i_inc = min(0, iFrame) + 1;
    bool start_inside = false;
    
    // ray marching loop (equivalent to "DDA" grid ray marching I think, except for the weird bit at the beginning)
     
    for (int i = 0; i < 28; i += i_inc) {
        vec2 tex_coord = floor(ray_O + t*V);
        
        // At the beginning, we may need to check some neighboring cells before proceeding across the grid in the usual way
        // Find those cells using the bit mask
        
        bool is_side_visit = i != 0 && neighbor_mask != 0;
        
        if (is_side_visit) {
            int m = neighbor_mask;
            
            {
                int bits;
                float d;
                
                if (m < 0x08) {
                    bits = 0x07;
                    d = -1.;
                } else if (m >= 0x40) {
                    bits = 0xc0;
                    d = 0.;
                } else {
                    bits = 0x38;
                    d = 1.;
                }
                
                m &= bits;
                tex_coord.x += d;
            }
            
            {
                int bits;
                float d;
                
                if ((m & 0x49) != 0) {
                    bits = 0x49;
                    d = -1.;
                } else if ((m & 0x12) != 0) {
                    bits = 0x12;
                    d = 0.;
                } else {
                    bits = 0xa4;
                    d = 1.;
                }
            
                m &= bits;
                tex_coord.y += d;
            }
            
            neighbor_mask ^= m;
        }
        
        float t_next = 0.;
        
        if (i == 0 || neighbor_mask == 0) {
            vec2 sd = vec2(V.x < 0. ? -1. : 1., V.y < 0. ? -1. : 1.); // sign(V) doesn't work because we need it to be non-zero
            
            vec2 use_xy = is_side_visit ? fract(ray_O) : (ray_O + t*V - tex_coord);
            
            vec2 s = (0.5 + sd*0.5 - use_xy) / V;
            
            t_next = min(s.x, s.y);
            
            t_next = min(t + t_next, 1.);
        }

        bool skip = tex_coord.x < 0. || tex_coord.y < 0. || tex_coord.x >= tex_dim.x || tex_coord.y >= tex_dim.y;
        
        bool inside = false;
        
        if ( ! skip) {
            // Visit cell and check for intersections and closest points
            
            inside = intersect_test_cutout_grid_cell(tex_coord_offset + ivec2(tex_coord), ray_O - tex_coord, V, max(0., t - 0.00002), t_next + 0.00002,
                                                     ! is_side_visit && t < 1. - EPS && t_cutout > 1e18, t_cutout, texture_pos,
                                                     i == 0 || is_side_visit || path_mask != 0, closest_d2, closest_tex_pos);
        }
        
        if (i == 0) start_inside = inside;
        
        if (i != 0 && ! is_side_visit) path_mask >>= 8;
        
        if (neighbor_mask == 0) {
            // after visiting any neighbors, proceed with grid ray march (or exit the loop if possible)
            
            if (path_mask == 0 && ( ( ! start_inside && closest_d2 > 1e18) || t_cutout < 1e18 || t_next >= 1. - EPS)) {
                break;
            }
            
            t = t_next + 0.00003;
        }
    }
   
    return start_inside;
}

// Project ray into the 2D grid coordinates used by the cutout data in Buffer A, and ray march
bool ray_march_cutout(int pk_index, vec3 ray_O, vec3 V, float t_near, float t_far, 
                      out float t_cutout, out float texture_pos,
                      out float closest_d, out float closest_tex_pos) {
    
    vec3 origin = vec3(0, 0., 0.);

    ray_O -= origin;

    ray_O.z = -ray_O.z;
    V.z = -V.z;
    
    float scale;
    vec2 offset;
    vec2 tex_dim;
    ivec2 tex_offset;
    
    if (pk_index==0) {
        scale = CUTOUT_SCALE_PK1;
        offset = CUTOUT_OFFSET_PK1;
        tex_dim = CUTOUT_TEX_DIM_PK1;
        tex_offset = CUTOUT_TEX_OFFSET_PK1;
    } else if (pk_index==1) {
        scale = CUTOUT_SCALE_PK2;
        offset = CUTOUT_OFFSET_PK2;
        tex_dim = CUTOUT_TEX_DIM_PK2;
        tex_offset = CUTOUT_TEX_OFFSET_PK2;
    } else {
        scale = CUTOUT_SCALE_PK3;
        offset = CUTOUT_OFFSET_PK3;
        tex_dim = CUTOUT_TEX_DIM_PK3;
        tex_offset = CUTOUT_TEX_OFFSET_PK3;
    }
    
    vec2 O_2d;
    vec2 V_2d;
    
    {
        vec3 P1 = ray_O + t_near*V;
        vec3 P2;
        
        if (ray_O.z + t_far*V.z > 1e-2) {
            P2 = ray_O + t_far*V;
        } else {
            P2 = ray_O + (1e-2 - ray_O.z) / V.z*V;
            t_far = (P2.z - ray_O.z) / V.z;
        }
        
        O_2d = P1.xy / P1.z;
        V_2d = P2.xy / P2.z - O_2d;
    }
     
    bool start_inside = ray_march_cutout_inner(tex_dim, tex_offset,
                                      scale*O_2d + offset,
                                      scale*V_2d,
                                      t_cutout, texture_pos,
                                      closest_d, closest_tex_pos);
    
    closest_d = sqrt(closest_d) * (ray_O + t_near*V).z / scale;
    
    if (start_inside && t_cutout < 1e18) {
        // Simple reverse transformation that doesn't use V.x and V.y (took me an embarrassingly long time to realize you can do this)
        
        float P1z = ray_O.z + t_near*V.z;
        float P2z = ray_O.z + t_far*V.z;
        
        t_cutout = t_near + (t_far - t_near) * P1z * t_cutout / ((P1z - P2z) * t_cutout + P2z);
    }
    
    return start_inside;
}

float dist_sq(vec3 p1, vec3 p2) {
    vec3 d = p1 - p2;
    
    return dot(d, d);
}

// Raymarch pumpkins and stalks, given a bitmask indicating which ones are potentially needed
float pumpkin_ray_march(int pk_mask, vec3 ray_O, vec3 V, inout vec3 N_surface, out int intersection_key) {
    int visit_order = 0;
    
    // Figure out the order in which to ray march the shapes and encode that order in an integer
    {
        float d1 = dist_sq(ray_O, PUMPKIN1_OFFSET);
        float d2 = dist_sq(ray_O, PUMPKIN2_OFFSET);
        float d3 = dist_sq(ray_O, PUMPKIN3_OFFSET);
        
        if (d1 <= d2 && d1 <= d3) {
            visit_order = d2 <= d3 ? (0 | (4 << 3) | (1<<6) | (5 << 9) | (2<<12) | (6 << 15)) 
                                   : (0 | (4 << 3) | (2<<6) | (6 << 9) | (1<<12) | (5 << 15));
        } else if (d2 <= d3) {
            visit_order = d1 <= d3 ? (1 | (5 << 3) | (0<<6) | (4 << 9) | (2<<12) | (6 << 15)) 
                                   : (1 | (5 << 3) | (2<<6) | (6 << 9) | (0<<12) | (4 << 15));
        } else {
            visit_order = d1 <= d2 ? (2 | (6 << 3) | (0<<6) | (4 << 9) | (1<<12) | (5 << 15)) 
                                   : (2 | (6 << 3) | (1<<6) | (5 << 9) | (0<<12) | (4 << 15));
        }
        
        visit_order |= 0xffffffff << 18;
        
        int shift = 0;
        
        for (int i = 0; i < 6; i++) {
            int v = (visit_order >> shift) & 7;
            
            if (v == 7) break;
            
            if ((pk_mask & (1 << v)) == 0) {
                visit_order = (visit_order & ~(0xffffffff << shift)) | ((visit_order & (0xfffffff8 << shift)) >> 3);
            } else {
                shift += 3;
            }
        }
    }

    const int STATE_BISECT_START = 12;
    const int STATE_BISECT_END = 16; // 15 is probably fine
    const int STATE_INIT = 0;
    const int STATE_INITIAL_STEP = 1;
    const int STATE_STEP = 2;
    const int STATE_PEAK = 3;

    float seg_inc = 0.01;

    int state = STATE_INIT;

    vec3 current_V;
    vec3 current_O;
    
    vec2 t_seg;
    vec2 v_seg;
    float t_next;
    vec3 d_start;
    vec3 d_end;
    vec2 t_outer;
    
    int itr_max = min(0, int(iTime)) + 5000;
    float scale;
    int pk_index;
    bool is_stalk;
    float found_distance = 1e20;
    intersection_key = -1;
    bool at_sphere_surface = false;
    
    visit_order <<= 3;
    
    for (int total_itr1 = 0; total_itr1 < itr_max; total_itr1++) {
        if (state == STATE_INIT) {
            // Set up the state for the next shape
            
            t_outer = vec2(1e20, 1e20);
            at_sphere_surface = false;
            
            float r_inner = 0.;
            
            visit_order >>= 3;
            
            if (intersection_key != -1) {
                if (((visit_order ^ intersection_key) & 3) != 0) visit_order = 0xffffffff;
                else if ((((visit_order >> 3) ^ intersection_key) & 3) != 0) visit_order |= 7 << 3;
            }
            
            if ((visit_order & 7) != 7) {
                // Short inner loop that keeps testing shapes until it finds one such that the ray hits the bounding sphere
                // (This is probably silly - should do this before the main loop instead, even if some effort is wasted - but it works)
                
                for (int inner_itr=0; inner_itr < 6 && (visit_order & 7) != 7; inner_itr++, visit_order >>= 3) {
                    is_stalk = (visit_order & 4) != 0;
                    pk_index = visit_order & 3;
                    
                    at_sphere_surface = false;
                    
                    vec3 OFFSET;
                    float shift;
                    float radius;
                    
                    if ( ! is_stalk) {
                        if (pk_index == 0) {
                            scale = PUMPKIN1_SCALE;
                            OFFSET = PUMPKIN1_OFFSET;
                            radius = BOUND_RADIUS_PK1;
                            r_inner = BOUND_RADIUS_INNER_PK1;
                        } else if (pk_index == 1) {
                            scale = PUMPKIN2_SCALE;
                            OFFSET = PUMPKIN2_OFFSET;
                            radius = BOUND_RADIUS_PK2;
                            r_inner = BOUND_RADIUS_INNER_PK2;
                        } else {
                            scale = PUMPKIN3_SCALE;
                            OFFSET = PUMPKIN3_OFFSET;
                            radius = BOUND_RADIUS_PK3;
                            r_inner = BOUND_RADIUS_INNER_PK3;
                        }
                        
                        shift = 0.;
                    } else {
                        if (pk_index == 0) {
                            scale = STALK1_SCALE;
                            OFFSET = STALK1_OFFSET;
                            shift = STALK1_BOUND_Y;
                            radius = STALK1_BOUND_RADIUS;
                        } else if (pk_index==1) {
                            scale = STALK2_SCALE;
                            OFFSET = STALK2_OFFSET;
                            shift = STALK2_BOUND_Y;
                            radius = STALK2_BOUND_RADIUS;
                        } else {
                            scale = STALK3_SCALE;
                            OFFSET = STALK3_OFFSET;
                            shift = STALK3_BOUND_Y;
                            radius = STALK3_BOUND_RADIUS;
                        }
                    }
                    
                    current_O = 1./scale*(ray_O - OFFSET);
                    
                    t_outer = intersect_sphere_both(vec3(0, shift, 0), radius, V, current_O);
                    
                    t_outer.x = max(t_outer.x, 0.);
                    t_outer.y = min(t_outer.y, 1./scale*found_distance);
                    
                    if (t_outer.x < t_outer.y && is_stalk) {
                        // For stalks, we also use a bounding box to narrow down the intersection interval further
                        // (I don't know if this really helps)
                        
                        bool pk1=pk_index==0, pk2=pk_index==1;
                        
                        vec2 b = 1./scale * intersect_box(CHOOSE3(pk1, pk2, STALK1_BOUND_LOW, STALK2_BOUND_LOW, STALK3_BOUND_LOW), 
                                                          CHOOSE3(pk1, pk2, STALK1_BOUND_HIGH, STALK2_BOUND_HIGH, STALK3_BOUND_HIGH), 
                                                          1./V, ray_O);
                        t_outer.x = max(t_outer.x, b.x);
                        t_outer.y = min(t_outer.y, b.y);
                    }

                    if (t_outer.x < t_outer.y && is_stalk) {
                        // Stalks have bounding cones that we need to test
                        
                        vec2 split = vec2(REMOVE_ZEROS(-0.25 - current_O.y)  * 1./V.y, REMOVE_ZEROS((pk_index == 2 ? 0.05 : 0.1) - current_O.y)  * 1./V.y);
                        
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
                        
                            vec2 c = cone_intersection(current_O - vec3(C.x, 0., C.y), V, dir, ab.x, ab.y);
                            
                            interval.x = max(interval.x, c.x);
                            interval.y = min(interval.y, c.y);
                        }

                        {
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
                            
                                vec2 c = cone_intersection(current_O - vec3(C.x, 0., C.y), V, dir, ab.x, ab.y);
                                
                                interval2.x = max(interval2.x, c.x);
                                interval2.y = min(interval2.y, c.y);
                                
                                if (interval2.x < interval2.y) {
                                    if (interval.x < interval.y) {
                                        interval.x = min(interval.x, interval2.x);
                                        interval.y = max(interval.y, interval2.y);
                                    } else {
                                        interval = interval2;
                                    }
                                }
                            }
                        }
            
                        bool split_dir = V.y >= 0.;
                        
                        if (pk_index == 2) {
                            bool split3_side;
                            float split3;
                            
                            {
                                float k = dot(V.xy, normalize(vec2(1,1.5)));
                            
                                split3 = (0.3 - dot(current_O.xy, normalize(vec2(1,1.5)))) / k;
                                split3_side = k >= 0.;
                            }

                            {
                                vec2 interval2 = t_outer;
                                
                                if (V.y < 0.) interval2.y = min(split.y, interval2.y);
                                else interval2.x = max(split.y, interval2.x);
                                
                                if (split3_side) interval2.y = min(split3, interval2.y);
                                else interval2.x = max(split3, interval2.x);
                                
                                if (interval2.x < interval2.y) {
                                    vec2 c = cone_intersection(current_O - vec3(-0.0148, 0, 0), V, vec3(0.5512425069, 0.8208679389, 0.14935704035), 0., 0.195);
                                    
                                    interval2.x = max(interval2.x, c.x);
                                    interval2.y = min(interval2.y, c.y);
                                    
                                    if (interval2.x < interval2.y) {
                                        if (interval.x < interval.y) {
                                            interval.x = min(interval.x, interval2.x);
                                            interval.y = max(interval.y, interval2.y);
                                        } else {
                                            interval = interval2;
                                        }
                                    }
                                }
                            }
                            
                            split.y = split3;
                            split_dir = split3_side;
                        }
                        
                        {
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
                                
                                vec2 c = cone_intersection(current_O - vec3(C.x, 0., C.y), V, dir, ab.x, ab.y);
                                
                                interval2.x = max(interval2.x, c.x);
                                interval2.y = min(interval2.y, c.y);
                                
                                if (interval2.x < interval2.y) {
                                    if (interval.x < interval.y) {
                                        interval.x = min(interval.x, interval2.x);
                                        interval.y = max(interval.y, interval2.y);
                                    } else {
                                        interval = interval2;
                                    }
                                }
                            }
                        }
                        
                        at_sphere_surface = interval.x == t_outer.x;
                        
                        t_outer = interval;
                    }
                    
                    if (t_outer.x < t_outer.y) break; // found a candidate shape
                }
            }
            
            if ( t_outer.x >= t_outer.y) break; // no more shapes to ray march
            
            // Rotate the origin and direction vector so we don't need to rotate each time we evaluate the implicit surface function
            {
                mat3 mtx;
                
                if (! is_stalk) {
                    if (pk_index==0) {
                        mtx = RMTX_PK1;
                    } else if (pk_index==1) {
                        mtx = RMTX_PK2;
                    } else {
                        mtx = RMTX_PK3;
                    }
                } else {
                    if (pk_index==0) {
                        mtx = STALK1_RMTX;
                    } else if (pk_index==1) {
                        mtx = STALK2_RMTX;
                    } else {
                        mtx = STALK3_RMTX;
                    }
                }
                
                current_V = mtx * V;
                current_O = mtx * current_O;
            }
            
            if ( ! is_stalk) {
                t_outer.y = min(intersect_sphere(vec3(0), r_inner, current_V, current_O), t_outer.y);
            }
        
            t_seg = vec2(t_outer.x);
            v_seg = vec2(0);
            t_next = t_seg.x;
            d_start = vec3(0);
            d_end = vec3(0);            
            state = STATE_INITIAL_STEP;
        }
        
        {
            vec4 dval;
            
            // Evaluate the implicit surface function at point "t_next" and get the value (similar to an SDF) and partial derivatives
                
            if ( ! is_stalk) {
                dval = pumpkin_val_and_deriv_fn(current_O + t_next*current_V, true, pk_index);
            } else {
                dval = stalk_val_and_deriv_fn(current_O + t_next*current_V, pk_index);
            }
            
            // Update the state based on whether the tested point is inside the shape
            // Remember the value, "t" value and partial derivatives for both ends of an interval,
            //      (data is needed when we switch to bisection)
            
            float v = dval.w;
            bool is_inside = v < 0.;
            
            // (Logic here is confusing because it was over-optimized, sorry)
            
            if (state <= STATE_STEP || is_inside) {
                bool is_init = state == STATE_INITIAL_STEP;
            
                if ( (t_next == t_outer.y && ! is_inside) || (is_init && is_inside)) {
                    // End of ray march.
                    // Either the initial tested point was inside the shape (usually means it's on an end cap for the stalks) 
                    //      or we passed through the bound without hitting the shape
                    
                    if (is_init) {
                        found_distance = scale*t_outer.x;
                        intersection_key = visit_order;
                        
                        if (at_sphere_surface && is_stalk) {
                            N_surface = vec3(0,-1,0);
                        } else {
                            N_surface = dval.xyz;
                        }
                    }
                    
                    state = STATE_INIT;
                    continue;
                }

                t_seg.y = t_next;
                v_seg.y = v;
                d_end = dval.xyz;
                
                if (is_inside) {
                    // Switch to bisection if we aren't already doing bisection
                    state = max(state, STATE_BISECT_START);
                }
            } else {
                // state==STATE_PEAK (advancing start of interval to peak that is not inside the shape)
                // or state>=STATE_BISECT_START (bisection found point not inside the shape)
                v_seg.x = v;
                t_seg.x = t_next;
                d_start = dval.xyz;
            }
        }
        
        if (state < STATE_BISECT_START) { // Regular ray marching phase (not bisection)
            state = STATE_STEP;
            
            // Get directional derivative from partial derivatives
            float d_seg_end = dot(current_V, d_end);
            
            // Test if the directional derivative changed sign, indicating that the value had
            //      a peak that we stepped over, potentially missing an intersection.
            // If so (and if the step size isn't already too small) then take a half-way step.
            // This is inefficient (backtracking) but it doesn't happen very often.

            {
                float h = 0.5*(t_seg.x + t_seg.y);
                
                if (h - t_seg.x >= 0.1*seg_inc) {
                    float d_seg_start = dot(current_V, d_start);
                    
                    if (d_seg_start < 0. && d_seg_end > 0.) {
                        state = STATE_PEAK;
                        t_next = h;
                    }
                }
            }
            
            if (state == STATE_STEP) {
                // If not backtracking, decide what size of step to take
                // seg_inc gives the minimum step size (when not backtracking or bisecting)
                // We use the function value (as you would an SDF) to take larger steps when safe.
                // (These step size rules were found by trial and error, as usual.)
                
                // Factor by which to multiply the value to get the step size (1 would be ideal for a true SDF)
                float step_scale = 1.;

                float v = v_seg.y;
                float t = t_seg.y;
                
                if (is_stalk) {
                    if (v <= 0.1) step_scale = 0.2;
                    else if (v < 0.3) step_scale = 0.3;
                    else step_scale = 0.4;
                } else if (d_seg_end > -0.25 && v >= 0.01) {
                    step_scale = pk_index == 2 ? 2. : 1.5;
                } else {
                    if (pk_index == 0) {
                        if (v <= 0.05) step_scale = 0.9;
                        else if (v >= 0.08) step_scale = 1.45;
                    }
                }
                
                v_seg.x = v;
                t_seg.x = t;
                d_start = d_end;
                
                // 0.5*seg_inc is always added to the step, because (unlike in typical SDF ray marching) we
                //      want to find a point inside the shape, so we can start bisecting (which is more accurate)
                // Don't step past the end of the bounding interval.
                
                t_next = min(t + 0.5*seg_inc + max(0.5*seg_inc, step_scale*v), t_outer.y);
            }
        } else if (state >= STATE_BISECT_END) {
            // End of bisection. Use regula falsi to estimate the location of the zero,
            //      and also blend the partial derivatives from the ends of the current interval to get the
            //      (unnormalized) surface normal
            
            float den = 1. / (v_seg.y - v_seg.x);
            float blend1 = v_seg.y * den;
            float blend2 = -v_seg.x * den;
            
            float d = scale*(t_seg.x*blend1 + t_seg.y*blend2);
            
            if (d < found_distance) {
                found_distance = d;
                N_surface = blend1*d_start + blend2*d_end;
                intersection_key = visit_order;
            }

            state = STATE_INIT;
        } else {
            // Combination of straightforward bisection and regula falsi (to speed up bisection a bit)
            // Clamping the point found by regula falsi to a sub interval
            
            float gap = t_seg.y - t_seg.x;
            
            t_next = clamp((t_seg.x*v_seg.y - t_seg.y*v_seg.x) / (v_seg.y - v_seg.x), t_seg.x + 0.33*gap, t_seg.y - 0.33*gap);
        
            state += 1;
        }
    }
    
    if (intersection_key != -1) {
        // Get the data that we want to return about the intersection
        
        is_stalk = (intersection_key & 4) != 0;
        pk_index = intersection_key & 3;
        
        if (N_surface != vec3(0,-1,0)) {
            mat3 mtx;
                        
            if ( ! is_stalk) {
                if (pk_index==0) {
                    mtx = RMTX_PK1;
                } else if (pk_index==1) {
                    mtx = RMTX_PK2;
                } else {
                    mtx = RMTX_PK3;
                }
            } else {
                if (pk_index==0) {
                    mtx = STALK1_RMTX;
                } else if (pk_index==1) {
                    mtx = STALK2_RMTX;
                } else {
                    mtx = STALK3_RMTX;
                }
            }
            
            N_surface = normalize(N_surface * mtx);
        }
    }
    
    return found_distance;
}

// Simpler version of the above, used for ray marching the inner shape (I want to replace this with something simpler and faster)
float pumpkin_ray_march_inner_shape(vec3 ray_O, vec3 V, vec2 t_outer, int pk_index, bool need_N, out vec3 N_surface) {
    N_surface = vec3(0);
    
    const int STATE_BISECT_START = 12;
    const int STATE_BISECT_END = 16;
    const int STATE_INIT = 0;
    const int STATE_INITIAL_STEP = 1;
    const int STATE_STEP = 2;
    const int STATE_PEAK = 3;

    const float seg_inc = 0.01;

    int state = STATE_INIT;
    
    vec2 t_seg;
    vec2 v_seg;
    float t_next;
    vec3 d_start;
    vec3 d_end;
    
    
    float scale;
    vec3 OFFSET;
    float radius;
    
    if (pk_index==0) {
        scale = PUMPKIN1_SCALE;
        OFFSET = PUMPKIN1_OFFSET;
        radius = BOUND_RADIUS_PK1;
    } else if (pk_index==1) {
        scale = PUMPKIN2_SCALE;
        OFFSET = PUMPKIN2_OFFSET;
        radius = BOUND_RADIUS_PK2;
    } else {
        scale = PUMPKIN3_SCALE;
        OFFSET = PUMPKIN3_OFFSET;
        radius = BOUND_RADIUS_PK3;
    }
    
    scale *= INNER_SHAPE_SCALE;
    
    t_outer *= 1./scale;

    vec3 current_V = V;
    vec3 current_O = 1./scale*(ray_O - OFFSET);
    
    {
        mat3 mtx;
                        
        if (pk_index==0) {
            mtx = RMTX_PK1;
        } else if (pk_index==1) {
            mtx = RMTX_PK2;
        } else {
            mtx = RMTX_PK3;
        }
        
        current_V = mtx * current_V;
        current_O = mtx * current_O;
    }
    
    {
        vec2 t = intersect_sphere_both(vec3(0, 0, 0), radius, current_V, current_O);

        t_outer.x = max(t_outer.x, t.x);
        t_outer.y = min(t_outer.y, t.y);
        
        if (t_outer.x > t_outer.y) {
            return 1e20;
        }
    }
    
    t_seg = vec2(t_outer.x);
    v_seg = vec2(0);
    t_next = t_seg.x;
    d_start = vec3(0);
    d_end = vec3(0);            
    state = STATE_INITIAL_STEP;
    
    float found_distance = 1e20;

    int itr_max = min(0, int(iTime)) + 1000;
    
    for (int total_itr1 = 0; total_itr1 < itr_max; total_itr1++) {
        {
            vec4 dval = pumpkin_val_and_deriv_fn(current_O + t_next*current_V, false, pk_index);
            
            float v = dval.w;
            
            if (state <= STATE_STEP || v < 0.) {
                t_seg.y = t_next;
                v_seg.y = v;
                d_end = dval.xyz;
                
                if (v < 0.) {
                    // Will get incremented to STATE_BISECT_START+1 (?) at the end of the loop
                    //   which means two bisections will be performed before state == STATE_MAX at end of the loop
                    state = max(state, STATE_BISECT_START);
                }
            } else {
                // state==STATE_PEAK (advancing start of interval to peak that is not inside the shape)
                // or state>=STATE_BISECT_START (bisection found point not inside the shape)
                v_seg.x = v;
                t_seg.x = t_next;
                d_start = dval.xyz;
            }
        }
        
        if (state < STATE_BISECT_START) {
            state = STATE_STEP;
            
            float d_seg_end = dot(current_V, d_end);
            
            {
                float h = 0.5*(t_seg.x + t_seg.y);
                
                if (h - t_seg.x >= 0.1*seg_inc) {
                    float d_seg_start = dot(current_V, d_start);
                    
                    if (d_seg_start < 0. && d_seg_end > 0.) {
                        state = STATE_PEAK;
                        t_next = h;
                    }
                }
            }
            
            if (state == STATE_STEP) {
                float step_scale = 1.;
                float v = v_seg.y;
                float t = t_seg.y;
                
                if (d_seg_end > -0.25) {
                    step_scale = pk_index == 0 ? 2.5 : 3.;
                } else {
                    if (pk_index == 0) {
                        if (v <= 0.05) step_scale = 0.9;
                        else if (v >= 0.08) step_scale = 1.45;
                    }
                }
                
                v_seg.x = v;
                t_seg.x = t;
                d_start = d_end;
                
                t_next = min(t + 0.5*seg_inc + max(0.5*seg_inc, step_scale*v), t_outer.y);
            }
        } else if (state >= STATE_BISECT_END) {
            float den = 1. / (v_seg.y - v_seg.x);
            float blend1 = v_seg.y * den;
            float blend2 = -v_seg.x * den;
            
            found_distance = scale*(t_seg.x*blend1 + t_seg.y*blend2);
            
            if (need_N) {
                N_surface = normalize(blend1*d_start + blend2*d_end);

                mat3 mtx;
                
                if (pk_index==0) {
                    mtx = RMTX_PK1;
                } else if (pk_index==1) {
                    mtx = RMTX_PK2;
                } else {
                    mtx = RMTX_PK3;
                }

                N_surface = N_surface * mtx;
            }
            
            break;
        } else {
            // Clamping regula falsi to a smaller interval
            float gap = t_seg.y - t_seg.x;
            
            t_next = clamp((t_seg.x*v_seg.y - t_seg.y*v_seg.x) / (v_seg.y - v_seg.x), t_seg.x + 0.33*gap, t_seg.y - 0.33*gap);
        
            state += 1;
        }
    }
    
    return found_distance;
}

// Test if a point is inside the pumpkin shape
bool is_inside_shape(vec3 P, int pk_index, bool inner) {
    {
        mat3 mtx;
                            
        if (pk_index==0) {
            mtx = RMTX_PK1;
        } else if (pk_index==1) {
            mtx = RMTX_PK2;
        } else {
            mtx = RMTX_PK3;
        }
            
        P = mtx * P;
    }
    
    float scale = inner ? INNER_SHAPE_SCALE : 1.;
    
    P *= 1./scale;
    
    float v = pumpkin_val_fn(P, ! inner, pk_index);
    
    return v < 0.;
}

// Get the normal vector on the simplified (no ripples version) of the pumpkin shape
// This is used for getting a TBN basis to use for the direction irradiance data computed for the pumpkins
vec3 pumpkin_local_basis_normal_fast(vec3 V, float t /* initial distance guess */, int pk_index) {
    mat3 mtx;
                        
    if (pk_index==0) {
        mtx = RMTX_PK1;
    } else if (pk_index==1) {
        mtx = RMTX_PK2;
    } else {
        mtx = RMTX_PK3;
    }

    V = mtx * V;
    
    vec4 dval = pumpkin_val_and_deriv_fn(t*V, false, pk_index);
    
#if 0 // Doesn't seem to be needed
    float d = dot(V, dval.xyz);
    
    if (abs(d) > 1e-10) {
        t -= dval.w / d;
        
        dval = pumpkin_val_and_deriv_fn(t*V, false, pk_index);
    }
#endif
    
    return normalize(dval.xyz * mtx);
}

// This is used for warping coordinates on the floor so the region around the corners of the boxes looks better
vec2 push_point(vec2 P, vec2 corner, float k) {
    vec2 V = corner - P;

    float d = length(V);

    return P - smoothstep(0., k, k-d)*k*normalize(V);
}

// Linear interpolating access for data in Buffer B (direct irradiance data)
// Not using hardware interpolation because it is broken on iOS (and we might need more control and precision anyway)
vec4 interpolate_map_iChannel1(int mesh_dim, int surface_index, inout ivec2 base_coord, inout vec2 coord) {
    vec2 c00;
    
    c00.x = floor(coord.x);
    
    coord.x -= c00.x;
    
    int x_inc = 1;

    if (surface_index >= INDEX_STALK1) {
        // For stalks, we need to wrap the longitude coordinates
        // We also need to look up the range of y (latitude) coordinates so we can map the coordinate properly
        //  (ranges are stored in BufferA, and need to be linearly interpolated in 1D)
        
        if (c00.x < 0.) c00.x += 40.;
        if (c00.x == 39.) x_inc = -39;
        
        int i = int(c00.x);
        
        vec4 data0 = texelFetch(iChannel0, ivec2((i & 7) + (surface_index - INDEX_STALK1)*8, (i >> 3) + (2*SPHERE_UV_DIM)), 0);
        
        i = int(c00.x) + x_inc;
        
        vec4 data1 = texelFetch(iChannel0, ivec2((i & 7) + (surface_index - INDEX_STALK1)*8, (i >> 3) + (2*SPHERE_UV_DIM)), 0);
        
        float min_y = mix(data0.x, data1.x, coord.x);
        float max_y = mix(data0.y, data1.y, coord.x);
        
        coord.y = 15. * (coord.y - min_y) / (max_y - min_y);
    }
    
    c00.y = floor(coord.y);
    coord.y -= c00.y;
    
    bool f00=false, f01=false, f10=false, f11=false;
    
    if (surface_index >= INDEX_PUMPKIN1 && surface_index <= INDEX_PUMPKIN3) {
        f00 = c00.x == 0. || c00.y == 0.;
        f01 = c00.x == float(TOP_SHADOW_MAP_DIM) || c00.y == 0.;
        f10 = c00.x == 0. || c00.y == float(TOP_SHADOW_MAP_DIM);
        f11 = c00.x == float(TOP_SHADOW_MAP_DIM) || c00.y == float(TOP_SHADOW_MAP_DIM);
    }

    c00 += vec2(base_coord);
    
    base_coord = ivec2(c00);
    
    vec4 val00 = f00 ? vec4(1) : texelFetch(iChannel1, ivec2(c00), 0);
    vec4 val01 = f01 ? vec4(1) : texelFetch(iChannel1, ivec2(c00 + vec2(x_inc,0)), 0);
    vec4 val10 = f10 ? vec4(1) : texelFetch(iChannel1, ivec2(c00 + vec2(0, 1)), 0);
    vec4 val11 = f11 ? vec4(1) : texelFetch(iChannel1, ivec2(c00 + vec2(x_inc, 1)), 0);
    
    return mix(mix(val00, val01, coord.x), mix(val10, val11, coord.x), coord.y);
}

ivec2 to_tex_coord(int x_mask, ivec2 ic) {
    ic.x &= x_mask;
    return ic;
}

// Used for preparing coordinates for accessing Buffer C (indirect irradiance data)
ivec2 prepare_interpolate_coord(int mesh_dim, bool samples_at_edges, bool is_sphere, inout vec2 coord) {
    coord *= float(samples_at_edges ? mesh_dim - 1 : mesh_dim);
    
    if ( ! samples_at_edges) coord -= 0.5;
    
    vec2 c00 = floor(coord);
    
    // This seems to be the one place where clamping is needed
    c00.y = clamp(c00.y, 0., float(mesh_dim-2));
    if ( ! is_sphere) c00.x = clamp(c00.x, 0., float(mesh_dim-2));
    
    coord -= c00;
    
    return ivec2(c00);
}

// Access Buffer C (indirect irradiance data)
vec3 interpolate_map_iChannel2_inner(int x_mask, ivec2 base_coord, ivec2 ic00, vec2 coord, int x_inc) {
    vec3 val00 = texelFetch(iChannel2, base_coord + to_tex_coord(x_mask, ic00), 0).rgb;
    vec3 val01 = texelFetch(iChannel2, base_coord + to_tex_coord(x_mask, ic00 + ivec2(x_inc,0)), 0).rgb;
    vec3 val10 = texelFetch(iChannel2, base_coord + to_tex_coord(x_mask, ic00 + ivec2(0,1)), 0).rgb;
    vec3 val11 = texelFetch(iChannel2, base_coord + to_tex_coord(x_mask, ic00 + ivec2(x_inc,1)), 0).rgb;
    
    return mix(mix(val00, val01, coord.x), mix(val10, val11, coord.x), coord.y);
}

// BRDF for the inside of the pumpkins (and the cutout edges)
// In candlelight, the colors are different (since we're not doing spectral rendering)
vec3 BRDF_inside(vec3 V, vec3 L, vec3 N, bool candlelight) {
    const vec3 SPEC_CANDLE = vec3(1.4544, 0.7212, -0.1643);

    vec3 DIFFUSE_COLOR = candlelight ? (vec3(1.172, 0.367, -0.311) - 0.0012*SPEC_CANDLE) / 0.9936 : (vec3(0.845, 0.493, -0.2305) - 0.0012) / 0.9936;

    return BRDF_eval(V, L, N, DIFFUSE_COLOR, candlelight ? SPEC_CANDLE : vec3(0), 0.5, 3, vec3(0.003214077325537801, 0.11170005053281784, 0.04991292208433151));
}

// Simple BRDF for the rough aluminum of the tealight containers
vec3 BRDF_metal(vec3 V, vec3 L, vec3 N) {
    return BRDF_eval_metal(V, L, N, vec3(1.33, 0.66, -0.15), 0.5); // spec color * 0.915
}

// BRDF with various parameters, for walls, boxes, outer surfaces of pumpkins, and stalks
vec3 BRDF_general(vec3 V, vec3 L, vec3 N, vec3 diffuse_color, float fresnel_base, float alpha, int fresnel_exponent, vec3 curve) {
    return BRDF_eval(V, L, N, diffuse_color, vec3(fresnel_base), alpha, fresnel_exponent, curve);
}

// Version of eval_area_light_clipped that returns centroid (and doesn't scale the final value)
vec3 eval_area_light_clipped2(vec3 dest_P, vec3 dest_N, vec4 rect) {
    float y = 1. - dest_P.y;
    
    vec2 P1 = vec2(rect.x, rect.y) - dest_P.xz;
    vec2 P2 = vec2(rect.z, rect.y) - dest_P.xz;
    vec2 P3 = vec2(rect.z, rect.w) - dest_P.xz;
    vec2 P4 = vec2(rect.x, rect.w) - dest_P.xz;
    
    vec2 Nxz = dest_N.xz;
    
    vec4 dots = vec4(dot(P1, Nxz), dot(P2, Nxz), dot(P3, Nxz), dot(P4, Nxz)) + y * dest_N.y;

    bool P1inside = dots.x > 0.;
    bool P2inside = dots.y > 0.;
    bool P3inside = dots.z > 0.;
    bool P4inside = dots.w > 0.;

    float c = float(P1inside) + float(P2inside) + float(P3inside) + float(P4inside);
    
    if (c == 0.) return vec3(0);

    vec2 rxz = 1. / Nxz;

    vec2 V_0 = P1, V_1 = P1;

    if (P1inside != P2inside) {
        V_0 = P1 - vec2(dots.x * rxz.x, 0);
        c++;
    }
    
    if (P2inside) {
        V_1 = V_0;
        V_0 = P2;
    }

    vec2 V_2 = V_1;
        
    if (P2inside != P3inside) {
        V_1 = V_0;
        V_0 = P3 - vec2(0, dots.z * rxz.y);
        c++;
    }

    vec2 V_3 = V_2;
    
    if (P3inside) {
        V_2 = V_1;
        V_1 = V_0;
        V_0 = P3;
    }

    if (P3inside != P4inside) {
        V_3 = V_2;
        V_2 = V_1;
        V_1 = V_0;
        V_0 = P3 - vec2(dots.z * rxz.x, 0);
        c++;
    }

    vec2 V_4 = V_3;
    
    if (P4inside) {
        V_3 = V_2;
        V_2 = V_1;
        V_1 = V_0;
        V_0 = P4;
    }
        
    if (P4inside != P1inside) {
        V_4 = V_3;
        V_3 = V_2;
        V_2 = V_1;
        V_1 = V_0;
        V_0 = P1 - vec2(0, dots.x * rxz.y);
        c++;
    }
    
    // put the last vertex in V_2
    
    float d = get_diff_poly_sum_same_y(V_1, V_0, y, dest_N);
    
    d += get_diff_poly_sum_same_y(V_2, V_1, y, dest_N);
    
    vec3 centroid_a;
    
    {
        float a = V_1.x*V_0.y - V_1.y*V_0.x;
        centroid_a = vec3(a * (V_1 + V_0), a);
    }
    
    {
        float a = V_2.x*V_1.y - V_2.y*V_1.x;
        centroid_a += vec3(a * (V_2 + V_1), a);
    }
    
    if (c >= 4.) {
        d += get_diff_poly_sum_same_y(V_3, V_2, y, dest_N);
    
        {
            float a = V_3.x*V_2.y - V_3.y*V_2.x;
            centroid_a += vec3(a * (V_3 + V_2), a);
        }

        if (c == 5.) {
            d += get_diff_poly_sum_same_y(V_4, V_3, y, dest_N);
    
            {
                float a = V_4.x*V_3.y - V_4.y*V_3.x;
                centroid_a += vec3(a * (V_4 + V_3), a);
            }
            
            V_2 = V_4;
        } else {
            V_2 = V_3;
        }
    }
    
    d += get_diff_poly_sum_same_y(V_0, V_2, y, dest_N);
    
    {
        float a = V_0.x*V_2.y - V_0.y*V_2.x;
        centroid_a += vec3(a * (V_0 + V_2), a);
    }
    
    return vec3(1. / (6. * 0.5 * centroid_a.z) * centroid_a.xy, d);
}

// Take BRDF samples for four quadrants of the area light, computing irradiance for each, and scale by shadow fractions
vec3 area_light_sample(vec3 view_V, vec3 dest_P, vec3 dest_N, vec4 shadow, vec3 diffuse_color, vec3 diffuse_curve, float fresnel_base, float ggx_alpha, int fresnel_exponent) {
    vec3 total = vec3(0);
    
    {
        vec3 centroid_ff = eval_area_light_clipped2(dest_P, dest_N, vec4(0.4, 0.4, 0.5, 0.5));
        
        if (centroid_ff.z != 0.) {
            total = shadow.x * centroid_ff.z * BRDF_general(-view_V, normalize(vec3(centroid_ff.x, 1. - dest_P.y, centroid_ff.y)), dest_N, diffuse_color, fresnel_base, ggx_alpha, fresnel_exponent, diffuse_curve);
        }
    }
    
    {
        vec3 centroid_ff = eval_area_light_clipped2(dest_P, dest_N, vec4(0.5, 0.4, 0.6, 0.5));
        
        if (centroid_ff.z != 0.) {
            total += shadow.y * centroid_ff.z * BRDF_general(-view_V, normalize(vec3(centroid_ff.x, 1. - dest_P.y, centroid_ff.y)), dest_N, diffuse_color, fresnel_base, ggx_alpha, fresnel_exponent, diffuse_curve);
        }
    }
    
    {
        vec3 centroid_ff = eval_area_light_clipped2(dest_P, dest_N, vec4(0.4, 0.5, 0.5, 0.6));
        
        if (centroid_ff.z != 0.) {
            total += shadow.z * centroid_ff.z * BRDF_general(-view_V, normalize(vec3(centroid_ff.x, 1. - dest_P.y, centroid_ff.y)), dest_N, diffuse_color, fresnel_base, ggx_alpha, fresnel_exponent, diffuse_curve);
        }
    }
    
    {
        vec3 centroid_ff = eval_area_light_clipped2(dest_P, dest_N, vec4(0.5, 0.5, 0.6, 0.6));
        
        if (centroid_ff.z != 0.) {
            total += shadow.w * centroid_ff.z * BRDF_general(-view_V, normalize(vec3(centroid_ff.x, 1. - dest_P.y, centroid_ff.y)), dest_N, diffuse_color, fresnel_base, ggx_alpha, fresnel_exponent, diffuse_curve);
        }
    }
    
    return total * -0.5 / PI * (1./0.2 * 1./0.2);
}

// Get a randomly animated matrix for a candle flame
mat2 get_flame_matrix(uint seed) {
    float time_scaled = 0.5*iTime + 123.4;
    
    float t = 0.1*time_scaled;
    float t_floor = floor(t);
    float f = t - t_floor;
    
    uint h0 = hash_fn1(seed);
    uint h1 = hash_fn1(uint(t_floor) ^ h0);
    uint h2 = hash_fn1((uint(t_floor)+1u) ^ h0);
    
    vec4 vals0 = HASH_EXTRACT_VEC4(h1);
    vec4 vals = mix(HASH_EXTRACT_VEC4(h1), HASH_EXTRACT_VEC4(h2), f);
    
    return mat2(
            1. + 0.06*sin((4.+vals0.x)*time_scaled + 2.*vals.x*time_scaled) + 0.1*abs(sin(5.7*time_scaled + 5.)),
            0.14*sin((3.1+vals0.y)*time_scaled + 2.*vals.x*time_scaled) + 0.02*abs(sin(1.2*time_scaled + 2.7)),
            0.08*sin((4.2+vals0.z)*time_scaled + 2.*vals.x*time_scaled) + 0.02*abs(sin(2.2*time_scaled + 2.)),
            1. + 0.07*sin((5.6+vals0.w)*time_scaled + 2.*vals.x*time_scaled) + 0.08*abs(sin(7.2*time_scaled + 7.))
        );
}

// Simple flame rendering
vec3 render_flame2d(vec2 xy) {
    float t = xy.x;
    float u = xy.y;

    if (abs(t - 0.5) > 0.5 || abs(u - 0.5) > 0.5) return vec3(0);
    
    t = 0.35*(2.*t - 1.);
    u = 0.55*u + 0.05;
    
    float t2 = t*t;
    float u2 = u*u;
    
    float curve1 = smoothstep(0., 0.1, u);
    
    float v = curve1 * u2 * exp(-1.*exp(12.0*t2 + 4.*u + 20.0*t2*u*u2) + 6.);
    
    v = v*v;
    
    float value1 = v*u;
    float value2 = v*v;

    float curve2 = smoothstep(0.1, 0.7, u);
    float curve3 = sqrt(curve2);
    
    float red = (value1 + value2)*curve3;
    
    return vec3(red, 0.73*(0.25*value1 + 0.75*value2)*curve3, (0.15*value2)*curve1*(1.-curve2) - 0.5*red);
}

// Axis-aligned infinite cylinder intersection
// Using the more precise quadratic root formula here - I don't know if this is necessary
vec2 intersect_inf_cylinder(vec2 C, float r, vec3 V, vec3 ray_O) {
    ray_O.xz -= C;
    
    float a = dot(V.xz, V.xz);
    float b = dot(V.xz, ray_O.xz);
    float c = dot(ray_O.xz, ray_O.xz) - r*r;
    
    float disc = b*b - a*c;
    
    if (disc < 0.) return vec2(1e20);
    
    disc = sqrt(disc);
    
    float q = (b < 0. ? disc : -disc) - b;
    return vec2(c/q, q/a); 
}

// Intersect ray with the cylinder used for the tealight and return distance and a code indicating the location
float intersect_tealight(vec2 C, float R, float bottom, float top, float middle, vec3 V, vec3 ray_O, out int inter_type) {
    vec2 t2 = intersect_inf_cylinder(C, R, V, ray_O);
    bool is_middle = false;
    
    if (t2.x < 1e18) {
        {
            vec3 P = ray_O + t2.x*V;
            if (P.y < bottom || P.y > top) t2.x = 1e20;
        }
        
        {
            vec3 P = ray_O + t2.y*V;
            if (P.y < bottom || P.y > top) t2.y = 1e20;
            else if (P.y < middle) is_middle = true;
        }
    }
    
    inter_type = 0;
    
    float t = 1e20;
    
    if (t2.x < t) inter_type=1, t = t2.x;
    if (t2.y < t) {
        inter_type=2;
        t = t2.y;
    }
    
    if ((inter_type == 0 || (inter_type==2 && is_middle)) && ray_O.y > middle && V.y < 0.) {
        float t3 = (middle - ray_O.y) / V.y;
        
        if (t3 < t) {
            vec2 d = ray_O.xz + t3*V.xz - C;
            
            if (dot(d,d) < R*R) inter_type=3, t = t3;
        }
    }
    
    return t;
}

// Get a mask for the anti-aliased rectangle used for the candle wick (defined by two points and a width)
float get_wick_mask(float scale, vec3 offset, vec3 ray_O, mat3 rotation_matrix, float view_plane_z, vec2 fragCoord, vec3 point1, vec3 point2, float width) {
    vec3 P1 = (scale*point1 + offset - ray_O) * rotation_matrix;
    vec3 P2 = (scale*point2 + offset - ray_O) * rotation_matrix;
    
    float dist_scale = view_plane_z / P1.z;

    P1.xy *= dist_scale;
    P2.xy *= dist_scale;
    
    vec2 W = normalize(P2.xy - P1.xy);
    
    vec2 gap1 = fragCoord - P1.xy;
    vec2 gap2 = P2.xy - fragCoord;
    
    float g = dot(gap1, W);
    
    float hwidth = width * dist_scale;
    float blur = 1.;
    float m = hwidth - blur;
    float p = hwidth + blur;
    float d = length(gap1 - g*W);
    
    return 1. - smoothstep(-blur, blur, g) * smoothstep(-blur, blur, dot(gap2, W)) * (smoothstep(-p, -m, d) - smoothstep(m, p, d));
}

// Compute direct lighting for candlelight, for interior surface of pumpkin (or cutout edges)
// Evaluates the BRDF for the inside surface of the pumpkins
vec3 get_flame_lighting(vec3 V, vec3 dest, vec3 src, vec3 N_dest, float light_amount) {
    vec3 L = src - dest;
    
    float scale = dot(L, N_dest);
    
    if (scale > 0.) {
        float rd = 1. / sqrt(dot(L, L));
        
        // extra "* rd" is because scale did not use normalized vector

        return light_amount * rd * rd * rd * scale * BRDF_inside(-V, L * rd, N_dest, true);
    } else {
        return vec3(0);
    }
}

// Compute direct lighting for candlelight, for rough aluminum surface
vec3 get_flame_lighting_metal(vec3 V, vec3 dest, vec3 src, vec3 N_dest, float light_amount) {
    vec3 L = src - dest;
    
    float scale = dot(L, N_dest);
    
    if (scale > 0.) {
        float rd = 1. / sqrt(dot(L, L));
        
        // extra "* rd" is because scale did not use normalized vector

        return light_amount * rd * rd * rd * scale * BRDF_metal(-V, L * rd, N_dest);
    } else {
        return vec3(0);
    }
}

// Compute an approximation of the ambient occlusion around each candle (I rendered this offline and then fitted a rational function)
float compute_tealight_ambient_occlusion(float x) {
    const vec3 A = vec3(-0.20143708365040436, 0.025017454524768123, -0.0007058922348599897);
    const vec4 B = vec4(0.9820676003071314, -0.18076648884947125, 0.02072624928092832, -0.0003590986567965412);
    
    float x2 = x*x;
    float x3 = x*x2;
    
    return (x3 + A.x*x2 + A.y*x + A.z) / (B.x*x3 + B.y*x2 + B.z*x + B.w);
}

// Compute an approximation of the shadow cast by the candle (I rendered this offline and then fitted a rational function)
float compute_tealight_shadow(float x) {
    if (x > 0.0674) {
        const vec3 A = vec3(-0.20466745841188677, 0.013967812891358436, -0.0003178557870654744);
        const vec4 B = vec4(1.0006293559811847, -0.20564421941100366, 0.014349156276804338, -0.0003248578592190295);
        
        float x2 = x*x;
        float x3 = x*x2;
        
        return (x3 + A.x*x2 + A.y*x + A.z) / (B.x*x3 + B.y*x2 + B.z*x + B.w);
    } else {
        return 0.;
    }
}

// Used for adding a bit of texture to interior surface
vec3 gyroid3d(vec3 p) {
    vec3 a = sin(p) * cos(p.yzx);
    
    return a.yxx + a.zzy;
}

// Decode the normal vectors of the cutout edges (stored in a 1D texture in buffer D)
vec3 cutout_normal_decode(vec4 values) {
    return octahedral_decode(values.zw);
}

// Decode the ambient occlusion values for the cutout edges (stored in a 1D texture in buffer D)
vec4 cutout_AO_decode(vec4 values) {
    ivec2 enc = floatBitsToInt(values.xy);
    
    // Divide by 2 because the values were multiplied by 2 prior to encoding
    
    return 0.5/127. * (vec4(ivec4(enc.x >> 13, enc.x >> 20, enc.y >> 13, enc.y >> 20) & 0x7f) + 0.5);
}

// Interpolate ambient occlusion fraction in the depth direction (piecewise linear with 4 points)
float interpolate_for_cutout_AO(float f, vec4 values) {
    float v;
    
    if (f < 0.1) v = 0.5 + (values.x - 0.5) * f / 0.1;
    else if (f < 0.3) v = values.x + (values.y - values.x) * (f - 0.1) / (0.3 - 0.1);
    else if (f < 0.6) v = values.y + (values.z - values.y) * (f - 0.3) / (0.6 - 0.3);
    else v = values.z + (values.w - values.z) * (f - 0.6) / (0.9 - 0.6);
    
    return v;
}

// Compute coordinates and emitted light amount for flame
// Flames aren't really 3D (they're billboards)
void flame_compute(bool render_inside, uint seed, float scale, vec3 use_O, vec3 V,
                   vec3 plane_N, vec3 dir1, vec3 dir2,
                   float d_scale, vec3 flame_offset, float FLAME_BOUND_HALF_X, float FLAME_BOUND_HALF_Y,
                   out float z_boost, out float light, out vec3 flame_pos, out vec2 flame_uv) {
    mat2 M = get_flame_matrix(seed);
    
    z_boost = M[0][0] + M[1][0];
    light = M[0][0]*M[1][1] - M[1][0]*M[0][1];
    
    light *= sqrt(light) * 1./(scale*scale) * CANDLELIGHT_SCALE;
    
    vec3 P = use_O + dot(flame_offset - use_O, plane_N) * d_scale*V - flame_offset;

    const vec2 FLAME_XFORM_CENTER = vec2(0.5, 0.025);
    const vec2 FLAME_LIGHT_CENTER = vec2(0.5);
    
    {
        vec2 uv = inverse(M) * (FLAME_LIGHT_CENTER - FLAME_XFORM_CENTER) + (FLAME_XFORM_CENTER - FLAME_LIGHT_CENTER);
        
        flame_pos = flame_offset + dot(P, plane_N)*plane_N + uv.x*(2.*FLAME_BOUND_HALF_X)*dir2 + uv.y*(2.*FLAME_BOUND_HALF_Y)*dir1;
    }
    
    flame_uv = vec2(0);
    
    if (render_inside) {
        float x = dot(P, dir2);
        float y = dot(P, dir1);
        
        if (x > -FLAME_BOUND_HALF_X && x < FLAME_BOUND_HALF_X && y > -FLAME_BOUND_HALF_Y && y < FLAME_BOUND_HALF_Y) {
            flame_uv = vec2(x/(2.*FLAME_BOUND_HALF_X), y/(2.*FLAME_BOUND_HALF_Y)) + FLAME_LIGHT_CENTER;
            
            flame_uv = M * (flame_uv - FLAME_XFORM_CENTER) + FLAME_XFORM_CENTER;
        }
    }
}

// Peform ray marching for pumpkins and stalks
// For pumpkin intersection, ray march the cutout shape (if necessary) and render interior of pumpkin.
// (This should probably be split up)            
int render_pumpkin(int pk_mask, inout vec3 final_color, inout float t_inter, vec3 ray_O, vec3 V, float view_plane_z, inout vec3 N_surface, out vec3 N_surface2, 
                   out int pk_index,
                   vec2 fragCoord, mat3 rotation_matrix, out float ambient, out float alpha_blend, out float edge_texture_pos,
                   out float fractional_distance, out float fract_dist_pix_scale) {
    pk_index = -1;
    ambient = 0.;
    alpha_blend = 0.;
    edge_texture_pos = 0.;
    fractional_distance = 0.;
    fract_dist_pix_scale = 0.;
    
    // perform ray march
    float t_inter2 = pumpkin_ray_march(pk_mask, ray_O, V, N_surface, pk_index);
    
    N_surface2 = N_surface;
    
    if (t_inter2 > 0. && t_inter2 < 1e18 && t_inter2 < t_inter) {
        bool is_stalk = (pk_index&4) != 0;
        pk_index &= 3;
        
        if (is_stalk) { // not doing anything else for stalks here
            t_inter = t_inter2;
            return 2;
        }
            
        float scale;
        vec3 offset;
        float radius;

        if (pk_index==0) {
            scale = PUMPKIN1_SCALE;
            offset = PUMPKIN1_OFFSET;
            radius = BOUND_RADIUS_PK1;
        } else if (pk_index==1) {
            scale = PUMPKIN2_SCALE;
            offset = PUMPKIN2_OFFSET;
            radius = BOUND_RADIUS_PK2;
        } else {
            scale = PUMPKIN3_SCALE;
            offset = PUMPKIN3_OFFSET;
            radius = BOUND_RADIUS_PK3;
        }
        
        // Scale the intersection back to the coordinate system we use for rendering the inside of the pumpkins
    
        float t_surface = 1./scale * t_inter2;
        
        vec3 origin = 1./scale*(ray_O - offset);
        
        // Get bounding interval from bounding sphere (because we didn't store it during ray marching)
        
        vec2 t_outer = intersect_sphere_both(vec3(0, 0, 0), radius, V, origin);

        bool need_cutout;
        
        // Use a 3D AABB to test if we need to ray march the cutout shape
        {
            vec2 box_x, box_y;
            float box_z;
            
            if (pk_index==0) {
                box_x = vec2(-0.32, 0.375);
                box_y = vec2(-0.34, 0.33);
                box_z = -0.28;
            } else if (pk_index==1) {
                box_x = vec2(-0.45, 0.41);
                box_y = vec2(-0.33, 0.32);
                box_z = -0.3;
            } else {
                box_x = vec2(-0.39, 0.39);
                box_y = vec2(-0.38, 0.42);
                box_z = -0.35;
            }
        
            vec3 P = origin + t_surface*V;
            
            need_cutout = P.x > box_x.x && P.x < box_x.y && P.y > box_y.x && P.y < box_y.y && P.z < box_z;
        }
        
        float t_inner = 0.;
        bool miss_inner = false;
        
        if (need_cutout) {
            vec3 N_unused;
            
            // Ray march inner shape (currently just a smaller copy of the pumpkin shape, without the ripples)
            //      to get the far end of the interval for ray marching the cutout
            
            t_inner = pumpkin_ray_march_inner_shape(ray_O, V, vec2(t_inter2, t_inter2+1.), pk_index, false, N_unused);
            
            miss_inner = t_inner > 1e18;
            
            t_inner = t_inner < 1e18 ? 1./scale * t_inner : t_outer.y;
        }
        
        float t_cutout = 0.;
        float closest_tex_pos = 0.;
        bool hits_cutout = false; // true if the ray hit a point on the surface of the pumpkin shape that is covered by the cutout shape
        
        if (need_cutout) {
            float closest_d;
            
            hits_cutout = ray_march_cutout(pk_index, origin, V, t_surface, t_inner, t_cutout, edge_texture_pos,
                                           closest_d, closest_tex_pos);

            if (miss_inner && t_cutout < 1e18 && (t_cutout - t_surface) > 0.001) {
                vec3 P = origin + t_cutout*V;
                
                if ( ! is_inside_shape(0.999*P, pk_index, false)) {
                    need_cutout = false;
                }
            }
            
            closest_d *= 150. * scale;
            
            if (closest_d < 1.5) {
                alpha_blend = hits_cutout ? -closest_d : closest_d;
            } else {
                alpha_blend = hits_cutout ? -10. : 10.;
            }
            
            if (alpha_blend > 1. || (alpha_blend < 0. && miss_inner && hits_cutout && t_cutout > 1e18)) need_cutout = false;
        } else {
            hits_cutout = false;
        }
        
        if (need_cutout) {
            vec3 P = t_inter2*V * rotation_matrix;
            
            alpha_blend *= 0.005 * view_plane_z / P.z;
            
            if (alpha_blend > 1.) {
                need_cutout = false;
                hits_cutout = false;
            }
        }
        
        if ( ! need_cutout) {
            alpha_blend = 1.;
            
            if ( ! hits_cutout) t_inter = t_inter2;
            
            return hits_cutout ? 0 : 1;
        }
        
        t_inter = t_inter2;

        alpha_blend = smoothstep(-1., 1., alpha_blend);
        
        bool render_inside = hits_cutout && t_cutout > 1e18;
        
        if (t_cutout > 1e18 || ! hits_cutout) {
            t_cutout = t_surface;
            edge_texture_pos = closest_tex_pos;
        }
        
        float scale_factor = pk_index==0 ? 1. :  pk_index==1 ? PUMPKIN1_SCALE/PUMPKIN2_SCALE : PUMPKIN1_SCALE/PUMPKIN3_SCALE;

        const float TEALIGHT_R = 0.05;
        const float TEALIGHT_HEIGHT = 0.045;
        const float TEALIGHT_WAX_HEIGHT = 0.035;
        
        const float FLAME_OFFSET = 0.08;
        
        float TEALIGHT1_BOTTOM_Y = -0.32;
        float TEALIGHT2_BOTTOM_Y = -0.32;
        float TEALIGHT3_BOTTOM_Y = -0.35;
        
        if (pk_index == 0) {
            TEALIGHT1_BOTTOM_Y = -0.355;
            TEALIGHT2_BOTTOM_Y = -0.36;
        } else if (pk_index == 1) {
            TEALIGHT1_BOTTOM_Y = -0.4;
            TEALIGHT2_BOTTOM_Y = -0.4;
        } else {
            TEALIGHT1_BOTTOM_Y = -0.425;
        }
        
        vec3 FLAME1_OFFSET = vec3(-0.05, TEALIGHT1_BOTTOM_Y + (TEALIGHT_WAX_HEIGHT + FLAME_OFFSET)*scale_factor, -0.05);
        vec3 FLAME2_OFFSET = vec3(0.15, TEALIGHT2_BOTTOM_Y + (TEALIGHT_WAX_HEIGHT + FLAME_OFFSET)*scale_factor, -0.1);
        vec3 FLAME3_OFFSET = vec3(0.05, TEALIGHT3_BOTTOM_Y + (TEALIGHT_WAX_HEIGHT + FLAME_OFFSET)*scale_factor, 0.05);
        
        if (pk_index == 1) {
            FLAME1_OFFSET.xz = vec2(-0.06, -0.125);
            FLAME2_OFFSET.xz = vec2(0.12, 0.);
        }

        float flame_light1 = 0.;
        float flame_light2 = 0.;
        float flame_light3 = 0.;
        vec3 flame_pos1 = vec3(0);
        vec3 flame_pos2 = vec3(0);
        vec3 flame_pos3 = vec3(0);

        vec2 flame_uv1 = vec2(0); // only used if render_inside
        vec2 flame_uv2 = vec2(0); // only used if render_inside
        vec2 flame_uv3 = vec2(0); // only used if render_inside
        
        float flame_z_boost1 = 0.;
        float flame_z_boost2 = 0.;
        float flame_z_boost3 = 0.;
        
        // Get coordinates and lighting data for the flames
        {
            vec3 dir1 = vec3(0., 1., 0.);
            vec3 dir2 = normalize(cross(dir1, V));
            vec3 plane_N = cross(dir1, dir2);
            
            float d_scale = 1./dot(V, plane_N);
            vec3 use_O = 1./scale*(ray_O - offset);
            
            float FLAME_BOUND_HALF_X = 0.03*scale_factor;
            float FLAME_BOUND_HALF_Y = 0.1*scale_factor;
        
            flame_compute(render_inside, 0xab6bc867u ^ uint(pk_index<<11), scale, use_O, V,
                          plane_N, dir1, dir2,
                          d_scale, FLAME1_OFFSET, FLAME_BOUND_HALF_X, FLAME_BOUND_HALF_Y,
                          flame_z_boost1, flame_light1, flame_pos1, flame_uv1);

            if (pk_index != 2) {
                flame_compute(render_inside, 0x51f05d9fu ^ uint(pk_index<<11), scale, use_O, V,
                              plane_N, dir1, dir2,
                              d_scale, FLAME2_OFFSET, FLAME_BOUND_HALF_X, FLAME_BOUND_HALF_Y,
                              flame_z_boost2, flame_light2, flame_pos2, flame_uv2);
            } else {
                flame_light2 = 0.;
            }
            
            if (pk_index == 0) {
                flame_compute(render_inside, 0xd379d7c3u ^ uint(pk_index<<11), scale, use_O, V,
                              plane_N, dir1, dir2,
                              d_scale, FLAME3_OFFSET, FLAME_BOUND_HALF_X, FLAME_BOUND_HALF_Y,
                              flame_z_boost3, flame_light3, flame_pos3, flame_uv3);
            } else {
                flame_light3 = 0.;
            }
        }
        
        vec3 indirectLightScale = vec3(0);
        
        // Indirect illumination scaling factors that I found by offline spectral path tracing
        // Indirect light is fairly uniform because the pumpkins do a great job of diffusing
        //      the light.
        // flame_light1, etc. have already been scaled to account for the different sizes
        //      (first pumpkin is bigger than third, so it would look darker if there was only
        //       a single candle in each).
        // These additional scaling factors are supposed to be taking into account the light
        //      exiting through the cutout shapes (cutout area on the third pumpkin is larger 
        //      in proportion to total surface area).
        // Yes, I'm using negative (out of gamut) blue values. The final gamut clipping (and tone
        //      mapping) should be able to handle this.
        if (pk_index == 0) {
            indirectLightScale = 21.721825 * vec3(1, 0.183, -0.228);
        } else if (pk_index == 1) {
            indirectLightScale = 19.30098 * vec3(1, 0.183, -0.228);
        } else {
            indirectLightScale = 15.524017 * vec3(1, 0.183, -0.228);
        }
        
        if (render_inside) {
            // Render everything inside the pumpkin (not including cutout edges)
            
            // Need to ray march the inner shape again to get the far intersection
            // (I should probably find a more efficient/simpler alternative, since it's a simpler shape)
            
            vec3 N_inner;
            float t_inner2 = 1./scale * (scale * t_outer.y - pumpkin_ray_march_inner_shape(ray_O + scale *t_outer.y*V, -V, vec2(0., scale *(t_outer.y-t_outer.x)), pk_index,
                true, N_inner));
                
            N_inner = -N_inner;
            
            vec3 use_O = 1./scale*(ray_O - offset);
            
            {
                vec3 P2 = use_O + t_inner2 * V;
                
                // Simple diffuse illumination inside the pumpkins (not using BRDFs)
                // Precomputed indirectLightScale does most of the work
                {
                    float factor;
                    
                    if (P2.y < 0.) {
                        // Apply ambient occlusion around the tealights
                        
                        float d = distance(P2.xz, FLAME1_OFFSET.xz) / scale_factor;
                        
                        factor = compute_tealight_ambient_occlusion(d);
                        
                        if (pk_index != 2) {
                            d = distance(P2.xz, FLAME2_OFFSET.xz) / scale_factor;
                            factor = min(factor, compute_tealight_ambient_occlusion(d));
                        }
                        
                        if (pk_index == 0) {
                            d = distance(P2.xz, FLAME3_OFFSET.xz) / scale_factor;
                            factor = min(factor, compute_tealight_ambient_occlusion(d));
                        }
                    } else {
                        factor = 1.;
                    }
                    
                    final_color = factor * (flame_light1 + flame_light2 + flame_light3)*indirectLightScale;
                }
                
                // Make the inside surface of the pumpkins less smooth
                N_inner = normalize(N_inner + 0.05*gyroid3d(83.*P2 + vec3(1,2,3)) + 0.1*gyroid3d(vec3(37., 23., 51.)*P2.zxy + vec3(-2,1,0.5)));
                
                // Compute direct lighting, with shadows
                // (I wanted to animate the shadows as the lights move, but I didn't get round to that)
                
                {
                    float d = distance(P2.xz, 2.*FLAME1_OFFSET.xz - flame_pos1.xz) / scale_factor;
                
                    final_color += (P2.y < 0. ? compute_tealight_shadow(d) : 1.) * get_flame_lighting(V, P2, flame_pos1, N_inner, flame_light1);
                }
                
                if (pk_index != 2) {
                    float d = distance(P2.xz, 2.*FLAME2_OFFSET.xz - flame_pos2.xz) / scale_factor;
                
                    final_color += (P2.y < 0. ? compute_tealight_shadow(d) : 1.) * get_flame_lighting(V, P2, flame_pos2, N_inner, flame_light2);
                }
                
                if (pk_index == 0) {
                    float d = distance(P2.xz, 2.*FLAME3_OFFSET.xz - flame_pos3.xz) / scale_factor;
                
                    final_color += (P2.y < 0. ? compute_tealight_shadow(d) : 1.) * get_flame_lighting(V, P2, flame_pos3, N_inner, flame_light3);
                }
            }
            
            {
                // Render the metal and wax part of the tealights
                
                int inter_type = 0;
                int inter_cyl = 0;

                float t = intersect_tealight(FLAME1_OFFSET.xz, TEALIGHT_R*scale_factor,
                                              TEALIGHT1_BOTTOM_Y, 
                                              TEALIGHT1_BOTTOM_Y + TEALIGHT_HEIGHT*scale_factor,
                                              TEALIGHT1_BOTTOM_Y + TEALIGHT_WAX_HEIGHT*scale_factor, V, use_O, inter_type);
                
                if (pk_index != 2) {
                    int inter_type2 = 0;
                    float t2 = intersect_tealight(FLAME2_OFFSET.xz, TEALIGHT_R*scale_factor,
                                                  TEALIGHT2_BOTTOM_Y,
                                                  TEALIGHT2_BOTTOM_Y + TEALIGHT_HEIGHT*scale_factor,
                                                  TEALIGHT2_BOTTOM_Y + TEALIGHT_WAX_HEIGHT*scale_factor, V, use_O, inter_type2);
                    
                    if (t2 < t) inter_type = inter_type2, inter_cyl = 1, t = t2;
                }
                
                if (pk_index == 0) {
                    int inter_type3 = 0;
                    float t2 = intersect_tealight(FLAME3_OFFSET.xz, TEALIGHT_R*scale_factor,
                                                  TEALIGHT3_BOTTOM_Y,
                                                  TEALIGHT3_BOTTOM_Y + TEALIGHT_HEIGHT*scale_factor,
                                                  TEALIGHT3_BOTTOM_Y + TEALIGHT_WAX_HEIGHT*scale_factor, V, use_O, inter_type3);
                    
                    if (t2 < t) inter_type = inter_type3, inter_cyl = 2, t = t2;
                }
                
                if (inter_type != 0) {
                    const vec3 CANDLELIGHT = 30. * vec3(1.4544, 0.7212, -0.1643);
                    
                    // Ad-hoc indirect lighting
                    if (inter_type == 1) final_color = 0.3 * CANDLELIGHT;
                    else if (inter_type == 2) final_color = 0.6 * CANDLELIGHT;
                    else final_color = 1.25 * CANDLELIGHT;
                    
                    final_color *= flame_light1 + flame_light2 + flame_light3;
                    
                    if (inter_type == 1) {
                        vec2 c;
                        if (inter_cyl == 0) c = FLAME1_OFFSET.xz;
                        else if (inter_cyl == 1) c = FLAME2_OFFSET.xz;
                        else c = FLAME3_OFFSET.xz;
                        
                        vec3 P = use_O + t*V;
                        vec3 N = vec3(normalize(P.xz - c), 0).xzy;
                        
                        final_color = vec3(0);
                        
                        if (inter_cyl != 0) final_color += get_flame_lighting_metal(V, P, flame_pos1, N, flame_light1);
                        if (inter_cyl != 1) final_color += get_flame_lighting_metal(V, P, flame_pos2, N, flame_light2);
                        if (inter_cyl != 2) final_color += get_flame_lighting_metal(V, P, flame_pos3, N, flame_light3);
                        
                        float x = -dot(N, V);
                        final_color += 0.915 * (0.9794513 + (-1.3955789 + (2.689428 + (-2.4966688 + 0.9153627*x)*x)*x)*x) * (flame_light1 + flame_light2 + flame_light3) * indirectLightScale;
                    }
                }
            }
            
            // Render the flames and wicks (the wicks are the only thing that is antialiased here)
            {
                float wick_mask = get_wick_mask(scale, offset, ray_O, rotation_matrix, view_plane_z, fragCoord,
                                                FLAME1_OFFSET + vec3(-0.001, -FLAME_OFFSET - 0.0, 0)*scale_factor,
                                                FLAME1_OFFSET + vec3(0.003, -FLAME_OFFSET + 0.045, -0.002)*scale_factor, 0.00065*scale_factor);
                
                if (pk_index != 2) {
                    wick_mask *= get_wick_mask(scale, offset, ray_O, rotation_matrix, view_plane_z, fragCoord,
                                               FLAME2_OFFSET + vec3(0.004, -FLAME_OFFSET - 0.001, -0.007)*scale_factor,
                                               FLAME2_OFFSET + vec3(-0.001, -FLAME_OFFSET + 0.047, 0.002)*scale_factor, 0.00065*scale_factor);
                }
                
                if (pk_index == 0) {
                    wick_mask *= get_wick_mask(scale, offset, ray_O, rotation_matrix, view_plane_z, fragCoord,
                                               FLAME3_OFFSET + vec3(0.004, -FLAME_OFFSET - 0.001, -0.007)*scale_factor,
                                               FLAME3_OFFSET + vec3(-0.001, -FLAME_OFFSET + 0.047, 0.002)*scale_factor, 0.00065*scale_factor);
                }
                
                vec3 flame_color = flame_z_boost1*render_flame2d(flame_uv1);
                
                if (pk_index != 2) flame_color += flame_z_boost2*render_flame2d(flame_uv2);
                if (pk_index == 0) flame_color += flame_z_boost3*render_flame2d(flame_uv3);
                
                // Not sure about this scaling factor.
                // I seemed to need too low a value, perhaps because of mistakes in the lighting elsewhere.
                flame_color *= 500. * CANDLELIGHT_SCALE; 

                final_color = wick_mask*final_color + (1.5 - wick_mask*0.5)*flame_color;
            }
            
            ambient = 0.;
        } else {
            // Need to render the cutout edge
            // We render the illumination from the candles here.
            // Illumination from outside the pumpkin is handled by the main function
            
            // Get ambient occlusion data from Buffer D
            
            float ao_inside, inside_dist;
            
            {
                vec3 P2 = origin + t_cutout*V;
                
                {
                    float pos = length(P2);
                    
                    vec3 dir = normalize(-P2);
                    
                    // TODO: use a larger radius_inner and smaller radius
                    float radius_inner = 0.;

                    if (pk_index==0) {
                        radius_inner = BOUND_RADIUS_INNER_PK1;
                    } else if (pk_index==1) {
                        radius_inner = BOUND_RADIUS_INNER_PK2;
                    } else {
                        radius_inner = BOUND_RADIUS_INNER_PK3;
                    }

                    float outside_dist;

                    {
                        vec2 pair = distance_to_pumpkin_shape(-dir, pk_index);
                        
                        inside_dist = pos - INNER_SHAPE_SCALE*pair.x;
                        outside_dist = pos - pair.y;
                    }
                    
                    fractional_distance = inside_dist / (inside_dist - outside_dist);
                    inside_dist = fractional_distance * 0.075;
                    
                    fract_dist_pix_scale = max(0.5, abs(inside_dist - outside_dist) * scale * (hits_cutout ? max(0.1, length(dir - dot(dir, V)*V)) : 0.1) * view_plane_z / t_cutout);
                }
                
                float edge_index_f = floor(0.5*edge_texture_pos);
                float point_frac = edge_texture_pos - 2.*edge_index_f;
                
                if (point_frac >= 1.5) {
                    point_frac = 0.;
                    edge_index_f += 1.;
                } else if (point_frac > 1.) {
                    point_frac = 1.;
                }
                
                int edge_index = 2 * int(edge_index_f);
                int texel_num = int(15.*point_frac);
                
                vec4 ao4 = texelFetch(iChannel3, ivec2((edge_index&255) + (texel_num >> 3), (texel_num & 7) + ((edge_index&256)>>5)), 0);
                
                N_surface2 = cutout_normal_decode(ao4);

                ao4 = cutout_AO_decode(ao4);
                
                ao_inside = clamp(interpolate_for_cutout_AO(fractional_distance, ao4), 0., 1.);
                ambient = clamp(interpolate_for_cutout_AO(1. - fractional_distance, ao4), 0., 1.);
                
                texel_num++;
                
                ao4 = texelFetch(iChannel3, ivec2((edge_index&255) + (texel_num >> 3),(texel_num & 7) + ((edge_index&256)>>5)), 0);
                
                point_frac = 15.*point_frac - floor(15.*point_frac);
                
                N_surface2 = mix(N_surface2, cutout_normal_decode(ao4), point_frac);
                
                ao4 = cutout_AO_decode(ao4);
                
                ao_inside = mix(ao_inside, clamp(interpolate_for_cutout_AO(fractional_distance, ao4), 0., 1.), point_frac);
                ambient = mix(ambient, clamp(interpolate_for_cutout_AO(1. - fractional_distance, ao4), 0., 1.), point_frac);
            }
            
            vec3 P2 = origin + t_cutout * V;

            N_surface2 = normalize(N_surface2);
            
            // Indirect light is uniform (inside of the pumpkin is a good diffuser) but gets modulated by AO
            final_color = (flame_light1 + flame_light2 + flame_light3)*indirectLightScale;
            
            // Direct light is also modulated by AO as a hack, to avoid having to treat candles as area or
            //      volume lights and ray march multiple samples (!)
            if (dot(V, N_surface2) < 0.) {
                final_color += 2. * get_flame_lighting(V, P2, flame_pos1, N_surface2, flame_light1);

                if (pk_index != 2) final_color += 2. * get_flame_lighting(V, P2, flame_pos2, N_surface2, flame_light2);
                if (pk_index == 0) final_color += 2. * get_flame_lighting(V, P2, flame_pos3, N_surface2, flame_light3);
            }
            
            final_color *= ao_inside;
            
            // Some fake light that might be from subsurface scattering or multiple bounces
            final_color += 2.0 * (flame_light1 + flame_light2 + flame_light3) * pow(vec3(0.6,0.25,0.0), vec3(1. + 50.*inside_dist));
            
            t_inter = scale*t_cutout;
        }
        
        return 1;
    }
    
    return 0;
}

// Decode packed data for the three Hermite spline segments used to represent shadowing on cutout edges
void decode_hermite_spline(vec4 data, out vec4 param1, out vec2 param2, out vec4 param3) {
    bool start_at_0 =  data.x < 0.;
    bool end_at_1 =  data.y < 0.;
    
    {
        uvec4 bits = (floatBitsToUint(data) >> 13) & 0x3fffu;
        
        {
            vec4 v = 1./128. * (vec4(bits.x & 127u, bits.x >> 7, bits.y & 127u, bits.y >> 7) + 0.5);

            {
                uint u = bits.x;
                
                if (data.z < 0.) u |= 0x4000u;
                
                v.x = 1./256. * (float(u & 255u) + 0.5);
                v.y = 1./128. * (float(u>>8) + 0.5);
            }

            
            param2 = v.zw;
        
            vec2 part1 = start_at_0 ? vec2(0, v.x) : vec2(v.x, 0);
        
            vec2 part2 = end_at_1 ? vec2(1, v.y) : vec2(v.y, 1);
            
            param1 = vec4(part1, part2);
        }
        
        if (start_at_0 && end_at_1) {
            param3 = 1./128. * (vec4(bits.z & 127u, bits.z >> 7, bits.w & 127u, bits.w >> 7) + 0.5);
        } else {
            vec3 v = 1./512. * (vec3(bits.z & 0x1ffu, (((bits.z >> 9) & 0x01fu) | (bits.w << 5)) & 0x1ffu, (bits.w >> 4) & 0x1ffu) + 0.5);
            
            param3 = vec4(start_at_0 ? v.x : 0., end_at_1 ? v.x : 0., v.yz);
        }
    }
}

// Integrate product of quadratic kernel and a constant function
float integ_constant_quad(float x_center, float start, float end, vec2 B) {
    float x1 = start - x_center;
    float x2 = end - x_center;
    
    return 1./3. * B.x * (x2*x2*x2 - x1*x1*x1) + B.y*(x2 - x1);
}

// Integrate product of quadratic kernel and a linear function
float integ_linear_quad(float x_center, float start, float end, vec4 hermite_points, vec2 B) {
    float A0 = (hermite_points.w - hermite_points.z)  / (hermite_points.y - hermite_points.x);
    float A1 = hermite_points.z - (hermite_points.x - x_center) * A0;
    
    float x1 = start - x_center;
    float x2 = end - x_center;
    
    float x1_2 = x1*x1;
    float x2_2 = x2*x2;
    
    return B.y * (A1*(x2 - x1) + 0.5*A0 * (x2_2 - x1_2)) + B.x * (1./3.*A1 * (x2*x2_2 - x1*x1_2) + 0.25*A0 * (x2_2*x2_2 - x1_2*x1_2));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    fragCoord -= 0.5*iResolution.xy;

    vec3 V;
    mat3 rotation_matrix;
    float view_plane_z;
    vec3 ray_O;
    
    {
        vec4 view_state1 = texelFetch(iChannel0, ivec2(8*3, 2*SPHERE_UV_DIM), 0);
        float view_state2 = texelFetch(iChannel0, ivec2(8*3 + 1, 2*SPHERE_UV_DIM), 0).x;
        
        ray_O = vec3(view_state1.zw + 0.5, -2.0);
    
        view_plane_z = exp(view_state2) * min(iResolution.x, iResolution.y);
        
        V = normalize(vec3(fragCoord, view_plane_z));

        rotation_matrix = make_camera_rotation_matrix(view_state1.xy);
    }

    V = rotation_matrix * V;
    
    ray_O = rotation_matrix * (ray_O - vec3(0.5,0.5,0.5)) + vec3(0.5, 0.5, 0.5);
    
    float t_inter = 10e20;
    int surface_index = -1;
    vec3 P_near;
    
    // Test for intersections with the outer box.
    // This box is also used to get bounds on the part of the ray that can intersect
    //      other objects in the scene.
    {
        vec2 tx = slab_nearfar(0. - ray_O.x, 1. - ray_O.x, 1./V.x);
        vec2 ty = slab_nearfar(0. - ray_O.y, 1. - ray_O.y, 1./V.y);
        vec2 tz = slab_nearfar(0. - ray_O.z, 1. - ray_O.z, 1./V.z);
            
        vec2 nf = vec2(max(tx.r, max(ty.r, tz.r)), min(tx.g, min(ty.g, tz.g)));
        
        if (nf.x >= nf.y) {
            fragColor = vec4(0);
            return;
        }
        
        t_inter = nf.y;
        
        if (t_inter == tx.g) surface_index = V.x < 0. ? INDEX_LEFT_WALL : INDEX_RIGHT_WALL;
        else if (t_inter == ty.g) surface_index = V.y < 0. ? INDEX_FLOOR : INDEX_CEILING;
        else surface_index = V.z < 0. ? -1 : INDEX_BACK_WALL;

        P_near = ray_O + nf.x*V;
    }
    
    bool bound_check;
    
    // quickly test if the ray could intersect the first box
    {
        vec3 P = ray_O + t_inter*V;
        
        bound_check = bound_overlap(min(P_near, P), max(P_near, P), BOX1_BOUND_LOW, BOX1_BOUND_HIGH);
    }
    
    vec2 box_coord;
    
    if (bound_check) {
        int side = 0;
        
        mat2 r = mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2));
        
        vec3 origin = ray_O;
        origin.xz = r * origin.xz;
        vec3 V2 = V;
        V2.xz = r * V2.xz;
        
        vec3 corner1 = vec3(0.25, 0., 0.45);
        vec3 corner2 = vec3(0.6, 0.55, 0.75);
        
        float t = intersect_box_near(corner1, corner2, 1./V2, origin, side);
        
        if (t < 1e18) {
            t_inter = t;
            
            vec3 p = origin + t * V2;
            
            if (side == 1) {
                box_coord = (p.zy - corner1.zy) / (corner2.zy - corner1.zy);
                surface_index = V2.x > 0. ? INDEX_LBLOCK_LEFT : INDEX_LBLOCK_RIGHT;
            } else if (side == 2) {
                if (V.y < 0.) {
                    box_coord = (p.xz - corner1.xz) / (corner2.xz - corner1.xz);
                    surface_index = INDEX_LBLOCK_TOP;
                } else {
                    surface_index = 100;
                }
            } else if (side == 4) {
                box_coord = (p.xy - corner1.xy) / (corner2.xy - corner1.xy);
                surface_index = V2.z > 0. ? INDEX_LBLOCK_FRONT : INDEX_LBLOCK_BACK;
            }
        }
    }
    
    // quickly test if the ray could intersect the second box
    {
        vec3 P = ray_O + t_inter*V;
        
        bound_check = bound_overlap(min(P_near, P), max(P_near, P), BOX2_BOUND_LOW, BOX2_BOUND_HIGH);
    }
    
    if (bound_check) {
        int side = 0;
        
        mat2 r = mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11));
        
        vec3 origin = ray_O;
        origin.xz = r * origin.xz;
        vec3 V2 = V;
        V2.xz = r * V2.xz;
        
        vec3 corner1 = vec3(0.55, 0., 0.45);
        vec3 corner2 = vec3(0.85, 0.3, 0.75);
        
        float t = intersect_box_near(corner1, corner2, 1./V2, origin, side);
        
        if (t < 1e18 && t < t_inter) {
            t_inter = t;
            
            vec3 p = origin + t * V2;
            
            if (side == 1) {
                box_coord = (p.zy - corner1.zy) / (corner2.zy - corner1.zy);
                surface_index = V2.x > 0. ? INDEX_RBLOCK_LEFT : INDEX_RBLOCK_RIGHT;
            } else if (side == 2) {
                if (V.y < 0.) {
                    box_coord = (p.xz - corner1.xz) / (corner2.xz - corner1.xz);
                    surface_index = INDEX_RBLOCK_TOP;
                } else {
                    surface_index = 100;
                }
            } else if (side == 4) {
                box_coord = (p.xy - corner1.xy) / (corner2.xy - corner1.xy);
                surface_index = V2.z > 0. ? INDEX_RBLOCK_FRONT : INDEX_RBLOCK_BACK;
            }
        }
    }
    
    vec3 N_surface, N_surface2;
    vec3 final_color = vec3(0);
    float ambient = 0., alpha_blend = 1., edge_texture_pos, fractional_distance, fract_dist_pix_scale;
    
    // Get bitmask indicating which pumpkins and stalks the ray could possibly intersect, and ray march
    //      them if this bitmask is non-zero
    {
        float pk_mask = 0.;
        
        vec3 low, high;
        
        {
            vec3 P = ray_O + t_inter*V;
            
            low = min(P_near, P);
            high = max(P_near, P);
        }
        
        vec3 rV = 1./V;
        
        if (bound_overlap(low, high, PK1_BOUND_LOW, PKSTALK1_BOUND_HIGH)) {
            if (intersect_sphere(PUMPKIN1_OFFSET, BOUND_RADIUS_PK1 * PUMPKIN1_SCALE, V, ray_O) < t_inter) pk_mask += 1.;
            if (intersect_sphere(STALK1_OFFSET + vec3(0, STALK1_BOUND_Y * STALK1_SCALE, 0), STALK1_BOUND_RADIUS * STALK1_SCALE, V, ray_O) < t_inter
                    && test_intersect_box(STALK1_BOUND_LOW, STALK1_BOUND_HIGH, rV, ray_O)) pk_mask += 16.;
        }
        
        if (bound_overlap(low, high, PK2_BOUND_LOW, PKSTALK2_BOUND_HIGH)) {
            if (intersect_sphere(PUMPKIN2_OFFSET, BOUND_RADIUS_PK2 * PUMPKIN2_SCALE, V, ray_O) < t_inter) pk_mask += 2.;
            if (intersect_sphere(STALK2_OFFSET + vec3(0, STALK2_BOUND_Y * STALK2_SCALE, 0), STALK2_BOUND_RADIUS * STALK2_SCALE, V, ray_O) < t_inter
                    && test_intersect_box(STALK2_BOUND_LOW, STALK2_BOUND_HIGH, rV, ray_O)) pk_mask += 32.;
        }
        
        if (bound_overlap(low, high, PK3_BOUND_LOW, PKSTALK3_BOUND_HIGH)) {
            if (intersect_sphere(PUMPKIN3_OFFSET, BOUND_RADIUS_PK3 * PUMPKIN3_SCALE, V, ray_O) < t_inter) pk_mask += 4.;
            if (intersect_sphere(STALK3_OFFSET + vec3(0, STALK3_BOUND_Y * STALK3_SCALE, 0), STALK3_BOUND_RADIUS * STALK3_SCALE, V, ray_O) < t_inter
                    && test_intersect_box(STALK3_BOUND_LOW, STALK3_BOUND_HIGH, rV, ray_O)) pk_mask += 64.;
        }
        
        if (pk_mask != 0.) {
            int pk_index;
            
            int surface_type = render_pumpkin(int(pk_mask), final_color, t_inter, ray_O, V, view_plane_z, N_surface, N_surface2, pk_index,
                                              fragCoord, rotation_matrix, ambient, alpha_blend, edge_texture_pos, fractional_distance, fract_dist_pix_scale);
            
            if (surface_type != 0) {
                surface_index = (surface_type == 1 ? INDEX_PUMPKIN1 : INDEX_STALK1) + pk_index;
            }
            
            if (surface_type == 1) {
                final_color *= 1. - alpha_blend;
            } else {
                alpha_blend = 1.;
            }
        }
    }

    if (alpha_blend >= 0.995) ambient = 0.;
    
    if (surface_index >= 0 && (alpha_blend > 0.005 || ambient > 0.005)) {
        vec3 surface_P = ray_O + t_inter*V;
        
        if (surface_index == INDEX_FLOOR) {
            // Warp the mesh coordinates so the lighting looks better near some of the corners of the two boxes
            
            surface_P.xz = push_point(surface_P.xz, vec2(0.55, 0.45) * mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11)), 0.04);
            surface_P.xz = push_point(surface_P.xz, vec2(0.55, 0.75) * mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11)), 0.04);
            
            // This one doesn't work well, perhaps because of the grid alignment
            //surface_P.xz = push_point(surface_P.xz, vec2(0.85, 0.75) * mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11)), 0.015);
            
            surface_P.xz = push_point(surface_P.xz, vec2(0.25, 0.45) * mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2)), 0.03);
            surface_P.xz = push_point(surface_P.xz, vec2(0.25, 0.75) * mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2)), 0.03);
        }
        
        // Get coordinates for looking up direct and indirect light
        // Get surface normal vector if we don't already have it
        // Get the index of the mesh we want to use, if not the same as surface_index
        
        vec2 coord = box_coord;

        bool have_direct = true;
        bool unshadowed = false;
        int high_res_dim = 0;
            
        switch (surface_index) {
        case INDEX_FLOOR:
            coord = surface_P.xz;
            high_res_dim = HIGH_RES_DIM_FLOOR;
            N_surface = vec3(0,1,0);
            break;
        case INDEX_LEFT_WALL:
            coord = surface_P.zy;
            high_res_dim = HIGH_RES_DIM_WALL;
            N_surface = vec3(1,0,0);
            break;
        case INDEX_RIGHT_WALL:
            coord = surface_P.zy;
            high_res_dim = HIGH_RES_DIM_WALL;
            N_surface = vec3(-1,0,0);
            break;
        case INDEX_BACK_WALL:
            coord = surface_P.xy;
            high_res_dim = HIGH_RES_DIM_BACK_WALL;
            N_surface = vec3(0,0,-1);
            break;
        case INDEX_CEILING:
            coord = surface_P.xz;
            have_direct = false;
            N_surface = vec3(0,-1,0);
            break;
        case INDEX_LBLOCK_TOP:
            high_res_dim = HIGH_RES_DIM_BLOCK_TOP;
            N_surface = vec3(0,1,0);
            break;
        case INDEX_RBLOCK_TOP:
            high_res_dim = HIGH_RES_DIM_BLOCK_TOP;
            N_surface = vec3(0,1,0);
            break;
        
        case INDEX_LBLOCK_LEFT:
            have_direct = false;
            N_surface = vec3(-cos(0.2), 0, -sin(0.2));
            break;
        case INDEX_RBLOCK_LEFT:
            unshadowed = true;
            N_surface = vec3(-cos(0.11), 0, sin(0.11));
            break;
        case INDEX_LBLOCK_FRONT:
            unshadowed = true;
            N_surface = vec3(sin(0.2), 0, -cos(0.2));
            break;
        case INDEX_RBLOCK_FRONT:
            have_direct = false;
            N_surface = vec3(-sin(0.11), 0, -cos(0.11));
            break;
        case INDEX_LBLOCK_RIGHT:
            unshadowed = true;
            N_surface = vec3(cos(0.2), 0, sin(0.2));
            break;
        case INDEX_RBLOCK_RIGHT:
            have_direct = false;
            N_surface = vec3(cos(0.11), 0, -sin(0.11));
            break;
        case INDEX_LBLOCK_BACK:
            have_direct = false;
            N_surface = vec3(-sin(0.2), 0, cos(0.2));
            break;
        case INDEX_RBLOCK_BACK:
            have_direct = false;
            N_surface = vec3(sin(0.11), 0, cos(0.11));
            break;
        }
        
        coord = clamp(coord, 0.0, 0.9999);
        
        vec2 coord_mapped = map_coords_from_linear(surface_index, coord);
        ivec2 mesh_coord_save;
        vec2 frac_coord_save;

        // TODO: clear have_direct for more regions
        
        // Fetch and interpolate direct lighting for the mesh, if applicable, and render using BRDF
        if (have_direct) {
            ivec2 mesh_coord = surface_index == INDEX_FLOOR ? ivec2(INDEX_FLOOR00 << MESH_DIM_SHIFT, 0) : ivec2(surface_index << MESH_DIM_SHIFT, 0);
                
            int use_dim;
            vec2 use_coord;
            bool samples_at_edges = false;
            
            bool possibly_shadowed = ! unshadowed;
            bool definitely_shadowed = false;
            
            if ( ! unshadowed) {
                if (surface_index >= INDEX_STALK1) {
                    if (N_surface != vec3(0,-1,0)) {
                        float scale, warp;
                        vec3 offset;
                        mat3 mtx;

                        if (surface_index == INDEX_STALK1) {
                            offset = STALK1_OFFSET;
                            scale = 1./STALK1_SCALE;
                            mtx = STALK1_RMTX;
                            warp = STALK1_WARP;
                        } else if (surface_index == INDEX_STALK2) {
                            offset = STALK2_OFFSET;
                            scale = 1./STALK2_SCALE;
                            mtx = STALK2_RMTX;
                            warp = STALK2_WARP;
                        } else {
                            offset = STALK3_OFFSET;
                            scale = 1./STALK3_SCALE;
                            mtx = STALK3_RMTX;
                            warp = STALK3_WARP;
                        }
                        
                        vec3 P = scale * (mtx * (surface_P - offset));
                        
                        P.x += warp * P.y*P.y;
                        
                        use_coord = vec2(40./(2.*PI) * atan(P.z, P.x), P.y);
                        
                        mesh_coord = ivec2(HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL, HIGH_RES_Y_OFFSET + HIGH_RES_DIM_WALL + (surface_index - INDEX_STALK1)*16);
                        
                        use_dim = 1024;
                    } else {
                        possibly_shadowed = false;
                        
                        vec3 offset;
            
                        if (surface_index == INDEX_STALK1) {
                            offset = STALK1_OFFSET + vec3(0, STALK1_SCALE*STALK1_BOUND_Y, 0);
                        } else if (surface_index == INDEX_STALK2) {
                            offset = STALK2_OFFSET + vec3(0, STALK2_SCALE*STALK2_BOUND_Y, 0);
                        } else {
                            offset = STALK3_OFFSET + vec3(0, STALK3_SCALE*STALK3_BOUND_Y, 0);
                        }

                        N_surface = normalize(surface_P - offset);
                    }
                } else if (surface_index >= INDEX_PUMPKIN1) {
                    // For pumpkins, we have shadow data for only a small rectangle (not the full uv sphere) and it needs special coordinates
                    
                    vec3 offset;
                    float margin1;
                    vec4 shadow_rect;
            
                    if (surface_index==INDEX_PUMPKIN1) {
                        offset = PUMPKIN1_OFFSET;
                        margin1 = -0.13;
                        shadow_rect = vec4(0.24,0.32, 0.235,0.3);
                        mesh_coord = ivec2(11*MESH_DIM - 1, -1);
                    } else if (surface_index==INDEX_PUMPKIN2) {
                        offset = PUMPKIN2_OFFSET;
                        margin1 = -0.25;
                        shadow_rect = vec4(0.615, 0.75, 0.24, 0.365);
                        mesh_coord = ivec2(11*MESH_DIM + TOP_SHADOW_MAP_DIM - 1, -1);
                    } else {
                        offset = PUMPKIN3_OFFSET;
                        margin1 = -0.18;
                        shadow_rect = vec4(0.76, 0.865, 0.503, 0.588);
                        mesh_coord = ivec2(-1, HIGH_RES_Y_OFFSET + HIGH_RES_DIM_FLOOR - 32 - 1);
                    }

                    vec3 dir = normalize(surface_P - offset);
                    
                    if (dot(normalize(vec3(0.5,1,0.5) - surface_P), N_surface) > margin1) {
                        use_coord = surface_P.xz;
                        
                        if (surface_index==INDEX_PUMPKIN2) {
                            float a = 0.25*PI;
                            use_coord = mat2(cos(a), -sin(a), sin(a), cos(a)) * use_coord;
                        }
                        
                        use_coord = (use_coord - shadow_rect.xz) / (shadow_rect.yw - shadow_rect.xz);
                        
                        possibly_shadowed = use_coord.x > 0. && use_coord.y > 0. && use_coord.x < 1. && use_coord.y < 1.;
                    } else {
                        possibly_shadowed = false;
                        definitely_shadowed = true;
                    }
                    
                    use_dim = TOP_SHADOW_MAP_DIM + 2;
                    
                    use_coord *= float(TOP_SHADOW_MAP_DIM + 1);
                } else {
                    use_coord = coord_mapped;

                    if (surface_index <= INDEX_RBLOCK_TOP) {
                        use_dim = high_res_dim;
                        use_coord = coord;
                        samples_at_edges = true;
                        
                        switch (surface_index) {
                        case INDEX_FLOOR:
                            mesh_coord = ivec2(0, HIGH_RES_Y_OFFSET);
                            break;
                        case INDEX_LEFT_WALL:
                            mesh_coord = ivec2(HIGH_RES_DIM_FLOOR, HIGH_RES_Y_OFFSET);
                            break;
                        case INDEX_RIGHT_WALL:
                            mesh_coord = ivec2(HIGH_RES_DIM_FLOOR, HIGH_RES_Y_OFFSET + HIGH_RES_DIM_WALL);
                            break;
                        case INDEX_BACK_WALL:
                            mesh_coord = ivec2(HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL, HIGH_RES_Y_OFFSET);
                            break;
                        case INDEX_LBLOCK_TOP:
                            mesh_coord = ivec2(HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL + HIGH_RES_DIM_BACK_WALL, HIGH_RES_Y_OFFSET);
                            break;
                        //case INDEX_RBLOCK_TOP:
                        default:
                            mesh_coord = ivec2(HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL + HIGH_RES_DIM_BACK_WALL, HIGH_RES_Y_OFFSET + HIGH_RES_DIM_BLOCK_TOP);
                            break;
                        }
                        
                        use_coord = use_coord * float(use_dim - 1);
                        
                        
                        if (surface_index == INDEX_FLOOR && use_coord.x < 46. && use_coord.y > float(HIGH_RES_DIM_FLOOR - 46)) {
                            possibly_shadowed = false;
                            definitely_shadowed = true;
                        }
                        
                    } else {
                        mesh_coord = ivec2(surface_index << MESH_DIM_SHIFT, 0);
                        
                        use_dim = MESH_DIM;
                        samples_at_edges = false;
                        
                        use_coord = use_coord * float(use_dim) - 0.5;
                    }
                }
            }
            
            vec4 shadow_data;
            
            if (possibly_shadowed) {
                // Fetch shadowing data
                shadow_data = interpolate_map_iChannel1(use_dim, surface_index, mesh_coord, use_coord);
                
                // Save some data that we need in the stalk case (because it was expensive to compute)
                mesh_coord_save = mesh_coord;
                frac_coord_save = use_coord;
                
                // If using low-res mesh, we don't have data for the four quadrants, so just use same fraction for all four
                if (surface_index > INDEX_RBLOCK_TOP && surface_index < INDEX_PUMPKIN1) shadow_data = vec4(shadow_data.b);
            } else {
                shadow_data = vec4(definitely_shadowed ? 0 : 1);

                mesh_coord_save = ivec2(HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL + 10, HIGH_RES_Y_OFFSET + HIGH_RES_DIM_WALL + (surface_index - INDEX_STALK1)*16 + 15);
                frac_coord_save = vec2(0);
            }
            
            if (dot(shadow_data, vec4(1)) > 0.001) {
                vec3 diffuse_color, diffuse_curve;
                float fresnel_base, ggx_alpha;
                int fresnel_exponent;
                
                if (surface_index >= INDEX_STALK1) {
                    diffuse_color = STALK_DIFFUSE_COLOR;
                    diffuse_curve = vec3(0.10591985, 0.06069383, 0.11740058);
                    fresnel_base = 0.15;
                    ggx_alpha = 0.5;
                    fresnel_exponent = 3;
                } else if (surface_index >= INDEX_PUMPKIN1) {
                    diffuse_color = PUMPKIN_DIFFUSE_COLOR;
                    diffuse_curve = vec3(0.04344538, 0.04786321, 0.14475393);
                    fresnel_base = PUMPKIN_FRESNEL_BASE;
                    ggx_alpha = 0.29;
                    fresnel_exponent = 4;
                } else {
                    diffuse_curve = vec3(0); // TODO: fix, and remove special case
                    fresnel_base = 0.;
                    ggx_alpha = 0.37;
                    fresnel_exponent = 3;
                    
                    if (surface_index == INDEX_LEFT_WALL) diffuse_color = LEFT_WALL_DIFFUSE_COLOR;
                    else if (surface_index == INDEX_RIGHT_WALL) diffuse_color = RIGHT_WALL_DIFFUSE_COLOR;
                    else diffuse_color = DEFAULT_DIFFUSE_COLOR;
                }
                
                #if SHOW_DIRECT_LIGHT
                final_color += alpha_blend * LIGHT_SCALE * area_light_sample(V, surface_P, N_surface, shadow_data, diffuse_color, diffuse_curve, fresnel_base, ggx_alpha, fresnel_exponent);
                #endif
            }
        }

        {
            // Get coordinates for accessing indirect data in Buffer C
            
            ivec2 mesh_coord = surface_index == INDEX_FLOOR ? ivec2(INDEX_FLOOR00 << MESH_DIM_SHIFT, 0) : ivec2(surface_index << MESH_DIM_SHIFT, 0);
        
            int use_dim = surface_index == INDEX_FLOOR ? 2*MESH_DIM : MESH_DIM;
            vec2 use_coord = coord_mapped;
            float pk_x, pk_x2;
            
            if (surface_index >= INDEX_STALK1 && surface_index <= INDEX_STALK3) {
                mesh_coord = mesh_coord_save;
                use_coord = frac_coord_save;
                // use_dim shouldn't matter
            } else if (surface_index >= INDEX_PUMPKIN1 && surface_index <= INDEX_PUMPKIN3) {
                vec3 offset;
                float scale;
        
                if (surface_index==INDEX_PUMPKIN1) {
                    offset = PUMPKIN1_OFFSET;
                    scale = PUMPKIN1_SCALE;
                } else if (surface_index==INDEX_PUMPKIN2) {
                    offset = PUMPKIN2_OFFSET;
                    scale = PUMPKIN2_SCALE;
                } else {
                    offset = PUMPKIN3_OFFSET;
                    scale = PUMPKIN3_SCALE;
                }
                
                vec3 dir = normalize(surface_P - offset);
            
                float phi = atan(dir.z, dir.x);
                float theta = asin(dir.y);
                
                vec3 T = vec3(sin(phi), 0., -cos(phi));

                vec3 N = pumpkin_local_basis_normal_fast(dir, 1./scale * distance(surface_P, offset), surface_index - INDEX_PUMPKIN1);
        
                T = normalize(T - dot(T, N)*N);
        
                pk_x = dot(N_surface, T);
                
                if (ambient > 0.005) {
                    pk_x2 = dot(N_surface2, T);
                }
                
                use_coord = vec2(1./PI * vec2(0.5, 1.) * vec2(phi, theta) + 0.5);
                
                use_coord.y = pumpkin_map_squished_to_01(use_coord.y);
                
                use_dim = SPHERE_UV_DIM;
                mesh_coord = CHOOSE3(surface_index==INDEX_PUMPKIN1, surface_index==INDEX_PUMPKIN2,
                                     ivec2(0, 2*MESH_DIM), ivec2(SPHERE_UV_DIM, 2*MESH_DIM), ivec2(2*SPHERE_UV_DIM, 2*MESH_DIM));
            }
            
            vec3 irradiance;
            
            {
                bool is_sphere = surface_index >= INDEX_PUMPKIN1 && surface_index <= INDEX_PUMPKIN3;
                ivec2 ic00;
                int x_inc;
                
                if (surface_index < INDEX_STALK1) {
                    ic00 = prepare_interpolate_coord(use_dim, false, is_sphere, use_coord);
                    x_inc = 1;
                } else {
                    use_dim = 1024;
                    ic00 = ivec2(64, 0);

                    x_inc = 1;
                    
                    if (mesh_coord.x == HIGH_RES_DIM_FLOOR + HIGH_RES_DIM_WALL + 39) x_inc = -39;
                    mesh_coord.x -= 64;
                }
                
                irradiance = interpolate_map_iChannel2_inner(use_dim-1, mesh_coord, ic00, use_coord, x_inc);
            
                if (surface_index >= INDEX_PUMPKIN1 && surface_index <= INDEX_PUMPKIN3) {
                    // Pumpkins have data for three different directions (different surface normals)
                    // Fetch the other two
                    
                    mesh_coord = CHOOSE3(surface_index==INDEX_PUMPKIN1, surface_index==INDEX_PUMPKIN2,
                                     ivec2(3*SPHERE_UV_DIM, 2*MESH_DIM), ivec2(4*SPHERE_UV_DIM, 2*MESH_DIM), ivec2(0, 2*MESH_DIM+SPHERE_UV_DIM));
                                     
                    vec3 comp1 = interpolate_map_iChannel2_inner(SPHERE_UV_DIM-1, mesh_coord, ic00, use_coord, 1).rgb;        
                    mesh_coord = CHOOSE3(surface_index==INDEX_PUMPKIN1, surface_index==INDEX_PUMPKIN2,
                                     ivec2(SPHERE_UV_DIM, 2*MESH_DIM+SPHERE_UV_DIM), ivec2(2*SPHERE_UV_DIM, 2*MESH_DIM+SPHERE_UV_DIM), ivec2(4*SPHERE_UV_DIM, 2*MESH_DIM+SPHERE_UV_DIM));
                                     
                    vec3 comp2 = interpolate_map_iChannel2_inner(SPHERE_UV_DIM-1, mesh_coord, ic00, use_coord, 1).rgb;
                    
                    if (ambient > 0.005) {
                        // estimate indirect irradiance for cutout edge, taking into account the surface normal
                        
                        float d = -dot(V, N_surface2);
                    
                        vec4 factors = vec4(0.10591985, 0.06069383, 0.11740058, 0.8722);
                        vec3 diffuse_color = vec3(0.9, 0.8, 0.1);
                    
                        float w = evaluate_diffuse_curve(d, factors.xyz);
                        
                        float f1 = 3.20912199e-04 + (-1.01676965 + (1.55960385 + (0.470790080 - 0.460981834*pk_x2) * pk_x2) * pk_x2) * pk_x2;
                        float f2 = 3.20912199e-04 + (1.01676965 + (1.55960385 + (-0.470790080 - 0.460981834*pk_x2) * pk_x2) * pk_x2) * pk_x2;
                        float f0 = 1. - f1 - f2;
                
                        final_color += (1. - alpha_blend) * ambient * LIGHT_SCALE * (f0*irradiance + f1*comp1 + f2*comp2) * ((1. - w) + factors.w * w * diffuse_color);
                    }

                    {
                        // estimate indirect irradiance for pumpkin surface, taking into account the surface normal
                        
                        float f1 = 3.20912199e-04 + (-1.01676965 + (1.55960385 + (0.470790080 - 0.460981834*pk_x) * pk_x) * pk_x) * pk_x;
                        float f2 = 3.20912199e-04 + (1.01676965 + (1.55960385 + (-0.470790080 - 0.460981834*pk_x) * pk_x) * pk_x) * pk_x;
                        float f0 = 1. - f1 - f2;
                
                        irradiance = f0*irradiance + f1*comp1 + f2*comp2;
                    }
                }
            }
            
            // Shade using diffuse lighting
            
            {
                vec2 diff_and_spec;
                vec3 diffuse_color;

                float d = dot(-V, N_surface);
                
                if (surface_index >= INDEX_PUMPKIN1) {
                    vec4 factors;
                    
                    if (surface_index >= INDEX_STALK1) {
                        diffuse_color = STALK_DIFFUSE_COLOR;
                        factors = vec4(0.10591985, 0.06069383, 0.11740058, 0.8722);
                    } else {
                        diffuse_color = PUMPKIN_DIFFUSE_COLOR;
                        factors = vec4(0.04344538, 0.04786321, 0.14475393, 0.9341);
                    }
                
                    float w = evaluate_diffuse_curve(d, factors.xyz);
                    
                    diff_and_spec = vec2(factors.w * w, 1. - w);
                } else {
                    if (surface_index == INDEX_LEFT_WALL) diffuse_color = LEFT_WALL_DIFFUSE_COLOR;
                    else if (surface_index == INDEX_RIGHT_WALL) diffuse_color = RIGHT_WALL_DIFFUSE_COLOR;
                    else diffuse_color = DEFAULT_DIFFUSE_COLOR;

                    float t = 1. - d;
                    
                    diff_and_spec = vec2(0.875 - 0.219*d*d, 0.0272 + 0.0928*t*t);
                }
                
                #if SHOW_INDIRECT_LIGHT
                final_color += alpha_blend * LIGHT_SCALE * (diff_and_spec.x*diffuse_color + diff_and_spec.y) * irradiance;
                #endif
            }
        }
    }
    
    // For cutout edges, we get the direct light separately, using data from Buffer D
    if (ambient > 0.005 && alpha_blend < 0.995) {
        float edge_index_f = floor(0.5*edge_texture_pos);
        float point_frac = edge_texture_pos - 2.*edge_index_f;
        
        if (point_frac >= 1.5) {
            point_frac = 0.;
            edge_index_f += 1.;
        } else {
            point_frac = min(point_frac, 1.);
        }
        
        bool need_direct = false;
        
        {
            int index = int(edge_index_f);
            
            if (surface_index == INDEX_PUMPKIN1) {
                need_direct = index >= 3 && index < 6;
            } else if (surface_index == INDEX_PUMPKIN2) {
                index -= 2*21;
                
                if (index >= 0 && index < 92) {
                    need_direct = ((index < 32 ? 263443401 : index < 64 ? 15902 : 377344) & (1 << (index&31))) != 0;
                }
            } else {
                index -= 2*21 + 92;
                
                need_direct = (index >= 8 && index < 16) || index==59 || (index >= 81 && index < 93);
            }
        }
        
        vec3 max_contrib;
            
        if (need_direct) {
            vec3 P = ray_O + t_inter*V;
            
            float f = eval_area_light_clipped(P, N_surface2);

            if (f > 0.001) {
                vec3 source_P = vec3(0.5, 1, 0.5);
                
                vec3 L = source_P - P;
                
                max_contrib = (1. - alpha_blend) * LIGHT_SCALE * f * BRDF_inside(-V, normalize(L), N_surface2, false);
                
                need_direct = dot(max_contrib, vec3(1)) > 0.005;
            } else {
                need_direct = false;
            }
        }

        if (need_direct) {
            const float SHADOW_SPLINE_P_LOW = 0.43;
            const float SHADOW_SPLINE_P_HIGH = 0.82;
            const vec4 SHADOW_SPLINE_SLOPE_SCALE = vec4(0.4, 1, 0.6, 0.5);
            
            vec4 param1;
            vec2 param2;
            vec4 param3;
            
            {
                int edge_index = 2 * int(edge_index_f);
                int texel_num = int(15.*point_frac);
                
                decode_hermite_spline(texelFetch(iChannel3, ivec2((edge_index&255) + (texel_num >> 3), 16 + (texel_num & 7) + ((edge_index&256)>>5)), 0), param1, param2, param3);
                
                texel_num++;
                
                vec4 param1_b;
                vec2 param2_b;
                vec4 param3_b;
                
                decode_hermite_spline(texelFetch(iChannel3, ivec2((edge_index&255) + (texel_num >> 3), 16 + (texel_num & 7) + ((edge_index&256)>>5)), 0), param1_b, param2_b, param3_b);
                
                point_frac = 15.*point_frac - floor(15.*point_frac);
            
                param1 = mix(param1, param1_b, point_frac);
                param2 = mix(param2, param2_b, point_frac);
                param3 = mix(param3, param3_b, point_frac);
            }
            
            param3 *= SHADOW_SPLINE_SLOPE_SCALE;
            
            float t = fractional_distance;
            float p_low = param1.x + SHADOW_SPLINE_P_LOW*(param1.z - param1.x);
            float p_high = param1.x + SHADOW_SPLINE_P_HIGH*(param1.z - param1.x);
            
            float radius = 0.7 / fract_dist_pix_scale;
            vec2 B = vec2(-0.75 / (radius*radius*radius), 0.75 / radius);
            
            float start0 = t - radius;
            float end0 = t + radius;
            
            float sum = 0.;
            
            if (t > param1.x && t < param1.z) {
                vec4 r;
                vec2 s;
                
                if (t < p_low) r = vec4(param1.x, p_low, param1.y, param2.x), s = vec2(param3.x, param3.z);
                else if (t < p_high) r = vec4(p_low, p_high, param2.x, param2.y), s = vec2(param3.z, param3.w);
                else r = vec4(p_high, param1.z, param2.y, param1.w), s = vec2(param3.w, param3.y);
                
                float v;
                
                {
                    float u = clamp((t - r.x) / (r.y - r.x), 0., 1.);

                    float dy = r.w - r.z;
                    
                    v = (((s.x + s.y - 2.*dy)*u + (3.*dy - 2.*s.x - s.y))*u + s.x)*u + r.z;
                }
                
                sum = integ_linear_quad(t, max(start0, r.x), t, vec4(r.x, t, r.z, v), B);
                sum += integ_linear_quad(t, t, min(end0, r.y), vec4(t, r.y, v, r.w), B);
            }
            
            {
                float start = max(start0, param1.x);
                float end = min(end0, p_low);
                
                if (start < end && (t < start || t > end)) sum += integ_linear_quad(t, start, end, vec4(param1.x, p_low, param1.y, param2.x), B);
            }
            
            {
                float start = max(start0, p_low);
                float end = min(end0, p_high);
                
                if (start < end && (t < start || t > end)) sum += integ_linear_quad(t, start, end, vec4(p_low, p_high, param2.x, param2.y), B);
            }
            
            {
                float start = max(start0, p_high);
                float end = min(end0, param1.z);
                
                if (start < end && (t < start || t > end)) sum += integ_linear_quad(t, start, end, vec4(p_high, param1.z, param2.y, param1.w), B);
            }
            
            {
                float start = max(start0, param1.z);
                float end = end0;
                
                if (start < end) sum += param1.w * integ_constant_quad(t, start, end, B);
            }
            
            if (param1.y > 0.) {
                float start = start0;
                float end = min(end0, param1.x);
                
                if (start < end) sum += param1.y * integ_constant_quad(t, start, end, B);
            }
            
            final_color += sum * max_contrib;
        }
    }
    
    final_color = tone_map_and_gamut_clip(final_color);
    
    // Render the area light (anti-aliased quadrilateral)
    if (surface_index == INDEX_CEILING && ray_O.y < 1. && V.y > 0.) {
        // Get intersection of view ray with the plane containing the light
        // (re-doing this to save the shader code from having to keep those
        //          5 values in registers)
        float light_t = (1. - ray_O.y) / V.y;
        
        if (light_t > 0.) {
            vec3 p = ray_O + light_t*V;
            vec2 coord = p.xz;

            float alpha = 1.; // blending factor for the light (1 = opaque)
            
            vec2 minmax_i = vec2(0.5-0.1, 0.5+0.1);
            vec2 minmax_j = vec2(0.5-0.1, 0.5+0.1);
            
            // anti-alias edges if we need to
            if (coord.x < minmax_j.x || coord.x > minmax_j.y || coord.y < minmax_i.x || coord.y > minmax_i.y) {

                // Get the 3D points for the corners of the light
                vec3 P1, P2, P3, P4;
                
                {
                    float y = 1.;
                
                    P1 = vec3(minmax_j.x, y, minmax_i.x);
                    P2 = vec3(minmax_j.y, y, minmax_i.x);
                    P3 = vec3(minmax_j.y, y, minmax_i.y);
                    P4 = vec3(minmax_j.x, y, minmax_i.y);
                }
                
                P1 = (P1-ray_O)*rotation_matrix;
                P2 = (P2-ray_O)*rotation_matrix;
                P3 = (P3-ray_O)*rotation_matrix;
                P4 = (P4-ray_O)*rotation_matrix;
                
                P1.xy *= view_plane_z / P1.z;
                P2.xy *= view_plane_z / P2.z;
                P3.xy *= view_plane_z / P3.z;
                P4.xy *= view_plane_z / P4.z;
                
                const float edge_dist = 2.;
                
                // anti-alias the edges
                if (coord.y < minmax_i.x) alpha *= 1. - get_edge_antialias_alpha(fragCoord, P1.xy, P2.xy, edge_dist);
                if (coord.x > minmax_j.y) alpha *= 1. - get_edge_antialias_alpha(fragCoord, P2.xy, P3.xy, edge_dist);
                if (coord.y > minmax_i.y) alpha *= 1. - get_edge_antialias_alpha(fragCoord, P3.xy, P4.xy, edge_dist);
                if (coord.x < minmax_j.x) alpha *= 1. - get_edge_antialias_alpha(fragCoord, P4.xy, P1.xy, edge_dist);
                
                // prevent the anti-aliased corners from stretching too far
                if (alpha != 0.) {
                    vec2 V1 = normalize(P1.xy - P2.xy);
                    vec2 V4 = normalize(P4.xy - P1.xy);
                    
                    float d = dot(fragCoord - P1.xy, normalize(V1 - V4));

                    vec2 V2 = normalize(P2.xy - P3.xy);
                    
                    d = max(d, dot(fragCoord - P2.xy, normalize(V2 - V1)));
                    
                    vec2 V3 = normalize(P3.xy - P4.xy);
                    
                    d = max(d, dot(fragCoord - P3.xy, normalize(V3 - V2)));
                    d = max(d, dot(fragCoord - P4.xy, normalize(V4 - V3)));
                    
                    alpha *= 1. - smoothstep(edge_dist, 2.*edge_dist, d);
                }
            }
            
            // Fade the light out when seen from the side to avoid artifacts
            if (alpha != 0.) {
                float t = V.y;
                
                alpha *= smoothstep(0., 0.02, t);
            }
        
            final_color = mix(final_color, vec3(1), alpha);
        }
    }

    final_color = LINEAR_TO_SRGB(final_color);

    fragColor = vec4(final_color, 1.0);
}
