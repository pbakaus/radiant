#include "../Common.metal"

// ─── Radiant Geometry: Unified parametric golden geometry ───
// Ported from static/radiant-geometry.html

// Default parameter values (screensaver — no interactive controls)
constant float RG_ROTATION_SPEED = 0.3;
constant float RG_COMPLEXITY = 1.0;
constant float RG_PATTERN = 0.05;

constant float RG_PI = 3.14159265359;
constant float RG_TAU = 6.28318530718;
constant float RG_PHI = 1.6180339887;
constant float RG_SQRT3 = 1.7320508;

// ── Rotation matrix ──
static float2x2 rg_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// ── Golden color palette ──
static float3 rg_gold(float t) {
    float3 a = float3(0.45, 0.32, 0.14);
    float3 b = float3(0.45, 0.35, 0.2);
    float3 c = float3(1.0, 0.8, 0.5);
    float3 d = float3(0.0, 0.1, 0.25);
    return a + b * cos(RG_TAU * (c * t + d));
}

// ── Polar fold ──
static float2 rg_polarFold(float2 p, float n) {
    float angle = atan2(p.y, p.x);
    float sector = RG_TAU / n;
    // Safe mod for potentially negative angle
    angle = (angle + sector * 0.5) - sector * floor((angle + sector * 0.5) / sector) - sector * 0.5;
    angle = abs(angle);
    float r = length(p);
    return float2(cos(angle), sin(angle)) * r;
}

// ── SDF: line segment ──
static float rg_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// ── SDF: circle ring ──
static float rg_sdRing(float2 p, float r) {
    return abs(length(p) - r);
}

// ── SDF: regular polygon outline ──
static float rg_sdPolygon(float2 p, float r, float n) {
    float angle = atan2(p.y, p.x);
    float sector = RG_TAU / n;
    // Safe mod
    float a = (angle + sector * 0.5) - sector * floor((angle + sector * 0.5) / sector) - sector * 0.5;
    float rp = length(p);
    float2 q = float2(cos(a), abs(sin(a))) * rp;
    float2 edge = float2(cos(sector * 0.5), sin(sector * 0.5)) * r;
    float2 d = q - edge * clamp(dot(q, edge) / dot(edge, edge), 0.0, 1.0);
    return length(d) * sign(q.x * edge.y - q.y * edge.x);
}

// ── Convert SDF distance to glowing line ──
static float3 rg_glowLine(float d, float3 coreColor, float3 bloomColor, float lineWidth, float bloomWidth) {
    float core = lineWidth / (abs(d) + lineWidth);
    core = pow(core, 2.0);
    float bloom = bloomWidth / (abs(d) + bloomWidth);
    bloom = pow(bloom, 1.5);
    return coreColor * core + bloomColor * bloom * 0.4;
}

// ── Star motif ──
static float rg_starMotif(float2 p, float symmetry, float breathe, float innerRatio, float petalInfluence) {
    float d = 1e9;
    float doubleSym = symmetry * 2.0;
    float2 fp = rg_polarFold(p, doubleSym);

    float2 a1 = float2(0.5 * breathe, 0.0);
    float2 b1 = float2(mix(0.35, 0.32, innerRatio) * breathe, mix(0.15, 0.13, innerRatio) * breathe);
    d = min(d, rg_sdSegment(fp, a1, b1));

    float innerR = mix(0.22, 0.18, innerRatio);
    float2 a2 = b1;
    float2 b2 = float2(innerR * breathe, 0.0);
    d = min(d, rg_sdSegment(fp, a2, b2));

    float2 a3 = b2;
    float2 b3 = float2(mix(0.12, 0.10, innerRatio) * breathe, mix(0.07, 0.06, innerRatio) * breathe);
    d = min(d, rg_sdSegment(fp, a3, b3));

    float2 a4 = b3;
    float2 b4 = float2(0.0, 0.0);
    d = min(d, rg_sdSegment(fp, a4, b4));

    d = min(d, rg_sdRing(p, 0.5 * breathe));
    d = min(d, rg_sdRing(p, innerR * breathe));

    if (petalInfluence > 0.01) {
        float petalR = 0.5 * breathe * 0.35 / RG_PHI;
        float2 petalCenter = float2(0.5 * breathe, 0.0);
        float petal = abs(length(fp - petalCenter) - petalR) - 0.002;
        d = min(d, mix(1e9, petal, petalInfluence));

        float2 innerPetalCenter = float2(0.5 * breathe * 0.65, 0.0);
        float innerPetalR = 0.5 * breathe * 0.25;
        float innerPetal = abs(length(fp - innerPetalCenter) - innerPetalR) - 0.0015;
        d = min(d, mix(1e9, innerPetal, petalInfluence));
    }

    return d;
}

