#version 450

in vec2 fragTexCoord;
out vec4 finalColor;

layout(location = 0) uniform sampler2D uTexture;
layout(location = 1) uniform vec2 uTexelSize; // 1.0 / texture resolution
layout(location = 2) uniform vec2 uFullSize;  // texture resolution

float w0(float a) { return (1.0/6.0)*(a*(a*(-a + 3.0) - 3.0) + 1.0); }
float w1(float a) { return (1.0/6.0)*(a*a*(3.0*a - 6.0) + 4.0); }
float w2(float a) { return (1.0/6.0)*(a*(a*(-3.0*a + 3.0) + 3.0) + 1.0); }
float w3(float a) { return (1.0/6.0)*(a*a*a); }

float g0(float a) { return w0(a) + w1(a); }
float g1(float a) { return w2(a) + w3(a); }
float h0(float a) { return -1.0 + w1(a) / (w0(a) + w1(a)); }
float h1(float a) { return  1.0 + w3(a) / (w2(a) + w3(a)); }

vec4 textureBicubic(sampler2D tex, vec2 uv, vec2 texelSize, vec2 fullSize) {
    uv = uv * fullSize + 0.5;
    vec2 iuv = floor(uv);
    vec2 fuv = fract(uv);

    float g0x = g0(fuv.x);
    float g1x = g1(fuv.x);
    float h0x = h0(fuv.x);
    float h1x = h1(fuv.x);
    float h0y = h0(fuv.y);
    float h1y = h1(fuv.y);

    vec2 p0 = (vec2(iuv.x + h0x, iuv.y + h0y) - 0.5) * texelSize;
    vec2 p1 = (vec2(iuv.x + h1x, iuv.y + h0y) - 0.5) * texelSize;
    vec2 p2 = (vec2(iuv.x + h0x, iuv.y + h1y) - 0.5) * texelSize;
    vec2 p3 = (vec2(iuv.x + h1x, iuv.y + h1y) - 0.5) * texelSize;

    return g0(fuv.y) * (g0x * texture(tex, p0) + g1x * texture(tex, p1)) +
           g1(fuv.y) * (g0x * texture(tex, p2) + g1x * texture(tex, p3));
}

void main() {
    // raylib render textures are Y-flipped vs. normal UVs
    vec2 uv = vec2(fragTexCoord.x, 1.0 - fragTexCoord.y);
    finalColor = textureBicubic(uTexture, uv, uTexelSize, uFullSize);
}