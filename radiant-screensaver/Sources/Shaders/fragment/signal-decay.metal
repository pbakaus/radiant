#include "../Common.metal"

// ─── Signal Decay: Clean harmonics dissolving into warm noise ───
// Ported from static/signal-decay.html

constant float SD_TAU = 6.28318530;
constant int SD_NUM_TRACKS = 10;
constant float SD_SIGNAL_SPEED = 0.5;
constant float SD_DECAY_INTENSITY = 1.0;

// ── Hash ──
static float sd_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Value noise ──
static float sd_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = sd_hash(i);
    float b = sd_hash(i + float2(1.0, 0.0));
    float c = sd_hash(i + float2(0.0, 1.0));
    float d = sd_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float sd_fbm(float2 p) {
    float f = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) {
        f += a * sd_vnoise(p);
        p *= 2.07;
        a *= 0.5;
    }
    return f;
}

// ── Soft clip ──
static float sd_softClip(float x, float amt) {
    float k = mix(1.0, 5.0, amt);
    float kx = k * x;
    float ax = abs(kx);
    return (kx / (1.0 + ax + 0.28 * kx * kx));
}

// ── Hard clip ──
static float sd_hardClip(float x, float amt) {
    float th = mix(1.0, 0.2, amt);
    return clamp(x, -th, th) / max(th, 0.001);
}

// ── Bit crush ──
static float sd_bitCrush(float x, float amt) {
    float levels = mix(128.0, 3.0, amt * amt);
    return floor(x * levels + 0.5) / levels;
}

// ── Compute one degraded harmonic ──
static float sd_degradedWave(float x, float t, float freq, float ph, float amp, float decay) {
    float speed = SD_SIGNAL_SPEED;
    float phase = x * freq * SD_TAU + ph + t * speed * (1.5 + freq * 0.2);

    float pd = decay * decay * 2.0;
    phase += pd * sin(phase * 1.7 + t * 0.3) + pd * 0.4 * sin(phase * 3.1);

    float fm = decay * 1.2;
    float w = sin(phase + fm * sin(phase * 2.13 + t * 0.5));

    float am = 1.0 - decay * 0.35 * (0.5 + 0.5 * sin(x * 2.5 + t * speed * 1.3 + ph));
    w *= am;

    float sc = smoothstep(0.08, 0.35, decay);
    w = mix(w, sd_softClip(w, sc), sc);

    float hc = smoothstep(0.25, 0.55, decay);
    w = mix(w, sd_hardClip(w, hc), hc);

    float bc = smoothstep(0.45, 0.8, decay);
    w = mix(w, sd_bitCrush(w, bc), bc);

    float ni = smoothstep(0.35, 0.9, decay);
    float noise = (sd_hash(float2(x * 50.0 + ph, t * 7.0 + freq)) - 0.5) * 2.0;
    w = mix(w, w + noise * 0.4, ni);

    return w * amp;
}

// ── Full composite: 6 harmonics ──
static float sd_compositeWave(float x, float t, float decay) {
    float w = 0.0;
    w += sd_degradedWave(x, t, 1.0,   0.0,   0.32, decay);
    w += sd_degradedWave(x, t, 1.618, 1.047, 0.26, decay);
    w += sd_degradedWave(x, t, 2.414, 2.094, 0.20, decay);
    w += sd_degradedWave(x, t, 3.302, 3.665, 0.16, decay);
    w += sd_degradedWave(x, t, 4.236, 0.524, 0.12, decay);
    w += sd_degradedWave(x, t, 5.879, 4.189, 0.09, decay);
    return w;
}

// ── Glowing line SDF ──
static float sd_glowLine(float d, float w, float g) {
    float core = smoothstep(w, 0.0, abs(d));
    float bloom = exp(-abs(d) / max(g, 0.0001)) * 0.45;
    return core + bloom;
}

// ── Glitch horizontal offset ──
static float sd_glitch(float y, float t, float decay) {
    float amt = smoothstep(0.3, 0.7, decay);
    float g1 = step(0.96, sd_hash(float2(floor(y * 60.0), floor(t * 4.0))));
    float g2 = step(0.93, sd_hash(float2(floor(y * 30.0), floor(t * 6.0 + 77.0))));
    float offset = g1 * (sd_hash(float2(y * 11.0, t * 3.0)) - 0.5) * 0.1;
    offset += g2 * (sd_hash(float2(y * 23.0, t * 5.0 + 50.0)) - 0.5) * 0.05;
    return offset * amt;
}

