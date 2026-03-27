#include "../Common.metal"

// ─── Golden Throne: Sacred geometry mandala ───
// Ported from static/golden-throne.html

// Default parameter values (screensaver — no mouse)
constant float GT_ROTATION_SPEED = 0.3;
constant float GT_COMPLEXITY = 5.0;

constant float GT_PI = 3.14159265359;
constant float GT_TAU = 6.28318530718;
constant float GT_PHI = 1.6180339887;

// GLSL-compatible mod (always returns positive result)
static float gt_mod(float x, float y) { return x - y * floor(x / y); }
static float2 gt_mod2(float2 x, float y) { return x - y * floor(x / y); }

// Rotation matrix
static float2x2 gt_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
}

// Golden color palette
static float3 gt_gold(float t) {
    float3 a = float3(0.45, 0.32, 0.14);
    float3 b = float3(0.45, 0.35, 0.2);
    float3 c = float3(1.0, 0.8, 0.5);
    float3 d = float3(0.0, 0.1, 0.25);
    return a + b * cos(GT_TAU * (c * t + d));
}

// Smooth min for SDF
static float gt_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Hexagonal distance
static float gt_hexDist(float2 p) {
    p = abs(p);
    return max(p.x + p.y * 0.577350269, p.y * 1.154700538);
}

// Triangle distance
static float gt_triDist(float2 p) {
    float k = sqrt(3.0);
    p.x = abs(p.x) - 1.0;
    p.y = p.y + 1.0 / k;
    if (p.x + k * p.y > 0.0) p = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0, 0.0);
    return -length(p) * sign(p.y);
}

// Flower of Life petal
static float gt_flowerPetal(float2 p, float r) {
    float d = 1e9;
    for (int i = 0; i < 6; i++) {
        float a = float(i) * GT_TAU / 6.0;
        float2 c = float2(cos(a), sin(a)) * r;
        d = min(d, length(p - c) - r);
    }
    return d;
}

// Star polygon
static float gt_starDist(float2 p, float r, int n, float inset) {
    float an = GT_PI / float(n);
    float en = GT_PI / float(n);
    float2 acs = float2(cos(an), sin(an));
    float2 ecs = float2(cos(en), sin(en));
    float bn = gt_mod(atan2(p.x, p.y), 2.0 * an) - an;
    p = length(p) * float2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
    return length(p) * sign(p.x);
}

// Sacred geometry layer compositing
static float gt_sacredRing(float2 p, float radius, float width) {
    return abs(length(p) - radius) - width;
}

// Mandala layer
static float gt_mandalaLayer(float2 uv, float time, float layer, float totalLayers) {
    float t = layer / totalLayers;
    float radius = 0.08 + t * 0.38;

    // Differential rotation — inner faster, outer slower, some counter-rotating
    float speed = GT_ROTATION_SPEED * (1.5 - t * 1.2);
    float direction = fmod(layer, 2.0) < 1.0 ? 1.0 : -1.0;
    float rot_angle = time * speed * direction + layer * GT_PHI;
    float2 p = gt_rot(rot_angle) * uv;

    float d = 1e9;
    float symmetry = 6.0 + floor(layer * 1.5);

    // Angular repetition for symmetry
    float angle = atan2(p.y, p.x);
    float r = length(p);
    float sector = GT_TAU / symmetry;
    float a = gt_mod(angle + sector * 0.5, sector) - sector * 0.5;
    float2 sp = float2(cos(a), sin(a)) * r;

    // Concentric ring
    float ring = abs(r - radius) - 0.003 * (1.0 + t);
    d = min(d, ring);

    // Petal arcs (flower of life inspiration)
    float petalR = radius * 0.35 / GT_PHI;
    float2 petalCenter = float2(radius, 0.0);
    float petal = abs(length(sp - petalCenter) - petalR) - 0.002;
    d = min(d, petal);

    // Inner petal arc
    float2 innerPetalCenter = float2(radius * 0.65, 0.0);
    float innerPetalR = radius * 0.25;
    float innerPetal = abs(length(sp - innerPetalCenter) - innerPetalR) - 0.0015;
    d = min(d, innerPetal);

    // Radial spokes
    float spoke = abs(sp.y) - 0.001;
    float spokeMask = smoothstep(radius - 0.05, radius - 0.01, r) * smoothstep(radius + 0.05, radius + 0.01, r);
    d = min(d, spoke / max(spokeMask, 0.001));

    // Hexagonal elements at intersections
    float hexR = 0.012 + t * 0.008;
    float2 hexPos = float2(radius, 0.0);
    float hex = gt_hexDist(sp - hexPos) - hexR;
    d = min(d, hex);

    // Diamond/triangular detail at half-radius
    if (layer > 1.0) {
        float2 triPos = float2(radius * 0.5, 0.0);
        float2 tp = (sp - triPos) * 60.0;
        float tri = gt_triDist(tp) / 60.0;
        d = min(d, tri);
    }

    return d;
}

// Spiral arms based on golden ratio
static float gt_goldenSpiral(float2 uv, float time) {
    float r = length(uv);
    float a = atan2(uv.y, uv.x);

    // Golden spiral: r = PHI^(2*theta/PI)
    float spiralPhase = log(max(r, 0.001)) / log(GT_PHI) * GT_PI * 0.5;
    float spiralD = abs(gt_mod(a - spiralPhase + time * GT_ROTATION_SPEED * 0.2 + GT_PI, GT_TAU) - GT_PI);
    spiralD = min(spiralD, abs(gt_mod(a - spiralPhase + time * GT_ROTATION_SPEED * 0.2 + GT_PI + GT_PI, GT_TAU) - GT_PI));

    // Fade spiral intensity with radius
    float fade = smoothstep(0.0, 0.05, r) * smoothstep(0.5, 0.35, r);
    return spiralD * fade + (1.0 - fade);
}

