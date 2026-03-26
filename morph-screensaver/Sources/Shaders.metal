#include <metal_stdlib>
using namespace metal;

// ─── Uniform buffer: 64 floats = 256 bytes ───
// Layout matches the WGSL struct exactly. Unused fields read 0.
struct Uniforms {
    float time;            // 0
    float zoom;            // 1
    float hue_shift;       // 2
    float fbm_octaves;     // 3

    float2 res;            // 4-5
    float2 mouse;          // 6-7

    float2 zoom_center;    // 8-9
    float fbm_decay;       // 10
    float fbm_freq_mul;    // 11

    float warp_scale;      // 12
    float warp1_str;       // 13
    float warp2_str;       // 14
    float orb_count;       // 15

    float orb_radius;      // 16
    float orb_intensity;   // 17
    float orb_color_mode;  // 18
    float fold_str;        // 19

    float fold_freq;       // 20
    float normal_str;      // 21
    float diffuse_str;     // 22
    float spec_str;        // 23

    float spec_power;      // 24
    float fresnel_f0;      // 25
    float edge_glow_str;   // 26
    float vignette_str;    // 27

    float grain_str;       // 28
    float ridge_str;       // 29
    float voronoi_str;     // 30
    float voronoi_scale;   // 31

    float4 color_shadow;   // 32-35
    float4 color_mid;      // 36-39
    float4 color_bright;   // 40-43
    float4 color_hot;      // 44-47

    float wave_str;        // 48
    float wave_freq;       // 49
    float orb_sharpness;   // 50
    float moire_str;       // 51

    float burn_str;        // 52
    float burn_speed;      // 53
    float spiral_str;      // 54
    float spiral_arms;     // 55

    float kaleido_str;     // 56
    float kaleido_seg;     // 57
    float chroma_str;      // 58
    float chladni_str;     // 59

    float chladni_mode;    // 60
    float colour_var_str;  // 61
    float _pad2;           // 62
    float _pad3;           // 63
};

// ─── Vertex output ───
struct VSOut {
    float4 pos [[position]];
};

// ─── Vertex shader: full-screen triangle ───
vertex VSOut vs(uint vi [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VSOut out;
    out.pos = float4(positions[vi], 0.0, 1.0);
    return out;
}

// ─── Hash (for Voronoi) ───
static float2 hash2(float2 p) {
    return float2(
        fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, float2(269.5, 183.3))) * 43758.5453)
    );
}

// ─── Simplex 2D noise ───
static float3 mod289_3(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float2 mod289_2(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float3 permute(float3 x) { return mod289_3((x * 34.0 + 1.0) * x); }

static float snoise(float2 v) {
    const float4 C = float4(0.211324865405187, 0.366025403784439,
                            -0.577350269189626, 0.024390243902439);
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1;
    if (x0.x > x0.y) { i1 = float2(1.0, 0.0); } else { i1 = float2(0.0, 1.0); }
    float4 x12 = x0.xyxy + C.xxzz;
    x12 = float4(x12.xy - i1, x12.zw);
    float2 ii = mod289_2(i);
    float3 p = permute(permute(ii.y + float3(0.0, i1.y, 1.0)) + ii.x + float3(0.0, i1.x, 1.0));
    float3 m = max(float3(0.5) - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), float3(0.0));
    m = m * m; m = m * m;
    float3 x_ = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x_) - 0.5;
    float3 ox = floor(x_ + 0.5);
    float3 a0 = x_ - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.y = a0.y * x12.x + h.y * x12.y;
    g.z = a0.z * x12.z + h.z * x12.w;
    return 130.0 * dot(m, g);
}

// ─── FBM ───
static float fbm(float2 p_in, float t, constant Uniforms& u) {
    float2 p = p_in;
    float val = 0.0;
    float amp = 0.5;
    const float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 5; i++) {
        if (float(i) >= u.fbm_octaves) { break; }
        val += amp * snoise(p + float2(sin(t * 0.13), cos(t * 0.17)) * 2.0);
        p = rot * p * u.fbm_freq_mul;
        amp *= u.fbm_decay;
    }
    return val;
}

static float fbm2(float2 p_in, float t, constant Uniforms& u) {
    float2 p = p_in;
    const float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    float v = 0.5 * snoise(p + float2(sin(t * 0.13), cos(t * 0.17)) * 2.0);
    p = rot * p * 2.0;
    return v + 0.25 * snoise(p + float2(sin(t * 0.13), cos(t * 0.17)) * 2.0);
}

