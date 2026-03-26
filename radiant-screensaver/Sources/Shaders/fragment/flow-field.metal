#include "../Common.metal"

// ─── Flow Field: Particles following a noise-driven vector field ───
// Ported from static/flow-field.html (Canvas 2D particle trails)
// Approach: for each pixel, trace a virtual particle backward through
// the noise field to accumulate trail brightness. This captures the
// streaky, flowing visual of particle trails without actual particles.

constant float FF_NOISE_SCALE      = 2.5;
constant float FF_TRAIL_STEPS      = 32.0;
constant float FF_STEP_SIZE        = 0.004;
constant float FF_TIME_SCALE       = 0.08;
constant float FF_TRAIL_DECAY      = 0.92;
constant float FF_PI               = 3.14159265;

// 3D noise for time-evolving flow field (using 2D snoise with offset trick)
static float ff_noise3(float2 p, float z) {
    float n1 = snoise(p + float2(z * 0.7, z * 1.3));
    float n2 = snoise(p + float2(z * 1.1 + 100.0, z * 0.9 + 200.0));
    return n1 * 0.7 + n2 * 0.3;
}

// Get flow direction at a point
static float2 ff_flow(float2 p, float time) {
    float angle = ff_noise3(p * FF_NOISE_SCALE, time) * FF_PI * 2.0;
    return float2(cos(angle), sin(angle));
}

// Color from noise value (warm amber palette)
static float3 ff_color(float noiseVal) {
    // Map noise [-1,1] to warm color palette
    float t = noiseVal * 0.5 + 0.5; // 0..1

    // 7 palette colors: amber, gold, coral, dark amber, light gold, deep coral, muted gold
    float3 colors[7] = {
        float3(0.784, 0.584, 0.424), // amber
        float3(0.831, 0.647, 0.455), // gold
        float3(0.878, 0.471, 0.314), // coral
        float3(0.745, 0.510, 0.353), // dark amber
        float3(0.902, 0.706, 0.549), // light gold
        float3(0.824, 0.392, 0.275), // deep coral
        float3(0.706, 0.627, 0.471)  // muted gold
    };

    float idx = t * 6.0;
    int i = int(floor(idx));
    i = clamp(i, 0, 5);
    float f = idx - float(i);
    return mix(colors[i], colors[i + 1], f);
}

fragment float4 fs_flow_field(VSOut in [[stage_in]],
                               constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float minDim = min(res.x, res.y);
    float2 uv = (in.pos.xy - res * 0.5) / minDim;
    float t = u.time * FF_TIME_SCALE;

    // Background
    float3 col = float3(0.039, 0.039, 0.039);

    // For each pixel, trace backward along the flow field
    // This simulates what a particle arriving at this point would have looked like
    float2 pos = uv;
    float accumBright = 0.0;
    float3 accumColor = float3(0.0);
    float weight = 1.0;

    for (int i = 0; i < int(FF_TRAIL_STEPS); i++) {
        float2 flow = ff_flow(pos, t);

        // Color noise at this position
        float colorNoise = ff_noise3(pos * FF_NOISE_SCALE * 1.5 + float2(100.0), t * 0.5);
        float3 c = ff_color(colorNoise);

        // Flow-aligned brightness: stronger where flow is coherent
        float flowStrength = length(flow);

        // Add contribution from this step
        float stepBright = weight * flowStrength * 0.15;
        accumBright += stepBright;
        accumColor += c * stepBright;

        // Step backward along the flow
        pos -= flow * FF_STEP_SIZE;

        // Decay weight for older positions
        weight *= FF_TRAIL_DECAY;
    }

    // Normalize color
    if (accumBright > 0.001) {
        accumColor /= accumBright;
        // Apply brightness with a soft curve
        float brightness = saturate(accumBright * 1.5);
        brightness = pow(brightness, 0.8);
        col += accumColor * brightness * 0.5;
    }

    // Add noise-based density variation (simulates particle density)
    float density = snoise(uv * 3.0 + t * 0.5);
    density = density * 0.5 + 0.5;
    float densityBright = pow(density, 3.0) * 0.08;
    float3 densityColor = ff_color(snoise(uv * FF_NOISE_SCALE * 1.5 + float2(100.0)));
    col += densityColor * densityBright;

    // Subtle flow-direction visualization (very faint streaks)
    float2 mainFlow = ff_flow(uv, t);
    float flowAngle = atan2(mainFlow.y, mainFlow.x);
    float streak = snoise(uv * 20.0 + mainFlow * 2.0 + t);
    float streakBright = pow(abs(streak), 4.0) * 0.03;
    col += ff_color(snoise(uv * 4.0 + float2(50.0))) * streakBright;

    // Vignette
    float vig = 1.0 - smoothstep(0.3, 0.7, length(uv));
    col *= 0.7 + 0.3 * vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
