# Morph WebGPU — Tranche 2: New Techniques

## Constraint

The uber-shader evaluates ONE noise field, ONE fold, ONE orb set, ONE wave field per pixel, then colors and lights it. A new preset can only tune parameters of existing stages. To add a genuinely new visual mode, we need new pipeline stages — but they must be small, parameterizable, and zero-contribution when off.

## Recommended batch: 5 new techniques (~90 WGSL lines, 10 new uniforms)

| # | Technique | Represents | New WGSL | New uniforms | What it adds visually |
|---|-----------|-----------|----------|-------------|----------------------|
| 1 | **Kaleidoscope fold** | kaleidoscope-runway | ~15 lines | `kaleido_str`, `kaleido_segments` | Folds UV into radial segments *before* noise — any pattern becomes a mandala |
| 2 | **Spiral warp** | vortex | ~25 lines | `spiral_str`, `spiral_arms`, `spiral_tight` | Log-spiral distance field mixed into noise — creates spiral arm structures |
| 3 | **Metaball orbs** | neon-drip | ~10 lines | `orb_sharpness` | Switches orb falloff from gaussian to inverse-distance — sharp merging blobs |
| 4 | **Moiré interference** | moire-interference | ~20 lines | `moire_str`, `moire_freq` | 4 orbiting ring centers with multiplicative beats — geometric patterns |
| 5 | **Burn frontier** | burning-film | ~20 lines | `burn_str`, `burn_speed` | Threshold sweep on noise field — advancing/retreating bright frontier edge |

Each adds a visually distinct mode that doesn't exist in the current 4 presets. All can be zeroed via multiplication (no branching). Total cost: ~90 WGSL lines + 40 bytes of uniforms.

## Why these five

**Kaleidoscope fold** has the best impact-to-cost ratio. 15 lines of UV folding before noise evaluation transforms *any* existing pattern (warp, fold, wave) into a mandala. It's a coordinate transform, not a new field computation — essentially free.

**Spiral warp** gives a completely new structural motif (spiral arms) that nothing in the current pipeline can produce. The log-spiral distance function is cheap (~25 lines) and mixes naturally with the noise field.

**Metaball orbs** is almost free — 10 lines modifying the existing `compute_orbs` function to switch falloff shape. But it turns the soft chromatic-bloom look into sharp, merging neon-drip blobs. High visual payoff.

**Moiré interference** adds a geometric/mathematical aesthetic. Purely analytical (sin of distance), no noise needed. The multiplicative beating of 4 ring patterns creates emergent large-scale structure that's visually distinct from everything noise-based.

**Burn frontier** reuses the existing domain-warped FBM field but applies a moving threshold — the burn boundary advances/retreats over time, creating a bright frontier edge. This gives a temporal narrative (the "burn" cycle) that the other presets lack.

## What's NOT recommended and why

| Shader | Why not |
|--------|---------|
| **voltage-arc** | Line-segment projection + displacement is a fundamentally different rendering paradigm. ~180 lines, needs its own arc geometry pipeline. |
| **aurora-veil** | 7 independent ribbon evaluations, each with multi-frequency undulation. Can't collapse into one field evaluation. |
| **thunder-sermon** | 250+ lines. Fractal tree generation with 14→5→3 segment hierarchy + multi-phase flash lifecycle. Too specialized. |
| **gothic-filigree** | Pure SDF geometry, 200+ lines, zero noise. Fundamentally incompatible with a noise-based pipeline. |
| **artpop-iridescence** | Thin-film interference replaces the entire color model (RGB phase offsets from thickness × viewing angle). Would need a parallel color path. |
| **shifting-veils** | Evaluates domain-warped FBM 7 times at different scales/parallax depths. 7x the cost. |
| **liquid-gold** | Very similar to fluid-amber (domain warp + metallic lighting). A variation, not a new mode. The PBR Fresnel needs finite-difference normals — expensive. |
| **magnetic-field** | Analytical dipole math is elegant but niche. ~160 lines for one visual mode. |
| **moonlit-ripple** | Ray-plane intersection for water surface. Different rendering paradigm (3D perspective). |
| **stardust-veil** | Grid-based star particles need per-cell hash loops. ~40 lines for a less visually distinct result compared to the 5 above. |

## Source shader analysis

### Batch A (analyzed)

**moonlit-ripple** — ~100 WGSL lines. Analytical multi-directional waves (7 layers) with normal derivatives, Fresnel + reflection/refraction blending. Ray-plane intersection for water surface. Different rendering paradigm (3D perspective).

**neon-drip** — ~120 WGSL lines. Metaball implicit surface via inverse-distance formulation (`field = Σ(r²/d²)`), tendril field overlay (vertically-stretched noise), multi-layer threshold coloring. 4-12 blobs with rising/wobbling animation.

