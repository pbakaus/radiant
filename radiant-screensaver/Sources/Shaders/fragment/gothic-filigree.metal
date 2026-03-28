#include "../Common.metal"

// ─── Gothic Filigree: Symmetrical ornamental scrollwork ───
// Ported from static/gothic-filigree.html

constant float GF_PI = 3.14159265359;
constant float GF_TAU = 6.28318530718;

// Default parameter values (no mouse interaction)
constant float GF_DETAIL = 1.0;
constant float GF_GLOW = 1.0;

static float2x2 gf_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// Gothic pointed arch SDF — two overlapping circles
static float gf_archSDF(float2 p, float w, float h) {
    float sep = w * 0.38;
    float rad = sqrt(sep * sep + h * h);
    float d1 = length(p - float2(-sep, 0.0)) - rad;
    float d2 = length(p - float2( sep, 0.0)) - rad;
    float arch = max(d1, d2);
    arch = max(arch, -p.y);
    arch = max(arch, p.y - h * 1.1);
    return arch;
}

// ── Main filigree composition ──
static float gf_filigree(float2 uv, float t) {
    float d = 1e5;
    float lw = 0.002;  // base line width — very thin

    float angle = atan2(uv.y, uv.x);
    float r = length(uv);
    float2 p = abs(uv);  // 4-fold mirror

    // ════════════════════════════════════════════
    // ZONE 1: Central medallion (r < 0.12)
    // ════════════════════════════════════════════
    // Outer ring
    float mR = 0.10;
    d = min(d, abs(r - mR) - lw * 1.3);
    // Inner ring
    d = min(d, abs(r - 0.055) - lw * 0.8);
    // Tiny center dot
    d = min(d, r - 0.012);

    // 8 petals inside medallion
    float seg8 = GF_TAU / 8.0;
    // GLSL mod always returns positive; replicate with x - y*floor(x/y)
    float ra8 = (angle + seg8 * 0.5) - seg8 * floor((angle + seg8 * 0.5) / seg8) - seg8 * 0.5;
    float2 petal8 = float2(cos(ra8), sin(ra8)) * r;
    // Small teardrop petal
    float petalD = length((petal8 - float2(0.075, 0.0)) * float2(1.0, 2.5)) - 0.025;
    petalD = max(petalD, -(r - 0.055));
    petalD = max(petalD, r - mR);
    d = min(d, abs(petalD) - lw * 0.6);

    // ════════════════════════════════════════════
    // ZONE 2: Inner tracery ring (0.12 — 0.28)
    // ════════════════════════════════════════════
    // Bounding rings
    float r1 = 0.13 + 0.003 * sin(t * 0.5);
    float r2 = 0.28 + 0.004 * sin(t * 0.4 + 1.0);
    d = min(d, abs(r - r1) - lw);
    d = min(d, abs(r - r2) - lw * 1.1);
    // Mid ring with scallops
    float midR = 0.205;
    float scallop = 0.015 * abs(cos(angle * 8.0 + t * 0.08));
    d = min(d, abs(r - midR - scallop) - lw * 0.7);

    // 8 pointed gothic arches radiating outward
    float ra8b = (angle + seg8 * 0.5) - seg8 * floor((angle + seg8 * 0.5) / seg8) - seg8 * 0.5;
    float2 rp8 = float2(cos(ra8b), sin(ra8b)) * r;
    // Arch between r1 and r2
    float2 archP = rp8 - float2(r1 + 0.01, 0.0);
    archP = gf_rot(-GF_PI * 0.5) * archP;  // rotate so arch points outward
    float archW = 0.06;
    float archH = (r2 - r1) * 0.85;
    float arch = gf_archSDF(archP, archW, archH);
    d = min(d, abs(arch) - lw * 0.9);

    // Nested inner arch (creates the tracery double-arch look)
    float2 archP2 = rp8 - float2(r1 + 0.015, 0.0);
    archP2 = gf_rot(-GF_PI * 0.5) * archP2;
    float arch2 = gf_archSDF(archP2, archW * 0.55, archH * 0.7);
    d = min(d, abs(arch2) - lw * 0.6);

    // Delicate spokes connecting rings (only in this zone)
    float spoke = abs(ra8b);  // angular distance from spoke center
    float spokeD = spoke * r - lw * 0.6;
    spokeD = max(spokeD, -(r - r1));
    spokeD = max(spokeD, r - r2);
    d = min(d, spokeD);

    // ════════════════════════════════════════════
    // ZONE 3: Scrollwork belt (0.28 — 0.46)
    // ════════════════════════════════════════════
    float r3 = 0.46 + 0.005 * sin(t * 0.35 + 2.0);
    d = min(d, abs(r - r3) - lw);

    // Fleur-de-lis / quatrefoil ornaments at 8 positions
    for (int i = 0; i < 8; i++) {
        float ia = float(i) * seg8;
        float ornR = 0.37;
        float2 oc = float2(cos(ia), sin(ia)) * ornR;
        float2 op = uv - oc;
        op = gf_rot(-ia) * op;

        // Paired arcs forming a heart/fleur shape (mirror on y)
        float2 opM = float2(op.x, abs(op.y));

        // Main lobe — arc curving outward
        float lobe1 = abs(length(opM - float2(0.015, 0.012)) - 0.022) - lw * 0.6;
        lobe1 = max(lobe1, -opM.x + 0.002);  // clip inner edge
        d = min(d, lobe1);

        // Inner counter-lobe — smaller arc curving inward
        float lobe2 = abs(length(opM - float2(-0.008, 0.008)) - 0.015) - lw * 0.5;
        lobe2 = max(lobe2, opM.x + 0.005);
        d = min(d, lobe2);

        // Central stem
        float stem = abs(op.y) - lw * 0.5;
        stem = max(stem, op.x - 0.035);
        stem = max(stem, -op.x - 0.025);
        d = min(d, stem);

        // Tip finial — small circle at outer end
        d = min(d, length(op - float2(0.035, 0.0)) - 0.005);

        // Base connecting to inner ring
        float base = abs(length(op + float2(0.02, 0.0)) - 0.025) - lw * 0.5;
        base = max(base, abs(op.y) - 0.018);
        base = max(base, op.x + 0.008);
        d = min(d, base);
    }

    // 16 small cusps on inner edge of scrollwork belt
    float seg16 = GF_TAU / 16.0;
    float ra16 = (angle + seg16 * 0.5) - seg16 * floor((angle + seg16 * 0.5) / seg16) - seg16 * 0.5;
    float2 rp16 = float2(cos(ra16), sin(ra16)) * r;
    float cusp = length((rp16 - float2(r2 + 0.01, 0.0)) * float2(1.0, 3.0)) - 0.012;
    d = min(d, abs(cusp) - lw * 0.5);

    // ════════════════════════════════════════════
    // ZONE 4: Outer tracery (0.46 — 0.68)
    // ════════════════════════════════════════════
    float r4 = 0.68;
    d = min(d, abs(r - r4) - lw * 1.2);

    // Large gothic arches — 4-fold with half-arch subdivisions
    float seg4 = GF_TAU / 4.0;
    float ra4 = (angle + seg4 * 0.5) - seg4 * floor((angle + seg4 * 0.5) / seg4) - seg4 * 0.5;
    float2 rp4 = float2(cos(ra4), sin(ra4)) * r;

    float2 oArchP = rp4 - float2(r3 + 0.01, 0.0);
    oArchP = gf_rot(-GF_PI * 0.5) * oArchP;
    float oArch = gf_archSDF(oArchP, 0.16, (r4 - r3) * 0.9);
    d = min(d, abs(oArch) - lw);

    // Sub-arches (two smaller ones inside each big arch)
    float2 subL = oArchP - float2(-0.04, 0.0);
    float subArchL = gf_archSDF(subL, 0.06, (r4 - r3) * 0.55);
    d = min(d, abs(subArchL) - lw * 0.7);

    float2 subR = oArchP - float2(0.04, 0.0);
    float subArchR = gf_archSDF(subR, 0.06, (r4 - r3) * 0.55);
    d = min(d, abs(subArchR) - lw * 0.7);

    // Trefoil at apex of each big arch
    float2 tP = oArchP - float2(0.0, (r4 - r3) * 0.65);
    float trefoil = 1e5;
    for (int j = 0; j < 3; j++) {
        float ta = float(j) * GF_TAU / 3.0 - GF_PI * 0.5;
        float2 tc = float2(cos(ta), sin(ta)) * 0.016;
        trefoil = min(trefoil, length(tP - tc) - 0.012);
    }
    trefoil = max(trefoil, -(oArch + lw * 2.0));  // keep inside arch
    d = min(d, abs(trefoil) - lw * 0.5);

    // Diagonal spokes in outer zone (8-fold)
    float ra8c = (angle + seg8 * 0.5 + seg8 * 0.5) - seg8 * floor((angle + seg8 * 0.5 + seg8 * 0.5) / seg8) - seg8 * 0.5;
    float dSpoke = abs(ra8c) * r - lw * 0.5;
    dSpoke = max(dSpoke, -(r - r3));
    dSpoke = max(dSpoke, r - r4);
    d = min(d, dSpoke);

    // ════════════════════════════════════════════
    // ZONE 5: Corner filigree (using mirror coords)
    // ════════════════════════════════════════════
    // Elegant arcs sweeping from edges
    float cArc1 = abs(length(p - float2(0.82, 0.0)) - 0.48) - lw * 1.0;
    float cArc2 = abs(length(p - float2(0.0, 0.82)) - 0.48) - lw * 1.0;
    cArc1 = max(cArc1, -(p.y - 0.25));
    cArc1 = max(cArc1, p.y - 0.72);
    cArc2 = max(cArc2, -(p.x - 0.25));
    cArc2 = max(cArc2, p.x - 0.72);
    d = min(d, cArc1);
    d = min(d, cArc2);

    // Corner spiral flourishes
    float2 cp = p - float2(0.58, 0.58);
    float cr = length(cp);
    float ca = atan2(cp.y, cp.x);
    float cSpiral = abs(cr - 0.015 * (ca / GF_PI + 1.5)) - lw * 0.8;
    cSpiral = max(cSpiral, cr - 0.10);
    d = min(d, cSpiral);

    // Mirror corner spiral
    float2 cp2 = float2(cp.y, cp.x);
    cr = length(cp2);
    ca = atan2(cp2.y, cp2.x);
    cSpiral = abs(cr - 0.015 * (ca / GF_PI + 1.5)) - lw * 0.8;
    cSpiral = max(cSpiral, cr - 0.10);
    d = min(d, cSpiral);

    // ════════════════════════════════════════════
    // ACCENTS: Dot ornaments at structural intersections
    // ════════════════════════════════════════════
    for (int k = 0; k < 8; k++) {
        float da = float(k) * seg8;
        // Dots on inner ring
        d = min(d, length(uv - float2(cos(da), sin(da)) * r1) - 0.005);
        // Dots on mid ring
        d = min(d, length(uv - float2(cos(da), sin(da)) * r2) - 0.006);
        // Dots on outer ring
        d = min(d, length(uv - float2(cos(da), sin(da)) * r3) - 0.005);
        // Offset dots
        float offA = da + seg8 * 0.5;
        d = min(d, length(uv - float2(cos(offA), sin(offA)) * midR) - 0.004);
        d = min(d, length(uv - float2(cos(offA), sin(offA)) * r4) - 0.005);
    }

    return d;
}

