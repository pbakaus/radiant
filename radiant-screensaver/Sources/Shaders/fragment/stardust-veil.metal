#include "../Common.metal"

// ─── Stardust Veil: Dense shimmering cosmic stardust curtain ───
// Ported from static/stardust-veil.html

constant float SV_PI = 3.14159265359;
constant float SV_TAU = 6.28318530718;

// Default parameter values (screensaver — no mouse, no postMessage)
constant float SV_DRIFT_SPEED = 0.4;
constant float SV_STAR_DENSITY = 1.0;

// ── Hash & Noise primitives ──

static float sv_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float sv_hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

static float2 sv_hash2(float2 p) {
    return float2(
        fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, float2(269.5, 183.3))) * 43758.5453)
    );
}

static float sv_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sv_hash(i);
    float b = sv_hash(i + float2(1.0, 0.0));
    float c = sv_hash(i + float2(0.0, 1.0));
    float d = sv_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float sv_fbm(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 7; i++) {
        if (i >= octaves) break;
        val += amp * sv_noise(p * freq);
        freq *= 2.03;
        amp *= 0.49;
        p += float2(1.7, 9.2);
    }
    return val;
}

static float sv_warpedFbm(float2 p, float t) {
    float2 q = float2(
        sv_fbm(p + t * 0.02, 3),
        sv_fbm(p + float2(5.2, 1.3) + t * 0.015, 3)
    );
    return sv_fbm(p + 3.0 * q, 4);
}

// ── Layer 1: Background Nebula ──

static float3 sv_backgroundNebula(float2 uv, float t) {
    float2 p = uv * 1.8;
    float n1 = sv_warpedFbm(p, t);

    float3 deepPurple = float3(0.06, 0.02, 0.10);
    float3 midnightBlue = float3(0.03, 0.03, 0.09);
    float3 darkMauve = float3(0.08, 0.03, 0.07);

    float3 col = mix(deepPurple, midnightBlue, n1);
    col = mix(col, darkMauve, smoothstep(0.3, 0.7, n1) * 0.5);

    float bright = smoothstep(0.35, 0.65, n1) * 0.06;
    col += bright;

    return col;
}

// ── Layer 2: Aurora Ribbons ──

static float3 sv_auroraRibbons(float2 uv, float t) {
    float3 col = float3(0.0);
    float drift = SV_DRIFT_SPEED;

    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float yOffset = -0.4 + fi * 0.25 + sin(fi * 1.7) * 0.1;

        float2 warpP = uv * float2(1.5, 2.0) + float2(t * 0.03 * drift + fi * 3.0, fi * 2.7);
        float warpX = sv_fbm(warpP, 3) * 0.4;
        float warpY = sv_fbm(warpP + float2(3.3, 7.7), 3) * 0.3;

        float2 warped = float2(uv.x + warpX, uv.y + warpY);

        float ribbonNoise = sv_fbm(float2(warped.x * 2.5 + t * 0.04 * drift, warped.y * 3.0 + yOffset) + fi * 5.0, 4);
        float ridged = 1.0 - abs(ribbonNoise * 2.0 - 1.0);
        ridged = pow(ridged, 4.0);

        float ribbonNoise2 = sv_fbm(float2(warped.x * 4.0 - t * 0.025 * drift, warped.y * 5.0 + yOffset * 1.5) + fi * 8.0, 3);
        float ridged2 = 1.0 - abs(ribbonNoise2 * 2.0 - 1.0);
        ridged2 = pow(ridged2, 5.0);

        float ribbon = ridged * 0.7 + ridged2 * 0.3;

        float3 bandColor;
        if (i == 0) bandColor = float3(0.55, 0.45, 0.80);      // lavender
        else if (i == 1) bandColor = float3(0.80, 0.50, 0.60);  // soft pink
        else if (i == 2) bandColor = float3(0.85, 0.75, 0.50);  // pale gold
        else bandColor = float3(0.70, 0.45, 0.70);              // rose-purple

        float breath = 0.6 + 0.4 * sin(t * 0.08 + fi * 1.3);

        col += bandColor * ribbon * breath * 0.18;
    }

    return col;
}

// ── Layer 3: Star field ──

