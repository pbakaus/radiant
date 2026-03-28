#include "../Common.metal"

// ─── Champagne Fizz: Rising bubbles with highlights and surface line ───
// Ported from static/champagne-fizz.html (Canvas 2D particle system)
// Approach: analytically place bubbles using hash-seeded positions,
// animate rise with wobble, render via SDF circles with specular highlights.

constant float CF_NUM_BUBBLES      = 80.0;
constant float CF_SURFACE_Y        = 0.04;
constant float CF_RISE_SPEED       = 0.08;
constant float CF_WOBBLE_AMP       = 0.02;
constant float CF_WOBBLE_FREQ      = 2.0;
constant float CF_MAX_RADIUS       = 0.018;
constant float CF_MIN_RADIUS       = 0.002;
constant float CF_STREAM_COUNT     = 5.0;
constant float CF_PI               = 3.14159265;

// Hash function for deterministic per-bubble randomness
static float cf_hash(float n) {
    return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

static float2 cf_hash2(float n) {
    return float2(cf_hash(n), cf_hash(n + 57.0));
}

// Single bubble SDF with highlight
static float3 cf_bubble(float2 uv, float2 center, float radius, float age) {
    float d = length(uv - center);
    float3 result = float3(0.0);

    if (d > radius * 3.0) return result;

    // Fade in
    float fadeIn = saturate(age * 3.0);

    // Body: subtle transparent fill
    float body = smoothstep(radius, radius - 0.001, d);
    result += float3(0.784, 0.706, 0.549) * body * 0.08 * fadeIn;

    // Rim: bright edge ring
    float rim = smoothstep(0.001, 0.0, abs(d - radius)) * 0.4;
    result += float3(0.863, 0.745, 0.588) * rim * fadeIn;

    // Specular highlight (upper-left)
    float2 hlOff = float2(-0.25, -0.25) * radius;
    float hlD = length(uv - center + hlOff);
    float hl = smoothstep(radius * 0.65, 0.0, hlD) * 0.6 * fadeIn;
    result += float3(1.0, 0.96, 0.86) * hl * step(d, radius * 0.92);

    // Small specular dot
    float2 specOff = float2(-0.3, -0.35) * radius;
    float specD = length(uv - center + specOff);
    float spec = smoothstep(radius * 0.15, 0.0, specD) * 0.8 * fadeIn;
    result += float3(1.0, 0.99, 0.94) * spec;

    // Bloom glow around bubble
    float glow = smoothstep(radius * 2.5, radius, d) * 0.03 * fadeIn;
    result += float3(0.784, 0.584, 0.424) * glow;

    return result;
}

// Surface wave line
static float cf_surface(float2 uv, float time) {
    float surfY = CF_SURFACE_Y;
    float wave = sin(uv.x * 6.0 + time * 1.2) * 0.002
               + sin(uv.x * 15.0 + time * 0.8) * 0.001
               + sin(uv.x * 3.0 + time * 0.5) * 0.003;
    float lineD = abs(uv.y - surfY - wave);
    return smoothstep(0.002, 0.0, lineD) * 0.15;
}

fragment float4 fs_champagne_fizz(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float aspect = res.x / res.y;
    float2 uvA = float2(uv.x * aspect, uv.y);
    float t = u.time;

    // Background
    float3 col = float3(0.039, 0.039, 0.039);

    // Ambient vertical streams
    for (int i = 0; i < int(CF_STREAM_COUNT); i++) {
        float fi = float(i);
        float sx = (0.15 + 0.7 * (fi / (CF_STREAM_COUNT - 1.0))) * aspect;
        sx += sin(t * 0.3 + fi * 2.1) * 0.02;
        float streamD = abs(uvA.x - sx);
        float streamFade = (1.0 - uv.y); // stronger at bottom
        float stream = smoothstep(0.04, 0.0, streamD) * 0.015 * streamFade;
        col += float3(0.784, 0.584, 0.424) * stream;
    }

    // Bubbles: each has deterministic properties from hash
    for (int i = 0; i < int(CF_NUM_BUBBLES); i++) {
        float fi = float(i);
        float2 rnd = cf_hash2(fi * 73.7);
        float rnd2 = cf_hash(fi * 137.3);
        float rnd3 = cf_hash(fi * 251.1);
        float rnd4 = cf_hash(fi * 419.9);

        // Size distribution: mostly tiny
        float sizeRoll = rnd2;
        float radius;
        if (sizeRoll < 0.55) {
            radius = CF_MIN_RADIUS + rnd3 * 0.003;
        } else if (sizeRoll < 0.85) {
            radius = 0.004 + rnd3 * 0.005;
        } else if (sizeRoll < 0.96) {
            radius = 0.008 + rnd3 * 0.006;
        } else {
            radius = CF_MAX_RADIUS * (0.6 + rnd3 * 0.4);
        }

        // Cycle time for this bubble (they repeat)
        float cycleTime = 6.0 + rnd4 * 8.0;
        float speedMult = 0.7 + rnd4 * 0.6;
        float phaseOffset = rnd.x * cycleTime;
        float localT = fmod(t * speedMult + phaseOffset, cycleTime);
        float age = localT;

        // Rise from bottom to surface
        float progress = localT / cycleTime;
        float baseY = 1.0 + radius - progress * (1.0 + radius - CF_SURFACE_Y);

        // X position: nucleation site + wobble
        float baseX = (0.1 + rnd.x * 0.8) * aspect;
        float wobble = sin(localT * CF_WOBBLE_FREQ * (1.5 + rnd.y * 1.5) + rnd.y * CF_PI * 2.0) * CF_WOBBLE_AMP;

        // Expand slightly as it rises (pressure decrease)
        float heightFrac = 1.0 - (baseY);
        float expandedR = radius * (1.0 + heightFrac * 0.15);

        float2 bubblePos = float2(baseX + wobble, baseY);

        // Only render if above surface and on screen
        if (baseY > CF_SURFACE_Y - expandedR && baseY < 1.0 + expandedR) {
            col += cf_bubble(uvA, bubblePos, expandedR, age);
        }
    }

    // Surface line
    float surfLine = cf_surface(float2(uvA.x, uv.y), t);
    col += float3(0.784, 0.667, 0.510) * surfLine;

    // Surface glow
    float surfGlow = smoothstep(0.03, 0.0, abs(uv.y - CF_SURFACE_Y)) * 0.04;
    col += float3(0.784, 0.667, 0.510) * surfGlow;

    // Vignette
    float2 vc = uv - 0.5;
    float vd = length(vc);
    float vig = smoothstep(0.25, 0.8, vd) * 0.4;
    col *= 1.0 - vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
