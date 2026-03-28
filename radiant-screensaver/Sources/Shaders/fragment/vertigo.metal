#include "../Common.metal"

// ─── Vertigo: Pulsing neon tunnel with wave-lit rings ───
// Ported from static/vertigo.html

constant float VT_PI = 3.14159265359;
constant float VT_TAU = 6.28318530718;
constant float VT_TUNNEL_SPEED = 0.15;
constant float VT_SPIRAL_INTENSITY = 0.0;

// ── Hash for noise ──
static float vt_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// ── Value noise ──
static float vt_vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = vt_hash(i);
    float b = vt_hash(i + float2(1.0, 0.0));
    float c = vt_hash(i + float2(0.0, 1.0));
    float d = vt_hash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

fragment float4 fs_vertigo(VSOut in [[stage_in]],
                           constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;

    // Center UV, correct aspect
    float2 p = (uv - 0.5) * float2(aspect, 1.0);

    float t = u.time;
    float scrollSpeed = VT_TUNNEL_SPEED;

    // ── Polar coordinates ──
    float r = length(p);
    float theta = atan2(p.y, p.x);

    // ── Steady tunnel depth ──
    float depth = 1.0 / (r + 0.04);

    // ── Rotation: auto drift (no mouse) ──
    float rotAngle = t * 0.02 + sin(t * 0.07) * 0.15;
    float thetaRot = theta + rotAngle;

    // ── Tunnel texture coordinates ──
    float tu = thetaRot / VT_TAU;
    float tv = depth - t * scrollSpeed;

    // ── Ring segments ──
    float ringFreq = 10.0;
    float ringCoord = tv * ringFreq / VT_TAU;
    float ringPhase = fract(ringCoord);
    float ringId = floor(ringCoord);

    // Primary rings
    float ring = smoothstep(0.0, 0.06, ringPhase) * smoothstep(0.5, 0.44, ringPhase);

    // Secondary thinner accent rings
    float ringPhase2 = fract(ringCoord * 2.0);
    float ring2 = smoothstep(0.0, 0.03, ringPhase2) * smoothstep(0.5, 0.47, ringPhase2);

    // ── Angular segments ──
    float angSegments = 16.0;
    float angPhase = fract(tu * angSegments);
    float angLine = smoothstep(0.0, 0.025, angPhase) * smoothstep(1.0, 0.975, angPhase);

    // ── Combine into tunnel structure ──
    float structure = ring * angLine;
    structure = max(structure, ring2 * 0.25 * angLine);

    // ── Wave-based ring illumination ──
    float wave1 = sin(ringId * 0.5 - t * 0.8) * 0.5 + 0.5;
    wave1 = pow(wave1, 3.0);

    float wave2 = sin(ringId * 0.3 + t * 0.5) * 0.5 + 0.5;
    wave2 = pow(wave2, 4.0);

    float wave3 = sin(ringId * 0.15 - t * 0.35) * 0.5 + 0.5;
    wave3 = pow(wave3, 2.0);

    float ringBrightness = 0.15 + wave1 * 0.5 + wave2 * 0.35 + wave3 * 0.25;
    ringBrightness = clamp(ringBrightness, 0.0, 1.5);

    // Occasional bright flash on specific rings
    float flash = pow(max(0.0, sin(ringId * 7.3 - t * 1.2)), 12.0);
    ringBrightness += flash * 0.8;

    structure *= ringBrightness;

    // ── Depth fog ──
    float depthFade = exp(-r * 3.0);
    float voidFade = smoothstep(0.0, 0.12, r);
    structure *= depthFade * voidFade;

    // ── Neon edge highlights ──
    float edgeHighlight = smoothstep(0.06, 0.02, abs(ringPhase - 0.01));
    edgeHighlight += smoothstep(0.06, 0.02, abs(ringPhase - 0.48));
    edgeHighlight *= angLine * depthFade * voidFade;

    // ── Color scheme ──
    float3 crimson    = float3(0.80, 0.067, 0.20);
    float3 darkPurple = float3(0.133, 0.0, 0.20);
    float3 neonRed    = float3(1.0, 0.133, 0.267);
    float3 amber      = float3(0.784, 0.584, 0.424);
    float3 magenta    = float3(0.6, 0.05, 0.35);
    float3 burntOrange = float3(0.85, 0.35, 0.1);

    // ── Per-ring color variation ──
    float colorSel = fract(ringId * 0.618033);
    float colorShift = sin(ringId * 1.7 + t * 0.2) * 0.5 + 0.5;

    float colorDepth = smoothstep(0.0, 0.5, r);
    float3 tunnelColor = mix(darkPurple, crimson, colorDepth);

    tunnelColor = mix(tunnelColor, magenta, colorSel * 0.3);
    tunnelColor = mix(tunnelColor, crimson * 1.3, colorShift * 0.25);

    float amberAmount = wave1 * wave3;
    tunnelColor = mix(tunnelColor, amber * 0.8, amberAmount * 0.3);

    tunnelColor = mix(tunnelColor, burntOrange, flash * 0.5);

    // ── Edge highlight color ──
    float3 edgeColor = mix(neonRed, amber, wave2 * 0.4);
    edgeColor = mix(edgeColor, magenta * 1.5, flash * 0.3);

    // ── Composite ──
    float3 col = float3(0.0);

    col += tunnelColor * structure;
    col += edgeColor * edgeHighlight * 0.5;
    col += amber * wave1 * structure * 0.3;
    col += mix(amber, float3(1.0, 0.9, 0.7), 0.5) * flash * structure * 0.5;

    // ── Subtle ambient glow ──
    float ambientGlow = exp(-r * 5.0) * (1.0 - smoothstep(0.0, 0.08, r));
    col += darkPurple * ambientGlow * 0.08;

    // ── Atmospheric haze ──
    float haze = exp(-r * 6.0) * 0.02;
    col += mix(darkPurple, crimson * 0.5, 0.3) * haze;

    // ── Vignette ──
    float vig = 1.0 - smoothstep(0.3, 1.1, r);
    col *= 0.55 + 0.45 * vig;

    // ── Film grain ──
    float grain = (fract(sin(dot(in.pos.xy, float2(12.9898, 78.233)) + fract(u.time * 0.1) * 100.0) * 43758.5453) - 0.5) * 0.02;
    col += grain;

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
