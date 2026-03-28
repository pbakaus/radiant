#include "../Common.metal"

// ─── Jazz Chaos: Syncopated particle groups with implied jazz rhythms ───
// Ported from static/jazz-chaos.html
// Approach: Four instrument groups (bass, lead, piano, drums) evaluated
// analytically per-pixel with rhythm-driven pulsing and orbital motion.

constant float JC_TEMPO = 120.0;           // BPM
constant float JC_SWING = 0.6;             // swing amount 0..1
constant float JC_BASS_COUNT = 20.0;       // bass particles
constant float JC_LEAD_COUNT = 50.0;       // lead particles
constant float JC_PIANO_COUNT = 35.0;      // piano particles
constant float JC_DRUM_COUNT = 25.0;       // drum particles
constant float JC_SOLO_CYCLE = 16.0;       // seconds between solos

// Group colors (warm amber palette)
static float3 jc_group_color(int group) {
    if (group == 0) return float3(0.627, 0.392, 0.196);  // bass - deep amber
    if (group == 1) return float3(0.941, 0.784, 0.392);  // lead - bright gold
    if (group == 2) return float3(0.784, 0.585, 0.424);  // piano - classic amber
    return float3(1.0, 0.902, 0.627);                     // drums - bright flash
}

// Hash
static float jc_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float jc_hash1(float s) {
    return fract(sin(s * 127.1 + 311.7) * 43758.5453);
}

// Beat timing
static float jc_beat_duration() { return 60.0 / JC_TEMPO; }

static float jc_swing_pulse(float time) {
    float beatLen = jc_beat_duration();
    float pos = fract(time / beatLen);
    return exp(-pos * 5.0);
}

static int jc_current_beat(float time) {
    float beatLen = jc_beat_duration();
    return int(fmod(time / beatLen, 4.0));
}

static float jc_beat_phase(float time) {
    float beatLen = jc_beat_duration();
    return fract(time / beatLen);
}

// Solo system: deterministic from time
static float jc_solo_intensity(int group, float time) {
    float soloCycle = JC_SOLO_CYCLE;
    float soloPhase = fract(time / soloCycle);
    // Solo active during 0.3..0.6 of each cycle
    if (soloPhase > 0.3 && soloPhase < 0.6) {
        int soloGroup = int(fmod(floor(time / soloCycle), 4.0));
        if (group == soloGroup) return 1.6;
        return 0.3;
    }
    return 1.0;
}

