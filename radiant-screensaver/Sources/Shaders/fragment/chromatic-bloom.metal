#include "../Common.metal"

// ─── Chromatic Bloom: Luminous color orbs on black ───
// Ported from static/chromatic-bloom.html

// Default parameter values
constant float CB_DRIFT_SPEED = 0.5;
constant float CB_GRAIN = 0.5;
constant float CB_PI = 3.14159265359;

// ── Hash for noise ──
static float cb_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float cb_hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

// ── Smooth value noise ──
static float cb_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = cb_hash(i);
    float b = cb_hash(i + float2(1.0, 0.0));
    float c = cb_hash(i + float2(0.0, 1.0));
    float d = cb_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Gaussian orb ──
static float3 cb_orb(float2 uv, float2 center, float3 color, float radius, float intensity) {
    float d = length(uv - center);
    float k = 1.0 / (radius * radius);
    float glow = exp(-d * d * k) * intensity;
    return color * glow;
}

fragment float4 fs_chromatic_bloom(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float aspect = u.resolution.x / u.resolution.y;
    float t = u.time * CB_DRIFT_SPEED;

    // ── Pure black background ──
    float3 col = float3(0.0);

    // ── Primary orb colors ──
    float3 cobalt    = float3(0.03, 0.10, 1.00);
    float3 orange    = float3(1.00, 0.42, 0.03);
    float3 whiteBlue = float3(0.85, 0.93, 1.00);
    float3 amber     = float3(1.00, 0.70, 0.08);
    float3 teal      = float3(0.03, 0.65, 0.65);

    // Noise perturbation for organic drift
    float n1  = cb_noise(float2(t * 0.37, 1.0))  * 2.0 - 1.0;
    float n2  = cb_noise(float2(t * 0.41, 2.3))  * 2.0 - 1.0;
    float n3  = cb_noise(float2(t * 0.33, 3.7))  * 2.0 - 1.0;
    float n4  = cb_noise(float2(t * 0.29, 5.1))  * 2.0 - 1.0;
    float n5  = cb_noise(float2(t * 0.43, 6.9))  * 2.0 - 1.0;
    float n6  = cb_noise(float2(t * 0.31, 8.2))  * 2.0 - 1.0;
    float n7  = cb_noise(float2(t * 0.39, 9.5))  * 2.0 - 1.0;
    float n8  = cb_noise(float2(t * 0.27, 10.8)) * 2.0 - 1.0;
    float n9  = cb_noise(float2(t * 0.35, 12.1)) * 2.0 - 1.0;
    float n10 = cb_noise(float2(t * 0.45, 13.4)) * 2.0 - 1.0;

    // Primary orb 1: Deep cobalt blue
    float2 p1 = float2(
        cos(t * 0.23 + 0.0) * 0.55 + n1 * 0.08,
        sin(t * 0.17 + 0.0) * 0.35 + n2 * 0.06
    );
    col += cb_orb(uv, p1, cobalt, 0.30, 1.6);

    // Primary orb 2: Warm burnt orange
    float2 p2 = float2(
        cos(t * 0.19 + 2.1) * 0.50 + n3 * 0.09,
        sin(t * 0.25 + 1.4) * 0.38 + n4 * 0.07
    );
    col += cb_orb(uv, p2, orange, 0.28, 1.5);

    // Primary orb 3: Cool white-blue
    float2 p3 = float2(
        cos(t * 0.15 + 4.2) * 0.42 + n5 * 0.07,
        sin(t * 0.21 + 3.0) * 0.45 + n6 * 0.06
    );
    col += cb_orb(uv, p3, whiteBlue, 0.26, 1.2);

    // Primary orb 4: Amber gold
    float2 p4 = float2(
        sin(t * 0.17 + 1.0) * cos(t * 0.11 + 0.5) * 0.55 + n7 * 0.08,
        sin(t * 0.13 + 2.5) * 0.35 + n8 * 0.06
    );
    col += cb_orb(uv, p4, amber, 0.27, 1.3);

    // Primary orb 5: Subtle teal
    float2 p5 = float2(
        cos(t * 0.13 + 5.5) * 0.48 + n9 * 0.07,
        sin(t * 0.19 + 4.8) * 0.30 + n10 * 0.08
    );
    col += cb_orb(uv, p5, teal, 0.32, 1.2);

    // ── Secondary smaller dimmer orbs ──
    float3 dimCobalt = float3(0.08, 0.15, 0.50);
    float3 dimOrange = float3(0.60, 0.28, 0.08);
    float3 dimWhite  = float3(0.50, 0.55, 0.70);
    float3 dimAmber  = float3(0.65, 0.42, 0.15);
    float3 dimTeal   = float3(0.08, 0.35, 0.35);
    float3 dimViolet = float3(0.25, 0.15, 0.50);
    float3 dimRose   = float3(0.55, 0.25, 0.30);

    float sn1  = cb_noise(float2(t * 0.51, 20.0)) * 2.0 - 1.0;
    float sn2  = cb_noise(float2(t * 0.47, 21.3)) * 2.0 - 1.0;
    float sn3  = cb_noise(float2(t * 0.53, 22.7)) * 2.0 - 1.0;
    float sn4  = cb_noise(float2(t * 0.43, 24.1)) * 2.0 - 1.0;
    float sn5  = cb_noise(float2(t * 0.49, 25.5)) * 2.0 - 1.0;
    float sn6  = cb_noise(float2(t * 0.55, 26.9)) * 2.0 - 1.0;
    float sn7  = cb_noise(float2(t * 0.41, 28.3)) * 2.0 - 1.0;
    float sn8  = cb_noise(float2(t * 0.57, 29.7)) * 2.0 - 1.0;
    float sn9  = cb_noise(float2(t * 0.39, 31.1)) * 2.0 - 1.0;
    float sn10 = cb_noise(float2(t * 0.61, 32.5)) * 2.0 - 1.0;
    float sn11 = cb_noise(float2(t * 0.37, 33.9)) * 2.0 - 1.0;
    float sn12 = cb_noise(float2(t * 0.59, 35.3)) * 2.0 - 1.0;
    float sn13 = cb_noise(float2(t * 0.45, 36.7)) * 2.0 - 1.0;
    float sn14 = cb_noise(float2(t * 0.63, 38.1)) * 2.0 - 1.0;

    float2 s1 = float2(
        cos(t * 0.31 + 0.7) * 0.45 + sn1 * 0.08,
        sin(t * 0.27 + 1.2) * 0.35 + sn2 * 0.07
    );
    col += cb_orb(uv, s1, dimCobalt, 0.18, 0.20);

    float2 s2 = float2(
        cos(t * 0.25 + 3.1) * 0.60 + sn3 * 0.09,
        sin(t * 0.33 + 2.5) * 0.42 + sn4 * 0.06
    );
    col += cb_orb(uv, s2, dimOrange, 0.16, 0.18);

    float2 s3 = float2(
        cos(t * 0.29 + 5.3) * 0.55 + sn5 * 0.07,
        sin(t * 0.23 + 4.1) * 0.45 + sn6 * 0.08
    );
    col += cb_orb(uv, s3, dimWhite, 0.14, 0.15);

    float2 s4 = float2(
        sin(t * 0.21 + 1.8) * 0.58 + sn7 * 0.06,
        cos(t * 0.29 + 0.3) * 0.40 + sn8 * 0.07
    );
    col += cb_orb(uv, s4, dimAmber, 0.17, 0.18);

    float2 s5 = float2(
        cos(t * 0.35 + 2.9) * 0.52 + sn9 * 0.08,
        sin(t * 0.19 + 5.7) * 0.48 + sn10 * 0.06
    );
    col += cb_orb(uv, s5, dimTeal, 0.15, 0.15);

    float2 s6 = float2(
        cos(t * 0.17 + 4.5) * 0.62 + sn11 * 0.07,
        sin(t * 0.31 + 3.3) * 0.38 + sn12 * 0.09
    );
    col += cb_orb(uv, s6, dimViolet, 0.16, 0.15);

    float2 s7 = float2(
        sin(t * 0.27 + 6.1) * cos(t * 0.15 + 0.8) * 0.50 + sn13 * 0.06,
        cos(t * 0.23 + 5.0) * 0.42 + sn14 * 0.08
    );
    col += cb_orb(uv, s7, dimRose, 0.14, 0.12);

    // ── Vignette ──
    float vd = length(uv * float2(1.1, 1.0));
    float vignette = 1.0 - smoothstep(0.5, 1.1, vd);
    col *= vignette;

    col = max(col, float3(0.0));

    // Soft knee tone mapping
    col = mix(col, sqrt(col), smoothstep(0.6, 1.5, col));

    // No mouse interaction in screensaver

    // ── Film grain ──
    float grain = fract(sin(dot(in.pos.xy + fract(u.time) * 100.0, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    col += grain * 0.3 * CB_GRAIN;

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(col, 1.0);
}
