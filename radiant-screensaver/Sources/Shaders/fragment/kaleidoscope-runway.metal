#include "../Common.metal"

// ─── Kaleidoscope Runway: Fashion-inspired kaleidoscopic tessellations ───
// Ported from static/kaleidoscope-runway.html

// Default parameter values (screensaver — no mouse)
constant float KR_SYMMETRY = 8.0;
constant float KR_PATTERN_SPEED = 0.5;

constant float KR_PI = 3.14159265359;
constant float KR_TAU = 6.28318530718;

// GLSL-compatible mod (always returns positive result)
static float kr_mod(float x, float y) { return x - y * floor(x / y); }

// Rotation matrix
static float2x2 kr_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
}

// Hash for pseudo-random values
static float kr_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Smooth noise
static float kr_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = kr_hash(i);
    float b = kr_hash(i + float2(1.0, 0.0));
    float c = kr_hash(i + float2(0.0, 1.0));
    float d = kr_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Kaleidoscope UV folding
// Folds the UV space into N symmetric mirror segments
static float2 kr_kaleidoscope(float2 uv, float segments) {
    float angle = atan2(uv.y, uv.x);
    float r = length(uv);
    // Fold into segment
    float segAngle = KR_TAU / segments;
    angle = kr_mod(angle, segAngle);
    // Mirror alternate segments for true kaleidoscope
    angle = abs(angle - segAngle * 0.5);
    return float2(cos(angle), sin(angle)) * r;
}

// Sharp geometric stripe pattern
static float kr_stripePattern(float2 p, float t) {
    float s1 = step(0.5, fract(p.x * 3.0 + t * 0.3));
    float s2 = step(0.5, fract(p.y * 4.0 - t * 0.2));
    return s1 * 0.5 + s2 * 0.5;
}

// Chevron / herringbone pattern
static float kr_chevronPattern(float2 p, float t) {
    float y = p.y + t * 0.15;
    float chevron = abs(fract(p.x * 2.0) - 0.5) * 2.0;
    chevron = abs(fract(chevron + y * 3.0) - 0.5) * 2.0;
    return smoothstep(0.3, 0.35, chevron);
}

// Diamond / rhombus pattern
static float kr_diamondPattern(float2 p, float t) {
    float2 q = kr_rot(KR_PI * 0.25) * p;
    float d = abs(fract(q.x * 2.5 + t * 0.1) - 0.5) + abs(fract(q.y * 2.5 - t * 0.08) - 0.5);
    return smoothstep(0.4, 0.42, d);
}

// Triangle grid pattern
static float kr_trianglePattern(float2 p, float t) {
    float2 q = p * 3.0;
    q.x += floor(q.y) * 0.5;
    float2 f = fract(q) - 0.5;
    float tri = abs(f.x) + abs(f.y);
    float anim = sin(t * 0.4 + floor(q.x) * 1.3 + floor(q.y) * 0.7) * 0.15;
    return smoothstep(0.45 + anim, 0.47 + anim, tri);
}

// Palette: warm gold, deep amber, bright copper, hot pink
static float3 kr_palette(float t, float patIdx) {
    // Five key colors that cycle
    float3 c0 = float3(0.85, 0.65, 0.15);  // warm gold
    float3 c1 = float3(0.60, 0.30, 0.08);  // deep amber
    float3 c2 = float3(0.90, 0.50, 0.18);  // bright copper
    float3 c3 = float3(0.92, 0.25, 0.45);  // hot pink
    float3 c4 = float3(1.00, 0.78, 0.30);  // bright gold

    float phase = fract(t + patIdx * 0.2);
    float3 col;
    if (phase < 0.2) {
        col = mix(c0, c1, phase / 0.2);
    } else if (phase < 0.4) {
        col = mix(c1, c2, (phase - 0.2) / 0.2);
    } else if (phase < 0.6) {
        col = mix(c2, c3, (phase - 0.4) / 0.2);
    } else if (phase < 0.8) {
        col = mix(c3, c4, (phase - 0.6) / 0.2);
    } else {
        col = mix(c4, c0, (phase - 0.8) / 0.2);
    }
    return col;
}

