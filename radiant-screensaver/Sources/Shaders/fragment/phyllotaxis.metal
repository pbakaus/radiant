#include "../Common.metal"

// ─── Phyllotaxis Spiral: Fibonacci golden-angle spiral pattern ───
// Ported from static/phyllotaxis.html

constant float PH_GOLDEN_ANGLE = 2.39996323; // 137.508 degrees in radians
constant float PH_MAX_POINTS = 1200.0;
constant float PH_SPREAD = 0.0065;
// ── Color palette (warm amber/coral) ──
static float3 ph_getColor(float index) {
    float3 amber = float3(0.784, 0.584, 0.424);
    float3 gold  = float3(0.831, 0.647, 0.455);
    float3 coral = float3(0.878, 0.471, 0.314);
    float3 colors[3] = { amber, gold, coral };

    float cycle = fmod(index * 0.015, 3.0);
    int seg = int(floor(cycle));
    float t = cycle - float(seg);
    float3 from = colors[seg % 3];
    float3 to = colors[(seg + 1) % 3];
    return mix(from, to, t);
}

fragment float4 fs_phyllotaxis(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float t = u.time;
    float minDim = min(res.x, res.y);

    // Center-relative pixel coords
    float2 pixPos = in.pos.xy - res * 0.5;

    // Slow overall rotation
    float rotation = t * 0.02;

    // Accumulate glow from spiral points
    float3 col = float3(0.0);

    // Center glow
    float centerDist = length(pixPos) / minDim;
    float pulseIntensity = 0.4 + 0.15 * sin(t * 1.5);
    float3 centerGlow = float3(0.0);
    centerGlow += float3(0.784, 0.584, 0.424) * pulseIntensity * 0.35 * exp(-centerDist * centerDist * 80.0);
    centerGlow += float3(0.831, 0.647, 0.455) * pulseIntensity * 0.15 * exp(-centerDist * centerDist * 30.0);
    col += centerGlow;

    // Evaluate all spiral points and accumulate per-pixel
    float totalGlow = 0.0;
    float3 totalColor = float3(0.0);

    int numPoints = int(PH_MAX_POINTS);
    for (int n = 0; n < numPoints; n++) {
        float fn = float(n);

        // Phyllotaxis position
        float angle = fn * PH_GOLDEN_ANGLE + rotation;
        float baseRadius = PH_SPREAD * sqrt(fn) * minDim;

        // Pulsing
        float pulse = 1.0 + 0.12 * sin(t * 2.0 + fn * 0.1);
        float r = baseRadius * pulse;

        // Spiral point in pixel coords
        float2 spiralPos = float2(cos(angle), sin(angle)) * r;

        // Distance from this pixel to the spiral point
        float2 diff = pixPos - spiralPos;
        float dist = length(diff);

        // Point size (in pixels)
        float age = min(1.0, fn * 0.025);
        float baseSize = (1.2 + min(2.5, age * 2.0)) * pulse;

        // Fade: inner points brighter, outer fade
        float radialFade = smoothstep(1.0, 0.3, baseRadius / (minDim * 0.5));
        float alpha = radialFade * (0.6 + 0.4 * pulse);

        // Main point glow
        float pointGlow = exp(-dist * dist / (baseSize * baseSize * 4.0));

        // Broader halo for larger points
        float haloGlow = exp(-dist * dist / (baseSize * baseSize * 60.0)) * 0.15;

        float3 pointColor = ph_getColor(fn);
        float totalPointGlow = (pointGlow + haloGlow) * alpha;

        // Bright center highlight
        float brightCenter = exp(-dist * dist / (baseSize * baseSize * 0.5)) * alpha * 0.5;
        float3 brightColor = float3(1.0, 0.94, 0.86);

        totalColor += pointColor * totalPointGlow + brightColor * brightCenter;
        totalGlow += totalPointGlow;
    }

    col += totalColor;

    // Subtle connection lines via Fibonacci lattice pattern
    // Approximate the lattice by looking at angular/radial derivatives of the spiral
    float pixR = length(pixPos);
    // Approximate closest spiral index
    float approxN = (pixR / (PH_SPREAD * minDim));
    approxN = approxN * approxN; // since r = spread * sqrt(n)
    // Fibonacci lattice lines at strides 8 and 13
    float lattice8 = sin(approxN * PH_GOLDEN_ANGLE * 8.0 + rotation * 8.0);
    float lattice13 = sin(approxN * PH_GOLDEN_ANGLE * 13.0 + rotation * 13.0);
    float latticeGlow = (smoothstep(0.02, 0.0, abs(lattice8) * 0.3) +
                         smoothstep(0.02, 0.0, abs(lattice13) * 0.3)) * 0.02;
    float latticeRadialFade = smoothstep(0.0, 0.1, pixR / minDim) *
                              smoothstep(0.55, 0.3, pixR / minDim);
    col += float3(0.784, 0.584, 0.424) * latticeGlow * latticeRadialFade;

    // Vignette
    float vigDist = length(uv - 0.5) * 2.0;
    float vig = 1.0 - smoothstep(0.4, 1.5, vigDist);
    col *= 0.3 + 0.7 * vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
