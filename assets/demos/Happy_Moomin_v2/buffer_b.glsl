// MIT License

// Buffer B - Outline
// Inputs: Buffer A

vec3 getPosition(vec2 coord, vec4 t)
{
    vec2 uv = map01_11(coord / iResolution.xy);
    uv.x *= iResolution.x / iResolution.y;

    float depth = deserializeDepth(getDepthComponent(t));
    vec3 rd = normalize(uv.x * state.viewX + uv.y * state.viewY + FIELD_OF_VIEW * state.viewZ * state.renderScale);

    vec3 pos = state.viewOrigin + depth * rd; // point in scene

    return pos;
}

vec3 getPosition(vec2 coord)
{
    return getPosition(coord, inputTexture(coord));
}

vec3 getNormal(vec2 fragCoord)
{
    vec3 pos = getPosition(fragCoord);
    vec3 nx0 = pos - getPosition(fragCoord - vec2(1.0, 0.0));
    vec3 ny0 = pos - getPosition(fragCoord - vec2(0.0, 1.0));
    vec3 nx1 = pos - getPosition(fragCoord + vec2(1.0, 0.0));
    vec3 ny1 = pos - getPosition(fragCoord + vec2(0.0, 1.0));
    vec3 nx = length(nx0) < length(nx1) ? -nx0 : nx1;
    vec3 ny = length(ny0) < length(ny1) ? -ny0 : ny1;
    return normalize(cross(nx, ny));
}

vec2 getDepthGradient(vec2 coord)
{
    vec2 g = vec2(0.0);

    for (int i = 0; i < 9; i++)
    {
        vec2 offset = vec2(float(i % 3), float(i / 3)) + vec2(-1.0);
        float d = deserializeDepth(getDepthComponent(inputTexture(coord + offset))) / MAX_DIST;
        g.x += d * offset.x * (2.0 - abs(offset.y));
        g.y += d * offset.y * (2.0 - abs(offset.x));
    }

    return g;
}

float getOutline(vec2 coord)
{
    const int innerEdgeCount = 4;

    float f, fx1, fx2, fy1, fy2;

    float material = getMaterialIndexComponent(inputTexture(coord));

    // depth gradient
    f =   length(getDepthGradient(coord));
    fx1 = length(getDepthGradient(coord - vec2x1));
    fx2 = length(getDepthGradient(coord + vec2x1));
    fy1 = length(getDepthGradient(coord - vec2y1));
    fy2 = length(getDepthGradient(coord + vec2y1));

    // perimeter outline based on depth
    float result = f >= 0.1 ? 1.0 : 0.0;

    // inner outline based on depth
    result += 4.0 * f >= 1.05 * (fx1 + fx2 + fy1 + fy2 + 0.000005) ? 1.0 : 0.0;

    // remove outline for the same material
    result = materialHasInnerLines(material) ? result : 0.0;

    vec4 t = inputTexture(coord);
    vec4 tx1 = inputTexture(coord - vec2x1);
    vec4 tx2 = inputTexture(coord + vec2x1);
    vec4 ty1 = inputTexture(coord - vec2y1);
    vec4 ty2 = inputTexture(coord + vec2y1);

    // material difference
    f = material;
    fx1 = getMaterialIndexComponent(tx1);
    fx2 = getMaterialIndexComponent(tx2);
    fy1 = getMaterialIndexComponent(ty1);
    fy2 = getMaterialIndexComponent(ty2);

    // perimeter outline based on material difference
    result += abs(f - fx1) + abs(f - fx2) + abs(f - fy1) + abs(f - fy2) > 0.0 ? 1.0 : 0.0;

    // edge group
    float edge = getEdgeGroupComponent(t);
    f = edge;
    fx1 = getEdgeGroupComponent(tx1);
    fx2 = getEdgeGroupComponent(tx2);
    fy1 = getEdgeGroupComponent(ty1);
    fy2 = getEdgeGroupComponent(ty2);
    result += f > 0.0 && ( // exclude edge group 0
        fx1 > 0.0 && abs(f - fx1) > 0.0 || fx2 > 0.0 && abs(f - fx2) > 0.0 ||
        fy1 > 0.0 && abs(f - fy1) > 0.0 || fy2 > 0.0 && abs(f - fy2) > 0.0) ? 1.0 : 0.0;

    // tint difference
    float tint = getTintIndexComponent(t);
    f = tint;
    fx1 = getTintIndexComponent(tx1);
    fx2 = getTintIndexComponent(tx2);
    fy1 = getTintIndexComponent(ty1);
    fy2 = getTintIndexComponent(ty2);

    // perimeter outline based on tint difference (excluding reflection on next slot)
    result += abs(f - fx1) > 1.0 || abs(f - fx2) > 1.0 || abs(f - fy1) > 1.0 || abs(f - fy2) > 1.0 ? 1.0 : 0.0;

    result = min(result, 1.0);

    return result;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    vec4 t = inputTexture(fragCoord);

    if (fragCoord.x < STATE_SIZE && fragCoord.y < 1.0)
    {
        fragColor = t;
        return;
    }

    deserializeState(iChannel0, iResolution.xy);

    fragColor = setOutlineComponent(t, getOutline(fragCoord));
}
