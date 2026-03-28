#include "../Common.metal"

// ─── Event Horizon: Schwarzschild black hole ray tracer ───
// Ported from static/event-horizon.html
// Verlet geodesic integration, Novikov-Thorne disk, Doppler beaming

constant float EH_PI = 3.14159265359;
constant float EH_TAU = 6.28318530718;
constant float EH_RS = 1.0;          // Schwarzschild radius
constant float EH_ISCO = 3.0;        // Innermost stable circular orbit
constant float EH_DISK_IN = 2.2;     // Inner glow edge
constant float EH_DISK_OUT = 14.0;   // Outer disk edge
constant float EH_ROTATION_SPEED = 0.3;
constant float EH_DISK_INTENSITY = 1.0;
constant float EH_TILT = 0.0;
constant float EH_ROTATE = 0.0;
constant float EH_CHROMATIC = 0.0;
constant int EH_MAX_STEPS = 200;

// ── Hash — PCG-inspired, no sin() ──
static float eh_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Gradient noise with quintic interpolation ──
static float eh_gNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(
        mix(eh_hash(i), eh_hash(i + float2(1.0, 0.0)), u.x),
        mix(eh_hash(i + float2(0.0, 1.0)), eh_hash(i + float2(1.0, 1.0)), u.x),
        u.y
    );
}

// ── FBM with domain rotation ──
static float eh_fbm(float2 p) {
    float v = 0.0, a = 0.5;
    float2x2 rot = float2x2(float2(0.866, 0.5), float2(-0.5, 0.866));
    for (int i = 0; i < 4; i++) {
        v += a * eh_gNoise(p);
        p = rot * p * 2.03 + float2(47.0, 13.0);
        a *= 0.49;
    }
    return v;
}

// ── Lightweight 2-octave noise ──
static float eh_fbmLite(float2 p) {
    float v = 0.5 * eh_gNoise(p);
    float2x2 rot = float2x2(float2(0.866, 0.5), float2(-0.5, 0.866));
    p = rot * p * 2.03 + float2(47.0, 13.0);
    v += 0.25 * eh_gNoise(p);
    return v;
}

// ── Star field — cell-based with spherical UV ──
static float3 eh_starField(float3 rd) {
    float su = atan2(rd.z, rd.x) / EH_TAU + 0.5;
    float sv = asin(clamp(rd.y, -0.999, 0.999)) / EH_PI + 0.5;
    float3 col = float3(0.0);

    // Bright sparse stars
    {
        float2 cell = floor(float2(su, sv) * 55.0);
        float2 f = fract(float2(su, sv) * 55.0);
        float2 r = float2(eh_hash(cell), eh_hash(cell + 127.1));
        float d = length(f - r);
        float b = pow(r.x, 10.0) * exp(-d * d * 500.0);
        col += mix(float3(1.0, 0.65, 0.35), float3(0.55, 0.75, 1.0), r.y) * b * 4.0;
    }
    // Medium density stars
    {
        float2 cell = floor(float2(su, sv) * 170.0);
        float2 f = fract(float2(su, sv) * 170.0);
        float2 r = float2(eh_hash(cell + 43.0), eh_hash(cell + 91.0));
        float d = length(f - r);
        float b = pow(r.x, 18.0) * exp(-d * d * 1000.0);
        col += float3(0.85, 0.88, 1.0) * b * 2.0;
    }
    // Subtle nebula
    float n = eh_fbmLite(float2(su, sv) * 3.0) * eh_fbmLite(float2(su, sv) * 5.5 + 10.0);
    col += float3(0.10, 0.04, 0.14) * pow(n, 3.0);

    return col;
}

// ── Blackbody color ──
static float3 eh_bbColor(float t) {
    t = clamp(t, 0.0, 2.5);
    float3 lo = float3(1.0, 0.18, 0.0);
    float3 mi = float3(1.0, 0.55, 0.12);
    float3 hi = float3(1.0, 0.93, 0.82);
    float3 hot = float3(0.65, 0.82, 1.0);
    float3 c = mix(lo, mi, smoothstep(0.0, 0.3, t));
    c = mix(c, hi, smoothstep(0.3, 0.8, t));
    return mix(c, hot, smoothstep(0.8, 1.8, t));
}

