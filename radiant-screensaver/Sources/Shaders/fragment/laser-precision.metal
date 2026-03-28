#include "../Common.metal"

// ─── Laser Precision: Industrial laser engraving geometric shapes ───
// Ported from static/laser-precision.html
// Original: animates laser beams tracing geometric shapes on brushed metal,
// with burn marks, sparks, and heat glow. Fragment shader reimagines this
// as a per-pixel SDF composition: brushed metal surface + laser-burned
// grooves + animated hot tip with glow.

constant float LP_CYCLE_TIME = 12.0;     // seconds per shape cycle
constant float LP_DRAW_FRAC = 0.55;      // fraction of cycle spent drawing
constant float LP_HOLD_FRAC = 0.25;      // fraction spent holding
constant float LP_GROOVE_WIDTH = 0.004;   // groove line width (normalized)
constant float LP_GLOW_RADIUS = 0.06;    // tip glow size
constant float LP_SURFACE_BASE = 0.24;   // brushed metal base brightness
constant float LP_GROOVE_DARK = 0.06;    // groove darkness
constant float LP_NUM_SHAPES [[maybe_unused]] = 5.0;
constant int LP_CIRCLE_SEGS [[maybe_unused]] = 64;
constant float LP_SPARK_COUNT = 8.0;     // pseudo-spark rays around tip
constant float LP_EMBOSS_OFFSET = 0.002; // emboss shadow/highlight offset

// ── Hash for pseudo-random ──
static float lp_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Brushed metal texture ──
static float lp_brushed(float2 uv, float t) {
    float grain = lp_hash(float2(floor(uv.x * 800.0), floor(uv.y * 2000.0)));
    float streak = snoise(float2(uv.x * 2.0, uv.y * 400.0 + t * 0.1)) * 0.5 + 0.5;
    return mix(0.92, 1.08, grain * 0.5 + streak * 0.5);
}

// ── SDF: circle (ring) ──
static float lp_sdCircle(float2 p, float2 c, float r) {
    return abs(length(p - c) - r);
}

// ── SDF: regular polygon outline ──
static float lp_sdPolygon(float2 p, float2 c, float r, int sides, float rot) {
    float2 d = p - c;
    float angle = atan2(d.y, d.x) - rot;
    float seg = 6.28318530718 / float(sides);
    float a = fmod(angle, seg);
    if (a < 0.0) a += seg;
    a -= seg * 0.5;
    float dist = length(d);
    // Distance to edge of regular polygon
    float edge = r * cos(seg * 0.5) / cos(a);
    return abs(dist - edge);
}

// ── SDF: star outline ──
static float lp_sdStar(float2 p, float2 c, float outerR, float innerR, int points, float rot) {
    float2 d = p - c;
    float angle = atan2(d.y, d.x) - rot;
    float seg = 3.14159265359 / float(points);
    float a = fmod(angle, seg * 2.0);
    if (a < 0.0) a += seg * 2.0;
    float dist = length(d);

    // Interpolate between inner and outer radius based on angle within segment
    float t = a / seg; // 0 to 2
    float edgeR;
    if (t < 1.0) {
        edgeR = mix(outerR, innerR, t);
    } else {
        edgeR = mix(innerR, outerR, t - 1.0);
    }
    return abs(dist - edgeR);
}

// ── SDF: diamond ──
static float lp_sdDiamond(float2 p, float2 c, float w, float h) {
    float2 d = abs(p - c);
    return abs(d.x / w + d.y / h - 1.0) * min(w, h) * 0.5;
}

// ── Composite shape SDF for a given shape index ──
static float lp_shapeSDF(float2 p, float2 center, float scale, int shapeIdx) {
    float d = 1e9;
    switch (shapeIdx % 5) {
        case 0: // Triangle + circle + inverted triangle
            d = min(d, lp_sdPolygon(p, center, scale * 0.85, 3, -1.5708));
            d = min(d, lp_sdCircle(p, center, scale * 0.42));
            d = min(d, lp_sdPolygon(p, center, scale * 0.35, 3, 1.5708));
            break;
        case 1: // Diamond + diamond + circle
            d = min(d, lp_sdDiamond(p, center, scale * 0.7, scale * 0.85));
            d = min(d, lp_sdDiamond(p, center, scale * 0.4, scale * 0.5));
            d = min(d, lp_sdCircle(p, center, scale * 0.55));
            break;
        case 2: // Star + pentagon + circle
            d = min(d, lp_sdStar(p, center, scale * 0.85, scale * 0.35, 5, -1.5708));
            d = min(d, lp_sdPolygon(p, center, scale * 0.55, 5, -1.5708));
            d = min(d, lp_sdCircle(p, center, scale * 0.28));
            break;
        case 3: // Hexagon + hexagon + circle
            d = min(d, lp_sdPolygon(p, center, scale * 0.85, 6, -0.5236));
            d = min(d, lp_sdPolygon(p, center, scale * 0.5, 6, 0.0));
            d = min(d, lp_sdCircle(p, center, scale * 0.7));
            break;
        case 4: // Circle + octagram + square
            d = min(d, lp_sdCircle(p, center, scale * 0.8));
            d = min(d, lp_sdStar(p, center, scale * 0.75, scale * 0.3, 8, 0.0));
            d = min(d, lp_sdPolygon(p, center, scale * 0.4, 4, 0.7854));
            break;
    }
    return d;
}

// ── Animated tip position along shape outline ──
static float2 lp_tipPosition(float2 center, float scale, int shapeIdx, float progress) {
    float angle = progress * 6.28318530718 - 1.5708;
    float r;
    switch (shapeIdx % 5) {
        case 0: r = scale * 0.85; break;
        case 1: r = scale * 0.7; break;
        case 2: r = scale * 0.85; break;
        case 3: r = scale * 0.85; break;
        default: r = scale * 0.8; break;
    }
    return center + float2(cos(angle), sin(angle)) * r;
}

