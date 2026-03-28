#include "../Common.metal"

// ─── Thunder Sermon: Dramatic lightning against a roiling storm sky ───
// Ported from static/thunder-sermon.html

// Default parameter values (screensaver — no interactive controls)
constant float TS_STRIKE_INTERVAL = 1.5;
constant float TS_FLASH_INTENSITY = 1.0;
constant float TS_PI = 3.14159265359;

// ── Hash functions ──
static float ts_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float ts_hash1(float n) {
    return fract(sin(n) * 43758.5453123);
}

// ── Smooth value noise ──
static float ts_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = ts_hash(i);
    float b = ts_hash(i + float2(1.0, 0.0));
    float c = ts_hash(i + float2(0.0, 1.0));
    float d = ts_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── FBM ──
static float ts_fbm(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 7; i++) {
        if (i >= octaves) break;
        val += amp * ts_noise(p * freq);
        freq *= 2.03;
        amp *= 0.5;
        p += float2(1.7, 9.2);
    }
    return val;
}

// ── Domain-warped storm clouds ──
static float ts_stormClouds(float2 p, float t) {
    float2 drift = float2(t * 0.03, t * 0.015);
    float2 pp = p + drift;
    float2 q = float2(
        ts_fbm(pp, 5),
        ts_fbm(pp + float2(5.2, 1.3), 5)
    );
    float2 r = float2(
        ts_fbm(pp + 3.0 * q + float2(1.7, 9.2) + t * 0.05, 6),
        ts_fbm(pp + 3.0 * q + float2(8.3, 2.8) + t * 0.03, 6)
    );
    float f = ts_fbm(pp + 2.5 * r, 7);
    return f * 0.5 + length(q) * 0.3 + length(r) * 0.2;
}

