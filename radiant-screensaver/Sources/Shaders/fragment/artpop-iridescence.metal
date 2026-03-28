#include "../Common.metal"

// ─── Artpop Iridescence: Thin-film soap bubble interference ───
// Ported from static/artpop-iridescence.html

constant float AI_PI = 3.141592653589793;
constant float AI_TAU = 6.283185307179586;
constant float AI_FILM_THICKNESS = 1.0;
constant float AI_FLOW_SPEED = 0.5;

// ── FBM using snoise from Common ──
static float ai_fbm(float2 p) {
    float f = 0.0;
    f += 0.5000 * snoise(p); p *= 2.02;
    f += 0.2500 * snoise(p); p *= 2.03;
    f += 0.1250 * snoise(p); p *= 2.01;
    f += 0.0625 * snoise(p);
    return f;
}

// ── Domain-warped noise for flowing organic surface ──
static float ai_warpedNoise(float2 p, float t) {
    float2 q = float2(
        ai_fbm(p + float2(0.0, 0.0) + t * 0.12),
        ai_fbm(p + float2(5.2, 1.3) + t * 0.09)
    );
    float2 r = float2(
        ai_fbm(p + 4.0 * q + float2(1.7, 9.2) + t * 0.07),
        ai_fbm(p + 4.0 * q + float2(8.3, 2.8) + t * 0.1)
    );
    return ai_fbm(p + 3.5 * r);
}

// ── Thin-film interference color ──
static float3 ai_thinFilm(float thickness, float cosTheta) {
    float phase = thickness * cosTheta;
    float3 film = 0.5 + 0.5 * cos(phase + float3(0.0, 2.094, 4.189));
    return film * film;
}

// ── Bubble surface height ──
static float ai_bubbleSurface(float2 p, float t) {
    float s = 0.0;
    s += sin(p.x * 2.0 + t * 0.5) * cos(p.y * 1.7 + t * 0.35) * 0.35;
    s += sin(p.x * 1.3 - t * 0.3 + p.y * 2.2) * 0.25;
    s += cos(p.y * 2.8 + t * 0.4 - p.x * 0.9) * 0.2;
    s += ai_warpedNoise(p * 1.2, t) * 0.4;
    s += snoise(p * 3.5 + t * 0.2) * 0.08;
    return s;
}

// ── Surface normal via forward differences ──
static float3 ai_getNormal(float2 p, float t, float h0) {
    float e = 0.004;
    float hx = ai_bubbleSurface(p + float2(e, 0.0), t);
    float hy = ai_bubbleSurface(p + float2(0.0, e), t);
    return normalize(float3(h0 - hx, h0 - hy, e));
}

