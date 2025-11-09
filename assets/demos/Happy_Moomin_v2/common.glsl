// MIT License

// Common

// --- Scene parameters ---

const vec3 INITIAL_TARGET = vec3(0.0, 1.2, 0.0);
const vec3 INITIAL_ORIGIN = vec3(0.0, 2.1, 2.3);
const vec3 SUN_DIRECTION = normalize(vec3(1.0));

//#define SMOOTH_SCALE
//#define DISPLAY_DEBUG_VALUE
#define TEXT_SCALE 0.6

#define MAX_STEPS 100
#define MAX_REFLECTION_STEPS 30
#define MAX_DIST 600.0
#define MAX_DIST_LOG 6.4
#define FIELD_OF_VIEW 1.8
#define SURF_DIST 0.0001
#define BOUNDS_MARGIN 0.2
#define BOUNDS_MARGIN_LARGE 0.4

// --- Materials ---
#define MATERIAL_EMPTY 0.0
#define MATERIAL_SKY 1.0
#define MATERIAL_GRASS 2.0
#define MATERIAL_FLOWER1 3.0
#define MATERIAL_FLOWER2 4.0
#define MATERIAL_MOUNTAIN 5.0
#define MATERIAL_ROCK 6.0
#define MATERIAL_SKIN 7.0
#define MATERIAL_EYE 8.0
#define MATERIAL_PUPIL 9.0
#define MATERIAL_MOUTH 10.0

// Materials properties
#define materialHasOutline(m) ((m) >= MATERIAL_ROCK || (m) >= MATERIAL_FLOWER1 && (m) <= MATERIAL_FLOWER2)
#define materialHasInnerLines(m) ((m) >= MATERIAL_MOUNTAIN)
#define materialFadeOutlines(m) ((m) >= MATERIAL_GRASS && maxIndex1 <= MATERIAL_FLOWER2)
#define materialFadeInnerLines(m) ((m) != MATERIAL_MOUNTAIN)
#define materialCastsShadow(m) ((m) >= MATERIAL_ROCK)
#define materialReceivesShadow(m) ((m) > MATERIAL_SKY && (m) < MATERIAL_MOUNTAIN || (m) > MATERIAL_CLOUD)
#define materialHasGroundBounceLight(m) ((m) > MATERIAL_GRASS && (m) < MATERIAL_SKIN)

// --- Interaction ---
#define ZOOM_DRAG_SPEED 4.0
#define ZOOM_SCROLL_SPEED 0.3
#define MOVE_CAMERA_HEIGHT 1.0
#define MOVE_SPEED1 4.0
#define MOVE_SPEED2 8.0
#define MOVE_GRAVITY 4.0
#define MOVE_COLLISION 6.0
#define SWIVEL_SPEED 5.0
#define CLICK_TIME 0.4
#define MIN_CAMERA_HEIGHT 0.2

// --- Constants ---
#define PI025 0.78539816339
#define PI05 1.57079632679
#define PI075 2.35619449019
#define PI 3.14159265359
#define PI2 6.28318530718

#define map11_01(x) (((x) + 1.0) * 0.5)
#define map01_11(x) ((x) * 2.0 - 1.0)

#define vec2x(x) vec2(x, 0.0)
#define vec2y(y) vec2(0.0, y)
#define vec3x(x) vec3(x, 0.0, 0.0)
#define vec3y(y) vec3(0.0, y, 0.0)
#define vec3z(z) vec3(0.0, 0.0, z)

#define vec2x1 vec2(1.0, 0.0)
#define vec2y1 vec2(0.0, 1.0)
#define vec3x1 vec3(1.0, 0.0, 0.0)
#define vec3y1 vec3(0.0, 1.0, 0.0)
#define vec3z1 vec3(0.0, 0.0, 1.0)


#define KEY_SHIFT 16
#define KEY_CONTROL 17
#define KEY_A 65
#define KEY_C 67
#define KEY_D 68
#define KEY_E 69
#define KEY_N 78
#define KEY_R 82
#define KEY_S 83
#define KEY_W 87
#define KEY_KP_PLUS 107
#define KEY_KP_MINUS 109
#define KEY_F1 112
#define KEY_F2 113
#define KEY_EQUALS 61
#define KEY_MINUS 173
#define BUTTON_LEFT 245
#define BUTTON_MIDDLE 246
#define BUTTON_RIGHT 247
#define MOUSE_SCROLL_UP 250
#define MOUSE_SCROLL_DOWN 251