fragment float4 fs_kaleidoscope_runway(VSOut in [[stage_in]],
                                        constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * KR_PATTERN_SPEED;
    float segments = KR_SYMMETRY;

    // Rotation: auto only (no mouse drag for screensaver)
    float globalRot = t * 0.12;
    uv = kr_rot(globalRot) * uv;

    float r = length(uv);

    // Apply kaleidoscope folding
    float2 kuv = kr_kaleidoscope(uv, segments);

    // Animate the pattern space
    // Radial zoom that breathes in and out
    float zoomPulse = 1.0 + sin(t * 0.35) * 0.15;
    kuv *= zoomPulse;

    // Slowly drift the pattern origin for evolution
    kuv += float2(t * 0.05, t * 0.03);

    // Layer 1: Chevron textile pattern
    float chev = kr_chevronPattern(kuv * 1.2, t);

    // Layer 2: Diamond facets
    float diam = kr_diamondPattern(kuv * 0.8 + float2(t * 0.02), t * 1.2);

    // Layer 3: Stripes (fashion runway stripes)
    float2 stripeUV = kr_rot(t * 0.08) * kuv;
    float stripe = kr_stripePattern(stripeUV * 1.5, t);

    // Layer 4: Triangle tessellation
    float tri = kr_trianglePattern(kuv * 0.9 + float2(sin(t * 0.2) * 0.3), t);

    // Morph between patterns over time
    float morphPhase = fract(t * 0.06);
    float m0 = smoothstep(0.0, 0.1, morphPhase) * smoothstep(0.35, 0.25, morphPhase);
    float m1 = smoothstep(0.2, 0.3, morphPhase) * smoothstep(0.55, 0.45, morphPhase);
    float m2 = smoothstep(0.4, 0.5, morphPhase) * smoothstep(0.75, 0.65, morphPhase);
    float m3 = smoothstep(0.6, 0.7, morphPhase) * smoothstep(0.95, 0.85, morphPhase);
    // Ensure there is always something visible
    float mSum = m0 + m1 + m2 + m3;
    if (mSum < 0.3) {
        m0 = max(m0, 0.3f);
        m1 = max(m1, 0.2f);
    }

    float pattern = chev * m0 + diam * m1 + stripe * m2 + tri * m3;
    // Add a persistent base layer so patterns never fully vanish
    float basePat = kr_diamondPattern(kuv * 1.1, t * 0.7) * 0.35;
    pattern = max(pattern, basePat);

    // Second kaleidoscope fold at different scale for depth
    float2 kuv2 = kr_kaleidoscope(uv * 1.3, segments + 2.0);
    kuv2 *= 1.0 + sin(t * 0.25) * 0.1;
    kuv2 += float2(t * 0.03, -t * 0.04);
    float innerPattern = kr_chevronPattern(kuv2, t * 0.8) * 0.4;
    innerPattern += kr_trianglePattern(kuv2 * 1.2, t * 0.6) * 0.3;

    // Color assignment
    float colorPhase = t * 0.04 + r * 0.5;
    float3 col1 = kr_palette(colorPhase, 0.0);
    float3 col2 = kr_palette(colorPhase + 0.3, 1.0);
    float3 col3 = kr_palette(colorPhase + 0.6, 2.0);

    // Build the color from pattern layers
    float3 col = float3(0.02, 0.015, 0.01); // Dark base

    // Primary kaleidoscope pattern
    col = mix(col, col1 * 1.1, pattern * 0.7);

    // Inner detail pattern with second color
    col = mix(col, col2, innerPattern * 0.5);

    // Geometric edge highlights
    float foldAngle = atan2(uv.y, uv.x);
    float segAngle = KR_TAU / segments;
    float foldDist = abs(sin(foldAngle * segments * 0.5));
    float foldLine = smoothstep(0.02, 0.0, 1.0 - foldDist) * 0.6;
    // Animate the fold brightness
    foldLine *= 0.5 + 0.5 * sin(t * 0.5 + r * 4.0);
    col += col3 * foldLine;

    // Radial gradient layers for depth
    float rings = sin(r * 12.0 - t * 1.5) * 0.5 + 0.5;
    rings = smoothstep(0.4, 0.6, rings) * 0.15;
    col += kr_palette(colorPhase + 0.5, 3.0) * rings * (1.0 - r);

    // Bright center focal point
    float centerGlow = exp(-r * r * 8.0);
    float3 centerColor = mix(
        float3(1.0, 0.85, 0.45),  // bright gold
        float3(1.0, 0.55, 0.65),  // warm pink-gold
        sin(t * 0.3) * 0.5 + 0.5
    );
    col += centerColor * centerGlow * 0.7;

    // Secondary center detail — mandala star
    float starAngle = atan2(uv.y, uv.x);
    float star = abs(sin(starAngle * segments * 0.5 + t * 0.4));
    star = pow(star, 8.0) * exp(-r * 3.0);
    col += float3(1.0, 0.9, 0.6) * star * 0.4;

    // Hot pink accent flashes
    float pinkFlash = sin(t * 0.7 + r * 6.0) * cos(foldAngle * 3.0 + t * 0.4);
    pinkFlash = pow(max(pinkFlash, 0.0), 6.0) * 0.8;
    col += float3(0.95, 0.2, 0.5) * pinkFlash * (1.0 - r * 0.5);

    // Outer fade — mandala dissolves at edges
    float edgeFade = smoothstep(0.9, 0.5, r);
    col *= edgeFade;

    // Subtle noise texture for fabric feel
    float tex = kr_noise(in.pos.xy * 0.5) * 0.04 - 0.02;
    col += tex;

    // Tone mapping
    col = col / (1.0 + col * 0.3);

    // Warmth push
    col = pow(max(col, float3(0.0)), float3(0.92, 0.96, 1.06));

    // Vignette
    float vig = 1.0 - dot(uv, uv) * 0.4;
    col *= max(vig, 0.0);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
