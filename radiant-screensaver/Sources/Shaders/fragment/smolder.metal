#include "../Common.metal"

// ─── Smolder: Atmospheric radial heat with turbulence and shimmer ───
// Ported from static/smolder.html

constant float SM_PI = 3.14159265359;
constant float SM_TAU = 6.28318530718;
constant float SM_HEAT = 1.0;
constant float SM_TURBULENCE = 1.0;

// ── Hash functions ──
static float sm_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float2 sm_hash2(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ── Smooth value noise ──
static float sm_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(
        mix(sm_hash(i), sm_hash(i + float2(1.0, 0.0)), f.x),
        mix(sm_hash(i + float2(0.0, 1.0)), sm_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// ── Gradient noise (returns value + analytical derivatives) ──
static float3 sm_noised(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u2 = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    float2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
    float a = sm_hash(i);
    float b = sm_hash(i + float2(1.0, 0.0));
    float c = sm_hash(i + float2(0.0, 1.0));
    float d = sm_hash(i + float2(1.0, 1.0));
    float val = a + (b - a) * u2.x + (c - a) * u2.y + (a - b - c + d) * u2.x * u2.y;
    float2 deriv = du * (float2(b - a + (a - b - c + d) * u2.y, c - a + (a - b - c + d) * u2.x));
    return float3(val, deriv);
}

// ── FBM with rotation between octaves ──
static float sm_fbm(float2 p, int octaves) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        v += a * sm_vnoise(p);
        p = rot * p * 2.05 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

// ── FBM with derivatives for distortion ──
static float3 sm_fbmd(float2 p, int octaves) {
    float v = 0.0, a = 0.5;
    float2 d = float2(0.0);
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        float3 n = sm_noised(p);
        v += a * n.x;
        d += a * n.yz;
        p = rot * p * 2.05 + float2(1.7, 9.2);
        a *= 0.5;
    }
    return float3(v, d);
}

// ── Ridged noise for veins ──
static float sm_ridged(float2 p, int octaves) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        float n = sm_vnoise(p);
        n = 1.0 - abs(n * 2.0 - 1.0);
        n = n * n;
        v += a * n;
        p = rot * p * 2.1 + float2(3.2, 1.3);
        a *= 0.5;
    }
    return v;
}

// ── Temperature color mapping ──
static float3 sm_tempColor(float temp, float luminosityVar) {
    float3 c0 = float3(0.04, 0.04, 0.055);
    float3 c1 = float3(0.08, 0.09, 0.14);
    float3 c2 = float3(0.18, 0.12, 0.10);
    float3 c3 = float3(0.70, 0.28, 0.10);
    float3 c4 = float3(1.2, 0.55, 0.14);
    float3 c5 = float3(1.8, 1.0, 0.25);
    float3 c6 = float3(2.5, 1.6, 0.6);
    float3 c7 = float3(3.5, 3.0, 2.5);

    float3 col;
    if (temp < 0.12) {
        col = mix(c0, c1, temp / 0.12);
    } else if (temp < 0.25) {
        col = mix(c1, c2, (temp - 0.12) / 0.13);
    } else if (temp < 0.38) {
        col = mix(c2, c3, (temp - 0.25) / 0.13);
    } else if (temp < 0.52) {
        col = mix(c3, c4, (temp - 0.38) / 0.14);
    } else if (temp < 0.68) {
        col = mix(c4, c5, (temp - 0.52) / 0.16);
    } else if (temp < 0.85) {
        col = mix(c5, c6, (temp - 0.68) / 0.17);
    } else {
        col = mix(c6, c7, (temp - 0.85) / 0.15);
    }

    col *= 1.0 + luminosityVar * 0.25;

    return col;
}

