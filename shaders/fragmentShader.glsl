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

// --- feature toggles (0 = off, 1 = on) ---
layout(location = 22) uniform int uEnableClouds;        // master switch, sky-only when off
layout(location = 23) uniform int uEnableAnimation;      // freezes the noise field in time when off
layout(location = 24) uniform int uEnableLightMarch;      // self-shadowing toward the sun
layout(location = 25) uniform int uEnablePowder;          // powder-edge darkening
layout(location = 26) uniform int uEnableAnisotropy;       // Henyey-Greenstein phase vs. isotropic scattering
layout(location = 27) uniform int uEnableSunGlow;           // additive sun disc/glow in the sky
layout(location = 28) uniform int uEnableSkyGradient;         // top/bottom sky gradient vs. flat color
layout(location = 29) uniform int uEnableDither;               // blue-noise temporal dithering of march offset
layout(location = 30) uniform int uEnableTonemap;               // Reinhard tonemap + gamma correction
layout(location = 31) uniform int uLowQualityNoise;               // forces cheap 3-octave fbm everywhere (fast preview)

#define MAX_STEPS 100
#define MAX_STEPS_LIGHTS 6
#define PI 3.14159265359

const int CLOUD_CLUSTERS = 12;
const int SPHERES_PER_CLUSTER = 6;

float sdSphere(vec3 p, float radius) {
    return length(p) - radius;
}

float hash(float n)
{
    return fract(sin(n) * 43758.5453123);
}

vec3 hash3(float n)
{
    return vec3(
        hash(n),
        hash(n + 17.13),
        hash(n + 31.71)
    );
}

float smoothUnion(float d1, float d2, float k)
{
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
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
    float t = uTime * float(uEnableAnimation);
    vec3 q = p + t * uNoiseSpeed * vec3(1.0, -0.2, -1.0);
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

// float scene(vec3 p, bool lowRes) {
//     bool useLowRes = lowRes || (uLowQualityNoise == 1);
//     float distance = sdSphere(p, uSphereRadius);
//     float f = fbm(p * uNoiseScale, useLowRes);
//     return -distance + f;
// }

float scene(vec3 p, bool lowRes)
{
    bool useLowRes = lowRes || (uLowQualityNoise == 1);

    float density = -1000.0;

    float time = uTime * float(uEnableAnimation);

    for(int c = 0; c < CLOUD_CLUSTERS; c++)
    {
        vec3 rnd = hash3(float(c));

        vec3 clusterPos =
            vec3(
                (rnd.x - 0.5) * 18.0,
                (rnd.y - 0.5) * 2.5,
                (rnd.z - 0.5) * 18.0
            );

        clusterPos += vec3(
            time * 0.35 / 2,
            sin(time*0.2+float(c))*0.08,
            time * 0.15 / 2
        );
        // clusterPos.x += time * 0.35;
        // clusterPos.z += time * 0.10;

        float clusterDensity = 1000.0;
        float bound = sdSphere(p - clusterPos, 4.0);

        if (bound > 0.5)
            continue;

        for(int s = 0; s < SPHERES_PER_CLUSTER; s++)
        {
            float seed = float(c * 100 + s);

            vec3 r = hash3(seed);

            vec3 offset =
                (r - 0.5) *
                vec3(2.5,1.2,2.5);

            float radius =
                uSphereRadius *
                mix(0.35,0.75,hash(seed+9.0));

            vec3 q = p - clusterPos - offset;

            q.y *= 1.5;

            float sphere = sdSphere(q,radius);

            clusterDensity =
                smoothUnion(
                    clusterDensity,
                    sphere,
                    0.5
                );
        }

        clusterDensity = -clusterDensity;

        float erosion =
            fbm(
                (p-clusterPos) *
                uNoiseScale,
                useLowRes
            );

        clusterDensity += erosion;

        density = max(density,clusterDensity);
    }
    float h =
        smoothstep(-1.5,-0.4,p.y)
        *
        (1.0-smoothstep(0.8,2.2,p.y));

    density *= h;
    return density;
}

float lightmarch(vec3 position, vec3 rayDirection) {
    if (uEnableLightMarch == 0) return 1.0;
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

    float phase = (uEnableAnisotropy == 1)
        ? HenyeyGreenstein(uAnisotropy, dot(rayDirection, sunDirection))
        : (1.0 / (4.0 * PI));

    for (int i = 0; i < MAX_STEPS; i++) {
        if (i >= uMaxSteps) break;
        float density = scene(p, false);
        if (density > 0.0) {
            float lightTransmittance = lightmarch(p, rayDirection);
            // powder effect: darkens dense cloud cores, brightens thin wispy edges
            float powder = (uEnablePowder == 1) ? (1.0 - exp(-density * 2.0)) : 1.0;
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
    if (uEnableSkyGradient == 1) {
        color -= uSkyColorBottom * rd.y;
    }
    if (uEnableSunGlow == 1) {
        color += 0.5 * uSunColor * pow(sun, uSunGlowExponent);
    }

    float offset = 0.5;
    if (uEnableDither == 1) {
        float blueNoise = texture(uBlueNoiseTex, gl_FragCoord.xy / vec2(textureSize(uBlueNoiseTex, 0))).r;
        offset = fract(blueNoise + float(uFrame % 32) * 0.61803398875);
    }

    vec3 res = vec3(0.0);
    if (uEnableClouds == 1) {
        res = raymarch(ro, rd, offset);
    }

    color = color + uSunColor * res;

    if (uEnableTonemap == 1) {
        color = color / (color + vec3(1.0));
        color = pow(color, vec3(1.0 / 2.2));
    }

    finalColor = vec4(color, 1.0);
}
