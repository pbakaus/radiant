#include "../Common.metal"

// ─── Lens Whisper: Anamorphic lens flare aesthetic ───
// Ported from static/lens-whisper.html

constant float LW_PI = 3.14159265359;
constant int LW_NUM_LIGHTS = 6;
constant float LW_FLARE_SPREAD = 1.0;
constant float LW_DRIFT_SPEED = 0.5;

// ── Hash functions ──
static float lw_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float lw_hash1(float n) {
    return fract(sin(n * 127.1) * 43758.5453);
}

// ── Smooth value noise ──
static float lw_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(lw_hash(i), lw_hash(i + float2(1.0, 0.0)), f.x),
        mix(lw_hash(i + float2(0.0, 1.0)), lw_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// ── FBM noise for ambient haze ──
static float lw_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * lw_noise(p);
        p = p * 2.1 + float2(1.7, 3.2);
        a *= 0.5;
    }
    return v;
}

// ── Per-light color tint ──
static float3 lw_lightTint(int idx) {
    if (idx == 0) return float3(0.30, 0.45, 1.00);  // cobalt
    if (idx == 1) return float3(1.00, 0.65, 0.20);  // amber
    if (idx == 2) return float3(0.20, 0.85, 0.75);  // teal
    if (idx == 3) return float3(1.00, 0.92, 0.80);  // warm white
    if (idx == 4) return float3(0.95, 0.40, 0.55);  // rose
    return float3(0.75, 0.85, 1.00);                  // cool white
}

// ── Light source positions with slow cinematic drift ──
static float2 lw_lightPos(int idx, float t) {
    float fi = float(idx);
    float seed = fi * 47.3;
    float ax = 0.30 + lw_hash1(seed) * 0.20;
    float ay = 0.35 + lw_hash1(seed + 1.0) * 0.20;
    float fx = 0.07 + lw_hash1(seed + 2.0) * 0.05;
    float fy = 0.05 + lw_hash1(seed + 3.0) * 0.04;
    float px = lw_hash1(seed + 4.0) * LW_PI * 2.0;
    float py = lw_hash1(seed + 5.0) * LW_PI * 2.0;
    float nx = lw_noise(float2(t * 0.03 + fi * 10.0, 0.0)) * 0.08 - 0.04;
    float ny = lw_noise(float2(0.0, t * 0.025 + fi * 10.0)) * 0.06 - 0.03;
    return float2(
        sin(t * fx + px) * ax + nx,
        sin(t * fy + py) * ay + ny
    );
}

// ── Light brightness ──
static float lw_lightBrightness(int idx, float t) {
    float fi = float(idx);
    float base = 0.45 + lw_hash1(fi * 13.7 + 100.0) * 0.25;
    float pulse = sin(t * (0.15 + lw_hash1(fi * 23.1) * 0.1) + fi * 2.0) * 0.12;
    return base + pulse;
}

