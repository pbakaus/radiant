#include "../Common.metal"

// ─── Shifting Veils: Layered translucent noise curtains ───
// Ported from static/shifting-veils.html

constant float SHV_PI = 3.14159265359;
constant float SHV_TAU = 6.28318530718;

// Default parameter values
constant float SHV_LAYER_SPEED = 0.5;
constant float SHV_LAYER_COUNT = 5.0;

// ── Hash functions ──

static float shv_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static float shv_hash3(float3 p) {
    return fract(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453123);
}

// ── Smooth 2D value noise ──

static float shv_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = shv_hash(i);
    float b = shv_hash(i + float2(1.0, 0.0));
    float c = shv_hash(i + float2(0.0, 1.0));
    float d = shv_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──

static float shv_fbm(float2 p) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 5; i++) {
        val += amp * shv_vnoise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return val;
}

// ── Domain-warped noise ──

static float shv_warpedNoise(float2 p, float t, float seed) {
    float2 q = float2(
        shv_fbm(p + float2(seed * 1.7, seed * 2.3) + t * 0.15),
        shv_fbm(p + float2(seed * 3.1 + 5.2, seed * 1.3 + 1.3) + t * 0.12)
    );
    float2 r = float2(
        shv_fbm(p + 4.0 * q + float2(1.7, 9.2) + t * 0.08),
        shv_fbm(p + 4.0 * q + float2(8.3, 2.8) + t * 0.1)
    );
    return shv_fbm(p + 3.5 * r);
}

// ── Rotation matrix ──

static float2x2 shv_rot2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// ── Main fragment function ──

fragment float4 fs_shifting_veils(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 aspect = float2(u.resolution.x / u.resolution.y, 1.0);
    float2 p = uv * aspect;
    float t = u.time * SHV_LAYER_SPEED;

    // No mouse in screensaver mode
    float2 mouseShift = float2(0.0);

    // ── Accumulate color from back to front ──
    float3 col = float3(0.012, 0.01, 0.008);

    for (int i = 0; i < 7; i++) {
        if (float(i) >= SHV_LAYER_COUNT) break;

        float fi = float(i);
        float layerFrac = fi / max(SHV_LAYER_COUNT - 1.0, 1.0);

        float speed = 0.3 + fi * 0.12;
        float scale = 1.8 + fi * 0.7;
        float angle = fi * 0.7 + 0.3;

        float parallax = 0.3 + layerFrac * 0.7;

        float2 drift = float2(
            cos(angle) * speed * t * parallax,
            sin(angle) * speed * t * parallax * 0.7
        );

        // Rotate coordinates per layer
        float2 lp = (p - 0.5 * aspect + mouseShift * (0.5 + layerFrac * 0.5)) * shv_rot2(fi * 0.4 + t * 0.02 * (fi - 2.5)) + 0.5 * aspect;
        lp = lp * scale + drift;

        float n = shv_warpedNoise(lp, t * (0.8 + fi * 0.15), fi * 3.7 + 1.0);

        float veil = smoothstep(0.25, 0.55, n);
        veil *= smoothstep(0.85, 0.6, n);
        float broad = smoothstep(0.2, 0.7, n) * 0.5;
        veil = max(veil, broad);

        float fadePhase = t * 0.15 + fi * 1.3;
        float fadeCycle = sin(fadePhase) * 0.5 + 0.5;
        float reveal = smoothstep(0.0, 0.3, fadeCycle);
        float opacity = mix(0.08, 0.55, reveal);

        opacity *= (0.6 + 0.4 * (1.0 - layerFrac));

        float3 layerColor;
        if (i == 0) {
            layerColor = float3(0.12, 0.07, 0.04);
        } else if (i == 1) {
            layerColor = float3(0.22, 0.12, 0.06);
        } else if (i == 2) {
            layerColor = float3(0.45, 0.25, 0.12);
        } else if (i == 3) {
            layerColor = float3(0.65, 0.42, 0.15);
        } else if (i == 4) {
            layerColor = float3(0.78, 0.55, 0.22);
        } else if (i == 5) {
            layerColor = float3(0.85, 0.65, 0.35);
        } else {
            layerColor = float3(0.9, 0.75, 0.5);
        }

        float colorShift = sin(n * 6.0 + t * 0.3 + fi * 2.0) * 0.05;
        layerColor += colorShift;

        float edgeGlow = smoothstep(0.0, 0.15, veil) * smoothstep(0.5, 0.25, veil);
        float3 glowColor = layerColor * 1.4 + float3(0.1, 0.06, 0.02);
        layerColor = mix(layerColor, glowColor, edgeGlow * 0.5);

        float alpha = veil * opacity;
        col = mix(col, layerColor, alpha);
    }

    // ── Subtle overall atmospheric glow ──
    float2 center = (uv - 0.5) * aspect;
    float centerDist = length(center);
    float atmosGlow = exp(-centerDist * centerDist * 2.0) * 0.04;
    col += float3(0.6, 0.4, 0.2) * atmosGlow;

    // ── Subtle breathing pulse ──
    float breathe = sin(u.time * 0.2) * 0.02 + 1.0;
    col *= breathe;

    // ── Tone mapping ──
    col = col / (col + 0.5) * 1.1;

    // ── Slight warmth push ──
    col = pow(col, float3(0.95, 0.98, 1.05));

    // ── Soft vignette ──
    float vig = 1.0 - dot(center / aspect, center / aspect) * 0.6;
    vig = smoothstep(0.0, 1.0, vig);
    col *= vig;

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(col, 1.0);
}
