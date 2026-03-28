#include "../Common.metal"

// ─── Hologram Glitch: Abstract holographic projection with scan lines,
//     color separation, and controlled glitch artifacts ───
// Ported from static/hologram-glitch.html

constant float HG_PI = 3.14159265359;

// Default parameter values
constant float HG_GLITCH_INTENSITY = 1.0;
constant float HG_SCAN_SPEED = 1.0;

// ── Hash helpers ──
static float hg_hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static float hg_hash2(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Value noise ──
static float hg_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hg_hash2(i), hg_hash2(i + float2(1.0, 0.0)), f.x),
        mix(hg_hash2(i + float2(0.0, 1.0)), hg_hash2(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// ── FBM noise (4 octaves) ──
static float hg_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0);
    float2x2 rot = float2x2(float2(cos(0.5), sin(0.5)), float2(-sin(0.5), cos(0.5)));
    for (int i = 0; i < 4; i++) {
        v += a * hg_vnoise(p);
        p = rot * p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ── Glitch timing — rhythmic bursts ──
static float hg_glitchEnvelope(float t) {
    // Slow rhythm: bursts every ~3-4 seconds
    float slow = sin(t * 0.7) * sin(t * 1.1);
    // Medium rhythm: sub-pulses within bursts
    float med = sin(t * 3.3) * 0.5 + 0.5;
    // Fast crackle during bursts
    float fast = step(0.88, hg_hash(floor(t * 12.0)));
    // Combine: active with frequent bursts
    float envelope = smoothstep(0.15, 0.5, slow) * (0.5 + 0.5 * med);
    // Add sharp spikes
    envelope += fast * 0.7;
    return clamp(envelope, 0.0, 1.0);
}

// ── Horizontal glitch band offset ──
static float hg_glitchBand(float y, float t, float intensity) {
    float env = hg_glitchEnvelope(t);
    if (env < 0.1) return 0.0;

    // Multiple glitch band layers at different scales
    float band1 = step(0.8, hg_vnoise(float2(y * 15.0, floor(t * 8.0)))) * 0.14;
    float band2 = step(0.85, hg_vnoise(float2(y * 40.0, floor(t * 15.0)))) * 0.07;
    float band3 = step(0.82, hg_vnoise(float2(y * 5.0, floor(t * 4.0)))) * 0.25;

    // Direction: some bands go left, some right
    float dir = sign(hg_vnoise(float2(y * 20.0, floor(t * 6.0))) - 0.5);

    return (band1 + band2 + band3) * dir * env * intensity;
}

// ── Noise burst rectangles ──
static float hg_noiseBurst(float2 uv, float t) {
    float env = hg_glitchEnvelope(t + 1.5);
    if (env < 0.3) return 0.0;

    // Random rectangular region
    float blockT = floor(t * 6.0);
    float bx = hg_hash(blockT * 7.3) * 0.8 - 0.4;
    float by = hg_hash(blockT * 11.7) * 0.8 - 0.4;
    float bw = hg_hash(blockT * 3.1) * 0.3 + 0.05;
    float bh = hg_hash(blockT * 5.9) * 0.1 + 0.02;

    float inBlock = step(bx, uv.x) * step(uv.x, bx + bw) *
                    step(by, uv.y) * step(uv.y, by + bh);

    // High-frequency noise inside the block
    float n = hg_hash2(floor(uv * 300.0) + blockT * 100.0);
    return inBlock * n * env * 1.0;
}

fragment float4 fs_hologram_glitch(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 centeredUV = (in.pos.xy - u.resolution * 0.5) / u.resolution.y;
    float t = u.time;
    float glitchI = HG_GLITCH_INTENSITY;
    float scanS = HG_SCAN_SPEED;

    // ── No mouse in screensaver mode ──
    float mouseInfluence = 0.0;

    // ── Layer 4: Horizontal glitch band displacement ──
    float bandOffset = hg_glitchBand(uv.y, t, glitchI);

    // Apply band displacement to UV
    float2 glitchedUV = uv;
    glitchedUV.x += bandOffset;

    // ── Layer 3: Chromatic aberration ──
    float chromBase = 0.008 + 0.006 * sin(t * 1.2);
    float chromSpike = hg_glitchEnvelope(t) * 0.035 * glitchI;
    float chromJump = step(0.92, hg_hash(floor(t * 5.0))) * 0.05 * glitchI;
    float chromAmount = chromBase + chromSpike + chromJump;

    // R shifts left, B shifts right
    float2 uvR = glitchedUV + float2(-chromAmount, 0.0);
    float2 uvG = glitchedUV;
    float2 uvB = glitchedUV + float2(chromAmount, 0.0);

    // Also add slight vertical separation
    uvR.y += chromAmount * 0.5;
    uvB.y -= chromAmount * 0.5;

    // ── Layer 1: Base flowing abstract shapes ──
    float slowT = t * 0.15;

    // Sample base pattern at each channel offset
    float patR = hg_fbm(uvR * 3.0 + float2(slowT, slowT * 0.7));
    patR += hg_fbm(uvR * 5.0 - float2(slowT * 0.5, slowT * 1.2)) * 0.5;
    patR += hg_fbm(uvR * 1.5 + float2(slowT * 0.3, -slowT * 0.4)) * 0.7;
    patR += hg_fbm(uvR * 10.0 + float2(slowT * 1.5, -slowT * 0.8)) * 0.15;

    float patG = hg_fbm(uvG * 3.0 + float2(slowT, slowT * 0.7));
    patG += hg_fbm(uvG * 5.0 - float2(slowT * 0.5, slowT * 1.2)) * 0.5;
    patG += hg_fbm(uvG * 1.5 + float2(slowT * 0.3, -slowT * 0.4)) * 0.7;
    patG += hg_fbm(uvG * 10.0 + float2(slowT * 1.5, -slowT * 0.8)) * 0.15;

    float patB = hg_fbm(uvB * 3.0 + float2(slowT, slowT * 0.7));
    patB += hg_fbm(uvB * 5.0 - float2(slowT * 0.5, slowT * 1.2)) * 0.5;
    patB += hg_fbm(uvB * 1.5 + float2(slowT * 0.3, -slowT * 0.4)) * 0.7;
    patB += hg_fbm(uvB * 10.0 + float2(slowT * 1.5, -slowT * 0.8)) * 0.15;

    // Normalize patterns
    patR = patR / 2.45;
    patG = patG / 2.45;
    patB = patB / 2.45;

    // Shape into sharply defined blobs
    patR = smoothstep(0.35, 0.55, patR);
    patG = smoothstep(0.35, 0.55, patG);
    patB = smoothstep(0.35, 0.55, patB);

    // Push contrast further
    patR = patR * patR * (3.0 - 2.0 * patR);
    patG = patG * patG * (3.0 - 2.0 * patG);
    patB = patB * patB * (3.0 - 2.0 * patB);

    // ── Layer 6: Holographic color shift ──
    float hueShift = t * 0.2;
    float hue1 = sin(hueShift) * 0.5 + 0.5;
    float hue2 = sin(hueShift + 2.094) * 0.5 + 0.5;
    float hue3 = sin(hueShift + 4.189) * 0.5 + 0.5;

    // Spatial variation in hue
    float spatialHue = sin(centeredUV.x * 4.0 + centeredUV.y * 3.0 + t * 0.3) * 0.5 + 0.5;

    // Base holographic palette
    float3 col1 = float3(0.0, 1.0, 1.2);
    float3 col2 = float3(1.2, 0.1, 0.9);
    float3 col3 = float3(1.2, 1.25, 1.3);
    float3 col4 = float3(1.0, 0.95, 0.2);

    // Mix palette based on time and position
    float3 palette = mix(col1, col2, hue1 * spatialHue);
    palette = mix(palette, col3, hue2 * 0.3);
    palette = mix(palette, col4, hue3 * spatialHue * 0.4);

    // Apply palette with per-channel separation
    float3 baseColor;
    baseColor.r = patR * palette.r;
    baseColor.g = patG * palette.g;
    baseColor.b = patB * palette.b;

    // Add bright spots where all channels align
    float alignment = patR * patG * patB;
    baseColor += float3(0.9, 0.95, 1.0) * pow(alignment, 1.5) * 1.2;

    // ── Layer 2: Scanline overlay ──
    float scanY = in.pos.y;

    // Fine scanlines
    float fineScan = sin(scanY * HG_PI * 0.8) * 0.5 + 0.5;
    fineScan = pow(fineScan, 1.5);

    // Medium scanlines — per-channel at different speeds
    float medScanR = sin((scanY + t * 60.0 * scanS) * 0.15) * 0.5 + 0.5;
    float medScanG = sin((scanY + t * 75.0 * scanS) * 0.15) * 0.5 + 0.5;
    float medScanB = sin((scanY + t * 55.0 * scanS) * 0.15) * 0.5 + 0.5;

    // Broad scan bands
    float broadScan = sin((scanY + t * 30.0 * scanS) * 0.03) * 0.5 + 0.5;
    broadScan = smoothstep(0.3, 0.7, broadScan);

    // Combine scanlines
    float scanR = mix(0.45, 1.0, fineScan) * mix(0.7, 1.0, medScanR) * mix(0.6, 1.0, broadScan);
    float scanG = mix(0.45, 1.0, fineScan) * mix(0.7, 1.0, medScanG) * mix(0.6, 1.0, broadScan);
    float scanB = mix(0.45, 1.0, fineScan) * mix(0.7, 1.0, medScanB) * mix(0.6, 1.0, broadScan);

    // Bright scan line sweep
    // Use positive mod: x - y * floor(x/y)
    float brightScanRaw = t * 40.0 * scanS;
    float brightScanPos = brightScanRaw - u.resolution.y * floor(brightScanRaw / u.resolution.y);
    float brightScan = exp(-abs(scanY - brightScanPos) * 0.12) * 0.7;

    baseColor.r *= scanR;
    baseColor.g *= scanG;
    baseColor.b *= scanB;
    baseColor += float3(0.3, 0.8, 1.0) * brightScan;

    // ── Layer 5: Interlace flicker ──
    // Use positive mod for interlace
    float interlaceRaw = scanY + floor(t * 30.0);
    float interlace = interlaceRaw - 2.0 * floor(interlaceRaw / 2.0);
    float interlaceFlicker = mix(0.78, 1.0, interlace);
    // Occasional full-line flicker
    float lineFlicker = 1.0 - step(0.95, hg_hash(floor(scanY * 0.5) + floor(t * 20.0) * 100.0)) * 0.5;
    baseColor *= interlaceFlicker * lineFlicker;

    // ── Layer 7: Noise burst artifacts ──
    float burst = hg_noiseBurst(centeredUV, t);
    float3 burstColor = float3(0.5, 0.9, 1.0) * burst;
    baseColor += burstColor * glitchI;

    // ── Layer 8: Edge glow ──
    float patCenter = hg_fbm(glitchedUV * 3.0 + float2(slowT, slowT * 0.7));
    float patDx = hg_fbm((glitchedUV + float2(0.005, 0.0)) * 3.0 + float2(slowT, slowT * 0.7));
    float patDy = hg_fbm((glitchedUV + float2(0.0, 0.005)) * 3.0 + float2(slowT, slowT * 0.7));
    float edgeStrength = length(float2(patDx - patCenter, patDy - patCenter)) * 20.0;
    edgeStrength = smoothstep(0.2, 0.8, edgeStrength);
    float3 edgeColor = mix(float3(0.2, 0.9, 1.2), float3(1.2, 0.3, 1.0), spatialHue) * edgeStrength * 0.6;
    baseColor += edgeColor;

    // ── Holographic shimmer ──
    float shimmer = sin(centeredUV.x * 20.0 + centeredUV.y * 15.0 + t * 2.0) * 0.15 + 0.85;
    shimmer *= sin(centeredUV.x * 8.0 - centeredUV.y * 12.0 + t * 1.3) * 0.1 + 0.9;
    baseColor *= shimmer;

    // ── Overall intensity modulation ──
    float clarity = sin(t * 0.4) * 0.15 + 0.85;
    baseColor *= clarity;

    // ── Layer 9: Vignette ──
    float vDist = length(centeredUV * float2(1.0, 0.85));
    float vignette = 1.0 - smoothstep(0.45, 1.1, vDist);
    float3 vignetteColor = float3(0.02, 0.03, 0.06);
    baseColor = mix(vignetteColor, baseColor, vignette);

    // ── Film grain ──
    float grain = (hg_hash2(in.pos.xy + fract(t * 43.0) * 1000.0) - 0.5) * 0.06;
    baseColor += grain;

    // ── Tone mapping ──
    baseColor = baseColor / (baseColor + float3(0.65));
    baseColor = pow(baseColor, float3(0.95));

    baseColor = max(baseColor, float3(0.0));

    baseColor = hue_rotate(baseColor, u.hue_shift);
    return float4(baseColor, 1.0);
}
