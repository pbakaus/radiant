#include "../Common.metal"

// ─── Gilded Fracture: Kintsugi-inspired golden cracks on dark ceramic ───
// Ported from static/gilded-fracture.html

constant float GF_PI = 3.14159265359;
constant float GF_CRACK_SPEED = 0.3;
constant float GF_GLOW_INTENSITY = 1.0;

// ── Hash primitives ──
static float gf_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float2 gf_hash2(float2 p) {
    return float2(
        fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, float2(269.5, 183.3))) * 43758.5453)
    );
}

// ── Smooth value noise ──
static float gf_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = gf_hash(i);
    float b = gf_hash(i + float2(1.0, 0.0));
    float c = gf_hash(i + float2(0.0, 1.0));
    float d = gf_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float gf_fbm(float2 p) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 5; i++) {
        val += amp * gf_noise(p * freq);
        freq *= 2.03;
        amp *= 0.49;
        p += float2(1.7, 9.2);
    }
    return val;
}

// ── Domain-warped Voronoi (5x5 neighbor) ──
static float3 gf_kintsugiVoronoi(float2 p, float t, float warpAmt) {
    float2 warp = float2(
        gf_fbm(p * 0.8 + t * 0.05),
        gf_fbm(p * 0.8 + float2(5.2, 1.3) + t * 0.04)
    );
    p += warp * warpAmt;

    float2 i = floor(p);
    float2 f = fract(p);
    float minDist = 10.0;
    float secondDist = 10.0;
    float2 nearestCell = float2(0.0);

    for (int jy = -2; jy <= 2; jy++) {
        for (int jx = -2; jx <= 2; jx++) {
            float2 nb = float2(float(jx), float(jy));
            float2 cid = i + nb;
            float2 h = gf_hash2(cid);
            float2 pt = nb + h * 0.85 + 0.075;
            pt.x += sin(t * 0.07 + h.x * 20.0) * 0.06;
            pt.y += cos(t * 0.06 + h.y * 20.0) * 0.06;
            float d = dot(pt - f, pt - f);
            if (d < minDist) { secondDist = minDist; minDist = d; nearestCell = cid; }
            else if (d < secondDist) { secondDist = d; }
        }
    }

    float edge = sqrt(secondDist) - sqrt(minDist);
    return float3(sqrt(minDist), edge, gf_hash(nearestCell));
}

// ── Fine crack Voronoi (3x3) ──
static float3 gf_fineVoronoi(float2 p, float t) {
    float2 warp = float2(
        gf_fbm(p * 1.2 + t * 0.03 + float2(10.0, 0.0)),
        gf_fbm(p * 1.2 + t * 0.04 + float2(20.0, 5.0))
    );
    p += warp * 0.4;

    float2 i = floor(p);
    float2 f = fract(p);
    float minDist = 10.0;
    float secondDist = 10.0;
    float2 nearestCell = float2(0.0);

    for (int jy = -1; jy <= 1; jy++) {
        for (int jx = -1; jx <= 1; jx++) {
            float2 nb = float2(float(jx), float(jy));
            float2 cid = i + nb;
            float2 h = gf_hash2(cid + float2(50.0));
            float2 pt = nb + h * 0.8 + 0.1;
            pt.x += sin(t * 0.05 + h.x * 15.0) * 0.04;
            pt.y += cos(t * 0.04 + h.y * 15.0) * 0.04;
            float d = dot(pt - f, pt - f);
            if (d < minDist) { secondDist = minDist; minDist = d; nearestCell = cid; }
            else if (d < secondDist) { secondDist = d; }
        }
    }

    float edge = sqrt(secondDist) - sqrt(minDist);
    return float3(sqrt(minDist), edge, gf_hash(nearestCell + float2(50.0)));
}

