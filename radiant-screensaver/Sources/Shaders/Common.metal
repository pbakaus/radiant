#ifndef COMMON_METAL
#define COMMON_METAL

#include <metal_stdlib>
using namespace metal;

// ─── Common uniform buffer shared by all shaders ───
struct CommonUniforms {
    float time;          // 0: elapsed seconds (quarter speed)
    float hue_shift;     // 1: slow hue rotation
    float2 resolution;   // 2-3: render target size in pixels
};

// ─── Vertex output ───
struct VSOut {
    float4 pos [[position]];
};

// ─── Simplex 2D noise ───
static float3 mod289_3(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float2 mod289_2(float2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
static float3 permute(float3 x) { return mod289_3((x * 34.0 + 1.0) * x); }

static float snoise(float2 v) {
    const float4 C = float4(0.211324865405187, 0.366025403784439,
                            -0.577350269189626, 0.024390243902439);
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1;
    if (x0.x > x0.y) { i1 = float2(1.0, 0.0); } else { i1 = float2(0.0, 1.0); }
    float4 x12 = x0.xyxy + C.xxzz;
    x12 = float4(x12.xy - i1, x12.zw);
    float2 ii = mod289_2(i);
    float3 p = permute(permute(ii.y + float3(0.0, i1.y, 1.0)) + ii.x + float3(0.0, i1.x, 1.0));
    float3 m = max(float3(0.5) - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), float3(0.0));
    m = m * m; m = m * m;
    float3 x_ = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x_) - 0.5;
    float3 ox = floor(x_ + 0.5);
    float3 a0 = x_ - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    float3 g;
    g.x = a0.x * x0.x + h.x * x0.y;
    g.y = a0.y * x12.x + h.y * x12.y;
    g.z = a0.z * x12.z + h.z * x12.w;
    return 130.0 * dot(m, g);
}

// ─── Hue rotation ───
static float3 hue_rotate(float3 c, float a) {
    float ca = cos(a); float sa = sin(a);
    float3 k = float3(0.57735);
    return c * ca + cross(k, c) * sa + k * dot(k, c) * (1.0 - ca);
}

#endif
