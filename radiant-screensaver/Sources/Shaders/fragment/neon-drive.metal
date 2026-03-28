#include "../Common.metal"

// ─── Neon Drive: Synthwave outrun horizon shader ───
// Ported from static/neon-drive.html

// Default parameter values (screensaver — no interactive controls)
constant float ND_SPEED = 1.0;
constant float ND_GLOW = 1.0;
constant float ND_HORIZON = 0.38;

// ── Hash / noise helpers ──
static float nd_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float nd_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = nd_hash(i);
    float b = nd_hash(i + float2(1.0, 0.0));
    float c = nd_hash(i + float2(0.0, 1.0));
    float d = nd_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Sun shape with layered glow ──
static float3 nd_sun(float2 uv, float t) {
    float2 sunPos = float2(0.0, ND_HORIZON + 0.18);
    float sunRadius = 0.12;
    float d = length(uv - sunPos);

    // Horizontal scanlines through the sun
    float scanline = 0.0;
    if (uv.y < sunPos.y && uv.y > sunPos.y - sunRadius) {
        float band = (sunPos.y - uv.y) / sunRadius;
        float lineSpacing = 0.028 + band * 0.06;
        // mod with positive-only input (uv.y + 0.001 is small positive offset, safe to use fmod)
        float lineY = uv.y + 0.001 - lineSpacing * floor((uv.y + 0.001) / lineSpacing);
        scanline = smoothstep(0.0, 0.003, lineY) * smoothstep(lineSpacing, lineSpacing - 0.003, lineY);
        scanline *= smoothstep(0.0, 0.4, band);
    }

    // Sun disc with gradient
    float sunMask = smoothstep(sunRadius + 0.003, sunRadius - 0.003, d);
    float3 sunColorTop = float3(1.0, 0.85, 0.1);
    float3 sunColorBot = float3(1.0, 0.15, 0.4);
    float sunGradient = smoothstep(sunPos.y + sunRadius, sunPos.y - sunRadius, uv.y);
    float3 sunCol = mix(sunColorTop, sunColorBot, sunGradient);
    sunCol *= sunMask;

    // Cut out scanline bands from lower half of sun
    sunCol *= mix(1.0, scanline, smoothstep(sunPos.y, sunPos.y - sunRadius, uv.y) * 0.85);

    // Multi-layered glow around the sun
    float glow1 = exp(-d * 4.0) * 0.5;
    float glow2 = exp(-d * 10.0) * 0.3;
    float glow3 = exp(-d * 25.0) * 0.2;
    float3 glowCol = float3(1.0, 0.3, 0.5) * glow1 +
                     float3(1.0, 0.6, 0.2) * glow2 +
                     float3(1.0, 0.9, 0.5) * glow3;

    return sunCol + glowCol;
}

// ── Sky gradient with stars ──
static float3 nd_sky(float2 uv, float t) {
    float skyY = (uv.y - ND_HORIZON) / (1.0 - ND_HORIZON);
    skyY = clamp(skyY, 0.0, 1.0);

    float3 colBot = float3(0.6, 0.05, 0.3);
    float3 colMid = float3(0.25, 0.02, 0.35);
    float3 colTop = float3(0.02, 0.01, 0.08);

    float3 col = mix(colBot, colMid, smoothstep(0.0, 0.35, skyY));
    col = mix(col, colTop, smoothstep(0.25, 0.85, skyY));

    // Horizon haze
    float hazeStrength = exp(-skyY * 8.0) * 0.7;
    col += float3(1.0, 0.4, 0.1) * hazeStrength;

    // Stars
    float starField = nd_hash(floor(uv * 200.0));
    float starMask = smoothstep(0.3, 0.9, skyY);
    float twinkle = sin(t * 2.0 + starField * 50.0) * 0.5 + 0.5;
    float star = smoothstep(0.992, 0.999, starField) * starMask * (0.5 + 0.5 * twinkle);
    col += float3(0.8, 0.7, 1.0) * star;

    // Add sun
    col += nd_sun(uv, t);

    return col;
}

