#version 450

in vec2 fragTexCoord;
out vec4 finalColor;

layout(location = 0) uniform float uTime;
layout(location = 1) uniform vec2 uResolution;

#define MAX_STEPS 100
#define PI 3.14159265359

mat2 rotate2D(float a) {
  float s = sin(a);
  float c = cos(a);
  return mat2(c, -s, s, c);
}

float nextStep(float t, float len, float smo) {
  float tt = mod(t += smo, len);
  float stp = floor(t / len) - 1.0;
  return smoothstep(0.0, smo, tt) + stp;
}

float sdCapsule(vec3 p, vec3 a, vec3 b, float r) {
  vec3 ab = b - a;
  vec3 ap = p - a;
  float t = dot(ab, ap) / dot(ab, ab);
  t = clamp(t, 0.0, 1.0);
  vec3 c = a + t * ab;
  float d = length(p - c) - r;
  return d;
}

float sdSphere(vec3 p, float radius) {
    return length(p) - radius;
}

float sdTorus(vec3 p, vec2 r) {
  float x = length(p.xz) - r.x;
  return length(vec2(x, p.y)) - r.y;
}

float sdCross(vec3 p, float s) {
  float da = max(abs(p.x), abs(p.y));
  float db = max(abs(p.y), abs(p.z));
  float dc = max(abs(p.z), abs(p.x));
  return min(da, min(db, dc)) - s;
}

float hash(float n) {
    return fract(sin(n) * 43758.5453);
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
    float scale = 0.25;
    float factor = 2.02;

    for (int i = 0; i < 6; i++) {
        f += scale * noise(q);
        q *= factor;
        factor += 0.21;
        scale *= 0.5;
    }

    return f;
}


// float scene(vec3 p) {
//   float distance = sdSphere(p, 1.0);

//   float f = fbm(p);

//   return -distance + f;
// }

float scene(vec3 p) {
  vec3 p1 = p;
  p1.xz *= rotate2D(-PI * 0.1);
  p1.yz *= rotate2D(PI * 0.3);

  float s1 = sdTorus(p1, vec2(1.3, 0.9));
  float s2 = sdCross(p1 * 2.0, 0.6);
  float s3 = sdSphere(p, 1.5);
  float s4 = sdCapsule(p, vec3(-2.0, -1.5, 0.0), vec3(2.0, 1.5, 0.0), 1.0);
  float t = mod(nextStep(uTime, 3.0, 1.2), 4.0);
  float distance = mix(s1, s2, clamp(t, 0.0, 1.0));
  distance = mix(distance, s3, clamp(t - 1.0, 0.0, 1.0));
  distance = mix(distance, s4, clamp(t - 2.0, 0.0, 1.0));
  distance = mix(distance, s1, clamp(t - 3.0, 0.0, 1.0));
  float f = fbm(p);

  return -distance + f;
}

// Sun direction used for both cloud shading and the sky glow
const vec3 SUN_POSITION = vec3(1.0, 0.0, 0.0);
const float MARCH_SIZE = 0.08;

vec4 raymarch(vec3 rayOrigin, vec3 rayDirection) {
    float depth = 0.0;
    vec3 p = rayOrigin + depth * rayDirection;
    vec3 sunDirection = normalize(SUN_POSITION);

    vec4 res = vec4(0.0);
    for (int i = 0; i < MAX_STEPS; i++) {
        float density = scene(p);
        if (density > 0.0) {
            // Directional derivative for fast diffuse lighting
            float diffuse = clamp((scene(p) - scene(p + 0.3 * sunDirection)) / 0.3, 0.0, 1.0);
            vec3 lin = vec3(0.60, 0.60, 0.75) * 1.1 + 0.8 * vec3(1.0, 0.6, 0.3) * diffuse;

            vec4 color = vec4(mix(vec3(1.0, 1.0, 1.0), vec3(0.0, 0.0, 0.0), density), density);
            color.rgb *= lin;
            color.rgb *= color.a;
            res += color * (1.0 - res.a);
        }
        depth += MARCH_SIZE;
        p = rayOrigin + depth * rayDirection;
    }
    return res;
}

vec3 getNormal(vec3 p) {
  vec2 e = vec2(.01, 0);

  vec3 n = scene(p) - vec3(
    scene(p-e.xyy),
    scene(p-e.yxy),
    scene(p-e.yyx));

  return normalize(n);
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;
    uv -= 0.5;
    uv.x *= uResolution.x / uResolution.y;

    vec3 ro = vec3(0.0, 0.0, 5.0);
    vec3 rd = normalize(vec3(uv, -1.0));

    vec3 sunDirection = normalize(SUN_POSITION);
    float sun = clamp(dot(sunDirection, rd), 0.0, 1.0);

    // Base sky color with vertical gradient + sun glow
    vec3 color = vec3(0.7, 0.7, 0.90);
    color -= 0.8 * vec3(0.90, 0.75, 0.90) * rd.y;
    color += 0.5 * vec3(1.0, 0.5, 0.3) * pow(sun, 10.0);

    vec4 res = raymarch(ro, rd);
    color = color * (1.0 - res.a) + res.rgb;

    finalColor = vec4(color, 1.0);
}