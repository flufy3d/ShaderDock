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

    Overview:
    This is a fairly straightforward ray-casting renderer, which uses irradiance 
    data computed in the first few frames as part of its lighting calculations. 
    The weirdest part is probably the way the cutout shapes are handled.

    Ray marching is used for the pumpkin and stalk shapes. The ray marcher uses 
    2nd-order information (directional derivatives) to help avoid distortion or 
    noise at edges and allow using functions that aren't quite SDFs. This is 
    practical because the functions are relatively simple, with cheap partial 
    derivatives. Having partial derivatives also makes computing surface normals 
    trivial.

    The cutout shapes also use ray marching, but it is performed in 2D instead of 
    3D, after projecting the 3D ray into 2D using a transformation similar to 
    perspective projection. This transformation gives lines at the corners that 
    radiate out from the center of the pumpkin. The shapes are vector data that 
    was prepared in advance. I think I probably *could* have implemented ray 
    marching of these shapes just using shader code, but there are a lot of line 
    segments (over 200 in total!) and I decided to encode the shapes compactly 
    (using 8-bit coordinate values) and expand them into a grid of cells that can 
    be traversed during ray marching.
    
    The cutout ray marching is currently slower than I expected on integrated
    graphics (maybe spilling some variables to memory?). I think I need to try
    refactoring it into separate steps for distance to closest point on edge
    (for antialiasing/masking) and ray marching (only when necessary).

    Indirect illumination outside the pumpkins is computed (during the first 12 
    frames) using the classical radiosity approach, but I am extending it 
    slightly by storing irradiance for three different directions (three surface 
    normals) for the pumpkin shapes so the ridges on the pumpkins can be lit 
    convincingly. This directional data is only used during final rendering (not 
    during the radiosity passes). The radiosity passes also modify the irradiance 
    of source patches using a function of incident angle, to compensate for the 
    fact that the BRDFs of the surfaces are not Lambertian (it's not physically 
    accurate, but I think it's better than just assuming Lambertian reflection).

    The meshes used for the radiosity steps are mostly 16x16. Data for higher 
    resolution meshes is also computed for some surfaces, to be used in final 
    rendering. Direct light uses similar meshes, but more high resolution data is 
    computed because it is necessary to capture shadow edges. For some shadow 
    data, fractional occlusion data for four quadrants of the area light is 
    computed (but this is not used during radiosity passes). The meshes are 
    warped in various ways to optimize utilization of the points (e.g. putting 
    more points closer to the floor where there is a steep irradiance gradient).

    The pumpkins and stalks also use radiosity, and so they need meshes. uv 
    spheres and uv cylinders are mapped to the surfaces. Data for this mapping 
    (e.g. displacements and normal vectors, in the case of the pumpkins) is 
    precomputed. The latitude-longitude mapping works well due to the nature of 
    the surface functions that I'm using.

    Inside the pumpkins, the lighting is a bit more ad-hoc. I was trying to use 
    physically-based lighting where possible (the candles are point lights 
    though). The interior of the pumpkins is a very good diffuser of light, so 
    there isn't really any need for radiosity. I used spectral path tracing 
    offline to figure out the lighting, and I found some cheap approximating 
    functions for the shadows and ambient occlusion around the tea lights.

    The edges of the cutouts really need ambient occlusion to look good, and this 
    *is* computed by the shader using a combination of sampling 32 different 
    directions (to find "horizons") and approximating the unoccluded area as a 
    polygon whose light can be integrated analytically using a standard approach 
    from radiosity. I'm using the same AO data for ambient light from both 
    directions (outside and inside the pumpkin).

    The most difficult thing (which I did last) was computing the shadowing for 
    the direct light (from the big area light) shining on the cutout edges. This 
    is only visible in a few places (less than a quarter of the total length of 
    the cutout edges, I think). I initially tried to fake it, but I couldn't find 
    anything that looked good. Sampling the light at each point required too many 
    samples, and expensive ray marching. I finally figured out how to do it 
    analytically. This is cheap enough to do in real time, but still somewhat 
    expensive, so I found a way to precompute it during the first frame. It 
    requires taking a lot of samples to get information about the fraction of 
    light that is occluded, as a function of depth. This function is approximated 
    as Hermite splines, which can be encoded compactly. An advantage of the 
    Hermite spline representation is that it can be integrated cheaply, to help 
    anti-alias the shadow edges, although in the end I found that I could integrate
    over piecewise linear segments and it looked fine.

    BRDFs are fairly standard (using the typical "GGX" D and G functions for 
    specular) but I'm using exponents 3 or 4 instead of 5 in the F function (not 
    treating it as an actual Fresnel function approximation, but it should still 
    be physically plausible by construction), and using functions for the 
    diffuse part that improve energy conservation and reciprocity (a bit similar 
    to the Disney BRDF diffuse function, but not the same, and they are different 
    for each BRDF). There's no perfect solution for using non-Lambertian BRDFs
    with (non-directional) radiosity data, but I'm trying to do better than 
    just assuming Lambertian reflectance; the scaling functions were found by 
    Monte Carlo simulation and approximated with polynomials.

    The candles are probably my favorite thing. I didn't expect the animation to 
    work so well. If you let it run for a long time, they end up flickering too 
    much though (I assume it's a sin/cos precision issue but I haven't
    investigated yet).

    (I put some additional information at the beginning of the individual 
    shaders.)

*/

// Parameter for the very boring, conservative tone mapping curve.
// Change to a higher number to essentially make it linear (i.e. use only the hue-preserving part of the tone mapping).
// Values below 1 don't really work.
const float TONE_MAP_BETA = 5.0;

const vec3 DEFAULT_DIFFUSE_COLOR = vec3(0.95);
const vec3 LEFT_WALL_DIFFUSE_COLOR = vec3(0.90, 0.02, 0.03);
const vec3 RIGHT_WALL_DIFFUSE_COLOR = vec3(0.10, 0.75, 0.15);
const vec3 PUMPKIN_DIFFUSE_COLOR = vec3(1, 0.22, 0);
const vec3 STALK_DIFFUSE_COLOR = vec3(0.6, 0.7, 0.45);

const float PUMPKIN_FRESNEL_BASE = 0.1;

// Controls brightness of the area light
// (I don't know if it's worth making this a radiometric quantity)
const float LIGHT_SCALE = 1.;

// Controls how bright the light is inside the pumpkins (illumination is also modulated by flame size)
const float CANDLELIGHT_SCALE = 0.0012;


// These affect illumination from the area light only (not the candles)
#define SHOW_DIRECT_LIGHT 1
#define SHOW_INDIRECT_LIGHT 1

// Set to 1 to use 256 samples instead of 64 samples of area light for stalk shadows (looks less blotchy)
//  (may increase delay in first frame on slower hardware)
#define BETTER_STALK_SHADOWS 0

// Relative size of the inner (carved out) shape for the pumpkin, which is a copy of the outer shape
//  with ripples removed. The direct illumination at the outside of the cutout edges assumes this specific value.
const float INNER_SHAPE_SCALE = 0.85;


// Zoom value is log of a factor that is multiplied by minimum of view width and height
//      to get distance to view plane (in device units).
// Factor has a simple relationship to field of view angle.
const float ZOOM_DEFAULT = 0.7;
const float ZOOM_MIN = -1.;
const float ZOOM_MAX = 3.;
    
// Width of the drag/tap bands for the UI
const float VIEW_UI_DIVISION = 0.2;

// Scaling factors for mouse drag. Negate these to flip direction.
const float VIEW_MOVE_MOUSE_SCALE = 0.5;
const float VIEW_ROTATE_MOUSE_SCALE = 4.;
const float VIEW_ZOOM_MOUSE_SCALE = 2.;

// Amount by which the view parameters are changed when you tap on a touch screen
// (multiplied by the "MOUSE_SCALE" factors)
const float VIEW_TAP_INCREMENT = 0.05;
        
