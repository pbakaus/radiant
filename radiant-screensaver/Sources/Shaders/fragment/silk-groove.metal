#include "../Common.metal"

// ─── Silk Groove: Luxurious flowing silk fabric with shimmering folds ───
// Ported from static/silk-groove.html

constant float SG_FLOW_SPEED = 0.8;
constant float SG_FOLD_DEPTH = 1.0;

// Smooth FBM — 3 octaves for organic warping (uses snoise from Common.metal)
static float sg_smoothFbm(float2 p, float t) {
    float val = 0.0;
    float amp = 0.55;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 3; i++) {
        val += amp * snoise(p + t * 0.1);
        p = rot * p * 1.9;
        amp *= 0.42;
    }
    return val;
}

// Silk fabric height field
static float sg_silkHeight(float2 uv, float t) {
    float angle = 0.45;
    float ca = cos(angle); float sa = sin(angle);
    float2 fuv = float2(ca * uv.x + sa * uv.y, -sa * uv.x + ca * uv.y);

    // Primary folds
    float folds = sin(fuv.y * 4.0 + t * 0.3) * 0.30;
    folds += sin(fuv.y * 6.5 + t * 0.45 + 1.0) * 0.16;
    folds += sin(fuv.y * 10.0 + t * 0.55 + 2.5) * 0.07;
    folds += sin(fuv.y * 14.0 + t * 0.7 + 4.0) * 0.03;

    // Gather modulation
    float gather = sin(fuv.x * 0.8 + t * 0.15) * 0.4 + 0.6;
    folds *= gather;

    // Cross-folds
    float cross_f = sin(fuv.x * 2.0 + fuv.y * 0.5 + t * 0.25 + 3.0) * 0.06;
    cross_f += sin(fuv.x * 3.5 - fuv.y * 0.8 + t * 0.35 + 5.0) * 0.04;

    // Billow
    float billow = sin(uv.x * 0.9 + uv.y * 0.6 + t * 0.2) * 0.15;
    billow += sin(uv.x * 0.5 - uv.y * 1.1 + t * 0.18 + 2.0) * 0.12;

    // Organic noise
    float organic = sg_smoothFbm(uv * 0.3, t * 0.4) * 0.1;

    return folds + cross_f + billow + organic;
}

// Surface normal via central differences
static float3 sg_silkNormal(float2 uv, float t) {
    float eps = 0.003;
    float hC = sg_silkHeight(uv, t);
    float hR = sg_silkHeight(uv + float2(eps, 0.0), t);
    float hU = sg_silkHeight(uv + float2(0.0, eps), t);
    return normalize(float3(hC - hR, hC - hU, eps * 1.0));
}

fragment float4 fs_silk_groove(VSOut in [[stage_in]],
                               constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y - 0.5) * 3.2;

    float t = u.time * SG_FLOW_SPEED;

    // Gentle domain warp
    float2 warp = float2(
        snoise(p * 0.18 + t * 0.05 + float2(0.0, 4.7)),
        snoise(p * 0.18 + t * 0.04 + float2(8.3, 0.0))
    ) * 0.25;
    float2 sp = p + warp;

    // Height and normal
    float h = sg_silkHeight(sp, t) * SG_FOLD_DEPTH;
    float3 N = sg_silkNormal(sp, t);

    // ── Lighting — warm two-point setup (no mouse) ──
    float3 L1 = normalize(float3(0.3, 0.5, 0.75));
    float3 L2 = normalize(float3(-0.5, -0.3, 0.65));
    float3 V = float3(0.0, 0.0, 1.0);

    // Diffuse
    float d1 = max(dot(N, L1), 0.0);
    float d2 = max(dot(N, L2), 0.0);

    // Wrapped diffuse
    float wd1 = max(0.0, (dot(N, L1) + 0.3) / 1.3);

    // Specular lobes
    float3 H1 = normalize(L1 + V);
    float3 H2 = normalize(L2 + V);

    float sheen1 = pow(max(dot(N, H1), 0.0), 3.0) * 0.4;
    float sheen2 = pow(max(dot(N, H2), 0.0), 4.0) * 0.2;

    float spec1 = pow(max(dot(N, H1), 0.0), 18.0);
    float spec2 = pow(max(dot(N, H2), 0.0), 22.0);

    float spark = pow(max(dot(N, H1), 0.0), 90.0);

    float fresnel = pow(1.0 - max(dot(N, V), 0.0), 3.0);

    // ── Color palette ──
    float3 deepAmber    = float3(0.45, 0.22, 0.08);
    float3 richGold     = float3(0.70, 0.50, 0.16);
    float3 warmBurgundy = float3(0.32, 0.07, 0.09);
    float3 deepRose     = float3(0.48, 0.16, 0.14);
    float3 lightSilk    = float3(1.0, 0.88, 0.55);
    float3 pearlHL      = float3(1.0, 0.94, 0.75);

    // Base color
    float cm1 = smoothstep(-0.3, 0.4, h);
    float cm2 = snoise(sp * 0.25 + t * 0.02 + float2(13.0, 7.0)) * 0.5 + 0.5;
    float cm3 = snoise(sp * 0.15 + float2(3.0, 11.0)) * 0.5 + 0.5;

    float3 baseColor = mix(warmBurgundy, deepAmber, cm1);
    baseColor = mix(baseColor, richGold, cm2 * 0.5);
    baseColor = mix(baseColor, deepRose, cm3 * 0.2);

    // ── Compose ──
    float3 col = baseColor * 0.15; // ambient

    // Primary warm key light
    float3 lc1 = float3(1.0, 0.87, 0.58);
    col += baseColor * wd1 * 0.5 * lc1;
    col += baseColor * sheen1 * lc1;
    col += lightSilk * spec1 * 0.6;
    col += pearlHL * spark * 0.5;

    // Secondary cooler fill
    float3 lc2 = float3(0.6, 0.5, 0.72);
    col += baseColor * d2 * 0.18 * lc2;
    col += baseColor * sheen2 * lc2;
    col += float3(0.75, 0.65, 0.85) * spec2 * 0.2;

    // Fresnel edge glow
    col += pearlHL * fresnel * 0.1;

    // ── Traveling shimmer along fold ridges ──
    float angle2 = 0.45;
    float ca2 = cos(angle2); float sa2 = sin(angle2);
    float foldDir = ca2 * sp.x + sa2 * sp.y;
    float shim = sin(foldDir * 4.0 - t * 1.5) * 0.5 + 0.5;
    shim = pow(shim, 18.0);
    col += pearlHL * shim * (spec1 + sheen1 * 0.3) * 0.5;

    // ── Fold shadows ──
    float valley = smoothstep(0.05, -0.25, h);
    col *= 1.0 - valley * 0.5;

    float deepSh = smoothstep(-0.1, -0.45, h);
    col = mix(col, float3(0.05, 0.02, 0.025), deepSh * 0.45);

    // ── Subtle iridescence ──
    col.r += fresnel * 0.06;
    col.b += fresnel * 0.03;

    // ── Vignette ──
    float2 vc = uv - 0.5;
    float vig = 1.0 - dot(vc, vc) * 1.4;
    vig = smoothstep(0.0, 1.0, vig);
    col *= vig;

    // Tone mapping + gamma
    col = col / (col + float3(0.6));
    col = pow(col, float3(0.9));

    // Floor to near-black
    col = max(col, float3(0.018, 0.015, 0.013));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
