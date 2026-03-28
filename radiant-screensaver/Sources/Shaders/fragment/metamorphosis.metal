#include "../Common.metal"

// ─── Metamorphosis: Raymarched metaballs with liquid-metal surface ───
// Ported from static/metamorphosis.html

constant float MM_TAU = 6.28318530718;
constant int MM_MAX_STEPS = 48;
constant float MM_MAX_DIST = 20.0;
constant float MM_SURF_DIST = 0.002;
constant int MM_BLOB_MAX = 6;
constant float MM_MORPH_SPEED = 0.5;
constant int MM_BLOB_COUNT = 4;

// ── Blob data (thread-local, precomputed per pixel) ──
struct MMBlobs {
    float3 pos[6];
    float3 radStretch[6];
    float2x2 rotXY[6];
    float2x2 rotYZ[6];
    int count;
};

static float mm_smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

static float mm_sdEllipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / k1;
}

static float mm_scene(float3 p, thread const MMBlobs& blobs) {
    float d = MM_MAX_DIST;
    for (int i = 0; i < MM_BLOB_MAX; i++) {
        if (i >= blobs.count) break;
        float3 q = p - blobs.pos[i];
        q = float3(blobs.rotXY[i] * q.xy, q.z);
        q = float3(q.x, blobs.rotYZ[i] * q.yz);
        d = mm_smin(d, mm_sdEllipsoid(q, blobs.radStretch[i]), 0.6);
    }
    return d;
}

// Tetrahedron normal
static float3 mm_calcNormal(float3 p, thread const MMBlobs& blobs) {
    float2 e = float2(0.002, -0.002);
    return normalize(
        e.xyy * mm_scene(p + e.xyy, blobs) +
        e.yyx * mm_scene(p + e.yyx, blobs) +
        e.yxy * mm_scene(p + e.yxy, blobs) +
        e.xxx * mm_scene(p + e.xxx, blobs)
    );
}

static float mm_softShadow(float3 ro, float3 rd, float mint, float maxt, float k, thread const MMBlobs& blobs) {
    float res = 1.0;
    float ph = 1e10;
    float t = mint;
    for (int i = 0; i < 16; i++) {
        float h = mm_scene(ro + rd * t, blobs);
        if (h < 0.001) return 0.0;
        float y = h * h / (2.0 * ph);
        float d = sqrt(h * h - y * y);
        res = min(res, k * d / max(0.0, t - y));
        ph = h;
        t += h;
        if (t > maxt) break;
    }
    return clamp(res, 0.0, 1.0);
}

static float mm_calcAO(float3 p, float3 n, thread const MMBlobs& blobs) {
    float occ = 0.0;
    float sca = 1.0;
    for (int i = 0; i < 3; i++) {
        float h = 0.01 + 0.12 * float(i) / 2.0;
        float d = mm_scene(p + h * n, blobs);
        occ += (h - d) * sca;
        sca *= 0.95;
    }
    return clamp(1.0 - 3.0 * occ, 0.0, 1.0);
}

static float mm_fresnel(float cosTheta, float f0) {
    return f0 + (1.0 - f0) * pow(1.0 - cosTheta, 5.0);
}

static float3 mm_envMap(float3 rd) {
    float y = rd.y * 0.5 + 0.5;
    float3 sky = mix(
        float3(0.02, 0.015, 0.01),
        float3(0.08, 0.05, 0.03),
        y
    );
    float sun = pow(max(dot(rd, normalize(float3(2.0, 3.0, 1.0))), 0.0), 32.0);
    sky += float3(1.0, 0.85, 0.6) * sun * 0.5;
    float fill = pow(max(dot(rd, normalize(float3(-2.0, 1.0, -1.0))), 0.0), 8.0);
    sky += float3(0.6, 0.35, 0.3) * fill * 0.15;
    float rim = pow(max(dot(rd, normalize(float3(0.0, 0.5, -2.0))), 0.0), 16.0);
    sky += float3(0.8, 0.5, 0.25) * rim * 0.2;
    return sky;
}