fragment float4 fs_laser_precision(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float aspect = res.x / res.y;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float t = u.time;

    // Determine which shape and phase we're in
    float cycleT = fmod(t, LP_CYCLE_TIME);
    float drawEnd = LP_CYCLE_TIME * LP_DRAW_FRAC;
    float holdEnd = drawEnd + LP_CYCLE_TIME * LP_HOLD_FRAC;
    int shapeIdx = int(floor(t / LP_CYCLE_TIME));

    float drawProgress = clamp(cycleT / drawEnd, 0.0, 1.0);
    float fadeAlpha = cycleT > holdEnd
        ? 1.0 - clamp((cycleT - holdEnd) / (LP_CYCLE_TIME - holdEnd), 0.0, 1.0)
        : 1.0;
    bool isDrawing = cycleT < drawEnd;

    // Scale in normalized coords
    float scale = 0.35;
    float2 center = float2(0.0);

    // ── Brushed metal surface ──
    float brushTex = lp_brushed(uv, t);
    float3 surface = float3(LP_SURFACE_BASE) * brushTex;

    // Subtle directional lighting gradient
    surface *= 0.92 + 0.16 * (1.0 - uv.y);

    // ── Shape groove ──
    float shapeDist = lp_shapeSDF(p, center, scale, shapeIdx);

    // Groove mask (how much of the shape is revealed)
    float grooveMask = drawProgress;
    // For the groove, we show the full SDF but modulate alpha by draw progress
    float grooveAlpha = smoothstep(LP_GROOVE_WIDTH * 1.5, 0.0, shapeDist) * fadeAlpha;

    // Emboss effect: offset sampling for light/shadow
    float shapeDistUp = lp_shapeSDF(p + float2(-LP_EMBOSS_OFFSET, -LP_EMBOSS_OFFSET), center, scale, shapeIdx);
    float shapeDistDown = lp_shapeSDF(p + float2(LP_EMBOSS_OFFSET, LP_EMBOSS_OFFSET), center, scale, shapeIdx);
    float shadowMask = smoothstep(LP_GROOVE_WIDTH * 1.5, 0.0, shapeDistUp) * fadeAlpha;
    float highlightMask = smoothstep(LP_GROOVE_WIDTH * 1.5, 0.0, shapeDistDown) * fadeAlpha;

    // Apply groove: darken, then add emboss
    float3 col = surface;
    col = mix(col, float3(LP_GROOVE_DARK), grooveAlpha * grooveMask * 0.7);
    col -= float3(0.08) * shadowMask * grooveMask;    // shadow
    col += float3(0.04) * highlightMask * grooveMask;  // highlight

    // ── Laser tip glow (only during drawing) ──
    if (isDrawing) {
        float2 tip = lp_tipPosition(center, scale, shapeIdx, drawProgress);
        float tipDist = length(p - tip);

        // Multi-layered glow like the original
        // Layer 1: Large soft heat bloom (red/orange)
        float bloom = exp(-tipDist * tipDist / (LP_GLOW_RADIUS * LP_GLOW_RADIUS * 4.0));
        col += float3(1.0, 0.4, 0.08) * bloom * 0.3;

        // Layer 2: Medium amber glow
        float midGlow = exp(-tipDist * tipDist / (LP_GLOW_RADIUS * LP_GLOW_RADIUS));
        col += float3(1.0, 0.63, 0.16) * midGlow * 0.5;

        // Layer 3: Bright core
        float core = exp(-tipDist * tipDist / (LP_GLOW_RADIUS * LP_GLOW_RADIUS * 0.15));
        col += float3(1.0, 0.88, 0.56) * core * 0.7;

        // Layer 4: White-hot center
        float hotCenter = exp(-tipDist * tipDist / (LP_GLOW_RADIUS * LP_GLOW_RADIUS * 0.03));
        col += float3(1.0, 1.0, 0.96) * hotCenter * 1.2;

        // ── Hot zone beam trail behind tip ──
        // Glow along the groove near the tip
        float hotZone = 0.08; // how far back the hot zone extends (normalized)
        float nearTip = smoothstep(LP_GROOVE_WIDTH * 2.0, 0.0, shapeDist);
        float2 toTip = tip - p;
        float projDist = length(toTip);
        float hotFade = exp(-projDist * projDist / (hotZone * hotZone));
        col += float3(1.0, 0.5, 0.12) * nearTip * hotFade * 0.4 * grooveMask;

        // ── Pseudo-sparks: radial noise rays around tip ──
        float2 sparkDir = p - tip;
        float sparkAngle = atan2(sparkDir.y, sparkDir.x);
        for (int si = 0; si < int(LP_SPARK_COUNT); si++) {
            float seedAngle = lp_hash(float2(float(si) * 7.3, t * 3.0 + float(si))) * 6.2832;
            float sparkLen = (0.02 + lp_hash(float2(float(si), t * 2.7)) * 0.06);
            float angleDiff = abs(sparkAngle - seedAngle);
            angleDiff = min(angleDiff, 6.2832 - angleDiff);
            float sparkMask = exp(-angleDiff * angleDiff * 200.0);
            float radialFade = smoothstep(sparkLen, 0.0, tipDist) * smoothstep(0.001, 0.005, tipDist);
            col += float3(1.0, 0.8, 0.3) * sparkMask * radialFade * 0.6;
        }
    }

    // ── Vignette ──
    float vig = 1.0 - 0.35 * dot(uv - 0.5, uv - 0.5) * 4.0;
    col *= vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
