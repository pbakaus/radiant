#include "../Common.metal"

// ─── Gilt Mosaic: Byzantine golden mosaic wall catching candlelight ───
// Ported from static/gilt-mosaic.html

constant float GM_PI = 3.14159265359;
constant float GM_TAU = 6.28318530718;
constant float GM_LIGHT_SPEED = 0.4;
constant float GM_TILE_SCALE = 1.0;
constant float GM_ANIM_MODE = 1.0;
constant float GM_WAVE_SPEED = 4.0;
constant float GM_WAVE_DELAY = 1.5;
constant float GM_WAVE_DIR = 0.0;

// ── Pseudo-random hash ──
static float gm_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float2 gm_hash2(float2 p) {
    return float2(
        fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, float2(269.5, 183.3))) * 43758.5453)
    );
}

// ── Smooth value noise ──
static float gm_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = gm_hash(i);
    float b = gm_hash(i + float2(1.0, 0.0));
    float c = gm_hash(i + float2(0.0, 1.0));
    float d = gm_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Tile grid with jitter ──
static float4 gm_tileGrid(float2 p, float scale) {
    float2 sp = p * scale;
    float2 id = floor(sp);
    float2 f = fract(sp);
    float2 jitter = gm_hash2(id) * 0.12 - 0.06;
    f -= jitter;
    return float4(f, id);
}

// ── Per-tile normal ──
static float3 gm_tileNormal(float2 id) {
    float h1 = gm_hash(id * 1.731 + 17.3);
    float h2 = gm_hash(id * 2.419 + 31.7);
    float tiltX = (h1 - 0.5) * 0.35;
    float tiltY = (h2 - 0.5) * 0.35;
    return normalize(float3(tiltX, tiltY, 1.0));
}

// ── Grout detection ──
static float gm_groutMask(float2 f, float groutWidth) {
    float2 edge = smoothstep(float2(0.0), float2(groutWidth), f) *
                  smoothstep(float2(0.0), float2(groutWidth), float2(1.0) - f);
    return edge.x * edge.y;
}

// ── Surface micro-roughness ──
static float gm_tileRoughness(float2 f, float2 id) {
    float n1 = gm_noise(f * 8.0 + id * 3.7);
    float n2 = gm_noise(f * 16.0 + id * 7.1 + 50.0);
    return n1 * 0.6 + n2 * 0.4;
}

// ── Wave flip ──
static float2 gm_waveFlip(float2 tileCenter, float rawTime, float2 aspect) {
    float sweepDur = GM_WAVE_SPEED;
    float cycleDur = sweepDur + GM_WAVE_DELAY;
    float cycleT = rawTime - cycleDur * floor(rawTime / cycleDur);
    float waveCount = floor(rawTime / cycleDur);
    float isOddWave = waveCount - 2.0 * floor(waveCount / 2.0);

    float sweepRaw = clamp(cycleT / sweepDur, 0.0, 1.0);
    float sweep = sweepRaw * sweepRaw * (3.0 - 2.0 * sweepRaw);

    float dir = floor(GM_WAVE_DIR + 0.5);
    float axisLen = aspect.x;
    float tilePos = tileCenter.x;
    if (dir == 1.0) { tilePos = aspect.x - tileCenter.x; }
    else if (dir == 2.0) { tilePos = 1.0 - tileCenter.y; axisLen = 1.0; }
    else if (dir == 3.0) { tilePos = tileCenter.y; axisLen = 1.0; }

    float waveX = sweep * (axisLen + 0.6) - 0.3;

    float tileRand = gm_hash(tileCenter * 31.7 + float2(17.3, 59.1));
    float stagger = tileRand * 0.06;
    float dist = tilePos - waveX + stagger;

    float flipProgress = smoothstep(0.5, -0.3, dist);
    float flipAngle = (isOddWave + flipProgress) * GM_PI;

    float inTransition = smoothstep(0.6, 0.0, abs(dist + 0.1));
    return float2(flipAngle, inTransition);
}

