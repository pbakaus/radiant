#include "../Common.metal"

// ─── Neon Revival: Glowing neon tube art installation ───
// Ported from static/neon-revival.html
// Inspired by Doja Cat — hot pink, electric blue, warm amber
// Uses shape 1 (Crown) as default for screensaver (no shape switching)

// Default parameter values (screensaver — no interactive controls)
constant float NR_GLOW_INTENSITY = 1.0;
constant float NR_FLICKER_RATE = 0.5;
constant float NR_SHAPE = 1.0;  // Crown shape

constant float NR_PI = 3.14159265359;
constant float NR_TAU = 6.28318530718;

// ── Hash / noise ──
static float nr_hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static float nr_hash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float nr_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = nr_hash2(i);
    float b = nr_hash2(i + float2(1.0, 0.0));
    float c = nr_hash2(i + float2(0.0, 1.0));
    float d = nr_hash2(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── SDF primitives ──
static float nr_sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

static float nr_sdCircle(float2 p, float2 center, float radius) {
    return abs(length(p - center) - radius);
}

static float nr_sdArc(float2 p, float2 center, float radius, float startAngle, float sweep) {
    float2 d = p - center;
    float angle = atan2(d.y, d.x);
    // Safe mod for potentially negative angle
    float a = angle - startAngle + NR_PI;
    a = a - NR_TAU * floor(a / NR_TAU);
    a -= NR_PI;
    if (a >= 0.0 && a <= sweep) {
        return abs(length(d) - radius);
    }
    float2 e1 = center + radius * float2(cos(startAngle), sin(startAngle));
    float2 e2 = center + radius * float2(cos(startAngle + sweep), sin(startAngle + sweep));
    return min(length(p - e1), length(p - e2));
}

static float nr_sdTriangle(float2 p, float2 a, float2 b, float2 c) {
    float d1 = nr_sdSegment(p, a, b);
    float d2 = nr_sdSegment(p, b, c);
    float d3 = nr_sdSegment(p, c, a);
    return min(min(d1, d2), d3);
}

static float nr_sdRoundRect(float2 p, float2 center, float2 halfSize, float radius) {
    float2 d = abs(p - center) - halfSize + radius;
    return abs(length(max(d, float2(0.0))) + min(max(d.x, d.y), 0.0) - radius);
}

static float nr_sdHeart(float2 p, float2 center, float size) {
    float2 q = (p - center) / size;
    q.y -= 0.2;
    float a1 = nr_sdArc(q, float2(-0.28, 0.18), 0.36, 0.3, NR_PI);
    float a2 = nr_sdArc(q, float2(0.28, 0.18), 0.36, -0.15, NR_PI);
    float v1 = nr_sdSegment(q, float2(-0.56, -0.02), float2(0.0, -0.65));
    float v2 = nr_sdSegment(q, float2(0.56, -0.02), float2(0.0, -0.65));
    return min(min(a1, a2), min(v1, v2)) * size;
}

static float nr_sdStar(float2 p, float2 center, float outerR, float innerR) {
    float d = 1e10;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float a1 = fi * NR_TAU / 5.0 - NR_PI / 2.0;
        float a2 = (fi + 0.5) * NR_TAU / 5.0 - NR_PI / 2.0;
        float a3 = (fi + 1.0) * NR_TAU / 5.0 - NR_PI / 2.0;
        float2 outer1 = center + outerR * float2(cos(a1), sin(a1));
        float2 inner1 = center + innerR * float2(cos(a2), sin(a2));
        float2 outer2 = center + outerR * float2(cos(a3), sin(a3));
        d = min(d, nr_sdSegment(p, outer1, inner1));
        d = min(d, nr_sdSegment(p, inner1, outer2));
    }
    return d;
}

