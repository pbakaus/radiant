#include "../Common.metal"

// ─── Velvet Spotlight: Dust particles illuminated by sweeping light cones ───
// Ported from static/velvet-spotlight.html
// Strategy: Analytically define spotlight cones, evaluate per-pixel
// illumination from multiple cones, add noise-based dust particle field.

constant float VS_PI = 3.14159265;
constant int VS_NUM_SPOTS = 4;
constant float VS_SWEEP_SPEED = 0.5;

// ── Hash for particle noise ──
static float vs_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float vs_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = vs_hash(i);
    float b = vs_hash(i + float2(1.0, 0.0));
    float c = vs_hash(i + float2(0.0, 1.0));
    float d = vs_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Spotlight cone illumination ──
static float vs_spotIllum(float2 px, float2 origin, float angle,
                           float halfCone, float reach, float intensity, float breath) {
    float2 dp = px - origin;
    float dist = length(dp);
    if (dist < 1.0 || dist > reach) return 0.0;

    float angleToPixel = atan2(dp.y, dp.x);
    float angleDiff = angleToPixel - angle;
    // Normalize to -PI..PI
    angleDiff = angleDiff - round(angleDiff / (2.0 * VS_PI)) * 2.0 * VS_PI;

    if (abs(angleDiff) > halfCone) return 0.0;

    // Distance falloff
    float normDist = dist / reach;
    float distFalloff = (1.0 - normDist) * (1.0 - normDist);

    // Cone falloff with distance-based widening
    float coneWidthAtDist = halfCone * (0.3 + 0.7 * normDist);
    float coneNorm = angleDiff / coneWidthAtDist;
    float coneFalloff = exp(-coneNorm * coneNorm * 2.5);

    return coneFalloff * distFalloff * intensity * breath;
}