// ── Hex-tile a motif ──
static float rg_hexTileMotif(float2 p, float scale, float symmetry, float breathe, float innerRatio, float petalInfl) {
    p *= scale;
    float2 s = float2(1.0, RG_SQRT3);
    float2 h = s * 0.5;
    // Safe mod for potentially negative p
    float2 a = float2(p.x - s.x * floor(p.x / s.x), p.y - s.y * floor(p.y / s.y)) - h;
    float2 ph = p - h;
    float2 b = float2(ph.x - s.x * floor(ph.x / s.x), ph.y - s.y * floor(ph.y / s.y)) - h;
    float2 gUV = dot(a, a) < dot(b, b) ? a : b;
    float d = rg_starMotif(gUV, symmetry, breathe, innerRatio, petalInfl);
    return d / scale;
}

// ── Central motif (no tiling) ──
static float rg_centralMotif(float2 p, float scale, float symmetry, float breathe, float innerRatio, float petalInfl) {
    p *= scale;
    float d = rg_starMotif(p, symmetry, breathe, innerRatio, petalInfl);
    return d / scale;
}

// ── Unified geometry layer ──
static float rg_geometryLayer(float2 p, float scale, float symmetry, float breathe, float innerRatio, float petalInfl, float tilingMix) {
    float tiledScale = scale;
    float centralScale = scale * 0.35;
    float effectiveScale = mix(tiledScale, centralScale, tilingMix);

    if (tilingMix < 0.01) {
        return rg_hexTileMotif(p, effectiveScale, symmetry, breathe, innerRatio, petalInfl);
    } else if (tilingMix > 0.99) {
        return rg_centralMotif(p, effectiveScale, symmetry, breathe, innerRatio, petalInfl);
    } else {
        float dTiled = rg_hexTileMotif(p, mix(tiledScale, tiledScale * 0.6, tilingMix), symmetry, breathe, innerRatio, petalInfl);
        float dCentral = rg_centralMotif(p, mix(centralScale * 1.5, centralScale, tilingMix), symmetry, breathe, innerRatio, petalInfl);
        return mix(dTiled, dCentral, tilingMix);
    }
}

// ── Golden spiral SDF ──
static float rg_goldenSpiral(float2 uv, float t, float rotSpd) {
    float r = length(uv);
    float a = atan2(uv.y, uv.x);
    float spiralPhase = log(max(r, 0.001)) / log(RG_PHI) * RG_PI * 0.5;
    // Safe mod
    float v1 = a - spiralPhase + t * rotSpd * 0.2 + RG_PI;
    float spiralD = abs(v1 - RG_TAU * floor(v1 / RG_TAU) - RG_PI);
    float v2 = v1 + RG_PI;
    spiralD = min(spiralD, abs(v2 - RG_TAU * floor(v2 / RG_TAU) - RG_PI));
    float fade = smoothstep(0.0, 0.05, r) * smoothstep(0.5, 0.35, r);
    return spiralD * fade + (1.0 - fade);
}

