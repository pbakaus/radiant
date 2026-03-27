#include "../Common.metal"

// ─── Vinyl Grooves: Spinning vinyl with prismatic groove diffraction ───
// Ported from static/vinyl-grooves.html

constant float VG_PI = 3.14159265359;
constant float VG_TAU = 6.28318530718;
constant float VG_ROTATION_SPEED = 1.0;
constant float VG_GROOVE_DENSITY = 1.0;

// ── Hash functions ──
static float vg_hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static float vg_hash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Smooth value noise ──
static float vg_vnoise(float x) {
    float i = floor(x);
    float f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(vg_hash(i), vg_hash(i + 1.0), f);
}

static float vg_vnoise2(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = vg_hash2(i);
    float b = vg_hash2(i + float2(1.0, 0.0));
    float c = vg_hash2(i + float2(0.0, 1.0));
    float d = vg_hash2(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ── HSV to RGB ──
static float3 vg_hsv2rgb(float h, float s, float v) {
    float3 c = float3(h, s, v);
    // GLSL mod always returns positive; use x - y*floor(x/y) for safety
    float3 raw = c.x * 6.0 + float3(0.0, 4.0, 2.0);
    float3 modded = raw - 6.0 * floor(raw / 6.0);
    float3 rgb = clamp(abs(modded - 3.0) - 1.0, 0.0, 1.0);
    return c.z * mix(float3(1.0), rgb, c.y);
}

// ── Groove micro-structure ──
static float vg_grooveProfile(float r, float density) {
    float grooveFreq = 280.0 * density;
    float groove = r * grooveFreq;
    float grooveFract = fract(groove);
    float profile = abs(grooveFract - 0.5) * 2.0;
    profile = pow(profile, 0.7);
    return profile;
}

// ── Groove waveform modulation ──
static float vg_grooveWaveform(float angle, float r) {
    float wave = 0.0;
    wave += sin(angle * 3.0 + r * 47.0) * 0.4;
    wave += sin(angle * 7.0 + r * 91.0 + 1.3) * 0.3;
    wave += sin(angle * 17.0 + r * 157.0 + 2.7) * 0.2;
    wave += sin(angle * 31.0 + r * 233.0 + 4.1) * 0.1;
    return wave;
}

// ── Diffraction grating color ──
static float3 vg_diffractionColor(float gratingAngle, float intensity) {
    float hue1 = fract(gratingAngle * 0.5 + 0.0);
    float hue2 = fract(gratingAngle * 0.5 + 0.33);
    float hue3 = fract(gratingAngle * 0.5 + 0.67);

    float3 color1 = vg_hsv2rgb(hue1, 0.7, 1.0) * 0.6;
    float3 color2 = vg_hsv2rgb(hue2, 0.5, 0.8) * 0.25;
    float3 color3 = vg_hsv2rgb(hue3, 0.4, 0.6) * 0.15;

    return (color1 + color2 + color3) * intensity;
}

fragment float4 fs_vinyl_grooves(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time * VG_ROTATION_SPEED;

    // ── Record geometry ──
    float dist = length(uv);
    float angle = atan2(uv.y, uv.x);

    float recordRadius = 0.44;
    float labelRadius = recordRadius * 0.27;
    float grooveInner = labelRadius + 0.01;
    float grooveOuter = recordRadius - 0.015;

    // ── Background ──
    float3 col = float3(0.012, 0.010, 0.010);

    float ambientGlow = exp(-dist * dist * 1.8) * 0.03;
    col += float3(0.08, 0.05, 0.03) * ambientGlow;

    // ── Record disc ──
    if (dist < recordRadius) {
        float rpm = 33.333;
        float rotationAngle = t * rpm / 60.0 * VG_TAU;
        float rotatedAngle = angle + rotationAngle;

        float rNorm = (dist - grooveInner) / (grooveOuter - grooveInner);
        rNorm = clamp(rNorm, 0.0, 1.0);

        // Vinyl base color
        float3 vinylBase = float3(0.02, 0.018, 0.016);
        vinylBase += float3(0.005) * vg_vnoise2(float2(dist * 20.0, angle * 3.0));

        col = vinylBase;

        // ── Groove structure ──
        if (dist > grooveInner && dist < grooveOuter) {
            float profile = vg_grooveProfile(dist, VG_GROOVE_DENSITY);

            float waveform = vg_grooveWaveform(rotatedAngle, dist) * 0.0004;
            float modulatedDist = dist + waveform;
            float modulatedProfile = vg_grooveProfile(modulatedDist, VG_GROOVE_DENSITY);

            float grooveShading = mix(0.015, 0.03, modulatedProfile);
            col = float3(grooveShading, grooveShading * 0.95, grooveShading * 0.9);

            // Light sources
            float2 light1Pos = float2(0.6, 0.5);
            float2 light2Pos = float2(-0.5, -0.4);

            // Specular reflection off groove walls
            float2 toLight1 = normalize(light1Pos - uv);
            float2 toLight2 = normalize(light2Pos - uv);

            float2 radialDir = normalize(uv);
            float2 tangentDir = float2(-radialDir.y, radialDir.x);

            float lightGrooveAngle1 = dot(toLight1, tangentDir);
            float lightGrooveAngle2 = dot(toLight2, tangentDir);

            float lightDist1 = length(light1Pos - uv);
            float lightDist2 = length(light2Pos - uv);
            float lightFalloff1 = 1.0 / (1.0 + lightDist1 * lightDist1 * 2.0);
            float lightFalloff2 = 1.0 / (1.0 + lightDist2 * lightDist2 * 3.0);

            // Prismatic diffraction
            float gratingPhase1 = lightGrooveAngle1 + rotatedAngle * 0.05;
            float3 diffraction1 = vg_diffractionColor(gratingPhase1, lightFalloff1);

            float gratingPhase2 = lightGrooveAngle2 + rotatedAngle * 0.05 + 0.5;
            float3 diffraction2 = vg_diffractionColor(gratingPhase2, lightFalloff2);

            float wallReflectivity = smoothstep(0.3, 0.8, modulatedProfile);

            // Specular highlight bands
            float specAngle1 = acos(clamp(lightGrooveAngle1, -1.0, 1.0));
            float specBand1 = exp(-pow(specAngle1 - VG_PI * 0.25, 2.0) * 8.0);
            specBand1 += exp(-pow(specAngle1 - VG_PI * 0.75, 2.0) * 8.0) * 0.5;

            float specAngle2 = acos(clamp(lightGrooveAngle2, -1.0, 1.0));
            float specBand2 = exp(-pow(specAngle2 - VG_PI * 0.3, 2.0) * 6.0) * 0.6;

            // Combine reflections
            float3 ambientReflection = float3(0.04, 0.03, 0.025) * lightFalloff1;

            float3 grooveReflection = float3(0.0);
            grooveReflection += diffraction1 * specBand1 * wallReflectivity * 1.2;
            grooveReflection += diffraction2 * specBand2 * wallReflectivity * 0.8;

            float3 warmSpec = float3(0.95, 0.75, 0.5);
            float specIntensity1 = specBand1 * lightFalloff1 * wallReflectivity;
            float specIntensity2 = specBand2 * lightFalloff2 * wallReflectivity;
            float3 specularHighlight = warmSpec * (specIntensity1 * 0.15 + specIntensity2 * 0.08);

            // Broad light sheen
            float sheen = exp(-lightDist1 * lightDist1 * 3.0) * 0.08;
            sheen += exp(-lightDist2 * lightDist2 * 4.0) * 0.03;
            float3 sheenColor = float3(0.2, 0.15, 0.1) * sheen;

            // Micro-groove shimmer
            float microGroove = fract(dist * 280.0 * VG_GROOVE_DENSITY);
            float microFlicker = pow(abs(sin(microGroove * VG_PI)), 12.0);
            float microAngle = sin(rotatedAngle * 3.0 + dist * 200.0);
            float microSpec = microFlicker * max(microAngle, 0.0) * lightFalloff1 * 0.1;

            // Rainbow bands
            float bandPhase = rotatedAngle + dist * 60.0;
            float rainbowBand = sin(bandPhase * 2.0) * 0.5 + 0.5;
            rainbowBand = pow(rainbowBand, 3.0);
            float rainbowHue = fract(dist * 8.0 + angle * 0.3 + t * 0.02);
            float3 rainbowColor = vg_hsv2rgb(rainbowHue, 0.6, 0.4) * rainbowBand;
            rainbowColor *= specBand1 * lightFalloff1 * 0.3;

            // Assemble
            col += ambientReflection;
            col += grooveReflection;
            col += specularHighlight;
            col += sheenColor;
            col += float3(microSpec) * float3(1.0, 0.9, 0.8);
            col += rainbowColor;

            // Lead-in and run-out
            float edgeFade = smoothstep(0.0, 0.03, rNorm) * smoothstep(1.0, 0.97, rNorm);
            col *= edgeFade * 0.9 + 0.1;
        }

        // ── Center label ──
        if (dist < labelRadius) {
            float labelR = dist / labelRadius;
            float3 labelColor = mix(
                float3(0.45, 0.30, 0.12),
                float3(0.30, 0.18, 0.08),
                labelR
            );

            float rpm2 = 33.333;
            float rotAngle2 = angle + u.time * VG_ROTATION_SPEED * rpm2 / 60.0 * VG_TAU;
            float paperTex = vg_vnoise2(float2(
                cos(rotAngle2) * dist * 50.0,
                sin(rotAngle2) * dist * 50.0
            ));
            labelColor += float3(0.03, 0.02, 0.01) * paperTex;

            float ring1 = smoothstep(0.72, 0.74, labelR) - smoothstep(0.76, 0.78, labelR);
            labelColor += float3(0.1, 0.07, 0.03) * ring1;

            float spindleHole = smoothstep(0.08, 0.06, labelR);
            labelColor = mix(labelColor, float3(0.01), spindleHole);

            float2 light1Pos = float2(0.6, 0.5);
            float labelLight = exp(-length(light1Pos - uv) * length(light1Pos - uv) * 4.0);
            labelColor += float3(0.15, 0.1, 0.05) * labelLight;

            col = labelColor;
        }

        // ── Record edge ──
        float edgeDist = recordRadius - dist;
        float edgeHighlight = smoothstep(0.008, 0.0, edgeDist) * 0.3;
        col += float3(0.15, 0.12, 0.08) * edgeHighlight;

        float edgeShadow = smoothstep(0.02, 0.0, edgeDist);
        col *= 1.0 - edgeShadow * 0.3;

        float edgeAA = smoothstep(recordRadius, recordRadius - 0.002, dist);
        col *= edgeAA;
    }

    // ── Drop shadow ──
    if (dist >= recordRadius) {
        float shadowDist = dist - recordRadius;
        float shadow = exp(-shadowDist * shadowDist * 80.0) * 0.25;
        col = mix(col, float3(0.0), shadow);
    }

    // ── Vignette ──
    float vig = 1.0 - dot(uv * 0.8, uv * 0.8);
    vig = smoothstep(0.0, 1.0, vig);
    col *= 0.7 + vig * 0.3;

    // ── Tone mapping ──
    col = col / (1.0 + col * 0.2);

    // ── Final warmth ──
    col = pow(max(col, 0.0), float3(0.95, 0.98, 1.05));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
