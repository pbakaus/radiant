#include "../Common.metal"

// ─── Aurora Veil: Dramatic northern lights display ───
// Ported from static/aurora-veil.html

constant float AV_PI = 3.14159265359;
constant int AV_NUM_BG_STARS = 120;
constant float AV_AURORA_SPEED = 0.5;
constant float AV_AURORA_INTENSITY = 1.0;

// ── Hash functions ──
static float av_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float av_hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

// ── Smooth value noise ──
static float av_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = av_hash(i);
    float b = av_hash(i + float2(1.0, 0.0));
    float c = av_hash(i + float2(0.0, 1.0));
    float d = av_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float av_fbm(float2 p, float t, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 6; i++) {
        if (i >= octaves) break;
        val += amp * av_noise(p * freq + t * 0.1);
        freq *= 2.1;
        amp *= 0.48;
        p += float2(1.7, 9.2);
    }
    return val;
}

// ── Aurora ribbon function ──
static float av_auroraRibbon(float2 uv, float t, float ribbonX, float ribbonWidth, float waveFreq, float waveAmp, float phase) {
    float centerX = ribbonX + sin(t * 0.15 + phase) * 0.25;

    float wave1 = sin(uv.y * waveFreq + t * 0.9 + phase) * waveAmp;
    float wave2 = sin(uv.y * waveFreq * 2.3 + t * 1.3 + phase * 1.7) * waveAmp * 0.5;
    float wave3 = sin(uv.y * waveFreq * 0.4 + t * 0.35 + phase * 0.6) * waveAmp * 1.2;
    float wave4 = sin(uv.y * waveFreq * 3.7 + t * 1.8 + phase * 2.3) * waveAmp * 0.2;
    float waveOffset = wave1 + wave2 + wave3 + wave4;

    float dx = uv.x - (centerX + waveOffset);

    float ribbon = exp(-dx * dx / (ribbonWidth * ribbonWidth));

    float brightBand = 0.5 + 0.5 * sin(uv.y * 2.5 + t * 0.7 + phase * 2.0);
    brightBand *= 0.5 + 0.5 * sin(uv.y * 5.0 - t * 0.9 + phase);

    float shimmer = 0.7 + 0.3 * sin(t * 2.5 + phase * 3.0 + uv.y * 8.0);
    shimmer *= 0.8 + 0.2 * sin(t * 1.7 + phase * 1.1 + uv.x * 6.0);

    float verticalFade = smoothstep(-0.35, -0.05, uv.y) * smoothstep(0.75, 0.35, uv.y);

    float detail = av_noise(float2(uv.x * 6.0, uv.y * 10.0 + t * 0.5 + phase));
    detail = 0.6 + 0.4 * detail;

    return ribbon * brightBand * verticalFade * detail * shimmer;
}

// ── Background stars ──
static float av_bgStars(float2 uv, float t) {
    float stars = 0.0;
    for (int i = 0; i < AV_NUM_BG_STARS; i++) {
        float fi = float(i);
        float2 pos = float2(
            av_hash1(fi * 17.31 + 100.0) * 2.8 - 1.4,
            av_hash1(fi * 11.97 + 200.0) * 1.4 - 0.3
        );
        float d = length(uv - pos);
        float twinkleSpeed = 0.5 + av_hash1(fi * 3.3 + 300.0) * 2.0;
        float tw = 0.3 + 0.7 * sin(t * twinkleSpeed + fi * 2.7);
        tw = max(tw, 0.0);
        tw *= tw;
        float sz = 0.0008 + av_hash1(fi * 5.5 + 400.0) * 0.002;
        float brightness = 0.4 + av_hash1(fi * 7.7 + 500.0) * 0.6;
        stars += smoothstep(sz, 0.0, d) * tw * brightness;
        if (brightness > 0.7) {
            stars += smoothstep(sz * 5.0, 0.0, d) * tw * 0.08;
        }
    }
    return stars;
}

// ── GLSL-compatible mod (always positive for positive y) ──
static float2 av_mod(float2 x, float2 y) { return x - y * floor(x / y); }

// ── Ice crystal pattern (hexagonal frost) ──
static float av_hexDist(float2 p) {
    p = abs(p);
    return max(p.x + p.y * 0.577350269, p.y * 1.154700538);
}