static float nr_sdDiamond(float2 p, float2 center, float2 halfSize) {
    float2 a = center + float2(0.0, halfSize.y);
    float2 b = center + float2(halfSize.x, 0.0);
    float2 c = center + float2(0.0, -halfSize.y);
    float2 dd = center + float2(-halfSize.x, 0.0);
    float d1 = nr_sdSegment(p, a, b);
    float d2 = nr_sdSegment(p, b, c);
    float d3 = nr_sdSegment(p, c, dd);
    float d4 = nr_sdSegment(p, dd, a);
    return min(min(d1, d2), min(d3, d4));
}

// ── Neon glow rendering ──
static float3 nr_neonGlow(float dist, float3 color, float tubeWidth, float brightness) {
    float core = exp(-dist * dist / (tubeWidth * tubeWidth * 0.3));
    float inner = exp(-dist * dist / (tubeWidth * tubeWidth * 2.5));
    float mid = exp(-dist * dist / (tubeWidth * tubeWidth * 12.0));
    float bloom = exp(-dist * dist / (tubeWidth * tubeWidth * 50.0));
    float scatter = exp(-dist * dist / (tubeWidth * tubeWidth * 200.0));

    float3 white = float3(1.0, 0.97, 0.95);
    float3 result = white * core * 1.5;
    result += mix(white, color, 0.5) * inner * 1.0;
    result += color * mid * 0.6;
    result += color * bloom * 0.25;
    result += color * scatter * 0.08;

    return result * brightness;
}

// ── Flicker function ──
static float nr_flicker(float t, float id, float rate) {
    float phase = nr_hash(id * 13.37) * NR_TAU;
    float speed = 3.0 + nr_hash(id * 7.91) * 8.0;
    float cutout = step(0.92 - rate * 0.15, sin(t * speed * 2.3 + phase * 1.7));
    float dim = 1.0 - cutout * 0.7;

    float buzz = 0.97 + 0.03 * sin(t * 376.99);
    float pulse = 0.92 + 0.08 * sin(t * 0.5 + phase);

    return pulse * buzz * dim;
}

// ── Fade-in animation ──
static float nr_fadeIn(float t, float delay, float duration) {
    return smoothstep(delay, delay + duration, t);
}