// Evaluate particle contribution at UV
static float3 jc_eval_group(float2 uv, float2 center, float time,
                             int group, float count, float aspect) {
    float3 groupCol = jc_group_color(group);
    float intensity = jc_solo_intensity(group, time);
    float beatLen = jc_beat_duration();
    int beat = jc_current_beat(time);
    float bPhase = jc_beat_phase(time);
    float3 accum = float3(0.0);

    for (int i = 0; i < int(count); i++) {
        float fi = float(i);
        float seed = fi * 17.3 + float(group) * 1000.0;

        // Base orbital position
        float orbitAngle = jc_hash1(seed) * 6.28318;
        float orbitRadius = (0.1 + jc_hash1(seed + 1.0) * 0.35);
        float orbitSpeed = (0.1 + jc_hash1(seed + 2.0) * 0.3);
        if (jc_hash1(seed + 3.0) < 0.5) orbitSpeed = -orbitSpeed;

        float hueShift = (jc_hash1(seed + 4.0) - 0.5) * 0.12;
        float brightness = 0.5 + jc_hash1(seed + 5.0) * 0.5;

        // Group-specific behavior
        float2 particlePos;
        float size;
        float flashBright = 0.0;

        if (group == 0) {
            // Bass: slow orbit, pulse on downbeats
            orbitAngle += orbitSpeed * time * 0.3 * intensity;
            particlePos = center + float2(cos(orbitAngle), sin(orbitAngle) / aspect) * orbitRadius;
            float downbeatPulse = (beat == 0 || beat == 2) ? jc_swing_pulse(time) * intensity : 0.0;
            size = (0.006 + jc_hash1(seed + 6.0) * 0.006) * (1.0 + downbeatPulse * 0.8);
            // Burst outward on pulse
            if (downbeatPulse > 0.8) {
                float burstAngle = atan2(particlePos.y - center.y, particlePos.x - center.x);
                particlePos += float2(cos(burstAngle), sin(burstAngle)) * 0.015 * downbeatPulse;
            }
        } else if (group == 1) {
            // Lead: syncopated runs — particle jitters around orbit
            float rhythmOffset = jc_hash1(seed + 7.0) * 0.5;
            float syncPhase = fract((time + rhythmOffset * beatLen) / beatLen);

            // Occasional burst movement
            float runTrigger = jc_hash(float2(floor(time / beatLen + rhythmOffset), fi));
            float runActive = (syncPhase < 0.3 && runTrigger < 0.3 * intensity) ? 1.0 : 0.0;
            float runAngle = jc_hash1(seed + 8.0 + floor(time / beatLen)) * 6.28;
            float jitter = runActive * 0.08 * (1.0 - syncPhase / 0.3);

            orbitAngle += orbitSpeed * time * 0.5;
            particlePos = center + float2(cos(orbitAngle), sin(orbitAngle) / aspect) * orbitRadius * 0.5;
            particlePos += float2(cos(runAngle), sin(runAngle)) * jitter;
            size = (0.002 + jc_hash1(seed + 6.0) * 0.003);
        } else if (group == 2) {
            // Piano: walking swing rhythm with wobble
            float rhythmOffset = jc_hash1(seed + 7.0) * 0.5;
            float swingPoint = 0.5 + JC_SWING * 0.25;
            float walkPhase = fract((time + rhythmOffset * beatLen) / beatLen);
            float walkSpeed = walkPhase < swingPoint ? 1.2 : 2.5;

            orbitAngle += orbitSpeed * time * walkSpeed * intensity;
            float wobble = sin(time * 3.0 + jc_hash1(seed + 9.0) * 6.28) * 0.02;
            particlePos = center + float2(cos(orbitAngle), sin(orbitAngle) / aspect) * (orbitRadius + wobble);
            float stepPulse = jc_swing_pulse(time + rhythmOffset * beatLen);
            size = (0.003 + jc_hash1(seed + 6.0) * 0.004) * (1.0 + stepPulse * 0.3);
        } else {
            // Drums: tight orbits, flashes on offbeats
            orbitAngle += orbitSpeed * time * 0.8;
            particlePos = center + float2(cos(orbitAngle), sin(orbitAngle) / aspect) * orbitRadius * 0.7;

            // Offbeat flash
            float offbeatZone = step(0.5 + JC_SWING * 0.15, bPhase) *
                               step(bPhase, 0.5 + JC_SWING * 0.15 + 0.12);
            flashBright = offbeatZone * intensity;

            // Random hi-hat flashes
            float eighthPhase = fract(time / (beatLen * 0.25));
            float hhTrigger = jc_hash(float2(floor(time / (beatLen * 0.25)), fi));
            if (eighthPhase < 0.08 && hhTrigger < 0.4) {
                flashBright = max(flashBright, 0.5 * intensity);
            }

            size = (0.003 + jc_hash1(seed + 6.0) * 0.003) * (1.0 + flashBright * 1.5);
        }

        // Distance from pixel to particle
        float2 diff = uv - particlePos;
        diff.x *= aspect;
        float dist = length(diff);

        if (dist > size * 8.0) continue;

        // Particle color with per-particle hue variation
        float3 pCol = groupCol + float3(hueShift, hueShift * 0.5, hueShift * 0.3);

        // Drum flash: brighten color
        if (group == 3 && flashBright > 0.0) {
            pCol = min(pCol + float3(flashBright * 0.196, flashBright * 0.157, flashBright * 0.078), float3(1.0));
        }

        // Alpha
        float alpha = 0.6 + brightness * 0.3;
        if (group == 3) alpha += flashBright * 0.4;

        // Solo dimming
        float soloInt = jc_solo_intensity(group, time);
        if (soloInt < 1.0) alpha *= 0.4;
        else if (soloInt > 1.0) alpha = min(1.0, alpha * 1.3);

        // Glow
        float glowSize = size * 3.0;
        float glowAlpha = 0.06 + brightness * 0.04;
        if (group == 3) { glowAlpha += flashBright * 0.15; glowSize += flashBright * 0.01; }
        if (soloInt > 1.0) glowAlpha *= 1.4;
        else if (soloInt < 1.0) glowAlpha *= 0.5;
        glowAlpha = min(glowAlpha, 0.3);
        float glow = smoothstep(glowSize, 0.0, dist) * glowAlpha;
        accum += pCol * glow;

        // Core
        float core = smoothstep(size, size * 0.2, dist) * alpha;
        accum += pCol * core;

        // Hot center for bass and drum flashes
        if (group == 0 || (group == 3 && flashBright > 0.3)) {
            float centerAlpha = (group == 0 ? 0.4 : flashBright * 0.6) * brightness;
            if (soloInt < 1.0) centerAlpha *= 0.3;
            float hotCore = smoothstep(size * 0.35, 0.0, dist) * centerAlpha;
            accum += float3(1.0, 0.973, 0.902) * hotCore;
        }
    }

    return accum;
}

fragment float4 fs_jazz_chaos(VSOut in [[stage_in]],
                               constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 centered = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float aspect = u.resolution.x / u.resolution.y;
    float t = u.time;

    float2 center = float2(0.5, 0.5);

    // Background
    float3 col = float3(0.039, 0.039, 0.039);

    // Warm stage spotlight
    float spotDist = length(centered - float2(0.0, -0.2));
    col += float3(0.784, 0.585, 0.424) * smoothstep(0.7, 0.0, spotDist) * 0.04;
    col += float3(0.706, 0.471, 0.275) * smoothstep(1.0, 0.0, spotDist) * 0.02;

    // Beat pulse
    float pulse = jc_swing_pulse(t);
    col += float3(0.784, 0.585, 0.424) * pulse * 0.025 * smoothstep(0.5, 0.0, length(centered));

    // Evaluate all 4 groups
    col += jc_eval_group(uv, center, t, 0, JC_BASS_COUNT, aspect);
    col += jc_eval_group(uv, center, t, 1, JC_LEAD_COUNT, aspect);
    col += jc_eval_group(uv, center, t, 2, JC_PIANO_COUNT, aspect);
    col += jc_eval_group(uv, center, t, 3, JC_DRUM_COUNT, aspect);

    // Vignette
    float vigDist = length(centered);
    float vig = smoothstep(0.2, 0.85, vigDist);
    col *= 1.0 - vig * 0.55;

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