// ── Accretion disk shading ──
static float4 eh_shadeDisk(float3 hit, float3 vel, float time) {
    float r = length(hit.xz);
    if (r < EH_DISK_IN * 0.5 || r > EH_DISK_OUT * 1.05) return float4(0.0);

    float xr = EH_ISCO / r;
    float tProfile = pow(EH_ISCO / r, 0.75) * pow(max(0.001, 1.0 - sqrt(xr)), 0.25);

    float gRedshift = sqrt(max(0.01, 1.0 - EH_RS / r));
    tProfile *= gRedshift;

    float lr = log2(max(r, 0.1));

    float keplerOmega = sqrt(0.5 * EH_RS / (r * r * r));
    float baseOmega = 0.04;
    float omega = max(keplerOmega, baseOmega) * 10.0;
    float rotAngle = time * omega;
    float ca = cos(rotAngle), sa = sin(rotAngle);
    float2 rotXZ = float2(hit.x * ca - hit.z * sa, hit.x * sa + hit.z * ca);

    float turb = eh_fbm(rotXZ * 1.2 + float2(lr * 3.0, 0.0));
    turb = 0.25 + 0.75 * turb;

    float timeShift = time * 0.15;
    float detail = eh_gNoise(rotXZ * 3.5 + float2(100.0 + timeShift, timeShift * 0.7));
    turb *= 0.7 + 0.3 * detail;

    float ringPhase1 = sin(r * 10.0 + rotAngle * r * 0.3) * 0.5 + 0.5;
    float ringPhase2 = sin(r * 20.0 - rotAngle * r * 0.15) * 0.5 + 0.5;
    float rings = ringPhase1 * 0.55 + ringPhase2 * 0.45;
    rings = 0.5 + 0.5 * rings;
    turb *= rings;

    float orbSpeed = sqrt(0.5 * EH_RS / max(r, EH_DISK_IN));
    float3 orbDir = normalize(float3(-hit.z, 0.0, hit.x));
    float dopplerFactor = 1.0 + 2.0 * dot(normalize(vel), orbDir) * orbSpeed;
    dopplerFactor = max(0.15, dopplerFactor);
    float dopplerBoost = dopplerFactor * dopplerFactor * dopplerFactor;

    float I = tProfile * turb * 6.0;

    float innerFade = smoothstep(EH_DISK_IN * 0.7, EH_DISK_IN * 1.2, r);
    float iscoFade = 0.35 + 0.65 * smoothstep(EH_ISCO * 0.85, EH_ISCO * 1.2, r);
    float outerFade = 1.0 - smoothstep(EH_DISK_OUT * 0.55, EH_DISK_OUT, r);
    I *= innerFade * iscoFade * outerFade;

    float colorTemp = tProfile * pow(dopplerFactor, 1.8) * 1.2;
    float3 col = eh_bbColor(colorTemp) * I * dopplerBoost;

    // Chromatic dispersion
    if (EH_CHROMATIC > 0.01) {
        float spectralR = (r - EH_DISK_IN) / (EH_DISK_OUT - EH_DISK_IN);
        float ringP = ringPhase1;
        float hue = spectralR * 0.8 + ringP * 0.4;

        float3 spectrum;
        spectrum.r = (1.0 - smoothstep(0.0, 0.35, hue))
                   + smoothstep(0.25, 0.45, hue) * (1.0 - smoothstep(0.55, 0.7, hue)) * 0.7
                   + smoothstep(0.85, 1.1, hue) * 0.4;
        spectrum.g = smoothstep(0.15, 0.4, hue) * (1.0 - smoothstep(0.7, 0.95, hue));
        spectrum.b = smoothstep(0.5, 0.8, hue)
                   + smoothstep(0.85, 1.1, hue) * 0.3;
        spectrum = max(spectrum, float3(0.05));

        float luma = dot(col, float3(0.3, 0.5, 0.2));
        float3 chromaCol = spectrum * luma * 2.0;
        col = mix(col, chromaCol, EH_CHROMATIC * 0.75);
    }

    float alpha = clamp(I * 1.3, 0.0, 0.96);
    return float4(col, alpha);
}