fragment float4 fs_velvet_spotlight(VSOut in [[stage_in]],
                                     constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 pixel = in.pos.xy;
    float t = u.time * VS_SWEEP_SPEED;

    float diag = length(res);
    float3 col = float3(0.039); // dark background

    // ── Define spotlights ──
    // Each: origin, base angle, angle range, cone width, reach, color, intensity
    struct SpotDef {
        float2 origin;
        float angleBase;
        float angleRange;
        float angleSpeed;
        float anglePhase;
        float halfCone;
        float reach;
        float3 color;
        float intensity;
        float breathPhase;
        float breathSpeed;
    };

    SpotDef spots[4];

    // Warm white from upper left
    spots[0].origin = float2(-res.x * 0.1, -res.y * 0.2);
    spots[0].angleBase = VS_PI * 0.35;
    spots[0].angleRange = 0.4;
    spots[0].angleSpeed = 0.13;
    spots[0].anglePhase = 0.0;
    spots[0].halfCone = 0.275;
    spots[0].reach = diag * 1.2;
    spots[0].color = float3(0.941, 0.910, 0.863);
    spots[0].intensity = 1.0;
    spots[0].breathPhase = 0.0;
    spots[0].breathSpeed = 0.3;

    // Cool from upper right
    spots[1].origin = float2(res.x * 1.1, -res.y * 0.15);
    spots[1].angleBase = VS_PI * 0.65;
    spots[1].angleRange = 0.35;
    spots[1].angleSpeed = 0.09;
    spots[1].anglePhase = VS_PI * 0.7;
    spots[1].halfCone = 0.25;
    spots[1].reach = diag * 1.1;
    spots[1].color = float3(0.816, 0.863, 0.910);
    spots[1].intensity = 0.85;
    spots[1].breathPhase = VS_PI * 0.5;
    spots[1].breathSpeed = 0.25;

    // Amber from center-right
    spots[2].origin = float2(res.x * 0.6, -res.y * 0.25);
    spots[2].angleBase = VS_PI * 0.5;
    spots[2].angleRange = 0.3;
    spots[2].angleSpeed = 0.07;
    spots[2].anglePhase = VS_PI * 1.3;
    spots[2].halfCone = 0.225;
    spots[2].reach = diag * 1.0;
    spots[2].color = float3(0.784, 0.584, 0.424);
    spots[2].intensity = 0.75;
    spots[2].breathPhase = VS_PI;
    spots[2].breathSpeed = 0.35;

    // Warm white narrow from upper-left
    spots[3].origin = float2(res.x * 0.15, -res.y * 0.3);
    spots[3].angleBase = VS_PI * 0.45;
    spots[3].angleRange = 0.25;
    spots[3].angleSpeed = 0.11;
    spots[3].anglePhase = VS_PI * 2.1;
    spots[3].halfCone = 0.19;
    spots[3].reach = diag * 0.9;
    spots[3].color = float3(1.0, 0.973, 0.941);
    spots[3].intensity = 0.65;
    spots[3].breathPhase = VS_PI * 1.5;
    spots[3].breathSpeed = 0.28;

    // ── Accumulate cone illumination and volumetric glow ──
    float totalIllum = 0.0;
    float3 lightColor = float3(0.0);
    float3 coneGlow = float3(0.0);

    for (int s = 0; s < VS_NUM_SPOTS; s++) {
        float angle = spots[s].angleBase +
                      sin(t * spots[s].angleSpeed * 2.0 + spots[s].anglePhase) * spots[s].angleRange;
        float breath = 0.7 + 0.3 * sin(t * spots[s].breathSpeed * 2.0 + spots[s].breathPhase);

        float illum = vs_spotIllum(pixel, spots[s].origin, angle,
                                    spots[s].halfCone, spots[s].reach,
                                    spots[s].intensity, breath);

        totalIllum += illum;
        lightColor += spots[s].color * illum;

        // Volumetric cone glow (additive atmospheric haze)
        float coneIllum = vs_spotIllum(pixel, spots[s].origin, angle,
                                        spots[s].halfCone * 0.8, spots[s].reach * 0.8,
                                        spots[s].intensity, breath);
        coneGlow += spots[s].color * coneIllum * 0.04;
    }

    col += coneGlow;

    // ── Dust particles via noise ──
    if (totalIllum > 0.02) {
        float3 normLight = lightColor / max(totalIllum, 0.001);

        // Multi-scale noise for dust
        float noiseTime = t * 0.3;
        float dust1 = vs_noise(pixel * 0.15 + float2(noiseTime * 7.0, noiseTime * 3.0));
        float dust2 = vs_noise(pixel * 0.4 + float2(-noiseTime * 5.0, noiseTime * 8.0));
        float dust3 = vs_noise(pixel * 1.0 + float2(noiseTime * 11.0, -noiseTime * 4.0));

        // Combine: sparse bright dust motes
        float dustVal = dust1 * 0.5 + dust2 * 0.3 + dust3 * 0.2;
        float dustThreshold = smoothstep(0.45, 0.75, dustVal);

        float dustAlpha = totalIllum * dustThreshold * 1.2;

        // White blend in bright overlaps
        float3 dustCol = normLight;
        if (totalIllum > 0.5) {
            float whiteBlend = min(1.0, (totalIllum - 0.5) * 0.8) * 0.4;
            dustCol = mix(dustCol, float3(1.0), whiteBlend);
        }

        col += dustCol * min(dustAlpha, 1.0) * 0.6;

        // Bright motes: larger, sparser
        float moteNoise = vs_noise(pixel * 0.03 + float2(noiseTime * 2.0, noiseTime));
        float moteThreshold = smoothstep(0.7, 0.85, moteNoise);
        if (moteThreshold > 0.0) {
            float pulse = 0.7 + 0.3 * sin(t * 1.5 + moteNoise * 20.0);
            float moteAlpha = totalIllum * moteThreshold * pulse * 0.8;
            float3 moteCol = mix(normLight, float3(1.0), 0.3);

            // Soft glow around motes
            float moteGlow = smoothstep(0.85, 0.7, moteNoise) * 0.3;
            col += moteCol * (moteAlpha + moteGlow * totalIllum) * 0.5;
        }
    }

    // ── Scattering haze near spotlight centers ──
    for (int s = 0; s < VS_NUM_SPOTS; s++) {
        float angle = spots[s].angleBase +
                      sin(t * spots[s].angleSpeed * 2.0 + spots[s].anglePhase) * spots[s].angleRange;
        float breath = 0.7 + 0.3 * sin(t * spots[s].breathSpeed * 2.0 + spots[s].breathPhase);

        float hazeDist = min(res.x, res.y) * 0.25;
        float2 hazeCenter = spots[s].origin + float2(cos(angle), sin(angle)) * hazeDist;
        float hazeRadius = min(res.x, res.y) * 0.3;

        float hd = length(pixel - hazeCenter) / hazeRadius;
        float hazeAlpha = 0.015 * spots[s].intensity * breath * smoothstep(1.0, 0.0, hd);
        col += spots[s].color * hazeAlpha;
    }

    col = hue_rotate(col, u.hue_shift);
    return float4(saturate(col), 1.0);
}
