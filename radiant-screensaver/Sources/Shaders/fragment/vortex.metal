#include "../Common.metal"

// ─── Vortex: Logarithmic spiral arms with silk glow ───
// Ported from static/vortex.html

// Default parameter values
constant float VX_WAVE_SPEED = 1.0;
constant float VX_LINE_COUNT = 6.0;
constant float VX_PI = 3.14159265;
constant float VX_TAU = 6.28318530;

// ── Hash for noise ──
static float vx_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float vx_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = vx_hash(i);
    float b = vx_hash(i + float2(1.0, 0.0));
    float c = vx_hash(i + float2(0.0, 1.0));
    float d = vx_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Distance from point to nearest logarithmic spiral arm
static float vx_spiralDist(float2 uv, float a, float b, float numArms, float t) {
    float r = length(uv);
    if (r < 0.001) return 1e6;
    float angle = atan2(uv.y, uv.x);

    float baseTheta = log(r / a) / b;

    // No mouse rotation in screensaver
    baseTheta -= t * 0.3;

    float armSpacing = VX_TAU / numArms;
    float nearest = fmod(angle - baseTheta, armSpacing);
    // Handle negative fmod result (MSL fmod can return negative)
    if (nearest < 0.0) nearest += armSpacing;
    if (nearest > armSpacing * 0.5) nearest -= armSpacing;

    float d = abs(nearest) * r;

    float undulation = sin(baseTheta * 4.0 + t * 0.5) * 0.015;
    d += undulation;
    d = abs(d);

    return d;
}

fragment float4 fs_vortex(VSOut in [[stage_in]],
                           constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - 0.5 * u.resolution) / u.resolution.y;
    float t = u.time * VX_WAVE_SPEED;

    // Center drifts slowly
    float2 center = float2(sin(t * 0.07) * 0.05, cos(t * 0.09) * 0.04);
    float2 p = uv - center;

    float r = length(p);
    int lineCount = int(VX_LINE_COUNT);

    float3 col = float3(0.0);

    for (int i = 0; i < 10; i++) {
        if (i >= lineCount) break;
        float fi = float(i);
        float frac_i = fi / max(VX_LINE_COUNT - 1.0, 1.0);

        float a = 0.02 + frac_i * 0.03;
        float b = 0.15 + frac_i * 0.08;
        float numArms = 3.0 + fi;

        float nOff = vx_noise(float2(fi * 3.7, t * 0.1)) * 0.008;

        float dist = vx_spiralDist(p + float2(nOff), a, b, numArms, t + fi * 0.5);

        // Silk glow
        float lw = 0.05 * smoothstep(0.1, 0.6, r);
        float l = smoothstep(lw, 0.0, dist - 0.004);

        float radialFade = smoothstep(0.9, 0.15, r) * smoothstep(0.0, 0.04, r);

        // Color: warm amber to gold
        float3 lineCol = float3(
            0.25 + frac_i * 0.65,
            0.2 + frac_i * 0.4,
            0.25 + (1.0 - frac_i) * 0.15
        );

        col += l * lineCol * radialFade;
    }

    // Central glow
    float centerGlow = 0.015 / (r + 0.02);
    col += float3(0.9, 0.65, 0.35) * centerGlow * 0.15;

    // ── Vignette ──
    float vig = 1.0 - dot(uv, uv) * 0.4;
    col *= max(vig, 0.0);

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(col, 1.0);
}
