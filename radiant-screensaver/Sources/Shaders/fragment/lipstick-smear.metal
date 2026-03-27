#include "../Common.metal"

// ─── Lipstick Smear: Procedural cosmetic fluid simulation ───
// Ported from static/lipstick-smear.html
// The original is a multi-pass Navier-Stokes fluid sim. This port
// recreates the visual aesthetic procedurally in a single pass using
// domain-warped noise fields to approximate advected dye.

constant float LS_PI = 3.14159265359;
constant float LS_VISCOSITY = 0.8;
constant float LS_COLOR_INTENSITY = 1.0;

// ── Hash ──
static float ls_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth value noise ──
static float ls_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ls_hash(i);
    float b = ls_hash(i + float2(1.0, 0.0));
    float c = ls_hash(i + float2(0.0, 1.0));
    float d = ls_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float ls_fbm(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        val += amp * ls_noise(p * freq);
        freq *= 2.03;
        amp *= 0.49;
        p += float2(1.7, 9.2);
    }
    return val;
}

// ── Domain warp to simulate fluid advection ──
static float2 ls_warp(float2 p, float t) {
    float2 q = float2(
        ls_fbm(p + float2(0.0, 0.0) + t * float2(0.15, -0.12), 5),
        ls_fbm(p + float2(5.2, 1.3) + t * float2(-0.10, 0.18), 5)
    );
    float2 r = float2(
        ls_fbm(p + 3.0 * q + float2(1.7, 9.2) + t * float2(0.08, 0.06), 5),
        ls_fbm(p + 3.0 * q + float2(8.3, 2.8) + t * float2(-0.09, 0.10), 5)
    );
    return p + 2.0 * r;
}

// ── Palette: hot pink / crimson / magenta / rose gold ──
static float3 ls_palette(float idx, float t) {
    // 6 colors from the original PAL array
    float3 colors[6] = {
        float3(1.00, 0.08, 0.58),   // hot pink
        float3(0.86, 0.08, 0.24),   // crimson
        float3(1.00, 0.00, 1.00),   // magenta
        float3(0.72, 0.43, 0.47),   // rose gold
        float3(0.95, 0.18, 0.45),   // deep pink
        float3(0.80, 0.02, 0.28),   // dark rose
    };
    // Smooth interpolation between palette entries
    float fi = idx - floor(idx / 6.0) * 6.0; // positive mod 6
    int i0 = int(fi);
    int i1 = (i0 + 1) % 6;
    float frac_val = fi - float(i0);
    // Ensure indices are in range
    i0 = clamp(i0, 0, 5);
    i1 = clamp(i1, 0, 5);
    return mix(colors[i0], colors[i1], frac_val);
}

static float ls_luma(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

fragment float4 fs_lipstick_smear(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float t = u.time;

    // Build fluid-like dye field from multiple warped noise layers
    // Each layer represents an emitter path from the original sim
    float3 dye = float3(0.0);

    // 6 emitter contributions, each with different warp and palette
    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float phase = fi * LS_PI * 2.0 / 6.0;

        // Emitter center orbits
        float2 center = float2(
            0.5 + 0.25 * sin(t * (0.20 + fi * 0.03) + phase),
            0.5 + 0.20 * cos(t * (0.15 + fi * 0.02) + phase + 1.2)
        );

        // Domain-warped coordinate relative to emitter
        float viscScale = 1.0 + LS_VISCOSITY * 0.5;
        float2 wp = ls_warp((uv - center) * 3.0 * viscScale + fi * float2(10.0, 7.0), t * 0.3);

        // Dye density from warped noise
        float density = ls_fbm(wp, 6);
        density = density * density; // sharpen

        // Gaussian falloff from emitter center
        float2 dc = uv - center;
        float falloff = exp(-dot(dc, dc) * 4.0);

        // Color from palette with time-varying shift
        float colorIdx = fi + sin(t * 0.28 + fi * 1.1) * 0.5;
        float3 dyeColor = ls_palette(colorIdx, t);

        dye += dyeColor * density * falloff * 0.7;
    }

    // Apply intensity
    float3 col = dye * LS_COLOR_INTENSITY;

    // Rose-gold metallic rim sheen on pigmented areas (from display shader)
    float pg = ls_luma(col);
    float2 vn = uv * 2.0 - 1.0;
    float rim = max(0.0, dot(normalize(vn + float2(1e-5)), normalize(float2(0.5, 0.8))));
    rim = pow(rim, 5.0);
    col += float3(1.0, 0.72, 0.78) * rim * pg * 0.7;

    // Vignette
    float vig = pow(1.0 - dot(vn * float2(0.6, 0.75), vn * float2(0.6, 0.75)), 0.5);
    col *= clamp(vig, 0.0, 1.0);

    // Tone map: Reinhard
    col = col / (col + float3(0.75));

    // Gamma
    col = pow(max(col, float3(0.0)), float3(0.9));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
