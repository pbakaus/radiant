#include "../Common.metal"

// ─── Tropical Heat: Heat distortion with chromatic aberration ───
// Ported from static/tropical-heat.html

// Default parameter values (screensaver — no interactive controls)
constant float TH_HEAT_INTENSITY = 1.0;
constant float TH_COLOR_VIBRANCY = 0.8;

// ── FBM using snoise from Common.metal ──
static float th_fbm(float2 p, float t) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 6; i++) {
        val += amp * snoise(p * freq + t * 0.25);
        freq *= 2.05;
        amp *= 0.5;
        p += float2(1.7, 9.2);
    }
    return val;
}

// ── Domain-warped fbm for organic heat flow ──
static float th_warpedFbm(float2 p, float t) {
    float2 q = float2(th_fbm(p + float2(0.0, 0.0), t),
                       th_fbm(p + float2(5.2, 1.3), t));
    float2 r = float2(th_fbm(p + 3.0 * q + float2(1.7, 9.2), t * 1.15),
                       th_fbm(p + 3.0 * q + float2(8.3, 2.8), t * 1.15));
    return th_fbm(p + 2.5 * r, t * 0.9);
}

// ── Heat shimmer distortion field ──
static float2 th_heatDistortion(float2 uv, float t, float intensity) {
    float n1 = snoise(float2(uv.x * 3.0, uv.y * 6.0 - t * 1.8)) * 0.5;
    float n2 = snoise(float2(uv.x * 5.0 + 1.3, uv.y * 10.0 - t * 2.5 + 3.7)) * 0.3;
    float n3 = snoise(float2(uv.x * 8.0 - 2.1, uv.y * 4.0 - t * 1.2 + 7.1)) * 0.2;

    float h1 = snoise(float2(uv.x * 4.0 + t * 0.8, uv.y * 7.0 - t * 1.5)) * 0.4;
    float h2 = snoise(float2(uv.x * 7.0 - t * 0.5, uv.y * 3.0 + 2.3)) * 0.25;

    float2 distort;
    distort.x = (h1 + h2) * intensity * 0.025;
    distort.y = (n1 + n2 + n3) * intensity * 0.018;

    return distort;
}

// ── Tropical color palette ──
static float3 th_tropicalColor(float t, float vibrancy) {
    float3 a = float3(0.55, 0.3, 0.25);
    float3 b = float3(0.45, 0.35, 0.3);
    float3 c = float3(1.0, 0.8, 0.7);
    float3 d = float3(0.0, 0.15, 0.35);
    float3 col = a + b * cos(6.28318 * (c * t + d));
    float luminance = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(luminance), col, 1.0 + vibrancy * 0.6);
    return col;
}

static float3 th_magentaOrange(float t, float vibrancy) {
    float3 a = float3(0.6, 0.2, 0.35);
    float3 b = float3(0.4, 0.3, 0.25);
    float3 c = float3(1.2, 1.0, 0.6);
    float3 d = float3(0.1, 0.25, 0.45);
    float3 col = a + b * cos(6.28318 * (c * t + d));
    float luminance = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(float3(luminance), col, 1.0 + vibrancy * 0.5);
    return col;
}

