#version 320 es
precision highp float;

in vec2 vUV;
out vec4 fragColor;

uniform float uTime;      // Seconds since start; optional but nice if provided.
uniform vec2 uResolution; // Viewport size; optional fallback handled below.

vec3 palette(float t)
{
    // Simple cosine palette for smooth cycling colors.
    const vec3 a = vec3(0.5, 0.5, 0.5);
    const vec3 b = vec3(0.5, 0.5, 0.5);
    const vec3 c = vec3(1.0, 1.0, 1.0);
    const vec3 d = vec3(0.0, 2.0 / 3.0, 1.0);
    return a + b * cos(6.28318 * (c * t + d));
}

void main()
{
    vec2 resolution = max(uResolution, vec2(1.0));

    vec2 uv = vUV;
    vec2 centered = (uv * resolution - 0.5 * resolution) / resolution.y;

    float time = uTime;
    float dist = length(centered);
    float ripple = sin(dist * 12.0 - time * 4.0);
    float angle = atan(centered.y, centered.x) / 6.28318;

    float hue = fract(angle + ripple * 0.1 + time * 0.05);
    float glow = exp(-dist * 2.5);

    vec3 color = palette(hue) * (0.4 + 0.6 * glow);

    fragColor = vec4(color, 1.0);
}
