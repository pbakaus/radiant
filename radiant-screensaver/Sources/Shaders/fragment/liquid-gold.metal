#include "../Common.metal"

// ─── Liquid Gold: Molten metal flow with surface tension and golden reflections ───
// Ported from static/liquid-gold.html

constant float LG_PI = 3.14159265359;

// Default parameter values
constant float LG_FLOW_SPEED = 0.4;
constant float LG_VISCOSITY = 0.6;

// ── Hash ──

static float lg_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth value noise ──

static float lg_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = lg_hash(i);
    float b = lg_hash(i + float2(1.0, 0.0));
    float c = lg_hash(i + float2(0.0, 1.0));
    float d = lg_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM with viscosity-controlled octave decay ──

static float lg_fbm(float2 p, float t, float visc) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    float decay = 0.45 + visc * 0.2;
    for (int i = 0; i < 6; i++) {
        val += amp * lg_noise(p * freq + t);
        freq *= 2.0 + visc * 0.3;
        amp *= decay;
        p += float2(1.7, 9.2);
    }
    return val;
}

// ── Domain warping for viscous flow ──

static float lg_warpedField(float2 p, float t, float visc) {
    float2 q = float2(
        lg_fbm(p + float2(0.0, 0.0), t * 0.5, visc),
        lg_fbm(p + float2(5.2, 1.3), t * 0.5, visc)
    );

    float2 r = float2(
        lg_fbm(p + 3.0 * q + float2(1.7, 9.2), t * 0.7, visc),
        lg_fbm(p + 3.0 * q + float2(8.3, 2.8), t * 0.7, visc)
    );

    float f = lg_fbm(p + 2.5 * r, t * 0.4, visc);

    return f + length(q) * 0.4 + length(r) * 0.3;
}

// ── Metaball-like surface bumps ──

static float lg_metaballs(float2 p, float t) {
    float val = 0.0;
    for (int i = 0; i < 7; i++) {
        float fi = float(i);
        float2 center = float2(
            sin(t * 0.3 + fi * 2.1) * 0.6 + cos(t * 0.2 + fi * 1.3) * 0.3,
            cos(t * 0.25 + fi * 1.7) * 0.6 + sin(t * 0.15 + fi * 2.5) * 0.3
        );
        float radius = 0.15 + 0.1 * sin(t * 0.4 + fi * 3.0);
        float d = length(p - center);
        val += radius / (d + 0.05);
    }
    return val;
}

// ── Surface normal estimation for lighting ──

static float3 lg_getNormal(float2 p, float t, float visc, float warpCenter) {
    constexpr float EPS = 0.005;
    float hC = warpCenter + lg_metaballs(p, t) * 0.08;
    float hR = lg_warpedField(p + float2(EPS, 0.0), t, visc) + lg_metaballs(p + float2(EPS, 0.0), t) * 0.08;
    float hU = lg_warpedField(p + float2(0.0, EPS), t, visc) + lg_metaballs(p + float2(0.0, EPS), t) * 0.08;

    float3 n = normalize(float3(
        (hC - hR) / EPS,
        (hC - hU) / EPS,
        1.0
    ));
    return n;
}

// ── Fresnel approximation ──