// ── Point-to-segment distance ──
static float ts_segDist(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// ── Lightning bolt ──
static float ts_lightningBolt(float2 uv, float seed, float startX, float endX) {
    float minD = 100.0;

    float prevX = startX;
    float prevY = -0.6;

    for (int i = 1; i <= 14; i++) {
        float fi = float(i);
        float frac = fi / 14.0;

        float jit = ts_hash1(seed * 13.37 + fi * 7.91) * 2.0 - 1.0;
        float jit2 = ts_hash1(seed * 29.13 + fi * 3.17) * 2.0 - 1.0;
        float disp = jit * 0.15 * (1.0 - frac * 0.4) + jit2 * 0.05;

        float targetX = mix(startX, endX, frac);
        float curX = targetX + disp;
        float curY = mix(-0.6, 0.55, frac);

        float d = ts_segDist(uv, float2(prevX, prevY), float2(curX, curY));
        minD = min(minD, d);

        // Branches
        float roll = ts_hash1(seed * 5.71 + fi * 11.3);
        if (roll > 0.45 && i > 1 && i < 13) {
            float side = (ts_hash1(seed * 3.3 + fi * 9.1) > 0.5) ? 1.0 : -1.0;
            float bLen = 0.08 + ts_hash1(seed * 7.7 + fi * 2.3) * 0.12;
            float bAng = 0.5 + ts_hash1(seed * 2.2 + fi * 5.5) * 0.6;

            float bpx = curX;
            float bpy = curY;
            for (int j = 1; j <= 5; j++) {
                float fj = float(j);
                float bj = ts_hash1(seed * 17.1 + fi * 3.7 + fj * 11.9) * 2.0 - 1.0;
                float bnx = bpx + side * bLen * 0.2 + bj * 0.025;
                float bny = bpy + bLen * 0.2 * bAng;
                float bd = ts_segDist(uv, float2(bpx, bpy), float2(bnx, bny));
                minD = min(minD, bd * 1.5);
                bpx = bnx;
                bpy = bny;
            }

            // Sub-branch fork
            if (ts_hash1(seed * 9.9 + fi * 4.1) > 0.55) {
                float sbx = curX + side * bLen * 0.12;
                float sby = curY + bLen * 0.12 * bAng;
                for (int k = 1; k <= 3; k++) {
                    float fk = float(k);
                    float sbj = ts_hash1(seed * 23.7 + fi * 7.3 + fk * 5.1) * 2.0 - 1.0;
                    float sbnx = sbx - side * 0.025 + sbj * 0.015;
                    float sbny = sby + 0.035;
                    float sbd = ts_segDist(uv, float2(sbx, sby), float2(sbnx, sbny));
                    minD = min(minD, sbd * 2.2);
                    sbx = sbnx;
                    sby = sbny;
                }
            }
        }

        prevX = curX;
        prevY = curY;
    }

    return minD;
}

// ── Get bolt parameters ──
static void ts_boltParams(int idx, float interval, thread float& birth, thread float& seed, thread float& sx, thread float& ex) {
    float fi = float(idx);
    birth = fi * interval + ts_hash1(fi * 17.31 + 42.0) * interval * 0.5;
    seed = fi * 7.13 + 1.0;
    sx = (ts_hash1(fi * 13.37 + 100.0) - 0.5) * 0.8;
    ex = sx + (ts_hash1(fi * 9.91 + 200.0) - 0.5) * 0.35;
}

fragment float4 fs_thunder_sermon(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float2 screenUV = in.pos.xy / u.resolution;
    float t = u.time;

    // ── Storm sky ──
    float3 skyTop = float3(0.015, 0.008, 0.05);
    float3 skyMid = float3(0.025, 0.018, 0.07);
    float3 skyBot = float3(0.01, 0.012, 0.035);
    float3 sky = mix(skyTop, skyMid, smoothstep(0.0, 0.5, screenUV.y));
    sky = mix(sky, skyBot, smoothstep(0.5, 1.0, screenUV.y));

    // ── Storm clouds ──
    float cloud1 = ts_stormClouds(uv * 1.8, t);
    float cloud2 = ts_stormClouds(uv * 2.4 + float2(3.7, 1.2), t * 1.1);
    float cloudDensity = smoothstep(0.3, 0.75, cloud1) * 0.6 + smoothstep(0.35, 0.8, cloud2) * 0.4;

    float heightBias = smoothstep(0.85, 0.0, screenUV.y);
    cloudDensity *= 0.4 + heightBias * 0.6;

    float3 cloudDark = float3(0.025, 0.02, 0.055);
    float3 cloudMid = float3(0.055, 0.045, 0.09);
    float3 cloudLight = float3(0.09, 0.07, 0.13);
    float3 cloudColor = mix(cloudDark, cloudMid, smoothstep(0.1, 0.4, cloudDensity));
    cloudColor = mix(cloudColor, cloudLight, smoothstep(0.4, 0.8, cloudDensity));

    float3 col = mix(sky, cloudColor, cloudDensity * 0.85);

    // ── Lightning system ──
    float interval = TS_STRIKE_INTERVAL;
    float totalFlash = 0.0;
    float3 boltLight = float3(0.0);

    float period = interval * 60.0;
    // mod that always returns positive
    float ct = t - period * floor(t / period);
    int cycle = int(floor(ct / interval));

    for (int i = -2; i <= 5; i++) {
        int bi = cycle + i;
        if (bi < 0) continue;

        float birth, seed, sx, ex;
        ts_boltParams(bi, interval, birth, seed, sx, ex);

        // No mouse interaction
        float age = ct - birth;
        if (age < -0.01 || age > 1.5) continue;
        if (age < 0.0) age = 0.0;

        // Flash lifecycle
        float flash = 0.0;
        if (age < 0.06) {
            flash = 1.0;
        } else if (age < 0.12) {
            flash = 0.4 + 0.6 * smoothstep(0.12, 0.06, age);
        } else if (age < 0.22) {
            float rs = smoothstep(0.12, 0.16, age) * smoothstep(0.22, 0.16, age);
            flash = 0.15 + rs * 0.7;
        } else if (age < 0.7) {
            flash = 0.15 * smoothstep(0.7, 0.22, age);
        }

        float boltVis = smoothstep(0.45, 0.0, age);

        if (boltVis > 0.001) {
            float d = ts_lightningBolt(uv, seed, sx, ex);

            float outer = exp(-d * d / 0.012) * boltVis * flash;
            boltLight += float3(0.25, 0.25, 0.7) * outer * 0.6;

            float mid = exp(-d * d / 0.003) * boltVis * flash;
            boltLight += float3(0.5, 0.6, 1.0) * mid;

            float core = exp(-d * d / 0.0004) * boltVis;
            float coreI = flash;
            if (age > 0.06 && age < 0.4) {
                float flk = 0.5 + 0.5 * sin(age * 130.0 + seed * 10.0);
                flk *= 0.5 + 0.5 * sin(age * 73.0 + seed * 7.0);
                coreI *= 0.4 + flk * 0.6;
            }
            boltLight += float3(1.0, 0.97, 0.92) * core * coreI * 3.0;

            float inner = exp(-d * d / 0.00006) * boltVis * flash;
            boltLight += float3(1.0) * inner * 4.0;
        }

        // Cloud illumination
        if (flash > 0.01) {
            float2 bc = float2(sx, -0.1);
            float dc = length(uv - bc);

            float illum = exp(-dc * dc / 0.45) * flash;
            illum *= 0.25 + cloudDensity * 0.75;
            float3 illumCol = mix(float3(0.12, 0.1, 0.22), float3(0.35, 0.3, 0.55), cloudDensity);
            col += illumCol * illum * 2.2;

            float close = exp(-dc * dc / 0.08) * flash;
            col += float3(0.25, 0.22, 0.32) * close * cloudDensity * 1.5;

            float groundDist = length(uv - float2(ex, 0.55));
            float groundGlow = exp(-groundDist * groundDist / 0.1) * flash;
            col += float3(0.15, 0.13, 0.22) * groundGlow * 0.8;

            totalFlash += flash * 0.5;
        }

        // Chromatic aberration shake
        if (age < 0.1) {
            float shake = smoothstep(0.1, 0.0, age) * 0.35;
            float sn = ts_hash1(seed + floor(age * 60.0)) * 2.0 - 1.0;
            col.r += sn * shake * 0.06;
            col.b -= sn * shake * 0.04;
        }
    }

    col += boltLight;

    totalFlash = min(totalFlash, 1.0);
    col += float3(0.1, 0.08, 0.16) * totalFlash * TS_FLASH_INTENSITY;

    // ── Sheet lightning ──
    float st = t * 0.8;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float ss = fi * 31.7 + 100.0;
        float sc = ts_hash1(ss + floor(st + fi * 0.37));
        float sa = fract(st + fi * 0.37);

        if (sc > 0.65) {
            float sf = smoothstep(0.04, 0.0, sa) + smoothstep(0.12, 0.04, sa) * 0.35;
            float2 sp = float2(
                (ts_hash1(ss + 1.0) - 0.5) * 1.4,
                (ts_hash1(ss + 2.0) - 0.5) * 0.5 - 0.15
            );
            float sd = length(uv - sp);
            float sg = exp(-sd * sd / 0.2) * sf;
            col += float3(0.07, 0.05, 0.14) * sg * (0.5 + cloudDensity * 1.5);
        }
    }

    // ── Rain ──
    float2 rainUV = in.pos.xy / min(u.resolution.x, u.resolution.y);
    float2 rc = float2(rainUV.x + rainUV.y * 0.12, rainUV.y);
    rc.y += t * 3.0;
    rc.x += t * 0.35;

    float rain = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float scale = 35.0 + fi * 20.0;
        float2 rv = rc * scale + float2(fi * 7.3, fi * 11.1);
        float ry = fract(rv.y);
        float rx = floor(rv.x);
        float rs = ts_hash1(rx * 13.7 + fi * 31.0);
        if (rs > 0.65) {
            float streak = smoothstep(0.0, 0.008, ry) * smoothstep(0.12 + rs * 0.08, 0.008, ry);
            rain += streak * (0.018 + fi * 0.006);
        }
    }
    col += float3(0.35, 0.38, 0.5) * rain * (0.25 + totalFlash * 2.5);

    // ── Vignette ──
    float vd = length(uv);
    float vig = 1.0 - smoothstep(0.35, 1.3, vd);
    col *= 0.5 + vig * 0.5;

    // ── Tone mapping ──
    col = col / (1.0 + col);
    col.r = pow(col.r, 1.05);
    col.b = pow(col.b, 0.93);
    col = max(col, float3(0.0));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
