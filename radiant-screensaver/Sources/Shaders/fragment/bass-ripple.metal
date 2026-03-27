#include "../Common.metal"

// ─── Bass Ripple: Beat-synced hexagonal speaker grille ───
// Ported from static/bass-ripple.html

constant float BR_PI = 3.14159265359;
constant float BR_TAU = 6.28318530718;
constant float BR_BASS_FREQ = 0.4;
constant float BR_BASS_INTENSITY = 1.0;
constant float BR_MESH_SCALE = 45.0;
constant float BR_WIRE_WIDTH = 0.06;

// ── Hash / noise ──
static float br_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float br_hash3(float3 p) {
    return fract(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453);
}

static float br_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(br_hash(i), br_hash(i + float2(1, 0)), f.x),
               mix(br_hash(i + float2(0, 1)), br_hash(i + float2(1, 1)), f.x), f.y);
}

// ── Rotation ──
static float2x2 br_rot2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// ── Beat-synced displacement ──
static float br_displacement(float2 p, float t, float bassFreq, float intensity) {
    float period = 1.0 / max(bassFreq, 0.01);
    float phase = t / period;
    float beatFrac = fract(phase);

    float envelope = exp(-beatFrac * 3.5);
    float prevEnv = exp(-(beatFrac + 1.0) * 3.5);
    float prevEnv2 = exp(-(beatFrac + 2.0) * 3.5);

    float dist = length(p);
    float angle = atan2(p.y, p.x);

    float wave1 = sin(dist * 14.0 - beatFrac * 22.0) * envelope;
    float wave2 = sin(dist * 9.0 - (beatFrac + 1.0) * 16.0) * prevEnv * 0.6;
    float wave3 = sin(dist * 6.0 - (beatFrac + 2.0) * 12.0) * prevEnv2 * 0.3;
    float standing = (sin(p.x * 18.0) * sin(p.y * 18.0)) * envelope * 0.3;

    float radialMode = sin(dist * 22.0) * cos(angle * 3.0) * envelope * 0.2;
    radialMode += sin(dist * 16.0) * cos(angle * 5.0 + 1.0) * prevEnv * 0.1;

    float2 offCenter = float2(0.3 * sin(t * 0.2), 0.25 * cos(t * 0.25));
    float dist2 = length(p - offCenter);
    float wave6 = sin(dist2 * 12.0 - beatFrac * 18.0) * envelope * 0.35;

    // No mouse wave in screensaver

    float dome = (1.0 - smoothstep(0.0, 1.0, dist)) * envelope * 0.8;

    float h = (wave1 + wave2 + wave3 + standing + radialMode + wave6 + dome) * intensity;

    float idle = sin(dist * 8.0 + t * 3.0) * 0.03 * (1.0 - envelope);
    idle += sin(dist * 5.0 - t * 1.5) * 0.015 * (1.0 - envelope);
    h += idle * intensity;

    return h;
}

// ── Normal from displacement ──
static float3 br_calcNormal(float2 p, float t, float bassFreq, float intensity, float hc) {
    float eps = 0.002;
    float hx = br_displacement(p + float2(eps, 0.0), t, bassFreq, intensity);
    float hy = br_displacement(p + float2(0.0, eps), t, bassFreq, intensity);
    float3 n = normalize(float3(-(hx - hc) / eps * 0.35, -(hy - hc) / eps * 0.35, 1.0));
    return n;
}

// ── Hexagonal grid distance ──
static float3 br_hexGrid(float2 p, float scale) {
    p *= scale;
    float2 r = float2(1.0, 1.732);
    float2 h = r * 0.5;
    // GLSL mod always returns positive; replicate with x - y * floor(x/y)
    float2 a = (p - r * floor(p / r)) - h;
    float2 b = ((p - h) - r * floor((p - h) / r)) - h;
    float2 g;
    if (dot(a, a) < dot(b, b)) {
        g = a;
    } else {
        g = b;
    }
    float edgeDist = 0.5 - max(abs(g.x) * 1.0 + abs(g.y) * 0.577, abs(g.y) * 1.155);
    float2 cellId = p - g;
    return float3(edgeDist, cellId);
}