// Number of directions that are sampled when computing ambient occlusion for cutout edges in Buffer D
const int AO_DIR_SAMPLE_COUNT = 32;

// Range of theta (latitude) values in the data for the pumpkins
const float UVSPHERE_MIN_THETA = 0.1;
const float UVSPHERE_MAX_THETA = 1.;


const float PI = 3.141592653589793;

// For avoiding 0/0 in places where +/- inf is acceptable
float REMOVE_ZEROS(float x) {
    return x != 0. ? x : 1e-20;
}

// Parameters for stalk shapes that are the same for all three
const float STALK_BIAS = -0.055;
const float STALK_FREQ1 = 5.;
const float STALK_FLARE_FACTOR = 8.;
const float STALK_FLARE_POW = 3.; // code now assumes this is 3

// Parameters for stalk shapes
const float STALK1_SCALE = 1./14.;
const vec3 STALK1_OFFSET = vec3(0.3, 0.31 - 0.005, 0.3 - 0.011);

const float STALK2_SCALE = 1./14.;
const vec3 STALK2_OFFSET = vec3(0.312 - 0.005, 0.832 + 0.001, 0.665 - 0.001);

const float STALK3_SCALE = 1./14.;
const vec3 STALK3_OFFSET = vec3(0.75 + 0.007, 0.553 + 0.007, 0.53);

const float STALK1_WARP = 0.35;
const float STALK1_MODSCALE = 0.14;
const float STALK1_BOUND_RADIUS = 0.75;
const float STALK1_BOUND_Y = -0.12;

const float STALK2_WARP = -0.31;
const float STALK2_MODSCALE = 0.111;
const float STALK2_BOUND_RADIUS = 0.9;
const float STALK2_BOUND_Y = -0.33;

const float STALK3_WARP = -1.14;
const float STALK3_MODSCALE = 0.096;
const float STALK3_BOUND_RADIUS = 0.75;
const float STALK3_BOUND_Y = 0.;

// Rotation matrices for the stalk shapes
const mat3 STALK1_RMTX = mat3(
  0.9736663950053749, 0.0, 0.2279775235351884,
  -0.011394127238675235, 0.9987502603949663, 0.04866303756914478,
  -0.22769261099496899, -0.04997916927067833, 0.9724495655494463
);

const mat3 STALK2_RMTX = mat3(
  0.9901664858254151, 0.00990199492695218, 0.1395431146442365,
  -0.023880245176565416, 0.9948151071471336, 0.0988566461202502,
  -0.13784072053807264, -0.10121686167978075, 0.9852690407565038
);

const mat3 STALK3_RMTX = mat3(
  0.9536173992649822, 0.2949884298511123, -0.059964006479444595,
  -0.3004527717592511, 0.9449780666692685, -0.12940087115701668,
  0.018492911108714614, 0.1414152741679161, 0.9897776176852751
);



// Parameters for pumpkin shapes that are the same for all three
const float RIPPLES_MODSCALE = 0.015;
const float RIPPLES_POW = 0.1;

const float PUMPKIN1_SCALE = 1./3.;
const vec3 PUMPKIN1_OFFSET = vec3(0.3, 0.14, 0.3);

const float PUMPKIN2_SCALE = 1./3.7;
const vec3 PUMPKIN2_OFFSET = vec3(0.3, 0.675, 0.67);

const float PUMPKIN3_SCALE = 1./4.5;
const vec3 PUMPKIN3_OFFSET = vec3(0.75, 0.412, 0.53);



// Parameters for the pumpkin shapes

// For bounding spheres:
const float BOUND_RADIUS_PK1 = 0.568;
const float BOUND_RADIUS_INNER_PK1 = 0.3754297;

const float BOUND_RADIUS_PK2 = 0.59;
const float BOUND_RADIUS_INNER_PK2 = 0.4411477;

const float BOUND_RADIUS_PK3 = 0.644;
const float BOUND_RADIUS_INNER_PK3 = 0.47124857;

// Rotation matrices
const mat3 RMTX_PK1 = mat3(
    0.55538403, 0., 0.831594,
    0.05677509, 0.9976667, -0.03791752,
    0.82965364, -0.06827261, -0.55408816
    );
const mat3 RMTX_PK2 = mat3(
    0.95146957, 0., 0.30774283,
    0.02288368, 0.99723148, -0.07075105,
    0.30689084, -0.07435977, -0.94883541
    );
const mat3 RMTX_PK3 = mat3(
    -0.84831922, 0., -0.52948512,
    -0.02237612, 0.99910664, 0.03585009,
    0.5290121, 0.04226015, -0.84756137
    );

    
const float IMPLICIT_FUNCTION_BIAS_PK1 = -0.280;
const vec3 SPHERE_SCALE_PK1 = vec3(1.0, 0.66, 1.0);

const vec3 WARP_MOD_SCALE_PK1 = vec3(0.0062, 0.0157, 0.0321);
const vec3 WARP_SCALE_PK1 = vec3(2.72, 6.19, 4.63);
const vec3 WARP_SHIFT_PK1 = vec3(-0.289, -1.630, -2.013);

const vec2 INDENT_SCALES_PK1 = vec2(0.226, 8.518);

const float RIPPLES_OFFSET_PK1 = 0.;
const vec3 RIPPLES_FREQ_PK1 = vec3(20.000, 37.000, 47.000);
const vec3 RIPPLE_SCALE_PK1 = vec3(0.300, 0.600, 0.100);
const vec3 RIPPLE_SHIFT_PK1 = vec3(1.700, 0.940, 1.170);


const float IMPLICIT_FUNCTION_BIAS_PK2 = -0.280;
const vec3 SPHERE_SCALE_PK2 = vec3(1.0, 0.51, 0.87);

const vec3 WARP_MOD_SCALE_PK2 = vec3(0.0062, 0.0066, 0.0069);
const vec3 WARP_SCALE_PK2 = vec3(2.15, 7.47, 8.92);
const vec3 WARP_SHIFT_PK2 = vec3(-0.746, -1.173, -1.955);

const vec2 INDENT_SCALES_PK2 = vec2(0.193, 6.985);

const float RIPPLES_OFFSET_PK2 = 0.2287;
const vec3 RIPPLES_FREQ_PK2 = vec3(23.879, 30.217, 30.148);
const vec3 RIPPLE_SCALE_PK2 = vec3(0.703, 0.374, 0.288);
const vec3 RIPPLE_SHIFT_PK2 = vec3(-1.009, -1.683, 0.069);


// Pumpkin 3 shape:

const float IMPLICIT_FUNCTION_BIAS_PK3 = -0.280;
const vec3 SPHERE_SCALE_PK3 = vec3(0.73, 0.42, 0.82);

const vec3 WARP_MOD_SCALE_PK3 = vec3(0.0069, 0.0080, 0.0160);
const vec3 WARP_SCALE_PK3 = vec3(2.86, 7.90, 6.20);
const vec3 WARP_SHIFT_PK3 = vec3(-2.861, -0.430, -0.927);

const vec2 INDENT_SCALES_PK3 = vec2(0.178, 4.896);

const float RIPPLES_MODSCALE_PK3 = 0.01;
const float RIPPLES_POW_PK3 = 0.1;
const float RIPPLES_OFFSET_PK3 = 0.2287;
const vec3 RIPPLES_FREQ_PK3 = vec3(7.122, 28.246, 46.905);
const vec3 RIPPLE_SCALE_PK3 = vec3(0.388, 0.445, 0.174);
const vec3 RIPPLE_SHIFT_PK3 = vec3(-2.495, -0.540, 1.154);


// Parameters for the texture map used for ray marching the cutout shapes
// (written by BufferA, read by BufferD and Image)

