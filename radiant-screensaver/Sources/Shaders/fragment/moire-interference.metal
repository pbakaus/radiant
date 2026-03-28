#include "../Common.metal"

// ─── Moiré Interference: Overlapping concentric ring interference patterns ───
// Ported from static/moire-interference.html

// Default parameter values (screensaver — no mouse)
constant float MI_RING_DENSITY = 1.0;
constant float MI_DRIFT_SPEED = 0.5;

constant float MI_PI = 3.14159265359;
constant float MI_TAU = 6.28318530718;

static float mi_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Concentric ring pattern from a center point
// Returns a value in [-1, 1] based on sine of distance
static float mi_rings(float2 uv, float2 center, float freq) {
    float d = length(uv - center);
    return sin(d * freq);
}

fragment float4 fs_moire_interference(VSOut in [[stage_in]],
                                       constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float drift = MI_DRIFT_SPEED;
    float density = MI_RING_DENSITY;

    // Ring frequency — controls how tight the concentric circles are
    float baseFreq = 60.0 * density;

    // Subtle breathing — ring spacing pulses slowly
    float breathe = 1.0 + 0.04 * sin(t * 0.3) + 0.02 * sin(t * 0.17 + 1.0);
    float freq = baseFreq * breathe;

    // Center points — 4 sources orbiting at different speeds and radii
    float d = drift;

    float2 c0 = float2(
        0.22 * cos(t * d * 0.31 + 0.0),
        0.18 * sin(t * d * 0.43 + 0.0)
    );

    float2 c1 = float2(
        0.25 * cos(t * d * 0.23 + 2.1),
        0.20 * sin(t * d * 0.37 + 1.4)
    );

    float2 c2 = float2(
        0.19 * sin(t * d * 0.41 + 4.2),
        0.24 * cos(t * d * 0.29 + 3.1)
    );

    float2 c3 = float2(
        0.21 * cos(t * d * 0.19 + 5.7),
        0.17 * sin(t * d * 0.47 + 0.8)
    );

    // No mouse interaction for screensaver

    // Each center generates rings at a slightly different frequency
    // The frequency differences are what create the moiré beats
    float f0 = freq;
    float f1 = freq * 1.07;
    float f2 = freq * 0.93;
    float f3 = freq * 1.13;

    // Compute ring patterns
    float r0 = mi_rings(uv, c0, f0);
    float r1 = mi_rings(uv, c1, f1);
    float r2 = mi_rings(uv, c2, f2);
    float r3 = mi_rings(uv, c3, f3);

    // Combine ring patterns through multiplication
    float moire = r0 * r1 * r2 * r3;

    // Also compute additive blend for a secondary interference layer
    float additive = (r0 + r1 + r2 + r3) * 0.25;

    // Blend multiplicative and additive for richer pattern
    float pattern = moire * 0.7 + additive * 0.3;

    // Normalize pattern to [0, 1] range
    float intensity = pattern * 0.5 + 0.5;
    intensity = clamp(intensity, 0.0, 1.0);

    // Color mapping
    float3 darkColor = float3(0.05, 0.035, 0.025);
    float3 midColor = float3(0.35, 0.22, 0.12);
    float3 brightColor = float3(0.65, 0.42, 0.22);
    float3 peakColor = float3(0.9, 0.78, 0.55);

    // Three-stop gradient through the palette
    float3 col;
    if (intensity < 0.35) {
        col = mix(darkColor, midColor, intensity / 0.35);
    } else if (intensity < 0.65) {
        col = mix(midColor, brightColor, (intensity - 0.35) / 0.3);
    } else {
        col = mix(brightColor, peakColor, (intensity - 0.65) / 0.35);
    }

    // Add subtle luminance boost at interference peaks
    float peakMask = smoothstep(0.7, 1.0, intensity);
    col += peakColor * peakMask * 0.15;

    // Secondary interference shimmer
    float shimmer = r0 * r2 * 0.5 + 0.5;
    shimmer = smoothstep(0.4, 0.8, shimmer);
    col += float3(0.12, 0.08, 0.04) * shimmer * 0.2;

    // Vignette — darken edges to focus attention on center
    float vig = 1.0 - dot(uv * 0.9, uv * 0.9);
    vig = clamp(vig, 0.0, 1.0);
    vig = pow(vig, 0.5);
    col *= vig;

    // Fine grain — subtle noise overlay for tactile quality
    float grain = (mi_hash(in.pos.xy + fract(t * 37.0) * 1000.0) - 0.5) * 0.03;
    col += grain;

    // Tone mapping — keep blacks deep
    col = max(col, float3(0.0));
    col = col / (1.0 + col * 0.2);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
