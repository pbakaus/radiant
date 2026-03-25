export const SHADER_WGSL = /* wgsl */`

struct Uniforms {
  time: f32,
  zoom: f32,
  hue_shift: f32,
  fbm_octaves: f32,

  res: vec2f,
  mouse: vec2f,

  zoom_center: vec2f,
  fbm_decay: f32,
  fbm_freq_mul: f32,

  warp_scale: f32,
  warp1_str: f32,
  warp2_str: f32,
  orb_count: f32,

  orb_radius: f32,
  orb_intensity: f32,
  orb_color_mode: f32,
  fold_str: f32,

  fold_freq: f32,
  normal_str: f32,
  diffuse_str: f32,
  spec_str: f32,

  spec_power: f32,
  fresnel_f0: f32,
  edge_glow_str: f32,
  vignette_str: f32,

  grain_str: f32,
  ridge_str: f32,       // NEW: 0=smooth FBM, 1=ridged veins
  voronoi_str: f32,     // NEW: 0=off, 1=full cracks
  voronoi_scale: f32,   // NEW: cell size (3-8)

  color_shadow: vec4f,
  color_mid: vec4f,
  color_bright: vec4f,
  color_hot: vec4f,

  wave_str: f32,
  wave_freq: f32,
  orb_sharpness: f32,   // 0=gaussian, 1=metaball (inverse-distance)
  moire_str: f32,       // 0=off, 1=full moiré interference

  burn_str: f32,        // 0=off, 1=full burn frontier
  burn_speed: f32,      // burn cycle speed
  spiral_str: f32,      // 0=off, 1=full spiral arms
  spiral_arms: f32,     // number of arms (3-8)

  kaleido_str: f32,     // 0=off, >0.3 activates fold
  kaleido_seg: f32,     // segment count (4-12)
  chroma_str: f32,      // 0=off, chromatic aberration strength
  chladni_str: f32,     // 0=off, 1=full chladni pattern

  chladni_mode: f32,    // 0-5 selects mode pair (interpolated)
  curtain_str: f32,     // 0=off, 1=full aurora curtains
  curtain_count: f32,   // number of curtain lines (3-8)
  _pad1: f32,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

// ─── Vertex ───
struct VSOut { @builtin(position) pos: vec4f };

@vertex
fn vs(@builtin(vertex_index) vi: u32) -> VSOut {
  var p = array<vec2f, 3>(vec2f(-1, -1), vec2f(3, -1), vec2f(-1, 3));
  var out: VSOut;
  out.pos = vec4f(p[vi], 0, 1);
  return out;
}

// ─── Hash (for Voronoi) ───
fn hash2(p: vec2f) -> vec2f {
  let k = vec2f(
    fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453),
    fract(sin(dot(p, vec2f(269.5, 183.3))) * 43758.5453)
  );
  return k;
}

// ─── Simplex 2D noise ───
fn mod289_3(x: vec3f) -> vec3f { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn mod289_2(x: vec2f) -> vec2f { return x - floor(x * (1.0 / 289.0)) * 289.0; }
fn permute(x: vec3f) -> vec3f { return mod289_3((x * 34.0 + 1.0) * x); }

fn snoise(v: vec2f) -> f32 {
  let C = vec4f(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
  let i = floor(v + dot(v, C.yy));
  let x0 = v - i + dot(i, C.xx);
  var i1: vec2f;
  if (x0.x > x0.y) { i1 = vec2f(1.0, 0.0); } else { i1 = vec2f(0.0, 1.0); }
  var x12 = x0.xyxy + C.xxzz;
  x12 = vec4f(x12.xy - i1, x12.zw);
  let ii = mod289_2(i);
  let p = permute(permute(ii.y + vec3f(0.0, i1.y, 1.0)) + ii.x + vec3f(0.0, i1.x, 1.0));
  var m = max(vec3f(0.5) - vec3f(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), vec3f(0.0));
  m = m * m; m = m * m;
  let x_ = 2.0 * fract(p * C.www) - 1.0;
  let h = abs(x_) - 0.5;
  let ox = floor(x_ + 0.5);
  let a0 = x_ - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  var g: vec3f;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.y = a0.y * x12.x + h.y * x12.y;
  g.z = a0.z * x12.z + h.z * x12.w;
  return 130.0 * dot(m, g);
}

// ─── FBM ───
fn fbm(p_in: vec2f, t: f32) -> f32 {
  var p = p_in;
  var val = 0.0;
  var amp = 0.5;
  let rot = mat2x2f(0.8, 0.6, -0.6, 0.8);
  for (var i = 0; i < 5; i++) {
    if (f32(i) >= u.fbm_octaves) { break; }
    val += amp * snoise(p + vec2f(sin(t * 0.13), cos(t * 0.17)) * 2.0);
    p = rot * p * u.fbm_freq_mul;
    amp *= u.fbm_decay;
  }
  return val;
}

fn fbm2(p_in: vec2f, t: f32) -> f32 {
  var p = p_in;
  let rot = mat2x2f(0.8, 0.6, -0.6, 0.8);
  var v = 0.5 * snoise(p + vec2f(sin(t * 0.13), cos(t * 0.17)) * 2.0);
  p = rot * p * 2.0;
  return v + 0.25 * snoise(p + vec2f(sin(t * 0.13), cos(t * 0.17)) * 2.0);
}

// ─── Domain-warped field ───
var<private> g_warp_grad: vec2f;

fn warped_field(p: vec2f, t: f32) -> f32 {
  let q = vec2f(fbm(p, t), fbm(p + vec2f(5.2, 1.3), t));
  let wp1 = p + u.warp1_str * q;
  let r = vec2f(fbm(wp1 + vec2f(1.7, 9.2), t * 1.1), fbm(wp1 + vec2f(8.3, 2.8), t * 1.1));
  let f = fbm(p + u.warp2_str * r, t * 0.8);
  g_warp_grad = u.warp1_str * q + u.warp2_str * r;
  return f;
}

// ─── NEW: Ridged noise ───
// Folds the noise into bright vein/ridge patterns.
// ridge_str=0 → passthrough, ridge_str=1 → fully ridged
fn apply_ridge(field: f32) -> f32 {
  let ridged = 1.0 - abs(field * 2.0 - 0.3);
  return mix(field, ridged, u.ridge_str);
}

// ─── NEW: Voronoi cracks ───
// Returns (minDist, edgeDist). edgeDist is 0 at crack lines.
struct VoronoiResult { min_dist: f32, edge_dist: f32 };

fn voronoi_cracks(p_in: vec2f, t: f32) -> VoronoiResult {
  let p = p_in * u.voronoi_scale;
  let cell = floor(p);
  let local = fract(p);

  var min_d = 8.0;
  var second_d = 8.0;

  // 3x3 neighbor search
  for (var y = -1; y <= 1; y++) {
    for (var x = -1; x <= 1; x++) {
      let neighbor = vec2f(f32(x), f32(y));
      let offset = cell + neighbor;
      var pt = hash2(offset);
      // Animate cell points gently
      pt += 0.3 * vec2f(
        sin(t * 0.09 + pt.x * 20.0),
        cos(t * 0.07 + pt.y * 20.0)
      );
      let diff = neighbor + pt - local;
      let d = dot(diff, diff);
      if (d < min_d) {
        second_d = min_d;
        min_d = d;
      } else if (d < second_d) {
        second_d = d;
      }
    }
  }

  min_d = sqrt(min_d);
  second_d = sqrt(second_d);
  let edge = second_d - min_d; // 0 at crack lines

  return VoronoiResult(min_d, edge);
}

// ─── NEW: Wave interference ───
// Sum of directional sine waves for ocean-like undulation.
fn wave_field(p: vec2f, t: f32) -> f32 {
  var h = 0.0;
  let freq = u.wave_freq;

  // 4 waves at different angles, speeds, and amplitudes
  h += sin(p.x * freq * 1.0 + p.y * freq * 0.3 + t * 0.7) * 0.35;
  h += sin(p.x * freq * -0.4 + p.y * freq * 0.9 + t * 0.5 + 1.3) * 0.25;
  h += sin(p.x * freq * 0.6 + p.y * freq * -0.7 + t * 0.9 + 2.7) * 0.20;
  h += sin(p.x * freq * 1.3 + p.y * freq * 0.5 + t * 0.3 + 4.1) * 0.15;

  return h; // roughly -0.95..0.95
}

// ─── Orbs ───
fn orb_color(i: i32) -> vec3f {
  switch (i) {
    case 0 { return vec3f(0.03, 0.10, 1.00); }
    case 1 { return vec3f(1.00, 0.42, 0.03); }
    case 2 { return vec3f(0.85, 0.93, 1.00); }
    case 3 { return vec3f(1.00, 0.70, 0.08); }
    case 4 { return vec3f(0.03, 0.65, 0.65); }
    case 5 { return vec3f(0.25, 0.15, 0.50); }
    default { return vec3f(0.55, 0.25, 0.30); }
  }
}

struct OrbResult { field: f32, color: vec3f };

fn compute_orbs(p: vec2f, t: f32) -> OrbResult {
  var result: OrbResult;
  let count = i32(u.orb_count + 0.5);
  let rr = max(u.orb_radius * u.orb_radius, 0.001);
  for (var i = 0; i < 7; i++) {
    if (i >= count) { break; }
    let fi = f32(i);
    let center = vec2f(
      sin(t * (0.17 + fi * 0.02) + fi * 2.1) * 0.5 + cos(t * (0.13 + fi * 0.015) + fi * 1.3) * 0.25,
      cos(t * (0.15 + fi * 0.018) + fi * 1.7) * 0.4 + sin(t * (0.11 + fi * 0.022) + fi * 2.5) * 0.2
    );
    let d = length(p - center);
    let gaussian = exp(-d * d / rr);
    let metaball = min(rr / max(d * d, 0.0005), 4.0);
    let glow = mix(gaussian, metaball, u.orb_sharpness) * u.orb_intensity;
    result.field += glow;
    result.color += orb_color(i) * glow;
  }
  return result;
}

// ─── Fabric fold ───
fn fabric_fold(p: vec2f, t: f32) -> vec3f {
  let ts = t * 0.75;
  let warp = vec2f(
    fbm2(p * 1.2 + vec2f(1.7, 9.2) + vec2f(sin(ts * 0.11), cos(ts * 0.14)) * 1.5, ts),
    fbm2(p * 1.2 + vec2f(8.3, 2.8) + vec2f(cos(ts * 0.09), sin(ts * 0.13)) * 1.5, ts)
  );
  let wp = p + warp * 0.55;
  let freq = u.fold_freq;
  var h = 0.0;
  var g = vec2f(0.0);

  let f1 = vec2f(freq * 0.7, freq * 0.4);
  let ph1 = wp.x * f1.x + wp.y * f1.y + ts * 0.3;
  h += sin(ph1) * 0.35; g += cos(ph1) * 0.35 * f1;

  let f2 = vec2f(-freq * 0.3, freq * 0.9);
  let ph2 = wp.x * f2.x + wp.y * f2.y + ts * 0.25 + 1.3;
  h += sin(ph2) * 0.25; g += cos(ph2) * 0.25 * f2;

  let f3 = freq * 0.6;
  let ph3 = (wp.x + wp.y) * f3 + ts * 0.2 + 4.5;
  h += sin(ph3) * 0.18; g += cos(ph3) * 0.18 * vec2f(f3);

  let f4 = vec2f(freq * 1.8, freq * 1.2);
  let ph4 = wp.x * f4.x + wp.y * f4.y - ts * 0.35 + 0.7;
  h += sin(ph4) * 0.08; g += cos(ph4) * 0.08 * f4;

  return vec3f(h, g);
}

// ─── Kaleidoscope fold ───
// Folds UV into radial segments for mandala symmetry.
// Uses floor-based modulo for correct negative angle handling in WGSL.
fn kaleido_fold(p: vec2f) -> vec2f {
  let r = length(p);
  var a = atan2(p.y, p.x);
  let seg = 3.14159265 / max(u.kaleido_seg, 2.0);
  let seg2 = seg * 2.0;
  a = a - floor(a / seg2) * seg2;
  if (a > seg) { a = seg2 - a; }
  return vec2f(cos(a), sin(a)) * r;
}

// ─── Aurora curtain ───
// Vertical sine-displaced luminous lines with per-line phase variation.
fn curtain_field(p: vec2f, t: f32) -> f32 {
  var glow = 0.0;
  let count = i32(u.curtain_count + 0.5);
  for (var i = 0; i < 8; i++) {
    if (i >= count) { break; }
    let fi = f32(i);
    let spacing = 1.6 / max(u.curtain_count, 1.0);
    var cx = (fi - u.curtain_count * 0.5 + 0.5) * spacing;
    // Horizontal drift
    cx += sin(t * (0.12 + fi * 0.02) + fi * 1.7) * 0.15;
    // Vertical sine displacement: multi-freq stack
    let disp = sin(p.y * 3.0 + t * 0.4 + fi * 2.3) * 0.08
             + sin(p.y * 7.0 - t * 0.25 + fi * 1.1) * 0.03
             + sin(p.y * 1.5 + t * 0.15 + fi * 3.7) * 0.12;
    let dx = abs(p.x - cx - disp);
    // Tapered width: narrower at top/bottom
    let width = 0.025 * (1.0 - smoothstep(0.3, 0.6, abs(p.y)));
    glow += smoothstep(width * 2.0, 0.0, dx) * 0.4;
  }
  return glow;
}

// ─── Chladni modes ───
// Standing-wave eigenfunctions: cos(nπx)cos(mπy) + cos(mπx)cos(nπy).
// Sand accumulates on nodal lines where field ≈ 0.
// 6 mode pairs interpolated by chladni_mode (0-5).
fn chladni_field(p: vec2f, t: f32) -> f32 {
  let PI = 3.14159265;
  // Mode pairs (n,m): increasing complexity
  let modes = array<vec2f, 6>(
    vec2f(1, 2), vec2f(2, 3), vec2f(3, 4),
    vec2f(4, 5), vec2f(3, 7), vec2f(5, 6)
  );
  let idx = clamp(u.chladni_mode, 0.0, 4.99);
  let i0 = i32(idx);
  let i1 = min(i0 + 1, 5);
  let frac = idx - f32(i0);
  let m0 = modes[i0]; let m1 = modes[i1];
  // Chladni: cos(nπx)cos(mπy) + cos(mπx)cos(nπy)
  let sp = p * 2.5 + vec2f(sin(t * 0.07), cos(t * 0.09)) * 0.3; // slow drift
  let c0 = cos(m0.x * PI * sp.x) * cos(m0.y * PI * sp.y)
         + cos(m0.y * PI * sp.x) * cos(m0.x * PI * sp.y);
  let c1 = cos(m1.x * PI * sp.x) * cos(m1.y * PI * sp.y)
         + cos(m1.y * PI * sp.x) * cos(m1.x * PI * sp.y);
  let pattern = mix(c0, c1, frac);
  // Nodal lines: field near 0 → bright sand. Invert so sand = high.
  return 1.0 - smoothstep(0.0, 0.15, abs(pattern));
}

// ─── Spiral field ───
// Log-spiral distance field. Tightness hardcoded to 0.18.
fn spiral_field(p: vec2f, t: f32) -> f32 {
  let r = length(p);
  if (r < 0.01) { return 0.0; }
  let theta = atan2(p.y, p.x);
  let spiral_theta = log(r / 0.03) / 0.18;
  let arm_spacing = 6.28318 / max(u.spiral_arms, 1.0);
  let raw_ang = theta - spiral_theta + t * 0.3;
  var ang = raw_ang - floor(raw_ang / arm_spacing) * arm_spacing;
  if (ang > arm_spacing * 0.5) { ang -= arm_spacing; }
  let screen_d = abs(ang) * r;
  let line_w = 0.06 * smoothstep(0.08, 0.5, r);
  return smoothstep(line_w, 0.0, screen_d) * smoothstep(0.85, 0.15, r);
}

// ─── Moiré interference ───
// Multiplicative ring pattern from 4 orbiting centers. Freq hardcoded to 55.
fn moire_field(p: vec2f, t: f32) -> f32 {
  var product = 1.0;
  var additive = 0.0;
  for (var i = 0; i < 4; i++) {
    let fi = f32(i);
    let center = vec2f(
      0.22 * cos(t * 0.03 * (fi + 1.0) + fi * 2.1),
      0.18 * sin(t * 0.04 * (fi + 1.0) + fi * 1.4)
    );
    let ring = sin(length(p - center) * 55.0);
    product *= ring;
    additive += ring;
  }
  return product * 0.7 + additive * 0.25 * 0.3;
}

// ─── Hue rotation ───
fn hue_rotate(c: vec3f, a: f32) -> vec3f {
  let ca = cos(a); let sa = sin(a);
  let k = vec3f(0.57735);
  return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

// ─── Fragment ───
@fragment
fn fs(@builtin(position) frag_coord: vec4f) -> @location(0) vec4f {
  let raw_uv = frag_coord.xy / u.res;
  let uv = (raw_uv - u.zoom_center) / u.zoom + u.zoom_center;
  var p = (uv - 0.5) * vec2f(u.res.x / u.res.y, 1.0);
  let t = u.time;

  // Mouse swirl
  if (u.mouse.x > 0.0) {
    let mn = (u.mouse - u.res * 0.5) / min(u.res.x, u.res.y);
    let diff = p - mn;
    let d = length(diff);
    let angle = exp(-d * d * 8.0) * 1.5;
    let ca = cos(angle); let sa = sin(angle);
    p = mn + mat2x2f(ca, -sa, sa, ca) * diff;
  }

  // ── Build the field ──
  // Kaleidoscope: binary switch. Smooth transition would require double
  // warped_field evaluation (2x GPU cost) which saturates the GPU.
  // The snap is brief and happens during transitions when things are changing.
  let kp = select(p, kaleido_fold(p), u.kaleido_str > 0.4);
  let wp = kp * u.warp_scale;
  var field = warped_field(wp, t);

  // Ridged noise: fold field into vein patterns
  field = apply_ridge(field);

  // Wave interference: undulation added to field height
  field += wave_field(p, t) * u.wave_str;

  // Aurora curtain: vertical flowing light threads
  let curtain_gate = smoothstep(0.3, 0.6, u.curtain_str);
  let curtain_val = curtain_field(p, t) * curtain_gate;
  field += curtain_val;

  // Chladni modes: cymatics standing-wave patterns
  let chladni_gate = smoothstep(0.3, 0.6, u.chladni_str);
  field += chladni_field(p, t) * chladni_gate;

  // Spiral arms: log-spiral distance field
  let spiral_gate = smoothstep(0.3, 0.6, u.spiral_str);
  field += spiral_field(p, t) * spiral_gate;

  // Moiré interference: high-freq rings need hard gate to avoid bleed
  let moire_gate = smoothstep(0.3, 0.6, u.moire_str);
  field += moire_field(p, t) * moire_gate;

  // Burn frontier: threshold sweep on noise field with bright edge
  let burn_gate = smoothstep(0.3, 0.6, u.burn_str);
  let burn_phase = fract(t * u.burn_speed * 0.05);
  let burn_thresh = mix(0.85, -0.3, smoothstep(0.0, 0.85, burn_phase));
  let burn_mask = smoothstep(burn_thresh, burn_thresh - 0.12, field);
  let burn_edge = smoothstep(burn_thresh - 0.02, burn_thresh, field)
                * smoothstep(burn_thresh + 0.08, burn_thresh, field);
  field = mix(field, field * burn_mask, burn_gate);

  // Voronoi cracks: computed in WARPED space so they flow with the field
  // The warp gradient displaces the voronoi lookup, integrating it with the noise
  let vor_p = p + g_warp_grad * 0.15; // cracks follow the warp flow
  let vor = voronoi_cracks(vor_p, t);
  let crack_edge = vor.edge_dist;
  // Cracks CUT INTO the field — they create dark valleys with bright edges
  let crack_cut = smoothstep(0.12, 0.0, crack_edge); // 1 at crack, 0 away
  field = mix(field, field * 0.3 - 0.2, crack_cut * u.voronoi_str); // darken at cracks
  // Cell distance modulates the field subtly (each cell gets slightly different value)
  field += (vor.min_dist - 0.3) * u.voronoi_str * 0.2;

  // Orbs
  let orbs = compute_orbs(p, t);

  // Combine field + orbs
  let envelope = mix(
    mix(1.0, clamp(orbs.field, 0.0, 1.0), 1.0 - u.orb_color_mode),
    1.0, u.orb_color_mode
  );
  var height = field * envelope + orbs.field * (1.0 - u.orb_color_mode) * 0.08;

  // Fabric fold
  let fold = fabric_fold(p, t);
  height = mix(height, fold.x, u.fold_str);
  let fold_grad = fold.yz * u.fold_str;

  // Normal: warp gradient + fold gradient + crack edges contribute
  var grad = g_warp_grad * 0.3 + fold_grad * 1.8;
  // Crack edges add sharp normal discontinuity
  let crack_normal = crack_cut * u.voronoi_str * 4.0;
  grad += vec2f(crack_normal, crack_normal * 0.7);
  let aN = normalize(vec3f(-grad, 1.0));
  let N = normalize(mix(vec3f(0.0, 0.0, 1.0), aN, u.normal_str));

  // Color palette: use BOTH field value AND warp vectors for spatial variation.
  // Field value selects the base brightness band.
  // Warp vectors (q, r from domain warping) add hue variation across the screen,
  // so you get multiple colors visible simultaneously, not a monotone field.
  let fn_ = smoothstep(-0.6, 0.8, field);
  var base = mix(u.color_shadow.rgb, u.color_mid.rgb, smoothstep(0.0, 0.25, fn_));
  base = mix(base, u.color_bright.rgb, smoothstep(0.2, 0.5, fn_));
  base = mix(base, u.color_hot.rgb, smoothstep(0.45, 0.85, fn_));

  // Warp vectors create cross-screen hue shifts:
  // q.x pushes toward bright, q.y pushes toward mid, length(r) pushes toward hot
  let q_len = length(g_warp_grad) * 0.12;
  base = mix(base, u.color_bright.rgb, clamp(q_len, 0.0, 0.4));
  // Use spatial position + time for additional color breakup
  let color_noise = snoise(p * 1.5 + vec2f(sin(t * 0.07), cos(t * 0.09)) * 3.0);
  base = mix(base, mix(u.color_mid.rgb, u.color_hot.rgb, fn_), clamp(color_noise * 0.25 + 0.1, 0.0, 0.3));

  var col = base;

  // Lighting
  let V = vec3f(0.0, 0.0, 1.0);
  let L1 = normalize(vec3f(0.4, 0.5, 0.9));
  let L2 = normalize(vec3f(-0.6, -0.3, 0.7));
  let lit = max(dot(N, L1), 0.0) * 0.7 + max(dot(N, L2), 0.0) * 0.3;
  let diffuse = base * lit;

  let H1 = normalize(L1 + V);
  let blinn = pow(max(dot(N, H1), 0.0), u.spec_power);
  var aniso = 0.0;
  let gl2 = dot(fold_grad, fold_grad);
  if (gl2 > 0.0001) {
    let tg = vec2f(-fold_grad.y, fold_grad.x) / sqrt(gl2);
    let TdH = dot(normalize(vec3f(tg, 0.0)), H1);
    aniso = pow(sqrt(max(1.0 - TdH * TdH, 0.0)), u.spec_power);
  }
  let spec = mix(blinn, aniso, smoothstep(0.3, 0.7, u.spec_str));

  let NdV = max(dot(N, V), 0.0);
  let fres = u.fresnel_f0 + (1.0 - u.fresnel_f0) * pow(1.0 - NdV, 5.0);
  let fr_mix = mix(1.0, fres, step(0.001, u.fresnel_f0));

  col = mix(col, diffuse, u.diffuse_str);
  col += u.color_hot.rgb * spec * u.spec_str * fr_mix * 0.8;

  // Environment reflection
  let refl_uv = N.xy * 0.5 + 0.5;
  col += mix(u.color_shadow.rgb, u.color_bright.rgb, refl_uv.y) * fres * u.fresnel_f0 * 0.3;

  // Additive orb color
  col = mix(col, orbs.color, u.orb_color_mode);

  // Edge glow (from noise field edges)
  let ink = smoothstep(-0.2, 0.1, field) * envelope;
  let edge_raw = ink * (1.0 - ink) * 4.0;
  col += u.color_bright.rgb * smoothstep(0.05, 0.5, edge_raw) * 0.5 * u.edge_glow_str;
  col += u.color_hot.rgb * smoothstep(0.6, 1.0, edge_raw) * 0.4 * u.edge_glow_str;

  // Crack edge glow: bright lines at fracture boundaries (integrated, not overlay)
  let crack_glow = smoothstep(0.06, 0.0, crack_edge) * u.voronoi_str;
  col += u.color_hot.rgb * crack_glow * 0.6;

  // Wave crest highlights
  let wave_val = wave_field(p, t);
  let wave_crest = smoothstep(0.3, 0.7, wave_val) * u.wave_str;
  col += u.color_bright.rgb * wave_crest * 0.25;

  // Burn frontier glow
  col += u.color_hot.rgb * burn_edge * burn_gate * 0.8;
  col += u.color_bright.rgb * burn_edge * burn_gate * 0.4;

  // Aurora curtain glow: additive bright threads
  col += u.color_bright.rgb * curtain_val * 0.5;
  col += u.color_hot.rgb * curtain_val * curtain_val * 0.3;

  // Vignette
  let vig = length(p * vec2f(0.85, 1.0));
  col *= 1.0 - smoothstep(0.3, 1.2, vig) * u.vignette_str;

  // Tone map (ACES)
  col = clamp(col, vec3f(0.0), vec3f(4.0));
  col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

  // Chromatic aberration: radial RGB split. R shifts warm toward edges,
  // B shifts cool. When chroma_str=0, multiplier is (1,1,1) = no-op.
  let chroma_d = length(p) * u.chroma_str;
  col *= vec3f(1.0 + chroma_d * 0.25, 1.0, 1.0 - chroma_d * 0.2);

  // Grain
  let grain = fract(sin(dot(frag_coord.xy + fract(u.time * 7.13) * 100.0, vec2f(12.9898, 78.233))) * 43758.5453) - 0.5;
  col += grain * u.grain_str;

  // Hue shift
  col = hue_rotate(col, u.hue_shift);

  return vec4f(clamp(col, vec3f(0.0), vec3f(1.0)), 1.0);
}
`;