// Reveal from center outward
static float gf_reveal(float2 uv, float t) {
    float r = length(uv);
    float edge = t * 0.25;  // speed of reveal
    float mask = smoothstep(edge, edge - 0.15, r);
    // Fully revealed after a while
    mask = max(mask, smoothstep(4.0, 5.5, t));
    return mask;
}

fragment float4 fs_gothic_filigree(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    // No mouse rotation in screensaver mode

    float t = u.time;
    float d = gf_filigree(uv, t);
    float rev = gf_reveal(uv, t);

    // ── Anti-aliased line from SDF ──
    float px = 1.2 / min(u.resolution.x, u.resolution.y);
    float line = 1.0 - smoothstep(0.0, px * 1.8, d);

    // ── Subtle glow ──
    float gSig = 0.014 * GF_GLOW;
    float glow = exp(-d * d / (gSig * gSig * 2.0)) * 0.32;
    float outerGlow = exp(-d * d / (gSig * gSig * 10.0)) * 0.10;

    // ── Color ──
    float3 gold = float3(0.90, 0.72, 0.34);
    float3 amber = float3(0.78, 0.55, 0.20);
    float3 pale = float3(1.0, 0.94, 0.76);
    float3 bronze = float3(0.45, 0.28, 0.10);

    float r = length(uv);
    float ang = atan2(uv.y, uv.x);
    float cv = sin(ang * 4.0 + r * 6.0) * 0.5 + 0.5;
    float3 lineCol = mix(amber, gold, cv);
    lineCol = mix(lineCol, pale, line * 0.25);

    // ── Background ──
    float3 bg = float3(0.028, 0.024, 0.022);

    // ── Composite ──
    float3 col = bg;
    col += bronze * outerGlow * rev;
    col += amber * 0.5 * glow * rev;
    col = mix(col, lineCol, line * rev);

    // Vignette
    float vig = smoothstep(0.0, 0.55, 1.0 - dot(uv * 0.75, uv * 0.75));
    col *= 0.55 + 0.45 * vig;

    // Gentle pulse once fully revealed
    col *= 1.0 + 0.025 * sin(t * 0.35) * smoothstep(7.0, 10.0, t);

    col = clamp(col, 0.0, 1.0);
    col = pow(col, float3(0.96));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