// ─── Domain-warped field ───
static float warped_field(float2 p, float t, constant Uniforms& u, thread float2& g_warp_grad) {
    float2 q = float2(fbm(p, t, u), fbm(p + float2(5.2, 1.3), t, u));
    float2 wp1 = p + u.warp1_str * q;
    float2 r = float2(fbm(wp1 + float2(1.7, 9.2), t * 1.1, u), fbm(wp1 + float2(8.3, 2.8), t * 1.1, u));
    float f = fbm(p + u.warp2_str * r, t * 0.8, u);
    g_warp_grad = u.warp1_str * q + u.warp2_str * r;
    return f;
}

// ─── Ridged noise ───
static float apply_ridge(float field, constant Uniforms& u) {
    float ridged = 1.0 - abs(field * 2.0 - 0.3);
    return mix(field, ridged, u.ridge_str);
}

// ─── Voronoi cracks ───
struct VoronoiResult { float min_dist; float edge_dist; };

static VoronoiResult voronoi_cracks(float2 p_in, float t, constant Uniforms& u) {
    float2 p = p_in * u.voronoi_scale;
    float2 cell = floor(p);
    float2 local = fract(p);

    float min_d = 8.0;
    float second_d = 8.0;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(float(x), float(y));
            float2 offset = cell + neighbor;
            float2 pt = hash2(offset);
            pt += 0.3 * float2(
                sin(t * 0.09 + pt.x * 20.0),
                cos(t * 0.07 + pt.y * 20.0)
            );
            float2 diff = neighbor + pt - local;
            float d = dot(diff, diff);
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
    float edge = second_d - min_d;

    VoronoiResult result;
    result.min_dist = min_d;
    result.edge_dist = edge;
    return result;
}

// ─── Wave interference ───
static float wave_field(float2 p, float t, constant Uniforms& u) {
    float h = 0.0;
    float freq = u.wave_freq;

    h += sin(p.x * freq * 1.0 + p.y * freq * 0.3 + t * 0.7) * 0.35;
    h += sin(p.x * freq * -0.4 + p.y * freq * 0.9 + t * 0.5 + 1.3) * 0.25;
    h += sin(p.x * freq * 0.6 + p.y * freq * -0.7 + t * 0.9 + 2.7) * 0.20;
    h += sin(p.x * freq * 1.3 + p.y * freq * 0.5 + t * 0.3 + 4.1) * 0.15;

    return h;
}

// ─── Orbs ───
static float3 orb_color(int i) {
    switch (i) {
        case 0: return float3(0.03, 0.10, 1.00);
        case 1: return float3(1.00, 0.42, 0.03);
        case 2: return float3(0.85, 0.93, 1.00);
        case 3: return float3(1.00, 0.70, 0.08);
        case 4: return float3(0.03, 0.65, 0.65);
        case 5: return float3(0.25, 0.15, 0.50);
        default: return float3(0.55, 0.25, 0.30);
    }
}

struct OrbResult { float field; float3 color; };

static OrbResult compute_orbs(float2 p, float t, constant Uniforms& u) {
    OrbResult result;
    result.field = 0.0;
    result.color = float3(0.0);
    int count = int(u.orb_count + 0.5);
    float rr = max(u.orb_radius * u.orb_radius, 0.001f);
    for (int i = 0; i < 7; i++) {
        if (i >= count) { break; }
        float fi = float(i);
        float2 center = float2(
            sin(t * (0.17 + fi * 0.02) + fi * 2.1) * 0.5 + cos(t * (0.13 + fi * 0.015) + fi * 1.3) * 0.25,
            cos(t * (0.15 + fi * 0.018) + fi * 1.7) * 0.4 + sin(t * (0.11 + fi * 0.022) + fi * 2.5) * 0.2
        );
        float d = length(p - center);
        float gaussian = exp(-d * d / rr);
        float metaball = min(rr / max(d * d, 0.0005f), 4.0f);
        float glow = mix(gaussian, metaball, u.orb_sharpness) * u.orb_intensity;
        result.field += glow;
        result.color += orb_color(i) * glow;
    }
    return result;
}