#define inputTexture(coord) texture(iChannel0, (coord) / iResolution.xy)
#define inputTextureState(i) texture(iChannel0, vec2(float(i) + 0.5, 0.5) / iResolution.xy)

// --- Serialization ---

// Buffer definition (broken into [whole].[fraction] parts):
//     x: outline.depth
//     y: material.uv_x
//     z: edge.uv_y
//     w: tint.shadow

#define getOutlineComponent(t) floor(t.x)
#define getDepthComponent(t) fract(t.x)
#define getMaterialIndexComponent(t) floor(t.y)
#define getEdgeGroupComponent(t) floor(t.z)
#define getMaterialUvComponent(t) fract(t.yz)
#define getTintIndexComponent(t) floor(t.w)
#define getShadowComponent(t) fract(t.w)

#define setOutlineComponent(t, g) vec4(fract(t.x) + g, t.yzw)
#define serializeDepth(d) clamp(log((d) + 1.0) / MAX_DIST_LOG, 0.0, 0.9999)
#define deserializeDepth(d) (exp((d) * MAX_DIST_LOG) - 1.0)

struct State
{
    bool initialized; // 0 - state initialized
    vec3 origin; // 1 - camera origin
    vec3 target; // 2 - camera target
    vec3 targetOffset; // 3 - camera target offset (when target is set but not centered)
    vec4 targetAnnotation; // 4 - camera target offset (when target is set but not centered)
    vec3 nextOrigin; // 5 - next frame navigated origin
    vec3 nextTarget; // 6 - next frame navigated target
    vec3 nextTargetOffset; // 7
    vec3 viewX; // 8 - camera x axis (cached)
    vec3 viewY; // 9 - camera y axis (cached)
    vec3 viewZ; // 10 - camera z axis (cached)
    vec3 viewOrigin; // 11 - clipped camera origin (above ground)
    float dragStartTime; // 12
    vec2 dragStartPosition; // 13
    vec2 dragLastPosition; // 14 - non applied drag delta start
    float renderMode; // 15
    float renderScale; // 16
    float nextRenderMode; // 17
    float nextRenderScale; // 18
    float navigationMode; // 19
    bool focused; // 20 - viewport was clicked
    float clickTime; // 21
    float clickCount; // 22
    vec2 modeAnnotation; // 23
    float theme; // 24
    float nextTheme; // 25
    vec4 debug; // 26
} state;

#define STATE_SIZE 27.0

void deserializeState(sampler2D iChannel0, vec2 iResolution)
{
    state.initialized = inputTextureState(0).x > 0.0;
    state.origin = inputTextureState(1).xyz;
    state.target = inputTextureState(2).xyz;
    state.targetOffset = inputTextureState(3).xyz;
    state.targetAnnotation = inputTextureState(4);
    state.nextOrigin = inputTextureState(5).xyz;
    state.nextTarget = inputTextureState(6).xyz;
    state.nextTargetOffset = inputTextureState(7).xyz;
    state.viewX = inputTextureState(8).xyz;
    state.viewY = inputTextureState(9).xyz;
    state.viewZ = inputTextureState(10).xyz;
    state.viewOrigin = inputTextureState(11).xyz;
    state.dragStartTime = inputTextureState(12).x;
    state.dragStartPosition = inputTextureState(13).xy;
    state.dragLastPosition = inputTextureState(14).xy;
    state.renderMode = inputTextureState(15).x;
    state.renderScale = inputTextureState(16).x;
    state.nextRenderMode = inputTextureState(17).x;
    state.nextRenderScale = inputTextureState(18).x;
    state.navigationMode = inputTextureState(19).x;
    state.focused = inputTextureState(20).x > 0.0;
    state.clickTime = inputTextureState(21).x;
    state.clickCount = inputTextureState(22).x;
    state.modeAnnotation = inputTextureState(23).xy;
    state.theme = inputTextureState(24).x;
    state.nextTheme = inputTextureState(25).x;
    state.debug = inputTextureState(26);
}

