#include "../Common.metal"

// ─── Magnetic Sand: Particles aligned to magnetic dipole field lines ───
// Ported from static/magnetic-sand.html
// Original: 5000 iron-filing particles that align and drift along 3 orbiting
// dipole sources with blended 1/r and 1/r^2 falloff. Fragment shader reimagines
// this as a per-pixel dipole field visualization: field-line texture +
// strength-based coloring + glowing dipole sources.

constant int MS_NUM_DIPOLES = 3;
constant float MS_FIELD_STRENGTH = 1.0;
constant float MS_LINE_DENSITY = 50.0;    // number of field lines visible
constant float MS_LINE_SHARPNESS = 20.0;  // how thin the filing streaks are
constant float MS_FILING_SCALE = 120.0;   // noise scale for filing texture

// ── Hash ──
static float ms_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth noise ──
static float ms_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ms_hash(i);
    float b = ms_hash(i + float2(1.0, 0.0));
    float c = ms_hash(i + float2(0.0, 1.0));
    float d = ms_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── Dipole position via Lissajous orbit ──
static float2 ms_dipolePos(int idx, float t) {
    float fi = float(idx);
    // Each dipole has unique Lissajous parameters
    float rx = 0.15 + 0.12 * ms_hash(float2(fi * 3.7, 1.0));
    float ry = 0.15 + 0.12 * ms_hash(float2(fi * 5.3, 2.0));
    float fx = 0.06 + 0.05 * ms_hash(float2(fi * 7.1, 3.0));
    float fy = 0.04 + 0.05 * ms_hash(float2(fi * 9.7, 4.0));
    float px = ms_hash(float2(fi * 11.3, 5.0)) * 6.2832;
    float py = ms_hash(float2(fi * 13.1, 6.0)) * 6.2832;

    // Slowly modulate orbit radius
    float rxMod = rx + 0.04 * sin(t * 0.013 + fi * 2.1);
    float ryMod = ry + 0.04 * cos(t * 0.011 + fi * 1.7);

    float x = 0.5 + rxMod * sin(t * fx + px);
    float y = 0.5 + ryMod * cos(t * fy + py);
    return float2(x, y);
}

// ── Dipole angle ──
static float ms_dipoleAngle(int idx, float t) {
    float fi = float(idx);
    float freq = 0.015 + 0.02 * ms_hash(float2(fi * 15.7, 7.0));
    float phase = ms_hash(float2(fi * 17.3, 8.0)) * 6.2832;
    return t * freq + phase;
}

// ── Dipole strength ──
static float ms_dipoleStrength(int idx) {
    float fi = float(idx);
    return 0.85 + 0.3 * ms_hash(float2(fi * 19.1, 9.0));
}

// ── Magnetic field at a point ──
// Returns field vector and closest dipole distance
static float3 ms_fieldAt(float2 p, float t) {
    float2 B = float2(0.0);
    float closestR = 1e9;
    float refR = 0.3; // reference radius (normalized)

    for (int i = 0; i < MS_NUM_DIPOLES; i++) {
        float2 dPos = ms_dipolePos(i, t);
        float dAngle = ms_dipoleAngle(i, t);
        float dStr = ms_dipoleStrength(i);

        float2 delta = p - dPos;
        float r2 = dot(delta, delta);
        float minDist = refR * 0.12;
        float minR2 = minDist * minDist;
        if (r2 < minR2) r2 = minR2;
        float r = sqrt(r2);

        closestR = min(closestR, r);

        // Unit vector from dipole to point
        float2 rhat = delta / r;

        // Dipole moment direction
        float2 m = float2(cos(dAngle), sin(dAngle));

        // Dipole angular factor: 2*(m.rhat)*rhat - m
        float mdotr = dot(m, rhat);
        float2 dir = 2.0 * mdotr * rhat - m;

        // Blended falloff: 1/r^2 close, 1/r far
        float invR = refR / r;
        float falloff = 0.35 * invR * invR + 0.65 * invR;

        B += dStr * MS_FIELD_STRENGTH * falloff * dir;
    }

    return float3(B, closestR);
}

