#include "../Common.metal"

// ─── Diamond Caustics: Prismatic fire through a brilliant-cut diamond ───
// Ported from static/diamond-caustics.html

constant float DC_PI = 3.14159265359;
constant float DC_TAU = 6.28318530718;
constant float DC_ROTATION_SPEED = 0.5;
constant float DC_BRILLIANCE = 1.0;

// ── GLSL-compatible mod (always positive for positive y) ──
static float dc_modf(float x, float y) { return x - y * floor(x / y); }
static float2 dc_mod2(float2 x, float2 y) { return x - y * floor(x / y); }

// ── Rotation matrix ──
static float2x2 dc_rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, -s), float2(s, c));
}

// ── Hash for randomness ──
static float dc_hash(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p.yx + 19.19);
    return fract((p.x + p.y) * p.x);
}

// ── Smooth noise ──
static float dc_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = dc_hash(i);
    float b = dc_hash(i + float2(1.0, 0.0));
    float c = dc_hash(i + float2(0.0, 1.0));
    float d = dc_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Hexagonal distance field ──
static float4 dc_hexGrid(float2 p) {
    float2 s = float2(1.0, 1.7320508);
    float2 h = s * 0.5;

    float2 a = dc_mod2(p, s) - h;
    float2 b = dc_mod2(p - h, s) - h;

    float2 ga = (dot(a, a) < dot(b, b)) ? a : b;
    float2 cellId = p - ga;

    float2 ab = abs(ga);
    float hexDist = max(dot(ab, normalize(float2(1.0, 1.7320508))), ab.x);

    return float4(ga, hexDist, dc_hash(cellId));
}

// ── Triangular grid for facet patterns ──
static float dc_triGrid(float2 p) {
    float2 q = float2(p.x + p.y * 0.57735, p.y * 1.1547);
    float2 f = fract(q);
    float edge = min(min(f.x, f.y), abs(1.0 - f.x - f.y));
    return edge;
}

// ── Diamond facet SDF — brilliant cut top-down view ──
static float dc_brilliantFacets(float2 uv, float time) {
    float r = length(uv);
    float a = atan2(uv.y, uv.x);

    // Table facet
    float table = smoothstep(0.12, 0.11, r);

    // Star facets
    float starAngle = dc_modf(a + DC_PI / 8.0, DC_PI / 4.0) - DC_PI / 8.0;
    float starR = r - 0.18;
    float star = abs(starAngle) * 8.0 / DC_PI;
    float starEdge = smoothstep(0.01, 0.0, abs(starR) - star * 0.08);

    // Kite facets
    float kiteAngle = dc_modf(a, DC_PI / 4.0) - DC_PI / 8.0;
    float kiteEdge = smoothstep(0.01, 0.0, abs(kiteAngle) * r * 6.0 - 0.02);
    float kiteRing = smoothstep(0.01, 0.0, abs(r - 0.28) - 0.005);

    // Upper girdle facets
    float ugAngle = dc_modf(a, DC_PI / 8.0) - DC_PI / 16.0;
    float ugEdge = smoothstep(0.01, 0.0, abs(ugAngle) * r * 10.0 - 0.02);
    float ugRing = smoothstep(0.01, 0.0, abs(r - 0.38) - 0.005);

    // Girdle outline
    float girdle = smoothstep(0.01, 0.0, abs(r - 0.45) - 0.008);

    // Combine facet edges
    float edges = max(max(starEdge, kiteEdge), max(ugEdge, girdle));
    edges = max(edges, kiteRing);
    edges = max(edges, ugRing);

    // Radial lines every 22.5 degrees
    float radial16 = dc_modf(a, DC_PI / 8.0) - DC_PI / 16.0;
    float radLine16 = smoothstep(0.008, 0.0, abs(radial16) * r * 4.0 - 0.004);
    radLine16 *= step(0.12, r) * step(r, 0.46);

    // Radial lines every 45 degrees
    float radial8 = dc_modf(a + DC_PI / 8.0, DC_PI / 4.0) - DC_PI / 8.0;
    float radLine8 = smoothstep(0.006, 0.0, abs(radial8) * r * 5.0 - 0.003);
    radLine8 *= step(0.12, r) * step(r, 0.46);

    edges = max(edges, max(radLine16 * 0.5, radLine8));

    return edges;
}

// ── Prismatic spectral color ──
static float3 dc_spectral(float t) {
    t = fract(t);
    float3 c = float3(0.0);
    c.r = smoothstep(0.0, 0.15, t) - smoothstep(0.35, 0.5, t);
    c.r += smoothstep(0.8, 0.95, t);
    c.g = smoothstep(0.15, 0.35, t) - smoothstep(0.55, 0.75, t);
    c.b = smoothstep(0.4, 0.6, t) - smoothstep(0.75, 0.95, t);
    c = pow(c, float3(0.6));
    return c * 3.0;
}

