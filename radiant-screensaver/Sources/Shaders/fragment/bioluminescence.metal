#include "../Common.metal"

// ─── Bioluminescence: Glowing plankton in ocean waves at night ───
// Ported from static/bioluminescence.html

// Default parameter values
constant float BL_GLOW_INTENSITY = 1.0;
constant float BL_WAVE_SPEED = 1.0;
constant float BL_PI = 3.14159265359;
constant float BL_TAU = 6.28318530718;

// ── Hash & noise primitives ──
static float bl_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float bl_hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

static float bl_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = bl_hash(i);
    float b = bl_hash(i + float2(1.0, 0.0));
    float c = bl_hash(i + float2(0.0, 1.0));
    float d = bl_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float bl_fbm(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        val += amp * bl_noise(p * freq);
        freq *= 2.03;
        amp *= 0.49;
        p += float2(1.7, 9.2);
    }
    return val;
}

// ── Domain-warped noise for organic flow ──
static float bl_warpedNoise(float2 p, float t) {
    float2 q = float2(
        bl_fbm(p + float2(0.0, 0.0) + t * 0.04, 4),
        bl_fbm(p + float2(5.2, 1.3) + t * 0.03, 4)
    );
    float2 r = float2(
        bl_fbm(p + 3.0 * q + float2(1.7, 9.2) + t * 0.05, 4),
        bl_fbm(p + 3.0 * q + float2(8.3, 2.8) + t * 0.04, 4)
    );
    return bl_fbm(p + 2.5 * r, 5);
}

// ── Ocean wave height field ──
static float2 bl_oceanWaves(float2 p, float t) {
    float h = 0.0;
    float d = 0.0;
    float amp = 1.0;
    float freq = 1.0;

    for (int i = 0; i < 6; i++) {
        float fi = float(i);
        float angle = fi * 0.7 + 0.3;
        float2 dir = float2(cos(angle), sin(angle));
        float phase = dot(p * freq, dir) + t * (0.6 + fi * 0.15);
        float wave = sin(phase) * 0.5 + 0.5;
        float sharpWave = pow(wave, 1.5);
        h += sharpWave * amp;
        d += pow(wave, 3.0) * amp;
        amp *= 0.55;
        freq *= 1.8;
    }
    return float2(h, d);
}

// ── Breaking wave / foam line detection ──
static float bl_waveBreak(float2 uv, float t) {
    float breaks = 0.0;
    for (int i = 0; i < 4; i++) {
        float fi = float(i);
        float y_center = 0.1 + fi * 0.22;
        float wave_x = uv.x * (2.0 + fi * 0.8) + t * (0.15 + fi * 0.05);
        float undulation = sin(wave_x) * 0.03 + sin(wave_x * 2.3 + fi) * 0.015;
        float dist_to_wave = abs(uv.y - y_center - undulation);
        float breakLine = smoothstep(0.03, 0.0, dist_to_wave);
        float modulation = bl_noise(float2(uv.x * 3.0 + fi * 10.0, t * 0.2 + fi));
        modulation = smoothstep(0.35, 0.7, modulation);
        breaks += breakLine * modulation * (1.0 - fi * 0.2);
    }
    return breaks;
}

// ── Bioluminescent glow patterns ──
static float bl_bioGlow(float2 uv, float t) {
    float glow = 0.0;

    float2 wv = bl_oceanWaves(uv * 3.0, t * 0.8);
    float disturbance = wv.y;

    float organic1 = bl_warpedNoise(uv * 4.0 + float2(t * 0.06, t * 0.04), t * 0.5);
    float organic2 = bl_warpedNoise(uv * 6.0 + float2(-t * 0.05, t * 0.07), t * 0.4);

    glow += organic1 * disturbance * 0.8;
    glow += organic2 * pow(disturbance, 2.0) * 0.5;

    // Swirling tendrils
    float2 eddy_uv = uv * 5.0 + float2(t * 0.08, t * 0.05);
    float eddy = bl_fbm(eddy_uv, 6);
    float eddy_curl = abs(eddy - bl_fbm(eddy_uv + float2(0.01, 0.0), 6)) * 80.0;
    glow += eddy_curl * disturbance * 0.3;

    // Scattered bright plankton clusters
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float2 center = float2(
            bl_hash1(fi * 13.7 + 1.0) * 1.6 - 0.3,
            bl_hash1(fi * 7.3 + 2.0) * 1.2 - 0.1
        );
        center.x += sin(t * 0.05 + fi * 2.0) * 0.15;
        center.y += cos(t * 0.04 + fi * 1.5) * 0.08;
        float d = length(uv - center);
        float cluster = exp(-d * d / (0.015 + bl_hash1(fi * 3.1) * 0.02));
        float pulse = sin(t * (0.3 + fi * 0.1) + fi * 4.0) * 0.5 + 0.5;
        glow += cluster * pulse * disturbance * 1.5;
    }

    return glow;
}

