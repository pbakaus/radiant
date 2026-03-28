#include "../Common.metal"

// ─── Fluid Amber: Domain-warped simplex noise with warm palette ───
// Ported from static/fluid-amber.html

static float fbm_fa(float2 p, float t) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    constexpr float AMP_DECAY = 0.48;
    for (int i = 0; i < 5; i++) {
        val += amp * snoise(p * freq + t * 0.3);
        freq *= 2.1;
        amp *= AMP_DECAY;
        p += float2(1.7, 9.2);
    }
    return val;
}

fragment float4 fs_fluid_amber(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 p = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    constexpr float TIME_SCALE = 0.15;
    float t = u.time * TIME_SCALE;

    // Domain warping: q feeds into r feeds into final field
    float2 q = float2(fbm_fa(p, t),
                       fbm_fa(p + float2(5.2, 1.3), t));

    float2 r = float2(fbm_fa(p + 4.0 * q + float2(1.7, 9.2), t * 1.2),
                       fbm_fa(p + 4.0 * q + float2(8.3, 2.8), t * 1.2));

    float f = fbm_fa(p + 3.5 * r, t * 0.8);

    // Warm amber palette
    float3 col = mix(float3(0.075, 0.065, 0.055), float3(0.20, 0.14, 0.07), clamp(f * f * 2.0, 0.0, 1.0));
    col = mix(col, float3(0.78, 0.58, 0.24), clamp(length(q) * 0.5, 0.0, 1.0));
    col = mix(col, float3(0.95, 0.75, 0.35), clamp(r.x * 0.6, 0.0, 1.0));

    float highlight = smoothstep(0.5, 1.2, f * f * 3.0 + length(r) * 0.5);
    col += float3(0.18, 0.12, 0.04) * highlight;

    col = pow(col, float3(1.1));

    return float4(col, 1.0);
}
