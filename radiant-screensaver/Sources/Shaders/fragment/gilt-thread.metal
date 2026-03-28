#include "../Common.metal"

// ─── Gilt Thread: Golden Lissajous threads with metallic sheen ───
// Ported from static/gilt-thread.html (Canvas 2D → fragment shader)
// Original draws trail-buffered Lissajous curves with directional metallic
// lighting. This port evaluates the curves analytically per-pixel.

constant float GT_PI = 3.14159265359;
constant float GT_PHI = 1.618033988749895;

// Default parameters
constant int GT_THREAD_COUNT = 5;
constant float GT_DRAW_SPEED = 1.0;
constant int GT_TRAIL_SAMPLES = 200;  // how many trail points to evaluate per thread

// Light direction for metallic sheen (matches original LX, LY)
constant float GT_LX = 0.58;
constant float GT_LY = -0.82;

// ── Smooth noise for sparkle ──
static float gt_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Thread curve: Lissajous with golden-ratio frequency pairs ──
// Returns position in [-0.55, 0.55] normalized space
static float2 gt_threadPos(int threadIdx, float s) {
    // Frequency pairs (matching makeThread from original)
    float fx, fy;
    float phase_x = float(threadIdx) * 0.93 + 0.5;
    float phase_y = float(threadIdx) * 1.17 + 2.3;
    float mod_fx = 0.11 + float(threadIdx) * 0.037;
    float mod_fy = 0.13 + float(threadIdx) * 0.029;
    float ax = 0.52 + float(threadIdx % 3) * 0.06;
    float ay = 0.48 + float((threadIdx + 1) % 3) * 0.06;
    float speed = 0.55 + float(threadIdx) * 0.04;

    // Select frequency pair based on index
    int fi = threadIdx % 8;
    if      (fi == 0) { fx = 3.0;           fy = 2.0 * GT_PHI; }
    else if (fi == 1) { fx = 2.0;           fy = 3.0 * GT_PHI; }
    else if (fi == 2) { fx = 5.0;           fy = 3.0 * GT_PHI; }
    else if (fi == 3) { fx = 3.0 * GT_PHI;  fy = 5.0; }
    else if (fi == 4) { fx = 4.0;           fy = 3.0 * GT_PHI + 1.0; }
    else if (fi == 5) { fx = 2.0 * GT_PHI;  fy = 5.0; }
    else if (fi == 6) { fx = 5.0;           fy = 4.0 * GT_PHI; }
    else              { fx = 3.0;           fy = 5.0 * GT_PHI; }

    float st = s * speed;
    ax *= (1.0 + 0.18 * sin(st * mod_fx));
    ay *= (1.0 + 0.18 * sin(st * mod_fy));

    return float2(
        sin(st * fx + phase_x) * ax,
        sin(st * fy + phase_y) * ay
    );
}

// ── Tangent direction via finite difference ──
static float2 gt_tangent(int threadIdx, float s) {
    float dt = 0.0005;
    float2 a = gt_threadPos(threadIdx, s - dt);
    float2 b = gt_threadPos(threadIdx, s + dt);
    float2 d = b - a;
    float len = length(d);
    return len > 0.0 ? d / len : float2(1.0, 0.0);
}