**voltage-arc** — ~180 WGSL lines. Line-segment displacement via 3-layer noise, distance-based glow (core/inner/outer), pulse/flicker modulation. 4 conductors + 5 primary arcs + 2 branch arcs. Mouse becomes 5th conductor.

**aurora-veil** — ~180 WGSL lines. 7 aurora ribbons with Gaussian profile + multi-frequency vertical undulation. 120 procedural stars with depth-based twinkling. Hexagonal ice crystal pattern. Reflection layer.

**shifting-veils** — ~140 WGSL lines. 7 layers of domain-warped FBM (2-level wrap: fbm→fbm→fbm) with per-layer parallax + rotation. Periodic opacity fading, edge glow. Warm sepia palette.

### Batch B (analyzed)

**liquid-gold** — ~180-200 WGSL lines. Domain warping (3-layer) + 7 metaballs for surface bumps. Finite-difference normal estimation. Fresnel + Blinn-Phong × 3 lights. Fake environment reflection. Very similar to fluid-amber with metallic lighting.

**artpop-iridescence** — ~200-220 WGSL lines. 3 bubble surfaces with domain-warped noise height. Thin-film interference: RGB cosine waves with 2π/3 phase offsets from thickness × cos(θ). Gravity-driven thickness variation. Breathing pulse.

**vortex** — ~110-130 WGSL lines. Logarithmic spiral math (`θ = ln(r/a)/b`), discrete arm quantization, noise perturbation on paths. Line rendering (silk glow: thin bright core → soft edge fade). 3-13 layers with increasing arm count.

**moire-interference** — ~140-160 WGSL lines. 4 orbiting centers in elliptical paths. Concentric rings: `sin(distance × freq)` per center. Multiplicative interference creates moiré beats. Additive blend for richness. Shimmer overlay.

**magnetic-field** — ~140-160 WGSL lines. Analytical dipole field line formula (`R = r/sin²(θ)`). Discrete line quantization. Pulsing energy along θ. Silk glow rendering. Mouse controls dipole orientation.

### Batch C (analyzed)

**stardust-veil** — ~120-150 WGSL lines. Grid-based star field (3 parallax depth layers at scales 35, 18, 8). Hash-based placement + twinkle. Background nebula via domain-warped FBM. Aurora ridges via ridged noise. Traveling diagonal wave pulse.

**gothic-filigree** — ~200-250 WGSL lines. Pure SDF geometry: 5 concentric zones with arches, petals, ornaments, trefoils, spirals. 4-fold mirror + 8-fold polar symmetry. Center-outward reveal animation. Zero noise.

**kaleidoscope-runway** — ~140-180 WGSL lines. Kaleidoscope UV fold (atan/mod/abs into segment). 4 geometric pattern layers (chevron, diamond, stripe, triangle) with morphing blend weights over ~16s cycles. 5-color palette cycle. Mandala star center.

**thunder-sermon** — ~250-320 WGSL lines. Fractal jagged path (14 main + 5 branch + 3 sub-branch segments). 6-phase flash lifecycle (bright→glow→restrike→decay). Domain-warped FBM storm clouds. Sheet lightning at 3 positions.

**burning-film** — ~180-220 WGSL lines. Domain-warped FBM with threshold sweep (0.88→0.08 over cycle). Burn frontier detection (bright edge at threshold boundary). Film grain + scanlines + sprocket holes. 4 spark particle layers drifting upward.

## Implementation plan

### Uniform buffer extension

Current: 52 floats (208 bytes). New uniforms needed:

```
52: kaleido_str      53: kaleido_segments
54: spiral_str       55: spiral_arms      56: spiral_tight
57: orb_sharpness    58: moire_str        59: moire_freq
60: burn_str         61: burn_speed
62: _pad             63: _pad
```

New total: 64 floats (256 bytes). Aligned to 16 bytes.

### WGSL additions

1. **Kaleidoscope fold** — insert before `warped_field` call:
   ```wgsl
   fn kaleido_fold(p: vec2f) -> vec2f {
     let angle = atan2(p.y, p.x);
     let r = length(p);
     let seg = 3.14159 / u.kaleido_segments;
     let a = ((angle % (2.0 * seg)) + 2.0 * seg) % (2.0 * seg);
     let folded_a = select(a, 2.0 * seg - a, a > seg);
     return mix(p, vec2f(cos(folded_a), sin(folded_a)) * r, u.kaleido_str);
   }
   ```

