#include "../Common.metal"

// ─── Voltage Arc: Electric arcs crackling between floating conductors ───
// Ported from static/voltage-arc.html

constant float VA_PI = 3.14159265359;
constant float VA_ARC_INTENSITY = 1.0;
constant float VA_CRACKLE_SPEED = 0.5;
constant int VA_NUM_CONDUCTORS = 4;

// ── Hash for noise ──
static float va_hash(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Value noise ──
static float va_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(va_hash(i), va_hash(i + float2(1.0, 0.0)), f.x),
        mix(va_hash(i + float2(0.0, 1.0)), va_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// ── Layered noise for arc displacement ──
static float va_arcNoise(float2 p) {
    float v = va_vnoise(p) * 0.6;
    v += va_vnoise(p * 2.3 + 17.1) * 0.3;
    v += va_vnoise(p * 5.7 + 43.2) * 0.1;
    return v;
}

// ── Conductor positions ──
static float2 va_conductor(int idx, float t) {
    float fi = float(idx);
    float angle = fi * 1.571 + t * (0.12 + fi * 0.03);
    float rx = 0.25 + fi * 0.05;
    float ry = 0.18 + fi * 0.04;
    float offx = sin(fi * 2.7 + 0.5) * 0.1;
    float offy = cos(fi * 1.9 + 1.3) * 0.08;
    return float2(
        offx + cos(angle) * rx + sin(t * 0.07 + fi * 3.1) * 0.06,
        offy + sin(angle * 1.3 + fi * 0.8) * ry + cos(t * 0.09 + fi * 2.3) * 0.05
    );
}

// ── Electric arc contribution ──
static float va_electricArc(float2 uv, float2 a, float2 b, float t, float seed) {
    float2 ab = b - a;
    float len = length(ab);
    if (len < 0.001) return 0.0;
    float2 dir = ab / len;
    float2 perp = float2(-dir.y, dir.x);

    float2 ap = uv - a;
    float proj = dot(ap, dir);
    float param = clamp(proj / len, 0.0, 1.0);

    float noiseT = t * VA_CRACKLE_SPEED * 8.0 + seed * 100.0;
    float noiseX = param * 6.0 + seed * 37.0;

    float disp = (va_arcNoise(float2(noiseX, noiseT)) - 0.5) * 0.12;
    float taper = param * (1.0 - param) * 4.0;
    taper = min(taper, 1.0);
    disp *= taper;

    float fine = (va_arcNoise(float2(noiseX * 3.0 + 91.0, noiseT * 1.7 + 53.0)) - 0.5) * 0.03;
    fine *= taper;

    float2 arcPoint = a + dir * (param * len) + perp * (disp + fine);
    float d = length(uv - arcPoint);

    float pulse = 0.7 + 0.3 * sin(t * 1.5 + seed * 5.0);
    pulse *= 0.8 + 0.2 * sin(t * 3.7 + seed * 11.0);

    float flicker = 0.85 + 0.15 * sin(noiseT * 13.0 + param * 20.0);

    float core = 0.004 / (d * d + 0.00006);
    core = min(core, 12.0);

    float inner = 0.002 / (d + 0.005);
    inner = min(inner, 1.5);

    float outer = 0.003 / (d + 0.03);
    outer = min(outer, 0.4);

    float total = (core * 0.5 + inner * 0.15 + outer * 0.05) * pulse * flicker * taper;
    return total;
}

// ── Branch arc ──
static float va_branchArc(float2 uv, float2 a, float2 b, float t, float seed) {
    float2 ab = b - a;
    float len = length(ab);
    if (len < 0.001) return 0.0;
    float2 dir = ab / len;
    float2 perp = float2(-dir.y, dir.x);

    float2 ap = uv - a;
    float proj = dot(ap, dir);
    float param = clamp(proj / len, 0.0, 1.0);

    float noiseT = t * VA_CRACKLE_SPEED * 10.0 + seed * 200.0;
    float noiseX = param * 4.0 + seed * 53.0;

    float disp = (va_arcNoise(float2(noiseX, noiseT)) - 0.5) * 0.06;
    float taper = sqrt(param) * pow(1.0 - param, 2.0) * 6.75;
    taper = min(taper, 1.0);
    disp *= taper;

    float2 arcPoint = a + dir * (param * len) + perp * disp;
    float d = length(uv - arcPoint);

    float flicker = 0.5 + 0.5 * sin(noiseT * 17.0 + param * 30.0);

    float core = 0.001 / (d * d + 0.0002);
    core = min(core, 4.0);
    float glow = 0.002 / (d + 0.012);
    glow = min(glow, 0.8);

    return (core * 0.4 + glow * 0.1) * flicker * taper;
}

// ── Conductor point glow ──
static float va_conductorGlow(float2 uv, float2 pos) {
    float d = length(uv - pos);
    float core = 0.0006 / (d * d + 0.00005);
    core = min(core, 6.0);
    float glow = 0.002 / (d + 0.01);
    glow = min(glow, 1.0);
    float halo = 0.003 / (d + 0.06);
    halo = min(halo, 0.2);
    return core * 0.3 + glow * 0.15 + halo * 0.05;
}

fragment float4 fs_voltage_arc(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float intensity = VA_ARC_INTENSITY;

    // ── Background ──
    float3 bg = float3(0.031, 0.024, 0.016);

    float bgNoise = va_vnoise(uv * 3.0 + t * 0.05) * 0.008;
    bg += float3(bgNoise * 0.8, bgNoise * 0.5, bgNoise * 0.3);

    // ── Conductor positions ──
    float2 c0 = va_conductor(0, t);
    float2 c1 = va_conductor(1, t);
    float2 c2 = va_conductor(2, t);
    float2 c3 = va_conductor(3, t);

    // ── Color layers ──
    float3 coreColor  = float3(3.0, 2.8, 2.4);
    float3 innerColor = float3(1.8, 1.2, 0.55);
    float3 outerColor = float3(1.0, 0.6, 0.2);

    // ── Accumulate arc contributions (no mouse arcs) ──
    float totalArc = 0.0;
    float totalBranch = 0.0;

    totalArc += va_electricArc(uv, c0, c1, t, 1.0);
    totalArc += va_electricArc(uv, c1, c2, t, 2.7);
    totalArc += va_electricArc(uv, c2, c3, t, 4.3);
    totalArc += va_electricArc(uv, c3, c0, t, 6.1);

    float diagPulse = smoothstep(0.3, 0.7, sin(t * 0.4 + 1.0) * 0.5 + 0.5);
    totalArc += va_electricArc(uv, c0, c2, t, 8.5) * diagPulse;

    // ── Branch arcs ──
    float2 mid01 = (c0 + c1) * 0.5 + float2(
        sin(t * 2.3) * 0.02,
        cos(t * 1.9) * 0.02
    );
    float2 branchEnd1 = mid01 + float2(
        sin(t * 0.7 + 3.0) * 0.12,
        cos(t * 0.5 + 1.0) * 0.08
    );
    float branchActive1 = smoothstep(0.4, 0.6, sin(t * 0.8 + 2.0) * 0.5 + 0.5);
    totalBranch += va_branchArc(uv, mid01, branchEnd1, t, 11.0) * branchActive1;

    float2 mid23 = (c2 + c3) * 0.5 + float2(
        cos(t * 1.8) * 0.02,
        sin(t * 2.1) * 0.02
    );
    float2 branchEnd2 = mid23 + float2(
        cos(t * 0.6 + 5.0) * 0.10,
        sin(t * 0.8 + 3.0) * 0.10
    );
    float branchActive2 = smoothstep(0.4, 0.6, sin(t * 0.6 + 4.0) * 0.5 + 0.5);
    totalBranch += va_branchArc(uv, mid23, branchEnd2, t, 15.0) * branchActive2;

    // ── Composite arc color ──
    float arcVal = totalArc * intensity;
    float branchVal = totalBranch * intensity * 0.85;

    float3 arcColor = outerColor * smoothstep(0.0, 0.3, arcVal) * 0.3;
    arcColor += innerColor * smoothstep(0.2, 1.0, arcVal) * 0.5;
    arcColor += coreColor * smoothstep(0.8, 2.0, arcVal) * 0.8;
    arcColor += float3(2.5, 2.3, 2.0) * smoothstep(2.0, 4.0, arcVal) * 0.5;

    float3 branchColor = outerColor * smoothstep(0.0, 0.2, branchVal) * 0.35;
    branchColor += innerColor * smoothstep(0.15, 0.5, branchVal) * 0.5;
    branchColor += coreColor * smoothstep(0.4, 1.2, branchVal) * 0.7;

    // ── Conductor point rendering ──
    float condGlow = 0.0;
    condGlow += va_conductorGlow(uv, c0);
    condGlow += va_conductorGlow(uv, c1);
    condGlow += va_conductorGlow(uv, c2);
    condGlow += va_conductorGlow(uv, c3);

    float3 condColor = float3(0.0);
    condColor += coreColor * smoothstep(0.0, 0.5, condGlow) * 0.25;
    condColor += innerColor * smoothstep(0.4, 1.5, condGlow) * 0.3;
    condColor += float3(2.0, 1.8, 1.5) * smoothstep(1.5, 3.5, condGlow) * 0.4;

    // ── Ambient electric haze ──
    float haze = 0.0;
    haze += 0.005 / (length(uv - c0) + 0.4);
    haze += 0.005 / (length(uv - c1) + 0.4);
    haze += 0.005 / (length(uv - c2) + 0.4);
    haze += 0.005 / (length(uv - c3) + 0.4);
    float3 hazeColor = outerColor * haze * intensity * 0.12;

    // ── Combine ──
    float3 col = bg;
    col += hazeColor;
    col += arcColor;
    col += branchColor;
    col += condColor;

    // ── Film grain ──
    float grain = (va_hash(in.pos.xy + fract(t * 43.0) * 1000.0) - 0.5) * 0.015;
    col += grain;

    // ── Vignette ──
    float vig = length(uv * float2(0.9, 1.0));
    float vignette = 1.0 - smoothstep(0.5, 1.2, vig);
    col *= 0.75 + vignette * 0.25;

    // ── Tone mapping — ACES filmic ──
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
    col = pow(col, float3(0.92, 0.97, 1.05));

    col = max(col, float3(0.0));
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