fragment float4 fs_radiant_geometry(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    // No mouse — skip drag rotation
    float t = u.time;
    float rotSpeed = RG_ROTATION_SPEED;
    float complexity = RG_COMPLEXITY;
    float pat = clamp(RG_PATTERN, 0.0, 1.0);
    float r = length(uv);

    float tilingMix = pat;
    float baseSym = mix(6.0, 10.0, pat);
    float spiralInfluence = smoothstep(0.2, 0.8, pat);
    float centralGlowStr = mix(0.03, 0.12, pat);
    float petalInfluence = smoothstep(0.3, 0.9, pat);
    float objectRadius = mix(1.0, 0.48, pat * pat);
    float objectFade = mix(1.0, smoothstep(objectRadius, objectRadius * 0.7, r), pat);
    float breathe = 1.0 + 0.03 * sin(t * 0.6);

    float3 dimGold = float3(0.35, 0.25, 0.12);
    float3 medGold = float3(0.7, 0.50, 0.22);
    float3 brightGold = float3(0.95, 0.72, 0.32);
    float3 coreGlow = float3(1.0, 0.82, 0.55);
    float3 hotGold = float3(1.0, 0.92, 0.72);

    float3 col = float3(0.02, 0.015, 0.01);

    float numLayers = 2.0 + (complexity - 0.3) * (4.0 / 1.7);
    numLayers = clamp(numLayers, 2.0, 6.0);

    // LAYER 1
    {
        float sym1 = floor(baseSym);
        float rot1 = t * rotSpeed * 0.04;
        float2 p1 = rg_rot(rot1) * uv;
        float scale1 = mix(2.5, 1.8, pat) * complexity;
        float d1 = rg_geometryLayer(p1, scale1, sym1, breathe, 0.0, petalInfluence * 0.3, tilingMix);
        col += rg_glowLine(d1, medGold, dimGold * 1.5, 0.002, 0.016);
    }

    // LAYER 2
    if (numLayers > 2.0) {
        float sym2 = floor(baseSym + 2.0);
        float rot2 = -t * rotSpeed * 0.06;
        float2 p2 = rg_rot(rot2) * uv;
        float scale2 = mix(3.5, 2.2, pat) * complexity;
        float innerR2 = mix(0.3, 0.6, pat);
        float d2 = rg_geometryLayer(p2, scale2, sym2, breathe, innerR2, petalInfluence * 0.5, tilingMix);
        float layer2alpha = min(numLayers - 2.0, 1.0);
        col += rg_glowLine(d2, brightGold * 0.8, dimGold * 1.2, 0.0015, 0.014) * layer2alpha;
    }

    // LAYER 3
    if (numLayers > 3.0) {
        float sym3 = floor(mix(5.0, 8.0, pat));
        float rot3 = t * rotSpeed * 0.09;
        float2 p3 = rg_rot(rot3) * uv;
        float scale3 = mix(4.0, 2.5, pat) * complexity;
        float d3 = rg_geometryLayer(p3, scale3, sym3, breathe * (1.0 + 0.01 * sin(t * 0.5 + 2.0)), 0.5, petalInfluence * 0.7, tilingMix);
        float layer3alpha = min(numLayers - 3.0, 1.0);
        col += rg_glowLine(d3, coreGlow * 0.6, medGold * 0.7, 0.0012, 0.012) * layer3alpha;
    }

    // LAYER 4
    if (numLayers > 4.0) {
        float sym4 = floor(mix(8.0, 12.0, pat));
        float rot4 = t * rotSpeed * mix(0.03, 0.05, pat);
        float2 p4 = rg_rot(rot4) * uv;
        float d4 = rg_centralMotif(p4, mix(2.2, 1.8, pat), sym4, breathe, 0.7, petalInfluence);
        float centralFade = smoothstep(mix(0.5, 0.48, pat), 0.12, r);
        float layer4alpha = min(numLayers - 4.0, 1.0);
        col += rg_glowLine(d4, hotGold * 0.7, coreGlow * 0.5, 0.0025, 0.022) * centralFade * layer4alpha;
    }

    // LAYER 5
    if (numLayers > 5.0) {
        float ringBreath = 1.0 + 0.04 * sin(t * 0.4);
        float rScale = mix(0.12, 0.10, pat) * ringBreath;
        float ringD = 1e9;
        float polySides1 = mix(6.0, 8.0, pat);
        float polySides2 = mix(8.0, 10.0, pat);
        float pr0 = abs(rg_sdPolygon(rg_rot(t * rotSpeed * 0.02) * uv, rScale * 1.0, polySides1));
        float pr1 = abs(rg_sdPolygon(rg_rot(-t * rotSpeed * 0.025) * uv, rScale * 2.0, polySides2));
        float pr2 = abs(rg_sdPolygon(rg_rot(t * rotSpeed * 0.015) * uv, rScale * 3.0, 12.0));
        float pr3 = abs(rg_sdPolygon(rg_rot(-t * rotSpeed * 0.018) * uv, rScale * 4.0, polySides1));
        ringD = min(ringD, pr0);
        ringD = min(ringD, pr1);
        ringD = min(ringD, pr2);
        ringD = min(ringD, pr3);
        float layer5alpha = min(numLayers - 5.0, 1.0);
        col += rg_glowLine(ringD, brightGold * 0.5, dimGold * 0.5, 0.0012, 0.01) * layer5alpha;
    }

    // Golden spiral arms
    if (spiralInfluence > 0.01) {
        float spiral = rg_goldenSpiral(uv, t, rotSpeed);
        float spiralGlow = 0.015 / (spiral + 0.015);
        col += rg_gold(0.7 + t * 0.01) * spiralGlow * 0.25 * spiralInfluence;
    }

    // Decorative elements
    if (pat > 0.3) {
        float decoFade = smoothstep(0.3, 0.7, pat);

        float outerRing = abs(r - objectRadius + 0.01) - 0.003;
        float outerGlow = 0.004 / (abs(outerRing) + 0.004);
        col += rg_gold(0.5 + t * 0.015) * outerGlow * 0.35 * decoFade;

        float outerRing2 = abs(r - objectRadius + 0.035) - 0.002;
        float outerGlow2 = 0.003 / (abs(outerRing2) + 0.003);
        col += rg_gold(0.6) * outerGlow2 * 0.2 * decoFade;

        float dotAngle = atan2(uv.y, uv.x);
        float dotSymmetry = mix(6.0, 12.0, pat);
        // Safe mod
        float dotA = (dotAngle + RG_PI / dotSymmetry) - (RG_TAU / dotSymmetry) * floor((dotAngle + RG_PI / dotSymmetry) / (RG_TAU / dotSymmetry)) - RG_PI / dotSymmetry;
        float2 dotP = float2(cos(dotA), sin(dotA)) * r;
        float2 dotCenter = float2(objectRadius - 0.01, 0.0);
        float dotD = length(dotP - dotCenter) - 0.008;
        float dotGlow = 0.004 / (abs(dotD) + 0.004);
        col += float3(1.0, 0.9, 0.65) * dotGlow * 0.3 * decoFade;
    }

    // Center pulse
    float centerPulse = 0.8 + 0.2 * sin(t * 1.5);
    float centerGlowD = exp(-r * r * mix(3.0, 6.0, pat)) * centralGlowStr * 2.0 * centerPulse;
    col += hotGold * centerGlowD;

    // Inner center ring
    if (pat > 0.2) {
        float ringPulse = 0.9 + 0.1 * sin(t * 2.3 + 1.0);
        float innerRing = abs(r - 0.03 * ringPulse) - 0.002;
        float innerRingGlow = 0.003 / (abs(innerRing) + 0.003);
        col += float3(1.0, 0.88, 0.6) * innerRingGlow * 0.3 * smoothstep(0.2, 0.6, pat);
    }

    // Ambient radial glow
    float ambientGlow = exp(-r * r * mix(2.5, 4.0, pat)) * mix(0.1, 0.14, pat);
    col += float3(0.5, 0.35, 0.16) * ambientGlow;

    // Object mask
    col *= objectFade;

    // Subtle pulse
    float pulse = 0.92 + 0.08 * sin(t * 0.3);
    col *= pulse;

    // Vignette
    float vig = 1.0 - r * r * mix(0.35, 0.25, pat);
    vig = max(vig, 0.0);
    col *= (0.65 + vig * 0.35);

    // Tone mapping
    col = col / (1.0 + col * 0.3);

    // Warmth boost
    col = pow(col, float3(0.95, 0.98, 1.06));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