const float CUTOUT_SCALE_PK1 = 10.514784;
const vec2 CUTOUT_OFFSET_PK1 = vec2(7.883424, 8.16508);
const vec2 CUTOUT_TEX_DIM_PK1 = vec2(20., 16.);
const ivec2 CUTOUT_TEX_OFFSET_PK1 = ivec2(0, 0);

const float CUTOUT_SCALE_PK2 = 12.196235;
const vec2 CUTOUT_OFFSET_PK2 = vec2(16.621096, 8.05079);
const vec2 CUTOUT_TEX_DIM_PK2 = vec2(30., 17.);
const ivec2 CUTOUT_TEX_OFFSET_PK2 = ivec2(0, 16);

const float CUTOUT_SCALE_PK3 = 15.955861;
const vec2 CUTOUT_OFFSET_PK3 = vec2(15.542389, 13.19815);
const vec2 CUTOUT_TEX_DIM_PK3 = vec2(28., 27.);
const ivec2 CUTOUT_TEX_OFFSET_PK3 = ivec2(0, 16 + 17);


// Dimensions of the various meshes used for radiosity and cached direct light
const int MESH_DIM_SHIFT = 4;
const int MESH_DIM = 1 << MESH_DIM_SHIFT;

const int HIGH_RES_DIM_FLOOR_SHIFT = 7;
const int HIGH_RES_DIM_FLOOR = 1 << HIGH_RES_DIM_FLOOR_SHIFT;

const int HIGH_RES_DIM_WALL_SHIFT = 6;
const int HIGH_RES_DIM_WALL = 1 << HIGH_RES_DIM_WALL_SHIFT;

const int HIGH_RES_DIM_BACK_WALL_SHIFT = 6;
const int HIGH_RES_DIM_BACK_WALL = 1 << HIGH_RES_DIM_BACK_WALL_SHIFT;

const int HIGH_RES_DIM_BLOCK_TOP_SHIFT = 6;
const int HIGH_RES_DIM_BLOCK_TOP = 1 << HIGH_RES_DIM_BLOCK_TOP_SHIFT;

const int SPHERE_UV_DIM_SHIFT = 6;
const int SPHERE_UV_DIM = 1 << SPHERE_UV_DIM_SHIFT;

// width of the mesh used for caching of direct light for top of pumpkins (shadows cast by stalks)
const int TOP_SHADOW_MAP_DIM = 24;

// y offset of the high res meshes in Buffer B
const int HIGH_RES_Y_OFFSET = 2*MESH_DIM;

// Parameter used for non-linear warping of the radiosity and cached direct light meshes in various places
const float SQUISH_LOW_SHIFT = 0.05;


// Indices used to identify different surfaces or different meshes stored in Buffer B and Buffer C
const int INDEX_FLOOR = 0;
const int INDEX_LEFT_WALL = 1;
const int INDEX_RIGHT_WALL = 2;
const int INDEX_BACK_WALL = 3;
const int INDEX_LBLOCK_TOP = 4;
const int INDEX_RBLOCK_TOP = 5;
const int INDEX_LBLOCK_LEFT = 6;
const int INDEX_RBLOCK_LEFT = 7;
const int INDEX_LBLOCK_FRONT = 8;
const int INDEX_RBLOCK_FRONT = 9;
const int INDEX_LBLOCK_RIGHT = 10;
const int INDEX_RBLOCK_RIGHT = 11;
const int INDEX_LBLOCK_BACK = 12;
const int INDEX_RBLOCK_BACK = 13;
const int INDEX_CEILING = 14;
const int INDEX_PUMPKIN1 = 15;
const int INDEX_PUMPKIN2 = 16;
const int INDEX_PUMPKIN3 = 17;

const int INDEX_FLOOR00 = 18;
const int INDEX_FLOOR01 = 19;
const int INDEX_FLOOR10 = 20;
const int INDEX_FLOOR11 = 21;

const int SURFACE_COUNT = 22;

const int INDEX_PUMPKIN1_UV = 22;
const int INDEX_PUMPKIN2_UV = 23;
const int INDEX_PUMPKIN3_UV = 24;
const int INDEX_PUMPKIN1_UV_LEFT = 25;
const int INDEX_PUMPKIN2_UV_LEFT = 26;
const int INDEX_PUMPKIN3_UV_LEFT = 27;
const int INDEX_PUMPKIN1_UV_RIGHT = 28;
const int INDEX_PUMPKIN2_UV_RIGHT = 29;
const int INDEX_PUMPKIN3_UV_RIGHT = 30;

const int INDEX_STALK1 = 31;
const int INDEX_STALK2 = 32;
const int INDEX_STALK3 = 33;



#define SURF_MASK(N) (1<<(N))

// Bits used in bitmasks for sets of surfaces (in Buffer C shader)
const int M_FLOOR = SURF_MASK(INDEX_FLOOR);
const int M_LEFT_WALL = SURF_MASK(INDEX_LEFT_WALL);
const int M_RIGHT_WALL = SURF_MASK(INDEX_RIGHT_WALL);
const int M_BACK_WALL = SURF_MASK(INDEX_BACK_WALL);
const int M_CEILING = SURF_MASK(INDEX_CEILING);
const int M_LBLOCK_TOP = SURF_MASK(INDEX_LBLOCK_TOP);
const int M_RBLOCK_TOP = SURF_MASK(INDEX_RBLOCK_TOP);
const int M_LBLOCK_LEFT = SURF_MASK(INDEX_LBLOCK_LEFT);
const int M_RBLOCK_LEFT = SURF_MASK(INDEX_RBLOCK_LEFT);
const int M_LBLOCK_FRONT = SURF_MASK(INDEX_LBLOCK_FRONT);
const int M_RBLOCK_FRONT = SURF_MASK(INDEX_RBLOCK_FRONT);
const int M_LBLOCK_RIGHT = SURF_MASK(INDEX_LBLOCK_RIGHT);
const int M_RBLOCK_RIGHT = SURF_MASK(INDEX_RBLOCK_RIGHT);
const int M_LBLOCK_BACK = SURF_MASK(INDEX_LBLOCK_BACK);
const int M_RBLOCK_BACK = SURF_MASK(INDEX_RBLOCK_BACK);
const int M_PUMPKIN1 = SURF_MASK(INDEX_PUMPKIN1);
const int M_PUMPKIN2 = SURF_MASK(INDEX_PUMPKIN2);
const int M_PUMPKIN3 = SURF_MASK(INDEX_PUMPKIN3);

const int M_FLOOR00 = SURF_MASK(INDEX_FLOOR00);
const int M_FLOOR01 = SURF_MASK(INDEX_FLOOR01);
const int M_FLOOR10 = SURF_MASK(INDEX_FLOOR10);
const int M_FLOOR11 = SURF_MASK(INDEX_FLOOR11);

const int SURFACE_ALL_BITS = (1<<SURFACE_COUNT) - 1;
const int M_LEFT_BLOCK = M_LBLOCK_TOP | M_LBLOCK_LEFT | M_LBLOCK_FRONT | M_LBLOCK_RIGHT | M_LBLOCK_BACK;
const int M_RIGHT_BLOCK = M_RBLOCK_TOP | M_RBLOCK_LEFT | M_RBLOCK_FRONT | M_RBLOCK_RIGHT | M_RBLOCK_BACK;
const int M_PUMPKIN = M_PUMPKIN1 | M_PUMPKIN2 | M_PUMPKIN3;
const int M_FLOOR_HIGHRES = M_FLOOR00 | M_FLOOR01 | M_FLOOR10 | M_FLOOR11;

const int M_WALLS_CEILING_AND_FLOOR = M_FLOOR | M_LEFT_WALL | M_RIGHT_WALL | M_BACK_WALL | M_CEILING;


// Starting coordinate in BufferA where 4 vec4 values of state are stored
// (rotation angles, x and y shifts), (zoom level,0,0,0), (start rotation and shift values for drag), (start zoom value for drag)
const ivec2 VIEW_STATE_COORD = ivec2(8*3, 2*SPHERE_UV_DIM);


