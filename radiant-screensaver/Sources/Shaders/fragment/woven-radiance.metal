#include "../Common.metal"

// ─── Woven Radiance: African textile-inspired geometric weave ───
// Ported from static/woven-radiance.html
// Strategy: Per-pixel weave pattern evaluation using grid-based thread
// indices, continuous over/under blending via sin-based pattern functions,
// thread coloring from a warm palette, 3D-ish shading.

constant float WR_PI = 3.14159265;
constant float WR_THREAD_W = 18.0;
constant float WR_GAP = 1.5;
constant int WR_BLOCK_THREADS = 8;
constant float WR_WEAVE_SPEED = 0.5;
constant float WR_COLOR_RICHNESS = 0.8;

// ── Seeded pseudo-random ──
static float wr_rand(float seed) {
    float x = sin(seed * 127.1 + 311.7) * 43758.5453;
    return x - floor(x);
}

// ── Smootherstep for extra-smooth transitions ──
static float wr_smootherstep(float edge0, float edge1, float x) {
    float t = saturate((x - edge0) / (edge1 - edge0));
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// ── Base palette: vibrant African textile colors ──
static float3 wr_palette(int idx) {
    const float3 colors[12] = {
        float3(0.855, 0.647, 0.125),  // deep gold
        float3(0.804, 0.522, 0.247),  // amber/peru
        float3(0.722, 0.451, 0.200),  // copper
        float3(0.698, 0.133, 0.133),  // crimson
        float3(0.396, 0.263, 0.129),  // chocolate
        float3(0.941, 0.863, 0.667),  // warm ivory
        float3(0.545, 0.271, 0.075),  // saddle brown
        float3(0.863, 0.353, 0.157),  // burnt orange
        float3(0.627, 0.157, 0.157),  // dark crimson
        float3(1.000, 0.765, 0.235),  // bright gold
        float3(0.314, 0.176, 0.086),  // espresso
        float3(0.902, 0.588, 0.196)   // marigold
    };
    return colors[idx % 12];
}

// ── Thread color with smooth interpolation ──
static float3 wr_threadColor(int threadIndex, bool isVertical, float t) {
    float seed = isVertical ? float(threadIndex) * 7.3 + 13.7 :
                              float(threadIndex) * 11.1 + 29.3;
    int baseIdx = int(wr_rand(seed) * 12.0) % 12;
    int nextIdx = (baseIdx + 1 + int(wr_rand(seed + 100.0) * 3.0)) % 12;

    float phase = t * 0.06 * WR_WEAVE_SPEED + float(threadIndex) * 0.3 +
                  (isVertical ? 5.0 : 0.0);
    float blend = 0.5 + 0.5 * sin(phase);

    float3 c1 = wr_palette(baseIdx);
    float3 c2 = wr_palette(nextIdx);
    return mix(c1, c2, blend * WR_COLOR_RICHNESS);
}

// ── Weave pattern functions (continuous) ──
static float wr_patternPlain(float h, float v) {
    return sin((h + v) * WR_PI);
}

static float wr_patternTwill(float h, float v) {
    return sin((h + v) * WR_PI * 0.5);
}

static float wr_patternSatin(float h, float v) {
    return sin((h * 2.0 + v) * WR_PI * 0.5);
}

static float wr_patternBasket(float h, float v) {
    return sin(floor(h / 2.0) * WR_PI + floor(v / 2.0) * WR_PI);
}

static float wr_patternHerringbone(float h, float v) {
    float diag = sin((h + v) * WR_PI * 0.5);
    float flip = sin(h * WR_PI * 0.25);
    return diag * (flip > 0.0 ? 1.0 : -1.0);
}

// ── Evaluate pattern at given thread indices ──
static float wr_evalPattern(int patIdx, float h, float v) {
    if (patIdx == 0) return wr_patternPlain(h, v);
    if (patIdx == 1) return wr_patternTwill(h, v);
    if (patIdx == 2) return wr_patternSatin(h, v);
    if (patIdx == 3) return wr_patternBasket(h, v);
    return wr_patternHerringbone(h, v);
}

// ── Get vertical-on-top amount (continuous 0..1) ──
static float wr_vertOnTop(int hIdx, int vIdx, float t) {
    int blockH = hIdx / WR_BLOCK_THREADS;
    int blockV = vIdx / WR_BLOCK_THREADS;
    float localH = float(hIdx % WR_BLOCK_THREADS);
    float localV = float(vIdx % WR_BLOCK_THREADS);

    float patternSeed = float(blockH) * 37.0 + float(blockV) * 71.0;
    int basePattern = int(wr_rand(patternSeed) * 5.0) % 5;
    int nextPattern = (basePattern + 1) % 5;

    float evolvePhase = t * 0.025 * WR_WEAVE_SPEED + float(blockH) * 2.3 + float(blockV) * 3.7;
    float rawBlend = 0.5 + 0.5 * sin(evolvePhase);
    float blendFactor = wr_smootherstep(0.0, 1.0, rawBlend);

    float val1 = wr_evalPattern(basePattern, localH, localV);
    float val2 = wr_evalPattern(nextPattern, localH, localV);
    float blended = mix(val1, val2, blendFactor);

    return smoothstep(-0.3, 0.3, blended);
}

fragment float4 fs_woven_radiance(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 pixel = in.pos.xy;
    float t = u.time;

    float cellSize = WR_THREAD_W + WR_GAP;

    // Slow pan
    float panX = sin(t * 0.02 * WR_WEAVE_SPEED) * cellSize * 0.5;
    float panY = cos(t * 0.015 * WR_WEAVE_SPEED) * cellSize * 0.3;

    float2 panned = pixel - float2(panX, panY);

    // Thread indices
    int col_idx = int(floor(panned.x / cellSize));
    int row_idx = int(floor(panned.y / cellSize));

    // Position within cell
    float2 cellPos = fract(panned / cellSize) * cellSize;

    // Determine if pixel is on a thread or in a gap
    bool onHThread = cellPos.y < WR_THREAD_W;
    bool onVThread = cellPos.x < WR_THREAD_W;

    float vertOnTop = wr_vertOnTop(row_idx, col_idx, t);

    float3 col = float3(0.039); // gap/background

    if (onHThread && onVThread) {
        // Crossing point: draw both threads with over/under blending
        float3 hColor = wr_threadColor(row_idx, false, t);
        float3 vColor = wr_threadColor(col_idx, true, t);

        // Apply brightness based on over/under
        float hLight = mix(0.75, 1.12, 1.0 - vertOnTop);
        float vLight = mix(0.75, 1.12, vertOnTop);

        float3 hFinal = hColor * WR_COLOR_RICHNESS + float3(0.549, 0.471, 0.392) * (1.0 - WR_COLOR_RICHNESS);
        float3 vFinal = vColor * WR_COLOR_RICHNESS + float3(0.549, 0.471, 0.392) * (1.0 - WR_COLOR_RICHNESS);

        hFinal *= hLight;
        vFinal *= vLight;

        // Blend: top thread dominates
        col = mix(hFinal, vFinal, vertOnTop);

        // Thread texture: subtle grain lines
        float grainH = smoothstep(0.02, 0.0, abs(fract(cellPos.y / (WR_THREAD_W / 4.0)) - 0.5) - 0.45);
        float grainV = smoothstep(0.02, 0.0, abs(fract(cellPos.x / (WR_THREAD_W / 4.0)) - 0.5) - 0.45);
        float grain = mix(grainH, grainV, vertOnTop);
        col += float3(1.0, 0.96, 0.94) * grain * 0.06 * WR_COLOR_RICHNESS;

        // Highlight on leading edge of top thread
        float hlIntensity = 0.0;
        if (vertOnTop > 0.5) {
            // Vertical thread on top: highlight on left edge
            hlIntensity = smoothstep(WR_THREAD_W * 0.3, 0.0, cellPos.x) * vertOnTop;
        } else {
            // Horizontal thread on top: highlight on top edge
            hlIntensity = smoothstep(WR_THREAD_W * 0.3, 0.0, cellPos.y) * (1.0 - vertOnTop);
        }
        col += float3(1.0, 0.96, 0.863) * hlIntensity * 0.12 * WR_COLOR_RICHNESS;

        // Shadow from top thread onto bottom
        float shadowIntensity = 0.0;
        if (vertOnTop > 0.5) {
            shadowIntensity = smoothstep(0.0, 4.0, cellPos.x - WR_THREAD_W) * vertOnTop;
        } else {
            shadowIntensity = smoothstep(0.0, 4.0, cellPos.y - WR_THREAD_W) * (1.0 - vertOnTop);
        }
        // This shadow is subtle since we're at the crossing
        col *= (1.0 - shadowIntensity * 0.15);

    } else if (onHThread) {
        // Only horizontal thread visible
        float3 hColor = wr_threadColor(row_idx, false, t);
        float3 hFinal = hColor * WR_COLOR_RICHNESS + float3(0.549, 0.471, 0.392) * (1.0 - WR_COLOR_RICHNESS);
        col = hFinal * 0.95;

        // Grain
        float grainH = smoothstep(0.02, 0.0, abs(fract(cellPos.y / (WR_THREAD_W / 4.0)) - 0.5) - 0.45);
        col += float3(1.0, 0.96, 0.94) * grainH * 0.05;

    } else if (onVThread) {
        // Only vertical thread visible
        float3 vColor = wr_threadColor(col_idx, true, t);
        float3 vFinal = vColor * WR_COLOR_RICHNESS + float3(0.549, 0.471, 0.392) * (1.0 - WR_COLOR_RICHNESS);
        col = vFinal * 0.95;

        // Grain
        float grainV = smoothstep(0.02, 0.0, abs(fract(cellPos.x / (WR_THREAD_W / 4.0)) - 0.5) - 0.45);
        col += float3(1.0, 0.96, 0.94) * grainV * 0.05;
    }

    // ── Warm glow overlay ──
    float2 glowCenter = res * 0.5 + float2(sin(t * 0.08 * WR_WEAVE_SPEED) * res.x * 0.08,
                                             cos(t * 0.06 * WR_WEAVE_SPEED) * res.y * 0.06);
    float glowDist = length(pixel - glowCenter) / max(res.x, res.y);
    float pulse = 0.035 + sin(t * 0.15 * WR_WEAVE_SPEED) * 0.012;
    float glowFalloff = smoothstep(0.6, 0.0, glowDist);
    col += float3(1.0, 0.784, 0.392) * glowFalloff * pulse;

    // ── Vignette ──
    float2 uv = pixel / res - 0.5;
    float vig = 1.0 - dot(uv, uv) * 2.5;
    col *= saturate(mix(0.65, 1.0, vig));

    col = hue_rotate(col, u.hue_shift);
    return float4(saturate(col), 1.0);
}
