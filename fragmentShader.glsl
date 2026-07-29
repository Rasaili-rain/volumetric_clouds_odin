#version 450

in vec2 fragTexCoord;
out vec4 finalColor;

layout(location = 0) uniform float uTime;
layout(location = 1) uniform vec2 uResolution;

#define MAX_STEPS 100

float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float sdSphere(vec3 p, float radius) {
    return length(p) - radius;
}

float noise(in vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);

    f = f * f * (3.0 - 2.0 * f);

    float n = p.x + p.y * 57.0 + 113.0 * p.z;

    float res = mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
                mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
            mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
    return res;
}

float fbm(vec3 p) {
    vec3 q = p + uTime * 0.5 * vec3(1.0, -0.2, -1.0);
    float g = noise(q);

    float f = 0.0;
    float scale = 0.5;
    float factor = 2.02;

    for (int i = 0; i < 6; i++) {
        f += scale * noise(q);
        q *= factor;
        factor += 0.21;
        scale *= 0.5;
    }

    return f;
}

float scene(vec3 p) {
  float distance = sdSphere(p, 1.0);
  float f = fbm(p);

  return -distance + f;
}

const float MARCH_SIZE = 0.08;

vec4 raymarch(vec3 rayOrigin, vec3 rayDirection) {
    float depth = 0.0;
    vec3 p = rayOrigin + depth * rayDirection;

    vec4 res = vec4(0.0);
    for (int i = 0; i < MAX_STEPS; i++) {
        float density = scene(p);
        if (density > 0.0) {
            vec4 color = vec4(mix(vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0), density), density);
            color.rgb *= color.a;
            res += color * (1.0 - res.a);
        }
        depth += MARCH_SIZE;
        p = rayOrigin + depth * rayDirection;
    }
    return res;
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;
    uv -= 0.5;
    uv.x *= uResolution.x / uResolution.y;

    vec3 ro = vec3(0.0, 0.0, 5.0);
    vec3 rd = normalize(vec3(uv, -1.0));

    vec4 res = raymarch(ro, rd);
    vec3 color = res.rgb;

    finalColor = vec4(color, 1.0);
}