vec4 serializeState(int index)
{
    if (index == 0) return vec4(state.initialized ? 1.0 : 0.0, 0.0, 0.0, 0.0);
    if (index == 1) return vec4(state.origin, 0.0);
    if (index == 2) return vec4(state.target, 0.0);
    if (index == 3) return vec4(state.targetOffset, 0.0);
    if (index == 4) return vec4(state.targetAnnotation);
    if (index == 5) return vec4(state.nextOrigin, 0.0);
    if (index == 6) return vec4(state.nextTarget, 0.0);
    if (index == 7) return vec4(state.nextTargetOffset, 0.0);
    if (index == 8) return vec4(state.viewX, 0.0);
    if (index == 9) return vec4(state.viewY, 0.0);
    if (index == 10) return vec4(state.viewZ, 0.0);
    if (index == 11) return vec4(state.viewOrigin, 0.0);
    if (index == 12) return vec4(state.dragStartTime, 0.0, 0.0, 0.0);
    if (index == 13) return vec4(state.dragStartPosition, 0.0, 0.0);
    if (index == 14) return vec4(state.dragLastPosition, 0.0, 0.0);
    if (index == 15) return vec4(state.renderMode, 0.0, 0.0, 0.0);
    if (index == 16) return vec4(state.renderScale, 0.0, 0.0, 0.0);
    if (index == 17) return vec4(state.nextRenderMode, 0.0, 0.0, 0.0);
    if (index == 18) return vec4(state.nextRenderScale, 0.0, 0.0, 0.0);
    if (index == 19) return vec4(state.navigationMode, 0.0, 0.0, 0.0);
    if (index == 20) return vec4(state.focused ? 1.0 : 0.0, 0.0, 0.0, 0.0);
    if (index == 21) return vec4(state.clickTime, 0.0, 0.0, 0.0);
    if (index == 22) return vec4(state.clickCount, 0.0, 0.0, 0.0);
    if (index == 23) return vec4(state.modeAnnotation, 0.0, 0.0);
    if (index == 24) return vec4(state.theme, 0.0, 0.0, 0.0);
    if (index == 25) return vec4(state.nextTheme, 0.0, 0.0, 0.0);
    if (index == 26) return vec4(state.debug);

    return vec4(0.0);
}

void resetState()
{
    state.initialized = false;
    state.origin = vec3(0.0);
    state.target = vec3(0.0);
    state.targetOffset = vec3(0.0);
    state.nextOrigin = vec3(0.0);
    state.nextTarget = vec3(0.0);
    state.nextTargetOffset = vec3(0.0);
    state.viewX = vec3(0.0);
    state.viewY = vec3(0.0);
    state.viewZ = vec3(0.0);
    state.viewOrigin = vec3(0.0);
    state.dragStartTime = 0.0;
    state.dragStartPosition = vec2(0.0);
    state.dragLastPosition = vec2(0.0);
    state.renderMode = 0.0;
    state.renderScale = 0.0;
    state.nextRenderMode = 0.0;
    state.nextRenderScale = 0.0;
    state.navigationMode = 0.0;
    state.focused = false;
    state.clickTime = 0.0;
    state.clickCount = 0.0;
    state.modeAnnotation = vec2(0.0);
    state.theme = 0.0;
    state.nextTheme = 0.0;
    state.debug = vec4(0.0);
}

// --- Common functions ---

float smin(float a, float b, float k) // smooth min
{
    k = max(k, 0.001);
    float h = max(k - abs(a - b), 0.0) / k;
    return min(a, b) - h * h * h * k / 6.0;
}

vec3 smin(vec3 a, vec3 b, float k) // x component smooth min
{
    float x = smin(a.x, b.x, k);
    return vec3(x, a.x <= b.x ? a.yz : b.yz);
}

float smax(float a, float b, float k) // smooth max
{
    k = max(k, 0.001);
    float h = max(k - abs(a - b), 0.0) / k;
    return max(a, b) + h * h * h * k / 6.0;
}

vec3 smax(vec3 a, vec3 b, float k) // x component smooth max
{
    float x = smax(a.x, b.x, k);
    return vec3(x, a.x <= b.x ? b.yz : a.yz);
}

