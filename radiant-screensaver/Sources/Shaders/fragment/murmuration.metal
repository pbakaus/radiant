#include "../Common.metal"

// ─── Murmuration: Boid flocking as a density/flow field ───
// Ported from static/murmuration.html
// Original: 2500 boids with separation/alignment/cohesion, wind, impulse
// waves, and a twilight sky backdrop with mountain silhouettes.
// Fragment shader reimagines this as animated noise-driven flow field that
// creates swirling density bands resembling a starling murmuration against
// a twilight gradient sky with layered mountain silhouettes.

constant float MU_FLOCK_SPEED [[maybe_unused]] = 1.0;
constant float MU_DENSITY_CONTRAST = 1.5;
constant float MU_WIND_SCALE = 0.0003;
constant float MU_TRAIL_STRENGTH = 0.7;
constant int MU_LAYERS = 4;
constant float MU_MOUNTAIN_OPACITY = 0.35;

// ── Sky palette (twilight amber) ──
constant float3 MU_SKY_TOP    = float3(210.0, 178.0, 140.0) / 255.0;
constant float3 MU_SKY_MID    = float3(198.0, 160.0, 122.0) / 255.0;
constant float3 MU_SKY_BOTTOM = float3(170.0, 135.0, 100.0) / 255.0;

// ── Mountain layer colors ──
constant float3 MU_MT_FAR  = float3(192.0, 162.0, 132.0) / 255.0;
constant float3 MU_MT_MID  = float3(168.0, 135.0, 105.0) / 255.0;
constant float3 MU_MT_NEAR = float3(138.0, 108.0, 80.0) / 255.0;

// ── Bird colors ──
constant float3 MU_BIRD_DIM    = float3(120.0, 80.0, 45.0) / 255.0;
constant float3 MU_BIRD_BRIGHT = float3(95.0, 58.0, 28.0) / 255.0;

// ── Hash ──
static float mu_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth noise ──
static float mu_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = mu_hash(i);
    float b = mu_hash(i + float2(1.0, 0.0));
    float c = mu_hash(i + float2(0.0, 1.0));
    float d = mu_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float mu_fbm(float2 p) {
    float v = 0.0;
    float amp = 0.65;
    for (int i = 0; i < 4; i++) {
        v += mu_noise(p) * amp;
        p *= 2.1;
        amp *= 0.45;
    }
    return v;
}

// ── Mountain silhouette SDF ──
static float mu_mountain(float2 uv, float baseY, float amp, float freq,
                          float phase, int octaves) {
    float h = 0.0;
    float a = 1.0;
    float f = 1.0;
    for (int o = 0; o < 3; o++) {
        if (o >= octaves) break;
        h += sin(uv.x * freq * f / 0.001 + phase + float(o) * 13.7) * a;
        h += cos(uv.x * freq * f * 0.7 / 0.001 + phase * 0.6 + float(o) * 7.3) * a * 0.6;
        f *= 2.1;
        a *= 0.45;
    }
    float mountainY = baseY + h * amp;
    return uv.y - mountainY; // positive = below mountain
}

// ── Flow field for flock direction ──
static float2 mu_flowField(float2 p, float t) {
    float globalAngle = mu_noise(float2(t * 0.00015 * 15.0, 0.0)) * 6.2832;
    float localVar = mu_fbm(p * MU_WIND_SCALE / 0.001 * 0.3 + float2(0.0, t * 0.00007 * 3.0)) * 1.5 - 0.75;
    float windAngle = globalAngle + localVar;
    return float2(cos(windAngle), sin(windAngle));
}

