#include "../Common.metal"

// ─── Crystal Lattice: Faceted crystalline structures with prismatic refraction ───
// Ported from static/crystal-lattice.html

constant float CL_PI = 3.14159265359;
constant float CL_TAU = 6.28318530718;
constant int CL_MAX_STEPS = 48;
constant float CL_MAX_DIST = 25.0;
constant float CL_SURF_DIST = 0.004;
constant float CL_GROWTH_SPEED = 1.0;
constant float CL_REFRACTION = 1.0;

// ── Rotation ──
static float2x2 cl_rot2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// ── Hash / noise ──
static float cl_hash(float n) { return fract(sin(n) * 43758.5453123); }

static float cl_noise(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 157.0 + i.z * 113.0;
    return mix(
        mix(mix(cl_hash(n), cl_hash(n + 1.0), f.x),
            mix(cl_hash(n + 157.0), cl_hash(n + 158.0), f.x), f.y),
        mix(mix(cl_hash(n + 113.0), cl_hash(n + 114.0), f.x),
            mix(cl_hash(n + 270.0), cl_hash(n + 271.0), f.x), f.y),
        f.z);
}

// ── SDF: Hexagonal prism ──
static float cl_sdHexPrism(float3 p, float2 h) {
    float3 q = abs(p);
    float d1 = q.z - h.y;
    float d2 = max(q.x * 0.866025 + q.y * 0.5, q.y) - h.x;
    return min(max(d1, d2), 0.0) + length(max(float2(d1, d2), 0.0));
}

// ── SDF: Box ──
static float cl_sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// ── Crystal shaft: hex prism with hex pyramid termination ──
static float cl_crystalShaft(float3 p, float radius, float height, float pointiness) {
    float taperLen = min(radius * pointiness, height * 0.4);
    p.y -= height * 0.5;
    float body = cl_sdHexPrism(float3(p.x, p.z, p.y), float2(radius, height * 0.5));
    float tipLocal = height * 0.5;
    float slope = radius / taperLen;
    float3 q = abs(p);
    float hexDist = max(q.x * 0.866025 + q.z * 0.5, q.z);
    float pyramid = hexDist - max(0.0, tipLocal - p.y) * slope;
    return max(body, pyramid);
}

