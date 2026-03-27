#include "../Common.metal"

// ─── Aurora Curtain: Vertical flowing curtain lines ───
// Ported from static/aurora-curtain.html

constant float AC_WAVE_SPEED = 1.0;
constant float AC_LINE_COUNT = 6.0;
constant float AC_AMPLITUDE = 1.0;
constant float AC_ROTATION = 0.0;
constant int AC_MAX_LINES = 12;

// ── Hash for noise ──
static float ac_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth value noise ──
static float ac_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ac_hash(i);
    float b = ac_hash(i + float2(1.0, 0.0));
    float c = ac_hash(i + float2(0.0, 1.0));
    float d = ac_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Rotation matrix ──
static float2x2 ac_rot2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// ── Single vertical curtain line ──
static float3 ac_curtainLine(float2 uv, float speed, float freq, float3 col, float t) {
    uv.x += smoothstep(1.0, 0.0, abs(uv.y)) * sin(t * speed + uv.y * freq) * 0.2;
    float lw = 0.06 * smoothstep(0.2, 0.9, abs(uv.y));
    float l = smoothstep(lw, 0.0, abs(uv.x) - 0.004);
    float fade = smoothstep(1.0, 0.3, abs(uv.y));
    return l * col * fade;
}

fragment float4 fs_aurora_curtain(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - 0.5 * u.resolution.xy) / u.resolution.y;
    uv = ac_rot2(AC_ROTATION) * uv;

    float mouseAmp = AC_AMPLITUDE;
    float mouseFreq = 1.0;
    float t = u.time * AC_WAVE_SPEED;
    int lineCount = int(AC_LINE_COUNT);

    float3 col = float3(0.0);

    for (int i = 0; i < AC_MAX_LINES; i++) {
        if (i >= lineCount) break;
        float fi = float(i);
        float frac = fi / max(AC_LINE_COUNT - 1.0, 1.0);

        float speed = (0.6 + frac * 0.5) * mouseFreq;
        float freq = (4.0 + frac * 2.0) * mouseAmp;

        // Color: warm amber at base, cool teal at top
        float3 warmAmber = float3(0.85, 0.55, 0.25);
        float3 coolTeal = float3(0.2, 0.6, 0.65);
        float3 lineCol = mix(warmAmber, coolTeal, frac) * (0.5 + frac * 0.5);

        float yBlend = smoothstep(-0.4, 0.5, uv.y);
        float3 pixelCol = mix(warmAmber, coolTeal, yBlend) * (0.4 + frac * 0.6);
        lineCol = mix(lineCol, pixelCol, 0.6);

        float drift = sin(t * 0.15 + fi * 1.3) * 0.03;
        float nOff = ac_noise(float2(uv.y * 2.0 + fi * 3.7, t * 0.1 + fi)) * 0.015;

        col += ac_curtainLine(uv + float2(nOff + drift, 0.0), speed, freq, lineCol, t);
    }

    // ── Vignette ──
    float vig = 1.0 - dot(uv, uv) * 0.4;
    col *= max(vig, 0.0);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
