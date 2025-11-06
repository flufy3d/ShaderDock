#version 320 es

// No vertex buffers required: we infer a fullscreen triangle from gl_VertexID.
out vec2 vUV;

const vec2 kPositions[3] = vec2[](
    vec2(-1.0, -1.0),
    vec2(3.0, -1.0),
    vec2(-1.0, 3.0)
);

void main()
{
    vec2 pos = kPositions[gl_VertexID];
    vUV = pos * 0.5 + 0.5;
    gl_Position = vec4(pos, 0.0, 1.0);
}