static float sv_starLayer(float2 uv, float scale, float threshold, float t, float speed, float seed) {
    float2 p = uv * scale;
    p.y += t * speed * SV_DRIFT_SPEED;
    p.x += t * speed * SV_DRIFT_SPEED * 0.3 + sin(t * 0.05) * 0.2;

    float2 cell = floor(p);
    float2 f = fract(p);

    float stars = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 cellId = cell + neighbor;
            float2 starCenter = sv_hash2(cellId + seed);

            float2 diff = neighbor + starCenter - f;
            float dist = length(diff);

            float present = step(threshold, sv_hash(cellId * 0.7 + seed + 77.0));

            float brightness = sv_hash(cellId * 1.3 + seed + 33.0);

            float twinklePhase = sv_hash(cellId * 2.1 + seed + 99.0) * SV_TAU;
            float twinkleSpeed = 0.8 + sv_hash(cellId * 3.7 + seed + 55.0) * 2.0;
            float twinkle = 0.5 + 0.5 * sin(t * twinkleSpeed + twinklePhase);

            float starSize = 0.015 + brightness * 0.02;
            float core = smoothstep(starSize, starSize * 0.1, dist);
            float glow = exp(-dist * dist / (starSize * starSize * 4.0));

            stars += (core * 1.2 + glow * 0.4) * brightness * twinkle * present;
        }
    }

    return stars * SV_STAR_DENSITY;
}

// ── Layer 5: Near star glow halos and flare pulses ──

static float sv_starFlare(float2 uv, float scale, float t, float seed) {
    float2 p = uv * scale;
    p.y += t * 0.12 * SV_DRIFT_SPEED;
    p.x += t * 0.04 * SV_DRIFT_SPEED;

    float2 cell = floor(p);
    float2 f = fract(p);
    float flare = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 cellId = cell + neighbor;
            float2 starCenter = sv_hash2(cellId + seed);
            float2 diff = neighbor + starCenter - f;
            float dist = length(diff);

            float isBright = step(0.82, sv_hash(cellId * 1.3 + seed + 33.0));
            float present = step(0.7, sv_hash(cellId * 0.7 + seed + 77.0));

            float flarePhase = sv_hash(cellId * 4.1 + seed + 111.0) * SV_TAU;
            float flareRate = 0.3 + sv_hash(cellId * 5.3 + seed + 222.0) * 0.4;
            float flarePulse = pow(max(sin(t * flareRate + flarePhase), 0.0), 12.0);

            float haloSize = 0.08 + flarePulse * 0.06;
            float halo = exp(-dist * dist / (haloSize * haloSize));

            flare += halo * flarePulse * isBright * present;
        }
    }

    return flare * SV_STAR_DENSITY;
}

// ── Layer 6: Connecting threads ──

static float sv_connectingThreads(float2 uv, float scale, float t, float seed) {
    float2 p = uv * scale;
    p.y += t * 0.08 * SV_DRIFT_SPEED;
    p.x += t * 0.025 * SV_DRIFT_SPEED;

    float2 cell = floor(p);
    float2 f = fract(p);
    float threads = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 neighbor = float2(float(dx), float(dy));
            float2 cellId = cell + neighbor;

            float present1 = step(0.6, sv_hash(cellId * 0.7 + seed + 77.0));
            if (present1 < 0.5) continue;

            float2 star1 = neighbor + sv_hash2(cellId + seed) - f;

            for (int ny = -1; ny <= 1; ny++) {
                for (int nx = 0; nx <= 1; nx++) {
                    if (nx == 0 && ny <= 0) continue;
                    float2 neighbor2 = neighbor + float2(float(nx), float(ny));
                    float2 cellId2 = cell + neighbor2;

                    float present2 = step(0.6, sv_hash(cellId2 * 0.7 + seed + 77.0));
                    if (present2 < 0.5) continue;

                    float2 star2 = neighbor2 + sv_hash2(cellId2 + seed) - f;

                    float starDist = length(star2 - star1);
                    if (starDist > 1.5) continue;

                    float2 pa = -star1;
                    float2 ba = star2 - star1;
                    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
                    float d = length(pa - ba * h);

                    float curve = sin(h * SV_PI + t * 0.3) * 0.015;
                    d = abs(d - curve);

                    float lineWidth = 0.008;
                    float line = exp(-d * d / (lineWidth * lineWidth));

                    float endFade = smoothstep(0.0, 0.15, h) * smoothstep(1.0, 0.85, h);

                    threads += line * endFade * 0.3;
                }
            }
        }
    }

    return threads;
}

