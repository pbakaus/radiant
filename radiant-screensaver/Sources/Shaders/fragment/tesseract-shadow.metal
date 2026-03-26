#include "../Common.metal"

// ─── Tesseract Shadow: 4D hypercube projected to 2D with bloom ───
// Ported from static/tesseract-shadow.html
// Strategy: Compute all 16 vertices of a tesseract with 4D rotation,
// project 4D->3D->2D, then draw edges and vertex glows via SDF.

constant float TS_PI = 3.14159265;
constant int TS_NUM_VERTS = 16;
constant int TS_NUM_EDGES = 32;
constant float TS_VIEW_DIST_3D = 5.0;

// ── 4D rotation in a plane ──
static float4 ts_rot4D(float4 v, int a, int b, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    float4 out = v;
    out[a] = v[a] * c - v[b] * s;
    out[b] = v[a] * s + v[b] * c;
    return out;
}

// ── 4D->2D projection ──
static float3 ts_project(float4 v4, float projDepth) {
    float viewDist4 = 3.0 + projDepth * 1.5;
    float scale4 = viewDist4 / (viewDist4 - v4.w);
    float3 p3 = float3(v4.xyz * scale4);
    float scale3 = TS_VIEW_DIST_3D / (TS_VIEW_DIST_3D - p3.z);
    float2 p2 = p3.xy * scale3;
    float depth = (v4.w + 1.0) / 2.0 * 0.5 + (p3.z + 1.5) / 3.0 * 0.5;
    return float3(p2, depth);
}

// ── Edge color by axis ──
static float3 ts_edgeColor(int axis, float depth) {
    if (axis == 0) return float3(0.922, 0.647, 0.314);      // amber-gold
    if (axis == 1) return float3(0.941, 0.549, 0.392);      // rose amber
    if (axis == 2) return float3(0.196, 0.765, 0.706);      // teal
    // w-axis: electric blue-violet with depth variation
    return float3(0.471 + depth * 0.157, 0.314 + depth * 0.078, 0.863 + depth * 0.137);
}

// ── Distance from point to line segment ──
static float ts_segDist(float2 p, float2 a, float2 b) {
    float2 ab = b - a;
    float2 ap = p - a;
    float t = saturate(dot(ap, ab) / max(dot(ab, ab), 0.0001));
    float2 closest = a + ab * t;
    return length(p - closest);
}

