#include "../Common.metal"

// ─── Phase Transition: Order-chaos wavefront across a particle lattice ───
// Ported from static/phase-transition.html

constant float PT_GRID_COLS = 50.0;
constant float PT_GRID_ROWS = 30.0;
constant float PT_WAVE_SPEED = 0.5;
constant float PT_TRANS_WIDTH = 0.12;
constant float PT_TURB_SCALE = 3.0;
constant float PT_PI = 3.14159265;

// ── Hash noise ──
static float pt_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float pt_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = pt_hash(i);
    float b = pt_hash(i + float2(1.0, 0.0));
    float c = pt_hash(i + float2(0.0, 1.0));
    float d = pt_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static float pt_fbm(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < octaves; i++) {
        val += amp * pt_noise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return val;
}

// ── Wavefront position (sweeps back and forth) ──
static float pt_wavePos(float t) {
    float cycleDuration = 8.0;
    float raw = t * PT_WAVE_SPEED / cycleDuration;
    float within = fract(raw);
    float eased = within * within * (3.0 - 2.0 * within);
    int cycleIdx = int(floor(raw));
    return (cycleIdx % 2 == 0) ? eased : (1.0 - eased);
}

// ── Wavefront phase (alternates order/chaos) ──
static float pt_wavePhase(float t) {
    float cycleDuration = 8.0;
    float raw = t * PT_WAVE_SPEED / cycleDuration;
    int cycleIdx = int(floor(raw));
    return (cycleIdx % 4 < 2) ? 0.0 : 1.0;
}

// ── Compute particle offset from lattice home via noise turbulence ──
static float2 pt_particleOffset(float2 home, float phase, float t) {
    float noiseT = t * 0.4;
    float2 np = home * PT_TURB_SCALE;
    float angle = pt_fbm(np + float2(noiseT, noiseT * 0.7), 3) * PT_PI * 4.0;
    float2 turbOffset = float2(cos(angle), sin(angle)) * 0.03 * phase;

    // Swirl component
    float2 toCenter = home - float2(0.5);
    float swirlAngle = atan2(toCenter.y, toCenter.x) + PT_PI * 0.5;
    float swirlDist = length(toCenter);
    float swirlStr = 0.01 * min(1.0, swirlDist / 0.3) * phase;
    turbOffset += float2(cos(swirlAngle), sin(swirlAngle)) * swirlStr;

    return turbOffset;
}

