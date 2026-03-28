#include "../Common.metal"

// ─── Shattered Plains: Dendritic channel networks carving through warm terrain ───
// Ported from static/shattered-plains.html

constant float SP_PI = 3.14159265359;
constant float SP_CHANNEL_SPEED = 0.5;
constant float SP_CHANNEL_DEPTH = 1.0;
constant float SP_GRAIN = 1.0;

// ── Hash functions ──
static float2 sp_hash2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)),
               dot(p, float2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

static float sp_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Gradient noise ──
static float sp_gnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(dot(sp_hash2(i), f),
                   dot(sp_hash2(i + float2(1.0, 0.0)), f - float2(1.0, 0.0)), u.x),
               mix(dot(sp_hash2(i + float2(0.0, 1.0)), f - float2(0.0, 1.0)),
                   dot(sp_hash2(i + float2(1.0, 1.0)), f - float2(1.0, 1.0)), u.x), u.y);
}

// ── Value noise ──
static float sp_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(sp_hash(i), sp_hash(i + float2(1.0, 0.0)), f.x),
               mix(sp_hash(i + float2(0.0, 1.0)), sp_hash(i + float2(1.0, 1.0)), f.x), f.y);
}

// ── Terrain FBM (3 octaves) ──
static float sp_terrainFBM(float2 p) {
    float v = 0.0, amp = 0.5;
    float2x2 rot = float2x2(float2(0.8, 0.6), float2(-0.6, 0.8));
    for (int i = 0; i < 3; i++) {
        v += amp * sp_vnoise(p);
        amp *= 0.5;
        p = rot * p * 2.0;
    }
    return v;
}

// ── Channel layer: U-shaped valleys ──
static float sp_channelLayer(float2 p, float width, float steepness) {
    float n = sp_gnoise(p);
    float r = smoothstep(0.0, width, abs(n));
    r = pow(r, steepness);
    return r;
}

// ── Full channel system ──
static float sp_channelSystem(float2 p, float t) {
    float2 wp = p + float2(
        sp_gnoise(p * 0.7 + float2(1.7, 9.2) + t * 0.015),
        sp_gnoise(p * 0.7 + float2(8.3, 2.8) + t * 0.012)
    ) * 0.9;
    wp = wp + float2(
        sp_gnoise(wp * 0.7 + float2(5.1, 3.4) + t * 0.01),
        sp_gnoise(wp * 0.7 + float2(2.9, 7.6) + t * 0.008)
    ) * 0.45;

    float main1 = sp_channelLayer(wp * 0.4, 0.16, 0.7);
    float main2 = sp_channelLayer(wp * 0.32 + float2(50.0, 30.0), 0.14, 0.65);
    float mainRivers = min(main1, main2);

    float trib1 = sp_channelLayer(wp * 0.7 + float2(10.0, 20.0), 0.11, 0.8);
    float trib2 = sp_channelLayer(wp * 0.85 + float2(25.0, 45.0), 0.09, 0.9);
    float tributaries = min(trib1, trib2);

    float rill = sp_channelLayer(wp * 1.5 + float2(30.0, 40.0), 0.07, 1.0);

    float combined = min(mainRivers, tributaries * 1.5 + 0.08);
    combined = min(combined, rill * 2.5 + 0.18);

    float depth = (1.0 - smoothstep(0.0, 0.25, combined)) * 0.85;
    return depth;
}

