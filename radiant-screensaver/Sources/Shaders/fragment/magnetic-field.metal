#include "../Common.metal"

// ─── Magnetic Field: Dipole field lines with silk glow ───
// Ported from static/magnetic-field.html

constant float MF_PI = 3.14159265;
constant float MF_WAVE_SPEED = 1.0;
constant float MF_LINE_COUNT = 8.0;

// ── Hash for noise ──
static float mf_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float mf_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = mf_hash(i);
    float b = mf_hash(i + float2(1.0, 0.0));
    float c = mf_hash(i + float2(0.0, 1.0));
    float d = mf_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Analytical dipole field line distance
static float mf_fieldLineGlow(float2 lp, float numLines, float t) {
    float r = length(lp);
    if (r < 0.01) return 0.0;
    float theta = atan2(abs(lp.y), lp.x);

    // Avoid singularity at theta=0 and theta=PI
    float sinT = sin(theta);
    if (sinT < 0.05) return 0.0;

    // The field line constant for this pixel
    float R = r / (sinT * sinT);

    // Quantize into discrete field lines
    float spacing = 0.8 / numLines;
    float lineIdx = R / spacing;
    float nearest = floor(lineIdx + 0.5) * spacing;

    // Distance in R-space, convert to approximate screen distance
    float dR = abs(R - nearest);
    float screenDist = dR * sinT * sinT;

    // Silk-style glow
    float lw = 0.06 * smoothstep(0.05, 0.5, r);
    float l = smoothstep(lw, 0.0, screenDist - 0.004);

    // Fade at extremities
    float fade = smoothstep(0.9, 0.2, r) * smoothstep(0.0, 0.05, sinT);

    // Energy pulse flowing along the field lines
    float pulse = pow(sin(theta * 3.0 - t * 1.5) * 0.5 + 0.5, 3.0);
    float brightness = 0.4 + pulse * 0.6;

    return l * fade * brightness;
}

fragment float4 fs_magnetic_field(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - 0.5 * u.resolution.xy) / u.resolution.y;
    float t = u.time * MF_WAVE_SPEED;

    // Poles — no mouse, use default angle 0
    float poleAngle = 0.0;
    float2 pole1 = float2(cos(poleAngle), sin(poleAngle)) * -0.3;
    float2 pole2 = float2(cos(poleAngle), sin(poleAngle)) * 0.3;
    float2 center = float2(0.0);
    float2 axis = normalize(pole2 - pole1);

    // Transform uv into dipole-local coords
    float2 lp = uv - center;
    lp = float2(dot(lp, axis), dot(lp, float2(-axis.y, axis.x)));

    // Noise perturbation
    float n = mf_noise(float2(lp.x * 3.0, t * 0.1)) * 0.01;
    lp += float2(n, n * 0.5);

    float numLines = MF_LINE_COUNT;

    // Compute glow for both halves of the dipole
    float glow1 = mf_fieldLineGlow(lp, numLines, t);
    float glow2 = mf_fieldLineGlow(float2(lp.x, -lp.y), numLines, t);
    float glow = max(glow1, glow2);

    // Color: warm amber gradient based on position
    float angle = atan2(lp.y, lp.x) / MF_PI;
    float3 lineCol = float3(
        0.35 + abs(angle) * 0.55,
        0.25 + abs(angle) * 0.3,
        0.3 + (1.0 - abs(angle)) * 0.1
    );

    float3 col = glow * lineCol;

    // Subtle glow at poles
    float g1 = 0.006 / (length(uv - pole1) + 0.01);
    float g2 = 0.006 / (length(uv - pole2) + 0.01);
    col += float3(0.9, 0.6, 0.3) * (g1 + g2) * 0.12;

    // Vignette
    float vig = 1.0 - dot(uv, uv) * 0.4;
    col *= max(vig, 0.0);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
