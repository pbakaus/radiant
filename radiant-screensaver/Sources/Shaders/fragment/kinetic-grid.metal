#include "../Common.metal"

// ─── Kinetic Grid: Spring-connected deforming grid with wave propagation ───
// Ported from static/kinetic-grid.html
// Approach: Analytically compute grid node displacement from noise-driven
// impulse waves, then render spring connections as SDFs with tension coloring.

constant float KG_COLS = 40.0;
constant float KG_ROWS = 25.0;
constant float KG_MARGIN = 0.06;          // margin fraction
constant float KG_IMPULSE_INTERVAL = 2.5; // seconds between impulses
constant float KG_WAVE_SPEED = 0.4;       // wave propagation speed (UV/sec)
constant float KG_WAVE_DECAY = 3.0;       // wave amplitude decay rate
constant float KG_WAVE_AMP = 0.015;       // max displacement in UV
constant float KG_LINE_WIDTH = 0.0012;    // base line width
constant float KG_GLOW_WIDTH = 0.004;     // glow line width
constant float KG_NUM_WAVES = 4.0;        // simultaneous wave sources
constant float KG_BREATHE_SPEED = 0.8;    // breathing animation speed

// Hash
static float kg_hash(float s) {
    return fract(sin(s * 127.1 + 311.7) * 43758.5453);
}

// Compute displacement at a grid node from all active wave sources
static float2 kg_displacement(float2 restPos, float time) {
    float2 disp = float2(0.0);

    // Multiple wave sources cycling over time
    for (int w = 0; w < int(KG_NUM_WAVES); w++) {
        float fw = float(w);
        float waveCycle = KG_IMPULSE_INTERVAL * KG_NUM_WAVES;
        float waveTime = fmod(time + fw * KG_IMPULSE_INTERVAL, waveCycle);

        // Wave source position (from edges)
        float seed = floor((time + fw * KG_IMPULSE_INTERVAL) / waveCycle) * 17.0 + fw * 73.1;
        int edge = int(fmod(kg_hash(seed) * 4.0, 4.0));
        float edgePos = kg_hash(seed + 1.0);

        float2 sourcePos;
        float2 impulseDir;
        if (edge == 0)      { sourcePos = float2(KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN), KG_MARGIN); impulseDir = float2(0.0, 1.0); }
        else if (edge == 1) { sourcePos = float2(1.0 - KG_MARGIN, KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN)); impulseDir = float2(-1.0, 0.0); }
        else if (edge == 2) { sourcePos = float2(KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN), 1.0 - KG_MARGIN); impulseDir = float2(0.0, -1.0); }
        else                { sourcePos = float2(KG_MARGIN, KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN)); impulseDir = float2(1.0, 0.0); }

        // Wave front distance and amplitude
        float distFromSource = length(restPos - sourcePos);
        float waveFront = waveTime * KG_WAVE_SPEED;
        float distFromFront = distFromSource - waveFront;

        // Wave shape: sharp attack, smooth decay
        float wave = 0.0;
        if (distFromFront > -0.15 && distFromFront < 0.02) {
            float frontDist = (-distFromFront + 0.02) / 0.17;
            wave = frontDist * exp(-frontDist * 2.0);
        }

        // Decay over time
        float timeDecay = exp(-waveTime * KG_WAVE_DECAY * 0.5);

        // Strength variation
        float strength = (0.7 + kg_hash(seed + 2.0) * 0.6);

        // Radial displacement: push away from source
        float2 dir = restPos - sourcePos;
        float dirLen = length(dir);
        if (dirLen > 0.001) dir /= dirLen;

        disp += dir * wave * KG_WAVE_AMP * strength * timeDecay;
    }

    // Gentle baseline noise sway
    disp += float2(
        snoise(restPos * 2.0 + float2(time * 0.1, 0.0)) * 0.001,
        snoise(restPos * 2.0 + float2(0.0, time * 0.1)) * 0.001
    );

    return disp;
}