fragment float4 fs_smolder(VSOut in [[stage_in]],
                            constant CommonUniforms& u [[buffer(0)]]) {
    // Default center and scale (no embed overrides in screensaver)
    float2 origin = float2(0.5);
    float sc = 1.0;
    float2 uv = (in.pos.xy - u.resolution * origin) / (min(u.resolution.x, u.resolution.y) * sc);
    float t = u.time;
    float heat = SM_HEAT;
    float turb = SM_TURBULENCE;

    float dist = length(uv);

    // No mouse heat source in screensaver mode

    // ── Layer 1: Base temperature field ──
    float angle = atan2(uv.y, uv.x);
    float ca = cos(angle);
    float sa = sin(angle);

    // Large-scale turbulence
    float turb1 = sm_fbm(float2(ca * 1.5 + sa * 0.7 + t * 0.08, dist * 2.0 - t * 0.05) * 1.8, 5) * turb;

    // Medium-scale turbulence
    float turb2 = sm_fbm(float2(ca * 3.0 - sa * 1.5 - t * 0.12, dist * 3.5 + t * 0.07) * 2.5 + float2(50.0, 30.0), 4) * turb;

    // Fine-scale turbulence
    float turb3 = sm_fbm(float2(ca * 5.0 + sa * 2.5 + t * 0.2, dist * 5.0 - t * 0.15) * 3.0 + float2(100.0, 70.0), 3) * turb;

    float turbTotal = turb1 * 0.45 + turb2 * 0.35 + turb3 * 0.2;

    float deformStrength = smoothstep(0.0, 0.3, dist) * smoothstep(0.9, 0.4, dist);
    float deformedDist = dist + (turbTotal - 0.5) * 0.35 * deformStrength;

    float pulse = sin(t * 0.15) * 0.04 + sin(t * 0.23 + 1.7) * 0.03 + sin(t * 0.37 + 3.1) * 0.02;
    deformedDist -= pulse * heat;

    float tempRange = 0.65 / heat;
    float temp = 1.0 - smoothstep(0.0, tempRange, deformedDist);
    float coreBoost = (1.0 - smoothstep(0.0, 0.15 / heat, deformedDist));
    temp = temp * 0.7 + coreBoost * 0.3;
    temp = clamp(temp, 0.0, 1.0);

    // ── Layer 2: Color mapping with luminosity variation ──
    float lumVar = sm_fbm(uv * 4.0 + t * 0.06, 3) * 2.0 - 1.0;

    float3 col = sm_tempColor(temp, lumVar);

    // ── Layer 3: Heat shimmer ──
    float3 shimmerNoise = sm_fbmd(uv * 8.0 + float2(t * 0.3, t * 0.25), 4);
    float shimmerWave = shimmerNoise.x;
    float2 shimmerDir = shimmerNoise.yz;

    float shimmerStrength = temp * temp * turb;
    float shimmerRipple = dot(shimmerDir, float2(0.7, 0.7));
    shimmerRipple = shimmerRipple * shimmerRipple * shimmerStrength;
    col += col * shimmerRipple * 0.4;

    float shimmerHighlight = pow(max(shimmerWave, 0.0), 4.0) * temp * temp;
    col += float3(1.0, 0.8, 0.4) * shimmerHighlight * 0.2 * heat;

    // ── Layer 4: Turbulent veins ──
    float veins1 = sm_ridged(uv * 5.0 + float2(t * 0.06, -t * 0.04), 4);
    float veins2 = sm_ridged(uv * 8.0 + float2(-t * 0.08, t * 0.05) + float2(20.0, 40.0), 3);
    float veins3 = sm_ridged(uv * 13.0 + float2(t * 0.1, t * 0.07) + float2(60.0, 90.0), 2);

    float veins = veins1 * 0.5 + veins2 * 0.35 + veins3 * 0.15;

    veins = smoothstep(0.3, 0.75, veins);
    veins = pow(veins, 2.0);

    float veinMask = smoothstep(0.15, 0.5, temp) * smoothstep(1.0, 0.7, temp);
    float veinIntensity = veins * veinMask * 0.7 * heat;

    float3 veinColor = float3(1.0, 0.72, 0.22);
    veinColor = mix(veinColor, float3(1.0, 0.58, 0.15), veins2);
    col += veinColor * veinIntensity;

    // ── Layer 5: Ember particles ──
    float emberScale = 18.0;
    float2 emberUV = uv * emberScale;
    emberUV.y -= t * 0.4;
    emberUV.x += sin(t * 0.3 + uv.y * 4.0) * 0.15;

    float2 emberId = floor(emberUV);
    float2 emberF = fract(emberUV) - 0.5;

    float embers = 0.0;
    for (int ey = -1; ey <= 1; ey++) {
        for (int ex = -1; ex <= 1; ex++) {
            float2 neighbor = float2(float(ex), float(ey));
            float2 cellId = emberId + neighbor;
            float2 rnd = sm_hash2(cellId);

            if (rnd.x > 0.08) continue;

            float2 emberPos = neighbor + rnd - 0.5;
            float emberDist = length(emberF - emberPos);

            float phase = sm_hash(cellId + float2(77.0, 33.0));
            float life = fract(phase + t * 0.08);
            float brightness = sin(life * SM_PI) * sin(life * SM_PI);
            brightness *= 0.5 + 0.5 * sin(t * 5.0 + phase * SM_TAU);

            float glow = smoothstep(0.08, 0.0, emberDist);
            float core = smoothstep(0.025, 0.0, emberDist) * 2.0;

            embers += (glow + core) * brightness;
        }
    }

    float emberTemp = temp;
    float emberMask = smoothstep(0.2, 0.5, emberTemp);
    embers *= emberMask;

    float3 emberColor = float3(1.0, 0.85, 0.5);
    col += emberColor * embers * 0.12 * heat;

    // ── Layer 6: Film grain ──
    float grainSeed = sm_hash(in.pos.xy + fract(t * 43.758) * 1000.0);
    float grain = (grainSeed - 0.5);

    float transitionMask = smoothstep(0.1, 0.35, temp) * smoothstep(0.7, 0.35, temp);
    float grainStrength = 0.012 + transitionMask * 0.018;

    float3 grainColor = float3(grain * 1.1, grain * 0.95, grain * 0.75);
    col += grainColor * grainStrength;

    // ── Final adjustments ──
    float vig = length(uv * 1.1);
    float vignette = 1.0 - smoothstep(0.5, 1.3, vig) * 0.3;
    col *= vignette;

    // ACES filmic tone mapping
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

    col = max(col, float3(0.0));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
