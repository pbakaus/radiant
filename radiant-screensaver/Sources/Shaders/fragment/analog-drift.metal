#include "../Common.metal"

// ─── Analog Drift: Lissajous figures with phosphor persistence ───
// Ported from static/analog-drift.html (Canvas 2D)
// Approach: evaluate Lissajous curves as distance fields per-pixel,
// add oscilloscope grid, CRT bloom, and cyan accent trace.

constant float AD_GRID_SIZE        = 0.4;
constant float AD_GRID_DIVISIONS   = 8.0;
constant float AD_GRID_ALPHA       = 0.04;
constant float AD_CURVE_SCALE      = 0.35;
constant float AD_NUM_POINTS       = 512.0;
constant float AD_BLOOM_WIDTH      = 0.012;
constant float AD_TRACE_WIDTH      = 0.003;
constant float AD_DOT_RADIUS       = 0.006;
constant float AD_DOT_COUNT        = 40.0;
constant float AD_DRIFT_SPEED      = 0.03;
constant float AD_PI               = 3.14159265;

// Lissajous waypoints (a, b, delta)
static float3 ad_waypoint(int idx) {
    // 10 waypoints cycling through interesting Lissajous forms
    switch (idx % 10) {
        case 0: return float3(1.0, 1.0, AD_PI * 0.5);   // circle
        case 1: return float3(1.0, 2.0, 0.0);             // figure-8
        case 2: return float3(2.0, 3.0, AD_PI * 0.25);   // trefoil
        case 3: return float3(3.0, 2.0, AD_PI / 3.0);    // complex
        case 4: return float3(3.0, 4.0, AD_PI / 6.0);    // rose-like
        case 5: return float3(2.0, 5.0, AD_PI * 0.5);    // intricate
        case 6: return float3(1.0, 3.0, AD_PI * 0.2);    // asymmetric
        case 7: return float3(4.0, 3.0, AD_PI / 7.0);    // dense rose
        case 8: return float3(3.0, 5.0, AD_PI / 3.0);    // complex weave
        default: return float3(1.0, 1.0, 0.0);            // diagonal
    }
}

// Smooth cubic ease-in-out
static float ad_ease(float t) {
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5;
}

// Get interpolated waypoint parameters at drift time
static float3 ad_get_params(float driftTime) {
    float cyclePos = fmod(driftTime, 10.0);
    if (cyclePos < 0.0) cyclePos += 10.0;
    int idx = int(floor(cyclePos));
    float frac = ad_ease(cyclePos - floor(cyclePos));
    float3 from = ad_waypoint(idx);
    float3 to = ad_waypoint((idx + 1) % 10);
    return mix(from, to, frac);
}

// Compute minimum distance from a point to the Lissajous curve
static float ad_curve_dist(float2 p, float a, float b, float delta, float scale, int numPts) {
    float coverage = AD_PI * 2.0 * max(ceil(a), ceil(b));
    float stepSize = coverage / float(numPts);
    float minDist = 1e6;
    for (int i = 0; i < numPts; i++) {
        float t = float(i) * stepSize;
        float2 cp = float2(sin(a * t + delta), sin(b * t)) * scale;
        float d = length(p - cp);
        minDist = min(minDist, d);
    }
    return minDist;
}

// Faster approximate curve distance using fewer samples
static float ad_curve_dist_fast(float2 p, float a, float b, float delta, float scale, int numPts) {
    float coverage = AD_PI * 2.0 * max(ceil(a), ceil(b));
    float stepSize = coverage / float(numPts);
    float minDist = 1e6;
    for (int i = 0; i < numPts; i++) {
        float t = float(i) * stepSize;
        float2 cp = float2(sin(a * t + delta), sin(b * t)) * scale;
        float d = length(p - cp);
        minDist = min(minDist, d);
    }
    return minDist;
}

// Oscilloscope grid SDF
static float ad_grid(float2 uv, float size) {
    float result = 0.0;

    // Crosshairs
    float hLine = smoothstep(0.002, 0.0, abs(uv.y));
    float vLine = smoothstep(0.002, 0.0, abs(uv.x));
    float crosshair = max(hLine, vLine);
    result += crosshair * 0.5;

    // Grid divisions
    float gridStep = size * 2.0 / AD_GRID_DIVISIONS;
    float gx = abs(fmod(abs(uv.x) + gridStep * 0.5, gridStep) - gridStep * 0.5);
    float gy = abs(fmod(abs(uv.y) + gridStep * 0.5, gridStep) - gridStep * 0.5);
    float gridLine = smoothstep(0.0015, 0.0, min(gx, gy));
    result += gridLine * 0.25;

    // Outer border
    float2 absUV = abs(uv);
    float borderD = max(absUV.x - size, absUV.y - size);
    float border = smoothstep(0.003, 0.0, abs(borderD));
    result += border * 0.4;

    // Tick marks on axes
    float tickX = smoothstep(0.004, 0.0, abs(uv.y)) * smoothstep(0.0, 0.001, abs(fmod(abs(uv.x) + gridStep * 0.5, gridStep) - gridStep * 0.5) < 0.002 ? 0.0 : 1.0);

    // Only show grid inside the box
    float inside = step(absUV.x, size) * step(absUV.y, size);
    return result * inside;
}