fragment float4 fs_gilt_mosaic(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 aspect = float2(u.resolution.x / u.resolution.y, 1.0);
    float2 p = uv * aspect;
    float t = u.time * GM_LIGHT_SPEED;

    // Tile grid
    float scale = 18.0 * GM_TILE_SCALE;
    float4 tile = gm_tileGrid(p, scale);
    float2 f = tile.xy;
    float2 id = tile.zw;

    // Grout
    float groutW = 0.06;
    float tMask = gm_groutMask(f, groutW);

    // Per-tile properties
    float tileHash = gm_hash(id);
    float tileHash2 = gm_hash(id + 200.0);
    float tileHash3 = gm_hash(id + 400.0);
    float3 N = gm_tileNormal(id);

    // Micro-surface variation
    float roughness = gm_tileRoughness(f, id);
    N = normalize(N + float3(
        (roughness - 0.5) * 0.12,
        (gm_noise(f * 12.0 + id * 5.3) - 0.5) * 0.12,
        0.0
    ));

    // Wave flip animation
    float2 tileCenter = (id + 0.5) / scale;
    float2 flipData = gm_waveFlip(tileCenter, u.time, aspect);
    float flipAngle = flipData.x * GM_ANIM_MODE;
    float inTransition = flipData.y * GM_ANIM_MODE;

    float cosFlip = cos(flipAngle);
    float abscos = abs(cosFlip);
    float dir = floor(GM_WAVE_DIR + 0.5);
    bool flipVertical = (dir == 2.0 || dir == 3.0);

    // 3D perspective compression
    if (flipVertical) {
        f.y = (f.y - 0.5) / max(abscos, 0.04) + 0.5;
    } else {
        f.x = (f.x - 0.5) / max(abscos, 0.04) + 0.5;
    }
    float inBounds = step(0.0, f.x) * step(f.x, 1.0) * step(0.0, f.y) * step(f.y, 1.0);
    tMask *= inBounds;

    float isBack = step(cosFlip, 0.0);

    // Rotate normal
    float sinFlip = sin(flipAngle);
    float3 flippedN;
    if (flipVertical) {
        flippedN = float3(N.x, N.y * cosFlip + N.z * sinFlip, -N.y * sinFlip + N.z * cosFlip);
    } else {
        flippedN = float3(N.x * cosFlip + N.z * sinFlip, N.y, -N.x * sinFlip + N.z * cosFlip);
    }
    N = normalize(mix(N, flippedN, GM_ANIM_MODE));

    // Back side normal
    if (isBack > 0.5) {
        float3 backN = gm_tileNormal(id + 500.0);
        float backRough = gm_tileRoughness(f, id + 500.0);
        backN = normalize(backN + float3(
            (backRough - 0.5) * 0.15,
            (gm_noise(f * 14.0 + id * 3.7) - 0.5) * 0.15,
            0.0
        ));
        N = backN;
        roughness = backRough;
    }

    // Moving light sources
    float3 light1Pos = float3(
        aspect.x * 0.5 + sin(t * 0.7) * aspect.x * 0.4,
        0.5 + cos(t * 0.53) * 0.4,
        0.8 + sin(t * 0.31) * 0.15
    );
    float3 light2Pos = float3(
        aspect.x * 0.5 + cos(t * 0.43 + 2.0) * aspect.x * 0.35,
        0.5 + sin(t * 0.37 + 1.5) * 0.35,
        0.7 + cos(t * 0.29) * 0.1
    );
    float3 light3Pos = float3(
        aspect.x * 0.5 + sin(t * 0.19 + 4.0) * aspect.x * 0.25,
        0.5 + cos(t * 0.23 + 3.0) * 0.25,
        1.2
    );

    // Per-tile specular
    float3 tileWorldPos = float3(p, 0.0);
    float3 viewDir = normalize(float3(aspect.x * 0.5, 0.5, 1.5) - tileWorldPos);

    float3 L1 = normalize(light1Pos - tileWorldPos);
    float3 H1 = normalize(L1 + viewDir);
    float NdotH1 = max(dot(N, H1), 0.0);
    float spec1 = pow(NdotH1, 80.0 + tileHash * 60.0);
    float diff1 = max(dot(N, L1), 0.0);

    float3 L2 = normalize(light2Pos - tileWorldPos);
    float3 H2 = normalize(L2 + viewDir);
    float NdotH2 = max(dot(N, H2), 0.0);
    float spec2 = pow(NdotH2, 60.0 + tileHash2 * 80.0);
    float diff2 = max(dot(N, L2), 0.0);

    float3 L3 = normalize(light3Pos - tileWorldPos);
    float3 H3 = normalize(L3 + viewDir);
    float NdotH3 = max(dot(N, H3), 0.0);
    float spec3 = pow(NdotH3, 30.0 + tileHash3 * 20.0);
    float diff3 = max(dot(N, L3), 0.0);

    float specTotal = spec1 * 1.2 + spec2 * 0.9 + spec3 * 0.4;
    float diffTotal = diff1 * 0.5 + diff2 * 0.35 + diff3 * 0.25;

    // Breathing
    float breathe = 1.0 + sin(t * 0.6) * 0.08 + sin(t * 0.37 + 1.0) * 0.05;
    specTotal *= breathe;
    diffTotal *= breathe;

    // Wave flip shading
    // Shimmer
    float shimmerPhase = tileHash * GM_TAU + t * (0.8 + tileHash2 * 1.5);
    float shimmer = pow(max(sin(shimmerPhase), 0.0), 16.0);
    float shimmer2Phase = tileHash3 * GM_TAU + t * (0.5 + tileHash * 0.7) + 2.0;
    float shimmer2 = pow(max(sin(shimmer2Phase), 0.0), 24.0);
    float shimmerBlend = 1.0 - GM_ANIM_MODE;
    float shimmerTotal = (shimmer * 0.6 + shimmer2 * 0.4) * shimmerBlend;

    // Gold color palette
    float3 groutColor = float3(0.03, 0.02, 0.01);
    float3 darkGold   = float3(0.12, 0.09, 0.05);
    float3 medGold    = float3(0.45, 0.32, 0.14);
    float3 brightGold = float3(0.78, 0.58, 0.24);
    float3 flashGold  = float3(1.0, 0.85, 0.55);
    float3 hotGold    = float3(1.0, 0.95, 0.80);

    // Per-tile base color
    float baseVar = tileHash;
    float3 tileBase = mix(darkGold, medGold, smoothstep(0.0, 0.5, baseVar));
    tileBase = mix(tileBase, brightGold, smoothstep(0.5, 0.85, baseVar));
    tileBase *= 0.9 + tileHash2 * 0.2;

    // Build tile color
    float3 tileColor = tileBase;
    tileColor += tileBase * diffTotal * 0.6;

    float3 specColor = mix(brightGold, flashGold, smoothstep(0.0, 0.5, specTotal));
    specColor = mix(specColor, hotGold, smoothstep(0.5, 1.0, specTotal));
    tileColor += specColor * specTotal * 1.4;

    float3 shimmerColor = mix(flashGold, hotGold, shimmerTotal);
    tileColor += shimmerColor * shimmerTotal * 0.7;

    // Wave flip 3D depth shading
    float flipShade = mix(1.0, abscos * 0.7 + 0.3, inTransition);
    tileColor *= flipShade;
    tileColor = mix(tileColor, tileColor * float3(1.2, 1.05, 0.85), isBack * 0.6);
    float edgeOnGlow = pow(1.0 - abscos, 4.0) * inTransition;
    tileColor += medGold * edgeOnGlow * 0.25 * GM_ANIM_MODE;

    // Micro-facet sparkle
    float microSpec = pow(roughness, 4.0) * specTotal * 3.0;
    tileColor += flashGold * microSpec * 0.3;

    // Edge highlighting
    float edgeDist = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    float edgeHighlightVal = smoothstep(0.15, 0.05, edgeDist);
    tileColor += brightGold * edgeHighlightVal * (diffTotal + specTotal * 0.5) * 0.15;

    // Composite: tile or grout
    float3 col = mix(groutColor, tileColor, tMask);

    // Grout depth
    float groutDepth = 1.0 - tMask;
    col -= float3(0.01, 0.008, 0.005) * groutDepth * (1.0 - smoothstep(0.0, 0.03, edgeDist));

    // Global warm glow
    float glow1 = smoothstep(0.7, 0.0, length(p - light1Pos.xy));
    float glow2 = smoothstep(0.6, 0.0, length(p - light2Pos.xy));
    col += medGold * glow1 * 0.06;
    col += medGold * glow2 * 0.04;

    // Vignette
    float2 vigUv = uv * 2.0 - 1.0;
    float vig = 1.0 - dot(vigUv, vigUv) * 0.35;
    vig = max(vig, 0.0);
    vig = smoothstep(0.0, 1.0, vig);
    col *= 0.5 + vig * 0.5;

    // Tone mapping (ACES-like)
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

    // Slight warmth push
    col = pow(max(col, float3(0.0)), float3(0.95, 1.0, 1.1));

    col = hue_rotate(col, u.hue_shift);
    return float4(clamp(col, float3(0.0), float3(1.0)), 1.0);
}