fragment float4 fs_event_horizon(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 fc = in.pos.xy;
    float2 ctr = float2(0.5) * u.resolution;
    float2 uv = (fc - ctr) / u.resolution.x;

    // Orbital camera
    float camR = 28.0;
    float orbit = u.time * 0.055 * EH_ROTATION_SPEED;
    float tilt = 0.25 + EH_TILT;

    float3 eye = float3(
        camR * cos(orbit) * cos(tilt),
        camR * sin(tilt),
        camR * sin(orbit) * cos(tilt)
    );

    // Look-at basis
    float3 fwd = normalize(-eye);
    float3 rt = normalize(cross(fwd, float3(0.0, 1.0, 0.0)));
    float3 up = cross(rt, fwd);

    // Roll rotation
    float cr = cos(EH_ROTATE), sr = sin(EH_ROTATE);
    float3 rr = cr * rt + sr * up;
    float3 ru = -sr * rt + cr * up;

    float3 rd = normalize(fwd + uv.x * rr + uv.y * ru);

    // ── Geodesic integration ──
    float3 pos = eye;
    float3 vel = rd;

    float3 Lvec = cross(pos, vel);
    float L2 = dot(Lvec, Lvec);

    float4 diskAccum = float4(0.0);
    float3 glow = float3(0.0);
    bool absorbed = false;
    int diskCrossings = 0;
    float minR = 1000.0;

    float gravCoeff = -1.5 * EH_RS * L2;

    for (int i = 0; i < EH_MAX_STEPS; i++) {
        float r = length(pos);

        float h = 0.16 * clamp(r - 0.4 * EH_RS, 0.06, 3.5);

        float invR2 = 1.0 / (r * r);
        float invR5 = invR2 * invR2 / r;
        float3 acc = (gravCoeff * invR5) * pos;

        float3 p1 = pos + vel * h + 0.5 * acc * h * h;
        float r1 = length(p1);
        float invR12 = 1.0 / (r1 * r1);
        float invR15 = invR12 * invR12 / r1;
        float3 acc1 = (gravCoeff * invR15) * p1;
        float3 v1 = vel + 0.5 * (acc + acc1) * h;

        minR = min(minR, r1);

        // Disk crossing detection (y=0 plane)
        if (pos.y * p1.y < 0.0 && diskAccum.a < 0.97) {
            float tc = pos.y / (pos.y - p1.y);
            float3 hit = mix(pos, p1, tc);
            float4 dc = eh_shadeDisk(hit, vel, u.time * EH_ROTATION_SPEED);
            dc.rgb *= EH_DISK_INTENSITY;
            if (diskCrossings >= 2) {
                dc.rgb *= 0.15;
                dc.a *= 0.15;
            }
            diskAccum.rgb += dc.rgb * dc.a * (1.0 - diskAccum.a);
            diskAccum.a += dc.a * (1.0 - diskAccum.a);
            float diskBright = dot(dc.rgb, float3(0.3, 0.5, 0.2)) * dc.a;
            glow += dc.rgb * 0.04 * max(diskBright - 0.3, 0.0);
            diskCrossings++;
        }

        // Glow calculations near BH
        if (r1 < 6.0) {
            float pDist = abs(r1 - 1.5 * EH_RS);
            float psGlow = 1.0 / (1.0 + pDist * pDist * 20.0) * h * 0.001 / max(r1 * r1, 0.2);
            glow += float3(0.8, 0.6, 0.35) * psGlow;

            float hzGlow = exp(-(r1 - EH_RS) * 3.5) * h * 0.003;
            glow += float3(0.5, 0.25, 0.08) * max(hzGlow, 0.0);
        }

        // Termination
        if (r1 < EH_RS * 0.35) { absorbed = true; break; }
        if (r1 > 25.0 && r1 > r) break;
        if (r1 > 55.0) break;

        pos = p1;
        vel = v1;
    }

    // ── Final compositing ──
    float3 col = float3(0.0);
    if (!absorbed) {
        col = eh_starField(normalize(vel));
    }
    col = col * (1.0 - diskAccum.a) + diskAccum.rgb;

    // Shadow-edge chromatic fringe
    float ringDist = abs(minR - 1.5 * EH_RS);
    float chromo = EH_CHROMATIC;
    float baseChroma = 0.1 + 0.5 * chromo;
    float spread = 0.08 + 0.18 * chromo;
    float falloff = 20.0 + 15.0 * (1.0 - chromo);
    float rRing = exp(-(ringDist + spread) * (ringDist + spread) * falloff);
    float bRing = exp(-(ringDist - spread) * (ringDist - spread) * falloff);
    col.r += rRing * 0.3 * baseChroma;
    col.b += bRing * 0.35 * baseChroma;

    // Glow additive
    col += glow;

    // Filmic tone mapping (ACES-inspired)
    col *= 1.4;
    float3 a = col * (col + 0.0245786) - 0.000090537;
    float3 b = col * (0.983729 * col + 0.4329510) + 0.238081;
    col = a / b;

    col = smoothstep(float3(0.0), float3(1.0), col);
    col = pow(max(col, float3(0.0)), float3(0.92));

    col = hue_rotate(col, u.hue_shift);
    return float4(clamp(col, float3(0.0), float3(1.0)), 1.0);
}