// ── Micro-crack Voronoi (3x3) ──
static float3 gf_microVoronoi(float2 p, float t) {
    float2 i = floor(p);
    float2 f = fract(p);
    float minDist = 10.0;
    float secondDist = 10.0;
    float2 nearestCell = float2(0.0);

    for (int jy = -1; jy <= 1; jy++) {
        for (int jx = -1; jx <= 1; jx++) {
            float2 nb = float2(float(jx), float(jy));
            float2 cid = i + nb;
            float2 h = gf_hash2(cid + float2(200.0));
            float2 pt = nb + h * 0.75 + 0.125;
            pt.x += sin(t * 0.03 + h.x * 10.0) * 0.03;
            pt.y += cos(t * 0.025 + h.y * 10.0) * 0.03;
            float d = dot(pt - f, pt - f);
            if (d < minDist) { secondDist = minDist; minDist = d; nearestCell = cid; }
            else if (d < secondDist) { secondDist = d; }
        }
    }

    float edge = sqrt(secondDist) - sqrt(minDist);
    return float3(sqrt(minDist), edge, gf_hash(nearestCell + float2(200.0)));
}

// ── Crack reveal animation ──
static float gf_crackReveal(float cellHash, float t) {
    float phase = cellHash * GF_PI * 2.0;
    float cycle = t * 0.12;
    float reveal = sin(cycle + phase) * 0.5 + 0.5;
    reveal *= sin(cycle * 0.7 + phase * 1.3) * 0.3 + 0.7;
    reveal = smoothstep(0.15, 0.65, reveal);
    return reveal;
}

// ── Gold dust particles ──
static float gf_goldDust(float2 p, float t, float crackProximity) {
    float dust = 0.0;
    float2 dp1 = p * 30.0 + float2(t * 0.2, t * 0.15);
    float d1 = gf_noise(dp1);
    d1 = smoothstep(0.72, 0.78, d1);
    dust += d1 * 0.6;

    float2 dp2 = p * 55.0 + float2(-t * 0.3, t * 0.25);
    float d2 = gf_noise(dp2);
    d2 = smoothstep(0.78, 0.82, d2);
    dust += d2 * 0.4;

    float2 dp3 = p * 18.0 + float2(t * 0.08, -t * 0.12);
    float d3 = gf_noise(dp3);
    d3 = smoothstep(0.82, 0.86, d3);
    d3 *= 0.5 + 0.5 * sin(t * 2.0 + d3 * 20.0);
    dust += d3 * 0.8;

    dust *= crackProximity;
    return dust;
}