void swap(inout vec2 a, inout vec2 b) { vec2 tmp = a; a = b; b = tmp; }

// Used to map a fragment coordinate in Buffer B or Buffer C to one of the low resolution meshes (does not handle all meshes)
int map_icoord_to_surface_index(ivec2 icoord) {
    if (icoord.y < 2*MESH_DIM && icoord.x < MESH_DIM*INDEX_FLOOR10) {
        int index = icoord.x >> MESH_DIM_SHIFT;
        
        if (icoord.y >= MESH_DIM) {
            index = index < INDEX_FLOOR00 ? -1 : index + 2;
        }
        
        return index;
    } else {
        return -1;
    }
}

// When computing shadows or radiosity, warp points under the boxes so they are just outside the boxes
// (helps fix light leakage, etc.)
void warp_point(inout vec3 P, float ANGLE, vec2 corner1, vec2 corner2) {
    mat2 M = mat2(cos(ANGLE), -sin(ANGLE), sin(ANGLE), cos(ANGLE));
        
    vec2 q = M * P.xz;
    
    const float MARGIN = 0.001;
    
    if (q.x >= corner1.x - MARGIN && q.x <= corner2.x + MARGIN && q.y >= corner1.y - MARGIN && q.y <= corner2.y + MARGIN) {
        float diag = (q.x - corner1.x)*(corner1.y-corner2.y) / (corner1.x - corner2.x);
        
        bool below_asc_diag = q.y < corner1.y + diag;
        bool below_desc_diag = q.y < corner2.y - diag;
        
        if (below_asc_diag) {
            if (below_desc_diag) {
                q.y = corner1.y - MARGIN;
            } else {
                q.x = corner2.x + MARGIN;
            }
        } else {
            if (below_desc_diag) {
                q.x = corner1.x - MARGIN;
            } else {
                q.y = corner2.y + MARGIN;
            }
        }
        
        P.xz = q * M;
    }
}

// Map a [0,1] x [0,1] coordinate in one of the meshes to a 3D point, and also return the surface normal
void map_coord_to_P_and_N(int surface_index, vec2 coord, out vec3 P, out vec3 N) {
    if (surface_index <= INDEX_BACK_WALL || surface_index == INDEX_CEILING) {
        switch (surface_index) {
        case INDEX_FLOOR:
            P = vec3(coord.x, 0., coord.y);
            N = vec3(0, 1, 0);
            break;
        case INDEX_LEFT_WALL:
            P = vec3(0., coord.y, coord.x);
            N = vec3(1, 0, 0);
            break;
        case INDEX_RIGHT_WALL:
            P = vec3(1., coord.y, coord.x);
            N = vec3(-1, 0, 0);
            break;
        case INDEX_BACK_WALL:
            P = vec3(coord.x, coord.y, 1);
            N = vec3(0, 0, -1);
            break;
        default:
            P = vec3(coord.x, 1., coord.y);
            N = vec3(0, -1, 0);
            break;
        }
    } else if (surface_index >= INDEX_FLOOR00 && surface_index <= INDEX_FLOOR11) {
        N = vec3(0, 1, 0);
        P = vec3(0.5*coord.x, 0., 0.5*coord.y);
        
        if (surface_index == INDEX_FLOOR01 || surface_index == INDEX_FLOOR11) P.x += 0.5;
        if (surface_index == INDEX_FLOOR10 || surface_index == INDEX_FLOOR11) P.z += 0.5;
    } else if (surface_index >= INDEX_PUMPKIN1 && surface_index <= INDEX_PUMPKIN3) {
        vec3 C;
        float S;
        float y_min = 0.;
        
        if (surface_index == INDEX_PUMPKIN1) {
            C = PUMPKIN1_OFFSET;
            S = 0.48 * PUMPKIN1_SCALE;
            y_min = 0.;
        } else if (surface_index == INDEX_PUMPKIN2) {
            C = PUMPKIN2_OFFSET;
            S = 0.48 * PUMPKIN2_SCALE;
            y_min = 0.55;
        } else {
            C = PUMPKIN3_OFFSET;
            S = 0.48 * PUMPKIN3_SCALE;
            y_min = 0.3;
        }
        
        //C += vec3(0., 0.01, 0.);
        
        float theta = PI*(coord.y - 0.5);
        float y = sin(theta);
        
        y_min = 1./S * (y_min - C.y) + 0.001;
        
        if (y < y_min) {
            y = y_min;
            theta = asin(y);
        }
        
        float cos_theta = cos(theta);
        
        // Does coord.x need to be changed here? (Probably not.)
        float phi = 2.*PI * (coord.x - 0.5);

        float x = cos(phi)*cos_theta;
        float z = sin(phi)*cos_theta;

        N = vec3(x, y, z);
            
        P = C + S*N;
    } else {
        mat2 M;
        vec3 corner1;
        vec3 corner2;
        
        if ((surface_index & 1) == 0) {
            M = mat2(cos(0.2), -sin(0.2), sin(0.2), cos(0.2));
            corner1 = vec3(0.25, 0., 0.45);
            corner2 = vec3(0.6, 0.55, 0.75);
        } else {
            M = mat2(cos(0.11), sin(0.11), -sin(0.11), cos(0.11));
            corner1 = vec3(0.55, 0., 0.45);
            corner2 = vec3(0.85, 0.3, 0.75);
        }
        
        vec3 mix_x = mix(corner1, corner2, coord.x);
        vec3 mix_y = mix(corner1, corner2, coord.y);
        
        switch (surface_index & ~1) {
        case INDEX_LBLOCK_TOP:
            P = vec3(mix_x.x, corner2.y, mix_y.z);
            N = vec3(0, 1, 0);
            break;
        case INDEX_LBLOCK_LEFT:
            P = vec3(corner1.x, mix_y.y, mix_x.z);
            N = vec3(-1, 0, 0);
            break;
        case INDEX_LBLOCK_FRONT:
            P = vec3(mix_x.x, mix_y.y, corner1.z);
            N = vec3(0, 0, -1);
            break;
        case INDEX_LBLOCK_RIGHT:
            P = vec3(corner2.x, mix_y.y, mix_x.z);
            N = vec3(1, 0, 0);
            break;
        default:
            P = vec3(mix_x.x, mix_y.y, corner2.z);
            N = vec3(0, 0, 1);
            break;
        }

        P.xz = P.xz * M;
        N.xz = N.xz * M;
    }
    
    if (surface_index == INDEX_FLOOR || (surface_index >= INDEX_FLOOR00 && surface_index <= INDEX_FLOOR11)) {
        // Warp points under the boxes so they are just outside the boxes (helps fix light leakage, etc.)
        warp_point(P, 0.2, vec2(0.25, 0.45), vec2(0.6, 0.75));
        warp_point(P, -0.11, vec2(0.55, 0.45), vec2(0.85, 0.75));
    }
}

/*
    For computing form factor between differential area and polygon
    This is applied to pairs of adjacent vertices on the polygon and summed (similar to the "shoelace formula" for computing 2D polygon area)
    
    I derived this formula from information and formulas I found in Glassner's Principles of Digital Image Synthesis (page 920).
    
    Later I read Stephen Hill & Eric Heitz's slide show "Real-Time Area Lighting: a Journey from Research to Production".
    They use a different version of the formula (and a different geometrical interpretation perhaps) and say that it had originally
        been derived by Lambert (!)
    The use of atan instead of acos here seems to solve the precision issue (avoids having to implement a specialized approximation as they did).
*/
float get_diff_poly_sum(vec3 A, vec3 B, vec3 N) {
    vec3 crossAB = cross(A, B);
    
    float len = length(crossAB);
    
    return 1./len * dot(crossAB, N) * atan(len, dot(A,B));
}

// Cross product of two vectors with same y value
// z values are in A.y and B.y
vec3 cross_sameY(vec2 A, vec2 B, float y) {
    return vec3(y*(B.y - A.y), A.y*B.x - B.y*A.x, y*(A.x - B.x));
}