// ── Perspective grid road ──
static float3 nd_grid(float2 uv, float t) {
    float roadY = ND_HORIZON - uv.y;
    if (roadY <= 0.0) return float3(0.0);

    float perspective = 1.5 / roadY;
    float worldX = uv.x * perspective;
    float worldZ = perspective;

    float speed = t * ND_SPEED * 3.0;
    worldZ += speed;

    // Z lines
    float zLine = abs(fract(worldZ * 0.5) - 0.5);
    float zLineWidth = clamp(perspective * 0.001, 0.01, 0.12);
    float zGrid = smoothstep(zLineWidth, 0.0, zLine);

    // X lines
    float xLine = abs(fract(worldX * 0.25) - 0.5);
    float xLineWidth = clamp(perspective * 0.0005, 0.006, 0.08);
    float xGrid = smoothstep(xLineWidth, 0.0, xLine);

    float gridVal = max(zGrid, xGrid);

    float fadeIn = smoothstep(0.0, 0.05, roadY);
    float proxBright = 0.5 + 0.5 * smoothstep(0.0, 0.4, roadY);

    float3 gridColor = float3(0.9, 0.1, 0.6);

    // Accent every 4th line with cyan
    float zMajor = abs(fract(worldZ * 0.125) - 0.5);
    float zMajorLine = smoothstep(zLineWidth * 0.5, 0.0, zMajor);
    float xMajor = abs(fract(worldX * 0.0625) - 0.5);
    float xMajorLine = smoothstep(xLineWidth * 0.5, 0.0, xMajor);
    float majorGrid = max(zMajorLine, xMajorLine);

    float3 accentColor = float3(0.1, 0.6, 1.0);
    gridColor = mix(gridColor, accentColor, majorGrid * 0.4);

    // Grid glow
    float zGlow = exp(-zLine * 20.0) * 0.25;
    float xGlow = exp(-xLine * 20.0) * 0.2;
    float gridGlow = max(zGlow, xGlow);

    float3 col = gridColor * gridVal * proxBright * fadeIn;
    col += gridColor * gridGlow * fadeIn * 0.7;

    // Ground base color
    float3 groundColor = float3(0.02, 0.01, 0.04);
    col += groundColor;

    // Horizon fog glow
    float fogBand = exp(-roadY * 10.0);
    col += float3(0.5, 0.1, 0.35) * fogBand * 0.5;

    return col;
}

// ── Side terrain / mountains ──
static float3 nd_mountains(float2 uv, float t) {
    if (uv.y < ND_HORIZON) return float3(0.0);

    float au = abs(uv.x);

    float m1 = nd_noise(float2(au * 3.0, 0.0)) * 0.08;
    float m2 = nd_noise(float2(au * 8.0, 1.0)) * 0.03;
    float m3 = nd_noise(float2(au * 20.0, 2.0)) * 0.01;
    float mountainHeight = m1 + m2 + m3;

    float sideMask = smoothstep(0.15, 0.5, au);
    mountainHeight *= sideMask;

    float mountainTop = ND_HORIZON + mountainHeight;
    float mountainMask = smoothstep(mountainTop + 0.005, mountainTop - 0.002, uv.y);

    float3 col = float3(0.015, 0.005, 0.03) * mountainMask;

    float edgeDist = abs(uv.y - mountainTop);
    float edgeGlow = exp(-edgeDist * 200.0) * sideMask;
    col += float3(0.6, 0.1, 0.5) * edgeGlow * 0.3;

    return col;
}

// ── Side grid ──
static float3 nd_sideGrid(float2 uv, float t) {
    float roadY = ND_HORIZON - uv.y;
    if (roadY <= 0.0) return float3(0.0);

    float perspective = 1.5 / roadY;
    float worldX = uv.x * perspective;
    float worldZ = perspective + t * ND_SPEED * 3.0;

    float zLine = abs(fract(worldZ * 0.5) - 0.5);
    float xLine = abs(fract(worldX * 0.25) - 0.5);

    float zLineWidth = clamp(perspective * 0.0008, 0.008, 0.08);
    float xLineWidth = clamp(perspective * 0.0004, 0.004, 0.06);

    float zGrid = smoothstep(zLineWidth, 0.0, zLine);
    float xGrid = smoothstep(xLineWidth, 0.0, xLine);
    float gridVal = max(zGrid, xGrid);

    float fadeIn = smoothstep(0.0, 0.05, roadY);

    float3 sideColor = float3(0.4, 0.05, 0.6);
    return sideColor * gridVal * fadeIn * 0.35;
}

// ── Sun reflection on road ──
static float3 nd_sunReflection(float2 uv, float t) {
    float roadY = ND_HORIZON - uv.y;
    if (roadY <= 0.0) return float3(0.0);

    float reflectWidth = 0.15 / (roadY * 3.0 + 0.3);
    float xDist = abs(uv.x);
    float reflStrength = exp(-xDist * xDist / (reflectWidth * reflectWidth * 0.02));

    float perspective = 1.5 / roadY;
    float worldZ = perspective + t * ND_SPEED * 3.0;
    float shimmer = nd_noise(float2(uv.x * 30.0, worldZ * 2.0)) * 0.5 + 0.5;

    float gradT = smoothstep(0.0, 0.25, roadY);
    float3 reflColor = mix(float3(1.0, 0.5, 0.2), float3(1.0, 0.15, 0.4), gradT);

    float fadeNear = smoothstep(0.35, 0.05, roadY);
    float fadeFar = smoothstep(0.0, 0.01, roadY);

    return reflColor * reflStrength * shimmer * fadeNear * fadeFar * 0.15;
}

