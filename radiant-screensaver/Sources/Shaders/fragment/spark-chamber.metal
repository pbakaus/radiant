#include "../Common.metal"

// ─── Spark Chamber: Magnetic field particle tracks ───
// Ported from static/spark-chamber.html

constant float SC_NUM_TRACKS = 12.0;
constant float SC_TWO_PI = 6.28318530;
constant float SC_FIELD_STRENGTH = 0.008;
constant float SC_DRAG = 0.999;
constant float SC_TRAIL_GLOW_WIDTH = 3.0;

// ── Hash functions ──
static float sc_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float sc_hash1(float p) {
    return fract(sin(p * 127.1) * 43758.5453);
}

// ── Analytically compute a charged particle spiral position ──
// A charged particle in a uniform B-field traces a circle.
// With drag, it spirals inward. We approximate this analytically.
static float2 sc_trackPoint(float trackId, float along, float t) {
    // Each track has unique seed-based properties
    float seed = trackId * 17.31 + 3.7;

    // Entry point: from edges
    float entryAngle = sc_hash1(seed) * SC_TWO_PI;
    float2 entryDir = float2(cos(entryAngle), sin(entryAngle));
    float2 entryPos = float2(sc_hash1(seed + 1.0) * 2.0 - 1.0,
                             sc_hash1(seed + 2.0) * 2.0 - 1.0) * 0.4;

    // Initial velocity
    float speed = 0.3 + sc_hash1(seed + 3.0) * 0.4;
    float charge = (sc_hash1(seed + 4.0) > 0.5) ? 1.0 : -1.0;
    float mass = 0.8 + sc_hash1(seed + 5.0) * 0.4;

    // Cyclotron radius: r = mv / (qB)
    float B = SC_FIELD_STRENGTH;
    float cyclotronR = mass * speed / B;
    float omega = charge * B / mass; // angular velocity

    // Spiral: position along the track parameterized by 'along'
    // Apply drag decay to radius
    float decayRate = 1.0 - SC_DRAG;
    float effRadius = cyclotronR * exp(-along * decayRate * 20.0);
    float angle = omega * along * 50.0;

    // Center of circular motion drifts with initial velocity direction
    float2 drift = entryDir * along * speed * 0.5;
    float2 circleOffset = float2(cos(angle), sin(angle)) * effRadius;

    return entryPos + drift + circleOffset;
}

// ── Energy along a track (decays with distance) ──
static float sc_trackEnergy(float trackId, float along) {
    float seed = trackId * 17.31 + 3.7;
    float initialEnergy = 0.7 + sc_hash1(seed + 6.0) * 0.3;
    return initialEnergy * exp(-along * 2.0);
}

// ── Energy-based warm color ──
static float3 sc_energyColor(float energy) {
    float3 dimCopper   = float3(0.47, 0.29, 0.16);
    float3 warmAmber   = float3(0.67, 0.43, 0.22);
    float3 richGold    = float3(0.82, 0.65, 0.35);
    float3 brightWhite = float3(1.0, 0.94, 0.82);

    if (energy > 0.8) {
        return mix(richGold, brightWhite, (energy - 0.8) / 0.2);
    } else if (energy > 0.5) {
        return mix(warmAmber, richGold, (energy - 0.5) / 0.3);
    } else if (energy > 0.2) {
        return mix(dimCopper, warmAmber, (energy - 0.2) / 0.3);
    } else {
        return dimCopper * (energy / 0.2);
    }
}

