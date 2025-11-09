//  _   _            ____   ____ __     __            ____    ____                _  _   _
// | | | |    /\    |  _ \ |  _ \\ \   / /  /\ /\    / __ \  / __ \    /\ /\    | || \ | |
// | |_| |   /  \   | | | || | | |\ \ / /  /  V  \  | |  | || |  | |  /  V  \   | ||  \| |
// |  _  |  / /\ \  | |_| || |_| | \ V /  / /\ /\ \ | |  | || |  | | / /\ /\ \  | || \ \ |
// | | | | / ____ \ |  __/ |  __/   | |  / /  V  \ \| |__| || |__| |/ /  V  \ \ | || |\  |
// |_| |_|/_/    \_\|_|    |_|      |_| /_/       \_\\____/  \____//_/       \_\|_||_| \_|
//

//
// Quickstart:
//
// - Toggle theme with F2
// - Toggle navigation mode with N
// - Move with W,A,S,D
//

//
// Inputs:
//
// - Mouse drag - Swivel
// - Ctrl + Mouse drag - Zoom
// - Shift + Mouse drag - Pan
// - Mouse click - Set pivot
// - Mouse double click - Set pivot and center view (Inspect) / Teleport (Walk)
//
// - F1 - Toggle render mode (Compose, Steps, Normal, Depth, Shadow, Outline, Edge, UV)
// - F2 - Toggle theme (Day, Night, Plain)
// - N - Toggle navigation mode (Inspect, Walk)
// - W,A,S,D - Move horizontally
// - E,C - Move vertically
// - +,- - Change render resolution
// - R - Reset view
//

// MIT License
// - Empty scene template:
//   https://www.shadertoy.com/view/mlsSRN

// Image - Scale and text
// Inputs: Buffer C, Font

// Notes:
// - Keyframe (pose) definition is at Buffer A
// - Keyframes can be mixed to create animation (see setPose usage at Buffer A's mainImage function)
// - Reference image:
//   https://i.pinimg.com/originals/b0/17/5a/b0175ab6fe33c7a24b75a657a26da6b5.png

#define fontTexture(coord) texture(iChannel1, (coord) / vec2(1024.0))

const int[] text = int[](
    87, 97, 108, 107, -1, // 0 - Walk
    73, 110, 115, 112, 101, 99, 116, -1, // 1 - Inspect
    80, 108, 97, 105, 110, -1, // 2 - Plain
    68, 97, 121, -1, // 3 - Day
    78, 105, 103, 104, 116, -1, // 4 - Night
    67, 111, 109, 112, 111, 115, 101, -1, // 5 - Compose
    83, 116, 101, 112, 115, -1, // 6 - Steps
    78, 111, 114, 109, 97, 108, -1, // 7 - Normal
    68, 101, 112, 116, 104, -1, // 8 - Depth
    83, 104, 97, 100, 111, 119, -1, // 9 - Shadow
    79, 117, 116, 108, 105, 110, 101, -1, // 10 - Outline
    69, 100, 103, 101, -1, // 11 - Edge
    85, 86, -1); // 12 - UV

float characterTexture(vec2 pos, int index)
{
    vec2 index2 = vec2(float(index % 16), float(15 - index / 16));
    return pos.x < 0.0 || pos.x > 64.0 || pos.y < 0.0 || pos.y > 64.0  ? 0.0 :
        fontTexture(pos + 64.0 * index2).r;
}

vec2 numberTexture(vec2 pos, float value, int digits) // (mask, width)
{
    vec2 pos1 = pos;
    float result = 0.0;

    if (value < 0.0)
    {
        result += characterTexture(pos1, 45);
        pos1.x -= 32.0;
        value = abs(value);
    }

    int magnitude = int(max(floor(log(value) / 2.302585), 0.0)) + 1;

    value /= pow(10.0, float(magnitude - 1));

    while (magnitude > -digits)
    {
        int digit = int(floor(value));
        result += characterTexture(pos1, digit + 48);
        value = fract(value) * 10.0;

        pos1.x -= 32.0;
        magnitude--;

        if (magnitude == 0 && digits > 0)
        {
            result += characterTexture(pos1, 46);
            pos1.x -= 32.0;
        }
    }

    return vec2(pos.x - pos1.x, min(result, 1.0));
}

