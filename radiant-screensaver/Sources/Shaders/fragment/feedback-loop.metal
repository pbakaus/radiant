#include "../Common.metal"

// ─── Feedback Loop: Recursive fractal tunnel with geometric seeds ───
// Ported from static/feedback-loop.html
// Original uses ping-pong FBO feedback; this single-pass version
// recreates the infinite tunnel depth with layered polar geometry.

constant float FL_PI = 3.14159265359;
constant float FL_ZOOM_SPEED = 1.0;
constant float FL_ROTATION_SPEED = 0.5;

// ── Hash ──
static float fl_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── 2D rotation ──
static float2 fl_rot2(float2 p, float a) {
    float c = cos(a), s = sin(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// ── SDF primitives ──
static float fl_sdHexagon(float2 p, float r) {
    float2 q = abs(p);
    return max(q.x - r * 0.866, max(q.x * 0.5 + q.y * 0.866 - r * 0.866, q.y - r * 0.5));
}

static float fl_sdTriangle(float2 p, float r) {
    float k = sqrt(3.0);
    p.x = abs(p.x) - r;
    p.y = p.y + r / k;
    if (p.x + k * p.y > 0.0) p = float2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
    p.x -= clamp(p.x, -2.0 * r, 0.0);
    return -length(p) * sign(p.y);
}

static float fl_sdCircle(float2 p, float r) {
    return length(p) - r;
}

static float fl_sdStar(float2 p, float r, int n, float m) {
    float an = FL_PI / float(n);
    float en = FL_PI / m;
    float2 acs = float2(cos(an), sin(an));
    float2 ecs = float2(cos(en), sin(en));
    // mod(atan(p.x, p.y), 2*an) - an  (GLSL mod always positive)
    float angle = atan2(p.x, p.y);
    float bn = angle - 2.0 * an * floor(angle / (2.0 * an)) - an;
    p = length(p) * float2(cos(bn), abs(sin(bn)));
    p -= r * acs;
    p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);
    return length(p) * sign(p.x);
}

// ── Simulate recursive feedback tunnel as layered rings ──
// Each layer represents one "feedback iteration" at a different zoom depth
static float3 fl_tunnelLayer(float2 uv, float aspect, float t, float layerDepth, float layerIdx) {
    float2 center = float2(0.5);
    float2 fromCenter = uv - center;
    fromCenter.x *= aspect;

    // Each layer is progressively zoomed and rotated
    float zoomAmt = 0.02 + 0.008 * sin(t * 0.3);
    zoomAmt *= FL_ZOOM_SPEED;
    float zoom = pow(1.0 - zoomAmt, layerDepth);
    fromCenter /= zoom;

    float rotAmt = (0.008 + 0.004 * sin(t * 0.5)) * FL_ROTATION_SPEED;
    rotAmt *= sin(t * 0.07);
    fromCenter = fl_rot2(fromCenter, rotAmt * layerDepth);

    fromCenter.x /= aspect;
    float2 layerUV = fromCenter + center;

    // Geometric seed shapes
    float2 sp = layerUV - float2(0.5);
    sp.x *= aspect;

    float seedScale = 0.06;
    float shapeCycle = (t * 0.15 + layerIdx * 0.7) - 4.0 * floor((t * 0.15 + layerIdx * 0.7) / 4.0);
    float shapeBlend = fract(shapeCycle);
    float shapeSmooth = shapeBlend * shapeBlend * (3.0 - 2.0 * shapeBlend);
    int shapeA = int(shapeCycle - 4.0 * floor(shapeCycle / 4.0));

    float seedRot = t * 0.3 * FL_ROTATION_SPEED + layerIdx * 0.5;
    float2 rsp = fl_rot2(sp, seedRot);

    float pulse = seedScale * (0.85 + 0.15 * sin(t * 2.0 + layerIdx));

    float dHex = fl_sdHexagon(rsp, pulse);
    float dTri = fl_sdTriangle(rsp, pulse * 1.3);
    float dCirc = fl_sdCircle(rsp, pulse * 0.7);
    float dStar = fl_sdStar(rsp, pulse * 0.9, 5, 2.5);

    float d1, d2;
    if (shapeA == 0) { d1 = dHex; d2 = dTri; }
    else if (shapeA == 1) { d1 = dTri; d2 = dCirc; }
    else if (shapeA == 2) { d1 = dCirc; d2 = dStar; }
    else { d1 = dStar; d2 = dHex; }
    float d = mix(d1, d2, shapeSmooth);

    float shape = 1.0 - smoothstep(-0.003, 0.003, d);
    float shapeGlow = 1.0 - smoothstep(0.0, 0.025, d);

    // Ring shapes
    float ringRadius = pulse * 2.8 + 0.02 * sin(t * 1.5 + layerIdx);
    float ringThickness = 0.004 + 0.002 * sin(t * 3.0);
    float ringDist = abs(length(rsp) - ringRadius);
    float ring = 1.0 - smoothstep(0.0, ringThickness, ringDist);

    float ring2Radius = pulse * 4.5;
    float ring2Dist = abs(length(rsp) - ring2Radius);
    float ring2 = 1.0 - smoothstep(0.0, ringThickness * 0.5, ring2Dist);

    // Rotating dot pattern
    float dotAngle = atan2(sp.y, sp.x) + t * 0.5;
    float dotRadius = length(sp);
    float dotPattern = step(0.95, cos(dotAngle * 6.0) * 0.5 + 0.5) *
                       step(0.03, dotRadius) * step(dotRadius, 0.05);

    // Colors with hue cycling per layer depth
    float hueShift = 0.012 * layerDepth;
    float cs = cos(hueShift), sn = sin(hueShift);
    float oneThird = 1.0 / 3.0;
    float sqrtThird = 0.57735;

    float3 seedColor = float3(0.95, 0.65, 0.25) * shape;
    seedColor += float3(0.7, 0.45, 0.15) * shapeGlow * 0.5;
    seedColor += float3(0.15, 0.75, 0.85) * ring * 0.8;
    seedColor += float3(0.5, 0.35, 0.65) * ring2 * 0.4;
    seedColor += float3(1.0, 0.85, 0.5) * dotPattern * 0.6;

    // Apply hue rotation for color cycling
    float3x3 hueMatrix = float3x3(
        float3(cs + oneThird * (1.0 - cs),          oneThird * (1.0 - cs) - sqrtThird * sn, oneThird * (1.0 - cs) + sqrtThird * sn),
        float3(oneThird * (1.0 - cs) + sqrtThird * sn, cs + oneThird * (1.0 - cs),          oneThird * (1.0 - cs) - sqrtThird * sn),
        float3(oneThird * (1.0 - cs) - sqrtThird * sn, oneThird * (1.0 - cs) + sqrtThird * sn, cs + oneThird * (1.0 - cs))
    );
    seedColor = hueMatrix * seedColor;

    // Burst
    float burstPhase = (t * 0.4 + layerIdx * 0.3) - floor(t * 0.4 + layerIdx * 0.3);
    float burst = smoothstep(0.0, 0.05, burstPhase) * smoothstep(0.15, 0.05, burstPhase);
    float burstShape = 1.0 - smoothstep(0.0, pulse * 1.5, length(sp));
    seedColor += float3(1.0, 0.9, 0.6) * burst * burstShape * 0.5;

    // Depth fade: further layers are dimmer
    float depthFade = exp(-layerDepth * 0.04) * 0.96;
    seedColor *= depthFade;

    return seedColor;
}

fragment float4 fs_feedback_loop(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    float t = u.time;

    // Accumulate multiple tunnel layers to simulate feedback depth
    float3 color = float3(0.0);
    int NUM_LAYERS = 24;

    for (int i = 0; i < NUM_LAYERS; i++) {
        float layerDepth = float(i);
        color += fl_tunnelLayer(uv, aspect, t, layerDepth, float(i));
    }

    // ── Post-processing (from display shader) ──

    // Scanlines
    float scanY = in.pos.y;
    float fineScan = sin(scanY * FL_PI * 0.5) * 0.5 + 0.5;
    fineScan = pow(fineScan, 2.0);
    float scanDarken = mix(0.75, 1.0, fineScan);

    float scrollScan = sin((scanY * 0.02 + t * 15.0) * 0.5) * 0.5 + 0.5;
    scrollScan = smoothstep(0.3, 0.7, scrollScan);
    scanDarken *= mix(0.85, 1.0, scrollScan);

    // Bright sweep line
    float sweepPos_val = t * 50.0;
    float totalH = u.resolution.y * 1.5;
    float sweepPos = sweepPos_val - totalH * floor(sweepPos_val / totalH) - u.resolution.y * 0.25;
    float sweep = exp(-abs(scanY - sweepPos) * 0.06) * 0.25;

    color *= scanDarken;
    color += float3(0.4, 0.65, 0.75) * sweep;

    // Vignette
    float2 vigUV = uv * 2.0 - 1.0;
    float vig = 1.0 - dot(vigUV * 0.55, vigUV * 0.55);
    vig = clamp(vig, 0.0, 1.0);
    vig = vig * vig;
    color *= 0.2 + vig * 0.8;

    // Center glow
    float centerDist = length(vigUV);
    float centerGlow = exp(-centerDist * centerDist * 2.0) * 0.08;
    color += float3(0.8, 0.55, 0.25) * centerGlow;

    // Film grain
    float grain = (fl_hash(in.pos.xy + fract(t * 43.0) * 1000.0) - 0.5) * 0.04;
    color += grain;

    // Tone mapping (Reinhard)
    color = color / (1.0 + color * 0.2);

    // Gamma
    color = pow(max(color, float3(0.0)), float3(0.95));

    color = hue_rotate(color, u.hue_shift);
    return float4(clamp(color, float3(0.0), float3(1.0)), 1.0);
}
