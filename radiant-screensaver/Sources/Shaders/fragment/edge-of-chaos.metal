#include "../Common.metal"

// ─── Edge of Chaos: Reaction-diffusion inspired procedural pattern ───
// Ported from static/edge-of-chaos.html
// Original uses multi-pass Gray-Scott simulation; this single-pass version
// recreates the visual feel using domain-warped noise with the same palette.

constant float EC_WARMTH = 1.0;
constant float EC_BG_BRIGHT = 0.0;
constant float EC_PATTERN_SPEED = 1.0;

// ── Hash ──
static float ec_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth value noise ──
static float ec_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ec_hash(i);
    float b = ec_hash(i + float2(1.0, 0.0));
    float c = ec_hash(i + float2(0.0, 1.0));
    float d = ec_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM with domain rotation ──
static float ec_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.866, 0.5), float2(-0.5, 0.866));
    for (int i = 0; i < 5; i++) {
        v += a * ec_noise(p);
        p = rot * p * 2.03 + float2(47.0, 13.0);
        a *= 0.49;
    }
    return v;
}

// ── Simulate reaction-diffusion-like pattern using domain-warped noise ──
// Gray-Scott patterns have characteristic spots/stripes; we mimic this
// with multi-scale warped noise shaped through a nonlinear transfer function
static float ec_rdPattern(float2 p, float t) {
    // Domain warp: two layers of FBM displacing coordinates
    float2 q = float2(
        ec_fbm(p + float2(0.0, 0.0) + t * 0.02 * EC_PATTERN_SPEED),
        ec_fbm(p + float2(5.2, 1.3) + t * 0.015 * EC_PATTERN_SPEED)
    );
    float2 r = float2(
        ec_fbm(p + 4.0 * q + float2(1.7, 9.2) + t * 0.01 * EC_PATTERN_SPEED),
        ec_fbm(p + 4.0 * q + float2(8.3, 2.8) + t * 0.008 * EC_PATTERN_SPEED)
    );

    float val = ec_fbm(p + 4.0 * r);

    // Shape to mimic Gray-Scott pattern structure:
    // Create sharper transitions between "filled" and "empty" regions
    val = val * val;
    val = smoothstep(0.05, 0.45, val);

    return val;
}

// ── 10-stop stained glass ember palette (from original display shader) ──
static float3 ec_palette(float t) {
    float3 c0 = float3(0.04, 0.025, 0.06);
    float3 c1 = float3(0.07, 0.035, 0.09);
    float3 c2 = float3(0.12, 0.04, 0.08);
    float3 c3 = float3(0.18, 0.03, 0.06);
    float3 c4 = float3(0.40, 0.06, 0.02);
    float3 c5 = float3(0.62, 0.18, 0.03);
    float3 c6 = float3(0.82, 0.38, 0.06);
    float3 c7 = float3(0.92, 0.58, 0.12);
    float3 c8 = float3(0.88, 0.52, 0.18);
    float3 c9 = float3(1.0, 0.88, 0.55);

    // Apply warmth shift
    float w = (EC_WARMTH - 1.0) * 0.4;
    c5 += float3(0.08, 0.03, 0.0) * w;
    c6 += float3(0.1, 0.06, 0.0) * w;
    c7 += float3(0.05, 0.08, 0.0) * w;

    float3 col;
    if (t < 0.03) {
        col = mix(c0, c1, t / 0.03);
    } else if (t < 0.08) {
        col = mix(c1, c2, (t - 0.03) / 0.05);
    } else if (t < 0.15) {
        col = mix(c2, c3, (t - 0.08) / 0.07);
    } else if (t < 0.25) {
        col = mix(c3, c4, (t - 0.15) / 0.10);
    } else if (t < 0.38) {
        col = mix(c4, c5, (t - 0.25) / 0.13);
    } else if (t < 0.52) {
        col = mix(c5, c6, (t - 0.38) / 0.14);
    } else if (t < 0.66) {
        col = mix(c6, c7, (t - 0.52) / 0.14);
    } else if (t < 0.80) {
        col = mix(c7, c8, (t - 0.66) / 0.14);
    } else if (t < 0.92) {
        col = mix(c8, c9, (t - 0.80) / 0.12);
    } else {
        col = mix(c9, float3(1.0, 0.95, 0.80), (t - 0.92) / 0.08);
    }
    return col;
}

fragment float4 fs_edge_of_chaos(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float t = u.time;

    // Scale UV for pattern — similar to the sim resolution mapping
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = float2(uv.x * aspect, uv.y) * 4.0;

    // Get the RD-like pattern value
    float val = ec_rdPattern(p, t);

    // Shape the value: pull down mid/high range so filled areas are darker
    float shaped = val;
    shaped = pow(shaped, 2.5);
    shaped = clamp(shaped * 1.5, 0.0, 1.0);

    float3 col = ec_palette(shaped);

    // Sobel edge detection approximation using noise gradient
    float2 eps = float2(0.02, 0.0);
    float vL = ec_rdPattern(p - eps.xy, t);
    float vR = ec_rdPattern(p + eps.xy, t);
    float vU = ec_rdPattern(p + eps.yx, t);
    float vD = ec_rdPattern(p - eps.yx, t);
    float grad = length(float2(vR - vL, vU - vD)) * 5.0;
    grad = clamp(grad, 0.0, 1.0);

    // Gold rim lighting on edges
    float3 rimColor = float3(1.0, 0.75, 0.22);
    col += rimColor * grad * 1.2 * EC_WARMTH;
    col += float3(0.4, 0.25, 0.6) * grad * 0.15;

    // Background brightness
    float3 bgCol = mix(float3(0.02, 0.01, 0.03), float3(1.0, 1.0, 1.0), EC_BG_BRIGHT);
    col = bgCol + col * (1.0 - EC_BG_BRIGHT * 0.3);

    // Bloom approximation: bright areas glow
    float bright = smoothstep(0.15, 0.5, val) * val;
    float3 bloomTinted = ec_palette(clamp(bright * 2.5, 0.0, 1.0));
    col += bloomTinted * 0.4 * EC_WARMTH;

    // Film grain
    float2 grainUV = uv * u.resolution;
    float grain = ec_hash(grainUV + float2(fract(t * 7.3), fract(t * 11.1)));
    grain = (grain - 0.5) * 0.03;
    col += grain;

    // Vignette
    float2 vigUV = uv * 2.0 - 1.0;
    float vig = 1.0 - dot(vigUV * 0.5, vigUV * 0.5);
    vig = clamp(vig, 0.0, 1.0);
    vig = vig * vig;
    col *= 0.3 + vig * 0.7;

    // Tone mapping (Reinhard)
    col = col / (1.0 + col * 0.15);

    // Gamma
    col = pow(max(col, float3(0.0)), float3(0.95));

    col = hue_rotate(col, u.hue_shift);
    return float4(clamp(col, float3(0.0), float3(1.0)), 1.0);
}
