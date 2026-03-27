# Morph WebGPU — Uber-shader with continuous parameter morphing

A single WGSL fragment shader that can express multiple visual effects from
the Radiant gallery by interpolating ~30 uniforms. No iframes, no texture
crossfades — the algorithm itself morphs.

## Source gallery items

Four shaders were decomposed into a shared pipeline:

| Gallery shader | Core technique extracted | Uber-shader feature |
|---|---|---|
| **fluid-amber** | Simplex FBM + triple domain warp (q→r→f) | `warp_scale`, `warp1_str`, `warp2_str` control warp chain depth. Low scale + high warp = large flowing shapes. |
| **chromatic-bloom** | Gaussian orb field with additive color | `orb_count`, `orb_radius`, `orb_intensity`, `orb_color_mode`. 7 orbs with per-orb hue, soft gaussian falloff. `orb_color_mode` crossfades between mask mode (orbs modulate noise) and additive mode (orbs emit color directly). |
| **silk-cascade** | Fabric fold displacement + Kajiya-Kay anisotropic specular | `fold_str`, `fold_freq` drive sin-wave fold height with 2-octave FBM warp. `normal_str` enables analytic normals from fold gradient. `spec_str` blends between Blinn-Phong (isotropic) and Kajiya-Kay (anisotropic along fold tangent). |
| **ink-dissolve** | Double domain-warped FBM + edge glow at ink boundaries | `edge_glow_str` detects the transition zone in the field (`ink * (1-ink) * 4`) and adds bright color at boundaries. The domain warp chain is shared with fluid-amber. |

Two additional techniques from batch 2 analysis:

| Analysed shader | Technique extracted | Uber-shader feature |
|---|---|---|
| **smolder (slow-burn)** | Ridged noise — `1 - abs(n*2 - 0.3)` folds FBM into bright vein patterns | `ridge_str` (0=smooth, 1=ridged). Applied as a post-process on the field value. Veins appear when warp dominates. |
| **bioluminescence** | Multi-directional wave sum for ocean-like undulation | `wave_str`, `wave_freq`. Sum of 4 sine waves at different angles/speeds added to the field. Wave crests emit bright highlights. |

Voronoi cracks (from gilded-fracture) were implemented but removed — they
read as a static grid overlay rather than integrating with the flow, even
when computed in warped coordinates.

## Pipeline stages

All stages run unconditionally every frame. Parameters at zero produce zero
contribution via multiplication, not branching. This eliminates visual pops
when features fade in/out.

```
1. Coordinate setup     — aspect-correct UV, mouse swirl distortion
2. Domain-warped FBM    — 3-octave simplex noise with rotated warp chain
3. Ridge transform      — optional fold of field into vein patterns
4. Wave interference    — 4-directional sine sum added to field
5. Orb field            — 7 gaussian energy wells with per-orb color
6. Field combination    — noise * envelope + orb contribution
7. Fabric fold          — 4 overlapping sin waves with 2-octave FBM warp
8. Normal computation   — analytic gradient from warp vectors + fold tangent
9. Color palette        — 4-stop ramp (shadow→mid→bright→hot) from field value
                          + spatial hue variation from warp gradient + noise
10. Lighting            — 2-light diffuse + Blinn-Phong/Kajiya-Kay specular
                          + Fresnel + environment reflection
11. Additive orb color  — blended by orb_color_mode
12. Edge glow           — field transition zone detection
13. Wave crest glow     — highlights at wave peaks
14. Post-processing     — vignette, ACES tone mapping, film grain, hue rotation
```

## Uniform buffer layout (208 bytes, 52 floats)

```
 0: time            1: zoom           2: hue_shift      3: fbm_octaves
 4: res.x           5: res.y          6: mouse.x        7: mouse.y
 8: zoom_center.x   9: zoom_center.y 10: fbm_decay     11: fbm_freq_mul
12: warp_scale     13: warp1_str     14: warp2_str     15: orb_count
16: orb_radius     17: orb_intensity 18: orb_color_mode 19: fold_str
20: fold_freq      21: normal_str    22: diffuse_str   23: spec_str
24: spec_power     25: fresnel_f0    26: edge_glow_str 27: vignette_str
28: grain_str      29: ridge_str     30: voronoi_str   31: voronoi_scale
32-35: color_shadow (vec4)
36-39: color_mid (vec4)
40-43: color_bright (vec4)
44-47: color_hot (vec4)
48: wave_str       49: wave_freq     50: _pad          51: _pad
```

