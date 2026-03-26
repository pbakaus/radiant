#include "../Common.metal"

// ─── Ink Calligraphy: Abstract ink strokes with diffusion on paper texture ───
// Ported from static/ink-calligraphy.html
// Approach: Noise-driven procedural brush strokes as thick curved SDFs on
// a noise-generated paper background, with gold leaf edge highlights.

constant float IC_STROKE_CYCLE = 4.0;      // seconds per stroke lifecycle
constant float IC_OVERLAP = 1.3;           // seconds of overlap between strokes
constant float IC_INK_DENSITY = 0.85;      // ink opacity
constant float IC_GOLD_AMOUNT = 0.6;       // gold leaf intensity
constant float IC_DIFFUSION = 0.008;       // ink bleed radius
constant float IC_PAPER_SCALE = 3.0;       // paper texture frequency

// Hash
static float ic_hash(float s) {
    return fract(sin(s * 127.1 + 311.7) * 43758.5453);
}

// Evaluate a single brush stroke at given UV, returns (ink_amount, distance_to_stroke)
static float2 ic_eval_stroke(float2 uv, float strokeIdx, float time, float aspect) {
    float seed = strokeIdx * 73.1 + floor(time / IC_STROKE_CYCLE + strokeIdx * 0.37) * 17.0;

    // Stroke timing
    float strokeStart = floor(time / IC_STROKE_CYCLE + strokeIdx * 0.37) * IC_STROKE_CYCLE
                       - strokeIdx * IC_OVERLAP;
    float age = time - strokeStart;
    float lifespan = IC_STROKE_CYCLE;

    // Normalized age 0..1
    float t = clamp(age / lifespan, 0.0, 1.0);
    if (t <= 0.0 || t >= 1.0) return float2(0.0, 99.0);

    // Stroke path: start position and direction from noise
    float2 startPos = float2(
        0.1 + ic_hash(seed) * 0.8,
        0.1 + ic_hash(seed + 1.0) * 0.8
    );
    float startAngle = ic_hash(seed + 2.0) * 6.28318;

    // Stroke width: hairline/medium/bold variety
    float strokeType = ic_hash(seed + 3.0);
    float maxWidth;
    if (strokeType < 0.4) maxWidth = 0.004 + ic_hash(seed + 4.0) * 0.008;      // hairline
    else if (strokeType < 0.8) maxWidth = 0.012 + ic_hash(seed + 4.0) * 0.020;  // medium
    else maxWidth = 0.030 + ic_hash(seed + 4.0) * 0.035;                         // bold

    // Stroke length
    float strokeLen = 0.2 + ic_hash(seed + 5.0) * 0.4;

    // Width envelope: thin-thick-thin calligraphy
    float wEnv;
    if (t < 0.15) wEnv = t / 0.15;
    else if (t > 0.7) wEnv = (1.0 - t) / 0.3;
    else wEnv = 1.0;
    wEnv = sqrt(wEnv); // organic ease

    // Evaluate stroke as a sequence of sample points
    // The brush traces a curved path driven by noise
    float minDist = 99.0;
    float bestT = 0.0;

    // How far along the stroke we've drawn (progressive reveal)
    float drawProgress = t;

    float2 prevPos = startPos;
    float angle = startAngle;
    float curveAmt = (ic_hash(seed + 6.0) - 0.5) * 0.008;

    // Number of segments to evaluate
    int numSegs = 24;
    float segLen = strokeLen / float(numSegs);

    for (int i = 0; i <= numSegs; i++) {
        float segT = float(i) / float(numSegs);
        if (segT > drawProgress) break;

        // Noise-driven steering
        float n1 = snoise(prevPos * 3.0 + float2(seed, time * 0.06));
        float n2 = snoise(prevPos * 7.0 + float2(seed + 50.0, time * 0.04));
        float curveFade = segT > 0.7 ? (1.0 - segT) / 0.3 : 1.0;
        angle += (n1 * 0.009 + n2 * 0.006 + curveAmt * curveFade) * 3.0;

        // Recompute position by integrating from start
        float a2 = startAngle;
        float2 pos = startPos;
        for (int j = 0; j < i; j++) {
            float jt = float(j) / float(numSegs);
            float jn1 = snoise(pos * 3.0 + float2(seed, time * 0.06));
            float jn2 = snoise(pos * 7.0 + float2(seed + 50.0, time * 0.04));
            float jcf = jt > 0.7 ? (1.0 - jt) / 0.3 : 1.0;
            a2 += (jn1 * 0.009 + jn2 * 0.006 + curveAmt * jcf) * 3.0;

            float sEnv = jt < 0.03 ? jt / 0.03 : (jt > 0.85 ? (1.0 - jt) / 0.15 : 1.0);
            pos += float2(cos(a2), sin(a2)) * segLen * sEnv;
        }

        // Width at this segment
        float localWEnv;
        if (segT < 0.15) localWEnv = segT / 0.15;
        else if (segT > 0.7) localWEnv = (1.0 - segT) / 0.3;
        else localWEnv = 1.0;
        localWEnv = sqrt(localWEnv);
        // Distance from this pixel to this point
        float2 diff = uv - pos;
        diff.x *= aspect;
        float d = length(diff);

        if (d < minDist) {
            minDist = d;
            bestT = segT;
        }
    }

    // Ink falloff
    float wAtBest;
    if (bestT < 0.15) wAtBest = bestT / 0.15;
    else if (bestT > 0.7) wAtBest = (1.0 - bestT) / 0.3;
    else wAtBest = 1.0;
    wAtBest = sqrt(wAtBest) * maxWidth;

    float ink = smoothstep(wAtBest + IC_DIFFUSION, wAtBest * 0.3, minDist);

    // Alpha envelope for entry/exit
    float alphaEnv = t < 0.02 ? t / 0.02 : (t > 0.94 ? (1.0 - t) / 0.06 : 1.0);
    ink *= alphaEnv * IC_INK_DENSITY;

    return float2(ink, minDist);
}

