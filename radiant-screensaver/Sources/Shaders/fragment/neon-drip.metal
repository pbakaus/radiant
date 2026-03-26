#include "../Common.metal"

// ─── Neon Drip: Metaball blobs dripping upward in liquid rebellion ───
// Ported from static/neon-drip.html

// Default parameter values (screensaver — no mouse)
constant float ND_DRIP_SPEED = 0.5;
constant float ND_BLOB_COUNT = 1.0;

constant float ND_PI = 3.14159265359;
constant int ND_MAX_BLOBS = 12;

// Hash for noise / grain
static float nd_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Value noise
static float nd_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(nd_hash(i), nd_hash(i + float2(1.0, 0.0)), f.x),
        mix(nd_hash(i + float2(0.0, 1.0)), nd_hash(i + float2(1.0, 1.0)), f.x),
        f.y
    );
}

// Smooth min for metaball blending (polynomial)
static float nd_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// Metaball field evaluation
static float nd_metaballField(float2 p, float t, float speed, float count) {
    float energy = 0.0;
    float numBlobs = 4.0 + count * 8.0; // 4 to 12 blobs

    // Emitter group 1: Rising blobs from bottom-left
    for (int i = 0; i < ND_MAX_BLOBS; i++) {
        if (float(i) >= numBlobs) break;
        float fi = float(i);
        float phase = fi * 1.618 + fi * fi * 0.13; // golden-ratio spacing

        // Base position: spread across bottom, rise upward
        float riseSpeed = (0.3 + 0.4 * fract(fi * 0.618)) * speed;
        float riseCycle = fmod(t * riseSpeed + phase * 0.7, 3.5) - 1.0;

        // X position: oscillate laterally as they rise
        float xBase = sin(phase * 2.39996) * 0.45;
        float xWobble = sin(t * speed * 0.8 + phase * 3.1) * 0.12;
        float xDrift = sin(riseCycle * 2.0 + phase) * 0.08;
        float bx = xBase + xWobble + xDrift;

        // Y position: rise from bottom, wrap around
        float by = -0.7 + riseCycle * 0.9;

        // Size varies per blob and pulses gently
        float baseSize = 0.04 + 0.03 * fract(phase * 0.317);
        float pulse = 1.0 + 0.15 * sin(t * speed * 1.5 + phase * 4.7);
        float radius = baseSize * pulse;

        // Metaball contribution: r^2 / d^2 formulation
        float d = length(p - float2(bx, by));
        energy += (radius * radius) / (d * d + 0.0001);
    }

    return energy;
}

// Tendril field: stretched vertical noise that creates trailing wisps
static float nd_tendrilField(float2 p, float t, float speed) {
    // Vertically stretched noise for upward-dripping feel
    float n1 = nd_vnoise(float2(p.x * 6.0, p.y * 2.0 - t * speed * 0.6) + 10.0);
    float n2 = nd_vnoise(float2(p.x * 12.0 + 3.7, p.y * 4.0 - t * speed * 0.8) + 20.0);
    float n3 = nd_vnoise(float2(p.x * 3.0 + 7.1, p.y * 1.5 - t * speed * 0.4));

    // Combine: large tendril shapes + fine detail
    float tendrils = n1 * 0.5 + n2 * 0.3 + n3 * 0.2;

    // Sharpen into tendril-like strands
    tendrils = smoothstep(0.35, 0.65, tendrils);

    // Fade tendrils toward top (they dissipate)
    tendrils *= smoothstep(0.6, -0.3, p.y);

    // Stronger at bottom where "drips" originate
    tendrils *= 0.6 + 0.4 * smoothstep(0.0, -0.5, p.y);

    return tendrils;
}

// Vignette
static float nd_vignette(float2 uv) {
    float d = length(uv * float2(0.9, 1.0));
    return smoothstep(1.3, 0.4, d);
}

