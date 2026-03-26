#include "../Common.metal"

// ─── Clockwork Mind: Interlocking precision gears via SDF ───
// Ported from static/clockwork-mind.html (Canvas 2D gear drawing)
// Approach: SDF gear shapes with tooth profiles, metallic gradients,
// hub details, spoke cutouts. Multiple gears meshing together.

constant float CM_PI               = 3.14159265;
constant float CM_ROTATION_SPEED   = 0.5;
constant float CM_MODULE           = 0.012;
constant float CM_TOOTH_LAND_FRAC  = 0.40;
constant float CM_ADDENDUM         = 1.0;
constant float CM_DEDENDUM         = 1.25;
constant int   CM_NUM_GEARS        = 9;

// Gear definition: teeth, x, y, speed, direction, phase, spoke style, palette index
struct CMGear {
    int teeth;
    float2 center;
    float speed;
    float direction;
    float phase;
    int spokeStyle;
    int colorIdx;
};

// Metallic color palette (bronze/brass/gold/copper)
static float3 cm_palette(int idx) {
    switch (idx % 8) {
        case 0: return float3(0.725, 0.580, 0.392);  // bronze
        case 1: return float3(0.784, 0.667, 0.431);  // brass
        case 2: return float3(0.824, 0.686, 0.353);  // gold
        case 3: return float3(0.686, 0.510, 0.333);  // copper
        case 4: return float3(0.647, 0.557, 0.424);  // antique bronze
        case 5: return float3(0.765, 0.627, 0.412);  // old gold
        case 6: return float3(0.706, 0.608, 0.451);  // warm silver
        default: return float3(0.745, 0.569, 0.373); // deep bronze
    }
}

// Build the gear system analytically
static CMGear cm_get_gear(int idx) {
    // Gear definitions: teeth, placement angle from parent, parent index, spoke style
    // Central gear at origin
    CMGear g;
    float mod = CM_MODULE;

    if (idx == 0) {
        g.teeth = 40; g.center = float2(0.0); g.speed = 1.0;
        g.direction = 1.0; g.phase = 0.0; g.spokeStyle = 1; g.colorIdx = 0;
        return g;
    }

    // Define child gears relative to parents
    // [teeth, parentIdx, placementAngle, spokeStyle]
    int teeth_arr[9]       = {40, 20, 28, 16, 24, 14, 18, 12, 22};
    int parent_arr[9]      = {-1, 0, 0, 0, 0, 1, 2, 3, 4};
    float angles_arr[9]    = {0.0, -2.4, -0.8, 0.7, 2.3, -3.2, -1.5, 1.5, 3.1};
    int spoke_arr[9]       = {1, 2, 0, 3, 1, 2, 0, 3, 1};

    int myTeeth = teeth_arr[idx];
    int parentIdx = parent_arr[idx];
    float placementAngle = angles_arr[idx];

    // Recursively compute parent chain (max depth 2 in this config)
    // Build parent properties first
    float2 parentCenter = float2(0.0);
    float parentSpeed = 1.0;
    float parentDir = 1.0;
    float parentPhase = 0.0;
    int parentTeeth = 40;

    if (parentIdx == 0) {
        // Parent is central gear - already set
    } else {
        // Grandparent is always gear 0 for our small system
        int gpTeeth = 40;
        float gpPR = float(gpTeeth) * mod * 0.5;
        float pTeeth_f = float(teeth_arr[parentIdx]);
        float pPR = pTeeth_f * mod * 0.5;
        float pAngle = angles_arr[parentIdx];
        float meshDist = gpPR + pPR;
        parentCenter = float2(cos(pAngle), sin(pAngle)) * meshDist;
        parentSpeed = float(gpTeeth) / pTeeth_f;
        parentDir = -1.0;
        parentTeeth = teeth_arr[parentIdx];

        // Phase calculation for parent
        float ppPitch = CM_PI * 2.0 / float(gpTeeth);
        float cpPitch = CM_PI * 2.0 / pTeeth_f;
        float contactInLocal = pAngle;
        float phaseAtContact = fmod(fmod(contactInLocal, ppPitch) + ppPitch, ppPitch);
        float childAngOff = -phaseAtContact * float(gpTeeth) / pTeeth_f;
        parentPhase = (pAngle + CM_PI) - childAngOff - cpPitch * 0.5;
    }

    float parentPR = float(parentTeeth) * mod * 0.5;
    float childPR = float(myTeeth) * mod * 0.5;
    float meshDist = parentPR + childPR;

    g.center = parentCenter + float2(cos(placementAngle), sin(placementAngle)) * meshDist;
    g.teeth = myTeeth;
    g.speed = parentSpeed * float(parentTeeth) / float(myTeeth);
    g.direction = -parentDir;
    g.spokeStyle = spoke_arr[idx];
    g.colorIdx = idx;

    // Phase for meshing
    float parentPitch = CM_PI * 2.0 / float(parentTeeth);
    float childPitch = CM_PI * 2.0 / float(myTeeth);
    float contactInLocal = placementAngle - parentPhase;
    float parentPhaseAtContact = fmod(fmod(contactInLocal, parentPitch) + parentPitch, parentPitch);
    float childAngularOffset = -parentPhaseAtContact * float(parentTeeth) / float(myTeeth);
    g.phase = (placementAngle + CM_PI) - childAngularOffset - childPitch * 0.5;

    return g;
}