fragment float4 fs_tesseract_shadow(VSOut in [[stage_in]],
                                     constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 pixel = in.pos.xy;
    float2 center = res * 0.5;
    float t = u.time;

    float scale = min(res.x, res.y) * 0.28;

    // Breathing projection depth
    float breathe = sin(t * 0.15) * 0.25 + sin(t * 0.37) * 0.1;
    float projDepth = 1.0 + breathe;

    // Integrated rotation angles with subtle surges
    float intT = t - (0.15 / 0.11) * cos(t * 0.11) - (0.08 / 0.29) * cos(t * 0.29);
    float spd = 0.3;
    float angleXW = intT * spd * 0.7;
    float angleYZ = intT * spd * 0.5;
    float angleXY = intT * spd * 0.23;
    float angleZW = intT * spd * 0.17;

    // Generate and project all 16 vertices
    float2 verts2D[16];
    float vertsDepth[16];

    for (int i = 0; i < TS_NUM_VERTS; i++) {
        float4 v = float4(
            (i & 1) ? 1.0 : -1.0,
            (i & 2) ? 1.0 : -1.0,
            (i & 4) ? 1.0 : -1.0,
            (i & 8) ? 1.0 : -1.0
        );
        v = ts_rot4D(v, 0, 3, angleXW);
        v = ts_rot4D(v, 1, 2, angleYZ);
        v = ts_rot4D(v, 0, 1, angleXY);
        v = ts_rot4D(v, 2, 3, angleZW);

        float3 proj = ts_project(v, projDepth);
        verts2D[i] = center + proj.xy * scale;
        vertsDepth[i] = proj.z;
    }

    float3 col = float3(0.0);

    // ── Background grid ──
    float2 gridUV = fract(pixel / 40.0);
    float gridLine = smoothstep(0.03, 0.0, min(gridUV.x, gridUV.y));
    col += float3(1.0) * gridLine * 0.02;

    // ── Radial energy pulse ──
    float pulsePhase = t * 0.4;
    for (int ring = 0; ring < 3; ring++) {
        float ringT = fract(pulsePhase + float(ring) * 0.33);
        float ringRadius = ringT * min(res.x, res.y) * 0.6;
        float ringDist = abs(length(pixel - center) - ringRadius);
        float ringAlpha = (1.0 - ringT) * 0.035;
        float ringGlow = smoothstep(2.0, 0.0, ringDist) * ringAlpha;
        col += float3(0.69, 0.753, 0.878) * ringGlow;
    }

    // ── Crosshair ──
    float chX = smoothstep(1.0, 0.0, abs(pixel.x - center.x)) *
                smoothstep(40.0, 0.0, abs(pixel.y - center.y));
    float chY = smoothstep(1.0, 0.0, abs(pixel.y - center.y)) *
                smoothstep(40.0, 0.0, abs(pixel.x - center.x));
    col += float3(1.0) * (chX + chY) * 0.03;

    // ── Edges: 32 edges connecting vertices differing in exactly 1 coordinate ──
    for (int i = 0; i < TS_NUM_VERTS; i++) {
        for (int j = i + 1; j < TS_NUM_VERTS; j++) {
            int xorVal = i ^ j;
            // Check if exactly 1 bit set (power of 2)
            if ((xorVal & (xorVal - 1)) != 0) continue;

            // Determine axis
            int axis = 0;
            if (xorVal == 2) axis = 1;
            else if (xorVal == 4) axis = 2;
            else if (xorVal == 8) axis = 3;

            float avgDepth = (vertsDepth[i] + vertsDepth[j]) * 0.5;
            float dist = ts_segDist(pixel, verts2D[i], verts2D[j]);

            float3 eCol = ts_edgeColor(axis, avgDepth);
            float alpha = 0.2 + avgDepth * 0.7;
            float lw = 0.8 + avgDepth * 2.2;

            // Multi-pass bloom
            float bloom3 = smoothstep(lw + 12.0, lw + 6.0, dist) * alpha * 0.08;
            float bloom2 = smoothstep(lw + 6.0, lw + 3.0, dist) * alpha * 0.15;
            float bloom1 = smoothstep(lw + 3.0, lw, dist) * alpha * 0.35;
            float core = smoothstep(lw, 0.0, dist) * alpha;

            col += eCol * (bloom3 + bloom2 + bloom1 + core);

            // Hot white center for front-facing edges
            if (avgDepth > 0.55) {
                float whiteAlpha = (avgDepth - 0.55) * 0.6;
                float whiteLine = smoothstep(lw * 0.35, 0.0, dist) * whiteAlpha;
                col += float3(1.0) * whiteLine;
            }
        }
    }

    // ── Vertex glows ──
    for (int i = 0; i < TS_NUM_VERTS; i++) {
        float d = length(pixel - verts2D[i]);
        float depth = vertsDepth[i];
        float pulse = 0.85 + 0.15 * sin(t * 1.5 + float(i) * 0.4);

        float glowSize = (8.0 + depth * 24.0) * pulse;
        float glowAlpha = (0.12 + depth * 0.5) * pulse;

        // Outer halo
        float halo = smoothstep(glowSize * 1.5, 0.0, d) * glowAlpha * 0.2;
        col += float3(0.627, 0.706, 0.863) * halo;

        // Inner glow
        float inner = smoothstep(glowSize, 0.0, d) * glowAlpha;
        col += float3(0.784, 0.824, 0.941) * inner * 0.5;

        // Core dot
        float coreSize = 1.8 + depth * 3.0;
        float coreAlpha = (0.4 + depth * 0.6) * pulse;
        float coreDot = smoothstep(coreSize, 0.0, d) * coreAlpha;
        col += float3(0.902, 0.922, 1.0) * coreDot;
    }

    // ── Vignette ──
    float2 uv = (pixel - center) / res;
    float vig = 1.0 - dot(uv, uv) * 3.0;
    col *= saturate(mix(0.45, 1.0, vig));

    // Background base
    col += float3(0.039);

    col = hue_rotate(col, u.hue_shift);
    return float4(saturate(col), 1.0);
}
