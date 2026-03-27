#include "../Common.metal"

// ─── Magma Core: Unified lava lake fragment shader ───
// Ported from static/magma-core.html

constant float MC_INTENSITY = 1.0;
constant float MC_CRUST_AMOUNT = 1.0;

// ── Hash & noise primitives ──
static float mc_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float2 mc_hash2(float2 p) {
    return float2(
        fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453),
        fract(sin(dot(p, float2(269.5, 183.3))) * 43758.5453)
    );
}

// Smooth value noise
static float mc_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = mc_hash(i);
    float b = mc_hash(i + float2(1.0, 0.0));
    float c = mc_hash(i + float2(0.0, 1.0));
    float d = mc_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// FBM
static float mc_fbm(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 8; i++) {
        if (i >= octaves) break;
        val += amp * mc_noise(p * freq);
        freq *= 2.03;
        amp *= 0.49;
        p += float2(1.7, 9.2);
    }
    return val;
}

// Ridged noise
static float mc_ridgedNoise(float2 p) {
    return 1.0 - abs(mc_noise(p) * 2.0 - 1.0);
}

// Ridged FBM for crack networks
static float mc_ridgedFBM(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    float prev = 1.0;
    for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        float n = mc_ridgedNoise(p * freq);
        n = n * n;
        val += n * amp * prev;
        prev = n;
        freq *= 2.2;
        amp *= 0.5;
        p += float2(1.3, 7.1);
    }
    return val;
}

// Voronoi for crust plate boundaries
static float mc_voronoi(float2 p, thread float2& cellCenter) {
    float2 i = floor(p);
    float2 f = fract(p);
    float minDist = 1.0;
    float secondDist = 1.0;
    cellCenter = float2(0.0);
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 neighbor = float2(float(x), float(y));
            float2 point = mc_hash2(i + neighbor);
            float2 diff = neighbor + point - f;
            float d = dot(diff, diff);
            if (d < minDist) {
                secondDist = minDist;
                minDist = d;
                cellCenter = i + neighbor + point;
            } else if (d < secondDist) {
                secondDist = d;
            }
        }
    }
    return sqrt(secondDist) - sqrt(minDist);
}

// Domain warping for fluid magma motion
static float2 mc_warpDomain(float2 p, float t) {
    float2 q = float2(
        mc_fbm(p + float2(0.0, 0.0) + t * float2(0.12, -0.08), 5),
        mc_fbm(p + float2(5.2, 1.3) + t * float2(-0.09, 0.14), 5)
    );
    float2 r = float2(
        mc_fbm(p + 3.5 * q + float2(1.7, 9.2) + t * float2(0.06, 0.05), 5),
        mc_fbm(p + 3.5 * q + float2(8.3, 2.8) + t * float2(-0.07, 0.08), 5)
    );
    return p + 2.5 * r;
}

// Thermal color mapping
static float3 mc_magmaColor(float temp) {
    float3 c;
    if (temp < 0.15) {
        float t = temp / 0.15;
        c = mix(float3(0.02, 0.005, 0.0), float3(0.15, 0.02, 0.005), t);
    } else if (temp < 0.35) {
        float t = (temp - 0.15) / 0.2;
        c = mix(float3(0.15, 0.02, 0.005), float3(0.55, 0.08, 0.01), t * t);
    } else if (temp < 0.55) {
        float t = (temp - 0.35) / 0.2;
        c = mix(float3(0.55, 0.08, 0.01), float3(0.9, 0.3, 0.02), t);
    } else if (temp < 0.72) {
        float t = (temp - 0.55) / 0.17;
        c = mix(float3(0.9, 0.3, 0.02), float3(1.0, 0.65, 0.08), t);
    } else if (temp < 0.88) {
        float t = (temp - 0.72) / 0.16;
        c = mix(float3(1.0, 0.65, 0.08), float3(1.0, 0.9, 0.4), t);
    } else {
        float t = (temp - 0.88) / 0.12;
        c = mix(float3(1.0, 0.9, 0.4), float3(1.0, 1.0, 0.85), t);
    }
    return c;
}