fragment float4 fs_metamorphosis(VSOut in [[stage_in]],
                                 constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float t = u.time;
    float speed = t * MM_MORPH_SPEED;

    // Precompute all blob data
    MMBlobs blobs;
    blobs.count = MM_BLOB_COUNT;
    for (int i = 0; i < MM_BLOB_MAX; i++) {
        if (i >= blobs.count) break;
        float fi = float(i);
        float phase = fi * MM_TAU / 6.0;
        blobs.pos[i] = float3(
            sin(speed * 0.7 + phase) * 0.8 + sin(speed * 0.3 + phase * 2.3) * 0.3,
            cos(speed * 0.5 + phase * 1.4) * 0.6 + sin(speed * 0.8 + phase * 0.7) * 0.25,
            sin(speed * 0.6 + phase * 1.8) * 0.5 + cos(speed * 0.4 + phase * 2.1) * 0.2
        );
        float base = 0.45 + fi * 0.03;
        float pulse = sin(speed * 1.2 + fi * 1.7) * 0.08 + sin(speed * 0.5 + fi * 3.1) * 0.05;
        float r = base + pulse;
        float sx = 1.0 + sin(speed * 0.9 + fi * 2.3) * 0.25;
        float sy = 1.0 + cos(speed * 0.7 + fi * 1.9) * 0.2;
        float sz = 1.0 + sin(speed * 1.1 + fi * 2.7) * 0.2;
        float norm = pow(1.0 / (sx * sy * sz), 0.333);
        blobs.radStretch[i] = float3(r) * float3(sx, sy, sz) * norm;
        float ca = cos(speed * 0.3 + fi * 1.1), sa = sin(speed * 0.3 + fi * 1.1);
        blobs.rotXY[i] = float2x2(float2(ca, -sa), float2(sa, ca));
        float cb = cos(speed * 0.2 + fi * 0.9), sb = sin(speed * 0.2 + fi * 0.9);
        blobs.rotYZ[i] = float2x2(float2(cb, -sb), float2(sb, cb));
    }

    // Camera
    float3 ro = float3(0.0, 0.3, 3.8);
    float3 target = float3(0.0);
    float3 fwd = normalize(target - ro);
    float3 right = normalize(cross(fwd, float3(0.0, 1.0, 0.0)));
    float3 up = cross(right, fwd);
    float3 rd = normalize(fwd * 1.5 + right * uv.x + up * uv.y);

    // Bounding sphere early-out
    float BS_RADIUS_SQ = 6.25; // radius 2.5 squared
    float bsB = dot(ro, rd);
    float bsC = dot(ro, ro) - BS_RADIUS_SQ;
    float bsDisc = bsB * bsB - bsC;

    float totalDist = 0.0;
    float dist;
    float3 p;
    bool hit = false;

    if (bsDisc > 0.0) {
        float sqrtDisc = sqrt(bsDisc);
        float t0 = -bsB - sqrtDisc;
        float t1 = -bsB + sqrtDisc;
        if (t1 > 0.0) {
            totalDist = max(t0, 0.0);
            float marchLimit = min(t1, MM_MAX_DIST);
            for (int i = 0; i < MM_MAX_STEPS; i++) {
                p = ro + rd * totalDist;
                dist = mm_scene(p, blobs);
                if (dist < MM_SURF_DIST) { hit = true; break; }
                if (totalDist > marchLimit) break;
                totalDist += dist;
            }
        }
    }

    float3 col = float3(0.0);

    if (hit) {
        float3 n = mm_calcNormal(p, blobs);
        float3 v = normalize(ro - p);

        float3 baseColor = float3(0.85, 0.65, 0.3);
        float3 roseColor = float3(0.8, 0.5, 0.45);
        float3 copperColor = float3(0.75, 0.45, 0.25);

        float colorMix1 = sin(p.x * 3.0 + p.z * 2.0 + t * MM_MORPH_SPEED * 0.4) * 0.5 + 0.5;
        float colorMix2 = sin(p.y * 4.0 - p.x * 2.5 + t * MM_MORPH_SPEED * 0.3) * 0.5 + 0.5;
        float3 albedo = mix(baseColor, roseColor, colorMix1 * 0.3);
        albedo = mix(albedo, copperColor, colorMix2 * 0.25);

        float metallic = 0.9;
        float roughness = 0.15;

        float3 lightDir1 = normalize(float3(2.0, 3.0, 1.5));
        float3 lightCol1 = float3(1.0, 0.9, 0.75) * 1.6;
        float3 lightDir2 = normalize(float3(-2.0, 1.0, -1.0));
        float3 lightCol2 = float3(0.7, 0.4, 0.35) * 0.6;
        float3 lightDir3 = normalize(float3(0.0, 0.5, -2.0));
        float3 lightCol3 = float3(0.9, 0.6, 0.3) * 0.8;

        float diff1 = max(dot(n, lightDir1), 0.0);
        float diff2 = max(dot(n, lightDir2), 0.0);
        float diff3 = max(dot(n, lightDir3), 0.0);

        float specPow = mix(256.0, 32.0, roughness);
        float3 h1 = normalize(lightDir1 + v);
        float3 h2 = normalize(lightDir2 + v);
        float3 h3 = normalize(lightDir3 + v);
        float spec1 = pow(max(dot(n, h1), 0.0), specPow);
        float spec2 = pow(max(dot(n, h2), 0.0), specPow);
        float spec3 = pow(max(dot(n, h3), 0.0), specPow);

        float NdotV = max(dot(n, v), 0.0);
        float fres = mm_fresnel(NdotV, 0.04 + metallic * 0.76);

        float shadow = mm_softShadow(p + n * 0.01, lightDir1, 0.02, 5.0, 16.0, blobs);
        float ao = mm_calcAO(p, n, blobs);

        float3 diffuse = albedo * (1.0 - metallic) * (
            lightCol1 * diff1 * shadow +
            lightCol2 * diff2 +
            lightCol3 * diff3
        );

        float3 specColor = mix(float3(0.04), albedo, metallic);
        float3 specular = specColor * (
            lightCol1 * spec1 * shadow * 1.5 +
            lightCol2 * spec2 * 0.8 +
            lightCol3 * spec3 * 1.0
        );

        float3 reflDir = reflect(-v, n);
        float3 envRefl = mm_envMap(reflDir);
        float3 envContrib = envRefl * mix(float3(0.04), albedo, metallic) * fres;

        float rimFactor = pow(1.0 - NdotV, 4.0);
        float3 rimColor = float3(0.9, 0.6, 0.35) * rimFactor * 0.8;

        float subsurface = pow(max(dot(-v, lightDir1), 0.0), 3.0) * (1.0 - metallic) * 0.2;
        float3 sssColor = float3(1.0, 0.7, 0.4) * subsurface;

        col = diffuse + specular + envContrib + rimColor + sssColor;
        col *= ao;

        float topSpec = pow(max(dot(n, h1), 0.0), 512.0) * shadow;
        col += float3(1.0, 0.98, 0.92) * topSpec * 2.0;

    } else {
        col = float3(0.012, 0.01, 0.008);
    }

    // Floor glow
    float floorY = -1.2;
    if (rd.y < 0.0) {
        float floorT = (floorY - ro.y) / rd.y;
        if (floorT > 0.0 && floorT < MM_MAX_DIST && !hit) {
            float3 floorP = ro + rd * floorT;
            float floorDist = length(floorP.xz);
            float glow = exp(-floorDist * floorDist * 1.5) * 0.15;
            glow *= 0.8 + 0.2 * sin(t * MM_MORPH_SPEED * 0.5);
            float3 glowColor = float3(0.6, 0.4, 0.2) * glow;
            float caustic = sin(floorP.x * 8.0 + t * 0.5) * sin(floorP.z * 8.0 + t * 0.7);
            caustic = caustic * caustic;
            glowColor += float3(0.4, 0.25, 0.1) * caustic * glow * 2.0;
            col += glowColor;
        }
    }

    // Atmospheric glow for missed rays
    if (!hit) {
        float closestT = max(-dot(ro, rd), 0.0);
        float3 closestP = ro + rd * closestT;
        float closestDist = length(closestP);
        float atmosGlow = exp(-closestDist * closestDist * 0.8) * 0.08;
        col += float3(0.5, 0.35, 0.15) * atmosGlow;
    }

    // ACES-ish tone mapping
    col = col * (2.51 * col + 0.03) / (col * (2.43 * col + 0.59) + 0.14);
    col = pow(col, float3(0.95, 0.98, 1.04));
    float vig = 1.0 - dot(uv, uv) * 0.25;
    col *= vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
