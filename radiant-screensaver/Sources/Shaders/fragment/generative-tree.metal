#include "../Common.metal"

// ─── Generative Tree: L-system branching tree via noise-driven SDF ───
// Ported from static/generative-tree.html
// Approach: Evaluate recursive branch structure analytically per-pixel
// using SDF line segments with noise-driven angles and lengths.

constant float GT_MAX_DEPTH = 10.0;
constant float GT_GROWTH_CYCLE = 12.0;     // seconds for full grow/hold/fade cycle
constant float GT_GROW_FRAC = 0.5;         // fraction of cycle spent growing
constant float GT_HOLD_FRAC = 0.3;         // fraction spent holding
constant float GT_TRUNK_LEN = 0.22;        // trunk length relative to height
constant float GT_TRUNK_THICK = 0.012;     // trunk thickness in UV
constant float GT_LEN_DECAY = 0.67;        // child length = parent * this
constant float GT_THICK_DECAY = 0.58;      // child thickness = parent * this
constant float GT_SWAY_AMP = 0.015;        // wind sway amplitude

// Hash for deterministic per-branch randomness
static float gt_hash2(float seed) {
    return fract(sin(seed * 127.1 + 311.7) * 43758.5453);
}

// SDF for a tapered line segment, returns (distance, closest_t)
static float2 gt_seg_sdf(float2 p, float2 a, float2 b, float thickA, float thickB) {
    float2 ba = b - a;
    float h = clamp(dot(p - a, ba) / dot(ba, ba), 0.0, 1.0);
    float d = length(p - a - ba * h);
    float thick = mix(thickA, thickB, h);
    return float2(d - thick, h);
}

