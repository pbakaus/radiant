#include "Common.metal"

// ─── Fullscreen triangle vertex shader (shared by all fragment shaders) ───
vertex VSOut vs_fullscreen(uint vi [[vertex_id]]) {
    constexpr float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VSOut out;
    out.pos = float4(positions[vi], 0.0, 1.0);
    return out;
}