static float lg_fresnel(float cosTheta, float f0) {
    return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

// ── Main fragment function ──

fragment float4 fs_liquid_gold(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float2 screenUv = in.pos.xy / u.resolution;
    float t = u.time * LG_FLOW_SPEED;
    float visc = LG_VISCOSITY;

    // ── Compute the height field ──
    float field = lg_warpedField(uv * 2.0, t, visc);
    float meta = lg_metaballs(uv, t);

    float height = field + meta * 0.08;

    // ── Surface normal for lighting ──
    float3 normal = lg_getNormal(uv * 2.0, t, visc, field);

    // ── View and light setup ──
    float3 viewDir = normalize(float3(0.0, 0.0, 1.0));
    float3 lightDir1 = normalize(float3(0.4, 0.5, 0.9));
    float3 lightDir2 = normalize(float3(-0.6, -0.3, 0.7));
    float3 lightDir3 = normalize(float3(0.0, 0.8, 0.5));

    // No mouse in screensaver mode

    // ── Gold material properties ──
    float3 goldBase = float3(0.83, 0.61, 0.22);
    float3 goldBright = float3(1.0, 0.84, 0.45);
    float3 goldDeep = float3(0.55, 0.35, 0.08);
    float3 goldShadow = float3(0.18, 0.10, 0.02);
    float3 whiteHot = float3(1.0, 0.97, 0.88);

    constexpr float F0 = 0.8;

    // ── Diffuse-like term ──
    float NdotL1 = max(dot(normal, lightDir1), 0.0);
    float NdotL2 = max(dot(normal, lightDir2), 0.0);
    float NdotL3 = max(dot(normal, lightDir3), 0.0);

    // ── Specular highlights ──
    float3 halfVec1 = normalize(lightDir1 + viewDir);
    float3 halfVec2 = normalize(lightDir2 + viewDir);
    float3 halfVec3 = normalize(lightDir3 + viewDir);

    float spec1 = pow(max(dot(normal, halfVec1), 0.0), 120.0);
    float spec2 = pow(max(dot(normal, halfVec2), 0.0), 80.0);
    float spec3 = pow(max(dot(normal, halfVec3), 0.0), 200.0);

    // ── Fresnel ──
    float NdotV = max(dot(normal, viewDir), 0.0);
    float fres = lg_fresnel(NdotV, F0);

    // ── Build the color ──
    float fieldNorm = smoothstep(0.3, 1.8, field);
    float3 baseColor = mix(goldShadow, goldDeep, smoothstep(0.0, 0.3, fieldNorm));
    baseColor = mix(baseColor, goldBase, smoothstep(0.3, 0.6, fieldNorm));
    baseColor = mix(baseColor, goldBright, smoothstep(0.6, 0.9, fieldNorm));

    // Metallic diffuse
    float3 diffuse = baseColor * (NdotL1 * 0.5 + NdotL2 * 0.3 + NdotL3 * 0.2);

    // Metallic specular
    float3 specColor1 = mix(goldBright, whiteHot, spec1);
    float3 specColor2 = mix(goldBright, whiteHot, spec2 * 0.5);
    float3 specColor3 = mix(goldBright, whiteHot, spec3);

    float3 specular = specColor1 * spec1 * 1.2
                    + specColor2 * spec2 * 0.6
                    + specColor3 * spec3 * 1.5;

    // ── Fake environment reflection ──
    float2 reflUv = normal.xy * 0.5 + 0.5;
    float3 envRefl = mix(
        float3(0.12, 0.07, 0.02),
        float3(0.45, 0.30, 0.12),
        reflUv.y
    );
    envRefl = mix(envRefl, float3(0.7, 0.55, 0.25), smoothstep(0.6, 1.0, reflUv.y));

    // ── Combine lighting ──
    float3 col = diffuse * 0.4 + specular * fres + envRefl * fres * 0.5;

    // ── Ambient ──
    col += baseColor * 0.12;

    // ── Surface tension ripples ──
    float metaGrad = abs(meta - 3.5);
    float tensionLine = smoothstep(0.5, 0.0, metaGrad) * 0.3;
    col += goldBright * tensionLine;

    // ── Subtle ripple highlights ──
    float ripple = lg_noise(uv * 15.0 + t * 2.0);
    ripple = ripple * ripple;
    float rippleHighlight = smoothstep(0.6, 0.9, ripple) * 0.08;
    col += whiteHot * rippleHighlight * fres;

    // ── Radial vignette ──
    float dist = length(uv);
    float vignette = 1.0 - smoothstep(0.3, 1.2, dist);
    col *= 0.35 + vignette * 0.65;

    // ── Central pooling glow ──
    float poolGlow = smoothstep(0.8, 0.0, dist) * 0.15;
    col += goldBright * poolGlow;

    // ── Tone mapping (ACES-like) ──
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

    // ── Slight warmth push ──
    col = pow(col, float3(0.95, 1.0, 1.08));

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(col, 1.0);
}
