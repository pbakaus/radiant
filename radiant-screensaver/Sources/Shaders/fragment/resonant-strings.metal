#include "../Common.metal"

// ─── Resonant Strings: Vibrating string harmonics ───
// Ported from static/resonant-strings.html

constant float RS_NUM_STRINGS = 7.0;
constant float RS_HARMONIC_COUNT = 5.0;
constant float RS_VIBRATION_SPEED = 1.0;
constant float RS_PI = 3.14159265;
constant float RS_MARGIN_FRAC = 0.08;
constant float RS_STRING_LEFT = 0.12;
constant float RS_STRING_SPAN = 0.76;

// ── Warm color palette per string ──
static float3 rs_stringColor(int idx) {
    float3 colors[7] = {
        float3(0.784, 0.584, 0.424),  // amber
        float3(0.831, 0.647, 0.455),  // gold
        float3(0.878, 0.706, 0.549),  // light gold
        float3(0.745, 0.549, 0.392),  // warm brown
        float3(0.902, 0.745, 0.588),  // pale gold
        float3(0.824, 0.627, 0.471),  // mid amber
        float3(0.706, 0.549, 0.431)   // copper
    };
    return colors[idx % 7];
}

// ── Harmonic envelope: modes fade in and out ──
static float rs_harmonicAmp(int mode, float t) {
    float period = 8.0 + float(mode) * 2.5;
    float phase = float(mode) * 1.3;
    float env = sin(t * 0.15 / period + phase) * 0.5 + 0.5;
    env = pow(env, 1.5);
    float baseAmp = 1.0 / (1.0 + float(mode) * 0.4);
    return baseAmp * env;
}

// ── String displacement at normalized y position ──
static float rs_stringDisp(int stringIdx, float yNorm, float t) {
    float baseFreq = 0.8 + float(stringIdx) * 0.15;
    float phaseOff = float(stringIdx) * 0.7;
    float disp = 0.0;
    for (int n = 1; n <= int(RS_HARMONIC_COUNT); n++) {
        float amp = rs_harmonicAmp(n, t) * (12.0 + 5.0 * sin(float(stringIdx) * 0.5));
        float omega = baseFreq * float(n) * 2.0 * RS_VIBRATION_SPEED;
        disp += amp * sin(float(n) * RS_PI * yNorm) * cos(omega * t + phaseOff * float(n));
    }
    return disp;
}

// ── String X position in normalized coords ──
static float rs_stringX(int idx) {
    return RS_STRING_LEFT + float(idx) * RS_STRING_SPAN / (RS_NUM_STRINGS - 1.0);
}

fragment float4 fs_resonant_strings(VSOut in [[stage_in]],
                                     constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float t = u.time;

    float3 col = float3(0.039, 0.031, 0.024); // dark warm bg

    float margin = RS_MARGIN_FRAC;
    float stringLen = 1.0 - margin * 2.0;

    // Pixel position in screen space
    float px = uv.x;
    float py = uv.y;

    // Compute yNorm (position along string)
    float yNorm = clamp((py - margin) / stringLen, 0.0, 1.0);

    // Displacement scale: pixels to UV fraction
    float dispScale = 1.0 / res.x;

    // For each string, compute distance from pixel to the displaced string curve
    for (int si = 0; si < int(RS_NUM_STRINGS); si++) {
        float sx = rs_stringX(si);
        float3 sCol = rs_stringColor(si);
        float thickness = 1.8 - float(si) * 0.12;

        // String displacement at this y-position (in pixels, convert to UV)
        float disp = rs_stringDisp(si, yNorm, t) * dispScale;
        float stringPosX = sx + disp;

        // Distance from pixel to string in x (aspect-corrected)
        float dx = abs(px - stringPosX) * res.x;

        // Only render within the string region (margin to 1-margin in y)
        float yInRange = smoothstep(margin - 0.01, margin + 0.01, py) *
                         smoothstep(1.0 - margin + 0.01, 1.0 - margin - 0.01, py);

        // Glow layers (outer, medium, core)
        float outerGlow = exp(-dx * dx / 32.0) * 0.08 * yInRange;
        float medGlow = exp(-dx * dx / 6.0) * 0.2 * yInRange;
        float coreGlow = exp(-dx * dx / (thickness * thickness * 0.3)) * 0.7 * yInRange;

        col += sCol * outerGlow;
        col += sCol * medGlow;
        col += (sCol + float3(0.16)) * coreGlow;

        // Antinode highlights: bright spots where displacement is large
        float absDx = abs(disp * res.x);
        if (absDx > 6.0) {
            float brightness = min(1.0, (absDx - 6.0) / 15.0);
            float highlightGlow = exp(-dx * dx / ((2.0 + brightness * 4.0) * (2.0 + brightness * 4.0) * 0.5));
            col += (sCol + float3(0.24)) * highlightGlow * brightness * 0.4 * yInRange;
        }

        // Bridge and nut markers (endpoints)
        float2 topEnd = float2(sx, margin);
        float2 botEnd = float2(sx, 1.0 - margin);
        float topDist = length(float2((px - topEnd.x) * res.x / res.y, py - topEnd.y) * res.y);
        float botDist = length(float2((px - botEnd.x) * res.x / res.y, py - botEnd.y) * res.y);
        float markerGlow = exp(-topDist * topDist / 8.0) + exp(-botDist * botDist / 8.0);
        col += float3(0.784, 0.584, 0.424) * markerGlow * 0.4;
    }

    // Resonance connections between strings at harmonic nodes
    for (int n = 1; n <= int(RS_HARMONIC_COUNT); n++) {
        float amp = rs_harmonicAmp(n, t);
        if (amp < 0.1) continue;
        for (int k = 1; k < n; k++) {
            float nodeY = margin + (float(k) / float(n)) * stringLen;
            float yDist = abs(py - nodeY) * res.y;
            float nodeLineGlow = exp(-yDist * yDist / 1.0) * amp * 0.04;

            // Only between string span
            float xInSpan = smoothstep(RS_STRING_LEFT - 0.02, RS_STRING_LEFT + 0.02, px) *
                            smoothstep(RS_STRING_LEFT + RS_STRING_SPAN + 0.02,
                                       RS_STRING_LEFT + RS_STRING_SPAN - 0.02, px);
            col += float3(0.784, 0.584, 0.424) * nodeLineGlow * xInSpan;
        }
    }

    // Rosin dust particles approximated via noise sparkle
    float sparkle = snoise(float2(px * 80.0 + t * 2.0, py * 80.0 - t * 1.5));
    sparkle = smoothstep(0.85, 1.0, sparkle);
    // Only near strings where displacement is high
    float nearString = 0.0;
    for (int si = 0; si < int(RS_NUM_STRINGS); si++) {
        float sx = rs_stringX(si);
        float disp = rs_stringDisp(si, yNorm, t) * dispScale;
        float dx = abs(px - (sx + disp)) * res.x;
        nearString = max(nearString, exp(-dx * dx / 50.0) * min(1.0, abs(disp * res.x) / 10.0));
    }
    col += float3(0.863, 0.706, 0.549) * sparkle * nearString * 0.3;

    // Vignette
    float2 vc = (uv - 0.5) * 2.0;
    float vig = 1.0 - smoothstep(0.5, 1.5, length(vc));
    col *= 0.5 + 0.5 * vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