fragment float4 fs_neon_drip(VSOut in [[stage_in]],
                              constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / u.resolution.y;
    float aspect = u.resolution.x / u.resolution.y;
    float t = u.time;
    float speed = ND_DRIP_SPEED;
    float count = ND_BLOB_COUNT;

    // Background: deep dark with subtle warm radial gradient
    float bgDist = length(uv * float2(0.8, 1.0));
    float3 col = float3(0.025, 0.018, 0.015) * (1.0 - bgDist * 0.3);
    col = max(col, float3(0.0));

    // No mouse interaction for screensaver
    float mouseField = 0.0;

    // Evaluate metaball field
    float field = nd_metaballField(uv, t, speed, count) + mouseField;

    // Tendril contribution: adds to the field
    float tendrils = nd_tendrilField(uv, t, speed);

    // Combine: metaballs are the main blobs, tendrils add trailing wisps
    float combinedField = field + tendrils * 0.6;

    // Isosurface thresholds for layered coloring
    float threshold = 1.0;

    // Outer glow: neon halo around the blob surfaces
    float outerGlow = smoothstep(threshold * 0.15, threshold * 0.5, combinedField);

    // Surface: sharper blob boundary for neon look
    float surface = smoothstep(threshold * 0.4, threshold * 0.7, combinedField);

    // Inner: brighter core inside the blobs
    float inner = smoothstep(threshold * 0.8, threshold * 1.8, combinedField);

    // Hot core: brightest center
    float core = smoothstep(threshold * 2.0, threshold * 4.0, combinedField);

    // Color palette: vibrant neon amber (HDR values > 1.0 for bloom)
    float3 glowColor = float3(1.2, 0.55, 0.10);
    float3 surfaceColor = float3(2.5, 1.3, 0.40);
    float3 innerColor = float3(3.5, 2.0, 0.70);
    float3 coreColor = float3(5.0, 4.0, 2.5);

    // Compose the blob color
    float3 blobCol = glowColor * outerGlow * 1.0;
    blobCol = mix(blobCol, surfaceColor, surface * 0.95);
    blobCol = mix(blobCol, innerColor, inner * 0.95);
    blobCol = mix(blobCol, coreColor, core * 1.0);

    // Surface edge highlight: rim lighting effect
    float edgeBand = surface * (1.0 - inner);
    blobCol += float3(1.8, 1.0, 0.3) * edgeBand * 0.8;

    // Tendril coloring: slightly different from main blobs
    float tendrilVis = tendrils * (1.0 - surface * 0.5);
    float3 tendrilColor = float3(1.4, 0.7, 0.20) * tendrilVis * 0.7;
    blobCol += tendrilColor;

    // Add blob color to scene
    col += blobCol;

    // Ambient upward-flowing noise: background movement
    float ambientFlow = nd_vnoise(float2(uv.x * 3.0, uv.y * 1.5 - t * speed * 0.2) + 50.0);
    ambientFlow = smoothstep(0.4, 0.6, ambientFlow) * 0.06;
    col += float3(0.2, 0.12, 0.06) * ambientFlow;

    // Subtle secondary blobs: small, fast, for liveliness
    float microField = 0.0;
    for (int i = 0; i < 5; i++) {
        float fi = float(i);
        float phase = fi * 2.39996 + 100.0;
        float mSpeed = (0.5 + 0.3 * fract(phase * 0.618)) * speed;
        float mCycle = fmod(t * mSpeed + phase, 2.8) - 0.8;
        float mx = sin(phase * 1.7) * 0.5 + sin(t * speed + phase * 2.3) * 0.1;
        float my = -0.6 + mCycle * 0.8;
        float mr = 0.015 + 0.01 * sin(t * speed * 2.0 + phase);
        float md = length(uv - float2(mx, my));
        microField += (mr * mr) / (md * md + 0.0001);
    }
    float microSurface = smoothstep(0.8, 1.5, microField);
    float microCore = smoothstep(1.5, 3.0, microField);
    col += float3(1.8, 1.0, 0.30) * microSurface * 0.7;
    col += float3(3.0, 2.2, 1.0) * microCore * 0.8;

    // Film grain
    float grain = (nd_hash(in.pos.xy + fract(t * 43.758) * 1000.0) - 0.5) * 0.025;
    col += grain;

    // Vignette
    col *= nd_vignette(uv);

    // Tone mapping: ACES filmic (preserves bright neon punch)
    col = max(col, float3(0.0));
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
    col = pow(col, float3(0.90));

    // Warm shadow push
    float lum = dot(col, float3(0.299, 0.587, 0.114));
    col = mix(col, col * float3(1.06, 0.97, 0.90), smoothstep(0.05, 0.0, lum) * 0.3);

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