// ── Scene SDF ──
static float cl_sceneSDF(float3 p, float t) {
    float d = CL_MAX_DIST;
    float density = CL_GROWTH_SPEED;
    float ga = smoothstep(0.0, 2.5, t);

    // Central crystal
    {
        float3 cp = p - float3(0.0, -1.0, 0.0);
        cp.xz = cl_rot2(0.05) * cp.xz;
        d = min(d, cl_crystalShaft(cp, 0.5 * ga, 2.8 * ga, 2.2));
    }
    // Right crystal
    if (density > 0.3) {
        float3 cp = p - float3(0.4, -1.0, 0.1);
        cp.xy = cl_rot2(-0.3) * cp.xy;
        cp.xz = cl_rot2(0.2) * cp.xz;
        d = min(d, cl_crystalShaft(cp, 0.4 * ga, 2.2 * ga, 2.0));
    }
    // Left crystal
    if (density > 0.3) {
        float3 cp = p - float3(-0.45, -1.0, -0.1);
        cp.xy = cl_rot2(0.35) * cp.xy;
        cp.xz = cl_rot2(-0.3) * cp.xz;
        d = min(d, cl_crystalShaft(cp, 0.38 * ga, 2.0 * ga, 1.9));
    }
    // Back crystal
    if (density > 0.5) {
        float3 cp = p - float3(0.1, -1.0, -0.5);
        cp.yz = cl_rot2(-0.3) * cp.yz;
        cp.xz = cl_rot2(0.5) * cp.xz;
        d = min(d, cl_crystalShaft(cp, 0.32 * ga, 1.8 * ga, 2.3));
    }
    // Back-left
    if (density > 0.5) {
        float3 cp = p - float3(-0.5, -1.0, -0.4);
        cp.xy = cl_rot2(0.35) * cp.xy;
        cp.yz = cl_rot2(-0.25) * cp.yz;
        d = min(d, cl_crystalShaft(cp, 0.3 * ga, 1.5 * ga, 2.0));
    }
    // Front-left
    if (density > 0.8) {
        float3 cp = p - float3(-0.35, -1.0, 0.45);
        cp.xy = cl_rot2(0.4) * cp.xy;
        cp.yz = cl_rot2(0.3) * cp.yz;
        d = min(d, cl_crystalShaft(cp, 0.26 * ga, 1.3 * ga, 2.1));
    }
    // Front-right
    if (density > 0.8) {
        float3 cp = p - float3(0.5, -1.0, 0.35);
        cp.xy = cl_rot2(-0.5) * cp.xy;
        cp.xz = cl_rot2(-0.2) * cp.xz;
        d = min(d, cl_crystalShaft(cp, 0.22 * ga, 1.0 * ga, 2.4));
    }
    // Accent crystals
    if (density > 1.0) {
        { float3 cp = p - float3(0.65, -1.0, 0.3); cp.xy = cl_rot2(-0.6) * cp.xy; cp.xz = cl_rot2(0.8) * cp.xz;
          d = min(d, cl_crystalShaft(cp, 0.12 * ga, 0.5 * ga, 2.0)); }
        { float3 cp = p - float3(-0.6, -1.0, 0.5); cp.xy = cl_rot2(0.55) * cp.xy; cp.xz = cl_rot2(-0.6) * cp.xz;
          d = min(d, cl_crystalShaft(cp, 0.1 * ga, 0.4 * ga, 2.2)); }
        { float3 cp = p - float3(0.3, -1.0, -0.6); cp.xy = cl_rot2(-0.4) * cp.xy; cp.yz = cl_rot2(-0.5) * cp.yz;
          d = min(d, cl_crystalShaft(cp, 0.14 * ga, 0.55 * ga, 1.8)); }
        { float3 cp = p - float3(-0.25, -1.0, -0.55); cp.xy = cl_rot2(0.5) * cp.xy; cp.yz = cl_rot2(-0.35) * cp.yz;
          d = min(d, cl_crystalShaft(cp, 0.11 * ga, 0.45 * ga, 2.1)); }
    }
    // Outer ring
    if (density > 1.4) {
        { float3 cp = p - float3(0.8, -1.0, 0.0); cp.xy = cl_rot2(-0.55) * cp.xy; cp.xz = cl_rot2(0.1) * cp.xz;
          d = min(d, cl_crystalShaft(cp, 0.28 * ga, 1.6 * ga, 2.0)); }
        { float3 cp = p - float3(-0.7, -1.0, 0.4); cp.xy = cl_rot2(0.5) * cp.xy; cp.xz = cl_rot2(-0.4) * cp.xz;
          d = min(d, cl_crystalShaft(cp, 0.25 * ga, 1.4 * ga, 2.1)); }
        { float3 cp = p - float3(0.2, -1.0, 0.75); cp.xy = cl_rot2(-0.2) * cp.xy; cp.yz = cl_rot2(0.5) * cp.yz;
          d = min(d, cl_crystalShaft(cp, 0.22 * ga, 1.2 * ga, 2.3)); }
        { float3 cp = p - float3(-0.3, -1.0, -0.7); cp.xy = cl_rot2(0.45) * cp.xy; cp.yz = cl_rot2(-0.4) * cp.yz;
          d = min(d, cl_crystalShaft(cp, 0.24 * ga, 1.3 * ga, 1.9)); }
    }
    // Dense procedural bed
    if (density > 1.7) {
        for (int i = 0; i < 8; i++) {
            float fi = float(i);
            float angle = fi * 0.785 + 0.15;
            float dist = 0.65 + sin(fi * 2.7) * 0.2;
            float3 cp = p - float3(cos(angle) * dist, -1.0, sin(angle) * dist);
            float tiltAngle = 0.6 + sin(fi * 3.1) * 0.25;
            cp.xy = cl_rot2(cos(angle) * tiltAngle) * cp.xy;
            cp.yz = cl_rot2(sin(angle) * tiltAngle * 0.5) * cp.yz;
            float r = (0.08 + sin(fi * 4.3) * 0.04) * ga;
            float h = (0.4 + sin(fi * 2.1) * 0.15) * ga;
            d = min(d, cl_crystalShaft(cp, r, h, 2.0));
        }
    }

    return d;
}

// ── Raymarching ──
static float cl_march(float3 ro, float3 rd, float t) {
    float d = 0.0;
    for (int i = 0; i < CL_MAX_STEPS; i++) {
        float3 p = ro + rd * d;
        float ds = cl_sceneSDF(p, t);
        d += ds;
        if (ds < CL_SURF_DIST || d > CL_MAX_DIST) break;
    }
    return d;
}

// ── Normal via tetrahedron technique ──
static float3 cl_getNormal(float3 p, float t) {
    float2 e = float2(0.008, -0.008);
    return normalize(
        e.xyy * cl_sceneSDF(p + e.xyy, t) +
        e.yyx * cl_sceneSDF(p + e.yyx, t) +
        e.yxy * cl_sceneSDF(p + e.yxy, t) +
        e.xxx * cl_sceneSDF(p + e.xxx, t)
    );
}

