# Volumetric Cloud Renderer

A real-time volumetric cloud renderer written in **Odin** using **raylib** and **GLSL**. The renderer uses GPU raymarching to render procedurally generated cloud fields composed of multiple smoothly blended Signed Distance Field (SDF) spheres, combined with fractal noise for realistic cloud shapes.

<!-- ![Cloud Renderer](docs/screenshot.png) -->

> A graphics programming project demonstrating raymarching, volumetric lighting, and procedural cloud generation without relying on a game engine.

---

## Features

-  Real-time volumetric cloud rendering
-  Procedural cloud field using multiple SDF cloud clusters
-  Fractal Brownian Motion (FBM) noise for cloud detail
-  Volumetric lighting with Beer-Lambert absorption
-  Henyey-Greenstein phase function for anisotropic scattering
-  Self-shadowing through secondary light marching
-  Powder edge effect
-  Blue-noise dithering to reduce raymarch banding
-  Configurable sky gradient and cloud tint
-  Hot shader reloading (F5)
-  Interactive parameter editor using Microui

---

## Screenshots

| Clouds | Parameters |
|--------|------------|
|||

---

## Rendering Pipeline

```
Camera
   │
   ▼
Cast Ray
   │
   ▼
Raymarch Through Cloud Field
   │
   ▼
Evaluate Density
   │
   ├── Multiple Cloud Clusters
   ├── Multiple SDF Spheres
   ├── Smooth Union
   └── FBM Noise
   │
   ▼
Light March
   │
   ▼
Beer's Law
HG Phase Function
Powder Effect
Ambient Light
   │
   ▼
Composite with Sky
   │
   ▼
Final Image
```

---

## Cloud Generation

Each cluster is built from multiple overlapping SDF spheres that are blended using smooth union operations.
The resulting density field is then eroded using Fractal Brownian Motion (FBM) noise to create soft cloud edges.

---

## Rendering Techniques

This project demonstrates several modern graphics techniques:

- GPU Raymarching
- Signed Distance Fields (SDF)
- Smooth Union Blending
- Fractal Brownian Motion (FBM)
- Procedural Cloud Generation
- Volumetric Lighting
- Beer-Lambert Absorption
- Henyey-Greenstein Phase Function
- Self Shadowing
- Blue Noise Dithering
- HDR Tonemapping

---

## GUI Controls

The renderer exposes all major parameters in real time.

### Cloud

- Sphere Radius
- Density Scale
- Noise Scale
- Noise Speed
- March Size
- Maximum Steps
- Light Steps

### Lighting

- Absorption
- Ambient
- Powder Strength
- Anisotropy
- Sun Glow

### Sun

- Direction
- Color

### Sky

- Top Color
- Bottom Color
- Cloud Tint

### Toggles

- Clouds
- Animation
- Self Shadow
- Powder Effect
- Anisotropy
- Sun Glow
- Sky Gradient
- Dither
- Tonemap
- Fast Preview

## Dependencies

- Odin
- raylib
- Microui
- OpenGL 4.5

---

## Building

Clone the repository

```bash
git clone https://github.com/Rasaili-rain/volumetric_clouds_odin
cd volumetric-cloud-renderer
```

Run

```bash
odin run .
```