// Recursive tree evaluation — iterative with fixed-depth loop
// Accumulates soft branch contribution for the current pixel
static float3 gt_eval_tree(float2 uv, float time, float treePhase, float treeSeed) {
    // Growth envelope: 0->1 during grow, 1 during hold, 1->0 during fade
    float cycleT = fract(treePhase);
    float growth;
    if (cycleT < GT_GROW_FRAC) {
        growth = cycleT / GT_GROW_FRAC;
        growth = 1.0 - pow(1.0 - growth, 3.0); // easeOutCubic
    } else if (cycleT < GT_GROW_FRAC + GT_HOLD_FRAC) {
        growth = 1.0;
    } else {
        float fadeT = (cycleT - GT_GROW_FRAC - GT_HOLD_FRAC) / (1.0 - GT_GROW_FRAC - GT_HOLD_FRAC);
        growth = 1.0 - fadeT;
    }

    if (growth < 0.001) return float3(0.0);

    // Color palette: deep sienna to golden tips
    // Encoded as array-like indexed colors
    float3 palette[6] = {
        float3(0.306, 0.176, 0.055),   // deep sienna
        float3(0.490, 0.298, 0.110),   // warm bark
        float3(0.675, 0.463, 0.196),   // rich amber
        float3(0.804, 0.620, 0.322),   // warm gold
        float3(0.855, 0.714, 0.424),   // golden
        float3(0.843, 0.765, 0.529)    // golden-cream
    };

    float3 accum = float3(0.0);
    float alpha = 0.0;

    // Tree root position
    float baseX = 0.5 + (gt_hash2(treeSeed * 7.3) - 0.5) * 0.06;
    float baseY = 1.02; // just below bottom

    // Trunk
    float trunkAngle = -1.5707963 + (gt_hash2(treeSeed * 3.1) - 0.5) * 0.1;

    // We iterate over branches using a stack-like approach
    // For fragment shader: evaluate a fixed set of branches deterministically
    // Each branch is identified by a path encoding (depth + child index)
    // We evaluate up to ~200 branches across the tree

    // Stack: start, angle, length, thickness, depth, seed, parentGrowthStart
    // We use a flat iteration with encoded branch IDs

    for (int pathCode = 0; pathCode < 250; pathCode++) {
        // Decode path: each branch at depth d has an index 0..2
        // pathCode encodes a full path from root
        float2 pos = float2(baseX, baseY);
        float angle = trunkAngle;
        float len = GT_TRUNK_LEN;
        float thick = GT_TRUNK_THICK;
        float seed = treeSeed;
        int code = pathCode;
        int depth = 0;
        bool valid = true;
        float branchGrowthStart = 0.0;

        // Decode path from root to leaf
        for (int d = 0; d < 10; d++) {
            if (d > 0) {
                int childIdx = code % 3;
                code /= 3;

                // Deterministic child count: 2-3 based on seed
                float childSeed = seed + float(d) * 13.7;
                int numChildren = gt_hash2(childSeed) < 0.35 ? 3 : 2;
                if (childIdx >= numChildren) { valid = false; break; }

                // Pruning at outer depths
                float pruneChance = d <= 3 ? 0.0 : (d <= 5 ? 0.1 : (d <= 7 ? 0.22 : 0.35));
                if (gt_hash2(childSeed + 77.0) < pruneChance && childIdx == numChildren - 1) {
                    valid = false; break;
                }

                // Compute child angle offset
                float spread = d < 2 ? 0.40 : 0.50;
                float angleOffset;
                if (numChildren == 2) {
                    angleOffset = (childIdx == 0 ? -1.0 : 1.0) * spread;
                } else {
                    angleOffset = (float(childIdx) - 1.0) * spread;
                }
                angleOffset += (gt_hash2(childSeed + float(childIdx) * 5.0) - 0.5) * 0.2;

                angle += angleOffset;
                len *= GT_LEN_DECAY + (gt_hash2(childSeed + 3.0) - 0.5) * 0.15;
                thick *= GT_THICK_DECAY + (gt_hash2(childSeed + 9.0) - 0.5) * 0.15;
                thick = max(thick, 0.001);
                seed = childSeed + float(childIdx) * 31.0;

                // Growth progression: deeper branches start growing later
                branchGrowthStart = float(d) * 0.06;
            }

            if (code == 0 && d > 0) { depth = d; break; }
            if (d == 0 && pathCode == 0) { depth = 0; break; }

            // Advance position along parent branch
            float sway = sin(time * 0.5 + seed * 1.7) * GT_SWAY_AMP * float(d + 1)
                       + sin(time * 0.3 + seed * 0.4) * GT_SWAY_AMP * 0.6 * float(d + 1);
            float curvedAngle = angle + sway;

            float2 dir = float2(cos(curvedAngle), sin(curvedAngle));
            float2 endPos = pos + dir * len;

            if (d == 0 && pathCode == 0) {
                // This is the trunk — evaluate it
                float depthGrowth = clamp((growth - branchGrowthStart) / (1.0 - branchGrowthStart), 0.0, 1.0);
                float2 grownEnd = mix(pos, endPos, depthGrowth);
                float2 sd = gt_seg_sdf(uv, pos, grownEnd, thick, thick * 0.5);

                if (sd.x < 0.008) {
                    float a = smoothstep(0.008, 0.0, sd.x);
                    float depthT = 0.0;
                    int pi = int(depthT * 5.0);
                    pi = min(pi, 4);
                    float pf = depthT * 5.0 - float(pi);
                    float3 branchCol = mix(palette[pi], palette[pi + 1], pf);
                    accum += branchCol * a * 0.95 * growth;
                    alpha = max(alpha, a * 0.95 * growth);
                }
                pos = endPos;
                depth = 0;
                continue;
            }

            pos = endPos;
        }

        if (!valid || pathCode == 0) continue;

        // Now evaluate this branch as an SDF segment
        float sway = sin(time * 0.5 + seed * 1.7) * GT_SWAY_AMP * float(depth + 1)
                   + sin(time * 0.3 + seed * 0.4) * GT_SWAY_AMP * 0.6 * float(depth + 1);
        float finalAngle = angle + sway;
        float2 dir = float2(cos(finalAngle), sin(finalAngle));

        float depthGrowth = clamp((growth - branchGrowthStart) / max(1.0 - branchGrowthStart, 0.01), 0.0, 1.0);
        float grownLen = len * depthGrowth;
        float2 endPos = pos + dir * grownLen;

        float thickEnd = thick * 0.35;
        float2 sd = gt_seg_sdf(uv, pos, endPos, thick, thickEnd);

        // Skip if far away
        if (sd.x > 0.015) continue;

        float a = smoothstep(0.008, -0.001, sd.x);

        // Color from depth
        float depthT = clamp(float(depth) / GT_MAX_DEPTH, 0.0, 1.0);
        float idx = depthT * 5.0;
        int pi = int(idx);
        pi = min(pi, 4);
        float pf = idx - float(pi);
        float3 branchCol = mix(palette[pi], palette[pi + 1], pf);

        // Alpha falloff at outer depths
        float depthAlpha = depth <= 1 ? 0.95 :
                          (depth <= 5 ? mix(0.92, 0.7, depthT) :
                                        mix(0.7, 0.35, (depthT - 0.5) * 2.0));

        float contrib = a * depthAlpha * growth;
        accum += branchCol * contrib;
        alpha = max(alpha, contrib);

        // Tip glow at terminal branches (depth >= 9)
        if (depth >= 9 && depthGrowth > 0.9) {
            float tipFade = smoothstep(0.9, 1.0, depthGrowth);
            float tipDist = length(uv - endPos);
            float tipGlow = smoothstep(0.012, 0.0, tipDist) * tipFade * 0.3;
            float3 tipCol = branchCol * 1.3 + float3(0.12, 0.10, 0.08);
            accum += tipCol * tipGlow * growth;
        }
    }

    return float3(accum);
}