// ── Flock density field ──
// Simulate boid clustering as animated noise bands
static float mu_flockDensity(float2 uv, float t) {
    float density = 0.0;

    // Wandering attractor position (from noise)
    float at = t * 0.15;
    float2 attractor = float2(0.1 + mu_noise(float2(at, 3.7)) * 0.8,
                               0.1 + mu_noise(float2(7.1, at)) * 0.8);

    // Distance to attractor influences density
    float atDist = length(uv - attractor);
    for (int i = 0; i < MU_LAYERS; i++) {
        float fi = float(i);
        float scale = 3.0 + fi * 2.0;
        float speed = 0.3 + fi * 0.15;

        // Advect noise along flow field
        float2 flow = mu_flowField(uv, t);
        float2 advected = uv * scale + flow * speed * t * 0.1;
        advected += float2(fi * 13.7, fi * 7.3);

        float n = mu_noise(advected);
        // Create banded density (like swirling streams of birds)
        float band = sin(n * 20.0 + t * speed * 0.5) * 0.5 + 0.5;
        band = smoothstep(0.3, 0.7, band);

        density += band * (1.0 / float(MU_LAYERS));
    }

    // Concentrate density near the attractor
    density = mix(density * 0.3, density, smoothstep(0.8, 0.1, atDist));

    // Impulse wave effect: periodic sweeping density waves
    float impulseFront = fmod(t * 0.08, 1.5);
    float impulseAngle = mu_noise(float2(floor(t * 0.08 / 1.5), 0.0)) * 6.2832;
    float2 impulseDir = float2(cos(impulseAngle), sin(impulseAngle));
    float proj = dot(uv - 0.5, impulseDir);
    float impulseDist = abs(proj - impulseFront + 0.5);
    float impulseWave = exp(-impulseDist * impulseDist * 40.0);
    density += impulseWave * 0.3;

    return clamp(density * MU_DENSITY_CONTRAST, 0.0, 1.0);
}

fragment float4 fs_murmuration(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float t = u.time;

    // ── Twilight sky gradient ──
    float3 sky;
    if (uv.y < 0.4) {
        sky = mix(MU_SKY_TOP, MU_SKY_MID, uv.y / 0.4);
    } else {
        sky = mix(MU_SKY_MID, MU_SKY_BOTTOM, (uv.y - 0.4) / 0.6);
    }

    float3 col = sky;

    // ── Mountain silhouettes ──
    // Far mountains
    float mt1 = mu_mountain(uv, 0.46, 0.09, 0.0025, 42.5, 3);
    if (mt1 > 0.0) {
        col = mix(col, MU_MT_FAR, MU_MOUNTAIN_OPACITY);
    }
    // Mid mountains
    float mt2 = mu_mountain(uv, 0.62, 0.08, 0.003, 197.3, 3);
    if (mt2 > 0.0) {
        col = mix(col, MU_MT_MID, MU_MOUNTAIN_OPACITY * 1.2);
    }
    // Near mountains
    float mt3 = mu_mountain(uv, 0.79, 0.05, 0.0035, 103.8, 2);
    if (mt3 > 0.0) {
        col = mix(col, MU_MT_NEAR, MU_MOUNTAIN_OPACITY * 1.4);
    }

    // ── Flock density ──
    // Only render birds in the upper portion (above near mountains)
    float birdMask = smoothstep(0.75, 0.3, uv.y);
    float density = mu_flockDensity(uv, t) * birdMask;

    // ── Bird rendering as dark streaks against the sky ──
    // Flow direction for streak orientation
    float2 flow = mu_flowField(uv, t);
    float flowAngle = atan2(flow.y, flow.x);

    // High-frequency aligned noise for individual bird-like marks
    float2 birdDir = float2(cos(flowAngle), sin(flowAngle));
    float2 birdPerp = float2(-birdDir.y, birdDir.x);
    float birdCoordPara = dot(uv * 200.0, birdDir);
    float birdCoordPerp = dot(uv * 200.0, birdPerp);

    float birdNoise = mu_noise(float2(birdCoordPara * 0.5, birdCoordPerp * 2.0) + t * 0.3);
    float birdMark = smoothstep(0.5, 0.55, birdNoise);

    // Combine density with bird marks
    float birdAlpha = density * mix(0.4, 1.0, birdMark) * MU_TRAIL_STRENGTH;

    // Color: darker birds against bright sky
    float3 birdColor = mix(MU_BIRD_DIM, MU_BIRD_BRIGHT, density);
    col = mix(col, birdColor, birdAlpha * 0.6);

    // ── Subtle grain texture ──
    float grain = mu_hash(uv * 1000.0 + fract(t * 0.1)) * 0.03 - 0.015;
    col += float3(grain);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