// ── Spectral color ──
static float3 cl_spectral(float t) {
    float tt = fract(t);
    float3 c;
    if (tt < 0.17) c = mix(float3(0.4, 0.0, 0.6), float3(0.15, 0.15, 1.0), tt / 0.17);
    else if (tt < 0.33) c = mix(float3(0.15, 0.15, 1.0), float3(0.0, 0.85, 0.7), (tt - 0.17) / 0.16);
    else if (tt < 0.5) c = mix(float3(0.0, 0.85, 0.7), float3(0.0, 1.0, 0.15), (tt - 0.33) / 0.17);
    else if (tt < 0.67) c = mix(float3(0.0, 1.0, 0.15), float3(1.0, 0.95, 0.0), (tt - 0.5) / 0.17);
    else if (tt < 0.83) c = mix(float3(1.0, 0.95, 0.0), float3(1.0, 0.35, 0.0), (tt - 0.67) / 0.16);
    else c = mix(float3(1.0, 0.35, 0.0), float3(0.55, 0.0, 0.35), (tt - 0.83) / 0.17);
    return c;
}

// ── Fresnel ──
static float cl_fresnel(float3 rd, float3 n, float ior) {
    float cosI = abs(dot(rd, n));
    float r0 = (1.0 - ior) / (1.0 + ior);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow(1.0 - cosI, 5.0);
}

// ── Internal refraction color ──
static float3 cl_internalColor(float3 p, float3 rd, float3 n, float t) {
    float ior = 1.55;
    float3 refractDir = refract(rd, n, 1.0 / ior);
    if (length(refractDir) < 0.01) refractDir = reflect(rd, n);

    float sd = cl_sceneSDF(p - n * 0.3, t);
    float pathLen = clamp(-sd * 3.0 + 0.3, 0.1, 1.0);

    float cr = pathLen * 1.95 + dot(refractDir, float3(1.0, 0.3, 0.2)) * 0.55;
    float cg = pathLen * 2.0 + dot(refractDir, float3(0.3, 1.0, 0.2)) * 0.55;
    float cb = pathLen * 2.05 + dot(refractDir, float3(0.2, 0.3, 1.0)) * 0.55;

    float3 prism = float3(
        cl_spectral(cr * 0.3 + t * 0.05).r,
        cl_spectral(cg * 0.3 + t * 0.05).g,
        cl_spectral(cb * 0.3 + t * 0.05).b
    );

    float3 absorption = exp(-pathLen * float3(0.15, 0.7, 1.8));
    return prism * 0.3 + absorption * 0.7;
}

// ── Ambient occlusion ──
static float cl_ao(float3 p, float3 n, float t) {
    float h1 = 0.05, h2 = 0.2;
    float d1 = cl_sceneSDF(p + n * h1, t);
    float d2 = cl_sceneSDF(p + n * h2, t);
    return clamp(1.0 - 1.5 * ((h1 - d1) + (h2 - d2) * 0.5), 0.0, 1.0);
}

