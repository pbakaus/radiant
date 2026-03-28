#include "../Common.metal"

// ─── Polaroid Burn: Nostalgic photos developing, overexposing, and burning ───
// Ported from static/polaroid-burn.html

// Default parameter values (screensaver — no interactive controls)
constant float PB_BURN_SPEED = 0.6;
constant float PB_PHOTO_COUNT = 5.0;
constant float PB_TAU = 6.2831853;

// ── Hash / noise utilities ──
static float pb_hash(float n) { return fract(sin(n) * 43758.5453123); }
static float pb_hash2(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123); }

static float2 pb_hash2v(float2 p) {
    return float2(pb_hash2(p), pb_hash2(p + float2(37.0, 91.0)));
}

// Simplex-like 2D noise (local copy — uses snoise from Common for fbm below)
static float pb_fbm(float2 p) {
    float f = 0.0;
    f += 0.5000 * snoise(p); p *= 2.02;
    f += 0.2500 * snoise(p); p *= 2.03;
    f += 0.1250 * snoise(p); p *= 2.01;
    f += 0.0625 * snoise(p);
    return f;
}

// Rotation matrix
static float2x2 pb_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// Rounded rectangle SDF
static float pb_roundedRectSDF(float2 p, float2 halfSize, float radius) {
    float2 d = abs(p) - halfSize + radius;
    return length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

// Get deterministic polaroid properties from index
static float2 pb_getPhotoPos(float idx) {
    float hx = pb_hash(idx * 73.156);
    float hy = pb_hash(idx * 127.843);
    return float2(hx * 1.2 - 0.6, hy * 0.8 - 0.4);
}

static float pb_getPhotoAngle(float idx) {
    return (pb_hash(idx * 231.71) - 0.5) * 0.6;
}

static float pb_getPhotoPhase(float idx) {
    return pb_hash(idx * 347.29) * PB_TAU;
}

// Warm nostalgic gradient for "photo" content
static float3 pb_photoGradient(float2 localUV, float idx) {
    float n1 = pb_fbm(localUV * 2.0 + float2(pb_hash(idx * 13.0) * 10.0, pb_hash(idx * 29.0) * 10.0));
    float n2 = pb_fbm(localUV * 1.5 + float2(pb_hash(idx * 53.0) * 10.0, pb_hash(idx * 67.0) * 10.0));

    float3 c1 = float3(0.85, 0.45, 0.55);
    float3 c2 = float3(0.82, 0.58, 0.32);
    float3 c3 = float3(0.55, 0.38, 0.65);
    float3 c4 = float3(0.90, 0.72, 0.55);
    float3 c5 = float3(0.65, 0.30, 0.45);

    float blend = n1 * 0.5 + 0.5;
    float blend2 = n2 * 0.5 + 0.5;
    float idxMod = pb_hash(idx * 91.0);

    float3 colA = mix(c1, c2, blend);
    float3 colB = mix(c3, c4, blend2);
    float3 col = mix(colA, colB, idxMod);
    col = mix(col, c5, smoothstep(0.4, 0.9, localUV.y) * 0.3);

    float photoVig = 1.0 - length(localUV) * 0.6;
    col *= 0.7 + 0.3 * clamp(photoVig, 0.0, 1.0);

    return col;
}

// Compute a single polaroid contribution — returns float4(rgb, alpha)
static float4 pb_polaroid(float2 p, float idx, float time, float px) {
    float2 center = pb_getPhotoPos(idx);
    float angle = pb_getPhotoAngle(idx);
    float phase = pb_getPhotoPhase(idx);

    float cycleDur = PB_TAU;
    // mod with potentially negative input — use safe mod
    float t_cyc = (time * PB_BURN_SPEED + phase);
    t_cyc = t_cyc - cycleDur * floor(t_cyc / cycleDur);
    float tNorm = t_cyc / cycleDur;

    float appear = smoothstep(0.0, 0.05, tNorm);
    float disappear = 1.0 - smoothstep(0.90, 1.0, tNorm);
    float visibility = appear * disappear;

    if (visibility < 0.001) return float4(0.0);

    float2 lp = p - center;
    lp = pb_rot(angle) * lp;

    float2 outerSize = float2(0.16, 0.20);
    float2 innerSize = float2(0.13, 0.13);
    float2 innerOffset = float2(0.0, -0.02);
    float cornerR = 0.006;
    float aa = px * 2.0;

    float outerD = pb_roundedRectSDF(lp, outerSize, cornerR);
    float outerMask = smoothstep(aa, 0.0, outerD);

    if (outerMask < 0.001) return float4(0.0);

    float innerD = pb_roundedRectSDF(lp - innerOffset, innerSize, 0.003);
    float innerMask = smoothstep(aa, 0.0, innerD);

    float2 photoUV = (lp - innerOffset) / innerSize;

    float developAmount = smoothstep(0.0, 0.20, tNorm);
    float overexpose = smoothstep(0.40, 0.70, tNorm);
    float burnPhase = smoothstep(0.50, 0.85, tNorm);

    float burnNoise = pb_fbm(lp * 12.0 + float2(pb_hash(idx * 17.0) * 5.0, pb_hash(idx * 31.0) * 5.0));
    burnNoise += snoise(lp * 20.0 + time * 0.3) * 0.3;
    float burnEdgeDist = -outerD * 8.0;
    float burnMask = smoothstep(0.0, 1.0, burnPhase * 3.0 - burnEdgeDist - burnNoise * 0.5);

    float3 paperColor = float3(0.95, 0.93, 0.90);
    float3 photoColor = pb_photoGradient(photoUV, idx);

    photoColor = mix(float3(0.02, 0.01, 0.02), photoColor, developAmount);
    photoColor = mix(photoColor, float3(1.0, 0.98, 0.95), overexpose * 0.85);
    paperColor = mix(paperColor, float3(1.0), overexpose * 0.3);

    float3 polaroidColor = mix(paperColor, photoColor, innerMask);

    float emberGlow = burnMask * (1.0 - smoothstep(0.0, 0.5, burnMask));
    float3 emberColor = float3(1.0, 0.5, 0.1) * 2.0;
    float3 charColor = float3(0.03, 0.02, 0.01);

    polaroidColor = mix(polaroidColor, charColor, smoothstep(0.0, 0.5, burnMask));
    polaroidColor += emberColor * emberGlow * 1.5;

    float burnHole = smoothstep(0.6, 1.0, burnMask);
    float alpha = outerMask * visibility * (1.0 - burnHole);

    float shadowD = pb_roundedRectSDF(lp + float2(0.004, 0.006), outerSize + 0.01, cornerR);
    float shadowMask = smoothstep(0.02, 0.0, shadowD) * 0.25 * visibility * (1.0 - burnPhase);

    return float4(polaroidColor + shadowMask * 0.01, alpha + shadowMask * (1.0 - alpha));
}

fragment float4 fs_polaroid_burn(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 aspect = float2(u.resolution.x / u.resolution.y, 1.0);
    float2 p = (uv - 0.5) * aspect;
    float t = u.time;
    float px = 1.0 / min(u.resolution.x, u.resolution.y);

    // Background
    float3 bg = float3(0.039, 0.039, 0.039);
    float bgNoise = snoise(p * 3.0 + t * 0.02) * 0.008;
    bg += bgNoise;

    float ambientGlow = exp(-length(p) * 2.5) * 0.03;
    bg += float3(0.8, 0.5, 0.3) * ambientGlow;

    float3 col = bg;

    // Render polaroids back to front
    for (int i = 0; i < 8; i++) {
        if (float(i) >= PB_PHOTO_COUNT) break;
        float idx = float(i);
        float4 p4 = pb_polaroid(p, idx, t, px);
        col = mix(col, p4.rgb, p4.a);
    }

    // Global vignette
    float vig = 1.0 - smoothstep(0.4, 1.2, length(p * float2(0.85, 1.0)));
    col *= 0.65 + 0.35 * vig;

    // Film grain
    float grain = (fract(sin(dot(in.pos.xy, float2(12.9898, 78.233)) + fract(u.time * 0.1) * 100.0) * 43758.5453) - 0.5) * 0.02;
    col += grain;

    // Tone mapping
    col = clamp(col, 0.0, 1.0);
    col = col * col * (3.0 - 2.0 * col);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