// For computing form factor between differential area and polygon
// Special case for when y is same and points are stored as vec2
float get_diff_poly_sum_same_y(vec2 A, vec2 B, float y, vec3 N) {
    vec3 crossAB = cross_sameY(A, B, y);
    
    float len = length(crossAB);
    
    return 1./len * dot(crossAB, N) * atan(len, dot(A,B) + y*y);
}

float eval_area_light_clipped(vec3 dest_P, vec3 dest_N) {
    float y = 1. - dest_P.y;
    
    vec2 P1 = vec2(0.4, 0.4) - dest_P.xz;
    vec2 P2 = vec2(0.6, 0.4) - dest_P.xz;
    vec2 P3 = vec2(0.6, 0.6) - dest_P.xz;
    vec2 P4 = vec2(0.4, 0.6) - dest_P.xz;
    
    vec2 Nxz = dest_N.xz;
    
    vec4 dots = vec4(dot(P1, Nxz), dot(P2, Nxz), dot(P3, Nxz), dot(P4, Nxz)) + y * dest_N.y;

    bool P1inside = dots.x > 0.;
    bool P2inside = dots.y > 0.;
    bool P3inside = dots.z > 0.;
    bool P4inside = dots.w > 0.;

    float c = float(P1inside) + float(P2inside) + float(P3inside) + float(P4inside);
    
    if (c == 0.) return 0.;

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

    if (c >= 4.) {
        d += get_diff_poly_sum_same_y(V_3, V_2, y, dest_N);

        if (c == 5.) {
            d += get_diff_poly_sum_same_y(V_4, V_3, y, dest_N);
            V_2 = V_4;
        } else {
            V_2 = V_3;
        }
    }
    
    d += get_diff_poly_sum_same_y(V_0, V_2, y, dest_N);
    
    return d * -0.5 / PI * (1./0.2 * 1./0.2);
}

// Used for warping meshes so points are closer together on one side
float map_squish_low(float x, float shift) {
    x += shift;
    
    return (sqrt(x)-sqrt(shift)) / (sqrt(1. + shift) - sqrt(shift));
}

// Used for warping meshes so points are closer together on one side
float inv_map_squish_low(float y, float shift) {
    float k = y * (sqrt(1. + shift) - sqrt(shift)) + sqrt(shift);
    
    return k*k - shift;
}

// Used for warping meshes so points are closer together on two sides
float map_squish_both_sides(float x) {
    x *= 2.;
    
    return 0.5*(x < 1. ? sqrt(x) : 2. - sqrt(2. - x));
}

// Used for warping meshes so points are closer together on two sides
float inv_map_squish_both_sides(float y) {
    if (y < 0.5) {
        return 2.*y*y;
    } else {
        float k = 2. - 2.*y;
        
        return 1. - 0.5*k*k;
    }
}

// Used for squishing the latitude values for the pumpkin meshes so points are closer together at the bottom
float pumpkin_map_01_to_squished(float t) {
    return mix(UVSPHERE_MIN_THETA, UVSPHERE_MAX_THETA, inv_map_squish_low(t, SQUISH_LOW_SHIFT));
}

// Used for squishing the latitude values for the pumpkin meshes so points are closer together at the bottom
float pumpkin_map_squished_to_01(float t) {
    return map_squish_low((t - UVSPHERE_MIN_THETA) / (UVSPHERE_MAX_THETA - UVSPHERE_MIN_THETA), SQUISH_LOW_SHIFT);
}

// Used when we have a mesh coordinates and we want to get the corresponding linear 2D coordinates (without "squishing")
vec2 map_coords_to_linear(int surface_index, vec2 coord) {
    if (surface_index == INDEX_LEFT_WALL || surface_index == INDEX_RIGHT_WALL) {
        coord.x = 1. - inv_map_squish_low(1. - coord.x, SQUISH_LOW_SHIFT);
        coord.y = inv_map_squish_both_sides(coord.y);
    } else if (surface_index == INDEX_BACK_WALL) {
        coord.x = inv_map_squish_both_sides(coord.x);
        coord.y = inv_map_squish_both_sides(coord.y);
    } else if (surface_index == INDEX_CEILING) {
        coord.x = inv_map_squish_both_sides(coord.x);
        coord.y = 1. - inv_map_squish_low(1. - coord.y, SQUISH_LOW_SHIFT);
    } else if (surface_index >= INDEX_LBLOCK_LEFT && surface_index <= INDEX_RBLOCK_BACK) {
        coord.x = inv_map_squish_both_sides(coord.x);
        coord.y = inv_map_squish_low(coord.y, SQUISH_LOW_SHIFT);
    }
    
    return coord;
}

// Used when we have linear 2D coordinates and we want to get the corresponding "squished" mesh coordinates
vec2 map_coords_from_linear(int surface_index, vec2 coord) {
    if (surface_index == INDEX_LEFT_WALL || surface_index == INDEX_RIGHT_WALL) {
        coord.x = 1. - map_squish_low(1. - coord.x, SQUISH_LOW_SHIFT);
        coord.y = map_squish_both_sides(coord.y);
    } else if (surface_index == INDEX_BACK_WALL) {
        coord.x = map_squish_both_sides(coord.x);
        coord.y = map_squish_both_sides(coord.y);
    } else if (surface_index == INDEX_CEILING) {
        coord.x = map_squish_both_sides(coord.x);
        coord.y = 1. - map_squish_low(1. - coord.y, SQUISH_LOW_SHIFT);
    } else if (surface_index >= INDEX_LBLOCK_LEFT && surface_index <= INDEX_RBLOCK_BACK) {
        coord.x = map_squish_both_sides(coord.x);
        coord.y = map_squish_low(coord.y, SQUISH_LOW_SHIFT);
    }

    return coord;
}

// Version of map_coords_to_linear for integer input coordinates (for low-resolution meshes only)
vec2 map_coords_to_linear_lowres(int surface_index, vec2 coord) {
    return map_coords_to_linear(surface_index, coord + 0.5/float(MESH_DIM));
}

// implementation of "sign" for vec2 that never returns 0s
vec2 sign_safe(vec2 v) {
    v.x = v.x < 0. ? -1. : 1.;
    v.y = v.y < 0. ? -1. : 1.;
    
    return v;
}

// For octahedral encoding of normalized 3D vector as vec2
vec2 octahedral_encode(vec3 V) {
    V.xy *= 1. / dot(abs(V), vec3(1));
    
    return 0.5 * (V.z >= 0. ? V.xy : (1. - abs(V.yx)) * sign_safe(V.xy)) + 0.5;
}

// For decoding a normalized 3D vector that was encoded as vec2
vec3 octahedral_decode(vec2 enc) {
    vec3 V;
    
    V.xy = 2. * enc - 1.;
    
    V.z = 1. - dot(abs(V.xy), vec2(1));
    
    if (V.z < 0.) V.xy = sign_safe(V.xy) * (1. - abs(V.yx));

    return normalize(V);
}

float GGX_lambda_D(float a2, float z) {
    return sqrt(z*z + a2 * (1. - z*z));
}

// Evaluate product of Trowbridge-Reitz microfacet distribution and the usual masking-shadowing function
float GGX(float alpha, float wm_z, float wi_z, float wo_z) {
    if (wo_z <= 0. || wi_z <= 0.) return 0.;

    float a2 = alpha*alpha;

    float tmp1 = (1. - wm_z*wm_z) + a2*wm_z*wm_z;
    
    float tmp2 = tmp1*tmp1 * (wi_z*GGX_lambda_D(a2, wo_z) + wo_z*GGX_lambda_D(a2, wi_z));

    return tmp2 < 1e-16 ? 0. : 0.5/PI * a2 / tmp2;
}