// Tension color ramp (resting dark brown -> orange -> hot white)
static float4 kg_tension_color(float tension) {
    float t = clamp(tension, 0.0, 1.0);
    float3 col;
    float a;

    if (t < 0.1) {
        float f = t / 0.1;
        col = float3(0.157 + f * 0.078, 0.055 + f * 0.031, 0.020 + f * 0.012);
        a = 0.25 + f * 0.1;
    } else if (t < 0.3) {
        float f = (t - 0.1) / 0.2;
        col = float3(0.235 + f * 0.471, 0.086 + f * 0.149, 0.031 + f * 0.031);
        a = 0.35 + f * 0.2;
    } else if (t < 0.55) {
        float f = (t - 0.3) / 0.25;
        col = float3(0.706 + f * 0.196, 0.235 + f * 0.235, 0.063 + f * 0.055);
        a = 0.55 + f * 0.2;
    } else if (t < 0.8) {
        float f = (t - 0.55) / 0.25;
        col = float3(0.902 + f * 0.098, 0.471 + f * 0.392, 0.118 + f * 0.353);
        a = 0.75 + f * 0.15;
    } else {
        float f = (t - 0.8) / 0.2;
        col = float3(1.0, 0.863 + f * 0.137, 0.471 + f * 0.471);
        a = 0.9 + f * 0.1;
    }

    return float4(col, a);
}

// SDF for a line segment
static float kg_line_sdf(float2 p, float2 a, float2 b) {
    float2 ba = b - a;
    float h = clamp(dot(p - a, ba) / dot(ba, ba), 0.0, 1.0);
    return length(p - a - ba * h);
}

