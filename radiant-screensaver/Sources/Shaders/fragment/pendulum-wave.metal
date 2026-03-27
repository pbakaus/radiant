#include "../Common.metal"

// ─── Pendulum Wave: Physics-based pendulum wave machine ───
// Ported from static/pendulum-wave.html
// Original: N pendulums with increasing frequencies creating mesmerizing
// wave patterns. Each pendulum swings at its own period, and a smooth
// curve connects the bobs. Fragment shader computes bob positions
// analytically and renders strings, bobs with glow, and connecting curve.

constant float PW_NUM_PENDULUMS = 20.0;
constant float PW_CYCLE_DURATION = 60.0;  // seconds for full pattern cycle
constant float PW_BASE_OSCILLATIONS = 30.0;
constant float PW_AMPLITUDE_DEG = 35.0;
constant float PW_AMPLITUDE_RAD = PW_AMPLITUDE_DEG * 3.14159265359 / 180.0;
constant float PW_BOB_GLOW_RADIUS = 0.025;  // normalized glow radius
constant float PW_BOB_CORE_RADIUS = 0.004;  // normalized core radius
constant float PW_STRING_WIDTH = 0.001;
constant float PW_CURVE_WIDTH = 0.002;
constant float PW_CURVE_GLOW_WIDTH = 0.008;
constant float PW_PIVOT_Y = 0.08;            // pivot height (from top, normalized)
constant float PW_MARGIN = 0.1;              // horizontal margin
constant float PW_MAX_DISPLAY_LEN = 0.72;    // longest pendulum length
constant float PW_MIN_DISPLAY_LEN = 0.38;    // shortest pendulum length
constant float PW_GRAVITY = 9.81;
constant int PW_MAX_PENDS = 24;               // loop ceiling

// ── Color gradient: amber to coral ──
constant float3 PW_AMBER = float3(200.0, 149.0, 108.0) / 255.0;
constant float3 PW_GOLD  = float3(212.0, 165.0, 116.0) / 255.0;
constant float3 PW_CORAL = float3(224.0, 120.0, 80.0) / 255.0;

static float3 pw_getColor(float t) {
    if (t < 0.5) {
        return mix(PW_AMBER, PW_GOLD, t * 2.0);
    }
    return mix(PW_GOLD, PW_CORAL, (t - 0.5) * 2.0);
}

// ── Get pendulum bob position ──
static float2 pw_bobPosition(int idx, float t, float2 res) {
    float fi = float(idx);
    float numP = PW_NUM_PENDULUMS;

    // Period for this pendulum
    float oscillations = PW_BASE_OSCILLATIONS + fi;
    float period = PW_CYCLE_DURATION / oscillations;
    float omega = 6.28318530718 / period;

    // Derive physical length from period: T = 2pi*sqrt(L/g)
    float physLength = PW_GRAVITY * (period / 6.28318530718) * (period / 6.28318530718);

    // Map physical lengths to display lengths
    // Longest pendulum (idx=0) has longest period and longest physical length
    float osc0 = PW_BASE_OSCILLATIONS;
    float period0 = PW_CYCLE_DURATION / osc0;
    float maxPhysLen = PW_GRAVITY * (period0 / 6.28318530718) * (period0 / 6.28318530718);

    float oscN = PW_BASE_OSCILLATIONS + numP - 1.0;
    float periodN = PW_CYCLE_DURATION / oscN;
    float minPhysLen = PW_GRAVITY * (periodN / 6.28318530718) * (periodN / 6.28318530718);

    float lenRatio = (physLength - minPhysLen) / max(maxPhysLen - minPhysLen, 0.001);
    float displayLen = PW_MIN_DISPLAY_LEN + (PW_MAX_DISPLAY_LEN - PW_MIN_DISPLAY_LEN) * lenRatio;

    // Current swing angle
    float angle = PW_AMPLITUDE_RAD * cos(omega * t);

    // Pivot X position
    float pivotX = PW_MARGIN + ((1.0 - 2.0 * PW_MARGIN) / (numP - 1.0)) * fi;

    // Bob position
    float bobX = pivotX + sin(angle) * displayLen;
    float bobY = PW_PIVOT_Y + cos(angle) * displayLen;

    return float2(bobX, bobY);
}