fragment float4 fs_neon_revival(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;

    // Tube thickness
    float tw = 0.012;

    // Dark background with subtle texture
    float3 col = float3(0.02, 0.018, 0.025);
    float brickNoise = nr_noise(in.pos.xy * 0.15) * 0.015;
    float brickY = step(0.95, fract(uv.y * 12.0)) * 0.008;
    float brickX = step(0.95, fract((uv.x + step(0.5, fract(uv.y * 6.0)) * 0.04) * 8.0)) * 0.006;
    col += brickNoise - brickY - brickX;

    // Neon colors
    float3 hotPink = float3(1.0, 0.08, 0.45);
    float3 electricBlue = float3(0.1, 0.5, 1.0);
    float3 warmAmber = float3(1.0, 0.65, 0.15);
    float3 softPink = float3(1.0, 0.35, 0.55);

    float3 neon = float3(0.0);
    float dist;
    float fl;
    float fi;

    // ═══════════════════════════════════════
    // SHAPE 1: "Crown" — default for screensaver
    // ═══════════════════════════════════════

    // Horizontal band across crown base
    fi = 41.0;
    dist = nr_sdSegment(uv, float2(-0.32, -0.05), float2(0.32, -0.05));
    fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 0.2, 1.5);
    neon += nr_neonGlow(dist, warmAmber, tw, fl * NR_GLOW_INTENSITY);

    // Center peak (tallest)
    fi = 42.0;
    dist = nr_sdTriangle(uv, float2(-0.06, -0.05), float2(0.0, 0.32), float2(0.06, -0.05));
    fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 0.4, 1.4);
    neon += nr_neonGlow(dist, hotPink, tw, fl * NR_GLOW_INTENSITY * 1.05);

    // Inner left peak
    fi = 43.0;
    dist = nr_sdTriangle(uv, float2(-0.18, -0.05), float2(-0.12, 0.18), float2(-0.06, -0.05));
    fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 0.55, 1.4);
    neon += nr_neonGlow(dist, hotPink, tw, fl * NR_GLOW_INTENSITY);

    // Inner right peak
    fi = 44.0;
    dist = nr_sdTriangle(uv, float2(0.06, -0.05), float2(0.12, 0.18), float2(0.18, -0.05));
    fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 0.6, 1.4);
    neon += nr_neonGlow(dist, hotPink, tw, fl * NR_GLOW_INTENSITY);

    // Outer left peak
    fi = 45.0;
    dist = nr_sdTriangle(uv, float2(-0.32, -0.05), float2(-0.25, 0.12), float2(-0.18, -0.05));
    fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 0.7, 1.4);
    neon += nr_neonGlow(dist, softPink, tw, fl * NR_GLOW_INTENSITY * 0.9);

    // Outer right peak
    fi = 46.0;
    dist = nr_sdTriangle(uv, float2(0.18, -0.05), float2(0.25, 0.12), float2(0.32, -0.05));
    fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 0.75, 1.4);
    neon += nr_neonGlow(dist, softPink, tw, fl * NR_GLOW_INTENSITY * 0.9);

    // Jewel circles at each peak tip
    fi = 47.0;
    {
        float jp = 0.8 + 0.2 * sin(t * 1.9);
        float dj1 = nr_sdCircle(uv, float2(0.0, 0.32), 0.018);
        float dj2 = nr_sdCircle(uv, float2(-0.12, 0.18), 0.018);
        float dj3 = nr_sdCircle(uv, float2(0.12, 0.18), 0.018);
        float dj4 = nr_sdCircle(uv, float2(-0.25, 0.12), 0.018);
        float dj5 = nr_sdCircle(uv, float2(0.25, 0.12), 0.018);
        dist = min(min(min(dj1, dj2), min(dj3, dj4)), dj5);
        fl = nr_flicker(t, fi, NR_FLICKER_RATE * 0.5) * nr_fadeIn(t, 1.2, 1.0) * jp;
        neon += nr_neonGlow(dist, warmAmber, tw * 0.65, fl * NR_GLOW_INTENSITY * 1.15);
    }

    // Left accent star
    fi = 48.0;
    {
        float sp = 0.85 + 0.15 * sin(t * 1.7);
        dist = nr_sdStar(uv, float2(-0.50, 0.05), 0.06, 0.025);
        fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 1.0, 1.2) * sp;
        neon += nr_neonGlow(dist, electricBlue, tw * 0.85, fl * NR_GLOW_INTENSITY);
    }

    // Right accent star
    fi = 49.0;
    {
        float sp2 = 0.85 + 0.15 * sin(t * 1.7 + 1.2);
        dist = nr_sdStar(uv, float2(0.50, 0.05), 0.06, 0.025);
        fl = nr_flicker(t, fi, NR_FLICKER_RATE) * nr_fadeIn(t, 1.1, 1.2) * sp2;
        neon += nr_neonGlow(dist, electricBlue, tw * 0.85, fl * NR_GLOW_INTENSITY);
    }

    // Reflection
    {
        float reflY = -0.14;
        if (uv.y < reflY) {
            float2 rUV = float2(uv.x, 2.0 * reflY - uv.y);
            float reflDist = reflY - uv.y;
            float reflAtten = exp(-reflDist * 5.0) * 0.15;
            rUV.x += sin(uv.y * 25.0 + t * 2.0) * 0.005;
            rUV.y += cos(uv.x * 20.0 + t * 1.5) * 0.003;
            float3 reflNeon = float3(0.0);
            float rfl;
            dist = nr_sdSegment(rUV, float2(-0.32, -0.05), float2(0.32, -0.05));
            rfl = nr_flicker(t, 41.0, NR_FLICKER_RATE) * nr_fadeIn(t, 0.2, 1.5);
            reflNeon += nr_neonGlow(dist, warmAmber, tw * 1.2, rfl * NR_GLOW_INTENSITY);
            dist = nr_sdTriangle(rUV, float2(-0.06, -0.05), float2(0.0, 0.32), float2(0.06, -0.05));
            rfl = nr_flicker(t, 42.0, NR_FLICKER_RATE) * nr_fadeIn(t, 0.4, 1.4);
            reflNeon += nr_neonGlow(dist, hotPink, tw * 1.1, rfl * NR_GLOW_INTENSITY * 1.05);
            dist = nr_sdTriangle(rUV, float2(-0.18, -0.05), float2(-0.12, 0.18), float2(-0.06, -0.05));
            rfl = nr_flicker(t, 43.0, NR_FLICKER_RATE) * nr_fadeIn(t, 0.55, 1.4);
            reflNeon += nr_neonGlow(dist, hotPink, tw * 1.1, rfl * NR_GLOW_INTENSITY);
            dist = nr_sdTriangle(rUV, float2(0.06, -0.05), float2(0.12, 0.18), float2(0.18, -0.05));
            rfl = nr_flicker(t, 44.0, NR_FLICKER_RATE) * nr_fadeIn(t, 0.6, 1.4);
            reflNeon += nr_neonGlow(dist, hotPink, tw * 1.1, rfl * NR_GLOW_INTENSITY);
            dist = nr_sdTriangle(rUV, float2(-0.32, -0.05), float2(-0.25, 0.12), float2(-0.18, -0.05));
            rfl = nr_flicker(t, 45.0, NR_FLICKER_RATE) * nr_fadeIn(t, 0.7, 1.4);
            reflNeon += nr_neonGlow(dist, softPink, tw * 1.1, rfl * NR_GLOW_INTENSITY * 0.9);
            dist = nr_sdTriangle(rUV, float2(0.18, -0.05), float2(0.25, 0.12), float2(0.32, -0.05));
            rfl = nr_flicker(t, 46.0, NR_FLICKER_RATE) * nr_fadeIn(t, 0.75, 1.4);
            reflNeon += nr_neonGlow(dist, softPink, tw * 1.1, rfl * NR_GLOW_INTENSITY * 0.9);
            {
                float rjp = 0.8 + 0.2 * sin(t * 1.9);
                float dj1 = nr_sdCircle(rUV, float2(0.0, 0.32), 0.018);
                float dj2 = nr_sdCircle(rUV, float2(-0.12, 0.18), 0.018);
                float dj3 = nr_sdCircle(rUV, float2(0.12, 0.18), 0.018);
                float dj4 = nr_sdCircle(rUV, float2(-0.25, 0.12), 0.018);
                float dj5 = nr_sdCircle(rUV, float2(0.25, 0.12), 0.018);
                dist = min(min(min(dj1, dj2), min(dj3, dj4)), dj5);
                rfl = nr_flicker(t, 47.0, NR_FLICKER_RATE * 0.5) * nr_fadeIn(t, 1.2, 1.0) * rjp;
                reflNeon += nr_neonGlow(dist, warmAmber, tw * 0.8, rfl * NR_GLOW_INTENSITY * 1.15);
            }
            neon += reflNeon * reflAtten;
        }
    }

    // Full sign flicker — occasional whole-sign blink
    {
        float fullFlick = 1.0;
        // Safe mod for time
        float flickerCycle = t - 12.0 * floor(t / 12.0);
        if (flickerCycle > 8.0 && flickerCycle < 8.15) fullFlick = 0.1;
        if (flickerCycle > 8.18 && flickerCycle < 8.22) fullFlick = 0.05;
        if (flickerCycle > 8.28 && flickerCycle < 8.32) fullFlick = 0.15;
        neon *= fullFlick;
    }

    // Combine
    col += neon;

    // Vignette
    float vDist = length(uv);
    float vignette = 1.0 - smoothstep(0.5, 1.4, vDist);
    col *= 0.65 + vignette * 0.35;

    // Tone mapping
    col = col / (1.0 + col * 0.3);

    // Subtle warm color grade
    col = pow(col, float3(0.95, 1.0, 1.05));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
