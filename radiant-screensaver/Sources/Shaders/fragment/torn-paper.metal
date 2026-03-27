#include "../Common.metal"

// ─── Torn Paper: Paper tearing apart to reveal warm light beneath ───
// Ported from static/torn-paper.html

// Default parameter values (screensaver — no interactive controls)
constant float TP_TEAR_SPEED = 1.0;
constant float TP_GLOW_INTENSITY = 1.0;
constant float TP_PI = 3.14159265359;
constant float TP_CYCLE_DURATION = 7.0;

// ── Hash functions ──
static float tp_hash(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float2 tp_hash2(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((float2(p3.x, p3.x) + float2(p3.y, p3.z)) * float2(p3.z, p3.y));
}

// ── Smooth value noise ──
static float tp_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(
        mix(tp_hash(i), tp_hash(i + float2(1.0, 0.0)), f.x),
        mix(tp_hash(i + float2(0.0, 1.0)), tp_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// ── FBM ──
static float tp_fbm(float2 p, int octaves) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        v += a * tp_vnoise(p);
        p = rot * p * 2.1 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// ── High-detail FBM for fibrous tear edges ──
static float tp_fibrousFbm(float2 p) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 7; i++) {
        v += a * tp_vnoise(p);
        p = rot * p * 2.0 + float2(3.1, 7.4);
        a *= 0.52;
    }
    return v;
}

// ── Phase calculation ──
static float2 tp_getPhase(float t, float speed) {
    float cycle = TP_CYCLE_DURATION / speed;
    float lt = t - cycle * floor(t / cycle);
    float norm = lt / cycle;

    float p0 = 1.5 / 7.0;
    float p1 = p0 + 1.5 / 7.0;
    float p2 = p1 + 2.0 / 7.0;

    if (norm < p0) return float2(norm / p0, 0.0);
    if (norm < p1) return float2((norm - p0) / (p1 - p0), 1.0);
    if (norm < p2) return float2((norm - p1) / (p2 - p1), 2.0);
    return float2((norm - p2) / (1.0 - p2), 3.0);
}

// ── Easing functions ──
static float tp_easeInQuad(float t) { return t * t; }
static float tp_easeOutCubic(float t) { float f = t - 1.0; return f * f * f + 1.0; }
static float tp_easeInOutCubic(float t) {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0;
}

// ── Tear line distance ──
static float tp_tearLine(float2 uv, float tearProgress, float cycleIndex) {
    float2 rnd = tp_hash2(float2(cycleIndex * 17.31, cycleIndex * 43.71));
    float2 impactPoint = float2(rnd.x * 0.6 - 0.3, rnd.y * 0.4 - 0.2);

    float tearAngle = (rnd.x - 0.5) * 0.5;
    float2 tearDir = normalize(float2(cos(tearAngle), sin(tearAngle * 0.3)));

    float2 relUV = uv - impactPoint;
    float along = dot(relUV, tearDir);
    float perp = dot(relUV, float2(-tearDir.y, tearDir.x));

    float roughness = tp_fibrousFbm(float2(along * 8.0 + cycleIndex * 7.0, perp * 3.0)) * 0.12;
    roughness += tp_fibrousFbm(float2(along * 22.0 + cycleIndex * 13.0, perp * 8.0)) * 0.04;
    roughness += tp_vnoise(float2(along * 50.0 + cycleIndex * 19.0, perp * 15.0)) * 0.015;

    float line = perp + roughness - 0.01;
    return line;
}

// ── Tear gap width ──
static float tp_tearGap(float2 uv, float tearProgress, float cycleIndex) {
    float2 rnd = tp_hash2(float2(cycleIndex * 17.31, cycleIndex * 43.71));
    float2 impactPoint = float2(rnd.x * 0.6 - 0.3, rnd.y * 0.4 - 0.2);
    float tearAngle = (rnd.x - 0.5) * 0.5;
    float2 tearDir = normalize(float2(cos(tearAngle), sin(tearAngle * 0.3)));

    float2 relUV = uv - impactPoint;
    float along = dot(relUV, tearDir);
    float distFromImpact = length(relUV);

    float propagation = tearProgress * 2.5;
    float reachFactor = smoothstep(propagation, propagation - 0.4, distFromImpact);

    float gapWidth = reachFactor * tearProgress * 0.18;
    gapWidth *= smoothstep(0.0, 0.3, tearProgress);

    float centerBoost = 1.0 - smoothstep(0.0, 0.8, distFromImpact);
    gapWidth *= 1.0 + centerBoost * 0.5;

    return gapWidth;
}

// ── Paper surface texture ──
static float3 tp_paperSurface(float2 uv, float t) {
    float3 paperBase = float3(0.88, 0.85, 0.80);

    float grain1 = tp_vnoise(uv * 40.0) * 0.04;
    float grain2 = tp_vnoise(uv * 80.0 + float2(5.5, 3.3)) * 0.02;
    float grain3 = tp_vnoise(uv * 160.0 + float2(11.1, 7.7)) * 0.01;
    float grain = grain1 + grain2 + grain3;

    float fiber = tp_vnoise(float2(uv.x * 3.0, uv.y * 60.0)) * 0.015;
    fiber += tp_vnoise(float2(uv.x * 5.0, uv.y * 100.0 + 33.0)) * 0.008;

    float warmPatch = tp_fbm(uv * 2.5, 3);
    float3 warmTint = mix(float3(0.88, 0.85, 0.80), float3(0.90, 0.86, 0.78), warmPatch);

    float3 col = warmTint - grain - fiber;

    float crumple = tp_fbm(uv * 5.0 + t * 0.003, 4);
    col *= 0.95 + crumple * 0.1;

    float edgeDark = smoothstep(0.4, 1.1, length(uv * 0.8));
    col -= edgeDark * 0.06;

    return col;
}

// ── Glow underneath — living plasma nebula ──
static float3 tp_underGlow(float2 uv, float t, float intensity) {
    float3 deep = float3(0.04, 0.01, 0.06);

    float2 warp1 = float2(
        tp_fbm(uv * 2.0 + float2(t * 0.06, t * 0.04), 4),
        tp_fbm(uv * 2.0 + float2(t * 0.05 + 5.2, t * 0.03 + 1.3), 4)
    );
    float2 warp2 = float2(
        tp_fbm(uv * 3.0 + warp1 * 1.8 + float2(t * 0.04 + 1.7, 0.0), 4),
        tp_fbm(uv * 3.0 + warp1 * 1.8 + float2(0.0, t * 0.035 + 9.2), 4)
    );
    float plasma = tp_fbm(uv * 2.5 + warp2 * 1.5, 5);

    float3 c1 = float3(0.12, 0.02, 0.18);
    float3 c2 = float3(0.55, 0.05, 0.45);
    float3 c3 = float3(0.95, 0.25, 0.35);
    float3 c4 = float3(1.0, 0.60, 0.12);
    float3 c5 = float3(1.0, 0.90, 0.50);
    float p = clamp(plasma, 0.0, 1.0);
    float3 nebula = p < 0.25 ? mix(c1, c2, p / 0.25)
        : p < 0.5 ? mix(c2, c3, (p - 0.25) / 0.25)
        : p < 0.75 ? mix(c3, c4, (p - 0.5) / 0.25)
        : mix(c4, c5, (p - 0.75) / 0.25);

    // Flowing veins of light
    float2 veinUV = uv * 5.0 + warp1 * 2.0 + float2(t * 0.07, -t * 0.05);
    float vein = tp_fbm(veinUV, 5);
    vein = 1.0 - abs(vein * 2.0 - 1.0);
    vein = pow(vein, 4.0);
    float2 veinUV2 = uv * 8.0 + warp2 * 1.5 + float2(-t * 0.05, t * 0.06);
    float vein2 = tp_fbm(veinUV2, 4);
    vein2 = 1.0 - abs(vein2 * 2.0 - 1.0);
    vein2 = pow(vein2, 5.0);
    float3 veinCol = float3(1.0, 0.45, 0.6) * vein * 0.7
                   + float3(1.0, 0.7, 0.2) * vein2 * 0.5;

    // Sparkle / star points
    float2 sparkleUV = uv * 25.0 + float2(t * 0.1, -t * 0.08);
    float sparkleNoise = tp_vnoise(sparkleUV);
    float2 sparkleCell = floor(sparkleUV);
    float twinklePhase = tp_hash(sparkleCell) * 6.28;
    float twinkle = sin(t * (1.5 + tp_hash(sparkleCell + 0.5) * 3.0) + twinklePhase);
    twinkle = twinkle * 0.5 + 0.5;
    float sparkle = smoothstep(0.78, 0.92, sparkleNoise) * twinkle;
    sparkle = pow(sparkle, 2.0) * 1.5;
    float3 sparkleCol = mix(float3(1.0, 0.85, 0.95), float3(1.0, 0.95, 0.7), tp_hash(sparkleCell + 1.0));

    // Animated glow centers
    float2 glowUV = uv + float2(sin(t * 0.15) * 0.12, cos(t * 0.12) * 0.1);
    float g1 = exp(-dot(glowUV, glowUV) * 1.5);
    float2 g2uv = glowUV - float2(0.25 + sin(t * 0.1) * 0.05, -0.2);
    float g2 = exp(-dot(g2uv, g2uv) * 2.2);
    float2 g3uv = glowUV + float2(0.3, 0.25 + cos(t * 0.08) * 0.05);
    float g3 = exp(-dot(g3uv, g3uv) * 2.8);
    float3 glowCenters = float3(1.0, 0.6, 0.15) * g1 * 0.5
                       + float3(0.75, 0.15, 0.55) * g2 * 0.4
                       + float3(0.4, 0.1, 0.5) * g3 * 0.3;

    // Pulsating energy
    float pulse = sin(t * 0.8) * 0.1 + sin(t * 1.3 + 1.5) * 0.06;
    pulse += sin(t * 0.3) * 0.04;

    // Combine
    float3 glow = deep;
    glow += nebula * 0.7;
    glow += glowCenters;
    glow += veinCol * intensity;
    glow += sparkleCol * sparkle * intensity;
    glow *= (1.0 + pulse) * intensity;

    return glow;
}

// ── Edge glow ──
static float3 tp_edgeGlow(float tearDist, float gapWidth, float tearProgress, float intensity) {
    float absDist = abs(tearDist);

    float innerGlow = smoothstep(gapWidth * 0.8, 0.0, absDist);
    innerGlow = pow(innerGlow, 1.5);
    float3 inner = float3(1.0, 0.85, 0.6) * innerGlow * 1.2;

    float midGlow = smoothstep(gapWidth * 2.5, gapWidth * 0.3, absDist);
    midGlow = pow(midGlow, 2.0);
    float3 mid = float3(0.8, 0.4, 0.15) * midGlow * 0.6;

    float outerGlow = smoothstep(gapWidth * 5.0, gapWidth, absDist);
    outerGlow = pow(outerGlow, 3.0);
    float3 outer = float3(0.5, 0.15, 0.3) * outerGlow * 0.25;

    return (inner + mid + outer) * tearProgress * intensity;
}

// ── Paper curl effect ──
static float3 tp_paperCurl(float3 paperCol, float tearDist, float gapWidth, float tearProgress) {
    float absDist = abs(tearDist);
    float curlZone = smoothstep(gapWidth * 3.0, gapWidth * 0.5, absDist);

    float side = sign(tearDist);
    float shadow = curlZone * smoothstep(gapWidth * 2.0, gapWidth * 0.8, absDist) * 0.3;
    float highlight = curlZone * smoothstep(gapWidth * 1.5, gapWidth * 0.6, absDist) * 0.15;

    paperCol -= shadow * (0.5 + 0.5 * side) * tearProgress;
    paperCol += highlight * (0.5 - 0.5 * side) * tearProgress;

    float warmLight = curlZone * tearProgress * 0.2;
    paperCol += float3(0.15, 0.06, 0.02) * warmLight;

    return paperCol;
}

fragment float4 fs_torn_paper(VSOut in [[stage_in]],
                               constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float speed = TP_TEAR_SPEED;
    float glowInt = TP_GLOW_INTENSITY;

    // ── Determine animation phase ──
    float cycle = TP_CYCLE_DURATION / speed;
    float cycleIndex = floor(t / cycle);
    float2 phase = tp_getPhase(t, speed);
    float phaseT = phase.x;
    float phaseId = phase.y;

    // ── Calculate tear progress ──
    float tearProgress = 0.0;
    if (phaseId < 0.5) {
        tearProgress = 0.0;
    } else if (phaseId < 1.5) {
        tearProgress = tp_easeInQuad(phaseT);
    } else if (phaseId < 2.5) {
        tearProgress = 1.0;
    } else {
        tearProgress = 1.0 - tp_easeInOutCubic(phaseT);
    }

    // ── Tear geometry ──
    float tearDist = tp_tearLine(uv, tearProgress, cycleIndex);
    float gapWidth = tp_tearGap(uv, tearProgress, cycleIndex);

    float inGap = smoothstep(gapWidth * 0.5 + 0.003, gapWidth * 0.5 - 0.003, abs(tearDist));
    inGap *= step(0.01, tearProgress);

    // ── Paper separation offset ──
    float separationAmount = tearProgress * 0.03;
    float side = sign(tearDist);
    float2 paperOffset = float2(0.0);

    if (phaseId > 1.5 && phaseId < 2.5) {
        float settle = sin(phaseT * TP_PI) * 0.005;
        separationAmount += settle;
    }

    float2 rnd = tp_hash2(float2(cycleIndex * 17.31, cycleIndex * 43.71));
    float tearAngle = (rnd.x - 0.5) * 0.5;
    float2 tearPerp = float2(-sin(tearAngle * 0.3), cos(tearAngle * 0.3));
    paperOffset = tearPerp * side * separationAmount;

    // ── Render paper surface with offset ──
    float3 paper = tp_paperSurface(uv + paperOffset, t);

    // ── Apply curl effect ──
    paper = tp_paperCurl(paper, tearDist, max(gapWidth, 0.01), tearProgress);

    // ── Render the glow underneath ──
    float3 glow = tp_underGlow(uv, t, glowInt);

    // ── Edge glow bleeding onto paper ──
    float3 eGlow = tp_edgeGlow(tearDist, max(gapWidth, 0.005), tearProgress, glowInt);

    // ── Composite ──
    float3 col = mix(paper + eGlow, glow, inGap);

    // ── During calm phase ──
    if (phaseId < 0.5) {
        float breathe = sin(phaseT * TP_PI * 2.0) * 0.02 + 0.01;
        float centerGlow = exp(-dot(uv, uv) * 4.0);
        col += float3(0.15, 0.06, 0.08) * centerGlow * breathe * glowInt;

        float creak = sin(phaseT * TP_PI) * 0.003;
        col = tp_paperSurface(uv + float2(creak, 0.0), t);
        col += float3(0.15, 0.06, 0.08) * centerGlow * breathe * glowInt;
    }

    // ── Crack formation hint ──
    if (phaseId < 0.5 && phaseT > 0.7) {
        float crackHint = (phaseT - 0.7) / 0.3;
        crackHint = tp_easeInQuad(crackHint);
        float crackLine = tp_tearLine(uv, 0.01, cycleIndex);
        float crackVis = smoothstep(0.008, 0.0, abs(crackLine)) * crackHint * 0.3;
        col -= crackVis * 0.15;
        col += float3(0.4, 0.15, 0.1) * crackVis * glowInt;
    }

    // ── Vignette ──
    float vig = length(uv * float2(0.8, 0.9));
    float vignette = 1.0 - smoothstep(0.5, 1.3, vig);
    vignette = vignette * 0.8 + 0.2;
    col *= vignette;

    // ── Film grain ──
    float filmGrain = (tp_hash(in.pos.xy + fract(t * 43.0) * 1000.0) - 0.5) * 0.025;
    col += filmGrain;

    // ── Tone mapping ──
    col = max(col, float3(0.0));
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(col, col * float3(1.05, 0.95, 0.9), smoothstep(0.1, 0.0, lum) * 0.3);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