fragment float4 fs_kinetic_grid(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 centered = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;

    // Grid spacing
    float spacingX = (1.0 - 2.0 * KG_MARGIN) / (KG_COLS - 1.0);
    float spacingY = (1.0 - 2.0 * KG_MARGIN) / (KG_ROWS - 1.0);
    float avgSpacing = (spacingX + spacingY) * 0.5;
    float tensionScale = 1.0 / (avgSpacing * 0.35);

    // Breathing
    float breathe = 0.85 + 0.15 * sin(t * KG_BREATHE_SPEED);

    // Background with trail persistence (dark warm)
    float3 col = float3(0.039, 0.031, 0.024);

    // Screen flash from impulses
    for (int w = 0; w < int(KG_NUM_WAVES); w++) {
        float fw = float(w);
        float waveCycle = KG_IMPULSE_INTERVAL * KG_NUM_WAVES;
        float waveTime = fmod(t + fw * KG_IMPULSE_INTERVAL, waveCycle);
        if (waveTime < 0.5) {
            float flash = exp(-waveTime * 8.0) * 0.04;
            col += float3(0.863, 0.392, 0.098) * flash;
        }
    }

    // Find nearest grid cell to limit work
    float2 gridUV = (uv - float2(KG_MARGIN)) / float2(spacingX, spacingY);
    int nearCol = int(clamp(round(gridUV.x), 0.0, KG_COLS - 1.0));
    int nearRow = int(clamp(round(gridUV.y), 0.0, KG_ROWS - 1.0));

    // Search radius in grid cells
    int searchR = 2;

    float3 glowAccum = float3(0.0);
    float3 coreAccum = float3(0.0);
    float3 nodeAccum = float3(0.0);

    for (int dr = -searchR; dr <= searchR; dr++) {
        for (int dc = -searchR; dc <= searchR; dc++) {
            int c = nearCol + dc;
            int r = nearRow + dr;
            if (c < 0 || c >= int(KG_COLS) || r < 0 || r >= int(KG_ROWS)) continue;

            // This node's rest and displaced position
            float2 restA = float2(KG_MARGIN + float(c) * spacingX,
                                  KG_MARGIN + float(r) * spacingY);
            float2 posA = restA + kg_displacement(restA, t);

            // Node velocity approximation (finite difference)
            float2 posAPrev = restA + kg_displacement(restA, t - 0.016);
            float2 velA = (posA - posAPrev) / 0.016;
            float speedA = length(velA);

            // Node glow
            float nodeDist = length(uv - posA);
            float nodeBright = clamp(speedA * 0.2, 0.0, 1.0);
            if (nodeBright > 0.02 && nodeDist < 0.015) {
                float nodeAlpha = (0.12 + nodeBright * 0.75);
                float nodeRadius = 0.001 + nodeBright * 0.003;
                float nodeGlow = smoothstep(nodeRadius * 3.0, 0.0, nodeDist) * nodeAlpha;
                float3 nCol = mix(float3(0.059, 0.118, 0.275), float3(0.922, 0.863, 1.0), nodeBright);
                nodeAccum += nCol * nodeGlow;

                // Wavefront bloom
                if (speedA > 3.0) {
                    float bloomInt = clamp((speedA - 3.0) / 15.0, 0.0, 1.0);
                    float haloR = 0.005 + bloomInt * 0.015;
                    float halo = smoothstep(haloR, 0.0, nodeDist) * bloomInt * 0.35;
                    nodeAccum += float3(0.863, 0.314, 0.059) * halo;
                    float coreBloom = smoothstep(haloR * 0.4, 0.0, nodeDist) * bloomInt * 0.6;
                    nodeAccum += float3(1.0, 0.863, 0.667) * coreBloom;
                }
            }

            // Right spring
            if (c < int(KG_COLS) - 1) {
                float2 restB = float2(KG_MARGIN + float(c + 1) * spacingX,
                                      KG_MARGIN + float(r) * spacingY);
                float2 posB = restB + kg_displacement(restB, t);
                float dist = length(posB - posA);
                float stretch = abs(dist - spacingX);
                float tension = stretch * tensionScale;
                float4 tCol = kg_tension_color(tension);

                float lineDist = kg_line_sdf(uv, posA, posB);

                // Glow pass
                float glowWidth = KG_GLOW_WIDTH + tension * 0.01;
                float glowAlpha = (0.04 + tension * 0.18) * breathe;
                float glow = smoothstep(glowWidth, 0.0, lineDist) * glowAlpha;
                glowAccum += tCol.rgb * glow;

                // Core pass
                float coreWidth = KG_LINE_WIDTH + tension * 0.002;
                float coreAlpha = (0.12 + tension * 0.6) * breathe;
                coreAlpha = min(coreAlpha, 1.0);
                float core = smoothstep(coreWidth, 0.0, lineDist) * coreAlpha;
                coreAccum += tCol.rgb * core;
            }

            // Bottom spring
            if (r < int(KG_ROWS) - 1) {
                float2 restB = float2(KG_MARGIN + float(c) * spacingX,
                                      KG_MARGIN + float(r + 1) * spacingY);
                float2 posB = restB + kg_displacement(restB, t);
                float dist = length(posB - posA);
                float stretch = abs(dist - spacingY);
                float tension = stretch * tensionScale;
                float4 tCol = kg_tension_color(tension);

                float lineDist = kg_line_sdf(uv, posA, posB);

                float glowWidth = KG_GLOW_WIDTH + tension * 0.01;
                float glowAlpha = (0.04 + tension * 0.18) * breathe;
                float glow = smoothstep(glowWidth, 0.0, lineDist) * glowAlpha;
                glowAccum += tCol.rgb * glow;

                float coreWidth = KG_LINE_WIDTH + tension * 0.002;
                float coreAlpha = (0.12 + tension * 0.6) * breathe;
                coreAlpha = min(coreAlpha, 1.0);
                float core = smoothstep(coreWidth, 0.0, lineDist) * coreAlpha;
                coreAccum += tCol.rgb * core;
            }
        }
    }

    // Additive compositing (matching the 'lighter' blend mode)
    col += glowAccum;
    col += coreAccum;
    col += nodeAccum;

    // Impulse flash expanding rings
    for (int w = 0; w < int(KG_NUM_WAVES); w++) {
        float fw = float(w);
        float waveCycle = KG_IMPULSE_INTERVAL * KG_NUM_WAVES;
        float waveTime = fmod(t + fw * KG_IMPULSE_INTERVAL, waveCycle);

        if (waveTime < 1.5) {
            float seed = floor((t + fw * KG_IMPULSE_INTERVAL) / waveCycle) * 17.0 + fw * 73.1;
            int edge = int(fmod(kg_hash(seed) * 4.0, 4.0));
            float edgePos = kg_hash(seed + 1.0);

            float2 sourcePos;
            if (edge == 0)      sourcePos = float2(KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN), KG_MARGIN);
            else if (edge == 1) sourcePos = float2(1.0 - KG_MARGIN, KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN));
            else if (edge == 2) sourcePos = float2(KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN), 1.0 - KG_MARGIN);
            else                sourcePos = float2(KG_MARGIN, KG_MARGIN + edgePos * (1.0 - 2.0 * KG_MARGIN));

            // Core flash
            float flashDist = length(uv - sourcePos);
            float fl = exp(-waveTime * 2.0);
            float flashRadius = waveTime * 0.08 + 0.02;
            float flash = smoothstep(flashRadius, 0.0, flashDist) * fl * 0.8;
            col += float3(1.0, 0.824, 0.588) * flash * 0.5;
            col += float3(0.941, 0.471, 0.118) * flash * 0.3;

            // Expanding ring
            float ringRadius = waveTime * 0.12 + 0.015;
            float ringWidth = 0.003 * fl;
            float ring = smoothstep(ringWidth, 0.0, abs(flashDist - ringRadius)) * fl * 0.5;
            col += float3(0.941, 0.510, 0.157) * ring;
        }
    }

    // Vignette
    float vigDist = length(centered);
    float vig = smoothstep(0.25, 0.72, vigDist);
    col *= 1.0 - vig * 0.6;

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