// Evaluate specular part of the BRDF, which is just GGX with a custom curve used instead of the Fresnel function
vec3 evaluate_specular(float wm_z, float wi_z, float wo_z, float dot_wi_wm, float alpha, vec3 metallic_color, int fresnel_exp) {
    float g = GGX(alpha, wm_z, wi_z, wo_z);

    float f1 = max(0., 1. - max(0., dot_wi_wm));
    
    float f2 = f1*f1;
    
    float fresnel = fresnel_exp == 4 ? f2*f2 : f1*f2;
    vec3 spec;
    
    if (metallic_color.x == 0.) { // Special case: curves for wall BRDFs are expressed differently (I intended to fix this later)
        spec = vec3(0.0333 + (0.456 - 0.0333) * fresnel);
    } else {
        spec = fresnel + metallic_color*(1. - fresnel);
    }
    
    return spec * g;
}

// Evaluate a curve applied to diffuse reflectance that helps ensure that the BRDF doesn't amplify energy for particular angles
// (approximating a curve found by Monte Carlo simulation)
float evaluate_diffuse_curve(float w_z, vec3 coeff) {
    float t = 1. - max(0., w_z);
    
    return 1. - (coeff.x + (coeff.y + coeff.z*t)*t*t);
}

vec3 BRDF_eval(vec3 V, vec3 L, vec3 N, vec3 diffuse_color, vec3 metallic_color, float alpha, int fresnel_exponent, vec3 curve) {
    vec3 wm = normalize(L + V);
        
    float wm_z = max(0., dot(wm, N));
    float wi_z = max(0., dot(L, N));
    float wo_z = max(0., dot(V, N));
    
    float dot_wi_wm = max(0., dot(L, wm));
    
    vec3 spec = evaluate_specular(wm_z, wi_z, wo_z, dot_wi_wm, alpha, metallic_color, fresnel_exponent);
    
    float diffuse_amount;

    // Scale the diffuse light to remove light that was specularly reflected
    // Since the BRDF needs to be bidirectional, we need to make it the same if wi_z and wo_z are swapped.
    // Obviously there are many ways to accomplish this, but a simple method that seems physically plausible is to apply the same function to both
    //      wi_z and wo_z, and then multiply. (The Disney BRDF does the same thing, but the third angle is used on both functions.)
    // Instead of using a generic Schlick-like function (as in the Disney BRDF) I'm using a different polynomial for each BRDF
    if (metallic_color.x == 0.) { // Special case: curves for wall BRDFs are expressed differently (I intended to fix this later)
        diffuse_amount = 1. - 0.25*wi_z*wi_z;
        diffuse_amount *= 1. - 0.25*wo_z*wo_z;
    } else {
        diffuse_amount = evaluate_diffuse_curve(wi_z, curve) * evaluate_diffuse_curve(wo_z, curve);
    }
    
    return PI*spec + diffuse_amount * diffuse_color;
}

// This is used only for the tealights. Aluminum has a pretty flat Frenel function, so I'm ignoring it. No diffuse term needed.
vec3 BRDF_eval_metal(vec3 V, vec3 L, vec3 N, vec3 spec_color, float alpha) {
    return PI * GGX(alpha, dot(normalize(L + V), N), dot(L, N), dot(V, N)) * spec_color;
}

// Some axis-aligned bounding boxes for the shapes, used for quickly excluding shapes based on the ray extent.
// The stalk bounding box is also used for refining the possible intersection interval (not sure if it really helps or just increases compile time)

const vec3 PK1_BOUND_LOW = vec3(0.134, -0.0075, 0.115);
//const vec3 PK1_BOUND_HIGH = vec3(0.481, 0.295, 0.47); // unused
const vec3 PK2_BOUND_LOW = vec3(0.155, 0.549, 0.515);
//const vec3 PK2_BOUND_HIGH = vec3(0.445, 0.81, 0.825); // unused
const vec3 PK3_BOUND_LOW = vec3(0.615, 0.299, 0.4);
//const vec3 PK3_BOUND_HIGH = vec3(0.88, 0.54, 0.665); // unused

const vec3 STALK1_BOUND_LOW = vec3(0.263, 0.27, 0.257);
const vec3 STALK1_BOUND_HIGH = vec3(0.33, 0.351, 0.324);

const vec3 STALK2_BOUND_LOW = vec3(0.276, 0.794, 0.632);
const vec3 STALK2_BOUND_HIGH = vec3(0.343, 0.874, 0.701);

const vec3 STALK3_BOUND_LOW = vec3(0.721, 0.518, 0.497);
const vec3 STALK3_BOUND_HIGH = vec3(0.804, 0.598, 0.561);

// These are for AABB that covers both pumpkin and stalk
const vec3 PKSTALK1_BOUND_HIGH = vec3(0.481, 0.351, 0.47);
const vec3 PKSTALK2_BOUND_HIGH = vec3(0.445, 0.874, 0.825);
const vec3 PKSTALK3_BOUND_HIGH = vec3(0.88, 0.598, 0.665);

const vec3 BOX1_BOUND_LOW = vec3(0.096, -0.001, 0.490);
const vec3 BOX1_BOUND_HIGH = vec3(0.499, 0.551, 0.855);        

const vec3 BOX2_BOUND_LOW = vec3(0.596, -0.001, 0.353);
const vec3 BOX2_BOUND_HIGH = vec3(0.928, 0.301, 0.686);

bool bound_overlap(vec3 low1, vec3 high1, vec3 low2, vec3 high2) {
    return all(greaterThan(high1, low2)) && all(lessThan(low1, high2));
}

// Convenience macro for choosing between three constants, based on two boolean values
#define CHOOSE3(B1, B2, V1, V2, V3) ((B1) ? (V1) : (B2) ? (V2) : (V3))

// Evaluate the function for the pumpkin implicit surface (surface is where this function is 0) and return both the value and the partial derivatives.
// This function turns out to be pretty close to an SDF (but I didn't plan it to be).
vec4 pumpkin_val_and_deriv_fn(vec3 P, bool rippled, int pk_index) {
    bool pk1 = pk_index==0;
    bool pk2 = pk_index==1;
    
    float value = CHOOSE3(pk1, pk2, IMPLICIT_FUNCTION_BIAS_PK1, IMPLICIT_FUNCTION_BIAS_PK2, IMPLICIT_FUNCTION_BIAS_PK3);
    
    vec3 deriv;
    
    {
        vec3 scaled_P = CHOOSE3(pk1, pk2, SPHERE_SCALE_PK1, SPHERE_SCALE_PK2, SPHERE_SCALE_PK3) * P;
        
        value += dot(P, scaled_P);
        deriv = 2.*scaled_P;
    }
    
    {
        vec3 scale, shift, mscale;
        
        if (pk1) {
            scale = WARP_SCALE_PK1;
            shift = WARP_SHIFT_PK1;
            mscale = WARP_MOD_SCALE_PK1;
        } else if (pk2) {
            scale = WARP_SCALE_PK2;
            shift = WARP_SHIFT_PK2;
            mscale = WARP_MOD_SCALE_PK2;
        } else {
            scale = WARP_SCALE_PK3;
            shift = WARP_SHIFT_PK3;
            mscale = WARP_MOD_SCALE_PK3;
        }
        
        vec3 warp = scale*P + shift;
        
        vec3 s = sin(warp);
        vec3 c = cos(warp);
        
        value += dot(mscale, s.xyz*c.yzx);
        deriv += scale * (mscale * c * c.yzx - mscale.zxy * s * s.zxy);
    }
    
    float k = dot(P.xz, P.xz);
    
    {
        vec2 scales = CHOOSE3(pk1, pk2, INDENT_SCALES_PK1, INDENT_SCALES_PK2, INDENT_SCALES_PK3);
        
        float m = scales.x * exp(-scales.y*k);
        
        value += m;
        deriv += -2.*scales.y * m * vec3(P.x, 0., P.z);
    }
    
    {
        vec3 freq, shift, scale;
        float offset;
        
        if (pk1) {
            freq = RIPPLES_FREQ_PK1;
            shift = RIPPLE_SHIFT_PK1;
            scale = RIPPLE_SCALE_PK1;
            offset = RIPPLES_OFFSET_PK1;
        } else if (pk2) {
            freq = RIPPLES_FREQ_PK2;
            shift = RIPPLE_SHIFT_PK2;
            scale = RIPPLE_SCALE_PK2;
            offset = RIPPLES_OFFSET_PK2;
        } else {
            freq = RIPPLES_FREQ_PK3;
            shift = RIPPLE_SHIFT_PK3;
            scale = RIPPLE_SCALE_PK3;
            offset = RIPPLES_OFFSET_PK3;
        }
        
        vec3 phi = freq * atan(P.z, P.x) + shift;
        vec3 sin_phi = sin(phi);
        
        float r = (rippled ? dot(scale, sin_phi) : 0.) + (1.001 + offset);
        float pow_r1 = RIPPLES_MODSCALE * pow(r, RIPPLES_POW - 1.);
        float d_ripples = (rippled ? RIPPLES_POW * pow_r1 / k * dot(freq*scale, cos(phi)) : 0.);
        
        value += -r * pow_r1;
        deriv += d_ripples*vec3(P.z, 0., -P.x);
    }
    
    return vec4(deriv, value);
}