static float av_crystalPattern(float2 uv, float t) {
    float scale = 12.0;
    float2 p = uv * scale;
    float2 r = float2(1.0, 1.732);
    float2 h = r * 0.5;
    float2 a = av_mod(p, r) - h;
    float2 b = av_mod(p - h, r) - h;
    float2 gv = (dot(a, a) < dot(b, b)) ? a : b;
    float hd = av_hexDist(gv);
    float edge = smoothstep(0.45, 0.40, hd) - smoothstep(0.40, 0.35, hd);
    float angle = atan2(gv.y, gv.x);
    float branch = abs(sin(angle * 3.0));
    float branchLine = smoothstep(0.04, 0.0, abs(branch - 0.5) * hd);
    branchLine *= smoothstep(0.0, 0.15, hd) * smoothstep(0.45, 0.25, hd);
    float subBranch = abs(sin(angle * 6.0));
    float subLine = smoothstep(0.03, 0.0, abs(subBranch - 0.5) * hd);
    subLine *= smoothstep(0.1, 0.2, hd) * smoothstep(0.4, 0.3, hd);
    float crystal = edge * 0.6 + branchLine * 0.4 + subLine * 0.2;
    float shimmer = 0.7 + 0.3 * sin(t * 0.2 + av_hash(floor(p / r)) * 6.28);
    crystal *= shimmer;
    return crystal;
}

