#include "../Common.metal"

// ─── Rain on Glass: Procedural rain drops with refraction effect ───
// Ported from static/rain-on-glass.html
// NOTE: The original uses Canvas 2D drop physics + WebGL refraction compositing.
// This Metal port replaces the texture-based drop map with procedural noise-based
// drop patterns, producing a similar refraction aesthetic without compute shaders.

constant float RG_PI = 3.14159265359;
constant float RG_TAU = 6.28318530718;

// ── Hash functions ──
static float rg_hash(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float rg_hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

// ── Value noise ──
static float rg_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = rg_hash(i);
    float b = rg_hash(i + float2(1.0, 0.0));
    float c = rg_hash(i + float2(0.0, 1.0));
    float d = rg_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM noise ──
static float rg_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0);
    for (int i = 0; i < 4; i++) {
        v += a * rg_vnoise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ── Procedural raindrop layer ──
// Creates a grid of drops at a given scale, each with position jitter,
// returning drop shape (alpha), refraction normal (xy), and depth (z).
static float4 rg_dropLayer(float2 uv, float t, float scale, float seed) {
    float2 gridUV = uv * scale;
    float2 cell = floor(gridUV);
    float2 frac_uv = fract(gridUV) - 0.5;

    float4 bestDrop = float4(0.0);

    // Check 3x3 neighborhood for drops
    for (int yi = -1; yi <= 1; yi++) {
        for (int xi = -1; xi <= 1; xi++) {
            float2 neighbor = float2(float(xi), float(yi));
            float2 cellId = cell + neighbor;

            // Random drop properties per cell
            float h = rg_hash(cellId + seed);
            float h2 = rg_hash(cellId + seed + 73.7);
            float h3 = rg_hash(cellId + seed + 137.3);

            // Only ~40% of cells have drops
            if (h < 0.4) continue;

            // Drop position within cell (jittered)
            float2 dropPos = neighbor + float2(h2, h3) * 0.6 - 0.3;

            // Drop falls over time — each drop has a different phase
            float fallSpeed = 0.3 + h * 0.4;
            float phase = h2 * 100.0;
            float fallOffset = t * fallSpeed + phase;
            // Drops fall, wrap around
            float yOff = fract(fallOffset * 0.1) * 2.0 - 1.0;
            dropPos.y += yOff;

            // Tail/streak behind the drop
            float2 delta = frac_uv - dropPos;
            float tailLen = 0.15 + h3 * 0.1;

            // Main drop (elliptical)
            float dropSize = 0.06 + h * 0.08;
            float2 squash = float2(1.0, 0.7); // slightly wide
            float dist = length(delta * squash);
            float drop = smoothstep(dropSize, dropSize * 0.3, dist);

            // Streak/trail above the drop
            float trail = 0.0;
            if (delta.y > 0.0 && abs(delta.x) < 0.015) {
                float trailDist = delta.y;
                float wobble = sin(delta.y * 40.0 + h * 20.0) * 0.003;
                float trailWidth = 0.012 - trailDist * 0.02;
                trailWidth = max(trailWidth, 0.002);
                trail = smoothstep(trailWidth, trailWidth * 0.3, abs(delta.x + wobble));
                trail *= smoothstep(tailLen, 0.0, trailDist);
                trail *= 0.5;
            }

            float alpha = max(drop, trail);
            if (alpha > bestDrop.w) {
                // Refraction normal from distance to center
                float2 norm = delta / (dropSize + 0.001);
                norm = clamp(norm, -1.0, 1.0);
                // Depth: bigger drops refract more
                float depth = drop * (0.5 + h * 0.5);
                bestDrop = float4(norm * 0.5 + 0.5, depth, alpha);
            }
        }
    }

    return bestDrop;
}

// ── Background: blurry city lights behind rainy glass ──
static float3 rg_cityBg(float2 uv, float t) {
    // Dark base with warm bokeh-like blobs
    float3 col = float3(0.02, 0.018, 0.015);

    // Layered bokeh blobs
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float2 pos = float2(
            rg_hash1(fi * 7.3 + 1.0) * 2.0 - 1.0,
            rg_hash1(fi * 11.7 + 3.0) * 2.0 - 1.0
        ) * 0.6;
        float size = 0.08 + rg_hash1(fi * 3.1 + 5.0) * 0.15;
        float d = length(uv - pos);
        float blob = smoothstep(size, size * 0.2, d);

        // Warm amber/orange tones
        float hue = rg_hash1(fi * 5.3 + 9.0);
        float3 blobColor = float3(
            0.5 + hue * 0.5,
            0.25 + hue * 0.2,
            0.08 + hue * 0.1
        );
        col += blobColor * blob * 0.15;
    }

    // Subtle noise texture
    float n = rg_fbm(uv * 3.0 + t * 0.01);
    col += float3(0.03, 0.02, 0.01) * n;

    return col;
}

fragment float4 fs_rain_on_glass(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 centered = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;

    // ── Background (blurry scene behind glass) ──
    float3 bgColor = rg_cityBg(centered, t);

    // ── Foreground (sharper version for refracted areas) ──
    // Slightly brighter and more saturated version of background
    float3 fgColor = bgColor * 1.3 + float3(0.02, 0.015, 0.01);

    // ── Rain drop layers at different scales ──
    float4 drops1 = rg_dropLayer(uv, t, 8.0, 0.0);
    float4 drops2 = rg_dropLayer(uv, t * 1.2, 14.0, 47.3);
    float4 drops3 = rg_dropLayer(uv, t * 0.8, 22.0, 91.7);

    // Combine drop layers (largest wins)
    float4 drops = drops1;
    if (drops2.w > drops.w) drops = drops2;
    if (drops3.w > drops.w) drops = drops3;

    // ── Refraction ──
    float2 refraction = (drops.xy - 0.5) * 2.0;
    float minRefraction = 256.0;
    float refractionDelta = 512.0;
    float depth = drops.z;
    float alpha = drops.w;

    float2 pixelSize = 1.0 / u.resolution;
    float2 refractionOffset = pixelSize * refraction * (minRefraction + depth * refractionDelta);

    // Refracted background lookup (offset UV for the "lens" effect)
    float2 refractedUV = (in.pos.xy + refractionOffset * u.resolution - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float3 refractedColor = rg_cityBg(refractedUV, t) * 1.3 + float3(0.02, 0.015, 0.01);

    // ── Shine/specular highlight on drops ──
    float shine = pow(max(0.0, 1.0 - length(refraction)), 4.0) * depth;
    refractedColor += float3(0.3, 0.25, 0.2) * shine;

    // ── Composite: blend refracted foreground over blurry background ──
    float3 col = mix(bgColor, refractedColor, alpha);

    // ── Drop shadow (subtle darkening below drops) ──
    float shadow = drops1.w * 0.08 + drops2.w * 0.05;
    col *= 1.0 - shadow * 0.3;

    // ── Glass tint — slight blue-green ──
    col = mix(col, col * float3(0.9, 0.95, 1.0), 0.15);

    // ── Vignette ──
    float vig = length(centered * 0.8);
    vig = 1.0 - smoothstep(0.4, 1.2, vig);
    col *= 0.7 + vig * 0.3;

    // ── Film grain ──
    float grain = (rg_hash(in.pos.xy + fract(t * 37.0) * 500.0) - 0.5) * 0.015;
    col += grain;

    col = max(col, float3(0.0));
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