// ── Diamond caustic ──
static float dc_diamondCaustic(float2 uv, float time, float scale, float rotation) {
    float2 p = dc_rot(rotation) * uv * scale;

    float4 hex = dc_hexGrid(p);
    float cellRand = hex.w;

    float facetAngle = cellRand * DC_TAU + time * 0.3;
    float2 refractV = float2(cos(facetAngle), sin(facetAngle)) * 0.3;

    float2 displaced = p + refractV * (1.0 + 0.5 * sin(time * 0.7 + cellRand * 10.0));

    float4 hex2 = dc_hexGrid(displaced * 1.5);

    float edgeDist = hex.z;
    float caustic = 1.0 - smoothstep(0.0, 0.4, edgeDist);

    float fold = 1.0 - smoothstep(0.0, 0.25, hex2.z);
    fold = pow(fold, 2.0);

    float interference = sin(displaced.x * 8.0 + time * 0.5) * sin(displaced.y * 8.0 - time * 0.4);
    interference = pow(abs(interference), 1.5) * 0.5;

    return caustic * 0.3 + fold * 0.5 + interference * 0.2;
}

// ── Scintillation ──
static float dc_scintillation(float2 uv, float time) {
    float sparkle = 0.0;

    for (float i = 0.0; i < 3.0; i++) {
        float sc = 5.0 + i * 4.0;
        float2 grid = floor(uv * sc);
        float2 f = fract(uv * sc) - 0.5;

        float h = dc_hash(grid + i * 100.0);
        float phase = h * DC_TAU + time * (1.5 + h * 2.0);

        float flash = pow(max(sin(phase), 0.0), 48.0);

        float dist = length(f);
        float point = smoothstep(0.15, 0.0, dist);

        sparkle += flash * point * (1.0 - i * 0.25);
    }

    return sparkle;
}

// ── Star burst ──
static float dc_starBurst(float2 uv, float time) {
    float r = length(uv);
    float a = atan2(uv.y, uv.x);

    float star4 = pow(abs(cos(a * 2.0)), 64.0) / (r * 20.0 + 1.0);
    float star6 = pow(abs(cos(a * 3.0)), 64.0) / (r * 25.0 + 1.0);

    return (star4 + star6 * 0.5) * smoothstep(0.5, 0.0, r);
}