fragment float4 fs_magnetic_sand(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float aspect = res.x / res.y;
    float2 uv = in.pos.xy / res;
    float2 p = float2(uv.x * aspect, uv.y);
    float t = u.time;

    // Compute magnetic field
    float2 pNorm = float2(uv.x, uv.y); // use 0-1 coords for dipole positions
    float3 fieldResult = ms_fieldAt(pNorm, t);
    float2 B = fieldResult.xy;
    float Bmag = length(B);

    // Field strength (0 to 1)
    float fieldStr = clamp(Bmag * 1.2, 0.0, 1.0);

    // ── Iron filing texture ──
    // Create aligned streaks: noise sampled along field direction
    float2 fieldDir = Bmag > 0.001 ? B / Bmag : float2(1.0, 0.0);
    float2 perpDir = float2(-fieldDir.y, fieldDir.x);

    // Sample noise perpendicular to field (creates elongated streaks along field lines)
    float perpCoord = dot(p * MS_FILING_SCALE, perpDir);
    float paraCoord = dot(p * MS_FILING_SCALE * 0.3, fieldDir);

    // Multiple octaves for varied filing sizes
    float filingNoise = ms_noise(float2(perpCoord, paraCoord));
    filingNoise += ms_noise(float2(perpCoord * 2.1, paraCoord * 2.1)) * 0.5;
    filingNoise += ms_noise(float2(perpCoord * 4.3, paraCoord * 4.3)) * 0.25;
    filingNoise /= 1.75;

    // Create sharp filing lines from the perpendicular noise
    float filingDensity = sin(perpCoord * MS_LINE_DENSITY * 0.1) * 0.5 + 0.5;
    filingDensity = pow(filingDensity, MS_LINE_SHARPNESS * 0.1);

    // Modulate filing visibility by local noise (breaks up uniform lines)
    filingDensity *= smoothstep(0.3, 0.6, filingNoise);

    // ── Color by field strength (warm amber palette) ──
    float3 dimColor    = float3(120.0, 85.0, 50.0) / 255.0;
    float3 warmColor   = float3(160.0, 115.0, 68.0) / 255.0;
    float3 mediumColor = float3(200.0, 150.0, 90.0) / 255.0;
    float3 brightColor = float3(235.0, 185.0, 115.0) / 255.0;
    float3 hotColor    = float3(255.0, 215.0, 140.0) / 255.0;

    float3 filingColor;
    if (fieldStr < 0.15) {
        filingColor = mix(dimColor, warmColor, fieldStr / 0.15);
    } else if (fieldStr < 0.3) {
        filingColor = mix(warmColor, mediumColor, (fieldStr - 0.15) / 0.15);
    } else if (fieldStr < 0.5) {
        filingColor = mix(mediumColor, brightColor, (fieldStr - 0.3) / 0.2);
    } else {
        filingColor = mix(brightColor, hotColor, clamp((fieldStr - 0.5) / 0.5, 0.0, 1.0));
    }

    // Filing alpha by field strength (more visible near dipoles)
    float filingAlpha = mix(0.3, 1.0, fieldStr) * filingDensity;

    // ── Dipole glow ──
    float3 glowCol = float3(0.0);
    for (int i = 0; i < MS_NUM_DIPOLES; i++) {
        float2 dPos = ms_dipolePos(i, t);
        float2 dp = pNorm - dPos;
        float dist = length(dp);
        float dStr = ms_dipoleStrength(i);
        float glowR = 0.3 * dStr * MS_FIELD_STRENGTH;

        // Multi-stop radial glow (matching original warm amber)
        float g1 = exp(-dist * dist / (glowR * glowR * 0.3));
        float g2 = exp(-dist * dist / (glowR * glowR));
        float g3 = exp(-dist * dist / (glowR * glowR * 3.0));

        glowCol += float3(220.0, 170.0, 90.0) / 255.0 * g1 * 0.28;
        glowCol += float3(170.0, 120.0, 60.0) / 255.0 * g2 * 0.12;
        glowCol += float3(90.0, 60.0, 30.0) / 255.0 * g3 * 0.06;
    }

    // ── Compose ──
    float3 col = float3(10.0 / 255.0); // dark background
    col += filingColor * filingAlpha;

    // Additive glow for high field strength areas
    if (fieldStr > 0.5) {
        float glowAmt = (fieldStr - 0.5) * 2.0;
        col += float3(255.0, 225.0, 170.0) / 255.0 * filingDensity * glowAmt * 0.15;
    }

    col += glowCol;

    // ── Vignette ──
    float2 vc = uv - 0.5;
    float vDist = length(vc);
    float vig = smoothstep(0.35, 1.0, vDist * 1.414);
    col *= 1.0 - vig * 0.4;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