fragment float4 fs_magma_core(VSOut in [[stage_in]],
                              constant CommonUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.pos.xy;
    float2 p = (fragCoord - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;

    // Scale for the magma surface
    float2 magmaUV = p * 3.0;

    // 1. Base convection flow
    float2 warped = mc_warpDomain(magmaUV, t * 0.4);
    float baseFlow = mc_fbm(warped, 7);

    float2 warped2 = mc_warpDomain(magmaUV * 1.3 + float2(50.0), t * 0.35);
    float flow2 = mc_fbm(warped2, 6);

    float convection = baseFlow * 0.6 + flow2 * 0.4;

    // 2. Crust formation from Voronoi cells
    float2 crustUV = magmaUV * 0.8 + t * float2(0.03, -0.02);
    crustUV += float2(baseFlow, flow2) * 0.6;

    float2 cellCenter;
    float crustEdge = mc_voronoi(crustUV, cellCenter);

    float2 cellCenter2;
    float subCracks = mc_voronoi(crustUV * 2.5 + float2(30.0), cellCenter2);

    // 3. Temperature field
    float temp = convection;

    float crackGlow = smoothstep(0.12 * MC_CRUST_AMOUNT, 0.0, crustEdge);
    float subCrackGlow = smoothstep(0.08 * MC_CRUST_AMOUNT, 0.0, subCracks) * 0.4;

    float crustMask = smoothstep(0.0, 0.15 * MC_CRUST_AMOUNT, crustEdge);
    float cellCool = mc_hash(floor(cellCenter * 100.0)) * 0.3 + 0.5;
    float crustCooling = crustMask * cellCool * MC_CRUST_AMOUNT;

    temp = temp - crustCooling * 0.6;
    temp = max(temp, crackGlow * 0.85);
    temp = max(temp, subCrackGlow * 0.5 + temp * 0.5);

    // 4. Hot spots
    float hotSpotNoise = mc_fbm(magmaUV * 0.5 + t * float2(0.08, -0.06), 4);
    float hotSpots = smoothstep(0.55, 0.85, hotSpotNoise);
    temp += hotSpots * 0.35 * MC_INTENSITY;

    float breathe = sin(t * 0.6) * 0.5 + 0.5;
    float breathe2 = sin(t * 0.37 + 2.0) * 0.5 + 0.5;
    temp += breathe * 0.08 + breathe2 * 0.05;

    // 5. Ridged detail
    float veins = mc_ridgedFBM(warped * 1.5 + t * 0.1, 5);
    float veinMask = smoothstep(0.2, 0.4, temp) * smoothstep(0.8, 0.5, temp);
    temp += veins * veinMask * 0.15;

    // 6. Localized brightening events
    float flareNoise = mc_noise(magmaUV * 1.2 + t * float2(0.3, -0.2));
    float flare = pow(max(flareNoise - 0.65, 0.0) / 0.35, 3.0);
    temp += flare * 0.25 * MC_INTENSITY;

    // Clamp temperature
    temp = clamp(temp * MC_INTENSITY, 0.0, 1.0);

    // 7. Convert temperature to color
    float3 col = mc_magmaColor(temp);

    // 8. Emissive glow
    float glow = smoothstep(0.6, 1.0, temp);
    col += float3(0.3, 0.08, 0.01) * glow * glow * 0.5;

    // 9. Crust surface texture
    float crustDetail = mc_fbm(magmaUV * 8.0 + float2(cellCool * 20.0), 4);
    col *= mix(1.0, 0.7 + crustDetail * 0.3, crustMask * MC_CRUST_AMOUNT * 0.5);

    // 10. Heat haze
    float hazeN = mc_fbm(p * 2.0 + t * float2(0.15, 0.4), 3);
    float hazeStrength = smoothstep(0.5, 1.0, temp) * 0.08;
    col += float3(0.15, 0.04, 0.0) * hazeN * hazeStrength;

    // 11. Edge cooling
    float edgeDist = length(p * float2(1.0, 1.3));
    float edgeFade = smoothstep(0.7, 1.4, edgeDist);
    float edgeCool = edgeFade * 0.3;
    col = mix(col, col * float3(0.3, 0.1, 0.08), edgeCool);

    // 12. Vignette
    float vignette = 1.0 - smoothstep(0.5, 1.5, edgeDist);
    col *= 0.65 + vignette * 0.35;

    // 13. Tone mapping
    col = col / (1.0 + col * 0.15);

    // 14. Color grading
    col = pow(col, float3(0.95, 1.0, 1.1));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
