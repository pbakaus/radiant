#include "../Common.metal"

// ─── Laser Labyrinth: Volumetric light cones through fog ───
// Ported from static/laser-labyrinth.html

constant float LL_PI = 3.14159265359;

// Default parameter values
constant float LL_SWEEP_SPEED = 0.5;
constant float LL_BEAM_INTENSITY = 1.0;

// ── Hash & noise for fog ──
static float ll_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float ll_hash3(float3 p) {
    return fract(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453);
}

// ── 3D value noise ──
static float ll_noise3d(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = ll_hash3(i);
    float n100 = ll_hash3(i + float3(1.0, 0.0, 0.0));
    float n010 = ll_hash3(i + float3(0.0, 1.0, 0.0));
    float n110 = ll_hash3(i + float3(1.0, 1.0, 0.0));
    float n001 = ll_hash3(i + float3(0.0, 0.0, 1.0));
    float n101 = ll_hash3(i + float3(1.0, 0.0, 1.0));
    float n011 = ll_hash3(i + float3(0.0, 1.0, 1.0));
    float n111 = ll_hash3(i + float3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    float nxy0 = mix(nx00, nx10, f.y);
    float nxy1 = mix(nx01, nx11, f.y);
    return mix(nxy0, nxy1, f.z);
}

// ── FBM (4 octaves) ──
static float ll_fbm(float3 p) {
    float v = 0.0;
    float a = 0.5;
    float3 shift = float3(100.0);
    for (int i = 0; i < 4; i++) {
        v += a * ll_noise3d(p);
        p = p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ── Color palette with hue rotation ──
static float3 ll_coneColor(int idx, float hueShiftVal) {
    float3 col;
    if (idx == 0) col = float3(1.0, 0.0, 0.5);        // hot magenta
    else if (idx == 1) col = float3(0.5, 0.05, 1.0);   // electric violet
    else if (idx == 2) col = float3(0.1, 0.35, 1.0);   // cool blue
    else if (idx == 3) col = float3(0.85, 0.0, 0.85);  // pure magenta
    else if (idx == 4) col = float3(0.15, 0.2, 1.0);   // deep blue
    else col = float3(0.0, 0.8, 0.95);                  // cyan accent

    // Apply slow hue rotation
    float angle = hueShiftVal;
    float cosA = cos(angle);
    float sinA = sin(angle);
    // Approximate hue rotation via luminance-preserving rotation
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    float3 grey = float3(lum);
    float3 diff = col - grey;
    float3 axis1 = normalize(float3(1.0, -1.0, 0.0));
    float3 axis2 = normalize(float3(0.5, 0.5, -1.0));
    float d1 = dot(diff, axis1);
    float d2 = dot(diff, axis2);
    float3 rotated = grey + axis1 * (d1 * cosA - d2 * sinA) + axis2 * (d1 * sinA + d2 * cosA);
    return clamp(rotated, 0.0, 1.0);
}

fragment float4 fs_laser_labyrinth(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    // UV: 0..1 range
    float2 fragUV = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    float2 uv = fragUV;
    uv.x = (uv.x - 0.5) * aspect;  // centered horizontally, aspect corrected

    float t = u.time * LL_SWEEP_SPEED;
    float intensity = LL_BEAM_INTENSITY;

    // No mouse in screensaver mode

    // ── Fog base: 3D FBM noise drifting slowly ──
    float3 fogCoord = float3(fragUV * 3.0, t * 0.08);
    fogCoord.y -= t * 0.03;
    fogCoord.x += t * 0.015;
    float fogDensity = ll_fbm(fogCoord);

    // Second fog layer for more detail
    float3 fogCoord2 = float3(fragUV * 6.0 + 50.0, t * 0.12);
    fogCoord2.y -= t * 0.05;
    float fogDetail = ll_fbm(fogCoord2);
    float fog = fogDensity * 0.5 + fogDetail * 0.5;
    fog = fog * fog * 1.5;

    // ── Accumulate light from all cones ──
    float3 col = float3(0.0);

    // Bounded hue oscillation
    float hueShift = sin(t * 0.07) * 0.2;

    // Global beat pulse
    float globalBeat = pow(abs(sin(t * LL_PI / 1.5)), 8.0) * 0.2;

    // ── Far layer: 3 cones (indices 0-2) ──
    for (int i = 0; i < 3; i++) {
        float fi = float(i);

        // Origin spread along top edge
        float originX = (fi - 1.0) * 0.4 * aspect;
        originX += sin(t * 0.07 + fi * 2.5) * 0.1 * aspect;
        float2 origin = float2(originX, 1.05);

        // Sweep angle
        float sweepAmp = 0.4 + fi * 0.1;
        float sweepFreq = 0.3 + fi * 0.11;
        float theta = sin(t * sweepFreq * 0.7 + fi * 1.9) * sweepAmp;

        // Direction of cone center
        float2 dir = float2(sin(theta), -cos(theta));

        // No mouse attraction in screensaver mode

        // Vector from origin to current pixel
        float2 toPixel = uv - origin;

        // Project onto cone axis
        float along = dot(toPixel, dir);

        // Perpendicular distance from cone axis
        float perp = abs(toPixel.x * dir.y - toPixel.y * dir.x);

        // Wide cone for far layer
        float halfWidth = 0.13 + fi * 0.015;
        float coneWidth = halfWidth * max(along, 0.0) + 0.012;

        // Soft gaussian falloff from center
        float inCone = exp(-perp * perp / (coneWidth * coneWidth * 0.55));

        // Only illuminate in front of origin
        inCone *= smoothstep(0.0, 0.08, along);

        // Distance falloff
        inCone *= exp(-along * along * 0.15);

        // Fog modulation
        float fogMod = 0.25 + fog * 0.75;
        float volumetric = inCone * fogMod;

        // Far layer: reduced brightness
        float farOpacity = 0.35;

        float3 coneCol = ll_coneColor(i, hueShift + fi * 0.15);
        col += coneCol * volumetric * farOpacity * intensity * (1.0 + globalBeat);
    }

    // ── Near layer: 3 cones (indices 3-5) ──
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        int colorIdx = i + 3;

        // Origin spread along top edge, offset from far layer
        float originX = (fi - 1.0) * 0.5 * aspect + 0.15 * aspect;
        originX += sin(t * 0.1 + fi * 3.1 + 1.0) * 0.08 * aspect;
        float2 origin = float2(originX, 1.02);

        // Sweep angle + beat snaps
        float sweepAmp = 0.5 + fi * 0.08;
        float sweepFreq = 0.4 + fi * 0.13;
        float theta = sin(t * sweepFreq + fi * 2.3 + 0.7) * sweepAmp;

        // Beat snap
        float beatFreq = 1.8 + fi * 0.4;
        float snap = pow(abs(sin(t * beatFreq)), 6.0);
        float snapGate = smoothstep(0.5, 0.85, sin(t * 0.7 + fi * 2.094));
        theta += snap * snapGate * 0.18 * sin(t * beatFreq * 0.5);

        float2 dir = float2(sin(theta), -cos(theta));

        // No mouse attraction in screensaver mode

        float2 toPixel = uv - origin;
        float along = dot(toPixel, dir);
        float perp = abs(toPixel.x * dir.y - toPixel.y * dir.x);

        // Wider cone
        float halfWidth = 0.11 + fi * 0.012;
        float coneWidth = halfWidth * max(along, 0.0) + 0.01;

        // Gaussian falloff with bright core
        float inCone = exp(-perp * perp / (coneWidth * coneWidth * 0.4));
        float coreLine = exp(-perp * perp / (coneWidth * coneWidth * 0.04));
        inCone = inCone + coreLine * 0.4;
        inCone *= smoothstep(0.0, 0.06, along);
        inCone *= exp(-along * along * 0.1);

        // Fog modulation
        float fogMod = 0.2 + fog * 0.8;
        float volumetric = inCone * fogMod;

        // Near layer: bright
        float nearOpacity = 0.75;

        float3 coneCol = ll_coneColor(colorIdx, hueShift + fi * 0.15 + 0.5);
        col += coneCol * volumetric * nearOpacity * intensity * (1.0 + globalBeat);
    }

    // ── Intersection bloom ──
    float brightness = dot(col, float3(0.299, 0.587, 0.114));
    float whiteBlend = smoothstep(0.4, 1.2, brightness);
    col = mix(col, float3(brightness * 1.3), whiteBlend * 0.5);

    // ── Ground haze ──
    float groundHaze = smoothstep(0.2, 0.0, fragUV.y);
    float hazeFog = ll_fbm(float3(fragUV.x * 4.0, fragUV.y * 2.0, t * 0.05 + 10.0));
    col += col * groundHaze * 0.3;
    col += float3(0.06, 0.03, 0.1) * groundHaze * hazeFog * intensity;

    // ── Exponential tone mapping ──
    float exposure = 2.0;
    col = 1.0 - exp(-col * exposure);

    // ── Film grain ──
    float grain = ll_hash(in.pos.xy + fract(u.time) * 100.0) * 0.04 - 0.02;
    col += grain;

    // ── Vignette ──
    float2 vigUV = fragUV - 0.5;
    float vigDist = dot(vigUV, vigUV);
    float vig = 1.0 - vigDist * 0.8;
    vig = clamp(vig, 0.0, 1.0);
    col *= vig;

    col = clamp(col, 0.0, 1.0);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
