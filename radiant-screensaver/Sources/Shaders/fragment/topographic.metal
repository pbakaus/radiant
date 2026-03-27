#include "../Common.metal"

// ─── Topographic: Contour lines on animated noise terrain ───
// Ported from static/topographic.html
// Strategy: Per-pixel FBM noise evaluation, contour extraction via
// fract/smoothstep on the noise value, marching-squares-style isolines
// approximated analytically.

constant float TP_NOISE_SCALE = 0.003;
constant float TP_TIME_SPEED = 0.15;
constant int TP_NUM_CONTOURS = 14;
constant float TP_PI = 3.14159265;

// ── FBM using snoise from Common.metal ──
static float tp_fbm(float2 p, float z) {
    float val = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    float sum = 0.0;
    for (int o = 0; o < 4; o++) {
        // Use snoise(2D) with z encoded as offset
        val += snoise(p * freq + float2(z * 0.7, z * 1.3 + float(o) * 17.0)) * amp;
        sum += amp;
        amp *= 0.5;
        freq *= 2.0;
    }
    return val / sum;
}

// ── Contour line intensity from a scalar field value ──
// Returns glow intensity for contour lines at regular intervals
static float tp_contourLine(float fieldVal, float contourLevel, bool isMajor) {
    float dist = abs(fieldVal - contourLevel);

    // Glow pass: wider, dimmer
    float glowWidth = isMajor ? 0.012 : 0.008;
    float sharpWidth = isMajor ? 0.004 : 0.002;

    float glow = smoothstep(glowWidth, 0.0, dist) * (isMajor ? 0.25 : 0.15);
    float sharp = smoothstep(sharpWidth, 0.0, dist) * (isMajor ? 1.0 : 0.65);

    return glow + sharp;
}

// ── Color interpolation for contour altitude ──
static float3 tp_contourColor(float threshold) {
    // coral -> amber -> gold
    float3 coral = float3(0.878, 0.471, 0.314);
    float3 amber = float3(0.784, 0.584, 0.424);
    float3 gold  = float3(0.831, 0.647, 0.455);

    if (threshold < 0.5) {
        return mix(coral, amber, threshold * 2.0);
    }
    return mix(amber, gold, (threshold - 0.5) * 2.0);
}

fragment float4 fs_topographic(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 pixel = in.pos.xy;
    float t = u.time * TP_TIME_SPEED;

    // Sample the noise field at this pixel
    float2 noiseCoord = pixel * TP_NOISE_SCALE;
    float fieldVal = tp_fbm(noiseCoord, t);

    // Also sample neighbors for gradient (used for label-like shading)
    float eps = TP_NOISE_SCALE * 2.0;
    float fx = tp_fbm(noiseCoord + float2(eps, 0.0), t);
    float fy = tp_fbm(noiseCoord + float2(0.0, eps), t);
    float2 grad = float2(fx - fieldVal, fy - fieldVal) / eps;
    float gradMag = length(grad);

    // Normalize field to approximately 0..1
    // snoise returns roughly -1..1, fbm is similar range
    float normalized = fieldVal * 0.5 + 0.5;

    float3 col = float3(0.039); // dark background

    // Subtle terrain shading based on height
    float terrainShade = normalized * 0.04;
    col += float3(0.784, 0.584, 0.424) * terrainShade;

    // Gradient-based hillshading (light from upper-left)
    float hillshade = dot(normalize(float2(-1.0, -1.0)), grad) * 0.02;
    col += float3(0.9, 0.8, 0.7) * max(hillshade, 0.0);

    // Draw contour lines
    float numContours = float(TP_NUM_CONTOURS);
    for (int c = 0; c < TP_NUM_CONTOURS; c++) {
        float threshold = float(c + 1) / (numContours + 1.0);
        bool isMajor = (c % 5 == 0);

        float3 lineColor = tp_contourColor(threshold);

        // Opacity: stronger in the middle, subtler at extremes
        float distFromCenter = abs(threshold - 0.5) * 2.0;
        float baseAlpha = 0.25 + (1.0 - distFromCenter) * 0.45;

        float intensity = tp_contourLine(normalized, threshold, isMajor);

        // Scale by the gradient magnitude for cleaner lines
        // Where gradient is near zero (flat areas), lines can get thick/messy
        float gradScale = smoothstep(0.0, 0.5, gradMag * 200.0);
        intensity *= mix(0.3, 1.0, gradScale);

        col += lineColor * intensity * baseAlpha;
    }

    // Elevation number labels approximation:
    // Use noise-modulated dots at major contour crossings
    float majorSpacing = 1.0 / (numContours + 1.0) * 5.0;
    float majorFrac = fract(normalized / majorSpacing);
    float nearMajor = smoothstep(0.03, 0.0, abs(majorFrac - 0.5) - 0.47);

    // Small label-like bright spots at sparse intervals
    float2 labelGrid = floor(pixel / 120.0);
    float labelHash = fract(sin(dot(labelGrid, float2(127.1, 311.7))) * 43758.5453);
    if (labelHash < 0.15 && nearMajor > 0.1) {
        float2 labelPos = (labelGrid + 0.5) * 120.0;
        float labelDist = length(pixel - labelPos);
        float labelGlow = smoothstep(8.0, 2.0, labelDist) * 0.3;
        col += float3(0.784, 0.584, 0.424) * labelGlow;
    }

    // Vignette
    float2 uv = pixel / res - 0.5;
    float vig = 1.0 - dot(uv, uv) * 2.0;
    col *= saturate(mix(0.6, 1.0, vig));

    col = hue_rotate(col, u.hue_shift);
    return float4(saturate(col), 1.0);
}