// ─── Fabric fold ───
static float3 fabric_fold(float2 p, float t, constant Uniforms& u) {
    float ts = t * 0.75;
    float2 warp = float2(
        fbm2(p * 1.2 + float2(1.7, 9.2) + float2(sin(ts * 0.11), cos(ts * 0.14)) * 1.5, ts, u),
        fbm2(p * 1.2 + float2(8.3, 2.8) + float2(cos(ts * 0.09), sin(ts * 0.13)) * 1.5, ts, u)
    );
    float2 wp = p + warp * 0.55;
    float freq = u.fold_freq;
    float h = 0.0;
    float2 g = float2(0.0);

    float2 f1 = float2(freq * 0.7, freq * 0.4);
    float ph1 = wp.x * f1.x + wp.y * f1.y + ts * 0.3;
    h += sin(ph1) * 0.35; g += cos(ph1) * 0.35 * f1;

    float2 f2 = float2(-freq * 0.3, freq * 0.9);
    float ph2 = wp.x * f2.x + wp.y * f2.y + ts * 0.25 + 1.3;
    h += sin(ph2) * 0.25; g += cos(ph2) * 0.25 * f2;

    float f3 = freq * 0.6;
    float ph3 = (wp.x + wp.y) * f3 + ts * 0.2 + 4.5;
    h += sin(ph3) * 0.18; g += cos(ph3) * 0.18 * float2(f3);

    float2 f4 = float2(freq * 1.8, freq * 1.2);
    float ph4 = wp.x * f4.x + wp.y * f4.y - ts * 0.35 + 0.7;
    h += sin(ph4) * 0.08; g += cos(ph4) * 0.08 * f4;

    return float3(h, g);
}

// ─── Kaleidoscope fold ───
static float2 kaleido_fold(float2 p, constant Uniforms& u) {
    float r = length(p);
    float a = atan2(p.y, p.x);
    float seg = 3.14159265 / max(u.kaleido_seg, 2.0f);
    float seg2 = seg * 2.0;
    a = a - floor(a / seg2) * seg2;
    if (a > seg) { a = seg2 - a; }
    return float2(cos(a), sin(a)) * r;
}

// ─── Spiral field ───
static float spiral_field(float2 p, float t, constant Uniforms& u) {
    float r = length(p);
    if (r < 0.01) { return 0.0; }
    float theta = atan2(p.y, p.x);
    float spiral_theta = log(r / 0.03) / 0.18;
    float arm_spacing = 6.28318 / max(u.spiral_arms, 1.0f);
    float raw_ang = theta - spiral_theta + t * 0.3;
    float ang = raw_ang - floor(raw_ang / arm_spacing) * arm_spacing;
    if (ang > arm_spacing * 0.5) { ang -= arm_spacing; }
    float screen_d = abs(ang) * r;
    float line_w = 0.06 * smoothstep(0.08f, 0.5f, r);
    return smoothstep(line_w, 0.0f, screen_d) * smoothstep(0.85f, 0.15f, r);
}

// ─── Moire interference ───
static float moire_field(float2 p, float t) {
    float product = 1.0;
    float additive = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float2 center = float2(
            0.22 * cos(t * 0.03 * (fi + 1.0) + fi * 2.1),
            0.18 * sin(t * 0.04 * (fi + 1.0) + fi * 1.4)
        );
        float ring = sin(length(p - center) * 55.0);
        product *= ring;
        additive += ring;
    }
    return product * 0.7 + additive * 0.25 * 0.3;
}

// ─── Chladni modes ───
static float chladni_field(float2 p, float t, constant Uniforms& u) {
    constexpr float PI = 3.14159265;
    constexpr float2 modes[6] = {
        float2(1, 2), float2(2, 3), float2(3, 4),
        float2(4, 5), float2(3, 7), float2(5, 6)
    };
    float idx = clamp(u.chladni_mode, 0.0f, 4.99f);
    int i0 = int(idx);
    int i1 = min(i0 + 1, 5);
    float fr = idx - float(i0);
    float2 m0 = modes[i0]; float2 m1 = modes[i1];
    float2 sp = p * 2.5 + float2(sin(t * 0.07), cos(t * 0.09)) * 0.3;
    float c0 = cos(m0.x * PI * sp.x) * cos(m0.y * PI * sp.y)
             + cos(m0.y * PI * sp.x) * cos(m0.x * PI * sp.y);
    float c1 = cos(m1.x * PI * sp.x) * cos(m1.y * PI * sp.y)
             + cos(m1.y * PI * sp.x) * cos(m1.x * PI * sp.y);
    float pattern = mix(c0, c1, fr);
    return 1.0 - smoothstep(0.0f, 0.15f, abs(pattern));
}

