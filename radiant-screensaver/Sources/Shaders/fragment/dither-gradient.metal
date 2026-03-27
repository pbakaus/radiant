#include "../Common.metal"

// ─── Dither Gradient: Smooth gradients decomposed into ordered dithering ───
// Ported from static/dither-gradient.html

constant float DG_PI = 3.14159265359;
constant float DG_TAU = 6.28318530718;
constant float DG_DITHER_SCALE = 1.0;
constant float DG_BIT_DEPTH = 1.0;

// ── Hash ──
static float dg_hash(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Value noise ──
static float dg_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(dg_hash(i), dg_hash(i + float2(1.0, 0.0)), f.x),
        mix(dg_hash(i + float2(0.0, 1.0)), dg_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// ── FBM ──
static float dg_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2x2 rot = float2x2(float2(0.8, -0.6), float2(0.6, 0.8));
    for (int i = 0; i < 4; i++) {
        v += a * dg_vnoise(p);
        p = rot * p * 2.0 + float2(100.0);
        a *= 0.5;
    }
    return v;
}

// ── Bayer 8x8 dithering ──
static float dg_bayer8(float2 p) {
    // GLSL mod always positive; use x - y * floor(x/y)
    float2 fp = floor(p - 8.0 * floor(p / 8.0));
    float val = 0.0;

    // Level 1
    float bx = step(4.0, fp.x);
    float by = step(4.0, fp.y);
    float b = bx * 2.0 * (1.0 - by) + (1.0 - bx) * 3.0 * by + bx * by * 1.0;
    val += b * 16.0;

    // Level 2
    float mx = fp.x - 4.0 * floor(fp.x / 4.0);
    float my = fp.y - 4.0 * floor(fp.y / 4.0);
    bx = step(2.0, mx);
    by = step(2.0, my);
    b = bx * 2.0 * (1.0 - by) + (1.0 - bx) * 3.0 * by + bx * by * 1.0;
    val += b * 4.0;

    // Level 3
    float lx = fp.x - 2.0 * floor(fp.x / 2.0);
    float ly = fp.y - 2.0 * floor(fp.y / 2.0);
    bx = step(1.0, lx);
    by = step(1.0, ly);
    b = bx * 2.0 * (1.0 - by) + (1.0 - bx) * 3.0 * by + bx * by * 1.0;
    val += b;

    return val / 64.0;
}

// ── Halftone dot pattern ──
static float dg_halftone(float2 p, float size) {
    float2 cell = floor(p / size) * size + size * 0.5;
    float d = length(p - cell) / (size * 0.5);
    return clamp(d, 0.0, 1.0);
}

// ── Diagonal line dither ──
static float dg_lineDither(float2 p, float size) {
    // mod with positive result
    float d = (p.x + p.y) - size * floor((p.x + p.y) / size);
    return d / size;
}

// ── Cross-hatch dither ──
static float dg_crossHatch(float2 p, float size) {
    float sum1 = p.x + p.y;
    float d1 = (sum1 - size * floor(sum1 / size)) / size;
    float diff1 = p.x - p.y;
    float d2 = (diff1 - size * floor(diff1 / size)) / size;
    return min(d1, d2);
}

// ── Dithered quantization ──
static float dg_ditherQuantize(float val, float levels, float threshold) {
    float stepped = floor(val * levels) / levels;
    float next = stepped + 1.0 / levels;
    float fr = fract(val * levels);
    return fr > threshold ? next : stepped;
}

// ── Base gradient field ──
static float3 dg_baseGradient(float2 uv, float t) {
    float angle = t * 0.05;
    float2x2 rot = float2x2(float2(cos(angle), -sin(angle)), float2(sin(angle), cos(angle)));
    float2 ruv = rot * uv;

    float2 c1 = float2(0.35 * sin(t * 0.07), 0.25 * cos(t * 0.09));
    float2 c2 = float2(-0.3 * cos(t * 0.06 + 1.0), 0.3 * sin(t * 0.08 + 2.0));
    float2 c3 = float2(0.2 * sin(t * 0.11 + 3.0), -0.35 * cos(t * 0.05 + 1.5));

    float d1 = length(ruv - c1);
    float d2 = length(ruv - c2);
    float d3 = length(ruv - c3);

    float a1 = atan2(ruv.y - c1.y, ruv.x - c1.x);
    float a2 = atan2(ruv.y - c2.y, ruv.x - c2.x);

    float g1 = sin(d1 * 3.0 - t * 0.15 + a1 * 0.5) * 0.5 + 0.5;
    float g2 = cos(d2 * 2.5 + t * 0.12 - a2 * 0.3) * 0.5 + 0.5;
    float g3 = sin(d3 * 4.0 + t * 0.1 + d1 * 2.0) * 0.5 + 0.5;

    float warp = dg_fbm(ruv * 2.0 + t * 0.05) * 0.3;

    float f = g1 * 0.4 + g2 * 0.35 + g3 * 0.25 + warp;
    f = clamp(f, 0.0, 1.0);

    float3 col0 = float3(0.04, 0.03, 0.02);
    float3 col1 = float3(0.30, 0.15, 0.06);
    float3 col2 = float3(0.70, 0.40, 0.15);
    float3 col3 = float3(0.92, 0.75, 0.45);

    float3 col;
    if (f < 0.33) {
        col = mix(col0, col1, f / 0.33);
    } else if (f < 0.66) {
        col = mix(col1, col2, (f - 0.33) / 0.33);
    } else {
        col = mix(col2, col3, (f - 0.66) / 0.34);
    }

    return col;
}

fragment float4 fs_dither_gradient(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.pos.xy;
    float2 uv = (fragCoord - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float ditherSc = DG_DITHER_SCALE;
    float bitD = DG_BIT_DEPTH;

    // No mouse interaction in screensaver

    // Base gradient
    float3 smoothColor = dg_baseGradient(uv, t);

    // Dither coordinates
    float2 ditherCoord = fragCoord / ditherSc;

    // Region noise for pattern transitions
    float regionNoise = dg_fbm(uv * 1.5 + t * 0.04);
    float regionNoise2 = dg_fbm(uv * 2.0 - t * 0.03 + float2(50.0));

    float zoneBayer = smoothstep(0.3, 0.6, regionNoise);
    float zoneHalftone = smoothstep(0.4, 0.7, regionNoise2);
    float zoneLine = smoothstep(0.35, 0.65, sin(regionNoise * DG_TAU + t * 0.2) * 0.5 + 0.5);
    float zoneCross = 1.0 - zoneBayer;

    float totalWeight = zoneBayer + zoneHalftone + zoneLine + zoneCross + 0.001;
    zoneBayer /= totalWeight;
    zoneHalftone /= totalWeight;
    zoneLine /= totalWeight;
    zoneCross /= totalWeight;

    // Bit-depth wave
    float waveAngle = t * 0.08;
    float2 waveDir = float2(cos(waveAngle), sin(waveAngle));
    float wavePos = dot(uv, waveDir);

    float wave1 = sin(wavePos * 4.0 - t * 0.3) * 0.5 + 0.5;
    float wave2 = sin(dot(uv, float2(sin(t * 0.05), cos(t * 0.07))) * 6.0 + t * 0.2) * 0.5 + 0.5;
    float waveMix = wave1 * 0.6 + wave2 * 0.4;

    float baseLevels = mix(2.0, 32.0, waveMix) * bitD;
    baseLevels = max(baseLevels, 2.0);

    // Chromatic dither separation
    float2 offsetR = float2(0.0, 0.0);
    float2 offsetG = float2(2.7, 1.3);
    float2 offsetB = float2(-1.5, 3.1);

    float threshR = dg_bayer8(ditherCoord + offsetR) * zoneBayer
                  + dg_halftone(ditherCoord + offsetR, 8.0) * zoneHalftone
                  + dg_lineDither(ditherCoord + offsetR, 6.0) * zoneLine
                  + dg_crossHatch(ditherCoord + offsetR, 6.0) * zoneCross;

    float threshG = dg_bayer8(ditherCoord + offsetG) * zoneBayer
                  + dg_halftone(ditherCoord + offsetG, 8.0) * zoneHalftone
                  + dg_lineDither(ditherCoord + offsetG, 6.0) * zoneLine
                  + dg_crossHatch(ditherCoord + offsetG, 6.0) * zoneCross;

    float threshB = dg_bayer8(ditherCoord + offsetB) * zoneBayer
                  + dg_halftone(ditherCoord + offsetB, 8.0) * zoneHalftone
                  + dg_lineDither(ditherCoord + offsetB, 6.0) * zoneLine
                  + dg_crossHatch(ditherCoord + offsetB, 6.0) * zoneCross;

    float levelsR = baseLevels;
    float levelsG = baseLevels * 1.15;
    float levelsB = baseLevels * 0.85;

    float3 ditheredColor;
    ditheredColor.r = dg_ditherQuantize(smoothColor.r, levelsR, threshR);
    ditheredColor.g = dg_ditherQuantize(smoothColor.g, levelsG, threshG);
    ditheredColor.b = dg_ditherQuantize(smoothColor.b, levelsB, threshB);

    float3 finalColor = ditheredColor;

    // Edge emphasis
    float bandEdge = abs(fract(waveMix * 4.0) - 0.5) * 2.0;
    bandEdge = smoothstep(0.85, 1.0, bandEdge);
    finalColor += float3(0.08, 0.05, 0.02) * bandEdge;

    // Vignette
    float vigVal = 1.0 - dot(uv * 0.85, uv * 0.85);
    vigVal = clamp(vigVal, 0.0, 1.0);
    vigVal = pow(vigVal, 0.4);
    finalColor *= vigVal;

    // Film grain
    float grain = (dg_hash(fragCoord + fract(t * 41.0) * 1000.0) - 0.5) * 0.02;
    finalColor += grain;

    finalColor = max(finalColor, float3(0.0));

    finalColor = hue_rotate(finalColor, u.hue_shift);
    return float4(finalColor, 1.0);
}
