#version 450
in vec2 fragTexCoord;
out vec4 finalColor;

layout(location = 0) uniform float uTime;
layout(location = 1) uniform vec2 uResolution;
layout(location = 2) uniform sampler2D uNoiseTex;
layout(location = 3) uniform sampler2D uBlueNoiseTex;
layout(location = 4) uniform int uFrame;

// --- tweakable params ---
layout(location = 5)  uniform float uSphereRadius;
layout(location = 6)  uniform float uAbsorption;
layout(location = 7)  uniform float uAnisotropy;
layout(location = 8)  uniform vec3  uSunDir;
layout(location = 9)  uniform vec3  uSunColor;
layout(location = 10) uniform vec3  uSkyColorTop;
layout(location = 11) uniform vec3  uSkyColorBottom;
layout(location = 12) uniform float uMarchSize;
layout(location = 13) uniform float uDensityScale;
layout(location = 14) uniform int   uMaxSteps;
layout(location = 15) uniform int   uMaxLightSteps;
layout(location = 16) uniform float uNoiseSpeed;
layout(location = 17) uniform float uAmbient;          // base ambient light added to every lit sample
layout(location = 18) uniform float uPowderStrength;    // 0..1, blends in the "powder sugar" darkening at cloud edges
layout(location = 19) uniform vec3  uCloudTint;         // multiplies accumulated cloud color (RGB tint)
layout(location = 20) uniform float uSunGlowExponent;   // controls the tightness of the sun disc/glow
layout(location = 21) uniform float uNoiseScale;        // scales world-space coords fed into fbm (cloud "zoom")

#define MAX_STEPS 100
#define MAX_STEPS_LIGHTS 6
#define PI 3.14159265359

float sdSphere(vec3 p, float radius) {
    return length(p) - radius;
}

float BeersLaw(float dist, float absorption) {
    return exp(-dist * absorption);
}

float HenyeyGreenstein(float g, float mu) {
    float gg = g * g;
    return (1.0 / (4.0 * PI)) * ((1.0 - gg) / pow(1.0 + gg - 2.0 * g * mu, 1.5));
}

float noise(in vec3 x) {
    vec3 p = floor(x);
    vec3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    vec2 texSize = vec2(textureSize(uNoiseTex, 0));
    vec2 uv = (p.xy + f.xy + vec2(37.0, 17.0) * p.z + 0.5) / texSize;
    vec2 rg = textureLod(uNoiseTex, uv, 0.0).yx;
    return mix(rg.x, rg.y, f.z) * 2.0 - 1.0;
}

float fbm(vec3 p, bool lowRes) {
    vec3 q = p + uTime * uNoiseSpeed * vec3(1.0, -0.2, -1.0);
    float f = 0.0;
    float scale = 0.5;
    float factor = 2.02;
    int maxOctave = lowRes ? 3 : 6;
    for (int i = 0; i < maxOctave; i++) {
        f += scale * noise(q);
        q *= factor;
        factor += 0.21;
        scale *= 0.5;
    }
    return f * uDensityScale;
}

float scene(vec3 p, bool lowRes) {
    float distance = sdSphere(p, uSphereRadius);
    float f = fbm(p * uNoiseScale, lowRes);
    return -distance + f;
}

float lightmarch(vec3 position, vec3 rayDirection) {
    vec3 lightDirection = normalize(uSunDir);
    float totalDensity = 0.0;
    float marchSize = 0.03;
    for (int step = 0; step < MAX_STEPS_LIGHTS; step++) {
        if (step >= uMaxLightSteps) break;
        position += lightDirection * marchSize * float(step);
        totalDensity += scene(position, true);
    }
    return BeersLaw(totalDensity, uAbsorption);
}

vec3 raymarch(vec3 rayOrigin, vec3 rayDirection, float offset) {
    float depth = uMarchSize * offset;
    vec3 p = rayOrigin + depth * rayDirection;
    vec3 sunDirection = normalize(uSunDir);
    float totalTransmittance = 1.0;
    vec3 lightEnergy = vec3(0.0);
    float phase = HenyeyGreenstein(uAnisotropy, dot(rayDirection, sunDirection));

    for (int i = 0; i < MAX_STEPS; i++) {
        if (i >= uMaxSteps) break;
        float density = scene(p, false);
        if (density > 0.0) {
            float lightTransmittance = lightmarch(p, rayDirection);
            // powder effect: darkens dense cloud cores, brightens thin wispy edges
            float powder = 1.0 - exp(-density * 2.0);
            float shaded = uAmbient + density * phase * mix(1.0, powder, uPowderStrength);
            totalTransmittance *= lightTransmittance;
            lightEnergy += totalTransmittance * shaded * uCloudTint;
        }
        depth += uMarchSize;
        p = rayOrigin + depth * rayDirection;
    }
    return lightEnergy;
}

void main() {
    vec2 uv = gl_FragCoord.xy / uResolution.xy;
    uv -= 0.5;
    uv.x *= uResolution.x / uResolution.y;

    vec3 ro = vec3(0.0, 0.0, 5.0);
    vec3 rd = normalize(vec3(uv, -1.0));

    vec3 sunDirection = normalize(uSunDir);
    float sun = clamp(dot(sunDirection, rd), 0.0, 1.0);

    vec3 color = uSkyColorTop;
    color -= uSkyColorBottom * rd.y;
    color += 0.5 * uSunColor * pow(sun, uSunGlowExponent);

    float blueNoise = texture(uBlueNoiseTex, gl_FragCoord.xy / vec2(textureSize(uBlueNoiseTex, 0))).r;
    float offset = fract(blueNoise + float(uFrame % 32) * 0.61803398875);

    vec3 res = raymarch(ro, rd, offset);
    color = color + uSunColor * res;
    finalColor = vec4(color, 1.0);
}