float stringTexture(vec2 pos, int index)
{
    float result = 0.0;

    int i = 0;
    while (i < text.length() && index > 0)
    {
        if (text[i] == -1)
        {
            index--;
        }

        i++;
    }

    while (i < text.length() && text[i] != -1)
    {
        result += characterTexture(pos, text[i]);
        pos.x -= 32.0;
        i++;
    }

    return result;
}

float getTargetMask(vec2 pos)
{
    const float thickness = 2.0;
    const float opening = 5.0;
    const float size = 15.0;

    pos.xy = abs(pos.xy);
    pos = vec2(max(pos.x, pos.y), min(pos.x, pos.y));

    return ((pos.x > opening && pos.x < size && pos.x > thickness && pos.y < thickness)) ? 1.0 : 0.0;
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
    deserializeState(iChannel0, iResolution.xy);

    vec2 skipState = fragCoord.x < STATE_SIZE + 2.0 && fragCoord.y < 3.0 ? vec2y(3.0) : vec2(0.0);
    vec2 uv = (fragCoord.xy + skipState) / iResolution.xy;

    float renderScale = state.renderScale;

    #ifndef SMOOTH_SCALE
        uv = round(uv * renderScale * iResolution.xy) / (renderScale * iResolution.xy);
    #endif

    uv *= renderScale;
    uv += (1.0 - renderScale) / 2.0;

    vec3 color = texture(iChannel0, uv).rgb;

    float annotation = 0.0;

    vec2 p = fragCoord.xy;

    vec2 p2 = p;
    if (iTime < state.targetAnnotation.z + 0.05 && state.targetAnnotation.w > 0.0)
    {
        annotation += getTargetMask(p2 - state.targetAnnotation.xy);
    }

    #ifdef DISPLAY_DEBUG_VALUE
        p2 = p;
        p2 /= TEXT_SCALE;
        vec4 displayValue = state.debug;
        p2.y -= 3.0 * 60.0; // 3 lines up
        annotation += numberTexture(p2, displayValue.x, 2).y; p2.y += 60.0;
        annotation += numberTexture(p2, displayValue.y, 2).y; p2.y += 60.0;
        annotation += numberTexture(p2, displayValue.z, 2).y; p2.y += 60.0;
        annotation += numberTexture(p2, displayValue.w, 2).y; p2.y += 60.0;
    #endif

    if (state.modeAnnotation.x > 0.0 && iTime < state.modeAnnotation.y + 1.0)
    {
        p2 = p;
        p2.y -= iResolution.y;
        p2 /= TEXT_SCALE;
        p2.y += 75.0;

        if (state.modeAnnotation.x > 3.0)
        {
            vec2 p3 = p2;
            vec2 t2 = numberTexture(p3, state.nextRenderScale * 100.0, 0);
            annotation += t2.y;
            p3.x -= t2.x;
            annotation += characterTexture(p3, 37); // "%"

            p3 = p2;
            p3.y += 60.0;
            t2 = numberTexture(p3, state.nextRenderScale * iResolution.x, 0);
            annotation += t2.y;
            p3.x -= t2.x;
            annotation += characterTexture(p3, 120); // "x"
            p3.x -= 32.0;
            t2 = numberTexture(p3, state.nextRenderScale * iResolution.y, 0);
            annotation += t2.y;
        }
        else if (state.modeAnnotation.x > 2.0)
        {
            annotation += stringTexture(p2, int(state.navigationMode));
        }
        else if (state.modeAnnotation.x > 1.0)
        {
            annotation += stringTexture(p2, 2 + int(state.nextTheme));
        }
        else
        {
            annotation += stringTexture(p2, 5 + int(state.nextRenderMode));
        }
    }

    vec3 annotationColor = vec3(min(step(color.r, 0.2) + step(color.g, 0.2) + step(color.b, 0.2), 1.0));
    color = mix(color, annotationColor, min(annotation, 1.0));

    fragColor = vec4(color, 1.0);
}