// ── Layer 7: Traveling brightness wave ──

static float sv_travelingWave(float2 uv, float t) {
    float diag = uv.x * 0.7 + uv.y * 0.3;

    constexpr float WAVE_PERIOD = 5.0;
    float wavePos = fract(t / WAVE_PERIOD) * 3.0 - 1.0;

    constexpr float WAVE_WIDTH = 0.35;
    float wave = exp(-(diag - wavePos) * (diag - wavePos) / (WAVE_WIDTH * WAVE_WIDTH));

    float wavePos2 = fract((t + 2.5) / (WAVE_PERIOD * 1.3)) * 3.0 - 1.0;
    constexpr float WAVE_WIDTH2 = WAVE_WIDTH * 1.5;
    float wave2 = exp(-(diag - wavePos2) * (diag - wavePos2) / (WAVE_WIDTH2 * WAVE_WIDTH2));

    return wave * 0.35 + wave2 * 0.2;
}

// ── Main fragment function ──

fragment float4 fs_stardust_veil(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);

    float t = u.time;

    // ── Layer 1: Background nebula ──
    float3 col = sv_backgroundNebula(uv, t);

    // ── Layer 2: Aurora ribbons ──
    float3 aurora = sv_auroraRibbons(uv, t);
    col += aurora;

    // ── Layer 3: Far stardust field ──
    float farStars = sv_starLayer(uv, 35.0, 0.35, t, 0.02, 0.0);
    float3 farStarColor = float3(0.65, 0.72, 0.90);
    col += farStarColor * farStars * 0.25;

    // ── Layer 4: Mid stardust field ──
    float midStars = sv_starLayer(uv, 18.0, 0.45, t, 0.06, 100.0);
    float3 midStarColor = float3(0.80, 0.65, 0.85);
    col += midStarColor * midStars * 0.45;

    // ── Layer 5: Near stardust field ──
    float nearStars = sv_starLayer(uv, 8.0, 0.65, t, 0.12, 200.0);
    float3 nearStarColor = float3(0.90, 0.75, 0.60);
    col += nearStarColor * nearStars * 0.55;

    // Near star glow halos and flare pulses
    float flares = sv_starFlare(uv, 8.0, t, 200.0);
    float3 flareColor = float3(1.0, 0.85, 0.70);
    col += flareColor * flares * 0.6;

    // ── Layer 6: Connecting threads ──
    float threads = sv_connectingThreads(uv, 8.0, t, 200.0);
    float3 threadColor = float3(0.60, 0.50, 0.75);
    col += threadColor * threads * 0.15;

    // Mid-layer threads too
    float threads2 = sv_connectingThreads(uv, 18.0, t, 100.0);
    col += threadColor * threads2 * 0.08;

    // ── Layer 7: Traveling brightness wave ──
    float wave = sv_travelingWave(uv, t);
    col *= 1.0 + wave;
    float3 waveColor = float3(0.70, 0.60, 0.85);
    col += waveColor * wave * 0.04;

    // ── Additional depth: faint overall shimmer ──
    float shimmer = sv_noise(uv * 12.0 + t * 0.5) * sv_noise(uv * 8.0 - t * 0.3);
    col += float3(0.75, 0.65, 0.85) * shimmer * 0.015;

    // ── Vignette ──
    float dist = length(uv);
    float vignette = 1.0 - smoothstep(0.5, 1.4, dist);
    col *= 0.7 + vignette * 0.3;

    // ── Film grain ──
    float grain = (fract(sin(dot(in.pos.xy, float2(12.9898, 78.233)) + fract(t * 0.1) * 100.0) * 43758.5453) - 0.5) * 0.012;
    col += grain;

    // ── Tone mapping: soft S-curve ──
    col = max(col, float3(0.0));
    col = col / (col + 0.85) * 1.15;

    // ── Subtle color grading ──
    col = pow(col, float3(0.97, 1.0, 1.04));

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(clamp(col, 0.0, 1.0), 1.0);
}