Per-frame uniforms (0-2, 4-9) are set by JS. Preset-driven uniforms (3,
10-31, 32-49) are interpolated between attractor presets.

## Attractor-based morphing

Instead of discrete transitions between presets, the system orbits in
parameter space around known-good configurations ("attractors"). Each
attractor corresponds to one of the gallery items above.

Four attractors are defined, each a flat array of 33 parameter values:

| # | Identity | Dominant features | Color palette |
|---|---|---|---|
| 0 | Flowing warp | High warp, 3 octaves, edge glow, ridged veins | Deep blue → teal → cyan → warm white |
| 1 | Orb field | 5 orbs, additive color mode, low warp | Indigo → magenta → violet → gold |
| 2 | Silk folds | High fold + lighting, Kajiya-Kay specular | Dark green → rose → pink → cyan |
| 3 | Ocean waves | Wave interference, gentle warp, normals | Navy → emerald → aqua → peach |

### Oscillator design

Each attractor has an independent **proximity signal** — a grid-free
sine-sum oscillator returning 0..1:

```js
drift(time, speed, seed) = 0.5 + 0.25 * (
    sin(t * 1.0      + s * 2.399) +
    sin(t * 1.618... + s * 3.147) +   // golden ratio
    sin(t * 2.236... + s * 1.893) +   // sqrt(5)
    sin(t * 0.732... + s * 4.261)     // sqrt(3)-1
)
```

Irrational frequency ratios ensure the combined waveform never repeats.
The function is infinitely differentiable — no grid boundaries, no
derivative discontinuities, no visual jumps.

### Winner-take-all selection

Raw proximity signals are squared before normalizing:

```
weight_i = prox_i^2 / sum(prox_j^2)
```

This concentrates ~75% of the blend weight on the dominant attractor.
The visual spends most of its time looking like a specific gallery item,
with smooth transitions as dominance shifts.

Each parameter is then:

```
value = sum(weight_i * preset_i[param]) * (1 + jitter * 0.06)
```

The jitter is a per-parameter sine-sum at a faster rate, adding organic
variation (±3%) on top of the attractor blend.

## Performance architecture

- **WebGPU** with a pre-recorded `GPURenderBundle` for the draw call
- **Single uniform buffer** (208 bytes) uploaded via `device.queue.writeBuffer` once per frame
- **Zero JS allocations in the render loop** — pre-allocated `Float32Array` for uniforms, `Float64Array` for proximity weights, indexed loops over flat arrays
- **No `canvas.width` assignment in the tick loop** — resize only on `window.resize` events to avoid clearing the WebGPU surface
- **DPR capped at 1x** — the uber-shader is compute-heavy (5x FBM calls in the warp chain + fold + orbs + lighting); 1x keeps it at 60fps on integrated GPUs
- **All time offsets oscillate** (`sin/cos`) rather than advancing linearly — prevents directional drift of the noise field

## Files

```
+page.svelte      — Animation loop, attractor presets, oscillator logic
+page.ts          — SvelteKit page config (prerender: true)
engine.ts         — WebGPU device/pipeline/buffer setup, render method
presets.ts        — Uniform buffer layout constants and index exports
shader.wgsl.ts    — Complete WGSL uber-shader (vertex + fragment)
```

## What could be added next

Batch 2 techniques not yet integrated:

| Technique | Source shader | Complexity | Notes |
|---|---|---|---|
| Arc/lightning bolts | voltage-arc | ~30 lines WGSL | Parametric line projection + noise displacement + distance glow. 2-3 uniforms. |
| Metaball isosurfaces | neon-drip | ~25 lines WGSL | Replace gaussian orb falloff with inverse-distance energy wells. Could be an `orb_sharpness` uniform on the existing orb system. |
| Animated state machine | torn-paper | ~50 lines WGSL | Phase-driven lifecycle (calm→tear→open→reform). Would need a dedicated time uniform for phase progression. |
| Gravitational lensing | event-horizon | ~80 lines WGSL | UV distortion via ray marching loop. Heavy — would need its own attractor with reduced FBM octaves to stay in budget. |
