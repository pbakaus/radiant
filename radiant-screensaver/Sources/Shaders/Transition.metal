#include "Common.metal"

// ─── Transition uniforms ───
struct TransitionUniforms {
    float progress;      // 0→1 during morph
    float time;          // for noise animation
    float hue_shift;     // global hue rotation
    float zoom;          // zoom factor (1.0→1.35)
    float2 resolution;   // render target size
};

// ─── Noise dissolve transition (ports zoom route's GLSL) ───
fragment float4 fs_transition(VSOut in [[stage_in]],
                              texture2d<float> texA [[texture(0)]],
                              texture2d<float> texB [[texture(1)]],
                              constant TransitionUniforms& u [[buffer(0)]]) {
    constexpr sampler samp(filter::linear, address::clamp_to_edge);

    float2 raw_uv = in.pos.xy / u.resolution;
    // Zoom toward center
    float2 uv = (raw_uv - 0.5) / u.zoom + 0.5;
    uv = clamp(uv, float2(0.0), float2(1.0));
    // Flip Y for texture sampling (Metal textures are top-down)
    float2 tex_uv = float2(uv.x, 1.0 - uv.y);

    float4 colA = texA.sample(samp, tex_uv);
    float4 colB = texB.sample(samp, tex_uv);

    // Early exit: no transition
    if (u.progress <= 0.0) {
        return float4(hue_rotate(colA.rgb, u.hue_shift), 1.0);
    }
    if (u.progress >= 1.0) {
        return float4(hue_rotate(colB.rgb, u.hue_shift), 1.0);
    }

    // Dual-octave noise dissolve
    constexpr float NOISE_SCALE = 3.0;
    constexpr float SOFTNESS = 0.25;
    float n = snoise(raw_uv * NOISE_SCALE + u.time * 0.15);
    n += 0.5 * snoise(raw_uv * (NOISE_SCALE * 2.0) - u.time * 0.1);
    n = n * 0.5 + 0.5;

    float edge = smoothstep(u.progress + SOFTNESS, u.progress - SOFTNESS, n);
    float3 blended = mix(colA.rgb, colB.rgb, edge);

    return float4(hue_rotate(blended, u.hue_shift), 1.0);
}