// ── Individual bright plankton sparks ──
static float bl_planktonSparks(float2 uv, float t, float disturbance) {
    float sparks = 0.0;
    for (int i = 0; i < 25; i++) {
        float fi = float(i);
        float2 pos = float2(
            bl_hash1(fi * 17.3 + 100.0),
            bl_hash1(fi * 11.9 + 200.0)
        );
        pos.x = fract(pos.x + t * (0.01 + bl_hash1(fi * 5.1 + 300.0) * 0.02));
        pos.y = fract(pos.y + sin(t * 0.3 + fi) * 0.02);

        float d = length(uv - pos);
        float size = 0.001 + bl_hash1(fi * 3.7 + 400.0) * 0.003;
        float spark = smoothstep(size, 0.0, d);

        float trigger = smoothstep(0.2, 0.6, disturbance);

        float twinkle = sin(t * (1.0 + bl_hash1(fi * 2.3) * 3.0) + fi * 7.0);
        twinkle = twinkle * 0.5 + 0.5;

        sparks += spark * trigger * twinkle * 0.8;
    }
    return sparks;
}

fragment float4 fs_bioluminescence(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    float2 uvAspect = float2(uv.x * aspect, uv.y);
    float t = u.time * BL_WAVE_SPEED;

    // ── Deep ocean base color ──
    float3 deepColor = float3(0.017, 0.011, 0.0);
    float3 midColor = float3(0.028, 0.018, 0.001);
    float3 surfaceColor = float3(0.034, 0.024, 0.0);
    float3 col = mix(deepColor, surfaceColor, uv.y);

    // ── Subtle underwater caustic light ──
    float caustic1 = bl_noise(uvAspect * 8.0 + float2(t * 0.12, t * 0.08));
    float caustic2 = bl_noise(uvAspect * 12.0 + float2(-t * 0.1, t * 0.15));
    float causticPattern = caustic1 * caustic2;
    causticPattern = pow(causticPattern, 2.0) * 3.0;
    float surfaceFade = smoothstep(0.3, 0.95, uv.y);
    col += float3(0.034, 0.021, 0.005) * causticPattern * surfaceFade;

    // ── Ocean wave structure ──
    float2 waves = bl_oceanWaves(uvAspect * 2.5, t);
    float waveHeight = waves.x;
    float waveDisturbance = waves.y;

    col += float3(0.02, 0.012, 0.005) * waveHeight * 0.3;

    // ── BIOLUMINESCENCE ──
    float bio = bl_bioGlow(uvAspect, t) * BL_GLOW_INTENSITY;

    // No mouse interaction in screensaver

    // Wave-break bioluminescence
    float breaks = bl_waveBreak(uvAspect, t);
    bio += breaks * 1.2 * BL_GLOW_INTENSITY;

    bio = pow(max(bio, 0.0), 1.3);

    // Bioluminescent color
    float3 bioColor1 = float3(0.55, 0.26, 0.0);
    float3 bioColor2 = float3(0.90, 0.36, 0.41);
    float3 bioColor3 = float3(1.0, 0.53, 0.37);

    float colorVar = bl_noise(uvAspect * 2.0 + t * 0.02);
    float3 bioCol = mix(bioColor1, bioColor2, colorVar);
    bioCol = mix(bioCol, bioColor3, smoothstep(0.5, 1.0, bio));

    col += bioCol * bio * 0.7;

    // ── Bright plankton sparks ──
    float sparks = bl_planktonSparks(uv, t, waveDisturbance);
    float3 sparkColor = float3(1.0, 0.67, 0.52);
    col += sparkColor * sparks * BL_GLOW_INTENSITY;

    // ── Wave foam with bioluminescent edge ──
    float foam = bl_waveBreak(uvAspect, t);
    float foamDetail = bl_noise(uvAspect * 25.0 + t * 0.3);
    foam *= foamDetail;
    col += float3(0.70, 0.36, 0.28) * foam * 0.4 * BL_GLOW_INTENSITY;

    // ── Flowing current streaks ──
    float streak_uv_y = uv.y * 15.0;
    float streakNoise = bl_noise(float2(uvAspect.x * 3.0 + t * 0.15, streak_uv_y));
    float streak = pow(streakNoise, 5.0) * 2.0;
    streak *= waveDisturbance;
    col += float3(0.38, 0.18, 0.06) * streak * BL_GLOW_INTENSITY;

    // ── Surface reflection ──
    float surfaceGlow = smoothstep(0.7, 1.0, uv.y);
    float surfaceWave = bl_noise(float2(uvAspect.x * 4.0 + t * 0.1, t * 0.2));
    col += float3(0.028, 0.018, 0.001) * surfaceGlow * surfaceWave;

    // ── Depth fog ──
    float depthFog = smoothstep(0.6, 0.0, uv.y);
    col = mix(col, deepColor * 0.5, depthFog * 0.4);

    // ── Moonlight from above ──
    float2 moonUV = uv - float2(0.5, 1.0);
    float moonDist = length(moonUV * float2(1.0, 1.5));
    float moonLight = exp(-moonDist * moonDist * 3.0);
    col += float3(0.034, 0.021, 0.005) * moonLight;

    // ── Vignette ──
    float2 vigUV = uv - 0.5;
    float vig = 1.0 - dot(vigUV, vigUV) * 1.8;
    vig = clamp(vig, 0.0, 1.0);
    col *= 0.5 + vig * 0.5;

    // ── Tone mapping & color grading ──
    col = max(col, float3(0.0));
    col = pow(max(col, 0.0), float3(0.95, 1.0, 1.02));

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(col, 1.0);
}
