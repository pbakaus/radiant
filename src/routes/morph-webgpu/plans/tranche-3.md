# Morph WebGPU — Tranche 3: New Techniques

## Recommended batch: 5 techniques (~110 WGSL lines, 10 new uniforms)

### New generators (create new visual structures)

| # | Technique | Source | WGSL | Uniforms | What it adds |
|---|-----------|--------|------|----------|-------------|
| 1 | **Chladni modes** | chladni-resonance | ~25 lines | `chladni_str`, `chladni_mode` | Standing-wave eigenfunctions: `cos(nπx)·cos(mπy)`. Cymatics patterns — geometric nodal lines from physics, nothing like noise. Dead simple math. |
| 2 | **Eclipse corona** | eclipse-glow | ~30 lines | `eclipse_str`, `eclipse_radius` | Polar-space FBM with radial falloff + angular modulation. Dark void center with bright corona rays — reuses existing FBM but in polar coordinates. |
| 3 | **Aurora curtain** | aurora-curtain | ~20 lines | `curtain_str`, `curtain_count` | Vertical sine-displaced line SDFs with per-line phase variation. Flowing luminous threads — a completely different primitive from noise fields. |

### Post-processing filters (modify how existing visuals look)

| # | Technique | Source | WGSL | Uniforms | What it adds |
|---|-----------|--------|------|----------|-------------|
| 4 | **Chromatic aberration** | tropical-heat | ~10 lines | `chroma_str` | Sample the final color at 3 radially-offset UVs for R/G/B. Prismatic fringing at edges — cheapest possible, highest visual impact. |
| 5 | **Hologram glitch** | hologram-glitch | ~25 lines | `glitch_str`, `glitch_speed` | Horizontal scanline overlay + temporal glitch bursts (RGB channel displacement keyed to hash-based timing). Makes any visual look digital/corrupt. |

## Implementation plan

### Uniform buffer extension

Current: 64 floats (256 bytes). New uniforms needed:

```
60: chladni_str     61: chladni_mode
62: eclipse_str     63: eclipse_radius
64: curtain_str     65: curtain_count
66: chroma_str      67: glitch_str
68: glitch_speed    69: _pad
70: _pad            71: _pad
```

New total: 72 floats (288 bytes). Replaces the current 4 padding floats at 60-63 and adds 8 more.

### WGSL additions

1. **Chladni modes** — new field generator:
   ```wgsl
   fn chladni_field(p: vec2f, t: f32) -> f32 {
     // 6 mode pairs cycled via chladni_mode (0-5)
     // Standing wave: cos(n*PI*x) * cos(m*PI*y) + cos(m*PI*x) * cos(n*PI*y)
     // Nodal lines where field ≈ 0 → sand accumulates
     // Mode interpolation for smooth transitions
   }
   ```

2. **Eclipse corona** — new field generator:
   ```wgsl
   fn eclipse_field(p: vec2f, t: f32) -> f32 {
     let r = length(p);
     let angle = atan2(p.y, p.x);
     // Dark void at center: smoothstep cutoff at eclipse_radius
     // Corona rays: FBM in polar coords (angle + r*stretch)
     // Angular modulation for asymmetric streamers
     // Radial falloff: 1/r^1.5 envelope
   }
   ```

3. **Aurora curtain** — new field generator:
   ```wgsl
   fn curtain_field(p: vec2f, t: f32) -> f32 {
     var glow = 0.0;
     for (var i = 0; i < 8; i++) {
       // Per-line: x-center drifts via sine, width tapers at top/bottom
       // Displacement: multi-freq sine stack along y
       // Line SDF: smoothstep(width, 0, |x - center|)
       glow += line_contrib;
     }
     return glow;
   }
   ```

4. **Chromatic aberration** — post-processing (replaces single color read):
   ```wgsl
   // After tone mapping, before final output:
   // Offset direction = normalize(p) * chroma_str * 0.02
   // Re-evaluate color palette at p, p+offset, p-offset for R, G, B
   // Or: shift the hue_rotate angle per channel
   ```

5. **Hologram glitch** — post-processing:
   ```wgsl
   fn glitch_effect(col: vec3f, uv: vec2f, t: f32) -> vec3f {
     // Scanlines: sin(uv.y * 400) * 0.03
     // Glitch burst: hash(floor(t * glitch_speed)) > 0.7 → active
     // During burst: horizontal band offset (hash-based y-range)
     // RGB channels displaced independently
   }
   ```

### Pipeline insertion points

```
 1. Coordinate setup (UV, mouse swirl)
 2. Kaleidoscope fold
 3. Domain-warped FBM
 4. Ridge transform
 5. Spiral field
 6. Burn frontier
 7. Moiré interference
 8. ★ Chladni modes (new — added to field)
 9. ★ Eclipse corona (new — added to field)
10. Voronoi cracks
11. Orb field (with metaball option)
12. Field combination
13. Fabric fold
14. Normal computation
15. Color palette
16. Lighting
17. Additive orb color
18. Edge glow + burn glow
19. Wave crest glow
20. ★ Aurora curtain glow (new — additive color)
21. Vignette
22. Tone mapping (ACES)
23. ★ Chromatic aberration (new — post-processing)
24. ★ Hologram glitch (new — post-processing)
25. Grain + hue shift
```

### New presets (added to P array)