float pumpkin_val_fn(vec3 P, bool rippled, int pk_index) {
    return pumpkin_val_and_deriv_fn(P, rippled, pk_index).w;
}

// Evaluate the function for the stalk implicit surface (surface is where this function is 0) and return both the value and the partial derivatives.
// This function is not as close to an SDF as the pumpkin function.
vec4 stalk_val_and_deriv_fn(vec3 P, int pk_index) {
    bool pk1 = pk_index==0, pk2 = pk_index==1;

    float warp = CHOOSE3(pk1, pk2, STALK1_WARP, STALK2_WARP, STALK3_WARP)*P.y;
    
    vec3 P2 = P + vec3(warp*P.y, 0, 0);
    
    float a = 1. + P2.y;
    
    float ms = CHOOSE3(pk1, pk2, STALK1_MODSCALE, STALK2_MODSCALE, STALK3_MODSCALE);
    
    //float a_pow = pow(a, STALK_FLARE_POW-1.);
    float a_pow = a*a; // assume STALK_FLARE_POW is 3
    
    float r = exp(-STALK_FLARE_FACTOR*a*a_pow);
    float phi = STALK_FREQ1 * atan(P2.z, P2.x);
    
    float m = sin(phi) + 1.001;

    float q = 1. / sqrt(m);
    
    float scaled_cos_phi = STALK_FREQ1 * ms * 0.5 / dot(P2.xz, P2.xz) * q * cos(phi);
    
    float dist = sqrt(dot(P2, vec3(1., 0., 1.)*P2));
    
    vec3 Df = 1./dist*vec3(1., 0., 1.)*P2 + vec3(
            P2.z * scaled_cos_phi,
            STALK_FLARE_POW*STALK_FLARE_FACTOR*a_pow * r,
            -P2.x * scaled_cos_phi
        );
    
    return vec4(Df.x, 2.*warp*P2.y*Df.x + Df.y, Df.z, dist - ms * m * q - r + STALK_BIAS);
}

// Returns distance from origin to pumpkin surface along a vector, both without ripples (simplified shape) and with ripples
// C0 and C1 contain coefficients for initial guess approximation
vec2 distance_to_pumpkin_shape(vec3 V, vec4 C0, float C1, int pk_index) {
    float t;
    
    {
        float y2 = V.y * V.y;
        
        t = C0.x + (C0.y + (C0.z + C0.w*y2)*y2)*y2;
        
        t += C1*V.x*V.z*t;
    }

    vec4 dval = pumpkin_val_and_deriv_fn(t*V, false, pk_index);
    
    float d = dot(V, dval.xyz);
    
    if (abs(d) > 1e-10) {
        t -= dval.w / d;
        
        dval = pumpkin_val_and_deriv_fn(t*V, false, pk_index);
    
        d = dot(V, dval.xyz);
        
        if (abs(d) > 1e-10) {
            t -= dval.w / d;
        }
    }
    
    float t_simplified = t;
    
    dval = pumpkin_val_and_deriv_fn(t*V, true, pk_index);

    d = dot(V, dval.xyz);
    
    if (abs(d) > 1e-10) {
        t -= dval.w / d;
        
        dval = pumpkin_val_and_deriv_fn(t*V, true, pk_index);

        d = dot(V, dval.xyz);
        
        if (abs(d) > 1e-10) {
            t -= dval.w / d;
        }
    }
    
    return vec2(t_simplified, t);
}

// Returns distance from origin to pumpkin shape along a vector, both without ripples (simplified shape) and with ripples
vec2 distance_to_pumpkin_shape(vec3 V, int pk_index) {
    mat3 mtx;
    vec4 C0;
    float C1;
    
    if (pk_index==0) {
        C0 = vec4(0.51591536, 0.0366811, 0.13520878, -0.2999165);
        C1 = 0.067574354;
        mtx = RMTX_PK1;
    } else if (pk_index==1) {
        C0 = vec4(0.53951799, 0.044976011, 0.11025531, -0.23711691);
        C1 = -0.049742672;
        mtx = RMTX_PK2;
    } else {
        C0 = vec4(0.58844957, 0.075244936, 0.090307939, -0.26195241);
        C1 = -0.037918395;
        mtx = RMTX_PK3;
    }
        
    return distance_to_pumpkin_shape(mtx * V, C0, C1, pk_index);
}

// Returns twice the triangle area. Used for point in polygon tests, etc.
float tri_area(vec2 p1, vec2 p2, vec2 p3) {
    return (p1.x - p3.x)*(p2.y - p1.y) - (p1.x - p2.x)*(p3.y - p1.y);
}

// Data for the cutout shapes, as integers with two points packed into each integer (8 bits per coordinate).
// Implemented using a switch statement instead of an array because arrays are sometimes problematic.
// This is data is only used in the first frame (for a relatively small section of two buffers) so performance shouldn't matter too much anyway.
ivec4 get_cutout_data4(int index) {
    ivec4 v0, v1, v2, v3;

    switch(index >> 2) {
    case 0:
        v0 = ivec4(-1321205970, -1262762496, -5918074, -1418665119); v1 = ivec4(1864281173, 1530564139, 2102232900, 1952487762);
        v2 = ivec4(1886488426, 1518702711, 1519742346, 1471313821); v3 = ivec4(16737982, 649411262, 277890209, 175194233);
        break;
    case 1:
        v0 = ivec4(995709536, 625169487, 606685236, 588661793); v1 = ivec4(35840, -13382842, -1167858856, -814294423);
        v2 = ivec4(-1418939271, -1281707944, -693514849, -642205523); v3 = ivec4(-1010307629, -1381717322, -1802988169, -2037083239);
        break;
    case 2:
        v0 = ivec4(2022671247, 2004968839, -2038659966, -1816491610); v1 = ivec4(-1529046070, -1678070290, -1848797467, 2040696507);
        v2 = ivec4(2043509179, 2030008549, 1726046454, 1891593168); v3 = ivec4(-1272265965, -1789418176, -1873574290, -1591502788);
        break;
    case 3:
        v0 = ivec4(2080418314, 2084011036, 2070903626, 1849455178); v1 = ivec4(1627940898, 1331185729, 1331643228, 393236591);
        v2 = ivec4(1518817659, 480137620, 1420645280, 1404324528); v3 = ivec4(801329352, 749739960, 60102321, 59520655);
        break;
    case 4:
        v0 = ivec4(947913601, 257425525, 374220893, -115086080); v1 = ivec4(-43778235, -257885820, -673847627, -1057498625);
        v2 = ivec4(-710293564, -412884852, -803414210, -1872325547); v3 = ivec4(-2139123598, 1738698898, 1488805553, 1490245322);
        break;
    case 5:
        v0 = ivec4(1809932510, 1993242074, 1791521222, 1691708880); v1 = ivec4(1623482572, 1874486973, 2143779262, 2128773588);
        v2 = ivec4(1693545198, 1356880106, 1270696913, 1553290405); v3 = ivec4(-2123993476, 1231250276, 1582254424, 1917937740);
        break;
    case 6:
        v0 = ivec4(-1841396139, -1271358172, -916798902, -914109331); v1 = ivec4(-1246969702, -1462457669, -1728992014, -1715956015);
        v2 = ivec4(-1818059859, -1987277161, -1718512505, -1482514790); v3 = ivec4(-1265717352, -1366968190, -1686790016, -1520591770);
        break;
    default:
        v0 = ivec4(-1420970918, 1045143365, 1131556445, 1167143809); v1 = ivec4(1152136608, 1120874942, 149756669, 348137169);
        v2 = ivec4(413084333, 394210192, 274278766, 2826569); v3 = ivec4(3606, 0, 0, 0);
        break;
    }

    index &= 3;

    return index < 2 ? (index == 0 ? v0 : v1) : (index == 2 ? v2 : v3);
}