// ─── Hue rotation ───
static float3 hue_rotate(float3 c, float a) {
    float ca = cos(a); float sa = sin(a);
    float3 k = float3(0.57735);
    return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

// ─── Fragment shader ───
fragment float4 fs(VSOut in [[stage_in]],
                   constant Uniforms& u [[buffer(0)]]) {
    float2 raw_uv = in.pos.xy / u.res;
    float2 uv = (raw_uv - u.zoom_center) / u.zoom + u.zoom_center;
    float2 p = (uv - 0.5) * float2(u.res.x / u.res.y, 1.0);
    float t = u.time;

    // g_warp_grad: local mutable, passed by reference
    float2 g_warp_grad = float2(0.0);

    // Kaleidoscope: binary switch
    float2 kp = (u.kaleido_str > 0.4) ? kaleido_fold(p, u) : p;
    float2 wp = kp * u.warp_scale;
    float field = warped_field(wp, t, u, g_warp_grad);

    // Ridged noise
    field = apply_ridge(field, u);

    // Wave interference
    field += wave_field(p, t, u) * u.wave_str;

    // Chladni modes
    float chladni_gate = smoothstep(0.3f, 0.6f, u.chladni_str);
    field += chladni_field(p, t, u) * chladni_gate;

    // Spiral arms
    float spiral_gate = smoothstep(0.3f, 0.6f, u.spiral_str);
    field += spiral_field(p, t, u) * spiral_gate;

    // Moire interference
    float moire_gate = smoothstep(0.3f, 0.6f, u.moire_str);
    field += moire_field(p, t) * moire_gate;

    // Burn frontier
    float burn_gate = smoothstep(0.3f, 0.6f, u.burn_str);
    float burn_phase = fract(t * u.burn_speed * 0.05);
    float burn_thresh = mix(0.85f, -0.3f, smoothstep(0.0f, 0.85f, burn_phase));
    float burn_mask = smoothstep(burn_thresh, burn_thresh - 0.12, field);
    float burn_edge = smoothstep(burn_thresh - 0.02, burn_thresh, field)
                    * smoothstep(burn_thresh + 0.08, burn_thresh, field);
    field = mix(field, field * burn_mask, burn_gate);

    // Voronoi cracks
    float2 vor_p = p + g_warp_grad * 0.15;
    VoronoiResult vor = voronoi_cracks(vor_p, t, u);
    float crack_edge = vor.edge_dist;
    float crack_cut = smoothstep(0.12f, 0.0f, crack_edge);
    field = mix(field, field * 0.3 - 0.2, crack_cut * u.voronoi_str);
    field += (vor.min_dist - 0.3) * u.voronoi_str * 0.2;

    // Orbs
    OrbResult orbs = compute_orbs(p, t, u);

    // Combine field + orbs
    float envelope = mix(
        mix(1.0f, clamp(orbs.field, 0.0f, 1.0f), 1.0 - u.orb_color_mode),
        1.0f, u.orb_color_mode
    );
    float height = field * envelope + orbs.field * (1.0 - u.orb_color_mode) * 0.08;

    // Fabric fold
    float3 fold = fabric_fold(p, t, u);
    height = mix(height, fold.x, u.fold_str);
    float2 fold_grad = fold.yz * u.fold_str;

    // Normal
    float2 grad = g_warp_grad * 0.3 + fold_grad * 1.8;
    float crack_normal = crack_cut * u.voronoi_str * 4.0;
    grad += float2(crack_normal, crack_normal * 0.7);
    float3 aN = normalize(float3(-grad, 1.0));
    float3 N = normalize(mix(float3(0.0, 0.0, 1.0), aN, u.normal_str));

    // Color palette
    float fn_ = smoothstep(-0.6f, 0.8f, field);
    float3 base = mix(u.color_shadow.rgb, u.color_mid.rgb, smoothstep(0.0f, 0.25f, fn_));
    base = mix(base, u.color_bright.rgb, smoothstep(0.2f, 0.5f, fn_));
    base = mix(base, u.color_hot.rgb, smoothstep(0.45f, 0.85f, fn_));

    // Warp vectors create cross-screen hue shifts
    float q_len = length(g_warp_grad) * 0.12;
    base = mix(base, u.color_bright.rgb, clamp(q_len, 0.0f, 0.4f));
    float color_noise = snoise(p * 1.5 + float2(sin(t * 0.07), cos(t * 0.09)) * 3.0);
    base = mix(base, mix(u.color_mid.rgb, u.color_hot.rgb, fn_), clamp(color_noise * 0.25 + 0.1, 0.0f, 0.3f));

    float3 col = base;

    // Lighting
    float3 V = float3(0.0, 0.0, 1.0);
    float3 L1 = normalize(float3(0.4, 0.5, 0.9));
    float3 L2 = normalize(float3(-0.6, -0.3, 0.7));
    float lit = max(dot(N, L1), 0.0f) * 0.7 + max(dot(N, L2), 0.0f) * 0.3;
    float3 diffuse = base * lit;

    float3 H1 = normalize(L1 + V);
    float blinn = pow(max(dot(N, H1), 0.0f), u.spec_power);
    float aniso = 0.0;
    float gl2 = dot(fold_grad, fold_grad);
    if (gl2 > 0.0001) {
        float2 tg = float2(-fold_grad.y, fold_grad.x) / sqrt(gl2);
        float TdH = dot(normalize(float3(tg, 0.0)), H1);
        aniso = pow(sqrt(max(1.0 - TdH * TdH, 0.0f)), u.spec_power);
    }
    float spec = mix(blinn, aniso, smoothstep(0.3f, 0.7f, u.spec_str));

    float NdV = max(dot(N, V), 0.0f);
    float fres = u.fresnel_f0 + (1.0 - u.fresnel_f0) * pow(1.0 - NdV, 5.0);
    float fr_mix = mix(1.0f, fres, step(0.001f, u.fresnel_f0));

    col = mix(col, diffuse, u.diffuse_str);
    col += u.color_hot.rgb * spec * u.spec_str * fr_mix * 0.8;

    // Environment reflection
    float2 refl_uv = N.xy * 0.5 + 0.5;
    col += mix(u.color_shadow.rgb, u.color_bright.rgb, refl_uv.y) * fres * u.fresnel_f0 * 0.3;

    // Additive orb color
    col = mix(col, orbs.color, u.orb_color_mode);

    // Edge glow
    float ink = smoothstep(-0.2f, 0.1f, field) * envelope;
    float edge_raw = ink * (1.0 - ink) * 4.0;
    col += u.color_bright.rgb * smoothstep(0.05f, 0.5f, edge_raw) * 0.5 * u.edge_glow_str;
    col += u.color_hot.rgb * smoothstep(0.6f, 1.0f, edge_raw) * 0.4 * u.edge_glow_str;

    // Crack edge glow
    float crack_glow = smoothstep(0.06f, 0.0f, crack_edge) * u.voronoi_str;
    col += u.color_hot.rgb * crack_glow * 0.6;

    // Wave crest highlights
    float wave_val = wave_field(p, t, u);
    float wave_crest = smoothstep(0.3f, 0.7f, wave_val) * u.wave_str;
    col += u.color_bright.rgb * wave_crest * 0.25;

    // Burn frontier glow
    col += u.color_hot.rgb * burn_edge * burn_gate * 0.8;
    col += u.color_bright.rgb * burn_edge * burn_gate * 0.4;

    // Vignette
    float vig = length(p * float2(0.85, 1.0));
    col *= 1.0 - smoothstep(0.3f, 1.2f, vig) * u.vignette_str;

    // Tone map (ACES)
    col = clamp(col, float3(0.0), float3(4.0));
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

    // Chromatic aberration
    float chroma_d = length(p) * u.chroma_str;
    col *= float3(1.0 + chroma_d * 0.25, 1.0, 1.0 - chroma_d * 0.2);

    // Grain
    float grain = fract(sin(dot(in.pos.xy + fract(u.time * 7.13) * 100.0, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    col += grain * u.grain_str;

    // Hue shift
    col = hue_rotate(col, u.hue_shift);

    return float4(clamp(col, float3(0.0), float3(1.0)), 1.0);
}
