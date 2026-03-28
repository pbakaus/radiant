#include "../Common.metal"

// ─── Synth Ribbon: Flowing metallic ribbons twisting in 3D, 80s chrome ───
// Ported from static/synth-ribbon.html
// Strategy: For each pixel, evaluate multiple ribbon spines as parametric
// curves. Compute distance from pixel to the projected ribbon surface.
// Chrome coloring via surface normal angle approximation.

constant int SR_RIBBON_COUNT = 4;
constant int SR_SEGMENTS = 40;
constant float SR_FOCAL = 600.0;
constant float SR_CAMERA_Z = -400.0;
constant float SR_PI = 3.14159265;

// ── Ribbon parameters (deterministic pseudo-random per ribbon) ──
static float sr_hash(float n) {
    return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

// ── Project 3D to 2D ──
static float3 sr_project(float3 p, float2 halfRes) {
    float dz = p.z - SR_CAMERA_Z;
    dz = max(dz, 1.0);
    float scale = SR_FOCAL / dz;
    return float3(halfRes.x + p.x * scale,
                  halfRes.y + p.y * scale,
                  dz);
}

// ── Chrome color from normal angle and depth ──
static float3 sr_chrome(float normalAngle, float ribbonHue, float depth, float t) {
    float specular = pow(sin(normalAngle * SR_PI), 2.5);
    float hueShift = ribbonHue + normalAngle * 2.0;
    float band = normalAngle * 5.0 + hueShift * 0.3;

    float pink = max(0.0, sin(band * 0.8) * 0.5 + 0.5);
    float cyan = max(0.0, sin(band * 0.8 + 2.5) * 0.5 + 0.5);
    float purple = max(0.0, sin(band * 0.8 + 4.5) * 0.5 + 0.5);

    float r = 0.08 + specular * (0.5 * pink + 0.3 * purple + 0.2);
    float g = 0.03 + specular * (0.6 * cyan + 0.1 * pink);
    float b = 0.1 + specular * (0.5 * cyan + 0.4 * purple + 0.15);

    // Highlight
    float highlight = pow(specular, 3.0);
    r += highlight * 1.0;
    g += highlight * 0.4;
    b += highlight * 0.7;

    // Rim glow
    float rim = pow(1.0 - specular, 2.5) * 0.4;
    r += rim * 0.1;
    g += rim * 0.8;
    b += rim * 1.0;

    // Depth fog
    float fogAmount = saturate((depth - 200.0) / 800.0);
    r = r * (1.0 - fogAmount * 0.7) + 0.02 * fogAmount;
    g = g * (1.0 - fogAmount * 0.6) + 0.03 * fogAmount;
    b = b * (1.0 - fogAmount * 0.4) + 0.08 * fogAmount;

    return saturate(float3(r, g, b));
}

fragment float4 fs_synth_ribbon(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 pixel = in.pos.xy;
    float t = u.time * 0.012 * 60.0; // match ~0.012 per frame at 60fps
    float2 halfRes = res * 0.5;

    float3 col = float3(0.0);
    float closestDepth = 9999.0;

    for (int ri = 0; ri < SR_RIBBON_COUNT; ri++) {
        float fi = float(ri);
        float seed = fi * 73.1;

        // Ribbon parameters
        float phaseX = sr_hash(seed + 1.0) * SR_PI * 2.0;
        float phaseY = sr_hash(seed + 2.0) * SR_PI * 2.0;
        float phaseZ = sr_hash(seed + 3.0) * SR_PI * 2.0;
        float freqX = 0.25 + sr_hash(seed + 4.0) * 0.5;
        float freqY = 0.2 + sr_hash(seed + 5.0) * 0.35;
        float freqZ = 0.15 + sr_hash(seed + 6.0) * 0.3;
        float ampX = 250.0 + sr_hash(seed + 7.0) * 300.0;
        float ampY = 120.0 + sr_hash(seed + 8.0) * 200.0;
        float ampZ = 100.0 + sr_hash(seed + 9.0) * 200.0;
        float twistFreq = 1.2 + sr_hash(seed + 10.0) * 2.5;
        float twistPhase = sr_hash(seed + 11.0) * SR_PI * 2.0;
        float hue = fi / float(SR_RIBBON_COUNT) * SR_PI * 2.0;
        float baseWidth = 35.0 + sr_hash(seed + 12.0) * 50.0;
        float speed = 0.25 + sr_hash(seed + 13.0) * 0.35;
        float zOffset = (fi - float(SR_RIBBON_COUNT) * 0.5) * 100.0;

        float tSpeed = t * speed;

        // Sample ribbon spine at many points, find closest projected distance
        for (int s = 0; s < SR_SEGMENTS; s++) {
            float t0 = float(s) / float(SR_SEGMENTS);
            float param = (t0 - 0.5) * 2.0;

            float px = sin(param * 3.0 * freqX + phaseX + tSpeed * 0.7) * ampX;
            float py = sin(param * 2.5 * freqY + phaseY + tSpeed * 0.5) * ampY;
            float pz = param * 500.0 + zOffset +
                        sin(param * 2.0 * freqZ + phaseZ + tSpeed * 0.3) * ampZ + 500.0;

            float twist = param * twistFreq * 3.0 + tSpeed * 2.0 + twistPhase;
            twist += sin(param * 5.0 + tSpeed) * 0.5;

            float absParam = abs(param);
            float widthFactor = cos(absParam * SR_PI * 0.5);
            widthFactor = widthFactor * widthFactor;
            widthFactor = max(0.02, widthFactor);
            float ribbonWidth = baseWidth * widthFactor;

            // Ribbon cross-section: two edge points
            float edgeX = cos(twist) * ribbonWidth;
            float edgeY = sin(twist) * ribbonWidth;

            // Project spine center
            float3 center3D = float3(px, py, pz);
            float3 projCenter = sr_project(center3D, halfRes);

            // Project both edges
            float3 edge1_3D = float3(px - edgeX, py - edgeY, pz);
            float3 edge2_3D = float3(px + edgeX, py + edgeY, pz);
            float3 projE1 = sr_project(edge1_3D, halfRes);
            float3 projE2 = sr_project(edge2_3D, halfRes);

            // Distance from pixel to the line segment between projected edges
            float2 e1 = projE1.xy;
            float2 e2 = projE2.xy;
            float2 seg = e2 - e1;
            float segLen2 = dot(seg, seg);
            float tParam = 0.5;
            if (segLen2 > 0.01) {
                tParam = saturate(dot(pixel - e1, seg) / segLen2);
            }
            float2 closest = e1 + seg * tParam;
            float dist = length(pixel - closest);

            // Ribbon width in screen space
            float screenWidth = length(e2 - e1);
            if (screenWidth < 0.5) continue;

            // Normalized distance across ribbon (for chrome shading)
            float normalAngle = tParam; // 0=edge1, 1=edge2

            // Glow falloff
            float halfW = screenWidth * 0.5;
            float ribbonGlow = smoothstep(halfW + 3.0, halfW * 0.3, dist);
            if (ribbonGlow < 0.001) continue;

            float depth = projCenter.z;
            float depthAlpha = max(0.2, 1.0 - (depth - 100.0) / 1000.0);

            float3 chrome = sr_chrome(normalAngle, hue + t * 0.005, depth, t);
            float alpha = ribbonGlow * depthAlpha * (0.6 + widthFactor * 0.4);

            col += chrome * alpha * 0.15;
        }
    }

    // Background: subtle radial gradient
    float2 uv = pixel / res - 0.5;
    float bgGrad = 1.0 - length(uv) * 1.0;
    float3 bg = mix(float3(0.039), float3(0.078, 0.063, 0.102), saturate(bgGrad));
    col += bg;

    // Subtle grid
    float2 gridUV = fract(pixel / 50.0);
    float gridLine = smoothstep(0.02, 0.0, min(gridUV.x, gridUV.y));
    col += float3(0.235, 0.118, 0.314) * gridLine * 0.02;

    col = hue_rotate(col, u.hue_shift);
    return float4(saturate(col), 1.0);
}
