#include "../Common.metal"

// ─── Digital Rain: Matrix-style falling columns with water surface ───
// Ported from static/digital-rain.html (Canvas 2D)
// Approach: procedural column grid, hash-based "character" brightness,
// water surface with reflections and zen ripples.

constant float DR_PI               = 3.14159265;
constant float DR_CELL_SIZE        = 0.025;
constant float DR_FALL_SPEED       = 0.6;
constant float DR_WATER_Y          = 0.78;
constant float DR_TRAIL_LEN_MIN    = 12.0;
constant float DR_TRAIL_LEN_RANGE  = 20.0;
constant float DR_CHAR_CYCLE_RATE  = 0.15;

// Hash functions for procedural randomness
static float dr_hash(float n) {
    return fract(sin(n * 127.1) * 43758.5453);
}

static float dr_hash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// Fake "character" pattern: a grid-based procedural glyph
// Returns brightness of a pseudo-character at grid position
static float dr_char_pattern(float2 localUV, float seed) {
    // Create a 5x7 "pixel font" pattern from the seed
    float2 cell = floor(localUV * float2(5.0, 7.0));
    if (cell.x < 0.0 || cell.x >= 5.0 || cell.y < 0.0 || cell.y >= 7.0) return 0.0;
    float cellHash = dr_hash(seed * 127.0 + cell.x * 13.0 + cell.y * 57.0);
    // About 40% of cells are "on" to simulate character shapes
    return step(0.6, cellHash);
}

// Column properties from column index
static float dr_col_speed(float colIdx) {
    return 1.2 + dr_hash(colIdx * 73.1) * 2.5;
}

static float dr_col_trail_len(float colIdx) {
    return DR_TRAIL_LEN_MIN + floor(dr_hash(colIdx * 137.3) * DR_TRAIL_LEN_RANGE);
}

static float dr_col_active(float colIdx, float time) {
    // Columns cycle on/off
    float period = 3.0 + dr_hash(colIdx * 251.0) * 5.0;
    float phase = dr_hash(colIdx * 419.0) * period;
    float cycleT = fmod(time + phase, period);
    float duty = 0.5 + dr_hash(colIdx * 331.0) * 0.3;
    return step(cycleT, period * duty) * 0.7 + 0.3;
}

// Column head Y position
static float dr_col_head_y(float colIdx, float time) {
    float speed = dr_col_speed(colIdx);
    float trailLen = dr_col_trail_len(colIdx);
    float totalDist = 1.0 + trailLen * DR_CELL_SIZE + 0.2;
    float startOffset = dr_hash(colIdx * 193.0) * totalDist;
    float rawY = fmod(speed * DR_FALL_SPEED * time + startOffset, totalDist);
    return rawY - trailLen * DR_CELL_SIZE * 0.3;
}

