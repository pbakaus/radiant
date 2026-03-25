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
  _pad1: f32,
  _pad2: f32,
  _pad3: f32,

  color_shadow: vec4f,
  color_mid: vec4f,
  color_bright: vec4f,
  color_hot: vec4f,
};

@group(0) @binding(0) var<uniform> u: Uniforms;

// ─── Vertex ───
struct VSOut {
  @builtin(position) pos: vec4f,
};

@vertex
fn vs(@builtin(vertex_index) vi: u32) -> VSOut {
  // Fullscreen triangle
  var p = array<vec2f, 3>(vec2f(-1, -1), vec2f(3, -1), vec2f(-1, 3));
  var out: VSOut;
  out.pos = vec4f(p[vi], 0, 1);
  return out;
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
  for (var i = 0; i < 3; i++) {
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
    let glow = exp(-d * d / rr) * u.orb_intensity;
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

  // Noise field + domain warp (always runs; 0 octaves = loop exits immediately)
  let field = warped_field(p * u.warp_scale, t);

  // Orbs (always runs; 0 count = loop exits immediately)
  let orbs = compute_orbs(p, t);

  // Combine: envelope fades smoothly with orb_color_mode
  let envelope = mix(
    mix(1.0, clamp(orbs.field, 0.0, 1.0), 1.0 - u.orb_color_mode),
    1.0,
    u.orb_color_mode
  );
  var height = field * envelope + orbs.field * (1.0 - u.orb_color_mode) * 0.08;

  // Fabric fold (always computed; fold_str=0 means mix weight is 0)
  let fold = fabric_fold(p, t);
  height = mix(height, fold.x, u.fold_str);
  let fold_grad = fold.yz * u.fold_str;

  // Normal (always computed; normal_str=0 means N stays (0,0,1))
  let grad = g_warp_grad * 0.3 + fold_grad * 1.8;
  let aN = normalize(vec3f(-grad, 1.0));
  let N = normalize(mix(vec3f(0.0, 0.0, 1.0), aN, u.normal_str));

  // Color palette
  let fn_ = smoothstep(-0.5, 1.2, field);
  var base = mix(u.color_shadow.rgb, u.color_mid.rgb, smoothstep(0.0, 0.35, fn_));
  base = mix(base, u.color_bright.rgb, smoothstep(0.3, 0.65, fn_));
  base = mix(base, u.color_hot.rgb, smoothstep(0.6, 0.95, fn_));

  var col = base;

  // Lighting (always computed; diffuse_str=0 and spec_str=0 means no visible effect)
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

  // Environment reflection (scales with fresnel, so 0 when fresnel_f0=0)
  let refl_uv = N.xy * 0.5 + 0.5;
  col += mix(u.color_shadow.rgb, u.color_bright.rgb, refl_uv.y) * fres * u.fresnel_f0 * 0.3;

  // Additive orb color (scales with orb_color_mode, so 0 when mode=0)
  col = mix(col, orbs.color, u.orb_color_mode);

  // Edge glow (scales with edge_glow_str, so 0 when str=0)
  let ink = smoothstep(-0.2, 0.1, field) * envelope;
  let edge_raw = ink * (1.0 - ink) * 4.0;
  col += u.color_bright.rgb * smoothstep(0.05, 0.5, edge_raw) * 0.5 * u.edge_glow_str;
  col += u.color_hot.rgb * smoothstep(0.6, 1.0, edge_raw) * 0.4 * u.edge_glow_str;

  // Vignette
  let vig = length(p * vec2f(0.85, 1.0));
  col *= 1.0 - smoothstep(0.3, 1.2, vig) * u.vignette_str;

  // Tone map (ACES)
  col = clamp(col, vec3f(0.0), vec3f(4.0));
  col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

  // Grain (grain_str=0 means no visible effect)
  let grain = fract(sin(dot(frag_coord.xy + fract(u.time * 7.13) * 100.0, vec2f(12.9898, 78.233))) * 43758.5453) - 0.5;
  col += grain * u.grain_str;

  // Hue shift (always applied, 0 = identity rotation)
  col = hue_rotate(col, u.hue_shift);

  return vec4f(clamp(col, vec3f(0.0), vec3f(1.0)), 1.0);
}
`;