fragment float4 fs_phase_transition(VSOut in [[stage_in]],
                                     constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float2 uv = in.pos.xy / res;
    float aspect = res.x / res.y;
    float t = u.time;

    // Normalized coordinates
    float2 p = float2(uv.x, uv.y);

    // Wavefront
    float wPos = pt_wavePos(t);
    float wPhase = pt_wavePhase(t);
    float wavePx = wPos; // in normalized 0..1

    // Per-pixel: accumulate glow from nearby lattice particles
    float3 col = float3(0.035, 0.028, 0.022); // dark bg

    // Grid spacing in UV
    float spacingX = 1.0 / (PT_GRID_COLS + 1.0);
    float spacingY = 1.0 / (PT_GRID_ROWS + 1.0);

    // Determine which grid cells are nearby (search window)
    float searchRadius = 4.0; // cells
    int nearCol = int(floor(p.x / spacingX));
    int nearRow = int(floor(p.y / spacingY));

    float3 accumColor = float3(0.0);
    float accumGlow = 0.0;

    for (int dr = -int(searchRadius); dr <= int(searchRadius); dr++) {
        for (int dc = -int(searchRadius); dc <= int(searchRadius); dc++) {
            int c = nearCol + dc;
            int r = nearRow + dr;
            if (c < 0 || c >= int(PT_GRID_COLS) || r < 0 || r >= int(PT_GRID_ROWS)) continue;

            // Home position in UV
            float2 home = float2((float(c) + 1.0) * spacingX,
                                 (float(r) + 1.0) * spacingY);

            // Phase for this particle
            float distToWave = (home.x - wavePx);
            float phase;
            if (wPhase < 0.5) {
                phase = 1.0 - smoothstep(-PT_TRANS_WIDTH, PT_TRANS_WIDTH, distToWave);
            } else {
                phase = smoothstep(-PT_TRANS_WIDTH, PT_TRANS_WIDTH, distToWave);
            }

            // Transition energy
            float transEnergy = 1.0 - abs(distToWave) / PT_TRANS_WIDTH;
            transEnergy = max(0.0, transEnergy);
            transEnergy = transEnergy * transEnergy;

            // Particle position = home + noise offset
            float2 offset = pt_particleOffset(home, phase, t);
            // Also add a small random static jitter per particle
            float2 jitter = float2(pt_hash(float2(float(c), float(r))) - 0.5,
                                   pt_hash(float2(float(r), float(c) + 100.0)) - 0.5) * 0.005;
            float2 particlePos = home + offset + jitter * phase;

            // Distance from pixel to particle (aspect-corrected)
            float2 diff = float2((p.x - particlePos.x) * aspect, p.y - particlePos.y);
            float dist = length(diff);

            // Particle size
            float baseSize = 0.003 + phase * 0.002;
            float size = baseSize + transEnergy * 0.006;

            // Glow falloff
            float glow = exp(-dist * dist / (size * size * 2.0));

            // Color determination
            float3 particleColor;
            if (transEnergy > 0.1) {
                // Wavefront: bright white-blue
                particleColor = mix(float3(0.82, 0.88, 1.0),
                                    float3(1.0, 0.98, 0.95),
                                    transEnergy);
            } else if (phase < 0.5) {
                // Ordered: cool blue
                float settled = 1.0 - min(1.0, length(offset) / (spacingX * 0.5));
                particleColor = mix(float3(0.38, 0.50, 0.69),
                                    float3(0.69, 0.75, 0.82),
                                    settled);
            } else {
                // Chaotic: warm amber
                float speed = length(offset) * 20.0;
                float energyBright = min(1.0, speed);
                particleColor = mix(float3(0.78, 0.58, 0.42),
                                    float3(0.88, 0.82, 0.75),
                                    energyBright);
            }

            float alpha = 0.6 + transEnergy * 0.4;
            accumColor += particleColor * glow * alpha;
            accumGlow += glow * alpha;
        }
    }

    col += accumColor;

    // Lattice connections in ordered regions (subtle grid lines)
    float gridDistX = abs(fract(p.x / spacingX + 0.5) - 0.5) * spacingX * aspect;
    float gridDistY = abs(fract(p.y / spacingY + 0.5) - 0.5) * spacingY;
    float gridLine = min(gridDistX, gridDistY);

    // Phase at this pixel
    float pixDistToWave = p.x - wavePx;
    float pixPhase;
    if (wPhase < 0.5) {
        pixPhase = 1.0 - smoothstep(-PT_TRANS_WIDTH, PT_TRANS_WIDTH, pixDistToWave);
    } else {
        pixPhase = smoothstep(-PT_TRANS_WIDTH, PT_TRANS_WIDTH, pixDistToWave);
    }
    float orderedAmount = max(0.0, 1.0 - pixPhase * 2.0);
    float lineGlow = smoothstep(0.003, 0.0, gridLine) * orderedAmount * 0.06;
    col += float3(0.25, 0.31, 0.44) * lineGlow;

    // Wavefront band glow
    float waveDist = abs(p.x - wavePx);
    float waveGlow = exp(-waveDist * waveDist / (PT_TRANS_WIDTH * PT_TRANS_WIDTH * 0.5));
    float waveWobble = snoise(float2(p.y * 10.0 + t * 0.5, t * 0.3)) * 0.01;
    float waveLineGlow = exp(-(waveDist + waveWobble) * (waveDist + waveWobble) / 0.0003);
    col += float3(0.82, 0.92, 1.0) * waveGlow * 0.04;
    col += float3(0.86, 0.92, 1.0) * waveLineGlow * 0.12;

    // Background energy noise in chaotic regions
    float bgNoise = pt_fbm(p * 5.0 + float2(t * 0.3, t * 0.2), 2);
    float bgGlow = (0.01 + abs(bgNoise) * 0.04) * pixPhase;
    col += float3(0.78, 0.58, 0.42) * bgGlow;

    // Vignette
    float2 vc = (uv - 0.5) * 2.0;
    float vig = 1.0 - smoothstep(0.5, 1.5, length(vc));
    col *= 0.6 + 0.4 * vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
