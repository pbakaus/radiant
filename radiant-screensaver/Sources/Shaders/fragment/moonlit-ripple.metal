#include "../Common.metal"

// ─── Moonlit Ripple: Moon reflection on dark water with concentric ripple interference ───
// Ported from static/moonlit-ripple.html

constant float MR_PI = 3.14159265359;
constant int MR_WAVE_LAYERS = 7;
constant float MR_RIPPLE_SPEED = 0.5;
constant float MR_MOON_GLOW = 1.0;
constant float MR_TILT = 0.15;
constant float MR_WAVES = 1.0;

// Simple hash for moon texture
static float mr_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Multi-directional waves with analytical normals ──
static float4 mr_sea(float2 p, float t) {
    float h = 0.0;
    float2 dh = float2(0.0);
    float freq = 1.0;
    float baseAmp = 0.2 * MR_WAVES;
    float decay = mix(0.55, 0.38, clamp(MR_WAVES / 3.0, 0.0, 1.0));
    float amp = baseAmp;
    float angle = 0.0;
    for (int i = 0; i < MR_WAVE_LAYERS; i++) {
        float c = cos(angle);
        float s = sin(angle);
        float2 pp = float2(c * p.x + s * p.y, -s * p.x + c * p.y);
        float fi = float(i);
        float spd = sqrt(freq) * 0.8;
        float phase = (pp.y + fi) * freq - t * spd;
        float sn = sin(phase);
        float cn = cos(phase);
        h += sn * amp;
        float dy = freq * amp * cn;
        dh += float2(-s * dy, c * dy);
        angle += fi + 1.2;
        freq *= 1.3;
        amp *= decay;
    }
    float3 N = normalize(float3(-dh.x, 1.0, -dh.y));
    return float4(h, N);
}

// ── Moon direction in 3D ──
static float3 mr_moonDir() {
    return normalize(float3(0.15, 0.35, 1.0));
}

// ── Night sky color with textured moon disc ──
static float3 mr_skyColor(float3 rd, float moonGlow) {
    float3 md = mr_moonDir();
    float3 skyDark = float3(0.06, 0.03, 0.02);
    float3 skyHoriz = float3(0.09, 0.05, 0.04);
    float3 sky = mix(skyHoriz, skyDark, max(rd.y, 0.0));
    float3 moonCol = float3(0.98, 0.92, 0.85);
    float moonDot = max(dot(rd, md), 0.0);
    float moonAngle = acos(clamp(moonDot, 0.0, 1.0));
    float moonRadius = 0.04;
    float disc = smoothstep(moonRadius, moonRadius * 0.7, moonAngle);
    // Crater texture
    if (disc > 0.0) {
        float3 up = float3(0.0, 1.0, 0.0);
        float3 right = normalize(cross(up, md));
        float3 mup = cross(md, right);
        float2 muv = float2(dot(rd - md, right), dot(rd - md, mup)) * 25.0;
        float crater = mr_hash(floor(muv * 2.0)) * 0.25;
        crater += mr_hash(floor(muv * 4.0)) * 0.15;
        float darkening = 1.0 - crater * smoothstep(moonRadius * 0.9, moonRadius * 0.4, moonAngle);
        float limb = smoothstep(0.0, moonRadius, moonAngle);
        darkening *= mix(1.0, 0.7, limb * limb);
        sky += moonCol * disc * 0.85 * darkening;
    }
    // Bloom
    sky += moonCol * 0.25 * pow(moonDot, 40.0) * moonGlow;
    sky += moonCol * 1.2 * pow(moonDot, 400.0) * moonGlow;
    return sky;
}

fragment float4 fs_moonlit_ripple(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 uv = -1.0 + 2.0 * in.pos.xy / u.resolution;
    uv.x *= aspect;
    float t = u.time * MR_RIPPLE_SPEED;
    float moonGlow = MR_MOON_GLOW;

    // ── 3D Camera ──
    float tiltRad = MR_TILT * 0.7;
    float3 ro = float3(0.0, 8.0, 0.0);
    float3 ww = normalize(float3(0.0, -sin(tiltRad), cos(tiltRad)));
    float3 uu = normalize(cross(float3(0.0, 1.0, 0.0), ww));
    float3 vv = normalize(cross(ww, uu));
    float3 rd = normalize(uv.x * uu + uv.y * vv + 2.5 * ww);

    float3 md = mr_moonDir();
    float3 moonCol = float3(0.98, 0.92, 0.85);

    // ── Sky (above horizon) ──
    float3 sky = mr_skyColor(rd, moonGlow);
    float3 col = sky;

    // ── Ray-plane intersection (water at y=0) ──
    float dsea = -ro.y / rd.y;

    if (dsea > 0.0) {
        float3 wp = ro + dsea * rd;

        // ── Sample waves ──
        float4 s = mr_sea(wp.xz, t);
        float h = s.x;
        float3 nor = s.yzw;

        // No mouse ripple in screensaver mode

        // Flatten normal with distance
        nor = mix(nor, float3(0.0, 1.0, 0.0), smoothstep(0.0, 300.0, dsea));

        // ── Fresnel ──
        float fre = clamp(1.0 - dot(-nor, rd), 0.0, 1.0);
        fre = pow(fre, 3.0);

        // ── Diffuse moonlight ──
        float dif = mix(0.25, 1.0, max(dot(nor, md), 0.0));

        // ── Reflection & refraction ──
        float3 refl = mr_skyColor(reflect(rd, nor), moonGlow);
        float3 seaCol1 = float3(0.05, 0.02, 0.01);
        float3 seaCol2 = float3(0.10, 0.06, 0.04);
        float3 refr = seaCol1 + dif * moonCol * seaCol2 * 0.15 * moonGlow;

        col = mix(refr, 0.9 * refl, fre);

        // ── Wave crest highlight ──
        float atten = max(1.0 - dsea * dsea * 0.0005, 0.0);
        col += seaCol2 * (wp.y - h) * 1.5 * atten;

        // ── Distance fog ──
        col = mix(col, sky, 1.0 - exp(-0.008 * dsea));
    }

    // ── Gamma ──
    col = pow(max(col, float3(0.0)), float3(0.85));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
