#include "../Common.metal"

// ─── Strobe Geometry: Sharp geometric shapes flash with glowing afterimage silhouettes ───
// Ported from static/strobe-geometry.html

// Default parameter values (screensaver — no interactive controls)
constant float SG_FLASH_RATE = 0.7;
constant float SG_GLOW_INTENSITY = 1.0;

constant float SG_PI = 3.141592653589793;
constant float SG_TAU = 6.283185307179586;
constant int SG_MAX_SHAPES = 8;

// ── ACES tone mapping ──
static float3 sg_ACESFilm(float3 x) {
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

// ── Hash ──
static float sg_hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static float2 sg_hash2(float n) {
    return float2(sg_hash(n), sg_hash(n + 7.31));
}

// ── Value noise for background texture ──
static float sg_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 57.0;
    return mix(mix(sg_hash(n), sg_hash(n + 1.0), f.x),
               mix(sg_hash(n + 57.0), sg_hash(n + 58.0), f.x), f.y);
}

// ── 2D rotation ──
static float2x2 sg_rot2(float a) {
    float c = cos(a); float s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
}

// ── SDF primitives ──

static float sg_sdTriangle(float2 p, float r) {
    float k = sqrt(3.0);
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0) p = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

static float sg_sdBox(float2 p, float2 b) {
    float2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

static float sg_sdParallelogram(float2 p, float wi, float he, float sk) {
    float2 e = float2(sk, he);
    p = (p.y < 0.0) ? -p : p;
    float2 w = p - e;
    w.x -= clamp(w.x, -wi, wi);
    float2 d = float2(dot(w, w), -w.y);
    float s = p.x * e.y - p.y * e.x;
    p = (s < 0.0) ? -p : p;
    float2 v = p - float2(wi, 0);
    v -= e * clamp(dot(v, e) / dot(e, e), -1.0, 1.0);
    d = min(d, float2(dot(v, v), wi * he - abs(s)));
    return sqrt(d.x) * sign(-d.y);
}

static float sg_sdRhombus(float2 p, float2 b) {
    float2 q = abs(p);
    float h = clamp((-2.0 * dot(q, b) + dot(b, b)) / dot(b, b), -1.0, 1.0);
    float d = length(q - 0.5 * b * float2(1.0 - h, 1.0 + h));
    return d * sign(q.x * b.y + q.y * b.x - b.x * b.y);
}

static float sg_sdHexagon(float2 p, float r) {
    float2 q = abs(p);
    float d = dot(q, normalize(float2(1.0, 1.732)));
    return max(d, q.y) - r;
}

static float sg_sdTrapezoid(float2 p, float r1, float r2, float he) {
    float2 k1 = float2(r2, he);
    float2 k2 = float2(r2 - r1, 2.0 * he);
    p.x = abs(p.x);
    float2 ca = float2(max(0.0, p.x - ((p.y < 0.0) ? r1 : r2)), abs(p.y) - he);
    float2 cb = p - k1 + k2 * clamp(dot(k1 - p, k2) / dot(k2, k2), 0.0, 1.0);
    float s = (cb.x < 0.0 && ca.y < 0.0) ? -1.0 : 1.0;
    return s * sqrt(min(dot(ca, ca), dot(cb, cb)));
}

// ── Shape evaluation ──
static float sg_evalShape(float2 p, int type, float scale) {
    float d = 1e5;
    if (type == 0) {
        d = sg_sdTriangle(p, scale * 0.36);
    } else if (type == 1) {
        d = sg_sdParallelogram(p, scale * 0.38, scale * 0.14, scale * 0.15);
    } else if (type == 2) {
        d = sg_sdRhombus(p, float2(scale * 0.12, scale * 0.40));
    } else if (type == 3) {
        d = sg_sdHexagon(p, scale * 0.25);
    } else if (type == 4) {
        d = sg_sdTrapezoid(p, scale * 0.15, scale * 0.35, scale * 0.18);
    }
    return d;
}

// ── Color decay sequence ──
static float3 sg_decayColor(float phase) {
    float3 white   = float3(1.0, 1.0, 1.0);
    float3 cyan    = float3(0.0, 0.95, 1.0);
    float3 blue    = float3(0.15, 0.4, 1.0);
    float3 magenta = float3(0.95, 0.1, 0.85);
    float3 purple  = float3(0.35, 0.05, 0.55);
    float3 dark    = float3(0.05, 0.01, 0.1);

    float3 col = dark;
    if (phase < 0.05) {
        col = mix(white, white, phase / 0.05);
    } else if (phase < 0.20) {
        col = mix(white, cyan, (phase - 0.05) / 0.15);
    } else if (phase < 0.40) {
        col = mix(cyan, blue, (phase - 0.20) / 0.20);
    } else if (phase < 0.65) {
        col = mix(blue, magenta, (phase - 0.40) / 0.25);
    } else if (phase < 0.85) {
        col = mix(magenta, purple, (phase - 0.65) / 0.20);
    } else {
        col = mix(purple, dark, (phase - 0.85) / 0.15);
    }
    return col;
}

// ── Per-shape parameters ──
struct SG_ShapeData {
    float2 center;
    float rotation;
    float scale;
    int type;
    float birthTime;
};

static SG_ShapeData sg_getShape(int idx, float flashInterval, float u_time) {
    SG_ShapeData s;
    float fi = float(idx);
    bool isStrong = (fi - 2.0 * floor(fi / 2.0) < 0.5);

    float cycleLen = float(SG_MAX_SHAPES) * flashInterval;
    float cycle = floor(u_time / cycleLen);
    float seed = fi * 13.37 + cycle * 97.31;

    float jitter = (sg_hash(seed + 10.0) - 0.5) * 0.2 * flashInterval;
    s.birthTime = fi * flashInterval + jitter;

    float2 basePos = sg_hash2(seed + 1.0) * 2.0 - 1.0;
    s.center = basePos * float2(0.65, 0.50);

    float baseAngle = floor(sg_hash(seed + 2.0) * 8.0) * (SG_PI / 4.0);
    float angleJitter = (sg_hash(seed + 5.0) - 0.5) * (SG_PI / 6.0);
    s.rotation = baseAngle + angleJitter;

    float baseScale = 0.4 + sg_hash(seed + 3.0) * 1.2;
    s.scale = isStrong ? baseScale * 1.3 : baseScale * 0.7;

    s.type = int(sg_hash(seed + 4.0) * 5.0 - 5.0 * floor(sg_hash(seed + 4.0) * 5.0 / 5.0));

    return s;
}

fragment float4 fs_strobe_geometry(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.pos.xy;
    float2 uv = fragCoord / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;

    // No mouse interaction — skip mouseShift
    float2 mouseShift = float2(0.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float t = u.time;
    float flashInterval = SG_FLASH_RATE;
    float decayDuration = 4.0;
    float cycleLen = float(SG_MAX_SHAPES) * flashInterval;

    float cycleTime = t - cycleLen * floor(t / cycleLen);

    // ── Background ──
    float3 bg = float3(0.015, 0.012, 0.025);
    float bgNoise = sg_vnoise(p * 3.0 + t * 0.05) * 0.4 + sg_vnoise(p * 7.0 - t * 0.03) * 0.3;
    bgNoise += sg_vnoise(p * 1.5 + float2(t * 0.02, -t * 0.01)) * 0.3;
    bg += float3(0.008, 0.006, 0.015) * bgNoise;

    float currentShapeIdx = floor(cycleTime / flashInterval);
    float timeSinceLastFlash = cycleTime - currentShapeIdx * flashInterval;
    bool currentIsStrong = (currentShapeIdx - 2.0 * floor(currentShapeIdx / 2.0) < 0.5);
    float bgPulseStrength = currentIsStrong ? 0.18 : 0.08;
    float bgPulse = exp(-timeSinceLastFlash * 6.0) * bgPulseStrength;
    bg += float3(0.08, 0.06, 0.12) * bgPulse;

    float3 col = bg;

    // ── Process each shape ──
    for (int ci = 0; ci < 2; ci++) {
        for (int i = 0; i < SG_MAX_SHAPES; i++) {
            SG_ShapeData shape = sg_getShape(i, flashInterval, t);

            float birthT = shape.birthTime;
            float fi = float(i);
            bool isStrong = (fi - 2.0 * floor(fi / 2.0) < 0.5);
            if (ci == 1) {
                float prevCycle = floor(t / cycleLen) - 1.0;
                float seed = fi * 13.37 + prevCycle * 97.31;
                shape.center = (sg_hash2(seed + 1.0) * 2.0 - 1.0) * float2(0.65, 0.50);
                float baseAngle = floor(sg_hash(seed + 2.0) * 8.0) * (SG_PI / 4.0);
                float angleJitter = (sg_hash(seed + 5.0) - 0.5) * (SG_PI / 6.0);
                shape.rotation = baseAngle + angleJitter;
                float baseScale = 0.4 + sg_hash(seed + 3.0) * 1.2;
                shape.scale = isStrong ? baseScale * 1.3 : baseScale * 0.7;
                shape.type = int(sg_hash(seed + 4.0) * 5.0 - 5.0 * floor(sg_hash(seed + 4.0) * 5.0 / 5.0));
                float jitter = (sg_hash(seed + 10.0) - 0.5) * 0.2 * flashInterval;
                shape.birthTime = fi * flashInterval + jitter;
                birthT = shape.birthTime - cycleLen;
            }

            float age = cycleTime - birthT;
            if (ci == 1) age = cycleTime + cycleLen - shape.birthTime;

            if (age < 0.0 || age > decayDuration) continue;

            float phase = age / decayDuration;

            float depthLayer = 0.5 + float(i) * 0.25;
            float2 localP = p - shape.center - mouseShift * depthLayer;
            localP = sg_rot2(shape.rotation) * localP;
            float d = sg_evalShape(localP, shape.type, shape.scale);

            float flashPhase = clamp(age / 0.2, 0.0, 1.0);
            float isFlashing = 1.0 - flashPhase;
            float beatMul = isStrong ? 1.4 : 0.8;

            // Layer 1: Active shape fill
            float fillAlpha = smoothstep(0.005, -0.005, d);
            float interiorDist = clamp(-d / (shape.scale * 0.25), 0.0, 1.0);
            float edgeBrightness = 1.0 - interiorDist * 0.65;
            float fillFade = exp(-age * 2.5);
            float flashBright = isFlashing * 2.0 * beatMul + fillFade;
            float3 fillColor = sg_decayColor(phase) * flashBright * edgeBrightness;
            fillColor = mix(fillColor, float3(2.5) * edgeBrightness, isFlashing * fillAlpha);
            col += fillColor * fillAlpha * (1.0 - phase * phase) * SG_GLOW_INTENSITY * 0.5;

            // Layer 2: Shape afterglow outline
            float edgeWidth = 0.006 + 0.003 * (1.0 - phase);
            float edge = smoothstep(edgeWidth, edgeWidth * 0.3, abs(d));
            float edgeFade = 1.0 - phase * phase * phase;
            float3 edgeColor = sg_decayColor(phase * 0.85) * edgeFade;
            col += edgeColor * edge * SG_GLOW_INTENSITY * 1.2;

            // Layer 3: Edge bloom
            float bloomWidthFlash = isStrong ? 0.08 : 0.05;
            float bloomWidthDecay = 0.015 + 0.015 * (1.0 - phase);
            float bloomWidth = mix(bloomWidthDecay, bloomWidthFlash, isFlashing);
            float bloom = exp(-abs(d) / bloomWidth);
            float bloomIntensity = mix(0.3, 1.8 * beatMul, isFlashing) * (1.0 - phase);
            float3 bloomColor = sg_decayColor(phase * 0.7);
            float3 warmBloom = mix(bloomColor, bloomColor + float3(0.15, 0.1, 0.05), bloom * isFlashing);
            col += warmBloom * bloom * bloomIntensity * SG_GLOW_INTENSITY * 0.4;

            // Extra hot bloom during flash
            if (age < 0.25) {
                float hotBloomWidth = isStrong ? 0.10 : 0.06;
                float hotBloom = exp(-abs(d) / hotBloomWidth) * isFlashing;
                col += float3(0.95, 0.92, 0.85) * hotBloom * SG_GLOW_INTENSITY * 0.7 * beatMul;
            }

            // Layer 4: Chromatic fringe
            float fringePeak = sin(clamp(phase * SG_PI, 0.0, SG_PI));
            float fringeAmount = fringePeak * 0.035;
            if (fringeAmount > 0.001) {
                float2 fringeDir = normalize(localP + float2(0.001));
                float dR = sg_evalShape(localP + fringeDir * fringeAmount, shape.type, shape.scale);
                float dB = sg_evalShape(localP - fringeDir * fringeAmount, shape.type, shape.scale);
                float dR2 = sg_evalShape(localP + fringeDir * fringeAmount * 0.5, shape.type, shape.scale);
                float dB2 = sg_evalShape(localP - fringeDir * fringeAmount * 0.5, shape.type, shape.scale);
                float fringeEdgeW = edgeWidth * 2.0;
                float edgeR = smoothstep(fringeEdgeW, fringeEdgeW * 0.2, abs(dR));
                float edgeB = smoothstep(fringeEdgeW, fringeEdgeW * 0.2, abs(dB));
                float edgeR2 = smoothstep(fringeEdgeW * 1.5, fringeEdgeW * 0.3, abs(dR2));
                float edgeB2 = smoothstep(fringeEdgeW * 1.5, fringeEdgeW * 0.3, abs(dB2));
                float fringeFade = edgeFade * 0.8;
                col.r += (edgeR + edgeR2 * 0.5) * fringeFade * 0.5;
                col.b += (edgeB + edgeB2 * 0.5) * fringeFade * 0.5;
            }
        }
    }

    // ── Scanline overlay ──
    float scanline = sin(fragCoord.y * 1.5) * 0.5 + 0.5;
    scanline = 0.92 + scanline * 0.08;
    col *= scanline;

    // ── Vignette ──
    float2 vc = uv - 0.5;
    float vig = 1.0 - dot(vc, vc) * 1.8;
    vig = clamp(vig, 0.0, 1.0);
    vig = pow(vig, 0.5);
    col *= vig;

    // ── Film grain ──
    float grain = (fract(sin(dot(fragCoord, float2(12.9898, 78.233)) + fract(t * 0.1) * 100.0) * 43758.5453) - 0.5) * 0.025;
    col += grain;

    // ── ACES tone mapping ──
    col = sg_ACESFilm(col);

    // ── Gamma correction ──
    col = pow(max(col, 0.0), float3(0.95));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