// ── Distance from a point to a line segment ──
static float pw_sdSeg(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

fragment float4 fs_pendulum_wave(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float t = u.time;

    // Work in aspect-corrected UV for circular glows
    float aspect = res.x / res.y;
    float2 p = float2(uv.x, uv.y);

    // ── Background ──
    float3 col = float3(10.0 / 255.0);

    // ── Reference lines (very subtle) ──
    for (int i = 0; i < 3; i++) {
        float refLen = PW_MIN_DISPLAY_LEN + (PW_MAX_DISPLAY_LEN - PW_MIN_DISPLAY_LEN) * float(i) * 0.5;
        float refY = PW_PIVOT_Y + refLen;
        float lineDist = abs(uv.y - refY);
        float lineAlpha = smoothstep(0.002, 0.0, lineDist) * 0.04;
        col += PW_AMBER * lineAlpha;
    }

    // ── Pivot bar ──
    float pivotBarDist = abs(uv.y - PW_PIVOT_Y);
    float pivotBarX = step(PW_MARGIN - 0.02, uv.x) * step(uv.x, 1.0 - PW_MARGIN + 0.02);
    float pivotBarAlpha = smoothstep(0.002, 0.0, pivotBarDist) * 0.15 * pivotBarX;
    col += PW_AMBER * pivotBarAlpha;

    // ── Compute all bob positions ──
    // Since we can't use arrays easily, we accumulate rendering per-pendulum
    int numP = int(PW_NUM_PENDULUMS);

    // ── Connecting curve glow ──
    // Sample distances to segments between adjacent bobs
    float curveDist = 1e9;
    float2 prevBob = pw_bobPosition(0, t, res);
    for (int i = 1; i < PW_MAX_PENDS; i++) {
        if (i >= numP) break;
        float2 bob = pw_bobPosition(i, t, res);
        // Aspect-correct distance
        float2 pAdj = float2(p.x * aspect, p.y);
        float2 aAdj = float2(prevBob.x * aspect, prevBob.y);
        float2 bAdj = float2(bob.x * aspect, bob.y);
        float d = pw_sdSeg(pAdj, aAdj, bAdj);
        curveDist = min(curveDist, d);
        prevBob = bob;
    }

    // Glow pass for connecting curve
    float curveGlow = exp(-curveDist * curveDist / (PW_CURVE_GLOW_WIDTH * PW_CURVE_GLOW_WIDTH));
    col += PW_GOLD * curveGlow * 0.08;

    // Crisp pass for connecting curve
    float curveLine = smoothstep(PW_CURVE_WIDTH, 0.0, curveDist);
    col += PW_GOLD * curveLine * 0.15;

    // ── Individual pendulums: strings, pivots, bobs ──
    for (int i = 0; i < PW_MAX_PENDS; i++) {
        if (i >= numP) break;
        float fi = float(i);
        float frac = fi / (PW_NUM_PENDULUMS - 1.0);
        float3 pendColor = pw_getColor(frac);

        float2 bob = pw_bobPosition(i, t, res);
        float pivotX = PW_MARGIN + ((1.0 - 2.0 * PW_MARGIN) / (PW_NUM_PENDULUMS - 1.0)) * fi;
        float2 pivot = float2(pivotX, PW_PIVOT_Y);

        // Aspect-correct distance calculations
        float2 pAdj = float2(p.x * aspect, p.y);
        float2 pivotAdj = float2(pivot.x * aspect, pivot.y);
        float2 bobAdj = float2(bob.x * aspect, bob.y);

        // String (line from pivot to bob)
        float stringDist = pw_sdSeg(pAdj, pivotAdj, bobAdj);
        float stringAlpha = smoothstep(PW_STRING_WIDTH, 0.0, stringDist) * 0.2;
        col += pendColor * stringAlpha;

        // Pivot point (small dot)
        float pivotDist = length(pAdj - pivotAdj);
        float pivotAlpha = smoothstep(0.003, 0.001, pivotDist) * 0.3;
        col += pendColor * pivotAlpha;

        // Bob distance
        float bobDist = length(pAdj - bobAdj);

        // Bob outer glow
        float outerGlow = exp(-bobDist * bobDist / (PW_BOB_GLOW_RADIUS * PW_BOB_GLOW_RADIUS));
        col += pendColor * outerGlow * 0.25;

        // Bob mid glow
        float midR = PW_BOB_GLOW_RADIUS * 0.45;
        float midGlow = exp(-bobDist * bobDist / (midR * midR));
        float3 brightCol = min(pendColor + float3(0.16), float3(1.0));
        col += brightCol * midGlow * 0.5;

        // Bob core
        float coreAlpha = smoothstep(PW_BOB_CORE_RADIUS, PW_BOB_CORE_RADIUS * 0.3, bobDist);
        float3 coreCol = min(pendColor + float3(0.24), float3(1.0));
        col += coreCol * coreAlpha * 0.9;
    }

    // ── Trail effect: ghostly after-images ──
    // Show faded bob positions from recent past
    for (int trail = 1; trail <= 4; trail++) {
        float trailT = t - float(trail) * 0.03;
        float trailAlpha = 0.06 / float(trail);
        for (int i = 0; i < PW_MAX_PENDS; i++) {
            if (i >= numP) break;
            float fi = float(i);
            float frac = fi / (PW_NUM_PENDULUMS - 1.0);
            float3 pendColor = pw_getColor(frac);

            float2 trailBob = pw_bobPosition(i, trailT, res);
            float2 trailBobAdj = float2(trailBob.x * aspect, trailBob.y);
            float2 pAdj = float2(p.x * aspect, p.y);
            float trailDist = length(pAdj - trailBobAdj);
            float trailGlow = exp(-trailDist * trailDist / (PW_BOB_GLOW_RADIUS * PW_BOB_GLOW_RADIUS * 0.5));
            col += pendColor * trailGlow * trailAlpha;
        }
    }

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
