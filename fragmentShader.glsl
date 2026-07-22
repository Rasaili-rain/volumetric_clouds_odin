#version 450

in vec2 fragTexCoord;
out vec4 finalColor;

layout(location = 0) uniform float uTime;
layout(location = 1) uniform vec2 uResolution;

#define MAX_STEPS 100

float sdSphere(vec3 p, float radius) {
    return length(p) - radius;
}

float scene(vec3 p) {
    float distance = sdSphere(p, 1.0);
    return -distance;
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