fragment float4 fs_generative_tree(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    // Aspect-correct: map to 0..1 range, y=0 at top, y=1 at bottom
    float aspect = u.resolution.x / u.resolution.y;
    float2 treeUV = float2((uv.x - 0.5) * aspect + 0.5, uv.y);

    float t = u.time;

    // Cycle through different trees
    float treePhase = t / GT_GROWTH_CYCLE;
    float treeSeed = floor(treePhase) * 17.31;

    // Canopy glow (warm halo behind tree crown)
    float2 canopyCenter = float2(0.5, 0.38);
    float canopyDist = length(treeUV - canopyCenter);
    float canopyGlow = smoothstep(0.42, 0.0, canopyDist);
    float3 col = float3(0.039, 0.039, 0.039); // #0a0a0a
    col += float3(0.235, 0.141, 0.047) * canopyGlow * 0.2;

    // Ground glow
    float groundGlow = smoothstep(0.3, 0.0, abs(treeUV.y - 1.0)) * smoothstep(0.4, 0.0, abs(treeUV.x - 0.5));
    col += float3(0.275, 0.165, 0.047) * groundGlow * 0.1;

    // Tree
    float3 tree = gt_eval_tree(treeUV, t, treePhase, treeSeed);
    col += tree;

    // Floating particles (noise-based approximation)
    for (int i = 0; i < 20; i++) {
        float fi = float(i);
        float px = 0.15 + gt_hash2(fi * 7.1) * 0.7;
        float py = fract(0.9 - t * (0.0006 + gt_hash2(fi * 3.3) * 0.002) + gt_hash2(fi * 11.0));
        px += sin(t * (0.0004 + gt_hash2(fi * 5.5) * 0.001) + fi * 2.0) * 0.04;
        float2 ppos = float2(px, py);
        float pdist = length(treeUV - ppos);
        float psize = 0.002 + gt_hash2(fi * 13.0) * 0.004;
        float palpha = smoothstep(psize, psize * 0.2, pdist) * (0.04 + gt_hash2(fi * 9.0) * 0.16);
        col += float3(0.902, 0.784, 0.608) * palpha;
    }

    // Vignette
    float2 vc = (uv - 0.5) * 2.0;
    float vig = 1.0 - smoothstep(0.6, 1.56, length(vc));
    col *= 0.7 + 0.3 * vig;

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