// Fractal detail — repeating at smaller scales
static float gt_fractalDetail(float2 uv, float time) {
    float d = 1e9;
    float scale = 1.0;
    float intensity = 0.0;

    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float2 p = uv * scale;
        p = gt_rot(time * GT_ROTATION_SPEED * (0.1 + fi * 0.05) * (fmod(fi, 2.0) < 1.0 ? 1.0 : -1.0)) * p;

        // Hexagonal tiling at this scale
        float hexSize = 0.15 / scale;
        float2 hexUV = p;
        float hx = gt_hexDist(gt_mod2(hexUV + hexSize, hexSize * 2.0) - hexSize);
        float hexLine = abs(hx - hexSize * 0.4) - 0.001 * scale;
        intensity += smoothstep(0.003, 0.0, hexLine) * (0.15 / (1.0 + fi));

        scale *= GT_PHI;
    }
    return intensity;
}

fragment float4 fs_golden_throne(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    // No mouse rotation for screensaver (u_mouse.x was drag offset)
    float t = u.time;
    float complexity = GT_COMPLEXITY;

    // Accumulated glow
    float3 col = float3(0.0);
    float r = length(uv);

    // Object mask — keep mandala centered with dark surround
    float objectRadius = 0.48;
    float objectFade = smoothstep(objectRadius, objectRadius * 0.7, r);

    // Build sacred geometry mandala layers
    float totalGlow = 0.0;

    for (int i = 0; i < 8; i++) {
        if (float(i) >= complexity) break;
        float fi = float(i);
        float layerD = gt_mandalaLayer(uv, t, fi, complexity);

        // Convert SDF to glow — sharp lines with soft bloom
        float lineGlow = 0.0025 / (abs(layerD) + 0.0025);
        float bloom = 0.008 / (abs(layerD) + 0.008) * 0.3;
        float layerIntensity = (lineGlow + bloom);

        // Color varies per layer — golden gradient from warm amber to bright gold
        float colorT = fi / complexity + t * 0.02;
        float3 layerColor = gt_gold(colorT);

        // Inner layers are brighter
        float brightness = 1.0 - fi / complexity * 0.5;

        col += layerColor * layerIntensity * brightness * 0.6;
        totalGlow += layerIntensity * brightness;
    }

    // Golden ratio spiral arms
    float spiral = gt_goldenSpiral(uv, t);
    float spiralGlow = 0.015 / (spiral + 0.015);
    col += gt_gold(0.7 + t * 0.01) * spiralGlow * 0.25;

    // Fractal hexagonal detail overlay
    float fractal = gt_fractalDetail(uv, t);
    col += gt_gold(0.3 + t * 0.03) * fractal * 0.4;

    // Central glowing point — pulses subtly
    float centerPulse = 0.8 + 0.2 * sin(t * 1.5);
    float centerGlow = 0.01 / (r * r + 0.01) * centerPulse;
    float3 centerColor = float3(1.0, 0.92, 0.7); // bright white-gold
    col += centerColor * centerGlow * 0.08;

    // Secondary center ring pulse
    float ringPulse = 0.9 + 0.1 * sin(t * 2.3 + 1.0);
    float innerRing = abs(r - 0.03 * ringPulse) - 0.002;
    float innerRingGlow = 0.003 / (abs(innerRing) + 0.003);
    col += float3(1.0, 0.88, 0.6) * innerRingGlow * 0.3;

    // Outer boundary ring — ornate edge
    float outerRing = abs(r - objectRadius + 0.01) - 0.003;
    float outerGlow = 0.004 / (abs(outerRing) + 0.004);
    col += gt_gold(0.5 + t * 0.015) * outerGlow * 0.35;

    // Second outer ring — slightly inside
    float outerRing2 = abs(r - objectRadius + 0.035) - 0.002;
    float outerGlow2 = 0.003 / (abs(outerRing2) + 0.003);
    col += gt_gold(0.6) * outerGlow2 * 0.2;

    // Decorative dots at outer ring intersections
    float dotAngle = atan2(uv.y, uv.x);
    float dotSymmetry = 12.0;
    float dotA = gt_mod(dotAngle + GT_PI / dotSymmetry, GT_TAU / dotSymmetry) - GT_PI / dotSymmetry;
    float2 dotP = float2(cos(dotA), sin(dotA)) * r;
    float2 dotCenter = float2(objectRadius - 0.01, 0.0);
    float dotVal = length(dotP - dotCenter) - 0.008;
    float dotGlow = 0.004 / (abs(dotVal) + 0.004);
    col += float3(1.0, 0.9, 0.65) * dotGlow * 0.3;

    // Apply object mask
    col *= objectFade;

    // Subtle warm ambient radial glow behind the mandala
    float ambientGlow = exp(-r * r * 6.0) * 0.06;
    col += float3(0.3, 0.2, 0.08) * ambientGlow;

    // Tone mapping
    col = col / (1.0 + col * 0.4);

    // Slight warmth boost
    col = pow(col, float3(0.95, 0.98, 1.05));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
