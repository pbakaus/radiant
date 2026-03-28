#include "../Common.metal"

// ─── Glitter Storm: Tumbling reflective flakes catching rotating spotlights ───
// Ported from static/glitter-storm.html
// Approach: Per-pixel evaluate a grid of pseudo-random particles with
// 3D tumbling normals and specular highlights from orbiting lights.

constant float GS_LIGHT_SPEED = 0.45;       // spotlight rotation speed
constant float GS_SPECULAR_THRESHOLD = 0.92;// dot product threshold for sparkle
constant float GS_GLOW_RADIUS = 3.5;        // glow halo multiplier
constant float GS_DRIFT_SPEED = 0.15;       // particle drift speed
constant float GS_NUM_CELLS = 48.0;         // grid cells per axis (density proxy)

// Palette: hot pink, gold, rose gold, silver, magenta, light pink, warm gold, cool silver
static float3 gs_palette(float idx) {
    float3 colors[8] = {
        float3(1.0,  0.078, 0.576),  // hot pink
        float3(1.0,  0.843, 0.0),    // gold
        float3(0.718, 0.431, 0.475), // rose gold
        float3(0.753, 0.753, 0.753), // silver
        float3(1.0,  0.0,   1.0),    // magenta
        float3(1.0,  0.431, 0.686),  // light pink
        float3(0.863, 0.698, 0.196), // warm gold
        float3(0.843, 0.843, 0.922)  // cool silver
    };
    int i = int(idx) % 8;
    return colors[i];
}

// Hash functions
static float gs_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float2 gs_hash2(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 19.19);
    return fract((p3.xx + p3.yz) * p3.zx);
}

// 3D rotating spotlight directions
static float3 gs_light_dir(int idx, float time) {
    float theta, dPhi;
    float phi0;
    if (idx == 0)      { theta = 0.70; phi0 = 0.0;  dPhi =  0.45; }
    else if (idx == 1) { theta = 0.85; phi0 = 2.09; dPhi = -0.31; }
    else               { theta = 0.60; phi0 = 4.19; dPhi =  0.22; }

    float phi = phi0 + dPhi * GS_LIGHT_SPEED * time;
    float st = sin(theta);
    return float3(st * cos(phi), st * sin(phi), cos(theta));
}

