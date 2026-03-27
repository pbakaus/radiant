#include "../Common.metal"

// ─── Silk Cascade: Multi-layered translucent silk fabric ───
// Ported from static/silk-cascade.html

// Default parameter values
constant float SC_FLOW_SPEED = 0.4;
constant float SC_SHEEN_INTENSITY = 1.0;
constant float SC_PI = 3.14159265359;

static float sc_hash12(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float sc_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sc_hash12(i);
    float b = sc_hash12(i + float2(1.0, 0.0));
    float c = sc_hash12(i + float2(0.0, 1.0));
    float d = sc_hash12(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float sc_fbm3(float2 p) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.8, -0.6), float2(0.6, 0.8));
    for (int i = 0; i < 3; i++) {
        v += a * sc_vnoise(p);
        p = rot * p * 2.0;
        a *= 0.5;
    }
    return v;
}

static float sc_fbm2(float2 p) {
    float v = 0.5 * sc_vnoise(p);
    float2x2 rot = float2x2(float2(0.8, -0.6), float2(0.6, 0.8));
    p = rot * p * 2.0;
    v += 0.25 * sc_vnoise(p);
    return v;
}

static float2 sc_domainWarp(float2 p, float t, float scale, float seed) {
    return float2(
        sc_fbm3(p * scale + float2(1.7 + seed, 9.2) + t * 0.15),
        sc_fbm3(p * scale + float2(8.3, 2.8 + seed) - t * 0.12)
    );
}

static float2 sc_domainWarpLite(float2 p, float t, float scale, float seed) {
    return float2(
        sc_fbm2(p * scale + float2(1.7 + seed, 9.2) + t * 0.15),
        sc_fbm2(p * scale + float2(8.3, 2.8 + seed) - t * 0.12)
    );
}

// Per-layer fold: returns float3(height, gradient.xy)
static float3 sc_fabricFold(float2 p, float t, float seed, float freq, float flow) {
    float ts = t * flow;
    float2 warp = sc_domainWarp(p + seed * 3.7, ts, 1.2, seed);
    float2 wp = p + warp * 0.55;
    float h = 0.0;
    float2 g = float2(0.0);

    float f1x = freq * 0.7, f1y = freq * 0.4;
    float ph1 = wp.x * f1x + wp.y * f1y + ts * 0.3 + seed * 2.1;
    h += sin(ph1) * 0.35; g += cos(ph1) * 0.35 * float2(f1x, f1y);

    float f2x = -freq * 0.3, f2y = freq * 0.9;
    float ph2 = wp.x * f2x + wp.y * f2y + ts * 0.25 + seed * 1.3;
    h += sin(ph2) * 0.25; g += cos(ph2) * 0.25 * float2(f2x, f2y);

    float f3 = freq * 0.6;
    float ph3 = (wp.x + wp.y) * f3 + ts * 0.2 + seed * 4.5;
    h += sin(ph3) * 0.18; g += cos(ph3) * 0.18 * float2(f3, f3);

    float f4x = freq * 1.8, f4y = freq * 1.2;
    float ph4 = wp.x * f4x + wp.y * f4y - ts * 0.35 + seed * 0.7;
    h += sin(ph4) * 0.08; g += cos(ph4) * 0.08 * float2(f4x, f4y);

    h += sc_vnoise(wp * freq * 0.9 + seed * 10.0 + ts * 0.04) * 0.12 - 0.06;
    return float3(h, g);
}

static float3 sc_fabricFoldLite(float2 p, float t, float seed, float freq, float flow) {
    float ts = t * flow;
    float2 warp = sc_domainWarpLite(p + seed * 3.7, ts, 1.2, seed);
    float2 wp = p + warp * 0.55;
    float h = 0.0;
    float2 g = float2(0.0);

    float f1x = freq * 0.7, f1y = freq * 0.4;
    float ph1 = wp.x * f1x + wp.y * f1y + ts * 0.3 + seed * 2.1;
    h += sin(ph1) * 0.35; g += cos(ph1) * 0.35 * float2(f1x, f1y);

    float f2x = -freq * 0.3, f2y = freq * 0.9;
    float ph2 = wp.x * f2x + wp.y * f2y + ts * 0.25 + seed * 1.3;
    h += sin(ph2) * 0.25; g += cos(ph2) * 0.25 * float2(f2x, f2y);

    float f3 = freq * 0.6;
    float ph3 = (wp.x + wp.y) * f3 + ts * 0.2 + seed * 4.5;
    h += sin(ph3) * 0.18; g += cos(ph3) * 0.18 * float2(f3, f3);

    float f4x = freq * 1.8, f4y = freq * 1.2;
    float ph4 = wp.x * f4x + wp.y * f4y - ts * 0.35 + seed * 0.7;
    h += sin(ph4) * 0.08; g += cos(ph4) * 0.08 * float2(f4x, f4y);

    return float3(h, g);
}

// Kajiya-Kay anisotropic specular
static float sc_kajiyaSpec(float2 grad, float3 L, float3 V, float shine) {
    float gl2 = dot(grad, grad);
    if (gl2 < 0.0001) return 0.0;
    float2 tg = float2(-grad.y, grad.x) / sqrt(gl2);
    float3 T = normalize(float3(tg, 0.0));
    float3 H = normalize(L + V);
    float TdH = dot(T, H);
    return pow(sqrt(max(1.0 - TdH * TdH, 0.0)), shine);
}

