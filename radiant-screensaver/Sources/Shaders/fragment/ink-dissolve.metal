#include "../Common.metal"

// ─── Ink Dissolve: Organic ink tendrils via double domain-warped noise ───
// Ported from static/ink-dissolve.html

// Default parameter values
constant float ID_SPREAD_SPEED = 0.4;
constant float ID_TENDRIL_DETAIL = 1.0;

// ── FBM with rotation between octaves (unrolled) ──
static float id_fbm4(float2 p, float dm) {
    float v = 0.0;
    float a = 0.55;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    v += a * snoise(p); a *= 0.45; p = rot * p * 2.02;
    v += a * snoise(p); a *= 0.45; p = rot * p * 2.03;
    v += a * snoise(p) * dm; a *= 0.4; p = rot * p * 2.01;
    v += a * snoise(p) * dm * 0.6;
    return v;
}

static float id_fbm3(float2 p) {
    float v = 0.0;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    v += 0.5 * snoise(p); p = rot * p * 2.02;
    v += 0.25 * snoise(p); p = rot * p * 2.03;
    v += 0.125 * snoise(p);
    return v;
}

// ── Double domain-warped ink field ──
static float id_inkField(float2 p, float t, float dm) {
    // First warp: large-scale organic flow
    float2 q = float2(
        id_fbm4(p + float2(0.0, 0.0) + t * 0.04, dm),
        id_fbm4(p + float2(5.2, 1.3) + t * 0.03, dm)
    );
    // Second warp: gentler, for tendril branching
    float2 r = float2(
        id_fbm4(p + 2.5 * q + float2(1.7, 9.2) + t * 0.022, dm),
        id_fbm4(p + 2.5 * q + float2(8.3, 2.8) + t * 0.032, dm)
    );
    return id_fbm4(p + 2.2 * r + t * 0.015, dm);
}

fragment float4 fs_ink_dissolve(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * ID_SPREAD_SPEED;
    float dm = ID_TENDRIL_DETAIL;

    // ── Primary ink field (broad tendrils via domain warping) ──
    float field = id_inkField(uv * 0.8, t, dm);

    // ── Ink source envelope: slow drifting origins ──
    float envelope = 0.0;
    float a1 = t * 0.05;
    envelope += smoothstep(0.95, 0.0, length(uv - float2(cos(a1) * 0.15, sin(a1 * 0.7) * 0.12)));
    float a2 = t * 0.04 + 2.2;
    envelope += smoothstep(0.85, 0.0, length(uv - float2(cos(a2) * 0.25, sin(a2 * 0.6) * 0.2)));
    float a3 = t * 0.048 + 4.7;
    envelope += smoothstep(0.75, 0.0, length(uv - float2(cos(a3 * 0.8) * 0.2, sin(a3) * 0.16)));
    envelope += smoothstep(0.65, 0.0, length(uv)) * 0.6;

    // No mouse in screensaver mode
    envelope = clamp(envelope, 0.0, 1.0);

    // ── Shape into ink ──
    float inkRaw = smoothstep(-0.2, 0.1, field);
    float ink = inkRaw * envelope;

    // ── Secondary fine tendrils ──
    float fineField = id_fbm3(uv * 2.5 + float2(t * 0.02, -t * 0.015));
    float fineTendril = smoothstep(-0.1, 0.12, fineField) * envelope;
    float combinedInk = max(ink, fineTendril * 0.35);

    // ── Edge glow: analytical from the ink transition zone ──
    float edgeRaw = combinedInk * (1.0 - combinedInk) * 4.0;
    float edgeSoft = smoothstep(0.05, 0.5, edgeRaw);
    float edgeMid = smoothstep(0.25, 0.8, edgeRaw);
    float edgeHot = smoothstep(0.6, 1.0, edgeRaw);

    // ── Fine edge from secondary tendrils ──
    float fineEdge = fineTendril * (1.0 - fineTendril) * 4.0;
    fineEdge = smoothstep(0.3, 0.9, fineEdge) * 0.4;

    // ── Color palette (warm amber) ──
    float3 inkDark    = float3(0.02, 0.015, 0.01);
    float3 amberDim   = float3(0.06, 0.035, 0.014);
    float3 amberDeep  = float3(0.18, 0.10, 0.035);
    float3 amberWarm  = float3(0.42, 0.28, 0.14);
    float3 amberGold  = float3(0.78, 0.58, 0.42);
    float3 amberBright = float3(1.0, 0.82, 0.52);
    float3 amberHot   = float3(1.0, 0.92, 0.72);

    // ── Liquid background ──
    float liqVar = 0.5 + 0.5 * id_fbm3(uv * 2.0 + t * 0.03);
    float3 liquid = mix(amberDim, amberDeep, liqVar * 0.7);

    // Subtle caustic shimmer in liquid
    float c1 = 0.5 + 0.5 * snoise(uv * 6.0 + float2(t * 0.05, -t * 0.035));
    float c2 = 0.5 + 0.5 * snoise(uv * 10.0 + float2(-t * 0.03, t * 0.04));
    liquid += amberWarm * c1 * c2 * 0.05 * (1.0 - combinedInk);

    // ── Compose: dark ink over amber liquid ──
    float3 col = mix(liquid, inkDark, combinedInk);

    // ── Multi-layer edge glow ──
    col += amberDeep * edgeSoft * 0.7;
    col += amberGold * edgeMid * 0.4;
    col += amberBright * edgeHot * 0.45;
    col += amberHot * edgeHot * edgeHot * 0.25;

    // Fine tendril glow
    col += amberWarm * fineEdge * 0.3;
    col += amberGold * fineEdge * fineEdge * 0.15;

    // ── Subtle depth in ink regions ──
    float inkTex = 0.5 + 0.5 * snoise(uv * 3.5 + t * 0.01);
    col += float3(0.015, 0.01, 0.005) * inkTex * combinedInk;

    // ── Subsurface glow ──
    float thinInk = smoothstep(0.5, 0.1, combinedInk);
    col += amberDim * thinInk * edgeSoft * 0.3;

    // ── Ambient warm light from below ──
    float vertGlow = smoothstep(0.6, -0.3, uv.y);
    col += float3(0.025, 0.012, 0.004) * vertGlow * (1.0 - combinedInk * 0.6);

    // ── Vignette ──
    float vig = 1.0 - smoothstep(0.35, 1.2, length(uv));
    col *= 0.5 + 0.5 * vig;

    // ── Warm gamma ──
    col = pow(max(col, float3(0.0)), float3(0.93, 0.97, 1.04));

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