fragment float4 fs_glitter_storm(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 px = in.pos.xy;
    float2 uv = px / u.resolution;
    float2 centered = (px - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;

    // Background: dark with subtle warm bloom
    float3 col = float3(0.039, 0.039, 0.039);

    // Wandering background bloom (pink/magenta)
    float2 bloomPos = float2(0.5 + sin(t * 0.14) * 0.22, 0.5 + cos(t * 0.11) * 0.20);
    float bloomDist = length(centered - (bloomPos - 0.5));
    col += float3(0.353, 0.0, 0.196) * smoothstep(0.7, 0.0, bloomDist) * 0.10;
    col += float3(0.196, 0.0, 0.275) * smoothstep(1.0, 0.0, bloomDist) * 0.04;

    // Warm dark tint
    col += float3(0.078, 0.020, 0.047) * 0.15;

    // Get light directions
    float3 lights[3];
    lights[0] = gs_light_dir(0, t);
    lights[1] = gs_light_dir(1, t);
    lights[2] = gs_light_dir(2, t);

    // Evaluate particles via grid cells
    float cellSize = 1.0 / GS_NUM_CELLS;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 cellUV = floor(uv / cellSize) + float2(float(dx), float(dy));
            float2 cellId = cellUV;
            float2 cellOrigin = cellUV * cellSize;

            // Hash for this cell's particle properties
            float h0 = gs_hash(cellId);
            float2 h12 = gs_hash2(cellId + 100.0);

            // Particle position (drifting)
            float2 ppos = cellOrigin + float2(h0, h12.x) * cellSize;
            ppos += float2(
                sin(t * GS_DRIFT_SPEED * 0.3 + h0 * 6.28) * cellSize * 0.3,
                cos(t * GS_DRIFT_SPEED * 0.2 + h12.y * 6.28) * cellSize * 0.2
            );

            // Distance from pixel to particle
            float2 delta = uv - ppos;
            float dist = length(delta * u.resolution);

            // Particle z-depth (affects size and brightness)
            float z = h12.y;
            float baseRadius = (1.0 + z * 1.8) * 0.5;

            // Skip if too far
            if (dist > baseRadius * GS_GLOW_RADIUS * 3.0) continue;

            // Tumbling disc normal
            float theta = h0 * 6.28 + t * ((h12.x - 0.5) * 3.2);
            float phi = h12.y * 6.28 + t * ((gs_hash(cellId + 50.0) - 0.5) * 2.8);
            float3 normal = float3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta));

            // Specular from each light
            float specMax = 0.0;
            float3 specCol = gs_palette(h0 * 8.0);
            for (int li = 0; li < 3; li++) {
                float d = abs(dot(normal, lights[li]));
                if (d > GS_SPECULAR_THRESHOLD) {
                    float s = (d - GS_SPECULAR_THRESHOLD) / (1.0 - GS_SPECULAR_THRESHOLD);
                    s = s * s * s * s;
                    s *= 4.0; // drive past 1 for vivid flare
                    specMax = max(specMax, s);
                }
            }

            float3 particleCol = specCol;
            float alpha;

            if (specMax > 0.015) {
                // Bright sparkle
                float3 brightCol = mix(specCol, float3(1.0), clamp(specMax, 0.0, 1.0) * 0.4);
                alpha = min(0.92, 0.55 + z * 0.4 + specMax * 0.25);

                // Glow halo
                if (specMax > 0.3) {
                    float glowR = baseRadius * (1.5 + specMax * 1.5);
                    float glowA = min(specMax * 0.35, 0.5);
                    float glow = smoothstep(glowR, 0.0, dist) * glowA;
                    col += brightCol * glow;

                    // Star-cross flare for very bright
                    if (specMax > 0.8) {
                        float flareAngle = gs_hash(cellId + 200.0) * 3.14159;
                        float2 flareDir1 = float2(cos(flareAngle), sin(flareAngle));
                        float2 flareDir2 = float2(-flareDir1.y, flareDir1.x);
                        float starLen = glowR * 1.8;
                        float starA = min((specMax - 0.8) * 1.5, 0.6);
                        // Cross flare via projected distance to line
                        float line1 = abs(dot(delta * u.resolution, float2(-flareDir1.y, flareDir1.x)));
                        float line2 = abs(dot(delta * u.resolution, float2(-flareDir2.y, flareDir2.x)));
                        float flare1 = smoothstep(baseRadius * 0.4, 0.0, line1) *
                                       smoothstep(starLen, 0.0, abs(dot(delta * u.resolution, flareDir1)));
                        float flare2 = smoothstep(baseRadius * 0.4, 0.0, line2) *
                                       smoothstep(starLen, 0.0, abs(dot(delta * u.resolution, flareDir2)));
                        col += brightCol * (flare1 + flare2) * starA;
                    }
                }

                // Disc body (elliptical due to tumbling)
                float sx = max(0.12, abs(cos(phi)));
                float sy = max(0.12, abs(cos(theta)));
                float2 scaledDelta = delta * u.resolution;
                float cosPhi = cos(phi), sinPhi = sin(phi);
                float2 rotDelta = float2(cosPhi * scaledDelta.x + sinPhi * scaledDelta.y,
                                         -sinPhi * scaledDelta.x + cosPhi * scaledDelta.y);
                float ellipseDist = length(rotDelta / float2(sx, sy));
                float discAlpha = smoothstep(baseRadius, baseRadius * 0.3, ellipseDist) * alpha;
                col += brightCol * discAlpha;
            } else {
                // Dim ambient flake
                alpha = (0.55 + z * 0.4) * 0.55;
                if (alpha < 0.05) continue;
                float discFade = smoothstep(baseRadius, 0.0, dist);
                col += particleCol * discFade * alpha * 0.3;
            }
        }
    }

    // Vignette
    float vDist = length(centered);
    float vig = smoothstep(0.0, 0.75, vDist);
    col *= 1.0 - vig * 0.88;

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
