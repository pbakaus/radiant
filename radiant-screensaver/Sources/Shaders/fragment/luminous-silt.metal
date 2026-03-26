#include "../Common.metal"

// ─── Luminous Silt: Dense particle field creating color clouds ───
// Ported from static/luminous-silt.html
// Original: 18K particles flowing through a noise field with bilinear
// color gradient across canvas corners. Fragment shader reimagines this
// as noise-driven flow field density + rotating color gradient.

constant float LS_DRIFT_SPEED = 0.6;
constant float LS_NOISE_SCALE = 3.0;       // spatial frequency of flow field
constant float LS_DENSITY_LAYERS = 5.0;     // number of overlaid noise octaves
constant float LS_PARTICLE_BRIGHTNESS = 0.6;
constant float LS_SPARKLE_THRESHOLD = 0.92; // top brightness percentile = sparkles
constant float LS_ROTATION_SPEED = 0.006;   // color gradient rotation speed
constant float LS_TRAIL_FADE [[maybe_unused]] = 0.85;

// ── Corner colors (matching original) ──
constant float3 LS_CORNER_TL = float3(50.0, 80.0, 220.0) / 255.0;   // deep cobalt
constant float3 LS_CORNER_TR = float3(180.0, 70.0, 140.0) / 255.0;  // rose/violet
constant float3 LS_CORNER_BL = float3(40.0, 170.0, 170.0) / 255.0;  // teal
constant float3 LS_CORNER_BR = float3(240.0, 150.0, 50.0) / 255.0;  // amber/orange
constant float3 LS_CENTER_C  = float3(230.0, 215.0, 190.0) / 255.0; // warm white

// ── Hash ──
static float ls_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth value noise ──
static float ls_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ls_hash(i);
    float b = ls_hash(i + float2(1.0, 0.0));
    float c = ls_hash(i + float2(0.0, 1.0));
    float d = ls_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM noise ──
static float ls_fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    float2 shift = float2(100.0);
    for (int i = 0; i < 5; i++) {
        v += amp * ls_noise(p);
        p = p * 2.1 + shift;
        amp *= 0.5;
    }
    return v;
}

// ── Flow field angle from noise ──
static float ls_flowAngle(float2 p, float t) {
    return ls_fbm(p * 0.5 + float2(0.0, t * 2.0)) * 6.2832;
}

// ── Bilinear gradient with rotating corners ──
static float3 ls_gradient(float2 uv, float rotAngle) {
    // Rotate UV around center
    float2 c = uv - 0.5;
    float ca = cos(rotAngle), sa = sin(rotAngle);
    float2 r = float2(c.x * ca - c.y * sa, c.x * sa + c.y * ca) + 0.5;
    r = clamp(r, 0.0, 1.0);

    // Bilinear interpolation of corners
    float3 col = LS_CORNER_TL * (1.0 - r.x) * (1.0 - r.y)
               + LS_CORNER_TR * r.x * (1.0 - r.y)
               + LS_CORNER_BL * (1.0 - r.x) * r.y
               + LS_CORNER_BR * r.x * r.y;

    // Blend toward warm white at center
    float dist = length(c) * 2.0;
    float centerW = 1.0 - clamp(dist, 0.0, 1.0);
    centerW *= centerW;
    col = mix(col, LS_CENTER_C, centerW);

    return col;
}

// ── Particle density approximation ──
// Instead of tracking individual particles, we compute a density field
// based on advected noise that mimics particle accumulation.
static float ls_particleDensity(float2 uv, float t) {
    float density = 0.0;

    // Multiple noise layers at different scales simulate particle clustering
    for (int i = 0; i < int(LS_DENSITY_LAYERS); i++) {
        float fi = float(i);
        float scale = LS_NOISE_SCALE * (1.0 + fi * 0.7);
        float speed = LS_DRIFT_SPEED * (0.3 + fi * 0.2);

        // Advect the noise sample position along the flow field
        float2 advected = uv * scale;
        float angle = ls_flowAngle(uv * LS_NOISE_SCALE * 0.3, t * 0.6);
        advected += float2(cos(angle), sin(angle)) * speed * t * 0.5;

        float n = ls_noise(advected + float2(fi * 17.3, fi * 31.7));

        // Sharpen to simulate discrete particles
        float sharpened = smoothstep(0.3, 0.7, n);
        density += sharpened * (1.0 / LS_DENSITY_LAYERS);
    }

    return density;
}

fragment float4 fs_luminous_silt(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float t = u.time;

    // Slow rotation angle for the color gradient
    float rotAngle = t * LS_ROTATION_SPEED * LS_DRIFT_SPEED;

    // Compute color gradient at this pixel
    float3 gradColor = ls_gradient(uv, rotAngle);

    // Compute particle density
    float density = ls_particleDensity(uv, t);

    // Sparkle layer: high-frequency bright spots
    float sparkle = ls_noise(uv * 80.0 + float2(t * 0.5, t * 0.7));
    sparkle = smoothstep(LS_SPARKLE_THRESHOLD, 1.0, sparkle);
    float sparkleIntensity = sparkle * 0.4;

    // Compose: dark background + colored density + sparkles
    float3 col = float3(0.0);

    // Base particle density glow
    float alpha = density * LS_PARTICLE_BRIGHTNESS;
    col += gradColor * alpha;

    // Sparkle highlights (brighter, whiter)
    float3 sparkleCol = mix(gradColor, float3(1.0), 0.5);
    col += sparkleCol * sparkleIntensity;

    // Subtle flow field visualization: thin bright streaks
    float flowAngle = ls_flowAngle(uv * LS_NOISE_SCALE * 0.3, t * 0.6);
    float2 flowDir = float2(cos(flowAngle), sin(flowAngle));
    float streak = ls_noise(uv * 40.0 + flowDir * t * 0.3);
    streak = smoothstep(0.6, 0.65, streak);
    col += gradColor * streak * 0.08;

    // Very subtle vignette
    float vig = 1.0 - 0.2 * length(uv - 0.5);
    col *= vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
