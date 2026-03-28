#include "../Common.metal"

// ─── Rubber Reality: Elastic membrane with deformed grid ───
// Ported from static/rubber-reality.html (already a GLSL shader, reimagined for Metal)

constant float RR_SPEED = 0.12;
constant float RR_AMPLITUDE = 1.0;
constant float RR_GRID_SCALE = 10.0;
constant float RR_LINE_WIDTH = 0.035;

// ── Smooth membrane height field ──
static float rr_membrane(float2 p, float t) {
    float val = 0.0;
    val += 0.6 * snoise(p * 0.8 + float2(t * 0.08, t * 0.06));
    val += 0.25 * snoise(p * 1.6 + float2(-t * 0.05, t * 0.09));
    val += 0.08 * snoise(p * 3.2 + float2(t * 0.07, -t * 0.04));
    return val;
}

fragment float4 fs_rubber_reality(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float minRes = min(res.x, res.y);
    float2 p = (in.pos.xy - res * 0.5) / minRes;
    float t = u.time * RR_SPEED;

    // Surface height
    float amp = RR_AMPLITUDE;
    float ht = rr_membrane(p, t) * amp;

    // Surface normal via finite differences
    float eps = 0.01;
    float hx = rr_membrane(p + float2(eps, 0.0), t) * amp;
    float hy = rr_membrane(p + float2(0.0, eps), t) * amp;
    float3 normal = normalize(float3((ht - hx) / eps, (ht - hy) / eps, 3.0));

    // Grid coordinates
    float2 gp = p * RR_GRID_SCALE;

    // Deformation displacement
    float dx = rr_membrane(p + float2(0.02, 0.0), t) - rr_membrane(p - float2(0.02, 0.0), t);
    float dy = rr_membrane(p + float2(0.0, 0.02), t) - rr_membrane(p - float2(0.0, 0.02), t);
    float2 deformedGP = gp + float2(dx, dy) * 1.8;

    // Anti-aliased grid lines
    float2 grid = abs(fract(deformedGP) - 0.5);
    float2 dgp_dx = dfdx(deformedGP);
    float2 dgp_dy = dfdy(deformedGP);
    float aaW = length(float2(dgp_dx.x, dgp_dy.x)) * 1.5;
    float aaH = length(float2(dgp_dx.y, dgp_dy.y)) * 1.5;

    float lineH = smoothstep(RR_LINE_WIDTH + aaW, RR_LINE_WIDTH - aaW, grid.x);
    float lineV = smoothstep(RR_LINE_WIDTH + aaH, RR_LINE_WIDTH - aaH, grid.y);
    float gridLine = max(lineH, lineV);

    // Intersection node dots
    float2 nearCenter = abs(fract(deformedGP) - 0.5);
    float nodeDist = length(nearCenter);
    float nodeAA = max(aaW, aaH);
    float nodeDot = smoothstep(0.14 + nodeAA, 0.09, nodeDist);

    // Lighting
    float3 lightDir = normalize(float3(0.3, 0.5, 1.0));
    float diffuse = max(dot(normal, lightDir), 0.0);
    float ambient = 0.3;
    float lighting = ambient + diffuse * 0.7;

    // Specular (soft rubber sheen)
    float3 viewDir = float3(0.0, 0.0, 1.0);
    float3 halfDir = normalize(lightDir + viewDir);
    float spec = pow(max(dot(normal, halfDir), 0.0), 30.0);

    // Color palette
    float3 bgColor = float3(0.035, 0.028, 0.022);
    float3 amberDark  = float3(0.35, 0.22, 0.08);
    float3 amberMid   = float3(0.70, 0.50, 0.20);
    float3 amberBright = float3(1.0, 0.82, 0.48);

    // Height-based color
    float htNorm = clamp(ht * 0.5 + 0.5, 0.0, 1.0);
    float3 gridColor = mix(amberDark, amberMid, smoothstep(0.25, 0.5, htNorm));
    gridColor = mix(gridColor, amberBright, smoothstep(0.6, 0.85, htNorm));
    gridColor *= lighting;
    gridColor += float3(1.0, 0.9, 0.65) * spec * 0.4;

    // Compose surface
    float3 surfaceColor = bgColor + float3(0.05, 0.03, 0.012) * (htNorm * lighting);
    float gridAlpha = gridLine * (0.35 + 0.45 * lighting);
    float3 col = mix(surfaceColor, gridColor, gridAlpha);

    // Node highlights
    col = mix(col, amberBright * lighting * 1.1, nodeDot * 0.5);

    // Warm subsurface glow in deformed areas
    float deformGlow = smoothstep(0.05, 0.5, abs(ht));
    col += float3(0.4, 0.22, 0.06) * deformGlow * 0.15 * (1.0 - gridAlpha);

    // Vignette
    float vig = 1.0 - smoothstep(0.35, 1.2, length(p));
    col *= 0.55 + 0.45 * vig;

    // Warmth adjustment
    col = pow(col, float3(0.95, 1.0, 1.08));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
