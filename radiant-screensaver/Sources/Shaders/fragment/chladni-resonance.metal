#include "../Common.metal"

// ─── Chladni Resonance: Vibrating plate nodal patterns ───
// Ported from static/chladni-resonance.html

// Default parameter values (screensaver — no mouse)
constant float CR_MODE_SPEED = 0.5;
constant float CR_COMPLEXITY = 5.0;

static float cr_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float cr_chladni(float2 p, float n, float m) {
    constexpr float pi = 3.14159265;
    return cos(n * pi * p.x) * cos(m * pi * p.y) - cos(m * pi * p.x) * cos(n * pi * p.y);
}

// Get mode pair using time — no arrays needed
static float2 cr_getMode(float idx) {
    // 6 beautiful Chladni mode pairs
    if (idx < 1.0) return float2(1.0, 2.0);
    if (idx < 2.0) return float2(2.0, 3.0);
    if (idx < 3.0) return float2(3.0, 5.0);
    if (idx < 4.0) return float2(1.0, 4.0);
    if (idx < 5.0) return float2(2.0, 5.0);
    return float2(3.0, 4.0);
}

fragment float4 fs_chladni_resonance(VSOut in [[stage_in]],
                                      constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * CR_MODE_SPEED;

    float2 p = uv * 2.0;

    // No mouse interaction for screensaver

    // Circular plate
    float plateDist = length(uv);
    float plateMask = smoothstep(0.52, 0.47, plateDist);

    // Cycle through modes
    float modeTime = t * 0.15;
    float modeIdx = fmod(modeTime, 6.0);
    float idx0 = floor(modeIdx);
    float idx1 = fmod(idx0 + 1.0, 6.0);
    float blend = fract(modeIdx);
    blend = blend * blend * (3.0 - 2.0 * blend);

    float2 mode0 = cr_getMode(idx0);
    float2 mode1 = cr_getMode(idx1);

    float cScale = CR_COMPLEXITY / 5.0;

    float c0 = cr_chladni(p, mode0.x * cScale, mode0.y * cScale);
    float c1 = cr_chladni(p, mode1.x * cScale, mode1.y * cScale);
    float c = mix(c0, c1, blend);

    // Secondary pattern for richness
    float cb0 = cr_chladni(p + 0.03, mode0.x * cScale + 0.5, mode0.y * cScale + 0.5);
    float cb1 = cr_chladni(p + 0.03, mode1.x * cScale + 0.5, mode1.y * cScale + 0.5);
    float cb = mix(cb0, cb1, blend);

    // Sand on nodal lines — use smoothstep for wide, visible lines
    float w = 0.3 + 0.1 * sin(t * 0.5);
    float sand = 1.0 - smoothstep(0.0, w, abs(c));
    float sand2 = (1.0 - smoothstep(0.0, w * 1.3, abs(cb))) * 0.35;
    sand = max(sand, sand2);
    sand = pow(sand, 0.6);

    // Grain texture
    float grain = cr_hash(in.pos.xy + fract(t * 0.1) * 100.0);
    float grainMask = smoothstep(0.1, 0.4, sand);
    sand *= 0.8 + 0.2 * grain * grainMask;

    // Color
    float3 plate = float3(0.03, 0.025, 0.02);
    float3 sandCol = mix(float3(0.65, 0.45, 0.22), float3(0.95, 0.78, 0.40), sand);

    // Bloom
    float bloom = 1.0 - smoothstep(0.0, w * 2.5, abs(c));

    float3 col = mix(plate, sandCol, sand);
    col += float3(0.25, 0.17, 0.07) * bloom * 0.4;

    // Plate reflection
    float reflAngle = atan2(uv.y, uv.x) + t * 0.05;
    float refl = 0.02 * (0.5 + 0.5 * sin(reflAngle * 3.0)) * smoothstep(0.55, 0.2, plateDist);
    col += float3(0.12, 0.10, 0.06) * refl * (1.0 - sand);

    // Edge glow
    float edge = smoothstep(0.5, 0.43, plateDist) * smoothstep(0.38, 0.46, plateDist);
    col += float3(0.10, 0.07, 0.03) * edge;

    col *= plateMask;
    col += float3(0.008, 0.006, 0.004) * (1.0 - plateMask);

    // Vignette
    float vig = 1.0 - smoothstep(0.3, 0.85, plateDist);
    col *= 0.75 + 0.25 * vig;

    // Grain
    col += (cr_hash(in.pos.xy + t * 73.0) - 0.5) * 0.012;
    col = pow(max(col, 0.0), float3(0.95));

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