// Phosphor dot brightness
static float ad_dot(float2 p, float a, float b, float delta, float scale, float time) {
    float coverage = AD_PI * 2.0 * max(ceil(a), ceil(b));
    float brightness = 0.0;
    for (int i = 0; i < int(AD_DOT_COUNT); i++) {
        float t = (float(i) / AD_DOT_COUNT) * coverage;
        float2 dp = float2(sin(a * t + delta), sin(b * t)) * scale;
        float d = length(p - dp);
        float pulse = 0.5 + 0.5 * abs(sin(t * 3.0 + time * 2.0));
        float r = AD_DOT_RADIUS * pulse;
        brightness += smoothstep(r, r * 0.3, d) * 0.35;
    }
    return brightness;
}

fragment float4 fs_analog_drift(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float minDim = min(res.x, res.y);
    float2 uv = (in.pos.xy - res * 0.5) / minDim;
    float t = u.time;

    // Get drifting Lissajous parameters
    float driftTime = t * AD_DRIFT_SPEED;
    float3 params = ad_get_params(driftTime);
    float a = params.x;
    float b = params.y;
    float delta = params.z;

    // Background: dark with subtle warmth
    float3 col = float3(0.039, 0.039, 0.039);

    // Oscilloscope grid
    float gridBrightness = ad_grid(uv, AD_GRID_SIZE);
    float gridBreath = AD_GRID_ALPHA + 0.02 * sin(t * 0.3);
    col += float3(0.784, 0.584, 0.424) * gridBrightness * gridBreath;

    // Sub-harmonic (larger, dimmer)
    float dSub = ad_curve_dist_fast(uv, a * 0.5, b * 0.5, delta * 0.7 - t * 0.05, 0.38, 200);
    float subGlow = smoothstep(AD_BLOOM_WIDTH * 1.5, 0.0, dSub) * 0.06;
    col += float3(0.706, 0.510, 0.353) * subGlow;

    // Second harmonic
    float d2nd = ad_curve_dist_fast(uv, a * 2.0, b * 2.0, delta + t * 0.15, 0.32, 256);
    float harmGlow2 = smoothstep(AD_BLOOM_WIDTH, 0.0, d2nd) * 0.12;
    col += float3(0.784, 0.584, 0.424) * harmGlow2;

    // Third harmonic
    float d3rd = ad_curve_dist_fast(uv, a * 3.0, b * 2.0, delta * 1.5 + t * 0.08, 0.28, 256);
    float harmGlow3 = smoothstep(AD_BLOOM_WIDTH, 0.0, d3rd) * 0.08;
    col += float3(0.784, 0.584, 0.424) * harmGlow3;

    // Main Lissajous trace
    float dMain = ad_curve_dist(uv, a, b, delta, AD_CURVE_SCALE, int(AD_NUM_POINTS));

    // CRT bloom (wide glow)
    float bloom = smoothstep(AD_BLOOM_WIDTH, 0.0, dMain) * 0.15;
    col += float3(0.784, 0.584, 0.424) * bloom;

    // Sharp trace line
    float trace = smoothstep(AD_TRACE_WIDTH, AD_TRACE_WIDTH * 0.3, dMain) * 0.7;
    col += float3(0.784, 0.584, 0.424) * trace;

    // Cyan accent trace (slightly offset phase)
    float dCyan = ad_curve_dist(uv, a, b, delta + 0.01, AD_CURVE_SCALE, int(AD_NUM_POINTS));
    float cyanTrace = smoothstep(AD_TRACE_WIDTH * 0.8, AD_TRACE_WIDTH * 0.2, dCyan) * 0.35;
    col += float3(0.0, 0.867, 1.0) * cyanTrace;

    // Phosphor dots along the main curve
    float dots = ad_dot(uv, a, b, delta, AD_CURVE_SCALE, t);
    col += float3(1.0, 0.96, 0.90) * dots * 0.3;
    col += float3(0.784, 0.584, 0.424) * dots * 0.12;

    // Vignette
    float vig = 1.0 - smoothstep(0.3, 0.7, length(uv));
    col *= 0.7 + 0.3 * vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
