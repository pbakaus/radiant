#include "../Common.metal"

// ─── Vintage Static: Retro TV color bars melting into warm interference ───
// Ported from static/vintage-static.html
// Strategy: Per-pixel color bar generation, noise-driven melt displacement,
// scan lines, static noise, CRT vignette, phosphor dots.

constant float VT_PI = 3.14159265;
constant int VT_NUM_BARS = 8;
constant float VT_MELT_CYCLE = 8.0;
constant float VT_MELT_SPEED = 0.5;
constant float VT_GLITCH_INTENSITY = 0.5;

// ── Deterministic hash ──
static float vt_hash(float x) {
    float s = sin(x * 127.1 + 311.7) * 43758.5453;
    return s - floor(s);
}

static float vt_smoothNoise(float x) {
    float ix = floor(x);
    float fx = x - ix;
    fx = fx * fx * (3.0 - 2.0 * fx);
    return vt_hash(ix) * (1.0 - fx) + vt_hash(ix + 1.0) * fx;
}

static float vt_hash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

fragment float4 fs_vintage_static(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 pixel = in.pos.xy;
    float t = u.time;

    // ── Color bar palette (warm-tinted) ──
    const float3 barColors[8] = {
        float3(0.941, 0.922, 0.863),  // warm white
        float3(0.824, 0.667, 0.235),  // gold
        float3(0.235, 0.725, 0.627),  // warm teal
        float3(0.314, 0.647, 0.235),  // warm green
        float3(0.725, 0.235, 0.549),  // warm magenta
        float3(0.784, 0.235, 0.216),  // warm red
        float3(0.176, 0.235, 0.667),  // warm blue
        float3(0.784, 0.584, 0.424)   // amber accent
    };

    // ── Melt cycle ──
    float cycleT = fract(t * VT_MELT_SPEED * 0.15);
    float meltProgress = min(cycleT * VT_MELT_SPEED * 2.0, 1.0);

    // Reform phase
    float reformT = 0.0;
    if (cycleT > 0.85) {
        reformT = (cycleT - 0.85) / 0.15;
        reformT = reformT * reformT * (3.0 - 2.0 * reformT);
        meltProgress = meltProgress * (1.0 - reformT);
    }

    // ── Determine which bar this pixel belongs to and compute melt ──
    float barWidth = res.x / float(VT_NUM_BARS);
    int barIdx = int(floor(pixel.x / barWidth));
    barIdx = clamp(barIdx, 0, VT_NUM_BARS - 1);

    // Per-bar melt offset
    float barMeltOffset = vt_smoothNoise(float(barIdx) * 3.7 + t * 0.3) * 0.3;
    float barMelt = saturate(meltProgress + barMeltOffset - 0.15);

    // Per-slice drip: subdivide each bar into narrow vertical slices
    float sliceWidth = 3.0;
    float sliceIdx = floor(pixel.x / sliceWidth);
    float sliceSeed = float(barIdx) * 100.0 + sliceIdx;

    float dripAmount = barMelt * res.y *
        (0.3 + vt_smoothNoise(sliceSeed * 1.7 + t * VT_MELT_SPEED * 0.5) * 0.7);
    float dripStretch = 1.0 + barMelt *
        (0.5 + vt_smoothNoise(sliceSeed * 2.3) * 1.5);

    // Map pixel.y back to source position accounting for drip
    float sourceY = (pixel.y - dripAmount) / dripStretch;

    // Base bar color with heat shift
    float3 barCol = barColors[barIdx];
    float heatShift = barMelt * 0.3;
    barCol.r = min(1.0, barCol.r + heatShift * 0.118);
    barCol.g = max(0.0, barCol.g - heatShift * 0.078);
    barCol.b = max(0.0, barCol.b - heatShift * 0.059);

    // Only show bar if in range
    float3 col = float3(0.039);
    if (sourceY >= 0.0 && sourceY < res.y) {
        float alpha = 1.0 - barMelt * 0.3;
        col = mix(col, barCol, alpha);
    }

    // Drip tip blob at bottom of each slice
    if (barMelt > 0.1) {
        float tipY = dripAmount + res.y * dripStretch;
        float tipSize = barMelt * 8.0 *
            (0.5 + vt_smoothNoise(sliceSeed * 3.1 + t) * 0.5);
        float tipDist = abs(pixel.y - tipY) / max(tipSize, 0.01);
        float tipBlob = smoothstep(1.0, 0.0, tipDist) * (0.7 - barMelt * 0.3);
        col = mix(col, barCol, tipBlob);
    }

    // ── Scan lines ──
    float scanLine = step(0.5, fract(pixel.y / 3.0)) * 0.08;
    col *= (1.0 - scanLine);

    // Rolling bright scan band
    float rollY = fract(t * 0.15) * res.y * 1.4 - res.y * 0.2;
    float rollDist = abs(pixel.y - rollY) / 40.0;
    float rollGlow = exp(-rollDist * rollDist) * 0.07;
    col += float3(0.784, 0.706, 0.588) * rollGlow;

    // Second dimmer rolling line
    float roll2Y = fract(t * 0.105 + 0.43) * res.y * 1.4 - res.y * 0.2;
    float roll2Dist = abs(pixel.y - roll2Y) / 15.0;
    float roll2Glow = exp(-roll2Dist * roll2Dist) * 0.03;
    col += float3(0.706, 0.627, 0.510) * roll2Glow;

    // ── VHS tracking glitch: horizontal displacement bands ──
    float glitchSeed = floor(t * 30.0) * 7919.0;
    for (int g = 0; g < 3; g++) {
        float gHash = vt_hash(glitchSeed + float(g) * 137.0);
        if (gHash > VT_GLITCH_INTENSITY * 0.15) continue;

        float gy = vt_hash(glitchSeed + float(g) * 237.0) * res.y;
        float gh = 2.0 + vt_hash(glitchSeed + float(g) * 337.0) * 15.0 * VT_GLITCH_INTENSITY;

        if (pixel.y > gy && pixel.y < gy + gh) {
            // Chromatic split effect
            float shift = (vt_hash(glitchSeed + float(g) * 437.0) - 0.5) * 20.0 * VT_GLITCH_INTENSITY;
            col.r += 0.08 * VT_GLITCH_INTENSITY * sign(shift);
            col.b -= 0.06 * VT_GLITCH_INTENSITY * sign(shift);
        }
    }

    // ── Static / snow overlay ──
    float staticSeed = floor(t * 60.0) * 9973.0;
    float staticNoise = vt_hash2(pixel + float2(staticSeed, staticSeed * 0.7));
    float staticBrightness = staticNoise * VT_GLITCH_INTENSITY * 0.15;
    col += float3(staticBrightness,
                   staticBrightness * 0.85,
                   staticBrightness * 0.7);

    // ── Chromatic aberration burst ──
    float aberSeed = floor(t * 2.0) * 4973.0;
    float aberTrigger = vt_hash(aberSeed);
    if (aberTrigger < VT_GLITCH_INTENSITY * 0.06) {
        float aberPhase = fract(t * 2.0);
        float aberIntensity = sin(aberPhase * VT_PI) * VT_GLITCH_INTENSITY;
        col.r += aberIntensity * 0.03;
        col.b += aberIntensity * 0.02;
    }

    // ── Phosphor dot pattern ──
    int phosphorCol = int(pixel.x) % 9;
    float3 phosphorTint = float3(0.0);
    if (phosphorCol < 3) phosphorTint = float3(1.0, 0.314, 0.235);
    else if (phosphorCol < 6) phosphorTint = float3(0.314, 1.0, 0.314);
    else phosphorTint = float3(0.235, 0.314, 1.0);
    col += phosphorTint * 0.015;

    // ── CRT vignette ──
    float2 uv = pixel / res - 0.5;
    float crtDist = dot(uv, uv);
    float vignette = smoothstep(0.6, 0.15, crtDist);
    col *= mix(0.2, 1.0, vignette);

    // Edge darkening
    float edgeX = smoothstep(0.0, 0.03, pixel.x / res.x) *
                  smoothstep(0.0, 0.03, 1.0 - pixel.x / res.x);
    float edgeY = smoothstep(0.0, 0.04, pixel.y / res.y) *
                  smoothstep(0.0, 0.04, 1.0 - pixel.y / res.y);
    col *= edgeX * edgeY;

    // Warm phosphor glow
    col += float3(0.784, 0.627, 0.392) * 0.02;

    col = hue_rotate(col, u.hue_shift);
    return float4(saturate(col), 1.0);
}