// Shade one fabric layer
static float4 sc_shadeLayer(
    float2 p, float t,
    float seed, float freq, float flow,
    float3 darkCol, float3 midCol, float3 brightCol, float3 specCol,
    float opacity, float shine,
    float3 L1, float3 L2, float3 V,
    float sheenMul
) {
    float3 fold = opacity < 0.35 ? sc_fabricFoldLite(p, t, seed, freq, flow) : sc_fabricFold(p, t, seed, freq, flow);
    float h = fold.x;
    float2 grad = fold.yz;
    float3 N = normalize(float3(-grad * 1.8, 1.0));

    float NdL1 = max(dot(N, L1), 0.0);
    float NdL2 = max(dot(N, L2), 0.0);
    float lit = NdL1 * 0.75 + NdL2 * 0.12;

    float depth = smoothstep(-0.8, 0.4, h);

    float shade = lit * depth;
    float midBlend = smoothstep(0.0, 0.35, shade);
    float brightBlend = smoothstep(0.25, 0.7, shade);
    float3 fabric = mix(darkCol, midCol, midBlend);
    fabric = mix(fabric, brightCol, brightBlend * 0.5);

    float sp = sc_kajiyaSpec(grad, L1, V, shine) * 0.9;
    sp += sc_kajiyaSpec(grad, L2, V, shine * 0.6) * 0.15;
    sp *= sheenMul;
    float specPow = sp * sp * sp;
    fabric += specCol * specPow * 0.9;

    float trans = smoothstep(0.3, 0.9, depth) * lit * 0.08;
    fabric += float3(0.45, 0.28, 0.15) * trans;

    float sparkle = sc_hash12(floor(p * 500.0 + t * 0.7));
    sparkle = step(0.9992, sparkle) * specPow * 20.0 * sheenMul;
    fabric += specCol * min(sparkle, 2.0);

    float alpha = opacity * (0.65 + depth * 0.35);
    return float4(fabric, alpha);
}

fragment float4 fs_silk_cascade(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float t = u.time * SC_FLOW_SPEED;

    // Primary light — auto-animated (no mouse in screensaver)
    float3 L1 = normalize(float3(
        0.4 + sin(t * 0.07) * 0.3,
        0.9 + cos(t * 0.09) * 0.15,
        0.8
    ));
    float3 L2 = normalize(float3(
        -0.7 + cos(t * 0.06) * 0.2,
        -0.3 + sin(t * 0.08) * 0.15,
        0.6
    ));
    float3 V = float3(0.0, 0.0, 1.0);

    // Background
    float bgD = length(p);
    float3 bg = mix(
        float3(0.055, 0.03, 0.075),
        float3(0.012, 0.006, 0.02),
        smoothstep(0.0, 1.0, bgD)
    );
    bg += float3(0.025, 0.012, 0.035) * exp(-bgD * bgD * 2.0);

    // Layer 1: Deep — warm gold/champagne
    float4 ly1 = sc_shadeLayer(
        p * 0.8 + float2(0.15, t * 0.015), t,
        0.0, 2.0, 0.5,
        float3(0.10, 0.06, 0.02),
        float3(0.50, 0.38, 0.15),
        float3(0.80, 0.65, 0.32),
        float3(1.0, 0.92, 0.65),
        0.30, 26.0,
        L1, L2, V,
        SC_SHEEN_INTENSITY * 0.7
    );

    // Layer 2: Middle — rose pink
    float4 ly2 = sc_shadeLayer(
        p * 1.0 + float2(t * 0.012, -0.1), t,
        1.0, 3.2, 0.75,
        float3(0.08, 0.03, 0.04),
        float3(0.42, 0.18, 0.22),
        float3(0.72, 0.38, 0.42),
        float3(1.0, 0.82, 0.86),
        0.38, 40.0,
        L1, L2, V,
        SC_SHEEN_INTENSITY * 0.9
    );

    // Layer 3: Front — soft lavender
    float4 ly3 = sc_shadeLayer(
        p * 1.2 + float2(-t * 0.008, t * 0.02), t,
        2.0, 4.5, 1.0,
        float3(0.06, 0.04, 0.10),
        float3(0.30, 0.22, 0.45),
        float3(0.58, 0.48, 0.72),
        float3(1.0, 0.90, 0.97),
        0.50, 55.0,
        L1, L2, V,
        SC_SHEEN_INTENSITY
    );

    // Composite back-to-front
    float3 col = bg;
    col = mix(col, ly1.rgb, ly1.a);
    col += float3(0.35, 0.18, 0.08) * ly1.a * ly2.a * 0.08;
    col = mix(col, ly2.rgb, ly2.a);
    col += float3(0.30, 0.15, 0.25) * ly2.a * ly3.a * 0.06;
    col += float3(0.40, 0.25, 0.12) * ly1.a * ly2.a * ly3.a * 0.04;
    col = mix(col, ly3.rgb, ly3.a);

    // Subtle backlight glow
    float cov = (ly1.a + ly2.a + ly3.a) * 0.333;
    col += float3(0.35, 0.20, 0.12) * cov * 0.04;

    // Vignette
    float vig = 1.0 - smoothstep(0.25, 1.15, length(p * float2(0.85, 1.0)));
    col *= 0.6 + 0.4 * vig;

    // Saturation boost
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(lum), col, 1.35);

    // Tone mapping (ACES)
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

    // Gamma
    col = pow(max(col, 0.0), float3(0.4545));

    // Film grain
    float grain = sc_hash12(in.pos.xy + fract(u.time * 7.13) * 100.0);
    col += (grain - 0.5) * 0.015;

    // Hue shift
    col = hue_rotate(col, u.hue_shift);

    return float4(clamp(col, 0.0, 1.0), 1.0);
}
