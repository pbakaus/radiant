#include "../Common.metal"

// ─── Painted Strata: Layered sedimentary strata with tectonic deformation ───
// Ported from static/painted-strata.html

// Default parameter values
constant float PS_FOLD_SPEED = 0.5;
constant float PS_LAYER_COUNT = 16.0;

// ── Hash functions ──

static float ps_hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

static float ps_hash21(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float2 ps_hash22(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((float2(p3.x, p3.x) + float2(p3.y, p3.z)) * float2(p3.z, p3.y));
}

// ── Value noise ──

static float ps_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ps_hash21(i);
    float b = ps_hash21(i + float2(1.0, 0.0));
    float c = ps_hash21(i + float2(0.0, 1.0));
    float d = ps_hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──

static float ps_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0);
    float2x2 rot = float2x2(float2(cos(0.5), sin(0.5)), float2(-sin(0.5), cos(0.5)));
    for (int i = 0; i < 5; i++) {
        v += a * ps_vnoise(p);
        p = rot * p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ── Domain warp for tectonic deformation ──

static float2 ps_tectonicWarp(float2 uv, float t) {
    float slow = t * 0.15;
    float warpX = ps_fbm(uv * 1.5 + float2(slow * 0.7, slow * 0.3)) - 0.5;
    float warpY = ps_fbm(uv * 1.5 + float2(slow * 0.5 + 50.0, slow * 0.8 + 30.0)) - 0.5;
    float compress = sin(uv.x * 2.0 + slow * 0.4) * 0.08;
    float shear = sin(uv.y * 3.0 + slow * 0.6) * 0.06;
    return float2(
        uv.x + warpX * 0.25 + shear,
        uv.y + warpY * 0.18 + compress
    );
}

// ── Layer boundary function ──

static float ps_layerBoundary(float x, float baseY, float idx, float t) {
    float h1 = ps_hash11(idx * 7.13);
    float h2 = ps_hash11(idx * 13.37);
    float h3 = ps_hash11(idx * 23.71);
    float freq1 = 1.5 + h1 * 2.5;
    float freq2 = 3.0 + h2 * 3.0;
    float amp1 = 0.04 + h1 * 0.06;
    float amp2 = 0.015 + h2 * 0.025;
    float phase1 = t * (0.1 + h3 * 0.15);
    float phase2 = t * (0.08 + h1 * 0.12);
    float fold = amp1 * sin(x * freq1 + phase1 + h2 * 6.28);
    fold += amp2 * sin(x * freq2 + phase2 + h3 * 6.28);
    fold += 0.02 * ps_vnoise(float2(x * 4.0 + h1 * 100.0, t * 0.2 + idx));
    return baseY + fold;
}

// ── Earth tone palette ──

static float3 ps_stratumColor(float idx, float maxLayers) {
    float3 colors[7];
    colors[0] = float3(145.0, 105.0, 60.0) / 255.0;
    colors[1] = float3(190.0, 155.0, 105.0) / 255.0;
    colors[2] = float3(215.0, 195.0, 155.0) / 255.0;
    colors[3] = float3(225.0, 205.0, 165.0) / 255.0;
    colors[4] = float3(115.0, 85.0, 55.0) / 255.0;
    colors[5] = float3(165.0, 120.0, 75.0) / 255.0;
    colors[6] = float3(230.0, 218.0, 190.0) / 255.0;
    float h = ps_hash11(idx * 17.31 + 3.7);
    int ci = int(fmod(floor(h * 7.0), 7.0));
    float3 base;
    if (ci == 0) base = colors[0];
    else if (ci == 1) base = colors[1];
    else if (ci == 2) base = colors[2];
    else if (ci == 3) base = colors[3];
    else if (ci == 4) base = colors[4];
    else if (ci == 5) base = colors[5];
    else base = colors[6];
    float h2 = ps_hash11(idx * 31.17);
    base += (h2 - 0.5) * 0.06;
    return base;
}

// ── Grain texture per layer ──

static float ps_grainTexture(float2 uv, float layerIdx) {
    float h = ps_hash11(layerIdx * 41.93);
    float h2 = ps_hash11(layerIdx * 67.19);
    float intensity = 0.0;
    float fiberAngle = h * 3.14 * 0.3;
    float ca = cos(fiberAngle), sa = sin(fiberAngle);
    float2 rotUV = float2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca);
    float fiber1 = ps_vnoise(float2(rotUV.x * 120.0, rotUV.y * 18.0) + layerIdx * 30.0);
    float fiber2 = ps_vnoise(float2(rotUV.x * 80.0, rotUV.y * 12.0) + layerIdx * 50.0 + 100.0);
    intensity = fiber1 * 0.08 + fiber2 * 0.05;
    float cross_fiber = ps_vnoise(float2(rotUV.x * 15.0, rotUV.y * 70.0) + layerIdx * 40.0);
    intensity += cross_fiber * 0.03;
    intensity += ps_vnoise(uv * 50.0 + layerIdx * 25.0) * 0.025;
    return intensity - 0.04;
}