fragment float4 fs_artpop_iridescence(VSOut in [[stage_in]],
                                       constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (uv - float2(0.5)) * float2(aspect, 1.0);
    float t = u.time * AI_FLOW_SPEED;

    // ── Multiple overlapping bubble film surfaces ──
    float3 totalColor = float3(0.0);
    float totalWeight = 0.0;

    // Surface 1: Large primary bubble
    {
        float dist1 = length(p * float2(1.0, 1.1));
        float edgeNoise = snoise(float2(atan2(p.y, p.x) * 3.0 + t * 0.15, t * 0.2)) * 0.06;
        float mask1 = smoothstep(0.82 + edgeNoise, 0.45 + edgeNoise, dist1);

        float2 sp1 = p * 1.6;
        float surface1 = ai_bubbleSurface(sp1, t);
        float3 norm1 = ai_getNormal(sp1, t, surface1);

        float thick1 = 8.0 + surface1 * 12.0 * AI_FILM_THICKNESS;
        thick1 += p.y * 4.0;
        thick1 += sin(t * 0.25) * 2.0;

        float3 viewDir = float3(0.0, 0.0, 1.0);
        float cosTheta1 = max(abs(dot(norm1, viewDir)), 0.15);
        float3 film1 = ai_thinFilm(thick1, cosTheta1);

        float fresnel1 = pow(1.0 - cosTheta1, 4.0);
        film1 = mix(film1, film1 * 2.0 + float3(0.15, 0.1, 0.2), fresnel1 * 0.5);

        float3 light1 = normalize(float3(0.4, 0.6, 1.0));
        float3 half1 = normalize(light1 + viewDir);
        float spec1 = pow(max(dot(norm1, half1), 0.0), 80.0);
        float3 light2 = normalize(float3(-0.5, -0.3, 0.9));
        float3 half2 = normalize(light2 + viewDir);
        float spec2 = pow(max(dot(norm1, half2), 0.0), 60.0);
        film1 += float3(1.0, 0.97, 0.92) * spec1 * 0.5;
        film1 += float3(0.9, 0.93, 1.0) * spec2 * 0.3;

        totalColor += film1 * mask1;
        totalWeight += mask1;
    }

    // Surface 2: Secondary smaller bubble, offset
    {
        float2 center2 = float2(0.25, -0.15);
        float dist2 = length((p - center2) * float2(1.2, 1.0));
        float edgeNoise2 = snoise(float2(atan2(p.y - center2.y, p.x - center2.x) * 4.0, t * 0.18)) * 0.04;
        float mask2 = smoothstep(0.38 + edgeNoise2, 0.18 + edgeNoise2, dist2);

        float2 sp2 = (p - center2) * 2.5;
        float2 sp2off = sp2 + float2(3.7, 1.2);
        float surface2 = ai_bubbleSurface(sp2off, t * 1.1);
        float3 norm2 = ai_getNormal(sp2off, t * 1.1, surface2);

        float thick2 = 6.0 + surface2 * 10.0 * AI_FILM_THICKNESS;
        thick2 += (p.y - center2.y) * 3.5;
        thick2 += sin(t * 0.3 + 1.5) * 1.8;

        float3 viewDir = float3(0.0, 0.0, 1.0);
        float cosTheta2 = max(abs(dot(norm2, viewDir)), 0.15);
        float3 film2 = ai_thinFilm(thick2, cosTheta2);

        float fresnel2 = pow(1.0 - cosTheta2, 4.0);
        film2 = mix(film2, film2 * 2.0 + float3(0.12, 0.15, 0.18), fresnel2 * 0.5);

        float3 light1 = normalize(float3(0.3, 0.5, 1.0));
        float3 half1 = normalize(light1 + viewDir);
        float spec1 = pow(max(dot(norm2, half1), 0.0), 90.0);
        film2 += float3(1.0, 0.97, 0.92) * spec1 * 0.45;

        totalColor = mix(totalColor, totalColor * 0.5 + film2, mask2);
        totalWeight = max(totalWeight, mask2);
    }

    // Surface 3: Another smaller bubble, opposite side
    {
        float2 center3 = float2(-0.3, 0.2);
        float dist3 = length((p - center3) * float2(1.0, 1.3));
        float edgeNoise3 = snoise(float2(atan2(p.y - center3.y, p.x - center3.x) * 5.0, t * 0.2)) * 0.035;
        float mask3 = smoothstep(0.32 + edgeNoise3, 0.14 + edgeNoise3, dist3);

        float2 sp3 = (p - center3) * 2.8;
        float2 sp3off = sp3 + float2(7.1, 4.3);
        float surface3 = ai_bubbleSurface(sp3off, t * 0.9);
        float3 norm3 = ai_getNormal(sp3off, t * 0.9, surface3);

        float thick3 = 5.0 + surface3 * 11.0 * AI_FILM_THICKNESS;
        thick3 += (p.y - center3.y) * 3.0;
        thick3 += cos(t * 0.35 + 3.0) * 2.0;

        float3 viewDir = float3(0.0, 0.0, 1.0);
        float cosTheta3 = max(abs(dot(norm3, viewDir)), 0.15);
        float3 film3 = ai_thinFilm(thick3, cosTheta3);

        float fresnel3 = pow(1.0 - cosTheta3, 4.0);
        film3 = mix(film3, film3 * 2.0 + float3(0.18, 0.1, 0.14), fresnel3 * 0.5);

        float3 light1 = normalize(float3(-0.3, 0.4, 1.0));
        float3 half1 = normalize(light1 + viewDir);
        float spec1 = pow(max(dot(norm3, half1), 0.0), 70.0);
        film3 += float3(0.95, 1.0, 0.97) * spec1 * 0.4;

        totalColor = mix(totalColor, totalColor * 0.5 + film3, mask3);
        totalWeight = max(totalWeight, mask3);
    }

    // ── Background ──
    float distCenter = length(p * float2(0.9, 1.0));
    float3 bgColor = float3(0.015, 0.015, 0.03);
    float bgGlow = exp(-distCenter * distCenter * 4.0) * 0.06;
    bgColor += float3(0.04, 0.02, 0.06) * bgGlow;

    // ── Compose ──
    float3 col = mix(bgColor, totalColor, clamp(totalWeight, 0.0, 1.0));

    // ── Vignette ──
    float vig = 1.0 - smoothstep(0.35, 1.3, length(p * float2(0.85, 1.0)));
    col *= 0.6 + 0.4 * vig;

    // ── Tone mapping ──
    col = clamp(col, 0.0, 1.0);
    col = pow(col, float3(0.95));
    col = col * col * (3.0 - 2.0 * col);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