// ── Anamorphic flare for a single light source ──
static float3 lw_anamorphicFlare(float2 uv, float2 lp, float brightness, float spread, float3 tint) {
    float2 delta = uv - lp;

    float stretch = 7.0 * spread;

    // Soft Gaussian point light (the core)
    float coreD = length(delta);
    float core = exp(-coreD * coreD * 160.0) * brightness * 0.45;
    float3 coreCol = mix(float3(1.0, 0.97, 0.90), tint, 0.3) * core;

    // Anamorphic horizontal streak
    float streakDx = delta.x / stretch;
    float streakDy = delta.y;

    float streakD = streakDx * streakDx * 12.0 + streakDy * streakDy * 600.0;
    float streak = exp(-streakD) * brightness * 0.35;

    // Chromatic aberration
    float chromaOffset = 0.015 * spread;
    float streakR_dx = (delta.x - chromaOffset) / stretch;
    float streakB_dx = (delta.x + chromaOffset) / stretch;
    float streakR_d = streakR_dx * streakR_dx * 12.0 + streakDy * streakDy * 600.0;
    float streakB_d = streakB_dx * streakB_dx * 12.0 + streakDy * streakDy * 600.0;
    float streakR = exp(-streakR_d) * brightness * 0.35;
    float streakB = exp(-streakB_d) * brightness * 0.35;

    float edgeness = smoothstep(0.0, 0.35 * spread, abs(delta.x));

    float3 warmFringe = float3(1.00, 0.55, 0.15);
    float3 coolFringe = float3(0.15, 0.35, 1.00);

    float3 leftColor = mix(tint, warmFringe, edgeness);
    float3 rightColor = mix(tint, coolFringe, edgeness);
    float3 streakTint = mix(leftColor, rightColor, smoothstep(-0.1, 0.1, delta.x));

    float3 streakCol = float3(0.0);
    streakCol.r = streakR * streakTint.r;
    streakCol.g = streak * streakTint.g;
    streakCol.b = streakB * streakTint.b;

    // Secondary wider, dimmer streak
    float wideStretch = stretch * 1.6;
    float wideDx = delta.x / wideStretch;
    float wideD = wideDx * wideDx * 8.0 + streakDy * streakDy * 700.0;
    float wideStreak = exp(-wideD) * brightness * 0.15;
    float3 wideCol = mix(tint * 0.6, mix(warmFringe, coolFringe, smoothstep(-0.2, 0.2, delta.x)) * 0.4, edgeness) * wideStreak;

    // Bokeh halo
    float haloR = 0.05 + brightness * 0.015;
    float haloDist = abs(coreD - haloR);
    float halo = exp(-haloDist * haloDist * 3500.0) * brightness * 0.10;
    float haloR2 = haloR * 1.8;
    float haloDist2 = abs(coreD - haloR2);
    float halo2 = exp(-haloDist2 * haloDist2 * 5000.0) * brightness * 0.04;
    float3 haloCol = tint * 0.8 * halo + float3(0.50, 0.60, 0.80) * halo2;

    return coreCol + streakCol + wideCol + haloCol;
}

fragment float4 fs_lens_whisper(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * LW_DRIFT_SPEED;

    // Pure black background
    float3 col = float3(0.0);

    // Ambient warm haze field
    float2 hazeUV = uv * 1.5 + float2(t * 0.01, t * 0.007);
    float hazeNoise = lw_fbm(hazeUV);
    float hazeNoise2 = lw_fbm(hazeUV * 0.7 + float2(5.3, 2.1));
    float3 hazeColor = mix(float3(0.35, 0.22, 0.10), float3(0.12, 0.15, 0.30), hazeNoise2);
    col += hazeColor * hazeNoise * 0.03;

    // Light sources with anamorphic flares and bokeh
    for (int i = 0; i < LW_NUM_LIGHTS; i++) {
        float2 lp = lw_lightPos(i, t);
        float bright = lw_lightBrightness(i, t);
        float3 tint = lw_lightTint(i);
        col += lw_anamorphicFlare(uv, lp, bright, LW_FLARE_SPREAD, tint);
    }

    // Lens dust / sparkle noise
    float2 dustUV = in.pos.xy * 0.8;
    float dustNoise = lw_hash(dustUV + fract(u.time * 0.7) * 200.0);
    float dust = smoothstep(0.985, 1.0, dustNoise);
    float dustLight = 0.0;
    for (int i = 0; i < LW_NUM_LIGHTS; i++) {
        float2 lp = lw_lightPos(i, t);
        float d = length(uv - lp);
        dustLight += exp(-d * d * 8.0) * lw_lightBrightness(i, t);
    }
    dustLight = min(dustLight, 1.2);
    col += float3(0.9, 0.85, 0.7) * dust * dustLight * 0.4;

    // Subtle warm ambient haze near lights
    float haze = 0.0;
    for (int i = 0; i < LW_NUM_LIGHTS; i++) {
        float2 lp = lw_lightPos(i, t);
        float d = length(uv - lp);
        haze += exp(-d * d * 3.0) * lw_lightBrightness(i, t) * 0.012;
    }
    col += float3(0.40, 0.25, 0.12) * haze;

    // Film grain
    float2 grainSeed = in.pos.xy + fract(u.time * 60.0) * float2(1973.0, 9277.0);
    float grain = (lw_hash(grainSeed) - 0.5) * 0.03;
    col += grain;

    // Vignette
    float vd = length(uv * float2(1.2, 1.0));
    float vignette = 1.0 - smoothstep(0.3, 0.95, vd);
    vignette = vignette * vignette;
    col *= vignette;

    // Tone mapping
    col = max(col, float3(0.0));
    col = col / (col + float3(0.6)) * 1.5;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