// Return one integer from the "array" of packed points (containing data for two polygon vertices, with 8 bit coordinates)
int get_cutout_data(int index) {
    ivec4 d = get_cutout_data4(index >> 2);
    
    index &= 3;
    
    return index < 2 ? (index == 0 ? d.x : d.y) : (index == 2 ? d.z : d.w);
}

// Data about the packed and unpacked polygons

// Each shape has multiple loops (eyes, nose, mouth, whiskers)
// The number of vertices in each loop is encoded here (last loop contains any remaining vertices)
const int CUTOUT_LOOP_COUNTS1 = 0x20030303;
const int CUTOUT_LOOP_COUNTS2 = 0x09999a99;
const int CUTOUT_LOOP_COUNTS3 = 0x16222b10;

// Shifts for decoding the above counts (i.e. number of bits in each count)
const int CUTOUT_LOOP_COUNT_SHIFT1 = 8;
const int CUTOUT_LOOP_COUNT_SHIFT2 = 4;
const int CUTOUT_LOOP_COUNT_SHIFT3 = 8;

const int CUTOUT_MAX_LOOPS_PER_PUMPKIN = 9;

// scales for unpacking 8-bit coordinates
const vec2 CUTOUT_DECODE_SCALE1 = vec2(0.0754901961, 0.0621698417);
const vec2 CUTOUT_DECODE_SCALE2 = vec2(0.1164215686, 0.0637950299);
const vec2 CUTOUT_DECODE_SCALE3 = vec2(0.109558831, 0.1020972832);

// Offsets for unpacking 8-bit coordinates (I could probably have avoided this)
const vec2 CUTOUT_DECODE_OFFSET1 = vec2(0.75, 0.);
const vec2 CUTOUT_DECODE_OFFSET2 = vec2(0.312501, 0.6875);
const vec2 CUTOUT_DECODE_OFFSET3 = vec2(0., 0.8125);

// Number of vertices for each pumpkin
const int CUTOUT_POINT_COUNT1 = 41;
const int CUTOUT_POINT_COUNT2 = 92;
const int CUTOUT_POINT_COUNT3 = 115;


// Offsets of cutout data for each pumpkin (125 integers total)
const int CUTOUT_DATA_OFFSET_PACKED1 = 0;
const int CUTOUT_DATA_OFFSET_PACKED2 = 21;
const int CUTOUT_DATA_OFFSET_PACKED3 = 67;


// For encoding edges in the grid cells
// This number of bits is chosen so it can be stored in float16 buffers (e.g. for compatibility with Mali GPUs)
const int CUTOUT_SUBGRID_LOG2 = 12;
const float CUTOUT_SUBGRID_SIZE = float(1 << CUTOUT_SUBGRID_LOG2);

// Unpack a point on the edge of a grid cell, which has already been unpacked into a pair of integers
vec2 cutout_unpack_point(ivec2 data) {
    int e = data.x;
    
    vec2 p = vec2(float(((e + 1) >> 1) & 1), 1./CUTOUT_SUBGRID_SIZE * float(data.y));
    
    if (e >= 2) p.y = 1. - p.y;
    if ((e & 1) != 0) p = p.yx;
    
    return p;
}

// Unpack a point on the edge of a grid cell (packed into a single integer)
vec2 cutout_unpack_point(int data) {
    return cutout_unpack_point(ivec2(data & 3, data >> 2));
}

// Encode 14 bits so they can safely be encoded as a floating point value
// This encoding is safe for both 32-bit and 16-bit floats (16-bit buffers are used by Shadertoy on some mobile devices, e.g. for Mali GPUs)
int encode_14bits(int b) {
    b <<= 13;
    b += b <= 0x007fe000 ? 0x40000000 : 0x38000000;
    return b;
}

// Decode the above encoding
int decode_14bits(int b) {
    return (b >> 13) & 0x3fff;
}

// Some ray-geometry intersection functions...


vec2 intersect_sphere_both(vec3 C, float r, vec3 V, vec3 ray_O) {
    ray_O -= C;

    float a = dot(V, ray_O);

    float d = a*a - dot(ray_O, ray_O) + r*r;

    return d >= 0. ? vec2(-sqrt(d) - a, sqrt(d) - a) : vec2(1e20, -1e20);
}

vec2 cone_intersection(vec3 ray_O, vec3 V, vec3 D, float A, float B) {
    float od = dot(ray_O, D);
    float vd = dot(V, D);

    vec3 P = ray_O - od*D;
    vec3 W = V - vd*D;

    float a = -A*A * vd*vd + dot(W,W);
    float b = 2. * (-A*A*od*vd - A*B*vd + dot(P,W));
    float c = dot(P,P) - (A*od + B)*(A*od + B);
    
    float disc = b*b - 4.*a*c;
    
    if (disc < 0.) {
        return vec2(1e20);
    } else {
        disc = sqrt(disc);
        
        vec2 t = 0.5/a * (-b + disc*vec2(-1., 1.));
        
        if (t.y < t.x) t = t.yx;
        
        bool trim_x = A*(od + t.x*vd) < -B;
        bool trim_y = A*(od + t.y*vd) < -B;
        
        if (trim_x) {
            if (trim_y) {
                t = vec2(1e20);
            } else {
                t.x = t.y;
                t.y = 1e20;
            }
        } else if (trim_y) {
            t.y = t.x;
            t.x = -1e20;
        }
        
        return t;
    }
}


vec2 slab_nearfar_raw(float c1, float c2, float rV) {
    return vec2(REMOVE_ZEROS(c1) * rV, REMOVE_ZEROS(c2) * rV);
}

vec2 vec2_sort(vec2 v) {
    return vec2(min(v.x, v.y), max(v.x, v.y));
}

vec2 slab_nearfar(float c1, float c2, float rV) {
    return vec2_sort(slab_nearfar_raw(c1, c2, rV));
}

float intersect_box_near(vec3 P1, vec3 P2, vec3 rV, vec3 ray_O, out int side) {
    P1 -= ray_O;
    P2 -= ray_O;
    
    vec2 tx = slab_nearfar(P1.x, P2.x, rV.x);
    vec2 ty = slab_nearfar(P1.y, P2.y, rV.y);
    vec2 tz = slab_nearfar(P1.z, P2.z, rV.z);
        
    float near = max(tx.r, max(ty.r, tz.r));
    
    if (near == tz.r) {
        side = 4;
    } else if (near == ty.r) {
        side = 2;
    } else {
        side = 1;
    }
    
    return near <= min(tx.g, min(ty.g, tz.g)) ? near : 1e20;
}