fragment float4 fs_tropical_heat(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    // No mouse — use default heat center
    float2 heatCenter = float2(0.5);
    float2 p = (in.pos.xy - u.resolution * heatCenter) / min(u.resolution.x, u.resolution.y);
    float t = u.time;

    // ── Heat distortion ──
    float2 distort = th_heatDistortion(uv, t, TH_HEAT_INTENSITY);

    // ── Chromatic aberration ──
    float aberration = TH_HEAT_INTENSITY * 0.012;
    float2 uvR = uv + distort * 1.3 + float2(aberration, aberration * 0.5);
    float2 uvG = uv + distort * 1.0;
    float2 uvB = uv + distort * 0.7 - float2(aberration * 0.8, aberration * 0.3);

    float2 pR = (uvR * u.resolution - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float2 pG = (uvG * u.resolution - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float2 pB = (uvB * u.resolution - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);

    // ── Base pattern ──
    float warpR = th_warpedFbm(pR * 1.5, t * 0.3);
    float warpG = th_warpedFbm(pG * 1.5, t * 0.3 + 0.7);
    float warpB = th_warpedFbm(pB * 1.5, t * 0.3 + 1.4);

    // ── Layer 1: Deep flowing heat base ──
    float3 baseColor;
    baseColor.r = th_tropicalColor(warpR * 0.8 + t * 0.05, TH_COLOR_VIBRANCY).r;
    baseColor.g = th_tropicalColor(warpG * 0.8 + t * 0.05 + 0.33, TH_COLOR_VIBRANCY).g;
    baseColor.b = th_magentaOrange(warpB * 0.8 + t * 0.05 + 0.66, TH_COLOR_VIBRANCY).b;

    // ── Layer 2: Hot magenta/orange undercurrent ──
    float flow1 = snoise(p * 2.5 + float2(t * 0.4, -t * 0.3));
    float flow2 = snoise(p * 3.8 + float2(-t * 0.35, t * 0.25));
    float flowMask = smoothstep(-0.2, 0.6, flow1 * flow2);

    float3 hotLayer = th_magentaOrange(flow1 * 0.5 + t * 0.08, TH_COLOR_VIBRANCY);
    hotLayer *= float3(1.1, 0.7, 0.9);
    baseColor = mix(baseColor, hotLayer, flowMask * 0.4 * TH_COLOR_VIBRANCY);

    // ── Layer 3: Warm teal accents ──
    float tealNoise = snoise(p * 4.0 + float2(t * 0.2, t * 0.15 + 5.0));
    float tealMask = smoothstep(0.3, 0.8, tealNoise) * 0.15 * TH_COLOR_VIBRANCY;
    baseColor = mix(baseColor, float3(0.1, 0.45, 0.4), tealMask);

    // ── Color blooms ──
    // Bloom 1
    float bloomTime1 = sin(t * 0.4) * 0.5 + 0.5;
    bloomTime1 = pow(bloomTime1, 6.0);
    float2 bloomCenter1 = float2(
        snoise(float2(t * 0.13, 0.0)) * 0.4,
        snoise(float2(0.0, t * 0.11 + 3.0)) * 0.4
    );
    float bloomDist1 = length(p - bloomCenter1);
    float bloom1 = bloomTime1 * smoothstep(0.5, 0.0, bloomDist1);
    float3 bloomColor1 = float3(0.95, 0.4, 0.2);

    // Bloom 2
    float bloomTime2 = sin(t * 0.7 + 2.1) * 0.5 + 0.5;
    bloomTime2 = pow(bloomTime2, 8.0);
    float2 bloomCenter2 = float2(
        snoise(float2(t * 0.17 + 7.0, 2.0)) * 0.35,
        snoise(float2(3.0, t * 0.14 + 5.0)) * 0.35
    );
    float bloomDist2 = length(p - bloomCenter2);
    float bloom2 = bloomTime2 * smoothstep(0.35, 0.0, bloomDist2);
    float3 bloomColor2 = float3(0.85, 0.15, 0.5);

    // Bloom 3
    float bloomTime3 = sin(t * 0.55 + 4.3) * 0.5 + 0.5;
    bloomTime3 = pow(bloomTime3, 7.0);
    float2 bloomCenter3 = float2(
        snoise(float2(t * 0.1 + 12.0, 8.0)) * 0.3,
        snoise(float2(6.0, t * 0.09 + 10.0)) * 0.3
    );
    float bloomDist3 = length(p - bloomCenter3);
    float bloom3 = bloomTime3 * smoothstep(0.45, 0.0, bloomDist3);
    float3 bloomColor3 = float3(1.0, 0.65, 0.1);

    baseColor += bloomColor1 * bloom1 * 0.7 * TH_COLOR_VIBRANCY;
    baseColor += bloomColor2 * bloom2 * 0.6 * TH_COLOR_VIBRANCY;
    baseColor += bloomColor3 * bloom3 * 0.5 * TH_COLOR_VIBRANCY;

    // ── Intensity spikes ──
    float spike = pow(sin(t * 0.25) * 0.5 + 0.5, 12.0);
    float spikeWave = snoise(p * 1.5 - float2(0.0, t * 0.8)) * 0.5 + 0.5;
    baseColor += float3(0.2, 0.08, 0.03) * spike * spikeWave * TH_HEAT_INTENSITY;

    // ── Heat haze highlight ──
    float haze = snoise(float2(p.x * 6.0, p.y * 12.0 - t * 2.0));
    float hazeLines = pow(smoothstep(0.4, 0.9, haze), 3.0);
    baseColor += float3(0.15, 0.08, 0.04) * hazeLines * TH_HEAT_INTENSITY * 0.5;

    // ── Grounding ──
    float luminance = dot(baseColor, float3(0.299, 0.587, 0.114));
    float3 amberTint = float3(0.78, 0.58, 0.42) * luminance;
    baseColor = mix(baseColor, amberTint, 0.12);

    // ── Vignette ──
    float vig = 1.0 - dot(p, p) * 0.5;
    vig = clamp(vig, 0.0, 1.0);
    vig = pow(vig, 0.7);
    baseColor *= vig;

    // ── Tone mapping ──
    baseColor = baseColor / (1.0 + baseColor * 0.25);

    // ── Final contrast and warmth ──
    baseColor = pow(baseColor, float3(0.95));
    baseColor *= float3(1.05, 0.97, 0.88);

    baseColor = hue_rotate(baseColor, u.hue_shift);
    return float4(baseColor, 1.0);
}