fragment float4 fs_ink_calligraphy(VSOut in [[stage_in]],
                                    constant CommonUniforms& u [[buffer(0)]]) {
    float2 uv = in.pos.xy / u.resolution;
    float2 centered = (in.pos.xy - u.resolution * 0.5) / min(u.resolution.x, u.resolution.y);
    float aspect = u.resolution.x / u.resolution.y;
    float t = u.time;

    // ── Paper texture (warm cream) ──
    float2 paperCoord = uv * IC_PAPER_SCALE;
    float warp = snoise(paperCoord * 3.0) * 0.5 + 0.5;
    float fiber = snoise(float2(uv.x * 12.0, uv.y * 1.2)) * 0.4
                + snoise(float2(uv.x * 3.5, uv.y * 10.0)) * 0.35
                + snoise(float2(uv.x * 0.6, uv.y * 6.0)) * 0.25;
    float grain = (ic_hash(dot(floor(in.pos.xy), float2(12.9898, 78.233))) - 0.5) * 0.024;

    float3 paper = float3(
        0.910 + warp * 0.031 + fiber * 0.039 + grain,
        0.878 + warp * 0.016 + fiber * 0.035 + grain,
        0.816 - warp * 0.016 + fiber * 0.027 + grain
    );

    // Subtle age spots
    float ageSpot = snoise(uv * 1.5 + 10.0);
    if (ageSpot > 0.2) {
        float a = (ageSpot - 0.2) * 5.0;
        paper.r += a * 0.004;
        paper.g += a * 0.002;
        paper.b -= a * 0.006;
    }

    // ── Evaluate ink strokes ──
    float totalInk = 0.0;
    float closestDist = 99.0;

    for (int i = 0; i < 5; i++) {
        float2 strokeResult = ic_eval_stroke(uv, float(i), t, aspect);
        totalInk = max(totalInk, strokeResult.x);
        closestDist = min(closestDist, strokeResult.y);
    }

    totalInk = clamp(totalInk, 0.0, 0.92);

    // ── Ink color (warm black) ──
    float inkShift = snoise(uv * 20.0) * 0.08;
    float3 inkColor = float3(
        0.071 + inkShift * 0.047,
        0.055 + inkShift * 0.039,
        0.047 + inkShift * 0.031
    );

    // ── Ink wash — faint ambient ink clouds ──
    float wash = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        float2 washPos = float2(
            0.5 + sin(t * 0.05 + fi * 2.1) * 0.3,
            0.5 + cos(t * 0.035 + fi * 1.7) * 0.3
        );
        float washDist = length(centered - (washPos - 0.5));
        float washR = 0.3 + 0.1 * sin(t * 0.02 + fi);
        wash += smoothstep(washR, 0.0, washDist) * 0.003;
    }

    // ── Compose: paper + ink ──
    float3 col = mix(paper, inkColor, totalInk);

    // Ink bleed halo on thicker strokes
    float bleed = smoothstep(0.04, 0.005, closestDist) * 0.03;
    col = mix(col, inkColor, bleed);

    // Ink wash tint
    col -= float3(0.02, 0.02, 0.015) * wash;

    // ── Gold leaf along stroke edges ──
    float edgeZone = totalInk * (1.0 - totalInk) * 4.0;
    float goldEdge = smoothstep(0.2, 0.8, edgeZone);

    // Shimmer
    float shimmer = sin(uv.x * 80.0 + uv.y * 60.0 + t * 2.8) * 0.5 + 0.5;
    shimmer = shimmer * shimmer * shimmer;

    float goldAlpha = goldEdge * (0.25 + shimmer * 0.7) * IC_GOLD_AMOUNT;
    float3 goldColor = float3(
        0.784 + shimmer * 0.216,
        0.585 + shimmer * 0.255,
        0.424 + shimmer * 0.086
    );
    float3 goldHighlight = float3(1.0, 0.941, 0.706);

    col = mix(col, goldColor, goldAlpha * 0.5);
    if (shimmer > 0.5) {
        float hotGold = (shimmer - 0.5) * 2.0 * goldAlpha;
        col += goldHighlight * hotGold * 0.15;
    }

    // ── Vignette ──
    float vigDist = length(centered);
    float vig = smoothstep(0.5, 1.0, vigDist);
    col *= 1.0 - vig * 0.12;

    col = clamp(col, 0.0, 1.0);
    col = hue_rotate(col, u.hue_shift);
    return float4(col, 1.0);
}