fragment float4 fs_shattered_plains(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.pos.xy;
    float2 p = (fragCoord - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * SP_CHANNEL_SPEED;
    float2 sp = p * 3.5;

    // ── Compute height ──
    float terrain = sp_terrainFBM(sp * 0.5 + float2(100.0, 200.0));
    float channels = sp_channelSystem(sp, t);
    float carve = channels * SP_CHANNEL_DEPTH * 0.45;
    float h = terrain - carve;

    // ── Normals via screen-space derivatives ──
    float3 normal = normalize(float3(-dfdx(h), -dfdy(h), 2.0 / min(u.resolution.x, u.resolution.y) * 4.0));

    // ── Light direction — auto-rotating sun (no mouse) ──
    float sunAng = t * 0.12 + SP_PI * 0.25;
    float sunElev = 0.4 + 0.2 * sin(t * 0.07);
    float3 lightDir = normalize(float3(cos(sunAng), sin(sunAng), sin(sunElev) + 0.3));

    float diff = max(dot(normal, lightDir), 0.0);
    float ambient = 0.22;
    float lighting = ambient + diff * 0.78;
    lighting *= mix(0.55, 1.0, smoothstep(0.0, 0.2, diff));

    float3 halfV = normalize(lightDir + float3(0.0, 0.0, 1.0));
    float spec = pow(max(dot(normal, halfV), 0.0), 20.0);

    // ── Color palette ──
    float3 surfaceHigh  = float3(0.863, 0.686, 0.431);
    float3 surfaceMid   = float3(0.706, 0.510, 0.275);
    float3 shallowChan  = float3(0.549, 0.353, 0.176);
    float3 deepChan     = float3(0.314, 0.196, 0.098);
    float3 waterHint    = float3(0.235, 0.216, 0.196);
    float3 hotHighlight = float3(0.961, 0.843, 0.647);

    // ── Terrain surface color ──
    float3 terrainCol = mix(surfaceMid, surfaceHigh, smoothstep(0.35, 0.65, terrain));
    terrainCol += (sp_vnoise(sp * 8.0) - 0.5) * 0.04;

    // ── Channel depth coloring ──
    float dn = clamp(carve / 0.45, 0.0, 1.0);

    float strata1 = sin(dn * 18.0 + terrain * 4.0) * 0.5 + 0.5;
    float strata2 = sin(dn * 35.0 + terrain * 6.0) * 0.5 + 0.5;
    float strata = mix(strata1, strata2, 0.3);
    strata = smoothstep(0.3, 0.7, strata);

    float3 chanCol = terrainCol;
    chanCol = mix(chanCol, surfaceMid * 0.88, smoothstep(0.0, 0.12, dn));
    float3 shallowBand = mix(shallowChan, surfaceMid * 0.75, strata * 0.5);
    chanCol = mix(chanCol, shallowBand, smoothstep(0.08, 0.3, dn));
    float3 midBand = mix(shallowChan * 0.85, deepChan * 1.2, strata);
    chanCol = mix(chanCol, midBand, smoothstep(0.25, 0.55, dn));
    chanCol = mix(chanCol, deepChan * 1.1, smoothstep(0.5, 0.8, dn));

    // ── Water flow hints ──
    float waterMask = smoothstep(0.75, 0.95, dn);
    float3 waterCol = waterHint;
    float waterSpec = pow(max(dot(normal, halfV), 0.0), 50.0);
    waterCol += float3(0.04, 0.06, 0.12) * waterSpec * 3.0;
    waterCol += float3(0.015, 0.025, 0.05) * (0.5 + 0.5 * sin(t * 0.25));
    chanCol = mix(chanCol, waterCol, waterMask);

    float3 col = mix(terrainCol, chanCol, smoothstep(0.0, 0.08, dn));
    col *= lighting;

    // ── Highlights ──
    float edgeLight = smoothstep(0.55, 0.95, diff) * max(0.0, 1.0 - dn * 1.5);
    col += hotHighlight * spec * 0.15 * max(0.0, 1.0 - dn * 1.2);
    col += hotHighlight * edgeLight * 0.04;

    // ── Grain / sandstone texture ──
    float grainAmt = SP_GRAIN;
    float g1 = sp_hash(fragCoord * 1.0 + fract(u.time * 0.7) * 100.0);
    float g2 = sp_hash(fragCoord * 0.5 + 73.1);
    col += (g1 - 0.5) * 0.03 * grainAmt;
    col += (g2 - 0.5) * 0.02 * grainAmt;
    float sandTex = sp_vnoise(fragCoord * 0.4);
    col += (sandTex - 0.5) * 0.04 * grainAmt * max(0.0, 1.0 - dn * 1.5);
    float streak = sp_vnoise(float2(fragCoord.x * 0.15, fragCoord.y * 0.6) + 50.0);
    col += (streak - 0.5) * 0.025 * grainAmt * smoothstep(0.0, 0.3, dn);

    // Vignette
    float vig = 1.0 - smoothstep(0.65, 1.4, length(p * float2(1.1, 1.0)));
    col *= mix(0.65, 1.0, vig);

    col = clamp(col, float3(0.0), float3(1.0));
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