fragment float4 fs_spark_chamber(VSOut in [[stage_in]],
                                  constant CommonUniforms& u [[buffer(0)]]) {
    float2 res = u.resolution;
    float minRes = min(res.x, res.y);
    float2 p = (in.pos.xy - res * 0.5) / minRes;
    float t = u.time;

    float3 col = float3(0.039, 0.039, 0.039); // #0a0a0a

    // For each track, evaluate distance from this pixel to the track curve
    int numTracks = int(SC_NUM_TRACKS);

    for (int ti = 0; ti < numTracks; ti++) {
        // Stagger track appearance over time
        float trackId = float(ti) + floor(t * 0.3) * SC_NUM_TRACKS;
        float trackAge = fract(t * 0.3) * 3.0 + float(ti) * 0.15;

        // Sample points along the track to find closest approach
        float minDist = 1e6;
        float closestEnergy = 0.0;
        float closestAlong = 0.0;

        // Coarse search
        float bestAlong = 0.0;
        float bestDist = 1e6;
        int numSamples = 40;
        float maxAlong = min(trackAge, 2.0);

        for (int s = 0; s < numSamples; s++) {
            float along = float(s) / float(numSamples) * maxAlong;
            float2 tp = sc_trackPoint(trackId, along, t);
            float d = length(p - tp);
            if (d < bestDist) {
                bestDist = d;
                bestAlong = along;
            }
        }

        // Refine search around best point
        float searchRange = maxAlong / float(numSamples) * 2.0;
        for (int s = 0; s < 8; s++) {
            float along = bestAlong - searchRange + float(s) / 7.0 * searchRange * 2.0;
            along = clamp(along, 0.0, maxAlong);
            float2 tp = sc_trackPoint(trackId, along, t);
            float d = length(p - tp);
            if (d < bestDist) {
                bestDist = d;
                bestAlong = along;
            }
        }

        minDist = bestDist;
        closestEnergy = sc_trackEnergy(trackId, bestAlong);
        closestAlong = bestAlong;

        // Trail glow
        float energy = closestEnergy;
        if (energy < 0.02) continue;

        // Width scales with energy
        float trailWidth = (SC_TRAIL_GLOW_WIDTH + energy * 6.0) / minRes;
        float glow = exp(-minDist * minDist / (trailWidth * trailWidth));

        // Position fade: newer parts brighter
        float posFade = sqrt(1.0 - closestAlong / max(maxAlong, 0.01));

        // Ghost fade: track fades as it ages beyond visible range
        float ghostFade = smoothstep(3.0, 1.5, trackAge);
        ghostFade = max(ghostFade, smoothstep(0.0, 0.3, trackAge));

        float alpha = (0.35 + energy * 0.65) * posFade;
        float3 trailColor = sc_energyColor(energy);

        col += trailColor * glow * alpha;

        // Bright core for high-energy sections
        if (energy > 0.4) {
            float coreWidth = trailWidth * 0.3;
            float coreGlow = exp(-minDist * minDist / (coreWidth * coreWidth));
            col += float3(1.0, 0.96, 0.88) * coreGlow * (energy - 0.4) * 1.5 * posFade;
        }

        // Particle head glow (at the tip of the track)
        float2 headPos = sc_trackPoint(trackId, maxAlong, t);
        float headDist = length(p - headPos);
        float headRadius = (3.0 + energy * 6.0) / minRes;
        float headGlow = exp(-headDist * headDist / (headRadius * headRadius));
        if (energy > 0.7) {
            col += float3(1.0, 0.96, 0.86) * headGlow * 0.6;
        } else {
            col += float3(0.94, 0.78, 0.59) * headGlow * 0.4;
        }
    }

    // Decay flash approximation: bright spots at track bifurcation points
    for (int ti = 0; ti < numTracks; ti++) {
        float trackId = float(ti) + floor(t * 0.3) * SC_NUM_TRACKS;
        float decayAlong = 0.8 + sc_hash1(trackId + 10.0) * 0.5;
        float2 decayPos = sc_trackPoint(trackId, decayAlong, t);
        float decayDist = length(p - decayPos);

        float flashTime = fract(t * 0.3) * 3.0 + float(ti) * 0.15 - decayAlong / 0.5;
        float flashAlpha = smoothstep(0.0, 0.05, flashTime) * smoothstep(0.5, 0.1, flashTime);
        if (flashAlpha < 0.01) continue;

        float flashRadius = (8.0 + sc_trackEnergy(trackId, decayAlong) * 25.0) / minRes;
        float flashGlow = exp(-decayDist * decayDist / (flashRadius * flashRadius));
        col += float3(1.0, 0.94, 0.86) * flashGlow * flashAlpha * 0.5;
        col += float3(0.784, 0.584, 0.424) * flashGlow * flashAlpha * 0.2 *
               smoothstep(0.0, flashRadius * 0.5, decayDist);
    }

    // Film grain
    float grain = sc_hash(p * 200.0 + float2(t * 3.7, t * 2.3));
    col += float3(0.784, 0.706, 0.627) * smoothstep(0.97, 1.0, grain) * 0.03;

    // Vignette
    float vigDist = length(p) / length(float2(res.x, res.y) * 0.5 / minRes);
    float vig = 1.0 - smoothstep(0.3, 1.0, vigDist);
    col *= 0.35 + 0.65 * vig;

    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