fragment float4 fs_crystal_lattice(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * float2(0.5)) / min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float slowT = t * 0.2;

    // Camera
    float camAngle = slowT * 0.3;
    float camRadius = 5.5;
    float camHeight = clamp(1.0 + sin(slowT * 0.4) * 0.4, -1.5, 4.0);
    float3 ro = float3(sin(camAngle) * camRadius, camHeight, cos(camAngle) * camRadius);
    float3 target = float3(0.0, -0.3, 0.0);

    float3 fwd = normalize(target - ro);
    float3 right = normalize(cross(fwd, float3(0, 1, 0)));
    float3 up = cross(right, fwd);
    float3 rd = normalize(fwd * 1.1 + right * uv.x + up * uv.y);

    // Lights
    float3 light1Dir = normalize(float3(0.8, 1.2, 0.6));
    float3 light1Col = float3(1.0, 0.92, 0.8) * 1.5;
    float3 light2Dir = normalize(float3(-0.5, 0.3, -0.8));
    float3 light2Col = float3(0.6, 0.7, 1.0) * 0.6;
    float3 light3Dir = normalize(float3(0.0, -0.5, 1.0));
    float3 light3Col = float3(0.9, 0.75, 0.5) * 0.4;

    // March
    float d = cl_march(ro, rd, t);

    // Background
    float3 col = float3(0.025, 0.02, 0.028);
    float2 center = (float2(0.5, 0.45) - 0.5) * 2.0;
    float glowDist = length(uv - center * 0.1);
    col += float3(0.12, 0.07, 0.04) * exp(-glowDist * 1.5);
    col += float3(0.02, 0.015, 0.03) * (1.0 - uv.y);
    float vig = 1.0 - dot(uv, uv) * 0.6;
    col *= vig;

    if (d < CL_MAX_DIST) {
        float3 p = ro + rd * d;
        float3 n = cl_getNormal(p, t);

        float diff1 = max(dot(n, light1Dir), 0.0);
        float diff2 = max(dot(n, light2Dir), 0.0);
        float diff3 = max(dot(n, light3Dir), 0.0);

        float3 h1 = normalize(light1Dir - rd);
        float3 h2 = normalize(light2Dir - rd);
        float spec1 = pow(max(dot(n, h1), 0.0), 90.0);
        float spec2 = pow(max(dot(n, h2), 0.0), 60.0);

        float fres = cl_fresnel(rd, n, 1.55);
        float occ = cl_ao(p, n, t);
        float sha = smoothstep(0.0, 0.5, cl_sceneSDF(p + light1Dir * 0.3, t));

        // Crystal material
        float heightFade = smoothstep(-1.2, 1.5, p.y);
        float3 crystalBase = mix(float3(0.8, 0.35, 0.12), float3(1.0, 0.55, 0.22), heightFade);
        crystalBase += cl_noise(p * 6.0 + t * 0.1) * float3(0.1, 0.05, -0.05);

        float3 interior = cl_internalColor(p, rd, n, t);
        interior *= CL_REFRACTION;

        float3 refl = reflect(rd, n);
        float envNoise = cl_noise(refl * 3.0 + t * 0.1);
        float3 envColor = mix(float3(0.2, 0.12, 0.06), float3(0.5, 0.35, 0.18), envNoise);
        envColor += cl_spectral(dot(refl, float3(0.5, 1.0, 0.3)) * 0.5 + t * 0.05) * 0.3 * CL_REFRACTION;

        float3 crystalCol = mix(interior, envColor, fres * 0.5);

        float3 diffuse = crystalBase * (diff1 * light1Col * sha + diff2 * light2Col + diff3 * light3Col);
        float3 specularH = light1Col * spec1 * sha + light2Col * spec2;

        float sFlicker = sin(dot(p, float3(13.7, 7.3, 11.1)) * 50.0 + t * 3.0) * 0.5 + 0.5;
        float sparkle = spec1 * sFlicker;
        float3 sparkleCol = mix(float3(1.0, 0.95, 0.85), cl_spectral(dot(p, float3(3.1, 7.3, 5.7)) + t * 0.3), 0.4);

        float striation = sin(dot(p, n) * 80.0 + cl_noise(p * 12.0) * 6.0) * 0.5 + 0.5;
        striation = smoothstep(0.3, 0.7, striation) * 0.15;
        crystalCol *= 1.0 + striation;

        col = diffuse * 0.15 + crystalCol * 0.75 + specularH * 0.7 + sparkleCol * sparkle * 0.5;
        col *= occ;

        float rimVal = pow(1.0 - max(dot(-rd, n), 0.0), 3.0);
        col += crystalBase * rimVal * 0.35;

        float edgeShimmer = fres * pow(max(dot(n, light1Dir), 0.0), 0.5);
        float3 prismEdge = cl_spectral(dot(p, float3(3.0, 5.0, 7.0)) * 0.4 + dot(n, rd) * 2.0 + t * 0.08);
        col += prismEdge * edgeShimmer * 0.35 * CL_REFRACTION;

        float caustic = pow(max(sin(dot(p, float3(5.0, 3.0, 7.0)) * 4.0 + t * 1.5), 0.0), 8.0);
        col += cl_spectral(dot(p, float3(2.1, 5.3, 3.7)) * 0.5 + t * 0.1) * caustic * 0.12 * CL_REFRACTION;

        float backLight = pow(clamp(dot(rd, light1Dir), 0.0, 1.0), 2.0);
        col += crystalBase * backLight * 0.6;

        float wrap = max(dot(n, light1Dir) * 0.5 + 0.5, 0.0);
        col += crystalBase * wrap * 0.1 * (1.0 - heightFade);
    }

    // Dust particles
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float3 sparkPos = float3(
            sin(fi * 2.37 + t * 0.15) * 2.0,
            sin(fi * 1.73 + t * 0.1) * 1.5 + 0.5,
            cos(fi * 3.11 + t * 0.12) * 2.0
        );
        float distToRay = length(cross(sparkPos - ro, rd));
        float depthAlongRay = dot(sparkPos - ro, rd);
        if (depthAlongRay > 0.0 && depthAlongRay < d) {
            float brightness = exp(-distToRay * 80.0) * 0.6;
            float flicker = sin(t * 3.0 + fi * 5.0) * 0.5 + 0.5;
            col += float3(1.0, 0.9, 0.7) * brightness * flicker;
        }
    }

    // ACES-ish tone mapping
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
    col = pow(col, float3(0.94, 0.97, 1.04));
    col = pow(col, float3(1.0 / 2.2));

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
