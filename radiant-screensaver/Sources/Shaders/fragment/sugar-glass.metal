#include "../Common.metal"

// ─── Sugar Glass: Caramelized sugar glass with Voronoi fracture patterns ───
// Ported from static/sugar-glass.html

// Default parameter values (screensaver — no interactive controls)
constant float SGL_CRACK_SPEED = 0.5;
constant float SGL_LIGHT_BLEED = 1.0;

// ── Hash functions ──
static float2 sgl_hash2(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)),
               dot(p, float2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453123);
}

static float sgl_hash1(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

// ── Voronoi with distance to nearest edge ──
static float3 sgl_voronoi(float2 p, float t) {
    float2 n = floor(p);
    float2 f = fract(p);

    float minDist = 8.0;
    float2 nearestCell = float2(0.0);
    float2 nearestPoint = float2(0.0);

    float2 g, o, diff;
    float d;

    g = float2(-1.0, -1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }
    g = float2(0.0, -1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }
    g = float2(1.0, -1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }

    g = float2(-1.0, 0.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }
    g = float2(0.0, 0.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }
    g = float2(1.0, 0.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }

    g = float2(-1.0, 1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }
    g = float2(0.0, 1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }
    g = float2(1.0, 1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearestCell = n + g; nearestPoint = diff; }

    // Second pass: find distance to nearest edge
    float minEdge = 8.0;

    g = float2(-1.0, -1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }
    g = float2(0.0, -1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }
    g = float2(1.0, -1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }

    g = float2(-1.0, 0.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }
    g = float2(0.0, 0.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }
    g = float2(1.0, 0.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }

    g = float2(-1.0, 1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }
    g = float2(0.0, 1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }
    g = float2(1.0, 1.0); o = sgl_hash2(n + g) * 0.5 + 0.25; o = 0.5 + 0.4 * sin(t * 0.3 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearestPoint, diff - nearestPoint) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearestPoint + diff), normalize(diff - nearestPoint))); }

    float cellId = sgl_hash1(nearestCell);
    return float3(sqrt(minDist), minEdge, cellId);
}

// ── Simpler Voronoi for micro fractures ──
static float sgl_voronoiEdge(float2 p, float t) {
    float2 n = floor(p);
    float2 f = fract(p);
    float minDist = 8.0;
    float2 nearPt = float2(0.0);
    float2 g, o, diff;
    float d;

    g = float2(-1.0, -1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(0.0, -1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(1.0, -1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(-1.0, 0.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(0.0, 0.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(1.0, 0.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(-1.0, 1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(0.0, 1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }
    g = float2(1.0, 1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f; d = dot(diff, diff);
    if (d < minDist) { minDist = d; nearPt = diff; }

    float minEdge = 8.0;
    g = float2(-1.0, -1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(0.0, -1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(1.0, -1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(-1.0, 0.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(0.0, 0.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(1.0, 0.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(-1.0, 1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(0.0, 1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }
    g = float2(1.0, 1.0); o = sgl_hash2(n + g); o = 0.5 + 0.35 * sin(t * 0.5 + 6.2831 * o); diff = g + o - f;
    if (dot(diff - nearPt, diff - nearPt) > 0.001) { minEdge = min(minEdge, dot(0.5 * (nearPt + diff), normalize(diff - nearPt))); }

    return minEdge;
}

fragment float4 fs_sugar_glass(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 p = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);

    float t = u.time * SGL_CRACK_SPEED;

    // Subtle heat shimmer distortion
    float2 shimmer = float2(
        sin(p.y * 12.0 + t * 2.3) * 0.003,
        cos(p.x * 10.0 + t * 1.7) * 0.003
    );
    p += shimmer;

    // Macro Voronoi fractures
    float2 macroUV = p * 3.5 + 0.5;
    float3 macro = sgl_voronoi(macroUV, t);
    float macroCenterDist = macro.x;
    float macroEdge = macro.y;
    float cellId = macro.z;

    // Micro fractures
    float microEdge = sgl_voronoiEdge(p * 9.0 + float2(3.7, 1.2), t * 0.7);

    // Time-varying crack widths
    float crackPulse = 0.5 + 0.3 * sin(t * 1.5) + 0.2 * sin(t * 2.7 + 1.0);
    float macroCrackWidth = 0.04 * crackPulse;
    float microCrackWidth = 0.025 * crackPulse;

    float macroCrack = 1.0 - smoothstep(0.0, macroCrackWidth, macroEdge);
    float microCrack = 1.0 - smoothstep(0.0, microCrackWidth, microEdge);

    float crack = macroCrack + microCrack * 0.4;
    crack = clamp(crack, 0.0, 1.0);

    float macroGlow = 1.0 - smoothstep(0.0, macroCrackWidth * 4.0, macroEdge);
    float microGlow = 1.0 - smoothstep(0.0, microCrackWidth * 3.0, microEdge);
    float glow = macroGlow * 0.7 + microGlow * 0.3;

    float cellThickness = 0.6 + 0.4 * cellId;
    float cellHueShift = cellId * 0.3;

    float3 amber = float3(0.78, 0.585, 0.424);
    float3 caramel = float3(0.831, 0.647, 0.455);
    float3 deepAmber = float3(0.29, 0.125, 0.0);

    float3 glassColor = mix(amber, caramel, cellHueShift);
    glassColor = mix(deepAmber, glassColor, cellThickness);

    float cellGrad = smoothstep(0.0, 0.5, macroCenterDist);
    glassColor = mix(glassColor * 1.1, glassColor * 0.85, cellGrad);

    float3 roseGold = float3(0.9, 0.65, 0.6);
    float refractTint = glow * (0.3 + 0.2 * sin(cellId * 12.0 + t * 0.8));
    glassColor = mix(glassColor, roseGold, refractTint * 0.25);

    float3 crackLight = float3(1.0, 0.91, 0.75);
    float3 crackBright = float3(1.0, 0.96, 0.9);
    float3 lightColor = mix(crackLight, crackBright, crack);

    float lightIntensity = crack * SGL_LIGHT_BLEED;
    float glowIntensity = glow * SGL_LIGHT_BLEED * 0.5;

    float3 col = glassColor;
    col = mix(col, lightColor * 0.8, glowIntensity);
    col = mix(col, lightColor, lightIntensity);

    float sss = 0.5 + 0.5 * sin(p.x * 3.0 + t * 0.5) * sin(p.y * 2.5 + t * 0.3);
    col += float3(0.05, 0.03, 0.01) * sss * cellThickness;

    // Vignette
    float vig = 1.0 - dot(p * 0.8, p * 0.8);
    vig = smoothstep(0.0, 1.0, vig);
    col *= 0.6 + 0.4 * vig;

    col = pow(col, float3(0.95));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