// ── Fresnel ──
static float br_fresnel(float cosTheta, float f0) {
    return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

fragment float4 fs_bass_ripple(VSOut in [[stage_in]],
                                constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float aspect = u.resolution.x / u.resolution.y;
    float t = u.time;

    float2 cuv = float2((uv.x - 0.5) * aspect, uv.y - 0.5);

    // Camera drift
    float camDriftX = sin(t * 0.15) * 0.03;
    float camDriftY = cos(t * 0.12) * 0.02;
    float foreshorten = 0.7 + camDriftY * 0.5;

    float2 meshUV = cuv;
    meshUV.x += camDriftX;
    meshUV.y = meshUV.y / foreshorten;
    meshUV.y += 0.08;
    meshUV = br_rot2(0.06 + sin(t * 0.08) * 0.02) * meshUV;

    // Displacement
    float h = br_displacement(meshUV, t, BR_BASS_FREQ, BR_BASS_INTENSITY);
    float3 N = br_calcNormal(meshUV, t, BR_BASS_FREQ, BR_BASS_INTENSITY, h);

    // Hexagonal mesh
    float3 hex = br_hexGrid(meshUV + N.xy * 0.003, BR_MESH_SCALE);
    float hexEdge = hex.x;

    float wire = 1.0 - smoothstep(0.0, BR_WIRE_WIDTH, hexEdge);
    float hole = smoothstep(BR_WIRE_WIDTH, BR_WIRE_WIDTH + 0.02, hexEdge);

    float2 microGrid = fract(meshUV * BR_MESH_SCALE * 3.0 + N.xy * 0.01);
    float microWire = smoothstep(0.04, 0.0, min(microGrid.x, microGrid.y));
    microWire += smoothstep(0.04, 0.0, min(1.0 - microGrid.x, 1.0 - microGrid.y));
    microWire *= 0.15;

    // View direction
    float3 V = normalize(float3(-cuv.x * 0.3, -cuv.y * 0.3 + 0.2, 1.0));

    // Beat envelope
    float period = 1.0 / max(BR_BASS_FREQ, 0.01);
    float bFrac = fract(t / period);
    float bEnv = exp(-bFrac * 3.5);

    // Key light
    float3 L1 = normalize(float3(0.4 + sin(t * 0.25) * 0.4, 0.6 + cos(t * 0.18) * 0.3, 1.0));
    float NdL1 = max(dot(N, L1), 0.0);
    float3 H1 = normalize(L1 + V);
    float NdH1 = max(dot(N, H1), 0.0);
    float spec1 = pow(NdH1, 180.0);
    float spec1med = pow(NdH1, 50.0);
    float spec1soft = pow(NdH1, 12.0);
    float3 lightCol1 = float3(1.0, 0.82, 0.55);

    // Fill light
    float3 L2 = normalize(float3(-0.8 + sin(t * 0.15) * 0.2, 0.4, 0.8));
    float NdL2 = max(dot(N, L2), 0.0);
    float3 H2 = normalize(L2 + V);
    float NdH2 = max(dot(N, H2), 0.0);
    float spec2 = pow(NdH2, 120.0);
    float spec2soft = pow(NdH2, 25.0);
    float3 lightCol2 = float3(0.85, 0.55, 0.3);

    // Accent light
    float3 L3 = normalize(float3(0.3 + bEnv * 0.3, -0.6, 0.6));
    float NdL3 = max(dot(N, L3), 0.0);
    float3 H3 = normalize(L3 + V);
    float NdH3 = max(dot(N, H3), 0.0);
    float spec3 = pow(NdH3, 90.0);
    float spec3soft = pow(NdH3, 18.0);
    float3 lightCol3 = float3(1.0, 0.7, 0.25);

    // Top-down fill
    float3 L4 = normalize(float3(0.0, 0.1, 1.0));
    float NdL4 = max(dot(N, L4), 0.0);

    // Rim
    float NdV = max(dot(N, V), 0.0);
    float rim = pow(1.0 - NdV, 4.0);
    float3 rimCol = float3(0.9, 0.55, 0.2);

    // Base color
    float3 baseColor = float3(0.38, 0.32, 0.25);
    baseColor += float3(0.035, 0.025, 0.015) * br_noise(meshUV * 30.0);
    baseColor += float3(0.02, 0.015, 0.01) * br_noise(meshUV * 80.0 + 5.0);

    float f0 = 0.75;
    float fres = br_fresnel(NdV, f0);

    // Diffuse
    float3 diffuse = baseColor * (NdL1 * lightCol1 * 1.0 + NdL2 * lightCol2 * 0.5 + NdL3 * lightCol3 * 0.25 + NdL4 * 0.4);
    diffuse += baseColor * 0.18;
    float3 hemiAmb = mix(float3(0.04, 0.03, 0.02), float3(0.08, 0.06, 0.04), N.y * 0.5 + 0.5);
    diffuse += hemiAmb;

    // Specular
    float3 specular = float3(0.0);
    specular += spec1 * lightCol1 * 3.5;
    specular += spec1med * lightCol1 * 1.2;
    specular += spec1soft * lightCol1 * 0.25;
    specular += spec2 * lightCol2 * 2.5;
    specular += spec2soft * lightCol2 * 0.5;
    specular += spec3 * lightCol3 * 3.0;
    specular += spec3soft * lightCol3 * 0.4;
    specular *= fres;
    specular *= 1.0 + bEnv * 1.0 * BR_BASS_INTENSITY;

    float wireCenter = abs(hexEdge - BR_WIRE_WIDTH * 0.5) / max(BR_WIRE_WIDTH, 0.001);
    float aniso = pow(max(1.0 - wireCenter, 0.0), 3.0);
    specular += aniso * wire * float3(0.55, 0.4, 0.2) * fres * 0.5;

    float3 wireCol = diffuse + specular;
    wireCol += rim * rimCol * 0.5;
    wireCol += microWire * float3(0.15, 0.1, 0.06) * fres;

    // Hole interior
    float3 holeCol = float3(0.015, 0.01, 0.006);
    float coneRefl = max(dot(N, float3(0.0, 0.0, 1.0)), 0.0);
    holeCol += float3(0.03, 0.02, 0.01) * coneRefl;
    float conePush = max(h * 0.4, 0.0);
    holeCol += float3(0.06, 0.04, 0.02) * conePush;
    holeCol += float3(0.2, 0.12, 0.04) * bEnv * 0.35 * BR_BASS_INTENSITY;
    holeCol += float3(0.12, 0.06, 0.02) * bEnv * 0.15 * BR_BASS_INTENSITY;

    // Combine
    float3 col = mix(holeCol, wireCol, wire);
    col += microWire * float3(0.02, 0.018, 0.025) * (1.0 - hole * 0.7);

    // Beat color wash
    float3 beatColor = mix(float3(0.5, 0.3, 0.1), float3(0.4, 0.2, 0.08), sin(t * 0.4) * 0.5 + 0.5);
    col += beatColor * bEnv * 0.03 * BR_BASS_INTENSITY;

    // Environment reflection
    float3 refl = reflect(-V, N);
    float3 envCol = float3(0.03, 0.03, 0.06);
    envCol += float3(0.12, 0.08, 0.06) * pow(max(refl.y, 0.0), 2.0);
    envCol += float3(0.15, 0.08, 0.03) * pow(max(-refl.x, 0.0), 2.0);
    envCol += float3(0.2, 0.1, 0.04) * pow(max(-refl.y, 0.0), 3.0);
    float softbox = pow(max(dot(refl, normalize(float3(0.2, 0.8, 0.5))), 0.0), 8.0);
    envCol += float3(0.3, 0.28, 0.25) * softbox;
    envCol *= 1.0 + bEnv * 0.5 * BR_BASS_INTENSITY;
    col += envCol * fres * wire * 0.5;

    // Post processing
    float2 vc = uv - 0.5;
    float vig = 1.0 - dot(vc, vc) * 2.0;
    vig = smoothstep(0.0, 1.0, vig);
    col *= vig;

    float dofDist = length(cuv);
    float dof = smoothstep(0.3, 0.8, dofDist);
    col = mix(col, col * float3(0.7, 0.65, 0.75), dof * 0.3);

    // Film grain
    float grain = br_hash(in.pos.xy + fract(t * 7.3) * 100.0);
    col += (grain - 0.5) * 0.018;

    // Chromatic aberration
    float ca = dofDist * 0.003;
    col.r += (br_hash(in.pos.xy * 0.5 + 1.0) - 0.5) * ca;
    col.b += (br_hash(in.pos.xy * 0.5 + 2.0) - 0.5) * ca;

    // Tone mapping
    col = col / (col + float3(1.5));
    col = pow(max(col, float3(0.0)), float3(0.88));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
