#include "../Common.metal"

// ─── Sequin Wave: Thousands of tiny reflective discs catching cascading light ───
// Ported from static/sequin-wave.html

constant float SQ_TAU = 6.28318530718;
constant float SQ_SQRT3 = 1.7320508;
constant float SQ_WAVE_SPEED = 0.8;
constant float SQ_SPARKLE = 1.0;
constant float SQ_SEQUIN_SCALE = 38.0;

// ── Hash functions for per-sequin variation ──
static float sq_hash21(float2 p) {
    p = fract(p * float2(233.34, 851.73));
    p += dot(p, p + 23.45);
    return fract(p.x * p.y);
}

static float2 sq_hash22(float2 p) {
    float n = sq_hash21(p);
    return float2(n, sq_hash21(p + n * 47.0));
}

// ── Hexagonal tiling ──
static float4 sq_hexTile(float2 p, float scale) {
    p *= scale;
    float2 s = float2(1.0, SQ_SQRT3);
    float2 halfS = s * 0.5;

    // Grid A
    float2 aBase = floor(p / s);
    // GLSL mod always returns positive; replicate with x - y * floor(x/y)
    float2 aLocal = (p - s * floor(p / s)) - halfS;

    // Grid B (offset)
    float2 pOff = p - halfS;
    float2 bBase = floor(pOff / s);
    float2 bLocal = (pOff - s * floor(pOff / s)) - halfS;

    float dA = dot(aLocal, aLocal);
    float dB = dot(bLocal, bLocal);

    float pick = step(dA, dB);
    float2 localCoord = mix(bLocal, aLocal, pick);
    float2 cellId = mix(bBase + float2(0.5), aBase, pick);

    return float4(localCoord, cellId);
}

// ── Wave field: multiple interfering wave sources ──
static float sq_waveField(float2 cellPos, float t) {
    float w = 0.0;
    w += sin(dot(cellPos, float2(0.7, 0.5)) * 3.5 - t * 2.8) * 0.35;
    w += sin(cellPos.x * 4.2 + t * 1.9) * 0.25;

    float r1 = length(cellPos - float2(-0.3, 0.2));
    w += sin(r1 * 6.0 - t * 3.2) * 0.2 * smoothstep(1.2, 0.0, r1);

    w += sin(dot(cellPos, float2(-0.4, 0.8)) * 2.8 - t * 1.5) * 0.2;

    float r2 = length(cellPos - float2(0.4, -0.3));
    w += sin(r2 * 5.0 - t * 2.4) * 0.15 * smoothstep(1.0, 0.0, r2);

    return w;
}

// ── Specular calculation for a tilted sequin disc ──
static float sq_sequinSpecular(float tiltAngle, float tiltDir) {
    float ct = cos(tiltAngle);
    float st = sin(tiltAngle);
    float cd = cos(tiltDir);
    float sd = sin(tiltDir);

    float3 N = float3(st * cd, st * sd, ct);
    float3 L = normalize(float3(0.4, 0.6, 0.9));
    float3 V = float3(0.0, 0.0, 1.0);
    float3 R = reflect(-L, N);

    float spec = max(dot(R, V), 0.0);
    spec = pow(spec, 48.0);

    float sheen = pow(max(dot(R, V), 0.0), 8.0) * 0.15;

    return spec + sheen;
}

fragment float4 fs_sequin_wave(VSOut in [[stage_in]],
                               constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * SQ_WAVE_SPEED;

    // ── Hexagonal grid of sequins ──
    float4 hex = sq_hexTile(uv, SQ_SEQUIN_SCALE);
    float2 localPos = hex.xy;
    float2 cellId = hex.zw;

    // ── Per-sequin random variation ──
    float2 rnd = sq_hash22(cellId);
    float sizeVar = 0.85 + rnd.x * 0.3;
    float baseTilt = (rnd.y - 0.5) * 0.15;
    float reflVar = 0.7 + rnd.x * 0.3;
    float phaseOff = rnd.y * SQ_TAU;

    // ── Sequin disc shape ──
    float discRadius = 0.42 * sizeVar;
    float dist = length(localPos);
    float disc = smoothstep(discRadius, discRadius - 0.06, dist);

    float bevel = smoothstep(discRadius, discRadius - 0.04, dist)
                - smoothstep(discRadius - 0.04, discRadius - 0.08, dist);

    // ── World position for wave sampling ──
    float2 worldPos = cellId / SQ_SEQUIN_SCALE;

    // ── Wave-driven tilt ──
    float wave = sq_waveField(worldPos, t);
    float shimmer = sin(t * 3.0 + phaseOff) * 0.04;
    float tiltAngle = wave * 0.85 + baseTilt + shimmer;

    float waveH = sq_waveField(worldPos + float2(0.01, 0.0), t);
    float waveV = sq_waveField(worldPos + float2(0.0, 0.01), t);
    float tiltDir = atan2(waveV - wave, waveH - wave);

    // ── Specular flash (no mouse) ──
    float spec = sq_sequinSpecular(tiltAngle, tiltDir);
    spec *= reflVar * SQ_SPARKLE;

    // ── Color composition ──
    float3 darkSequin = float3(0.02, 0.015, 0.01);
    float3 copperMid = float3(0.78, 0.58, 0.42);
    float3 amberFlash = float3(1.0, 0.82, 0.55);
    float3 hotGold = float3(1.0, 0.92, 0.72);

    float facing = cos(tiltAngle) * 0.5 + 0.5;
    facing = clamp(facing, 0.0, 1.0);

    float3 ambient = mix(darkSequin, float3(0.05, 0.035, 0.02), facing * 0.6);

    float3 sequinColor = ambient;

    float sheenAmount = pow(max(facing, 0.0), 3.0) * 0.2 * reflVar;
    sequinColor += copperMid * sheenAmount;

    float flashLow = smoothstep(0.0, 0.3, spec);
    float flashHigh = smoothstep(0.3, 0.8, spec);
    float flashPeak = smoothstep(0.7, 1.0, spec);
    sequinColor += copperMid * flashLow * 0.5;
    sequinColor += amberFlash * flashHigh * 0.8;
    sequinColor += hotGold * flashPeak * 1.2;

    sequinColor += copperMid * bevel * facing * 0.3;

    // ── Background between sequins ──
    float3 bgColor = float3(0.012, 0.008, 0.005);

    // ── Final mix ──
    float3 col = mix(bgColor, sequinColor, disc);

    // ── Global lighting ──
    float2 uvSafe = uv + float2(0.0001);
    float globalLight = 0.85 + 0.15 * dot(normalize(uvSafe), float2(0.4, 0.6));
    col *= globalLight;

    // ── Vignette ──
    float vig = 1.0 - smoothstep(0.4, 1.3, length(uv));
    col *= 0.6 + 0.4 * vig;

    // ── Warm gamma correction ──
    col = pow(max(col, float3(0.0)), float3(0.93, 0.97, 1.04));

    col = clamp(col, float3(0.0), float3(1.0));
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
