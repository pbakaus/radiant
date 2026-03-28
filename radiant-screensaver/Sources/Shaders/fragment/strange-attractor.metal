#include "../Common.metal"

// ─── Strange Attractor: Lorenz attractor with glowing trails ───
// Ported from static/strange-attractor.html
// Strategy: Approximate the Lorenz attractor's butterfly shape using
// noise-modulated figure-eight paths in screen space. Multiple "particles"
// traced as parametric curves with glow accumulation.

constant float SA_PI = 3.14159265;
constant float SA_ROTATION_SPEED = 0.12;
constant int SA_NUM_TRAILS = 5;
constant int SA_TRAIL_SAMPLES = 80;

// ── Hash ──
static float sa_hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// ── Lorenz-like parametric curve ──
// Traces the characteristic butterfly shape analytically
static float3 sa_lorenzCurve(float param, float offset, float t) {
    // Two lobes of the Lorenz attractor
    // param sweeps 0..1 along the trail
    float p = param * SA_PI * 4.0 + offset * 2.3 + t * 0.4;

    // Asymmetric figure-eight with Lorenz-like proportions
    float x = sin(p) * (1.0 + 0.3 * sin(p * 0.5 + offset));
    float z_raw = cos(p) * sin(p) + 0.5 * sin(p * 0.37 + offset * 1.7);
    // Lorenz z is ~25 center, scale to normalized coords
    float y = cos(p * 0.5 + offset * 0.3) * 0.6 + sin(p * 0.73) * 0.3;

    // Add chaotic wobble via noise-like hash mixing
    float wobbleX = sin(p * 3.7 + offset * 5.1 + t * 0.2) * 0.15;
    float wobbleY = cos(p * 2.9 + offset * 3.7 + t * 0.15) * 0.12;

    return float3(x + wobbleX, y + wobbleY, z_raw);
}

// ── Project with Y-axis rotation and perspective ──
static float2 sa_project(float3 p, float angle, float scaleFactor) {
    float ca = cos(angle);
    float sa_s = sin(angle);
    float rx = p.x * ca - p.z * sa_s;
    float rz = p.x * sa_s + p.z * ca;
    float scale = 1.5 / (1.5 + rz * 0.3);
    return float2(rx * scale, -p.y * scale) * scaleFactor;
}

fragment float4 fs_strange_attractor(VSOut in [[stage_in]],
                                      constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 screenPt = in.pos.xy - 0.5 * res;
    float t = u.time;
    float angle = t * SA_ROTATION_SPEED;
    float scaleFactor = min(res.x, res.y) * 0.3;

    float totalDensity = 0.0;
    float3 totalColor = float3(0.0);

    // Warm color palette per trail
    float3 trailColors[5] = {
        float3(0.784, 0.584, 0.424),
        float3(0.831, 0.647, 0.455),
        float3(0.878, 0.471, 0.314),
        float3(0.745, 0.549, 0.392),
        float3(0.902, 0.588, 0.353)
    };

    for (int trail = 0; trail < SA_NUM_TRAILS; trail++) {
        float trailOffset = float(trail) * 0.7;

        for (int s = 0; s < SA_TRAIL_SAMPLES; s++) {
            float param = float(s) / float(SA_TRAIL_SAMPLES);

            float3 pos3D = sa_lorenzCurve(param, trailOffset, t);
            float2 projected = sa_project(pos3D, angle, scaleFactor);

            float2 diff = screenPt - projected;
            float dist2 = dot(diff, diff);

            // Trail fades: head brighter, tail dimmer
            float headFade = param * param;

            // Two glow passes: wide soft + narrow bright
            float wideGlow = exp(-dist2 / 64.0) * headFade * 0.12;
            float narrowGlow = exp(-dist2 / 6.0) * headFade * 0.7;

            float glow = wideGlow + narrowGlow;
            totalColor += trailColors[trail] * glow;
            totalDensity += glow;
        }
    }

    float3 col = totalColor * 0.15;

    // Bright head dots (at param ~1.0 for each trail)
    for (int trail = 0; trail < SA_NUM_TRAILS; trail++) {
        float trailOffset = float(trail) * 0.7;
        float3 headPos = sa_lorenzCurve(1.0, trailOffset, t);
        float2 headProj = sa_project(headPos, angle, scaleFactor);
        float headDist = length(screenPt - headProj);

        // Radial glow for head
        float outerGlow = exp(-headDist * headDist / 100.0) * 0.3;
        float innerGlow = exp(-headDist * headDist / 4.0) * 0.8;

        float3 headCol = trailColors[trail] * 1.3 + float3(0.2);
        col += headCol * (outerGlow + innerGlow);
    }

    // Background
    col += float3(0.039);

    // Vignette
    float2 uv = in.pos.xy / res - 0.5;
    float vig = 1.0 - dot(uv, uv) * 1.5;
    col *= max(vig, 0.0);

    col = hue_rotate(col, u.hue_shift);
    return float4(saturate(col), 1.0);
}