// Gear tooth profile SDF (distance to gear boundary)
static float cm_gear_sdf(float2 p, int teeth, float mod, float rotation) {
    float pitchR = float(teeth) * mod * 0.5;
    float addendum = mod * CM_ADDENDUM;
    float dedendum = mod * CM_DEDENDUM;
    float tipR = pitchR + addendum;
    float rootR = pitchR - dedendum;

    // Rotate point into gear local frame
    float ca = cos(-rotation);
    float sa = sin(-rotation);
    float2 rp = float2(p.x * ca - p.y * sa, p.x * sa + p.y * ca);

    float r = length(rp);
    float angle = atan2(rp.y, rp.x);

    // Tooth profile: modulate radius based on angle
    float toothAngle = CM_PI * 2.0 / float(teeth);
    float halfTooth = toothAngle * CM_TOOTH_LAND_FRAC * 0.5;

    // Angle within current tooth period
    float a = fmod(angle + CM_PI * 4.0, toothAngle) - toothAngle * 0.5;

    // Smooth tooth profile
    float toothBlend = smoothstep(halfTooth + toothAngle * 0.06, halfTooth, abs(a));
    float gearR = mix(rootR, tipR, toothBlend);

    return r - gearR;
}

// Render a single gear
static float3 cm_render_gear(float2 uv, CMGear g, float time) {
    float mod = CM_MODULE;
    float pitchR = float(g.teeth) * mod * 0.5;
    float addendum = mod * CM_ADDENDUM;
    float tipR = pitchR + addendum;

    float2 local = uv - g.center;
    float dist = length(local);

    // Early out if too far away
    if (dist > tipR * 1.8) return float3(0.0);

    float rotation = g.direction * g.speed * time * CM_ROTATION_SPEED + g.phase;
    float sdf = cm_gear_sdf(local, g.teeth, mod, rotation);

    float3 result = float3(0.0);

    // Gear body
    if (sdf < 0.001) {
        float3 baseCol = cm_palette(g.colorIdx);
        float3 bright = min(baseCol + float3(0.275, 0.235, 0.196), float3(1.0));
        float3 dark = max(baseCol - float3(0.235), float3(0.0));

        // Metallic gradient with rotating specular
        float specAngle = time * 0.3 + float(g.colorIdx) * 1.5;
        float2 specDir = float2(cos(specAngle), sin(specAngle));
        float specDot = dot(normalize(local), specDir);
        float radialFrac = dist / tipR;

        float3 metallic = mix(bright, baseCol, radialFrac * 0.8);
        metallic = mix(metallic, dark, smoothstep(0.3, 0.9, radialFrac));
        metallic += bright * 0.15 * smoothstep(0.0, 0.5, specDot) * (1.0 - radialFrac);

        // Edge highlight
        float edge = smoothstep(0.0, -0.002, sdf) * smoothstep(-0.003, -0.001, sdf);
        metallic += bright * edge * 0.25;

        // Hub
        float hubR = max(pitchR * 0.12, 0.005);
        float hubDist = dist;
        if (hubDist < hubR * 1.4) {
            float hubFrac = hubDist / (hubR * 1.4);
            metallic = mix(bright * 0.9, dark * 0.8, hubFrac);
        }
        // Axle hole
        if (hubDist < hubR * 0.5) {
            metallic = float3(0.059, 0.047, 0.039);
        }

        // Spoke cutouts (darken interior)
        float rootR = pitchR - mod * CM_DEDENDUM;
        float spokeOuterR = rootR * 0.85;
        float ca2 = cos(-rotation);
        float sa2 = sin(-rotation);
        float2 rl = float2(local.x * ca2 - local.y * sa2, local.x * sa2 + local.y * ca2);
        float rl_angle = atan2(rl.y, rl.x);

        if (g.spokeStyle == 1 && pitchR > 0.03) {
            // Spoked: wedge cutouts
            float numSpokes = 6.0;
            float spokeAngle = CM_PI * 2.0 / numSpokes;
            float sa3 = fmod(rl_angle + CM_PI * 4.0, spokeAngle);
            float spokeGap = spokeAngle * 0.85;
            if (sa3 > spokeAngle * 0.075 && sa3 < spokeGap &&
                dist > hubR * 1.5 && dist < spokeOuterR) {
                metallic = float3(0.031, 0.031, 0.031);
            }
        } else if (g.spokeStyle == 2 && pitchR > 0.025) {
            // Circular holes
            float numHoles = 5.0;
            float holeDist = (hubR + spokeOuterR) * 0.5;
            float holeR = (spokeOuterR - hubR) * 0.3;
            for (int h = 0; h < 5; h++) {
                float ha = float(h) / numHoles * CM_PI * 2.0;
                float2 holeCenter = float2(cos(ha), sin(ha)) * holeDist;
                if (length(rl - holeCenter) < holeR) {
                    metallic = float3(0.031, 0.031, 0.031);
                }
            }
        } else if (g.spokeStyle == 3 && pitchR > 0.025) {
            // Cross pattern with small holes between spokes
            float cutR2 = (hubR + spokeOuterR) * 0.5;
            float cutSize = (spokeOuterR - hubR) * 0.28;
            for (int cs = 0; cs < 4; cs++) {
                float arcMid = float(cs) / 4.0 * CM_PI * 2.0 + CM_PI / 8.0;
                float2 cc = float2(cos(arcMid), sin(arcMid)) * cutR2;
                if (length(rl - cc) < cutSize) {
                    metallic = float3(0.031, 0.031, 0.031);
                }
            }
        }

        // Concentric etch lines
        float etchAlpha = 0.08;
        for (int ring = 1; ring <= 3; ring++) {
            float ringR = rootR * (0.35 + 0.15 * float(ring));
            float etch = smoothstep(0.001, 0.0, abs(dist - ringR)) * etchAlpha;
            metallic += bright * etch;
        }

        result = metallic;
    }

    // Shadow/glow around gear
    float outerGlow = smoothstep(0.005, 0.0, sdf) * 0.08;
    result += float3(0.784, 0.584, 0.424) * outerGlow;

    return result;
}