vec2 minx(vec2 a, vec2 b) // x component min
{
    return a.x <= b.x ? a : b;
}

vec3 minx(vec3 a, vec3 b) // x component min
{
    return a.x <= b.x ? a : b;
}

vec4 minx(vec4 a, vec4 b) // x component min
{
    return a.x <= b.x ? a : b;
}

vec2 maxx(vec2 a, vec2 b) // x component max
{
    return a.x >= b.x ? a : b;
}

vec3 maxx(vec3 a, vec3 b) // x component max
{
    return a.x >= b.x ? a : b;
}

vec4 maxx(vec4 a, vec4 b) // x component max
{
    return a.x >= b.x ? a : b;
}

// smooth merge based on k, and interpolating a.w, and b.w
vec4 smin(vec4 a, vec4 b, float k)
{
    float x = smin(a.x, b.x, k);

    float d = abs(x - a.x) - abs(x - b.x);
    d = clamp(d * 6.0, -1.0, 1.0);

    float w = a.w * max(0.0, -d) + b.w * max(0.0, d);

    return vec4(x, a.x <= b.x ? a.yz : b.yz, w);
}

// smooth merge based on b.w
vec3 smin(vec3 a, vec4 b)
{
    return smin(a, b.xyz, b.w);
}

// smooth merge based on b.w, while keeping a.w unchanged
vec4 smin(vec4 a, vec4 b)
{
    return vec4(smin(a.xyz, b.xyz, b.w), a.w);
}

mat2 rotation(float angle)
{
    float s = sin(angle);
    float c = cos(angle);
    return mat2(c, s, -s, c);
}

float pow2(float value)
{
    return value * value;
}

float stretchAxis(float p, float w)
{
    p += w * 0.5;
    return p - clamp(p, 0.0, w);
}

float stretchAxis(float p, float a, float b)
{
    return p - clamp(p, a, b) + a;
}

vec2 bendSpace(vec2 pos, vec2 origin, float stretch, float squash, float angle)
{
    angle *= 0.5;
    pos += origin;
    float a = atan(pos.y, pos.x);
    a += angle; // rotate
    a = mod(a + PI, PI2) - PI; // map back to -PI..PI

    float side = step(0.0, angle) * PI; // stretch side 0 or PI

    float f = 1.0 - exp(-abs((side - abs(a)) / stretch)); // exponential ease-in from 0 to stretch
    f -= exp(-abs(PI - side - abs(a)) / squash); // exponential ease-out from PI-squash to PI

    a = sign(a) * clamp(abs(a) + f * angle, 0.0, PI);

    pos = length(pos) * vec2(cos(a), sin(a));
    pos -= origin;

    return pos;
}

vec2 radialMod(vec2 p, float count, out float index)
{
    float angle = atan(p.y, p.x);
    float size = PI2 / count;

    index = angle / size + 0.5;
    angle = (fract(index) - 0.5) * size;

    index = floor(index);
    return vec2(cos(angle), sin(angle)) * length(p.xy);
}


// --- Quaternions ---

const vec4 quaternion0 = vec4(0.0, 0.0, 0.0, 1.0);

#define quaternion(axis, a) vec4(sin(a / 2.0) * axis.xyz, cos(a / 2.0))
#define quaternionx(a) vec4(sin(a / 2.0), 0.0, 0.0, cos(a / 2.0))
#define quaterniony(a) vec4(0.0, sin(a / 2.0), 0.0, cos(a / 2.0))
#define quaternionz(a) vec4(0.0, 0.0, sin(a / 2.0), cos(a / 2.0))

vec4 quaternionInverse(vec4 q)
{
    return vec4(-q.xyz, q.w);
}

vec4 quaternionScale(vec4 q, float scale)
{
    float angle = acos(q.w) * 2.0;
    vec3 axis = q.xyz / sin(angle / 2.0);

    return quaternion(axis, angle * scale);
}

vec4 multiply(vec4 q1, vec4 q2)
{
    return vec4(q1.w * q2.xyz + q2.w * q1.xyz + cross(q1.xyz, q2.xyz), q1.w * q2.w - dot(q1.xyz, q2.xyz));
}