fragment float4 fs_aurora_veil(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    // No mouse interaction for screensaver
    float2 screenUV = in.pos.xy / u.resolution;
    float t = u.time * AV_AURORA_SPEED;
    float auroraIntensity = AV_AURORA_INTENSITY;

    // ── Dark sky background ──
    float3 col = float3(0.012, 0.010, 0.022);
    col += float3(0.012, 0.010, 0.018) * smoothstep(0.5, -0.3, uv.y);

    // ── Background stars ──
    float starField = av_bgStars(uv, u.time);
    float3 starColor = float3(0.9, 0.88, 0.8);
    col += starColor * starField;

    // ── Aurora ribbons — 7 layers ──
    float r1 = av_auroraRibbon(uv, t, 0.0, 0.22, 2.5, 0.28, 0.0);
    float3 r1color = mix(
        float3(0.15, 0.95, 0.35),
        float3(0.10, 0.75, 0.55),
        0.5 + 0.5 * sin(uv.y * 3.5 + t * 0.3)
    );
    r1color = mix(r1color, float3(0.55, 0.20, 0.80), smoothstep(0.25, 0.65, uv.y) * 0.4);

    float r2 = av_auroraRibbon(uv, t * 0.9, 0.35, 0.18, 2.8, 0.24, 2.1);
    float3 r2color = mix(
        float3(0.20, 0.90, 0.30),
        float3(0.30, 0.80, 0.25),
        0.5 + 0.5 * sin(uv.y * 4.0 - t * 0.4 + 1.0)
    );
    r2color = mix(r2color, float3(0.65, 0.25, 0.75), smoothstep(0.3, 0.6, uv.y) * 0.35);

    float r3 = av_auroraRibbon(uv, t * 0.75, -0.30, 0.16, 3.0, 0.22, 4.3);
    float3 r3color = mix(
        float3(0.60, 0.15, 0.70),
        float3(0.80, 0.20, 0.55),
        0.5 + 0.5 * sin(uv.y * 5.0 + t * 0.2 + 2.0)
    );
    r3color = mix(r3color, float3(0.20, 0.70, 0.40), smoothstep(0.1, -0.1, uv.y) * 0.3);

    float r4 = av_auroraRibbon(uv, t * 0.6, 0.15, 0.30, 1.8, 0.35, 1.0);
    float3 r4color = mix(
        float3(0.10, 0.65, 0.25),
        float3(0.05, 0.50, 0.35),
        0.5 + 0.5 * sin(uv.y * 2.0 + t * 0.15)
    );

    float r5 = av_auroraRibbon(uv, t * 1.1, -0.10, 0.10, 3.5, 0.18, 5.7);
    float3 r5color = mix(
        float3(0.30, 1.0, 0.50),
        float3(0.50, 0.30, 0.90),
        0.5 + 0.5 * sin(uv.y * 6.0 + t * 0.5 + 3.0)
    );

    float r6 = av_auroraRibbon(uv, t * 0.65, 0.55, 0.14, 2.2, 0.20, 3.5);
    float3 r6color = mix(
        float3(0.45, 0.10, 0.65),
        float3(0.70, 0.15, 0.50),
        0.5 + 0.5 * sin(uv.y * 3.0 - t * 0.3 + 1.5)
    );

    float r7 = av_auroraRibbon(uv, t * 0.5, -0.20, 0.35, 1.5, 0.30, 6.2);
    float3 r7color = mix(
        float3(0.08, 0.55, 0.20),
        float3(0.12, 0.45, 0.30),
        0.5 + 0.5 * sin(uv.y * 2.5 + t * 0.1 + 4.0)
    );

    // Depth-based intensity layering
    float i1 = r1 * 1.4 * auroraIntensity;
    float i2 = r2 * 1.1 * auroraIntensity;
    float i3 = r3 * 0.9 * auroraIntensity;
    float i4 = r4 * 0.5 * auroraIntensity;
    float i5 = r5 * 0.8 * auroraIntensity;
    float i6 = r6 * 0.6 * auroraIntensity;
    float i7 = r7 * 0.35 * auroraIntensity;

    // Additive blending of all aurora light
    float3 auroraLight = r1color * i1 + r2color * i2 + r3color * i3
                       + r4color * i4 + r5color * i5 + r6color * i6 + r7color * i7;

    // Global pulsing intensity
    float pulse = 0.85 + 0.15 * sin(t * 0.8) * sin(t * 0.53 + 1.0);
    auroraLight *= pulse;

    // Atmospheric glow
    float glowY = smoothstep(-0.3, 0.0, uv.y) * smoothstep(0.75, 0.25, uv.y);
    float totalAurora = i1 + i2 + i3 + i4 + i5 + i6 + i7;
    float3 atmosphericGlow = mix(
        float3(0.06, 0.15, 0.06),
        float3(0.10, 0.05, 0.12),
        0.5 + 0.5 * sin(t * 0.15)
    ) * glowY * min(totalAurora, 2.5) * 0.4;

    col += auroraLight + atmosphericGlow;

    // ── Stars dimmed by aurora light ──
    col -= starColor * starField * clamp(totalAurora * 0.5, 0.0, 1.0);

    // ── Ice crystal ground plane (lower portion) ──
    float groundLine = -0.35;
    float groundFade = smoothstep(groundLine + 0.05, groundLine - 0.15, uv.y);

    if (groundFade > 0.001) {
        float perspY = max(0.001, groundLine - uv.y);
        float2 crystalUV = float2(uv.x / (perspY * 2.0 + 0.5), 1.0 / (perspY * 3.0));
        crystalUV.x += t * 0.02;
        float crystal = av_crystalPattern(crystalUV, u.time);
        float3 iceColor = float3(0.06, 0.08, 0.12);
        float3 iceCrystalColor = float3(0.18, 0.22, 0.32);
        float3 iceSurface = mix(iceColor, iceCrystalColor, crystal * 0.5);

        // ── Aurora reflection on ice ──
        float2 reflUV = float2(uv.x, -uv.y - groundLine * 2.0);
        float rr1 = av_auroraRibbon(reflUV, t, 0.0, 0.25, 2.5, 0.28, 0.0) * 0.3;
        float rr2 = av_auroraRibbon(reflUV, t * 0.9, 0.35, 0.20, 2.8, 0.24, 2.1) * 0.2;
        float rr3 = av_auroraRibbon(reflUV, t * 0.75, -0.30, 0.18, 3.0, 0.22, 4.3) * 0.15;
        float3 reflectionColor = r1color * rr1 + r2color * rr2 + r3color * rr3;
        reflectionColor *= auroraIntensity * pulse;
        float reflStrength = smoothstep(0.25, 0.0, perspY) * 0.6;
        float sparkle = pow(crystal, 3.0) * reflStrength;
        float3 sparkleColor = float3(0.9, 0.85, 0.7) * sparkle * 0.3;
        iceSurface += reflectionColor * reflStrength + sparkleColor;
        col = mix(col, iceSurface, groundFade);
    }

    // ── Horizon glow ──
    float horizonDist = abs(uv.y - groundLine);
    float horizonGlow = exp(-horizonDist * horizonDist / 0.003);
    float3 horizonColor = mix(
        float3(0.10, 0.20, 0.08),
        float3(0.12, 0.08, 0.18),
        0.5 + 0.5 * sin(t * 0.2)
    ) * min(totalAurora, 3.0) * 0.35 + float3(0.02, 0.03, 0.04);
    col += horizonColor * horizonGlow;

    // ── Vignette ──
    float dist = length(uv * float2(0.7, 0.9));
    float vignette = 1.0 - smoothstep(0.5, 1.5, dist);
    col *= 0.7 + vignette * 0.3;

    // ── Ensure no negatives ──
    col = max(col, float3(0.0));

    // ── Subtle tone curve ──
    col = pow(col, float3(0.92, 0.95, 0.98));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