fragment float4 fs_gilt_thread(VSOut in [[stage_in]],
                               constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float minDim = min(res.x, res.y);
    float scale = minDim * 0.55;

    // Pixel position in normalized space [-0.55, 0.55]
    float2 pixNorm = (in.pos.xy - res * 0.5) / scale;

    float t = u.time * GT_DRAW_SPEED;

    // Per-pixel line width in normalized space
    float pxSize = 1.0 / scale;
    float baseWidth = 2.5 * pxSize;  // ~2.5 px thread width

    float3 col = float3(0.039, 0.039, 0.039);  // #0a0a0a background

    // Accumulate glow and line contributions from all threads
    float3 glowAccum = float3(0.0);
    float3 lineAccum = float3(0.0);
    float sparkleAccum = 0.0;

    for (int thr = 0; thr < GT_THREAD_COUNT; thr++) {
        float threadTime = t + float(thr) * 0.4;
        float threadWidth = baseWidth * (1.0 + float(thr % 3) * 0.27);
        float hueOffset = float(thr) * 0.15;

        // Find closest point on the trail by sampling
        float closestDist = 1e5;
        float closestFrac = 0.0;
        float2 closestTang = float2(1.0, 0.0);

        // Sample trail points: from (threadTime - trailLength) to threadTime
        float trailLength = 10.0;  // time units of trail
        for (int si = 0; si < GT_TRAIL_SAMPLES; si++) {
            float frac = float(si) / float(GT_TRAIL_SAMPLES - 1);
            float sampleT = threadTime - trailLength * (1.0 - frac);
            float2 pos = gt_threadPos(thr, sampleT);
            float dist = length(pixNorm - pos);
            if (dist < closestDist) {
                closestDist = dist;
                closestFrac = frac;
                closestTang = gt_tangent(thr, sampleT);
            }
        }

        // Alpha: quadratic fade from tail (frac=0) to head (frac=1)
        float alpha = closestFrac * closestFrac;
        if (alpha < 0.003) continue;

        // ── Outer glow ──
        float outerGlowWidth = threadWidth * 5.0;
        float outerGlow = exp(-closestDist * closestDist / (outerGlowWidth * outerGlowWidth)) * 0.04 * alpha;
        glowAccum += float3(0.784, 0.584, 0.424) * outerGlow;

        // ── Inner glow ──
        float innerGlowWidth = threadWidth * 2.6;
        float innerGlow = exp(-closestDist * closestDist / (innerGlowWidth * innerGlowWidth)) * 0.08 * alpha;
        glowAccum += float3(0.784, 0.584, 0.424) * innerGlow;

        // ── Metallic body ──
        float dot_val = closestTang.x * GT_LX + closestTang.y * GT_LY;
        float spec = dot_val * dot_val;
        float cross_val = abs(-closestTang.y * GT_LX + closestTang.x * GT_LY);

        float r = clamp((160.0 + spec * 85.0 + cross_val * 20.0 + hueOffset * 8.0) / 255.0, 0.51, 1.0);
        float g = clamp((120.0 + spec * 75.0 + cross_val * 25.0 - hueOffset * 4.0) / 255.0, 0.353, 0.922);
        float b = clamp((40.0 + spec * 70.0 + cross_val * 20.0) / 255.0, 0.098, 0.569);
        float3 metalColor = float3(r, g, b);

        float lineShape = 1.0 - smoothstep(0.0, threadWidth, closestDist);
        float lineAlpha = lineShape * 0.82 * alpha;
        lineAccum += metalColor * lineAlpha;

        // ── Specular highlight ──
        float spec4 = spec * spec;
        if (spec4 > 0.08 && alpha > 0.05) {
            float specWidth = threadWidth * 0.28;
            float specShape = 1.0 - smoothstep(0.0, specWidth, closestDist);
            lineAccum += float3(1.0, 0.941, 0.784) * specShape * spec4 * 0.65 * alpha;
        }

        // ── Tip sparkle (only near head) ──
        if (closestFrac > 0.95) {
            float sparkle = gt_hash(in.pos.xy + float2(float(thr) * 100.0, u.time * 60.0));
            if (sparkle > 0.7) {
                float sparkDist = closestDist / (threadWidth * 3.0);
                sparkleAccum += exp(-sparkDist * sparkDist) * (sparkle - 0.7) * 3.33;
            }
        }
    }

    col += glowAccum;
    col += lineAccum;

    // Sparkle glow
    col += float3(0.863, 0.706, 0.314) * sparkleAccum * 0.25;
    col += float3(1.0, 0.941, 0.784) * sparkleAccum * 0.85;

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