fragment float4 fs_gilded_fracture(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.pos.xy;
    float2 p = (fragCoord - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * GF_CRACK_SPEED;

    // Multi-scale Voronoi crack network (no mouse shift in screensaver)
    float3 coarse = gf_kintsugiVoronoi(p * 2.5, t, 0.6);
    float coarseEdge = coarse.y;
    float coarseCellHash = coarse.z;

    float3 medium = gf_fineVoronoi(p * 5.5, t);
    float mediumEdge = medium.y;
    float mediumCellHash = medium.z;

    float3 micro = gf_microVoronoi(p * 14.0, t);
    float microEdge = micro.y;

    // Crack reveal animation
    float coarseReveal = gf_crackReveal(coarseCellHash, t);
    float mediumReveal = gf_crackReveal(mediumCellHash, t * 1.3 + 1.0);
    float microReveal = mix(coarseReveal, mediumReveal, 0.5);

    // Crack line intensities
    float coarseCrack = smoothstep(0.08, 0.0, coarseEdge) * coarseReveal;
    float coarseGlow  = smoothstep(0.22, 0.0, coarseEdge) * coarseReveal;
    float coarseBloom = smoothstep(0.45, 0.0, coarseEdge) * coarseReveal;

    float medCrack = smoothstep(0.06, 0.0, mediumEdge) * mediumReveal * 0.7;
    float medGlow  = smoothstep(0.16, 0.0, mediumEdge) * mediumReveal * 0.5;

    float microCrack = smoothstep(0.04, 0.0, microEdge) * microReveal * 0.25;
    float microGlow  = smoothstep(0.10, 0.0, microEdge) * microReveal * 0.15;

    float crackCore = max(coarseCrack, max(medCrack, microCrack));
    float crackGlow = max(coarseGlow, max(medGlow, microGlow));
    float crackBloom = coarseBloom;

    // Dark ceramic surface
    float3 darkBase = float3(0.03, 0.025, 0.02);
    float3 darkTex  = float3(0.06, 0.045, 0.03);

    float grain = gf_fbm(p * 8.0 + coarseCellHash * 40.0);
    float fineGrain = gf_noise(p * 30.0 + mediumCellHash * 60.0) * 0.5;

    float plateTone = 0.3 + grain * 0.4 + fineGrain * 0.3;
    float3 surface = mix(darkBase, darkTex, plateTone);

    float3 plateHighlight = float3(0.10, 0.07, 0.04);
    float edgeHighlight = smoothstep(0.5, 0.15, coarse.x) * 0.3;
    surface += plateHighlight * edgeHighlight;

    // Golden crack coloring
    float3 goldCore   = float3(1.0, 0.82, 0.55);
    float3 goldEdge   = float3(0.78, 0.58, 0.24);
    float3 goldHot    = float3(1.0, 0.92, 0.72);

    float flowTurb = gf_fbm(p * 6.0 + t * float2(0.08, -0.06));
    float flowTurb2 = gf_fbm(p * 10.0 + t * float2(-0.05, 0.07) + float2(30.0, 0.0));
    float moltenFlow = flowTurb * 0.6 + flowTurb2 * 0.4;

    float goldTemp = crackCore * (0.6 + moltenFlow * 0.4);
    goldTemp = clamp(goldTemp, 0.0, 1.0);

    float3 goldColor = mix(goldEdge, goldCore, smoothstep(0.2, 0.6, goldTemp));
    goldColor = mix(goldColor, goldHot, smoothstep(0.6, 1.0, goldTemp));

    float emissive = smoothstep(0.3, 1.0, crackCore);
    goldColor += goldHot * emissive * emissive * 0.5;

    // Composite: surface + gold
    float3 warmCast = goldEdge * crackGlow * 0.4 * GF_GLOW_INTENSITY;
    surface += warmCast;
    surface += float3(0.12, 0.08, 0.03) * crackBloom * 0.25 * GF_GLOW_INTENSITY;

    float blendFactor = smoothstep(0.0, 0.12, crackCore);
    float3 col = mix(surface, goldColor, blendFactor);
    col += goldEdge * crackGlow * 0.3 * GF_GLOW_INTENSITY;

    // Gold dust particles
    float crackProximity = smoothstep(0.5, 0.0, coarseEdge) * coarseReveal;
    crackProximity = max(crackProximity, smoothstep(0.3, 0.0, mediumEdge) * mediumReveal * 0.5);
    float dust = gf_goldDust(p, u.time, crackProximity);
    col += goldHot * dust * 0.35 * GF_GLOW_INTENSITY;

    // Subsurface warmth
    float subsurface = crackBloom * 0.15 * GF_GLOW_INTENSITY;
    col += float3(0.08, 0.05, 0.02) * subsurface;

    // Breathing
    float breathe = sin(u.time * 0.15) * 0.08 + 0.92;
    col *= breathe;

    // Vignette
    float edgeDist = length(p * float2(1.0, 1.1));
    float vignette = 1.0 - smoothstep(0.4, 1.3, edgeDist);
    col *= 0.5 + vignette * 0.5;

    // Tone mapping
    col = col / (1.0 + col * 0.15);

    // Push warm
    col = pow(max(col, float3(0.0)), float3(0.95, 1.0, 1.1));

    // Contrast
    col = clamp(col, float3(0.0), float3(1.0));
    col = col * col * (3.0 - 2.0 * col) * 0.7 + col * 0.3;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