2. **Spiral warp** — add to field after warped_field:
   ```wgsl
   fn spiral_field(p: vec2f, t: f32) -> f32 {
     let r = length(p);
     let theta = atan2(p.y, p.x);
     let spiral_theta = log(max(r, 0.01) / 0.03) / u.spiral_tight;
     let arm_spacing = 6.28318 / u.spiral_arms;
     var ang_dist = ((theta - spiral_theta + t * 0.3) % arm_spacing + arm_spacing) % arm_spacing;
     if (ang_dist > arm_spacing * 0.5) { ang_dist -= arm_spacing; }
     let screen_dist = abs(ang_dist) * r;
     let line_w = 0.05 * smoothstep(0.1, 0.6, r);
     return smoothstep(line_w, 0.0, screen_dist) * smoothstep(0.8, 0.2, r);
   }
   ```

3. **Metaball orbs** — modify `compute_orbs`:
   ```wgsl
   // Replace: let glow = exp(-d * d / rr) * u.orb_intensity;
   // With:
   let gaussian = exp(-d * d / rr);
   let metaball = rr / max(d * d, 0.001);
   let glow = mix(gaussian, min(metaball, 4.0), u.orb_sharpness) * u.orb_intensity;
   ```

4. **Moiré interference** — new function:
   ```wgsl
   fn moire_field(p: vec2f, t: f32) -> f32 {
     var product = 1.0;
     for (var i = 0; i < 4; i++) {
       let fi = f32(i);
       let center = vec2f(
         0.22 * cos(t * 0.03 * (fi + 1.0) + fi * 2.1),
         0.18 * sin(t * 0.04 * (fi + 1.0) + fi * 1.4)
       );
       product *= sin(length(p - center) * u.moire_freq);
     }
     return product;
   }
   ```

5. **Burn frontier** — modify field post-processing:
   ```wgsl
   // After ridge, before orbs:
   let burn_phase = fract(t * u.burn_speed * 0.05);
   let burn_thresh = mix(0.85, -0.3, smoothstep(0.0, 0.85, burn_phase));
   let burn_mask = smoothstep(burn_thresh, burn_thresh - 0.12, field);
   let burn_edge = smoothstep(burn_thresh - 0.02, burn_thresh, field)
                 * smoothstep(burn_thresh + 0.08, burn_thresh, field);
   field = mix(field, field * burn_mask, u.burn_str);
   // burn_edge feeds into edge glow later
   ```

### New presets (added to P array)

```js
// 4: Kaleidoscope mandala — kaleidoscope-runway
[5, .40, 2.0, .60, 1.5, .8,  7,.25,0,0, 0,2, 0,0,0,40,0, .3,
 .2, 0,2,
 .02,.015,.01, .15,.10,.06, .65,.45,.20, .95,.80,.45,
 /* kaleido: */ 1.0, 8,  /* spiral: */ 0, 5, .18,
 /* orb_sharp: */ 0,  /* moire: */ 0, 60,  /* burn: */ 0, .5],

// 5: Spiral vortex — vortex
[3, .42, 2.05, .55, 1.0, .5,  7,.25,0,0, 0,2, 0,0,0,40,0, .2,
 0, 0,2,
 .02,.015,.008, .12,.08,.04, .55,.40,.18, .90,.75,.40,
 0, 8,  1.0, 5, .18,  0,  0, 60,  0, .5],

// 6: Neon metaballs — neon-drip
[5, .15, 2.0, .30, 0,0,  7,.28,1.8,1.0, 0,2, 0,0,0,40,0, 0,
 0, 0,2,
 .005,.005,.01, .03,.02,.06, .15,.08,.30, .90,.50,.80,
 0, 8,  0, 5, .18,  1.0,  0, 60,  0, .5],

// 7: Moiré beats — moire-interference
[5, .15, 2.0, .40, 0,0,  7,.25,0,0, 0,2, 0,0,0,40,0, 0,
 0, 0,2,
 .01,.01,.008, .08,.06,.04, .50,.35,.15, .85,.75,.40,
 0, 8,  0, 5, .18,  0,  1.0, 55,  0, .5],

// 8: Burning film — burning-film
[5, .48, 2.10, .65, 2.5, 1.8,  7,.25,0,0, 0,2, 0,0,0,40,0, .8,
 .4, 0,2,
 .02,.01,.005, .25,.10,.03, .80,.45,.12, 1.0,.85,.40,
 0, 8,  0, 5, .18,  0,  0, 60,  1.0, .4],
```

### Pipeline insertion points

```
1.  Coordinate setup (UV, mouse swirl)
2.  ★ Kaleidoscope fold (new — before noise)
3.  Domain-warped FBM
4.  Ridge transform
5.  ★ Spiral field (new — added to field)
6.  Wave interference
7.  ★ Burn frontier (new — threshold sweep on field)
8.  ★ Moiré interference (new — added to field)
9.  Orb field (★ with metaball option)
10. Field combination
11. Fabric fold
12. Normal computation
13. Color palette
14. Lighting
15. Additive orb color
16. Edge glow (+ burn edge contribution)
17. Wave crest glow
18. Post-processing
```
