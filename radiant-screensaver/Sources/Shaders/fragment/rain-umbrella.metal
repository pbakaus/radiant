#include "../Common.metal"

// ─── Rain Umbrella: Rain on an umbrella canopy with refraction + rib structure ───
// Ported from static/rain-umbrella.html
// NOTE: The original uses Canvas 2D drop physics + WebGL refraction compositing.
// This Metal port replaces texture-based drops with procedural noise patterns,
// and includes the umbrella rib/panel structure from the original fragment shader.

constant float RU_PI = 3.14159265359;
constant float RU_TAU = 6.28318530718;
constant float RU_NUM_RIBS = 8.0;

// ── Hash functions ──
static float ru_hash(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float ru_hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

// ── Value noise ──
static float ru_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ru_hash(i);
    float b = ru_hash(i + float2(1.0, 0.0));
    float c = ru_hash(i + float2(0.0, 1.0));
    float d = ru_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float ru_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0);
    for (int i = 0; i < 4; i++) {
        v += a * ru_vnoise(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ── Procedural raindrop layer ──
static float4 ru_dropLayer(float2 uv, float t, float scale, float seed) {
    float2 gridUV = uv * scale;
    float2 cell = floor(gridUV);
    float2 frac_uv = fract(gridUV) - 0.5;

    float4 bestDrop = float4(0.0);

    for (int yi = -1; yi <= 1; yi++) {
        for (int xi = -1; xi <= 1; xi++) {
            float2 neighbor = float2(float(xi), float(yi));
            float2 cellId = cell + neighbor;

            float h = ru_hash(cellId + seed);
            float h2 = ru_hash(cellId + seed + 73.7);
            float h3 = ru_hash(cellId + seed + 137.3);

            if (h < 0.35) continue;

            float2 dropPos = neighbor + float2(h2, h3) * 0.6 - 0.3;

            // Drops slide outward on umbrella dome
            float2 center = float2(0.5, 0.5) * scale;
            float2 radialDir = normalize(cellId - center);
            float slideSpeed = 0.15 + h * 0.2;
            float phase = h2 * 100.0;
            float slideOffset = fract((t * slideSpeed + phase) * 0.05);
            dropPos += radialDir * slideOffset * 0.3;

            float2 delta = frac_uv - dropPos;

            // Drop shape
            float dropSize = 0.05 + h * 0.06;
            float dist = length(delta);
            float drop = smoothstep(dropSize, dropSize * 0.3, dist);

            // Small trail
            float trail = 0.0;
            float2 trailDir = -radialDir;
            float trailProj = dot(delta, trailDir);
            if (trailProj > 0.0) {
                float trailPerp = abs(dot(delta, float2(-trailDir.y, trailDir.x)));
                float trailWidth = 0.01 - trailProj * 0.015;
                trailWidth = max(trailWidth, 0.002);
                trail = smoothstep(trailWidth, trailWidth * 0.3, trailPerp);
                trail *= smoothstep(0.12, 0.0, trailProj);
                trail *= 0.4;
            }

            float alpha = max(drop, trail);
            if (alpha > bestDrop.w) {
                float2 norm = delta / (dropSize + 0.001);
                norm = clamp(norm, -1.0, 1.0);
                float depth = drop * (0.5 + h * 0.5);
                bestDrop = float4(norm * 0.5 + 0.5, depth, alpha);
            }
        }
    }

    return bestDrop;
}

// ── Umbrella canopy color (fabric + walking scene beneath) ──
static float3 ru_canopyColor(float2 uv, float t) {
    // Rich fabric color — deep warm tones
    float3 col = float3(0.35, 0.12, 0.08);

    // Subtle fabric texture
    float tex = ru_fbm(uv * 20.0);
    col += float3(0.03, 0.015, 0.01) * tex;

    // Radial gradient from center (dome curvature lighting)
    float dist = length(uv - float2(0.5, 0.5));
    float dome = 1.0 - smoothstep(0.0, 0.6, dist);
    col *= 0.7 + dome * 0.4;

    return col;
}

// ── Umbrella rib structure overlay ──
static float3 ru_applyUmbrellaRibs(float3 color, float2 pos, float2 resolution) {
    float2 center = float2(0.5, 0.5);
    float2 dir = pos - center;
    float aspect = resolution.x / resolution.y;
    dir.x *= aspect;
    float dist = length(dir);
    float ang = atan2(dir.y, dir.x);

    float SECTOR = RU_TAU / RU_NUM_RIBS;

    // Angular distance to nearest rib
    // GLSL mod always positive; replicate with x - y*floor(x/y)
    float angPlusSector = ang + SECTOR * 0.5;
    float secAng = (angPlusSector - SECTOR * floor(angPlusSector / SECTOR)) - SECTOR * 0.5;

    // Organic wobble
    float ribIdx = floor((ang + RU_PI) / SECTOR);
    float wobble = sin(dist * 16.0 + ribIdx * 4.7) * 0.018 * dist;
    wobble += sin(dist * 37.0 - ribIdx * 2.3) * 0.008 * dist;
    wobble *= smoothstep(0.0, 0.1, dist);
    secAng += wobble;

    float angDist = abs(secAng);
    float screenDist = angDist * dist;

    // Rib width
    float ribW = mix(0.006, 0.0008, smoothstep(0.0, 0.55, dist));
    float rib = 1.0 - smoothstep(ribW * 0.15, ribW, screenDist);
    rib *= 1.0 - smoothstep(0.55, 0.75, dist);

    // 3D depth
    float side = step(0.0, secAng) * 2.0 - 1.0;
    float highlight = rib * 0.06 * max(0.0, side);
    float shadow = rib * 0.14;

    // Panel billowing
    float panelEdge = smoothstep(0.0, SECTOR * 0.35 * max(0.01, dist), screenDist);
    float panelShade = (1.0 - panelEdge * panelEdge) * 0.025 * smoothstep(0.03, 0.25, dist);

    // Alternating panel tint
    float panelIdx = floor((ang + RU_PI) / SECTOR);
    // Use x - y*floor(x/y) for mod with potentially negative input
    float panelMod = panelIdx - 2.0 * floor(panelIdx / 2.0);
    float panelTint = panelMod * 0.012 - 0.006;

    // Center cap
    float cap = (1.0 - smoothstep(0.008, 0.016, dist)) * 0.18;
    float ring = max(0.0, 1.0 - abs(dist - 0.02) / 0.004) * 0.06;

    // Dome vignette
    float vig = smoothstep(0.05, 0.7, dist);
    vig = vig * vig * 0.14;

    float darken = shadow + panelShade + cap + ring + vig;
    color = color * (1.0 - darken) + float3(highlight + panelTint);

    return color;
}

fragment float4 fs_rain_umbrella(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 centered = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;

    // Walking offset (from the original shader)
    float2 walkOffset = float2(t * 0.03, sin(t * 0.5) * 0.003);

    // ── Background (canopy fabric) ──
    float3 bgColor = ru_canopyColor(uv + walkOffset * 0.1, t);

    // ── Foreground (brighter, for refracted areas) ──
    float3 fgColor = bgColor * 1.2 + float3(0.03, 0.02, 0.01);

    // ── Rain drop layers ──
    float4 drops1 = ru_dropLayer(uv, t, 10.0, 0.0);
    float4 drops2 = ru_dropLayer(uv, t * 1.1, 16.0, 53.1);
    float4 drops3 = ru_dropLayer(uv, t * 0.9, 24.0, 107.3);

    // Combine drop layers
    float4 drops = drops1;
    if (drops2.w > drops.w) drops = drops2;
    if (drops3.w > drops.w) drops = drops3;

    // ── Refraction ──
    float2 refraction = (drops.xy - 0.5) * 2.0;
    float minRefraction = 200.0;
    float refractionDelta = 400.0;
    float depth = drops.z;
    float alpha = drops.w;

    float2 pixelSize = 1.0 / u.resolution;
    float2 refractionOffset = pixelSize * refraction * (minRefraction + depth * refractionDelta);

    // Refracted look
    float2 refractedUV = uv + refractionOffset + walkOffset * 0.1;
    float3 refractedColor = ru_canopyColor(refractedUV, t) * 1.2 + float3(0.03, 0.02, 0.01);

    // Shine
    float shine = pow(max(0.0, 1.0 - length(refraction)), 4.0) * depth;
    refractedColor += float3(0.25, 0.2, 0.15) * shine;

    // ── Composite ──
    float3 col = mix(bgColor, refractedColor, alpha);

    // ── Apply umbrella rib structure ──
    col = ru_applyUmbrellaRibs(col, uv, u.resolution);

    // ── Slight wet sheen ──
    float wetSheen = ru_fbm(uv * 15.0 + t * 0.02) * 0.04;
    col += float3(wetSheen);

    // ── Vignette ──
    float vig = length(centered * 0.8);
    vig = 1.0 - smoothstep(0.4, 1.1, vig);
    col *= 0.75 + vig * 0.25;

    // ── Film grain ──
    float grain = (ru_hash(in.pos.xy + fract(t * 41.0) * 500.0) - 0.5) * 0.012;
    col += grain;

    col = max(col, float3(0.0));
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