vec4 multiply(vec4 q1, vec4 q2, vec4 q3)
{
    vec4 q12 = vec4(q1.w * q2.xyz + q2.w * q1.xyz + cross(q1.xyz, q2.xyz), q1.w * q2.w - dot(q1.xyz, q2.xyz));
    return vec4(q12.w * q3.xyz + q3.w * q12.xyz + cross(q12.xyz, q3.xyz), q12.w * q3.w - dot(q12.xyz, q3.xyz));
}

vec3 rotate(vec3 pos, vec4 q)
{
    vec3 t = q.w * pos + cross(q.xyz, pos);
    return dot(q.xyz, pos) * q.xyz + q.w * t - cross(t, q.xyz);
}

// --- Noise ---

float hash(float p)
{
    p = fract(p * .1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash(vec2 p)
{
    vec3 p3  = fract(vec3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 pos)
{
    vec2 p = floor(pos);
    vec2 f = fract(pos);

    f = f * f * (3.0 - 2.0 * f);

    float n = p.x + 7.0 * p.y;

    return mix(mix(hash(n), hash(n + 1.0), f.x),
               mix(hash(n + 7.0), hash(n + 8.0), f.x), f.y);
}

float noise(vec3 pos)
{
    vec3 p = floor(pos);
    vec3 f = fract(pos);

    f = f * f * (3.0 - 2.0 * f);

    float a = 37.0;
    float b = 19.0;

    float n = p.x + a * p.y + b * p.z;

    float res = mix(mix(mix(hash(n), hash(n + 1.0), f.x),
                        mix(hash(n + a), hash(n + a + 1.0), f.x), f.y),
                    mix(mix(hash(n + b), hash(n + b + 1.0), f.x),
                        mix(hash(n + a + b), hash(n + a + b + 1.0), f.x), f.y), f.z);
    return res;
}

float fbm(vec2 p)
{
    float f = 0.5 * noise(p);
    p *= 2.1; f += 0.25 * noise(p);
    p *= 2.1; f += 0.25 * noise(p);
    return f;
}

float fbm(vec3 p)
{
    float f = 0.5 * noise(p);
    p *= 2.1; f += 0.25 * noise(p);
    return f;
}

// --- SDF ---

float sdCircle(vec2 pos, float size)
{
    return length(pos) - size;
}

float sdRectangle(vec2 pos, vec2 size)
{
    vec2 d = abs(pos) - size;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdSphere(vec3 pos, float size)
{
    return length(pos) - size;
}

float sdEllipsoid(vec3 pos, vec3 rad)
{
    float k0 = length(pos / rad);
    float k1 = length(pos / rad / rad);
    return k0 * (k0 - 1.0) / k1;
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r)
{
  vec3 pa = p - a;
  vec3 ba = b - a;
  float h = clamp( dot(pa, ba) / dot(ba, ba), 0.0, 1.0);

  return length(pa - ba * h) - r;
}

float sdArc(vec3 pos, float len, float angle, float width, float taper)
{
    angle = map01_11(step(0.0, angle)) * max(abs(angle), 0.01);

    // parameters
    vec2 sc = vec2(sin(angle), cos(angle));
    float ra = 0.5 * len / angle;

    // recenter
    pos.x -= ra;

    // reflect
    vec2 q = pos.xy - 2.0 * sc * max(0.0, dot(sc, pos.xy));

    float u = abs(ra) - length(q);
    float d2 = (q.y < 0.0) ? dot(q + vec2(ra, 0.0), q + vec2(ra, 0.0)) : u * u;
    float s = sign(angle);

    float t = (pos.y > 0.0) ? atan(s * pos.y, -s * pos.x) * ra : (s * pos.x < 0.0) ? pos.y : len - pos.y;
    width = max(0.001, width - t * taper);

    return sqrt(d2 + pos.z * pos.z) - width;
}

float sdBox(vec3 pos, vec3 size)
{
    vec3 d = abs(pos) - size;
    return length(max(d, 0.0)) + min(max(max(d.x, d.y), d.z), 0.0);
}

float sdBoxApprox(vec3 pos, vec3 size)
{
    vec3 d = abs(pos) - size;
    return max(max(d.x, d.y), d.z);
}

float sdBoxApprox(vec3 pos, vec3 size, vec3 origin)
{
    return sdBoxApprox(pos - origin * size, size);
}
