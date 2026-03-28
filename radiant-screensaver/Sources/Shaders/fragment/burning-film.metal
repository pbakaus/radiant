#include "../Common.metal"

// ─── Burning Film: Celluloid catching fire in a projector ───
// Ported from static/burning-film.html

// Default parameter values (screensaver — no interactive controls)
constant float BF_BURN_SPEED = 0.5;
constant float BF_EMBER_GLOW = 1.0;

// ── Hash functions ──
static float bf_hash21(float2 p) {
    p = fract(p * float2(443.897, 441.423));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

static float2 bf_hash22(float2 p) {
    float3 a = fract(float3(p.x, p.y, p.x) * float3(443.897, 441.423, 437.195));
    a += dot(a, float3(a.y, a.z, a.x) + 19.19);
    return fract((float2(a.x, a.x) + float2(a.y, a.z)) * float2(a.z, a.y));
}

// ── Value noise ──
static float bf_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = bf_hash21(i);
    float b = bf_hash21(i + float2(1.0, 0.0));
    float c = bf_hash21(i + float2(0.0, 1.0));
    float d = bf_hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM with domain warping ──
static float bf_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2 shift = float2(100.0);
    float2x2 rot = float2x2(float2(0.866, 0.5), float2(-0.5, 0.866));
    for (int i = 0; i < 6; i++) {
        v += a * bf_noise(p);
        p = rot * p * 2.0 + shift;
        a *= 0.5;
    }
    return v;
}

// ── Domain-warped noise for organic burn patterns ──
static float bf_warpedNoise(float2 p, float t) {
    float2 q = float2(
        bf_fbm(p + float2(0.0, 0.0)),
        bf_fbm(p + float2(5.2, 1.3))
    );
    float2 r = float2(
        bf_fbm(p + 4.0 * q + float2(1.7, 9.2) + 0.05 * t),
        bf_fbm(p + 4.0 * q + float2(8.3, 2.8) + 0.06 * t)
    );
    return bf_fbm(p + 4.0 * r);
}

// ── Ember / hot background noise ──
static float bf_emberNoise(float2 p, float t) {
    float n1 = bf_noise(p * 3.0 + float2(t * 0.3, t * 0.2));
    float n2 = bf_noise(p * 7.0 - float2(t * 0.5, t * 0.15));
    float n3 = bf_noise(p * 15.0 + float2(t * 0.8, -t * 0.4));
    return n1 * 0.5 + n2 * 0.35 + n3 * 0.15;
}

// ── Film grain ──
static float bf_filmGrain(float2 uv, float t, float2 res) {
    float grain = bf_hash21(uv * res * 0.5 + fract(t * 137.0));
    return grain;
}

// ── Sprocket hole indicators (film strip detail) ──
static float bf_sprocketHoles(float2 uv) {
    float edge = 0.0;
    if (uv.x < 0.06) {
        float y = fract(uv.y * 8.0);
        float hole = smoothstep(0.08, 0.06, length(float2(uv.x - 0.03, y - 0.5) * float2(1.0, 1.5)));
        edge = hole * 0.15;
    }
    if (uv.x > 0.94) {
        float y = fract(uv.y * 8.0);
        float hole = smoothstep(0.08, 0.06, length(float2(uv.x - 0.97, y - 0.5) * float2(1.0, 1.5)));
        edge = max(edge, hole * 0.15);
    }
    return edge;
}