// ── Center road line ──
static float3 nd_centerLine(float2 uv, float t) {
    float roadY = ND_HORIZON - uv.y;
    if (roadY <= 0.0) return float3(0.0);

    float perspective = 1.5 / roadY;
    float worldZ = perspective + t * ND_SPEED * 3.0;

    float dashPattern = step(0.5, fract(worldZ * 0.12));

    float lineWidth = 0.003 / (perspective * 0.05 + 0.1);
    lineWidth = clamp(lineWidth, 0.0005, 0.01);

    float lineMask = smoothstep(lineWidth, 0.0, abs(uv.x));
    float distFade = smoothstep(0.0, 0.02, roadY) * smoothstep(0.35, 0.05, roadY);

    return float3(0.9, 0.8, 0.6) * lineMask * dashPattern * distFade * 0.5;
}

// ── Road edge glow lines ──
static float3 nd_roadEdges(float2 uv, float t) {
    float roadY = ND_HORIZON - uv.y;
    if (roadY <= 0.0) return float3(0.0);

    float roadHalfWidth = roadY * 0.8 + 0.001;

    float leftEdge = abs(uv.x + roadHalfWidth);
    float rightEdge = abs(uv.x - roadHalfWidth);
    float edgeDist = min(leftEdge, rightEdge);

    float lineWidth = 0.002;
    float edgeLine = smoothstep(lineWidth, 0.0, edgeDist);
    float edgeGlow = exp(-edgeDist * 300.0) * 0.4;

    float distFade = smoothstep(0.0, 0.015, roadY) * smoothstep(0.35, 0.02, roadY);

    float3 edgeColor = float3(0.1, 0.7, 1.0);
    return edgeColor * (edgeLine + edgeGlow) * distFade;
}

// ── Atmospheric haze particles ──
static float nd_haze(float2 uv, float t) {
    float n1 = nd_noise(uv * 3.0 + float2(t * 0.1, 0.0));
    float n2 = nd_noise(uv * 7.0 + float2(0.0, t * 0.15));
    float n3 = nd_noise(uv * 15.0 + float2(t * 0.05, t * 0.08));
    return (n1 * 0.5 + n2 * 0.3 + n3 * 0.2);
}

// ── Vignette ──
static float nd_vignette(float2 uv) {
    float d = length(uv * float2(0.8, 1.0));
    return smoothstep(1.2, 0.4, d);
}

// ── CRT scanline effect (subtle) ──
static float nd_scanlines(float2 fragCoord) {
    return 0.95 + 0.05 * sin(fragCoord.y * 3.14159 * 1.5);
}

fragment float4 fs_neon_drive(VSOut in [[stage_in]],
                              constant CommonUniforms& u [[buffer(0)]]) {
    // No mouse — no vanishing point shift
    float2 uv = (in.pos.xy - u.resolution * 0.5) / u.resolution.y;
    float t = u.time;

    float3 col = float3(0.0);

    // Sky above horizon
    if (uv.y >= ND_HORIZON) {
        col = nd_sky(uv, t);

        // Mountain silhouettes
        float3 mtn = nd_mountains(uv, t);
        float mtnMask = step(0.001, mtn.r + mtn.g + mtn.b);
        col = mix(col, mtn, mtnMask * 0.7);
        col += mtn * 2.0 * (1.0 - mtnMask);
    }

    // Grid road below horizon
    col += nd_grid(uv, t);

    // Side grid
    col += nd_sideGrid(uv, t);

    // Sun reflection on road surface
    col += nd_sunReflection(uv, t);

    // Road edge glow
    col += nd_roadEdges(uv, t);

    // Center dashed line
    col += nd_centerLine(uv, t);

    // Atmospheric haze near horizon
    float horizonDist = abs(uv.y - ND_HORIZON);
    float hazeMask = exp(-horizonDist * 15.0);
    float hazeVal = nd_haze(uv, t);
    col += float3(0.5, 0.15, 0.4) * hazeVal * hazeMask * 0.15;

    // Global glow control
    col *= ND_GLOW;

    // Vignette
    col *= nd_vignette(uv);

    // Subtle scanlines for CRT feel
    col *= nd_scanlines(in.pos.xy);

    // Tone mapping
    col = col / (col + float3(0.8));
    col = pow(col, float3(0.95));

    // Very slight chromatic shift at edges
    float chromDist = length(uv * float2(0.5, 0.7));
    float chromShift = chromDist * 0.003;
    float3 finalCol;
    finalCol.r = col.r * (1.0 + chromShift * 2.0);
    finalCol.g = col.g;
    finalCol.b = col.b * (1.0 + chromShift * 2.0);

    finalCol = hue_rotate(finalCol, u.hue_shift);
    return float4(finalCol, 1.0);
}