fragment float4 fs_clockwork_mind(VSOut in [[stage_in]],
                                   constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float minDim = min(res.x, res.y);
    float2 uv = (in.pos.xy - res * 0.5) / minDim;
    float t = u.time;

    // Background with subtle warmth
    float3 col = float3(0.039, 0.039, 0.039);

    // Background grid dots
    float2 gridUV = fmod(abs(uv) + 0.01, 0.035) - 0.0175;
    float gridDot = smoothstep(0.002, 0.0, length(gridUV));
    col += float3(0.784, 0.584, 0.424) * gridDot * 0.012;

    // Vignette
    float vig = smoothstep(0.15, 0.65, length(uv));
    col *= 1.0 - vig * 0.6;

    // Ambient glow behind gears
    float glowR = 0.35;
    float pulse = 1.0 + 0.05 * sin(t * 0.8);
    float ambientGlow = smoothstep(glowR * pulse, 0.0, length(uv)) * 0.04;
    col += float3(0.784, 0.584, 0.424) * ambientGlow;

    // Render gears (back to front by depth)
    for (int i = CM_NUM_GEARS - 1; i >= 0; i--) {
        CMGear g = cm_get_gear(i);
        float3 gearCol = cm_render_gear(uv, g, t);
        // Composite: if gear has color, it occludes background
        float gearMask = step(0.001, dot(gearCol, float3(1.0)));
        col = mix(col, gearCol, gearMask);
    }

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