fragment float4 fs_burning_film(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float t = u.time;

    // ── Burn cycle ──
    float cycleDuration = 12.0 / max(BF_BURN_SPEED, 0.1);
    float cycleT = fmod(t, cycleDuration);
    float cyclePhase = cycleT / cycleDuration;

    float burnThreshold = mix(0.88, 0.08, smoothstep(0.0, 0.85, cyclePhase));

    float resetFade = smoothstep(0.88, 1.0, cyclePhase);
    float startFade = smoothstep(0.0, 0.05, cyclePhase);

    // ── Compute burn pattern ──
    float aspect = u.resolution.x / u.resolution.y;
    float2 burnUV = uv;
    // No mouse interaction in screensaver
    float2 noiseUV = burnUV * float2(aspect, 1.0) * 2.5;

    float cycleIndex = floor(t / cycleDuration);
    float2 cycleOffset = float2(cycleIndex * 7.31, cycleIndex * 3.17);

    float burnNoise = bf_warpedNoise(noiseUV + cycleOffset, cycleT * BF_BURN_SPEED * 0.3);

    // ── Burn regions ──
    float burnAmount = smoothstep(burnThreshold, burnThreshold - 0.12, burnNoise);

    float edgeWidth = 0.06;
    float edgeInner = smoothstep(burnThreshold, burnThreshold - edgeWidth, burnNoise);
    float edgeMask = edgeInner * (1.0 - burnAmount * 0.7);

    float hotEdge = smoothstep(burnThreshold + 0.01, burnThreshold - 0.01, burnNoise)
                  - smoothstep(burnThreshold - 0.01, burnThreshold - 0.04, burnNoise);
    hotEdge = max(hotEdge, 0.0);

    // ── Film base ──
    float grain = bf_filmGrain(uv, t, u.resolution);
    float grainStrength = 0.035;
    float3 filmBase = float3(0.035, 0.03, 0.028);
    filmBase += (grain - 0.5) * grainStrength;

    float scanline = sin(uv.y * u.resolution.y * 0.5) * 0.5 + 0.5;
    filmBase *= 0.95 + scanline * 0.05;

    float sprocket = bf_sprocketHoles(uv);
    filmBase += sprocket;

    // ── Burn edge glow ──
    float3 whiteHot = float3(1.0, 0.88, 0.67);
    float3 orangeGlow = float3(1.0, 0.533, 0.2);
    float3 amberEdge = float3(0.784, 0.584, 0.424);
    float3 deepAmber = float3(0.5, 0.25, 0.08);

    float3 edgeColor = mix(amberEdge, orangeGlow, smoothstep(0.0, 0.5, edgeMask));
    edgeColor = mix(edgeColor, whiteHot, hotEdge);

    float edgeNoise = bf_noise(noiseUV * 8.0 + cycleOffset + t * 0.5);
    edgeColor *= 0.8 + edgeNoise * 0.4;

    float edgePulse = 0.85 + 0.15 * sin(t * 3.0 + burnNoise * 10.0);
    edgeColor *= edgePulse;

    // ── Ember field ──
    float ember = bf_emberNoise(noiseUV, t);

    float3 emberDark = float3(0.1, 0.02, 0.0);
    float3 emberRed = float3(0.4, 0.04, 0.0);
    float3 emberOrange = float3(0.85, 0.35, 0.05);
    float3 emberWhite = float3(1.0, 0.7, 0.3);

    float3 emberColor = mix(emberDark, emberRed, smoothstep(0.2, 0.5, ember));
    emberColor = mix(emberColor, emberOrange, smoothstep(0.55, 0.75, ember));
    emberColor = mix(emberColor, emberWhite, smoothstep(0.8, 0.95, ember) * 0.5);

    float emberPulse = 0.7 + 0.3 * sin(t * 2.0 + ember * 8.0 + burnNoise * 5.0);
    emberColor *= emberPulse * BF_EMBER_GLOW;

    float edgeProximity = smoothstep(0.3, 0.0, abs(burnNoise - burnThreshold + 0.15));
    emberColor += orangeGlow * edgeProximity * 0.4 * BF_EMBER_GLOW;

    // ── Compose layers ──
    float3 col = filmBase;

    float preheat = smoothstep(burnThreshold + 0.15, burnThreshold + 0.02, burnNoise);
    preheat *= (1.0 - burnAmount);
    col += deepAmber * preheat * 0.4;

    col = mix(col, emberColor, burnAmount);

    col += edgeColor * edgeMask * 1.8;

    col += whiteHot * hotEdge * 1.2;

    // ── Curling burn pattern detail ──
    float curl = bf_noise(noiseUV * 20.0 + cycleOffset);
    float curlEdge = smoothstep(burnThreshold + 0.03, burnThreshold - 0.02, burnNoise);
    curlEdge *= (1.0 - burnAmount * 0.8);
    col += float3(0.6, 0.3, 0.1) * curl * curlEdge * 0.3;

    // ── Floating sparks / embers ──
    for (float i = 0.0; i < 4.0; i++) {
        float2 sparkUV = uv * float2(aspect, 1.0);
        float sparkScale = 30.0 + i * 15.0;
        float2 sparkPos = sparkUV * sparkScale;
        sparkPos.y -= t * (1.5 + i * 0.8);
        sparkPos.x += sin(t * (1.0 + i * 0.3) + i * 3.0) * 0.5;

        float2 sparkId = floor(sparkPos);
        float2 sparkFrac = fract(sparkPos) - 0.5;

        float sparkHash = bf_hash21(sparkId + i * 100.0);
        float sparkActive = step(0.85, sparkHash);

        float2 sparkOffset = bf_hash22(sparkId + i * 50.0) - 0.5;
        float sparkDist = length(sparkFrac - sparkOffset * 0.3);
        float sparkSize = 0.03 + sparkHash * 0.02;
        float spark = smoothstep(sparkSize, sparkSize * 0.2, sparkDist);

        float sparkFlicker = sin(t * 15.0 + sparkHash * 50.0) * 0.5 + 0.5;
        spark *= sparkFlicker * sparkActive;

        float nearBurn = smoothstep(0.6, 0.3, abs(burnNoise - burnThreshold));
        spark *= nearBurn;

        float3 sparkColor = mix(orangeGlow, whiteHot, sparkHash);
        col += sparkColor * spark * 0.6 * BF_EMBER_GLOW;
    }

    // ── Vignette ──
    float2 vc = uv - 0.5;
    float vig = 1.0 - dot(vc, vc) * 1.6;
    vig = clamp(vig, 0.0, 1.0);
    vig = pow(vig, 0.6);
    col *= vig;

    // ── Cycle fades ──
    col *= startFade;
    col *= 1.0 - resetFade;

    // ── Subtle overall film warmth ──
    col = mix(col, col * float3(1.05, 0.95, 0.85), 0.15);

    // ── Tone mapping ──
    col = col / (1.0 + col * 0.2);

    // ── Gamma ──
    col = pow(max(col, 0.0), float3(0.95));

    // ── Hue shift ──
    col = hue_rotate(col, u.hue_shift);

    return float4(col, 1.0);
}