fragment float4 fs_digital_rain(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float aspect = res.x / res.y;
    float t = u.time;

    // Background
    float3 col = float3(0.039, 0.039, 0.039);

    // Grid coordinates
    float colWidth = DR_CELL_SIZE;
    float colIdx = floor(uv.x / colWidth);
    float localX = fract(uv.x / colWidth);

    // Only render above water surface for main columns
    if (uv.y < DR_WATER_Y) {
        float active = dr_col_active(colIdx, t);
        float headY = dr_col_head_y(colIdx, t);
        float trailLen = dr_col_trail_len(colIdx);
        float opacity = 0.6 + dr_hash(colIdx * 571.0) * 0.4;

        // Which character row are we in?
        float charRow = floor(uv.y / colWidth);
        float localY = fract(uv.y / colWidth);

        // Distance from head in character units
        float charY_pos = uv.y;
        float distFromHead = (headY - charY_pos) / colWidth;

        // Only render if we're in the trail
        if (distFromHead >= 0.0 && distFromHead < trailLen) {
            float trailFrac = distFromHead / trailLen;

            // Brightness based on position in trail
            float brightness;
            if (distFromHead < 0.5) {
                brightness = 1.0; // leading character - white hot
            } else if (distFromHead < 1.5) {
                brightness = 0.9;
            } else if (distFromHead < 4.0) {
                brightness = 0.75 - (distFromHead - 2.0) * 0.04;
            } else {
                brightness = max(0.0, 0.6 * (1.0 - trailFrac));
            }

            // Fade near water surface
            float distToWater = DR_WATER_Y - uv.y;
            if (distToWater < colWidth * 3.0) {
                brightness *= max(0.0, distToWater / (colWidth * 3.0));
            }

            brightness *= opacity * active;

            if (brightness > 0.02) {
                // Generate character pattern
                float charSeed = dr_hash(colIdx * 31.0 + charRow * 17.0 + floor(t * DR_CHAR_CYCLE_RATE + dr_hash(colIdx * 97.0 + charRow * 43.0) * 10.0));
                float charBright = dr_char_pattern(float2(localX, localY), charSeed);

                // Color: lead is white-amber, trail is warm amber
                float3 charCol;
                if (distFromHead < 0.5) {
                    charCol = float3(1.0, 0.96, 0.863);
                } else if (distFromHead < 3.0) {
                    charCol = float3(0.941, 0.784, 0.549);
                } else {
                    charCol = float3(0.784, 0.584, 0.424);
                }

                col += charCol * charBright * brightness;

                // Leading character glow
                if (distFromHead < 0.5) {
                    float glow = smoothstep(colWidth * 2.0, 0.0, abs(uv.y - headY)) * 0.15;
                    col += float3(1.0, 0.863, 0.627) * glow;
                }
            }
        }
    }

    // ── Water region ──
    if (uv.y >= DR_WATER_Y - 0.02) {
        // Water surface wave
        float waveY = DR_WATER_Y
            + sin(uv.x * 6.0 + t * 0.8) * 0.002
            + sin(uv.x * 14.0 + t * 0.5) * 0.0015
            + sin(uv.x * 4.0 + t * 0.3) * 0.003;

        // Darken water region
        if (uv.y > waveY) {
            float waterDepth = (uv.y - waveY) / (1.0 - waveY);
            float3 waterDark = float3(0.047, 0.043, 0.039);
            float darkFade = 0.6 + 0.35 * waterDepth;
            col = mix(col, waterDark, darkFade);

            // Faint reflections in water
            float reflectY = waveY - (uv.y - waveY);
            float reflectDepth = uv.y - waveY;
            float reflectAlpha = max(0.0, 0.12 * (1.0 - reflectDepth * 5.0));
            if (reflectAlpha > 0.01) {
                float rColIdx = floor(uv.x / colWidth);
                float rHeadY = dr_col_head_y(rColIdx, t);
                float rTrailLen = dr_col_trail_len(rColIdx);
                float rDistFromHead = (rHeadY - reflectY) / colWidth;
                if (rDistFromHead >= 0.0 && rDistFromHead < rTrailLen) {
                    float rBright = max(0.0, 0.6 * (1.0 - rDistFromHead / rTrailLen));
                    // Distort x slightly
                    float waveDistort = sin(reflectDepth * 30.0) * 0.003;
                    col += float3(0.784, 0.584, 0.424) * reflectAlpha * rBright;
                }
            }

            // Zen ripples in water
            float2 zenPoints[3] = {
                float2(0.3, DR_WATER_Y + (1.0 - DR_WATER_Y) * 0.4),
                float2(0.7, DR_WATER_Y + (1.0 - DR_WATER_Y) * 0.5),
                float2(0.5, DR_WATER_Y + (1.0 - DR_WATER_Y) * 0.7)
            };
            for (int z = 0; z < 3; z++) {
                float2 zp = zenPoints[z];
                for (int ring = 0; ring < 4; ring++) {
                    float phase = t * 0.4 + float(ring) * 1.5 + float(z) * 2.0;
                    float radius = 0.03 + fmod(phase, 6.0) * 0.02;
                    float alpha = 0.06 * max(0.0, 1.0 - fmod(phase, 6.0) / 6.0);
                    // Elliptical ripple (compressed vertically)
                    float2 diff = uv - zp;
                    diff.y *= 3.3; // flatten
                    float rippleDist = abs(length(diff) - radius);
                    float ripple = smoothstep(0.003, 0.0, rippleDist) * alpha;
                    col += float3(0.784, 0.667, 0.510) * ripple;
                }
            }

            // Scattered water particles
            for (int wp = 0; wp < 20; wp++) {
                float fwp = float(wp);
                float px = fract(sin(fwp * 73.1 + t * 0.07) * 0.5 + 0.5);
                float py = DR_WATER_Y + fract(cos(fwp * 127.3 + t * 0.05) * 0.5 + 0.5) * (1.0 - DR_WATER_Y);
                float wpAlpha = 0.04 + 0.03 * sin(t * 0.5 + fwp * 1.7);
                float wpDist = length(uv - float2(px, py));
                col += float3(0.784, 0.584, 0.424) * smoothstep(0.003, 0.0, wpDist) * wpAlpha;
            }
        }

        // Surface line
        float surfLineDist = abs(uv.y - waveY);
        float surfLine = smoothstep(0.002, 0.0, surfLineDist) * 0.25;
        col += float3(0.784, 0.667, 0.510) * surfLine;

        // Surface glow
        float surfGlow = smoothstep(0.015, 0.0, abs(uv.y - waveY)) * 0.06;
        col += float3(0.784, 0.584, 0.424) * surfGlow;
    }

    // Vignette
    float2 vc = uv - 0.5;
    float vd = length(vc);
    float vig = smoothstep(0.25, 0.8, vd) * 0.45;
    col *= 1.0 - vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