fragment float4 fs_signal_decay(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 fragCoord = in.pos.xy;
    float2 uv = fragCoord / u.resolution;
    float ar = u.resolution.x / u.resolution.y;
    float t = u.time;

    // yNorm: 0 at top, 1 at bottom (no mouse interaction)
    float yNorm = 1.0 - uv.y;
    float decay = clamp(pow(max(yNorm, 0.0), 0.75) * SD_DECAY_INTENSITY, 0.0, 1.0);

    float gOff = sd_glitch(yNorm, t, decay);

    // ── Accumulate waveform lines ──
    float3 col = float3(0.0);

    float3 colClean   = float3(0.78, 0.58, 0.42);
    float3 colDistort = float3(1.0,  0.76, 0.45);
    float3 colHot     = float3(1.0,  0.92, 0.72);
    float3 colNoise   = float3(0.62, 0.45, 0.30);

    float trackH = 1.0 / float(SD_NUM_TRACKS);

    for (int i = 0; i < SD_NUM_TRACKS; i++) {
        float fi = float(i);
        float trackCenter = (fi + 0.5) * trackH;

        float tYNorm = 1.0 - trackCenter;
        float tDecay = clamp(pow(tYNorm, 0.75) * SD_DECAY_INTENSITY, 0.0, 1.0);

        float tOff = fi * 0.391;
        float x = (uv.x + gOff) * ar + tOff;

        float wave = sd_compositeWave(x, t + fi * 0.17, tDecay);

        float ampScale = trackH * 0.38 * (1.0 + tDecay * 0.6);
        float waveY = trackCenter + wave * ampScale;

        float dist = uv.y - waveY;

        float lw = mix(0.0006, 0.0025, tDecay);
        float gw = mix(0.003, 0.014, tDecay * tDecay);

        float fragAmt = smoothstep(0.5, 0.85, tDecay);
        float dashMask = 1.0;
        float dashFreq = mix(25.0, 90.0, fragAmt);
        float dashSeed = sd_hash(float2(floor(x * dashFreq), fi + floor(t * 2.5)));
        dashMask = mix(1.0, step(0.28, dashSeed), fragAmt);

        float line = sd_glowLine(dist, lw, gw) * dashMask;

        float3 tCol = mix(colClean, colDistort, smoothstep(0.15, 0.5, tDecay));
        tCol = mix(tCol, colHot, smoothstep(0.45, 0.75, tDecay));

        float chromaStr = smoothstep(0.45, 0.85, tDecay) * 0.008;
        float3 lineCol = tCol * line;

        if (chromaStr > 0.0001) {
            float xA = x + chromaStr * ar * 8.0;
            float xB = x - chromaStr * ar * 8.0;
            float waveA = sd_compositeWave(xA, t + fi * 0.17, tDecay);
            float waveB = sd_compositeWave(xB, t + fi * 0.17, tDecay);
            float waveYA = trackCenter + waveA * ampScale;
            float waveYB = trackCenter + waveB * ampScale;
            float lineA = sd_glowLine(uv.y - waveYA, lw, gw) * dashMask;
            float lineBv = sd_glowLine(uv.y - waveYB, lw, gw) * dashMask;
            float3 warmA = float3(1.0, 0.55, 0.25);
            float3 warmB = float3(1.0, 0.85, 0.4);
            float chromaMix = smoothstep(0.45, 0.85, tDecay);
            float3 monoLine = tCol * line;
            float3 chromaLine = warmA * lineA * 0.5 + warmB * lineBv * 0.35 + tCol * line * 0.3;
            lineCol = mix(monoLine, chromaLine, chromaMix);
        }

        col += lineCol;
    }

    // ── Noise floor (bottom 25%) ──
    float nfAmt = smoothstep(0.65, 1.0, yNorm) * SD_DECAY_INTENSITY;
    if (nfAmt > 0.001) {
        float n1 = sd_fbm(fragCoord * 0.012 + float2(t * 0.4, 0.0));
        float n2 = sd_vnoise(fragCoord * float2(0.25, 0.008) + float2(t * 2.5, 0.0));
        float band = sd_vnoise(float2(t * 3.5, fragCoord.y * 0.08)) * 0.5 + 0.5;
        float nf = n1 * 0.55 + n2 * 0.3 + band * 0.15;

        // Ghost lines
        float ghostX = uv.x * ar;
        for (int gi = 0; gi < 3; gi++) {
            float gfi = float(gi);
            float gWave = sd_compositeWave(ghostX + gfi * 0.5, t + gfi * 0.3, 0.0);
            float gLine = exp(-abs((1.0 - uv.y) - (0.88 + gfi * 0.03) - gWave * 0.015) * 250.0);
            nf += gLine * 0.12;
        }

        float3 nfCol = colNoise + float3(0.08, -0.02, -0.05) * sd_vnoise(fragCoord * 0.05 + t);
        col += nfCol * nf * nfAmt * 0.7;
    }

    // ── Warm ambient glow ──
    col += float3(0.42, 0.28, 0.16) * decay * 0.018;

    // ── Background gradient ──
    float3 bg = mix(float3(0.035, 0.035, 0.038), float3(0.05, 0.04, 0.035), yNorm);
    col += bg;

    // ── Vignette ──
    float2 vc = uv - 0.5;
    float vig = 1.0 - dot(vc * float2(0.9, 0.55), vc * float2(0.9, 0.55)) * 1.4;
    col *= clamp(0.45 + 0.55 * vig, 0.0, 1.0);

    // ── Film grain ──
    float grain = (sd_hash(fragCoord + fract(t * 0.07) * 137.0) - 0.5) * 0.022;
    col += grain;

    // ── Tone map: gentle S-curve ──
    col = clamp(col, float3(0.0), float3(1.0));
    col = col * col * (3.0 - 2.0 * col);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
