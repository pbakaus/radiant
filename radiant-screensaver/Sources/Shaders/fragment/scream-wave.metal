#include "../Common.metal"

// ─── Scream Wave: Emotional waveform — calm verse to screaming chorus ───
// Ported from static/scream-wave.html

constant float SW_PI = 3.14159265359;
constant float SW_CYCLE = 7.0;
constant float SW_INTENSITY = 1.0;
constant float SW_WAVE_SPEED = 0.8;

// ── Hash for noise ──
static float sw_hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static float sw_hash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Value noise ──
static float sw_noise(float x) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(sw_hash(i), sw_hash(i + 1.0), f);
}

// ── 2D noise for visual grain ──
static float sw_noise2d(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sw_hash2(i);
    float b = sw_hash2(i + float2(1.0, 0.0));
    float c = sw_hash2(i + float2(0.0, 1.0));
    float d = sw_hash2(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Emotional intensity envelope ──
static float sw_emotionCurve(float t) {
    float phase = fract(t / SW_CYCLE);

    // Calm
    float calm = smoothstep(0.0, 0.06, phase) * (1.0 - smoothstep(0.14, 0.25, phase));
    float calmVal = 0.08 + 0.04 * sin(phase * SW_PI * 20.0);

    // Building
    float buildStart = 0.214;
    float buildEnd = 0.5;
    float build = smoothstep(buildStart - 0.03, buildStart + 0.04, phase) * (1.0 - smoothstep(buildEnd - 0.04, buildEnd + 0.02, phase));
    float buildProgress = clamp((phase - buildStart) / (buildEnd - buildStart), 0.0, 1.0);
    buildProgress = buildProgress * buildProgress * (3.0 - 2.0 * buildProgress);
    float buildVal = 0.1 + buildProgress * buildProgress * 0.85;

    // Scream
    float screamStart = 0.5;
    float screamEnd = 0.714;
    float scream = smoothstep(screamStart - 0.03, screamStart + 0.03, phase) * (1.0 - smoothstep(screamEnd - 0.04, screamEnd + 0.01, phase));
    float screamProgress = clamp((phase - screamStart) / (screamEnd - screamStart), 0.0, 1.0);
    float screamVal = 0.95 + 0.05 * sin(screamProgress * SW_PI);

    // Collapse
    float collapseStart = 0.714;
    float collapse = smoothstep(collapseStart - 0.04, collapseStart + 0.03, phase);
    float collapseProgress = clamp((phase - collapseStart) / (1.0 - collapseStart), 0.0, 1.0);
    float collapseFlash = exp(-collapseProgress * 20.0) * 0.25;
    float flutter = sin(collapseProgress * 40.0) * exp(-collapseProgress * 5.0) * 0.08;
    float collapseVal = (0.95 + collapseFlash) * exp(-collapseProgress * 4.5) + flutter;
    collapseVal = max(collapseVal, 0.0);

    return calmVal * calm + buildVal * build + screamVal * scream + collapseVal * collapse;
}

// ── Waveform function ──
static float sw_waveform(float x, float t, float emotion, float speed) {
    float baseFreq = 3.0;
    float timeOsc = t * speed;

    float wave = sin(x * baseFreq * SW_PI * 2.0 + timeOsc * 4.0);
    wave += sin(x * baseFreq * 2.0 * SW_PI * 2.0 + timeOsc * 3.0 + 0.8) * 0.12;

    float harmonics = emotion * emotion;
    wave += sin(x * baseFreq * 2.0 * SW_PI * 2.0 + timeOsc * 6.0 + 0.5) * harmonics * 0.5;
    wave += sin(x * baseFreq * 3.0 * SW_PI * 2.0 + timeOsc * 8.0 + 1.2) * harmonics * harmonics * 0.35;
    wave += sin(x * baseFreq * 5.0 * SW_PI * 2.0 + timeOsc * 12.0 + 2.1) * harmonics * harmonics * 0.2;
    wave += sin(x * baseFreq * 7.0 * SW_PI * 2.0 - timeOsc * 5.0 + 3.7) * pow(harmonics, 3.0) * 0.15;

    float noiseAmt = smoothstep(0.7, 1.0, emotion);
    wave += (sw_noise(x * 40.0 + timeOsc * 15.0) - 0.5) * 2.0 * noiseAmt * 0.6;
    wave += (sw_noise(x * 80.0 - timeOsc * 20.0) - 0.5) * 2.0 * noiseAmt * noiseAmt * 0.3;

    float amplitude = 0.05 + emotion * 0.45;
    wave *= amplitude;

    float clipThreshold = mix(0.5, 0.12, smoothstep(0.8, 1.0, emotion));
    wave = clamp(wave, -clipThreshold, clipThreshold);

    return wave;
}

fragment float4 fs_scream_wave(VSOut in [[stage_in]],
                               constant CommonUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.pos.xy;
    float2 uv = fragCoord / u.resolution;
    float t = u.time;

    // Emotional intensity (no mouse interaction)
    float emotion = sw_emotionCurve(t) * SW_INTENSITY;
    emotion = clamp(emotion, 0.0, 1.0);

    // ── Background ──
    float3 bgCalm = float3(0.02, 0.01, 0.04);
    float3 bgScream = float3(0.06, 0.01, 0.01);
    float3 bg = mix(bgCalm, bgScream, emotion);

    float centerDist = length(uv - float2(0.5, 0.5));
    float bgGlow = exp(-centerDist * centerDist * 3.0);
    float3 bgGlowColor = mix(float3(0.05, 0.02, 0.08), float3(0.12, 0.02, 0.02), emotion);
    bg += bgGlowColor * bgGlow * (0.3 + emotion * 0.5);

    // ── Screen noise at peak ──
    float screenNoise = 0.0;
    float noiseIntensity = smoothstep(0.6, 1.0, emotion);
    if (noiseIntensity > 0.0) {
        screenNoise = (sw_noise2d(fragCoord * 0.8 + t * 100.0) - 0.5) * noiseIntensity * 0.15;
        screenNoise += (sw_noise2d(fragCoord * 2.5 + t * 200.0) - 0.5) * noiseIntensity * noiseIntensity * 0.08;
    }

    // ── Chromatic aberration offset ──
    float chromatic = smoothstep(0.5, 1.0, emotion) * 0.025 * SW_INTENSITY;

    // Vertical jitter during scream
    float jitter = smoothstep(0.85, 1.0, emotion) * (sw_noise(t * 30.0) - 0.5) * 0.015;

    // ── Horizontal glitch displacement during scream ──
    float glitchAmt = smoothstep(0.8, 1.0, emotion);
    float glitchBand = step(0.92, sw_noise(floor(uv.y * 25.0) + floor(t * 8.0) * 7.3));
    float glitchOffset = glitchBand * glitchAmt * (sw_noise(t * 50.0 + uv.y * 10.0) - 0.5) * 0.06;

    // ── Compute waveform SDF for each RGB channel ──
    float waveX = uv.x + glitchOffset;
    float yCenter = uv.y - 0.5 + jitter;
    float speed = SW_WAVE_SPEED;

    float waveR = sw_waveform(waveX - chromatic, t, emotion, speed);
    float distR = abs(yCenter - waveR);

    float waveG = sw_waveform(waveX, t, emotion, speed);
    float distG = abs(yCenter - waveG);

    float waveB = sw_waveform(waveX + chromatic, t, emotion, speed);
    float distB = abs(yCenter - waveB);

    // ── Wave thickness and glow ──
    float lineThickness = 0.003 + emotion * 0.004;
    float glowRadius = 0.022 + emotion * 0.038;
    float bloomRadius = 0.08 + emotion * 0.14;

    // ── Color palette based on emotion ──
    float3 calmColor = float3(0.62, 0.42, 0.88);
    float3 buildColor = float3(0.95, 0.2, 0.6);
    float3 screamCoreColor = float3(1.0, 0.95, 0.9);
    float3 screamGlowColor = float3(1.0, 0.25, 0.1);

    float buildPhase = smoothstep(0.1, 0.6, emotion);
    float screamPhase = smoothstep(0.7, 0.95, emotion);

    float3 coreColor = mix(calmColor, buildColor, buildPhase);
    coreColor = mix(coreColor, screamCoreColor, screamPhase);

    float3 glowColor = mix(calmColor * 0.6, buildColor * 0.7, buildPhase);
    glowColor = mix(glowColor, screamGlowColor, screamPhase);

    // ── Compute per-channel intensities ──
    float coreR = smoothstep(lineThickness, 0.0, distR);
    float coreG = smoothstep(lineThickness, 0.0, distG);
    float coreB = smoothstep(lineThickness, 0.0, distB);

    float glowR = exp(-distR * distR / (glowRadius * glowRadius));
    float glowG_v = exp(-distG * distG / (glowRadius * glowRadius));
    float glowB = exp(-distB * distB / (glowRadius * glowRadius));

    float bloomR = exp(-distR * distR / (bloomRadius * bloomRadius));
    float bloomG = exp(-distG * distG / (bloomRadius * bloomRadius));
    float bloomB = exp(-distB * distB / (bloomRadius * bloomRadius));

    // ── Compose final color ──
    float3 col = bg;

    float splitAmount = smoothstep(0.4, 0.9, emotion);

    // Unified wave (low emotion)
    float unifiedCore = smoothstep(lineThickness, 0.0, distG);
    float unifiedGlow = exp(-distG * distG / (glowRadius * glowRadius));
    float unifiedBloom = exp(-distG * distG / (bloomRadius * bloomRadius));

    float coreBright = 2.0 + smoothstep(0.8, 1.0, emotion) * 1.5;

    float3 unifiedCol = coreColor * unifiedCore * coreBright
                      + glowColor * unifiedGlow * 0.9
                      + glowColor * 0.35 * unifiedBloom;

    // Split wave (high emotion) — chromatic aberration
    float3 splitCol = float3(0.0);
    splitCol.r = coreColor.r * coreR * coreBright + glowColor.r * glowR * 0.9 + glowColor.r * 0.35 * bloomR;
    splitCol.g = coreColor.g * coreG * coreBright + glowColor.g * glowG_v * 0.9 + glowColor.g * 0.35 * bloomG;
    splitCol.b = coreColor.b * coreB * coreBright + glowColor.b * glowB * 0.9 + glowColor.b * 0.35 * bloomB;

    float3 waveCol = mix(unifiedCol, splitCol, splitAmount);
    col += waveCol;

    // ── Reflection ──
    float reflUvY = 1.0 - uv.y;
    float reflYCenter = reflUvY - 0.5 + jitter;
    float reflDistG = abs(reflYCenter - waveG);
    float belowCenter = uv.y - 0.5;
    float reflFade = step(0.0, belowCenter) * (1.0 - smoothstep(0.0, 0.35, belowCenter)) * 0.2;
    float reflGlow = exp(-reflDistG * reflDistG / (glowRadius * glowRadius * 3.0));
    float reflBloom = exp(-reflDistG * reflDistG / (bloomRadius * bloomRadius * 2.5));
    float3 reflCol = glowColor * reflGlow * 0.45 + glowColor * reflBloom * 0.12;
    col += reflCol * reflFade;

    // ── Horizontal scan lines during scream ──
    float scanline = smoothstep(0.8, 1.0, emotion) * 0.08;
    float scan = sin(fragCoord.y * 1.5) * 0.5 + 0.5;
    col *= 1.0 - scanline * scan;

    // ── Screen noise ──
    col += float3(screenNoise);

    // ── Vignette ──
    float2 vigUV = uv - 0.5;
    float vig = 1.0 - dot(vigUV, vigUV) * 1.8;
    vig = clamp(vig, 0.0, 1.0);
    col *= 0.5 + vig * 0.5;

    // ── Pulsing brightness at scream peak ──
    float pulse = 1.0 + smoothstep(0.85, 1.0, emotion) * sin(t * 25.0) * 0.15;
    col *= pulse;

    // ── Tone mapping ──
    col = col / (1.0 + col * 0.4);
    col = pow(col, float3(0.95));
    col = max(col, float3(0.0));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
