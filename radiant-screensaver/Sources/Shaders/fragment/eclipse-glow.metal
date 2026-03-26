#include "../Common.metal"

// ─── Eclipse Glow: Solar eclipse corona ───
// Ported from static/eclipse-glow.html

constant float EG_PI = 3.14159265359;
constant float EG_CORONA_SIZE = 1.0;
constant float EG_RAY_INTENSITY = 1.0;

// ── Hash for star field and grain ──
static float eg_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Value noise ──
static float eg_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(
        mix(eg_hash(i), eg_hash(i + float2(1.0, 0.0)), f.x),
        mix(eg_hash(i + float2(0.0, 1.0)), eg_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// ── FBM for corona rays (3 octaves, cheap) ──
static float eg_fbm3(float2 p) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 3; i++) {
        v += a * eg_vnoise(p);
        p = rot * p * 2.1 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// ── FBM 4 octaves for finer detail ──
static float eg_fbm4(float2 p) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.866, 0.5), float2(-0.5, 0.866));
    for (int i = 0; i < 4; i++) {
        v += a * eg_vnoise(p);
        p = rot * p * 2.05 + float2(3.1, 7.4);
        a *= 0.48;
    }
    return v;
}

fragment float4 fs_eclipse_glow(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float coronaSize = EG_CORONA_SIZE;
    float rayIntensity = EG_RAY_INTENSITY;

    // ── Polar coordinates ──
    float r = length(uv);
    float a = atan2(uv.y, uv.x);

    // ── Background: deep space ──
    float3 col = float3(0.005, 0.003, 0.008);

    // ── Star field — sparse hash-based points ──
    float2 starGrid = floor(in.pos.xy / 3.0);
    float starHash = eg_hash(starGrid * 0.73 + float2(13.7, 29.3));
    float starBright = step(0.997, starHash);
    // Twinkle
    float twinkle = sin(t * 1.5 + starHash * 100.0) * 0.4 + 0.6;
    starBright *= twinkle * eg_hash(starGrid * 1.31 + float2(7.1, 3.9));
    // Fade stars near corona
    starBright *= smoothstep(0.15, 0.45, r);
    col += float3(0.7, 0.75, 0.9) * starBright * 0.6;

    // ── Eclipse disc parameters ──
    float discRadius = 0.15;
    float chromoRadius = discRadius + 0.008;

    // ── Slow corona rotation ──
    float rotAngle = a + t * 0.05;

    // ── Corona ray noise — multiple octaves at different speeds ──
    float ray1 = eg_fbm3(float2(rotAngle * 3.0, r * 4.0 - t * 0.08));
    float ray2 = eg_fbm3(float2(rotAngle * 7.0 + 5.0, r * 6.0 - t * 0.12));
    float ray3 = eg_fbm4(float2(rotAngle * 13.0 + 10.0, r * 8.0 - t * 0.18));

    // Combine rays with weighting
    float rays = ray1 * 0.5 + ray2 * 0.3 + ray3 * 0.2;

    // ── Angular asymmetry — corona streamers vary in length ──
    float asymmetry = 0.7 + 0.3 * sin(a * 2.0 + 0.5) * sin(a * 3.0 + t * 0.02);
    asymmetry += 0.15 * sin(a * 5.0 + 1.7);
    rays *= asymmetry;

    // ── Radial falloff for corona ──
    float coronaOuter = discRadius + 0.35 * coronaSize;
    float radialFalloff = smoothstep(coronaOuter, discRadius + 0.02, r);
    radialFalloff *= smoothstep(discRadius - 0.01, discRadius + 0.03, r);

    // ── Extended ray reach — rays extend further than base corona ──
    float rayReach = discRadius + 0.6 * coronaSize;
    float rayFalloff = smoothstep(rayReach, discRadius + 0.03, r);
    rayFalloff *= smoothstep(discRadius - 0.01, discRadius + 0.03, r);

    // ── Corona color gradient: warm amber inner to deep orange outer ──
    float colorMix = smoothstep(discRadius, coronaOuter, r);
    float3 innerColor = float3(1.0, 0.75, 0.30);
    float3 outerColor = float3(0.8, 0.35, 0.08);
    float3 coronaColor = mix(innerColor, outerColor, colorMix);

    // ── Apply corona base glow ──
    float coronaGlow = radialFalloff * (0.4 + rays * 0.6);
    col += coronaColor * coronaGlow * 1.2 * rayIntensity;

    // ── Apply extended ray streaks ──
    float rayStreak = rayFalloff * pow(rays, 1.5) * 0.8;
    col += mix(coronaColor, outerColor, 0.5) * rayStreak * rayIntensity;

    // ── Bright inner corona ring (chromosphere) ──
    float chromoDist = abs(r - chromoRadius);
    float chromo = exp(-chromoDist * chromoDist / 0.00008);
    float chromoNoise = eg_fbm3(float2(rotAngle * 10.0, t * 0.2));
    chromo *= 0.7 + chromoNoise * 0.5;
    float3 chromoColor = float3(1.0, 0.85, 0.5);
    col += chromoColor * chromo * 2.5 * rayIntensity;

    // ── Hot inner edge — very tight bright ring ──
    float innerEdge = exp(-pow((r - discRadius) * 80.0, 2.0));
    innerEdge *= smoothstep(discRadius - 0.02, discRadius + 0.005, r);
    col += float3(1.0, 0.95, 0.8) * innerEdge * 3.0;

    // ── Solar wind — fine radial streaks via cheap hash ──
    float windA = floor((a + t * 0.02) * 80.0);
    float windR2 = floor((r - t * 0.06) * 100.0);
    float wind = eg_hash(float2(windA, windR2));
    wind = smoothstep(0.95, 1.0, wind);
    float windFade = smoothstep(discRadius, discRadius + 0.05, r);
    windFade *= smoothstep(rayReach + 0.08, discRadius + 0.06, r);
    col += float3(1.0, 0.85, 0.55) * wind * windFade * 0.06 * rayIntensity;

    // ── Bloom / lens flare ──
    float bloomDist = max(r - discRadius, 0.0);
    float bloom = exp(-bloomDist * 2.5);
    bloom *= smoothstep(discRadius - 0.05, discRadius + 0.01, r);
    col += float3(0.4, 0.25, 0.1) * bloom * 0.25 * rayIntensity;

    // Very wide subtle bloom
    float wideBloom = exp(-r * 1.2) * 0.15;
    col += float3(0.3, 0.18, 0.06) * wideBloom * rayIntensity;

    // Horizontal lens streak
    float streak = exp(-uv.y * uv.y * 80.0) * exp(-abs(r - discRadius) * 5.0);
    streak *= smoothstep(discRadius - 0.02, discRadius + 0.05, r);
    col += float3(0.6, 0.4, 0.2) * streak * 0.08 * rayIntensity;

    // ── Dark moon disc ──
    float disc = smoothstep(discRadius + 0.003, discRadius - 0.003, r);
    col *= 1.0 - disc;
    // Very faint lunar surface noise
    float lunarNoise = eg_vnoise(uv * 40.0) * 0.008;
    col += float3(lunarNoise * 0.5, lunarNoise * 0.4, lunarNoise * 0.3) * disc;

    // ── Diamond ring effect — no mouse, use slow oscillation ──
    float diamondAngle = sin(t * 0.02) * EG_PI;
    float2 diamondDir = float2(cos(diamondAngle), sin(diamondAngle));
    float diamondDot = dot(normalize(uv), diamondDir);
    float diamond = smoothstep(0.96, 1.0, diamondDot);
    float diamondR = smoothstep(discRadius + 0.025, discRadius, r);
    diamondR *= smoothstep(discRadius - 0.015, discRadius, r);
    float diamondGlow = diamond * diamondR;
    float diamondBoost = 1.5;
    col += float3(1.0, 0.95, 0.8) * diamondGlow * diamondBoost * rayIntensity;
    // Diamond bloom — soft radial spread
    float dBloomR = exp(-pow((r - discRadius) * 20.0, 2.0));
    float dBloomA = smoothstep(0.92, 1.0, diamondDot);
    col += float3(0.5, 0.35, 0.15) * dBloomR * dBloomA * (diamondBoost * 0.4) * rayIntensity;

    // ── Film grain ──
    float grain = (eg_hash(in.pos.xy + fract(t * 43.0) * 1000.0) - 0.5) * 0.015;
    col += grain;

    // ── Vignette — darker sky away from corona ──
    float vig = 1.0 - smoothstep(0.3, 1.1, r);
    col *= 0.7 + 0.3 * vig;

    // ── Tone mapping — keep blacks deep ──
    col = max(col, float3(0.0));
    // Soft highlight compression
    col = col / (1.0 + col * 0.3);
    // Slight warm push in shadows
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(col, col * float3(1.06, 0.97, 0.90), smoothstep(0.05, 0.0, lum) * 0.2);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