// ── Main fragment function ──

fragment float4 fs_painted_strata(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspectRatio = u.resolution.x / u.resolution.y;
    float2 uvAspect = float2(uv.x * aspectRatio, uv.y);

    float t = u.time * PS_FOLD_SPEED;
    float layerCount = floor(PS_LAYER_COUNT);

    // Apply tectonic domain warp
    float2 warped = ps_tectonicWarp(uvAspect, t);

    // No mouse in screensaver mode
    float2 mOff = float2(0.0);

    // Determine which layer this pixel is in
    float layerSpacing = 1.0 / (layerCount + 1.0);
    float currentLayer = -1.0;
    float layerPos = 0.0;

    float prevBound = -0.2;
    for (int i = 0; i < 24; i++) {
        if (float(i) >= layerCount) break;
        float fi = float(i);
        float baseY = (fi + 1.0) * layerSpacing;
        float layerDepth = fi / layerCount;
        float px = warped.x + mOff.x * (0.3 + layerDepth * 1.5);
        float bound = ps_layerBoundary(px, baseY, fi, t);
        bound += mOff.y * (0.1 + layerDepth * 0.4);
        if (warped.y >= prevBound && warped.y < bound) {
            currentLayer = fi;
            float thickness = bound - prevBound;
            layerPos = (warped.y - prevBound) / max(thickness, 0.001);
            break;
        }
        prevBound = bound;
    }
    // Top layer catches everything above last boundary
    if (currentLayer < 0.0) {
        currentLayer = layerCount;
        layerPos = 0.5;
    }

    // Get stratum color
    float3 col = ps_stratumColor(currentLayer, layerCount);

    // Add grain texture
    float grain = ps_grainTexture(warped, currentLayer);
    col += grain;

    // Subtle shading at layer boundaries
    float edgeShade = smoothstep(0.0, 0.15, layerPos) * smoothstep(1.0, 0.85, layerPos);
    col *= 0.85 + 0.15 * edgeShade;

    // Paper edge shadow
    float edgeShadow = smoothstep(0.0, 0.08, layerPos);
    col *= 0.82 + 0.18 * edgeShadow;
    // Slight highlight at top edge
    float topHighlight = smoothstep(1.0, 0.92, layerPos);
    col += float3(0.04, 0.035, 0.025) * (1.0 - topHighlight);

    // Subtle vignette
    float vig = 1.0 - 0.3 * length((uv - 0.5) * 1.5);
    col *= vig;

    // Overall paper texture overlay
    float paperTex = ps_vnoise(in.pos.xy * 0.15) * 0.03;
    paperTex += (ps_hash21(in.pos.xy + fract(u.time * 0.1) * 1000.0) - 0.5) * 0.015;
    col += paperTex;

    // Slightly desaturate
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(lum), col, 0.82);

    // Warm tone adjustment
    col = pow(col, float3(0.95, 1.0, 1.08));

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(col, 1.0);
}