```js
// 9: Chladni cymatics — chladni-resonance
// Standing-wave patterns with minimal noise background
[5, .15, 2.0, .40, 0,0, 7,.25,0,0, 0,2, 0,0,0,40,0, .2,
 0, 0,2,
 .01,.01,.008, .06,.05,.04, .45,.35,.20, .90,.80,.50,
 0,8, 0,5,.18, 0, 0,55, 0,.5,
 /* chladni: */ 1.0, 3, /* eclipse: */ 0, .15,
 /* curtain: */ 0, 6, /* chroma: */ 0, /* glitch: */ 0, .5],

// 10: Eclipse corona — eclipse-glow
// Dark void center with radial corona rays
[5, .42, 2.05, .60, 1.2,.6, 7,.25,0,0, 0,2, 0,0,0,40,0, .4,
 0, 0,2,
 .005,.005,.008, .08,.04,.02, .60,.35,.10, 1.0,.80,.35,
 0,8, 0,5,.18, 0, 0,55, 0,.5,
 0, 3, 1.0, .15,
 0, 6, 0, 0, .5],

// 11: Aurora threads — aurora-curtain
// Vertical flowing light curtains
[5, .15, 2.0, .35, 0,0, 7,.25,0,0, 0,2, 0,0,0,40,0, 0,
 0, 0,2,
 .008,.008,.005, .04,.06,.05, .25,.50,.35, .70,.90,.65,
 0,8, 0,5,.18, 0, 0,55, 0,.5,
 0, 3, 0, .15,
 1.0, 7, 0, 0, .5],

// 12: Hologram corruption — hologram-glitch
// Any noise pattern with digital glitch artifacts
[5, .40, 2.05, .55, 1.5,.8, 7,.25,0,0, 0,2, 0,0,0,40,0, .3,
 .15, 0,2,
 .01,.008,.015, .05,.04,.12, .20,.15,.45, .60,.80,.95,
 0,8, 0,5,.18, 0, 0,55, 0,.5,
 0, 3, 0, .15,
 0, 6, .15, 1.0, .6],
```

Note: chromatic aberration doesn't need its own preset — it enhances others.
Several existing presets could have small `chroma_str` values (0.05-0.10) for subtle fringing.

## Disqualified shaders (24 assessed)

### Requires multi-pass / frame state

| Shader | Why |
|--------|-----|
| **edge-of-chaos** | Gray-Scott reaction-diffusion needs per-frame state buffer for U/V concentrations |
| **lipstick-smear** | Navier-Stokes semi-Lagrangian advection + Jacobi pressure solve = multi-pass + state |
| **feedback-loop** | Reads previous frame output as input — needs frame buffer texture |
| **rain-on-glass** | Canvas physics engine pre-renders 255 drop bitmaps + refraction normal maps |

### Requires ray marching loop

| Shader | Why |
|--------|-----|
| **metamorphosis** | 6 metaball ray march + tetrahedron normal sampling + shadow march |
| **crystal-lattice** | 30+ crystal hex-prism SDFs + interior refraction march |
| **event-horizon** | Schwarzschild geodesic Verlet integration in curved spacetime |

### Too much WGSL (>150 lines for core technique)

| Shader | Lines | Why |
|--------|-------|-----|
| **painted-strata** | 200-250 | Tectonic folding + fault displacement + fiber texture + sparkle |
| **radiant-geometry** | 280 | 5+ SDF mandala layers with polar folding + golden spiral |
| **dither-gradient** | 180-220 | Bayer 8x8 matrix encoding + multi-pattern morphing |
| **gilt-mosaic** | 150 | 3D perspective tile flipping + wave cascade + multi-light specular |
| **neon-drive** | 220-280 | Perspective grid highway + mountain silhouettes + vanishing point |
| **diamond-caustics** | 100+ | Hex Voronoi refraction + chromatic dispersion + scintillation |

### Viable but lower priority

| Shader | Lines | Why deprioritized |
|--------|-------|-------------------|
| **tropical-heat** | 120-150 | Too similar to fluid-amber with chromatic aberration filter |
| **shattered-plains** | 130-160 | Geological terrain + erosion — interesting but niche |
| **signal-decay** | 110 | Oscilloscope waveform degradation — niche aesthetic |
| **vertigo** | 70 | Polar tunnel rings — overlaps with spiral + moiré |
| **sequin-wave** | 120 | Hex grid specularity — novel but complex for one mode |
| **lens-whisper** | 140-180 | Anamorphic flares — could extend orbs but heavy |
| **sacred-strange** | 280 | Same as radiant-geometry |

## Coverage after tranche 3

With tranches 1-3, the uber-shader would represent techniques from **17 gallery shaders** across **14 distinct visual modes**:

| Mode | Source shader | Tranche |
|------|-------------|---------|
| Domain-warped FBM | fluid-amber | 1 |
| Gaussian orb field | chromatic-bloom | 1 |
| Fabric fold + Kajiya-Kay | silk-cascade | 1 |
| Edge glow boundaries | ink-dissolve | 1 |
| Ridged vein noise | slow-burn | 1 |
| Wave interference | bioluminescence | 1 |
| Kaleidoscope fold | kaleidoscope-runway | 2 |
| Spiral arms | vortex | 2 |
| Metaball orbs | neon-drip | 2 |
| Moiré interference | moire-interference | 2 |
| Burn frontier | burning-film | 2 |
| Chladni cymatics | chladni-resonance | 3 |
| Eclipse corona | eclipse-glow | 3 |
| Aurora curtain | aurora-curtain | 3 |
| Chromatic aberration | tropical-heat | 3 (filter) |
| Hologram glitch | hologram-glitch | 3 (filter) |