fragment float4 fs_diamond_caustics(VSOut in [[stage_in]],
                                     constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    // No mouse interaction for screensaver
    float t = u.time;
    float rotSpeed = DC_ROTATION_SPEED;
    float brilliance = DC_BRILLIANCE;

    // ── Gentle overall rotation ──
    float globalRot = t * rotSpeed * 0.1;
    float2 uvRot = dc_rot(globalRot) * uv;

    // ═══ LAYER 1: Faceted crystalline geometry ═══
    float facetPattern = dc_brilliantFacets(uvRot * 2.2, t);

    float tri1 = dc_triGrid(dc_rot(t * 0.05) * uv * 8.0);
    float tri2 = dc_triGrid(dc_rot(-t * 0.07 + 1.0) * uv * 12.0);
    float triEdges = smoothstep(0.04, 0.0, tri1) * 0.3 + smoothstep(0.03, 0.0, tri2) * 0.15;

    float4 mainHex = dc_hexGrid(dc_rot(t * 0.06) * uv * 6.0);
    float hexEdges = smoothstep(0.44, 0.40, mainHex.z) - smoothstep(0.40, 0.36, mainHex.z);
    float hexOutline = smoothstep(0.45, 0.43, mainHex.z) - smoothstep(0.43, 0.41, mainHex.z);

    // ═══ LAYER 2: Caustic light patterns ═══
    float c1 = dc_diamondCaustic(uv, t, 3.0, t * rotSpeed * 0.15);
    float c2 = dc_diamondCaustic(uv, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + DC_PI * 0.3);
    float c3 = dc_diamondCaustic(uv, t * 0.9 + 20.0, 8.0, t * rotSpeed * 0.08 + DC_PI * 0.7);

    float caustics = c1 * 0.5 + c2 * 0.3 + c3 * 0.2;
    caustics = pow(caustics, 1.3) * 3.5;

    // ═══ LAYER 3: Chromatic dispersion ═══
    float dispersion = 0.018 * (1.0 + caustics * 0.3);
    float dispAngle = t * rotSpeed * 0.3 + atan2(uv.y, uv.x) * 0.5;

    float2 rOff = float2(cos(dispAngle), sin(dispAngle)) * dispersion;
    float cR = dc_diamondCaustic(uv + rOff, t, 3.0, t * rotSpeed * 0.15);
    cR += dc_diamondCaustic(uv + rOff, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + DC_PI * 0.3) * 0.6;

    float2 gOff = float2(cos(dispAngle + DC_TAU / 3.0), sin(dispAngle + DC_TAU / 3.0)) * dispersion;
    float cG = dc_diamondCaustic(uv + gOff, t, 3.0, t * rotSpeed * 0.15);
    cG += dc_diamondCaustic(uv + gOff, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + DC_PI * 0.3) * 0.6;

    float2 bOff = float2(cos(dispAngle + DC_TAU * 2.0 / 3.0), sin(dispAngle + DC_TAU * 2.0 / 3.0)) * dispersion;
    float cB = dc_diamondCaustic(uv + bOff, t, 3.0, t * rotSpeed * 0.15);
    cB += dc_diamondCaustic(uv + bOff, t * 1.1 + 10.0, 5.0, -t * rotSpeed * 0.12 + DC_PI * 0.3) * 0.6;

    float3 chromatic = float3(cR, cG, cB);
    float chrDiff = abs(cR - cG) + abs(cG - cB) + abs(cB - cR);

    // ═══ LAYER 4: Spectral fire ═══
    float specPhase = atan2(cR - cG, cG - cB) / DC_TAU + 0.5;
    specPhase += t * 0.03 + length(uv) * 0.5;
    float3 fireColor = dc_spectral(specPhase);

    float specPhase2 = dc_noise(uvRot * 3.0 + t * 0.2) + t * 0.05;
    float3 fireColor2 = dc_spectral(specPhase2);

    // ═══ LAYER 5: Scintillation ═══
    float sparkle = dc_scintillation(uvRot, t * rotSpeed);

    float starTotal = 0.0;
    for (float i = 0.0; i < 4.0; i++) {
        float sc = 4.0 + i * 3.0;
        float2 grid = floor(dc_rot(i * 0.7 + t * 0.03) * uv * sc);
        float2 center = (grid + 0.5) / sc;
        center = dc_rot(-i * 0.7 - t * 0.03) * center;
        float h = dc_hash(grid + i * 77.0);
        float phase = h * DC_TAU + t * (1.0 + h);
        float flash = pow(max(sin(phase), 0.0), 24.0);
        float star = dc_starBurst((uv - center) * sc * 0.8, t) * flash;
        starTotal += star * 0.35;
    }

    // ═══ COMPOSITING ═══
    float3 col = float3(0.0);

    // Base: cool white caustic light
    float3 whiteLight = float3(0.92, 0.95, 1.0);
    col += whiteLight * caustics * 1.2;

    // Chromatic caustics
    col += chromatic * 0.5 * brilliance;

    // Prismatic fire
    float fireMask = smoothstep(0.03, 0.25, chrDiff) * caustics;
    col += fireColor * fireMask * 2.5 * brilliance;
    col += fireColor2 * caustics * 0.6 * brilliance;

    // Facet geometry overlay
    float3 facetColor = float3(0.7, 0.75, 0.85);
    float structureMask = smoothstep(0.1, 0.5, caustics);
    col += facetColor * facetPattern * 0.04 * structureMask;
    col += facetColor * triEdges * hexEdges * 0.03 * (0.3 + structureMask * 0.7);
    col += float3(0.8, 0.85, 0.95) * hexOutline * 0.025 * (0.2 + structureMask * 0.8);

    // Scintillation sparkles
    float3 sparkleColor = float3(1.0, 0.98, 0.95);
    col += sparkleColor * sparkle * 3.5 * brilliance;

    // Star bursts with spectral color
    float starSpec = fract(t * 0.15 + starTotal * 2.0);
    col += mix(float3(1.0, 0.97, 0.92), dc_spectral(starSpec), 0.5) * starTotal * 2.5 * brilliance;

    // Warm amber base tone
    float3 amber = float3(0.78, 0.58, 0.42);
    col += amber * caustics * 0.08;

    // Center diamond brilliance
    float centerGlow = smoothstep(0.6, 0.0, length(uv));
    col *= 0.8 + centerGlow * 0.8;

    // Occasional intense fire flash
    float flashPhase = sin(t * rotSpeed * 1.7 + uvRot.x * 4.0) *
                       cos(t * rotSpeed * 2.3 + uvRot.y * 3.0);
    float intenseFlash = pow(max(flashPhase, 0.0), 10.0) * 3.5;
    float flashSpec = fract(t * 0.2 + atan2(uvRot.y, uvRot.x) / DC_TAU);
    col += dc_spectral(flashSpec) * intenseFlash * centerGlow * brilliance;

    // Subtle animated prismatic sweep
    float sweep = sin(uv.x * 3.0 + uv.y * 2.0 + t * rotSpeed * 0.5);
    sweep = pow(max(sweep, 0.0), 4.0) * 0.35;
    col += dc_spectral(t * 0.1 + uv.x * 0.3) * sweep * brilliance;

    // Vignette
    float vig = 1.0 - dot(uv, uv) * 0.35;
    vig = max(vig, 0.0);
    col *= vig;

    // ACES filmic tone mapping
    col *= 2.2;
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);

    // Slight cool-warm contrast
    col = pow(col, float3(0.97, 0.98, 1.03));

    // Minimum ambient
    col += float3(0.008, 0.008, 0.012);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
