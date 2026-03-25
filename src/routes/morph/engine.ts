/**
 * MorphEngine v3 — Single uber-shader, all morphing on the GPU.
 * One draw call per frame. ~30 interpolated uniforms. No FBOs.
 *
 * Perf-critical changes from v2:
 * - Simplex noise only (no dual-noise blend)
 * - Max 4 FBM octaves (not 6)
 * - Analytic normals from warp gradient (no finite-difference re-evaluation)
 * - Fabric fold warp uses cheap 2-octave FBM
 */

const VERT_SRC = `
attribute vec2 a_pos;
void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }
`;

const MAX_FBM_OCTAVES = 4;
const MAX_ORBS = 7;

const FRAG_SRC = `
precision highp float;

uniform float u_time;
uniform vec2  u_res;
uniform vec2  u_mouse;
uniform float u_zoom;
uniform vec2  u_zoomCenter;
uniform float u_hueShift;

uniform float u_fbmOctaves;
uniform float u_fbmDecay;
uniform float u_fbmFreqMul;

uniform float u_warpScale;
uniform float u_warp1Str;
uniform float u_warp2Str;

uniform float u_orbCount;
uniform float u_orbRadius;
uniform float u_orbIntensity;
uniform float u_orbColorMode;

uniform float u_foldStr;
uniform float u_foldFreq;

uniform float u_normalStr;
uniform float u_diffuseStr;
uniform float u_specStr;
uniform float u_specPower;
uniform float u_fresnelF0;

uniform float u_edgeGlowStr;

uniform vec3  u_colorShadow;
uniform vec3  u_colorMid;
uniform vec3  u_colorBright;
uniform vec3  u_colorHot;

uniform float u_vignetteStr;
uniform float u_grainStr;

// ─── Simplex noise (Ashima, single implementation) ───
vec3 mod289(vec3 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
vec2 mod289v2(vec2 x) { return x - floor(x * (1.0/289.0)) * 289.0; }
vec3 permute(vec3 x) { return mod289((x*34.0+1.0)*x); }

float snoise(vec2 v) {
  const vec4 C = vec4(0.211324865405187, 0.366025403784439,
                      -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0,0.0) : vec2(0.0,1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod289v2(i);
  vec3 p = permute(permute(i.y + vec3(0.0,i1.y,1.0)) + i.x + vec3(0.0,i1.x,1.0));
  vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
  m = m*m; m = m*m;
  vec3 x = 2.0*fract(p*C.www)-1.0;
  vec3 h = abs(x)-0.5;
  vec3 ox = floor(x+0.5);
  vec3 a0 = x-ox;
  m *= 1.79284291400159-0.85373472095314*(a0*a0+h*h);
  vec3 g;
  g.x = a0.x*x0.x+h.x*x0.y;
  g.yz = a0.yz*x12.xz+h.yz*x12.yw;
  return 130.0*dot(m,g);
}

// ─── FBM (max 4 octaves, rotated) ───
float fbm(vec2 p, float t) {
  float val = 0.0, amp = 0.5;
  mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
  for (int i = 0; i < ${MAX_FBM_OCTAVES}; i++) {
    if (float(i) >= u_fbmOctaves) break;
    val += amp * snoise(p + t * 0.15);
    p = rot * p * u_fbmFreqMul;
    amp *= u_fbmDecay;
  }
  return val;
}

float fbm2(vec2 p, float t) {
  mat2 rot = mat2(0.8, 0.6, -0.6, 0.8);
  float v = 0.5 * snoise(p + t * 0.15);
  p = rot * p * 2.0;
  return v + 0.25 * snoise(p + t * 0.15);
}

// ─── Domain-warped field ───
// Returns field value. q and r are out params for color mixing.
// Also accumulates an approximate gradient in gAccum for normals.
vec2 gAccum;

float warpedField(vec2 p, float t, out vec2 q, out vec2 r) {
  gAccum = vec2(0.0);

  q = vec2(
    fbm(p, t),
    fbm(p + vec2(5.2, 1.3), t)
  );

  vec2 wp1 = p + u_warp1Str * q;
  r = vec2(
    fbm(wp1 + vec2(1.7, 9.2), t * 1.1),
    fbm(wp1 + vec2(8.3, 2.8), t * 1.1)
  );

  float f = fbm(p + u_warp2Str * r, t * 0.8);

  // Approximate gradient from warp vectors (avoids finite differences)
  gAccum = u_warp1Str * q + u_warp2Str * r;

  return f;
}

// ─── Orb field ───
vec3 getOrbColor(int i) {
  if (i==0) return vec3(0.03,0.10,1.00);
  if (i==1) return vec3(1.00,0.42,0.03);
  if (i==2) return vec3(0.85,0.93,1.00);
  if (i==3) return vec3(1.00,0.70,0.08);
  if (i==4) return vec3(0.03,0.65,0.65);
  if (i==5) return vec3(0.25,0.15,0.50);
  return vec3(0.55,0.25,0.30);
}

void computeOrbs(vec2 p, float t, out float field, out vec3 color) {
  field = 0.0;
  color = vec3(0.0);
  int count = int(u_orbCount + 0.5);
  float rr = max(u_orbRadius * u_orbRadius, 0.001);
  for (int i = 0; i < ${MAX_ORBS}; i++) {
    if (i >= count) break;
    float fi = float(i);
    vec2 center = vec2(
      sin(t*(0.17+fi*0.02)+fi*2.1)*0.5 + cos(t*(0.13+fi*0.015)+fi*1.3)*0.25,
      cos(t*(0.15+fi*0.018)+fi*1.7)*0.4 + sin(t*(0.11+fi*0.022)+fi*2.5)*0.2
    );
    float d = length(p - center);
    float glow = exp(-d*d/rr) * u_orbIntensity;
    field += glow;
    color += getOrbColor(i) * glow;
  }
}

// ─── Fabric fold ───
vec3 fabricFold(vec2 p, float t) {
  float ts = t * 0.75;
  // Cheap warp (2-octave FBM)
  vec2 warp = vec2(
    fbm2(p * 1.2 + vec2(1.7, 9.2) + ts * 0.15, ts),
    fbm2(p * 1.2 + vec2(8.3, 2.8) - ts * 0.12, ts)
  );
  vec2 wp = p + warp * 0.55;
  float freq = u_foldFreq;
  float h = 0.0;
  vec2 g = vec2(0.0);

  float f1x=freq*0.7, f1y=freq*0.4;
  float ph1=wp.x*f1x+wp.y*f1y+ts*0.3;
  h+=sin(ph1)*0.35; g+=cos(ph1)*0.35*vec2(f1x,f1y);

  float f2x=-freq*0.3, f2y=freq*0.9;
  float ph2=wp.x*f2x+wp.y*f2y+ts*0.25+1.3;
  h+=sin(ph2)*0.25; g+=cos(ph2)*0.25*vec2(f2x,f2y);

  float f3=freq*0.6;
  float ph3=(wp.x+wp.y)*f3+ts*0.2+4.5;
  h+=sin(ph3)*0.18; g+=cos(ph3)*0.18*vec2(f3);

  float f4x=freq*1.8, f4y=freq*1.2;
  float ph4=wp.x*f4x+wp.y*f4y-ts*0.35+0.7;
  h+=sin(ph4)*0.08; g+=cos(ph4)*0.08*vec2(f4x,f4y);

  return vec3(h, g);
}

// ─── Hue rotation ───
vec3 hueRotate(vec3 c, float a) {
  float ca=cos(a), sa=sin(a);
  vec3 k=vec3(0.57735);
  return c*ca + cross(k,c)*sa + k*dot(k,c)*(1.0-ca);
}

// ============================================================
void main() {
  vec2 rawUV = gl_FragCoord.xy / u_res;
  vec2 uv = (rawUV - u_zoomCenter) / u_zoom + u_zoomCenter;
  vec2 p = (uv - 0.5) * vec2(u_res.x / u_res.y, 1.0);
  float t = u_time;

  // Mouse swirl
  if (u_mouse.x > 0.0) {
    vec2 mN = (u_mouse - u_res*0.5) / min(u_res.x, u_res.y);
    vec2 diff = p - mN;
    float d = length(diff);
    float angle = exp(-d*d*8.0) * 1.5;
    float ca=cos(angle), sa=sin(angle);
    p = mN + mat2(ca,-sa,sa,ca) * diff;
  }

  // ── Noise field + domain warp ──
  vec2 q = vec2(0.0), r = vec2(0.0);
  float field = 0.0;
  if (u_fbmOctaves > 0.5) {
    field = warpedField(p * u_warpScale, t, q, r);
  }

  // ── Orbs ──
  float orbField = 0.0;
  vec3 orbColor = vec3(0.0);
  if (u_orbCount > 0.5) {
    computeOrbs(p, t, orbField, orbColor);
  }

  // ── Combine ──
  float envelope = mix(
    mix(1.0, clamp(orbField, 0.0, 1.0), step(0.5, u_orbCount) * (1.0 - u_orbColorMode)),
    1.0, u_orbColorMode
  );
  float height = field * envelope + orbField * (1.0 - u_orbColorMode) * 0.08;

  // ── Fabric fold ──
  vec2 foldGrad = vec2(0.0);
  if (u_foldStr > 0.001) {
    vec3 fold = fabricFold(p, t);
    height = mix(height, fold.x, u_foldStr);
    foldGrad = fold.yz * u_foldStr;
  }

  // ── Normal (analytic from warp gradient + fold gradient, NO finite differences) ──
  vec3 N = vec3(0.0, 0.0, 1.0);
  if (u_normalStr > 0.001) {
    // Combine warp gradient and fold gradient
    vec2 grad = gAccum * 0.3 + foldGrad * 1.8;
    vec3 analyticN = normalize(vec3(-grad, 1.0));
    N = normalize(mix(vec3(0.0,0.0,1.0), analyticN, u_normalStr));
  }

  // ── Color palette ──
  float fn = smoothstep(-0.5, 1.2, field);
  vec3 baseColor = mix(u_colorShadow, u_colorMid, smoothstep(0.0, 0.35, fn));
  baseColor = mix(baseColor, u_colorBright, smoothstep(0.3, 0.65, fn));
  baseColor = mix(baseColor, u_colorHot, smoothstep(0.6, 0.95, fn));
  baseColor = mix(baseColor, u_colorBright, clamp(length(q)*0.4, 0.0, 0.5));
  baseColor = mix(baseColor, u_colorHot, clamp(length(r)*0.3, 0.0, 0.3));

  vec3 col = baseColor;

  // ── Lighting ──
  if (u_diffuseStr > 0.001 || u_specStr > 0.001) {
    vec3 V = vec3(0.0,0.0,1.0);
    vec3 L1 = normalize(vec3(0.4, 0.5, 0.9));
    vec3 L2 = normalize(vec3(-0.6, -0.3, 0.7));
    float lit = max(dot(N,L1),0.0)*0.7 + max(dot(N,L2),0.0)*0.3;
    vec3 diffuse = baseColor * lit;

    float spec = 0.0;
    if (u_specStr > 0.001) {
      vec3 H1 = normalize(L1+V);
      float blinn = pow(max(dot(N,H1),0.0), u_specPower);
      float aniso = 0.0;
      float gl2 = dot(foldGrad,foldGrad);
      if (gl2 > 0.0001) {
        vec2 tg = vec2(-foldGrad.y, foldGrad.x) / sqrt(gl2);
        float TdH = dot(normalize(vec3(tg,0.0)), H1);
        aniso = pow(sqrt(max(1.0-TdH*TdH,0.0)), u_specPower);
      }
      spec = mix(blinn, aniso, smoothstep(0.3, 0.7, u_specStr));
    }

    float NdV = max(dot(N,V), 0.0);
    float fres = u_fresnelF0 + (1.0-u_fresnelF0)*pow(1.0-NdV, 5.0);
    float frMix = mix(1.0, fres, step(0.001, u_fresnelF0));

    col = mix(col, diffuse, u_diffuseStr);
    col += u_colorHot * spec * u_specStr * frMix * 0.8;

    if (u_fresnelF0 > 0.001) {
      vec2 reflUV = N.xy*0.5+0.5;
      col += mix(u_colorShadow, u_colorBright, reflUV.y) * fres * 0.3;
    }
  }

  // ── Additive orb color ──
  col = mix(col, orbColor, u_orbColorMode);

  // ── Edge glow ──
  if (u_edgeGlowStr > 0.001) {
    float ink = smoothstep(-0.2, 0.1, field) * envelope;
    float edgeRaw = ink*(1.0-ink)*4.0;
    col += u_colorBright * smoothstep(0.05,0.5,edgeRaw) * 0.5 * u_edgeGlowStr;
    col += u_colorHot * smoothstep(0.6,1.0,edgeRaw) * 0.4 * u_edgeGlowStr;
  }

  // ── Post ──
  float vig = length(p * vec2(0.85,1.0));
  col *= 1.0 - smoothstep(0.3, 1.2, vig) * u_vignetteStr;
  col = clamp(col, vec3(0.0), vec3(4.0));
  col = col*(2.51*col+0.03)/(col*(2.43*col+0.59)+0.14);

  if (u_grainStr > 0.001) {
    float grain = fract(sin(dot(gl_FragCoord.xy+fract(u_time*7.13)*100.0, vec2(12.9898,78.233)))*43758.5453)-0.5;
    col += grain * u_grainStr;
  }

  if (abs(u_hueShift) > 0.001) {
    col = hueRotate(col, u_hueShift);
  }

  gl_FragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
`;

// ─── Uniform mapping ───
const PARAM_TO_UNIFORM: Record<string, string> = {
	noiseBlend: '', // removed, simplex only now
	fbmOctaves: 'u_fbmOctaves',
	fbmDecay: 'u_fbmDecay',
	fbmFreqMul: 'u_fbmFreqMul',
	warpScale: 'u_warpScale',
	warp1Str: 'u_warp1Str',
	warp2Str: 'u_warp2Str',
	orbCount: 'u_orbCount',
	orbRadius: 'u_orbRadius',
	orbIntensity: 'u_orbIntensity',
	orbColorMode: 'u_orbColorMode',
	foldStr: 'u_foldStr',
	foldFreq: 'u_foldFreq',
	normalStr: 'u_normalStr',
	diffuseStr: 'u_diffuseStr',
	specStr: 'u_specStr',
	specPower: 'u_specPower',
	fresnelF0: 'u_fresnelF0',
	edgeGlowStr: 'u_edgeGlowStr',
	colorShadow: 'u_colorShadow',
	colorMid: 'u_colorMid',
	colorBright: 'u_colorBright',
	colorHot: 'u_colorHot',
	vignetteStr: 'u_vignetteStr',
	grainStr: 'u_grainStr'
};

const ALL_UNIFORMS = [
	'u_time', 'u_res', 'u_mouse', 'u_zoom', 'u_zoomCenter', 'u_hueShift',
	'u_fbmOctaves', 'u_fbmDecay', 'u_fbmFreqMul',
	'u_warpScale', 'u_warp1Str', 'u_warp2Str',
	'u_orbCount', 'u_orbRadius', 'u_orbIntensity', 'u_orbColorMode',
	'u_foldStr', 'u_foldFreq',
	'u_normalStr', 'u_diffuseStr', 'u_specStr', 'u_specPower', 'u_fresnelF0',
	'u_edgeGlowStr',
	'u_colorShadow', 'u_colorMid', 'u_colorBright', 'u_colorHot',
	'u_vignetteStr', 'u_grainStr'
];

export class MorphEngine {
	private gl: WebGLRenderingContext;
	private program: WebGLProgram;
	private width = 0;
	private height = 0;

	// Pre-cached uniform locations — no Map lookups, no iteration in hot path
	private uTime: WebGLUniformLocation | null = null;
	private uRes: WebGLUniformLocation | null = null;
	private uMouse: WebGLUniformLocation | null = null;
	private uZoom: WebGLUniformLocation | null = null;
	private uZoomCenter: WebGLUniformLocation | null = null;
	private uHueShift: WebGLUniformLocation | null = null;
	private uFbmOctaves: WebGLUniformLocation | null = null;
	private uFbmDecay: WebGLUniformLocation | null = null;
	private uFbmFreqMul: WebGLUniformLocation | null = null;
	private uWarpScale: WebGLUniformLocation | null = null;
	private uWarp1Str: WebGLUniformLocation | null = null;
	private uWarp2Str: WebGLUniformLocation | null = null;
	private uOrbCount: WebGLUniformLocation | null = null;
	private uOrbRadius: WebGLUniformLocation | null = null;
	private uOrbIntensity: WebGLUniformLocation | null = null;
	private uOrbColorMode: WebGLUniformLocation | null = null;
	private uFoldStr: WebGLUniformLocation | null = null;
	private uFoldFreq: WebGLUniformLocation | null = null;
	private uNormalStr: WebGLUniformLocation | null = null;
	private uDiffuseStr: WebGLUniformLocation | null = null;
	private uSpecStr: WebGLUniformLocation | null = null;
	private uSpecPower: WebGLUniformLocation | null = null;
	private uFresnelF0: WebGLUniformLocation | null = null;
	private uEdgeGlowStr: WebGLUniformLocation | null = null;
	private uColorShadow: WebGLUniformLocation | null = null;
	private uColorMid: WebGLUniformLocation | null = null;
	private uColorBright: WebGLUniformLocation | null = null;
	private uColorHot: WebGLUniformLocation | null = null;
	private uVignetteStr: WebGLUniformLocation | null = null;
	private uGrainStr: WebGLUniformLocation | null = null;

	constructor(canvas: HTMLCanvasElement) {
		const gl = canvas.getContext('webgl', { alpha: false, antialias: false, preserveDrawingBuffer: true })!;
		if (!gl) throw new Error('WebGL not available');
		this.gl = gl;

		const buf = gl.createBuffer()!;
		gl.bindBuffer(gl.ARRAY_BUFFER, buf);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 3,-1, -1,3]), gl.STATIC_DRAW);

		const vs = this.compile(gl.VERTEX_SHADER, VERT_SRC);
		const fs = this.compile(gl.FRAGMENT_SHADER, FRAG_SRC);
		this.program = gl.createProgram()!;
		gl.attachShader(this.program, vs);
		gl.attachShader(this.program, fs);
		gl.linkProgram(this.program);
		if (!gl.getProgramParameter(this.program, gl.LINK_STATUS)) {
			console.error('Link:', gl.getProgramInfoLog(this.program));
		}
		gl.useProgram(this.program);

		const aPos = gl.getAttribLocation(this.program, 'a_pos');
		gl.enableVertexAttribArray(aPos);
		gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

		// Cache every uniform location once
		const u = (n: string) => gl.getUniformLocation(this.program, n);
		this.uTime = u('u_time');
		this.uRes = u('u_res');
		this.uMouse = u('u_mouse');
		this.uZoom = u('u_zoom');
		this.uZoomCenter = u('u_zoomCenter');
		this.uHueShift = u('u_hueShift');
		this.uFbmOctaves = u('u_fbmOctaves');
		this.uFbmDecay = u('u_fbmDecay');
		this.uFbmFreqMul = u('u_fbmFreqMul');
		this.uWarpScale = u('u_warpScale');
		this.uWarp1Str = u('u_warp1Str');
		this.uWarp2Str = u('u_warp2Str');
		this.uOrbCount = u('u_orbCount');
		this.uOrbRadius = u('u_orbRadius');
		this.uOrbIntensity = u('u_orbIntensity');
		this.uOrbColorMode = u('u_orbColorMode');
		this.uFoldStr = u('u_foldStr');
		this.uFoldFreq = u('u_foldFreq');
		this.uNormalStr = u('u_normalStr');
		this.uDiffuseStr = u('u_diffuseStr');
		this.uSpecStr = u('u_specStr');
		this.uSpecPower = u('u_specPower');
		this.uFresnelF0 = u('u_fresnelF0');
		this.uEdgeGlowStr = u('u_edgeGlowStr');
		this.uColorShadow = u('u_colorShadow');
		this.uColorMid = u('u_colorMid');
		this.uColorBright = u('u_colorBright');
		this.uColorHot = u('u_colorHot');
		this.uVignetteStr = u('u_vignetteStr');
		this.uGrainStr = u('u_grainStr');
	}

	private compile(type: number, src: string): WebGLShader {
		const gl = this.gl;
		const s = gl.createShader(type)!;
		gl.shaderSource(s, src);
		gl.compileShader(s);
		if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
			console.error('GLSL:', gl.getShaderInfoLog(s));
		}
		return s;
	}

	resize(w: number, h: number) { this.width = w; this.height = h; }

	/** Zero-allocation render. All params read directly by key, no iteration. */
	render(
		p: Record<string, number | [number, number, number]>,
		time: number,
		mouse: [number, number],
		zoom: number,
		zoomCenter: [number, number],
		hueShift: number
	) {
		const gl = this.gl;
		gl.viewport(0, 0, this.width, this.height);

		// Per-frame uniforms
		gl.uniform1f(this.uTime, time);
		gl.uniform2f(this.uRes, this.width, this.height);
		gl.uniform2f(this.uMouse, mouse[0], mouse[1]);
		gl.uniform1f(this.uZoom, zoom);
		gl.uniform2f(this.uZoomCenter, zoomCenter[0], zoomCenter[1]);
		gl.uniform1f(this.uHueShift, hueShift);

		// Preset params — direct property access, no iteration
		gl.uniform1f(this.uFbmOctaves, p.fbmOctaves as number);
		gl.uniform1f(this.uFbmDecay, p.fbmDecay as number);
		gl.uniform1f(this.uFbmFreqMul, p.fbmFreqMul as number);
		gl.uniform1f(this.uWarpScale, p.warpScale as number);
		gl.uniform1f(this.uWarp1Str, p.warp1Str as number);
		gl.uniform1f(this.uWarp2Str, p.warp2Str as number);
		gl.uniform1f(this.uOrbCount, p.orbCount as number);
		gl.uniform1f(this.uOrbRadius, p.orbRadius as number);
		gl.uniform1f(this.uOrbIntensity, p.orbIntensity as number);
		gl.uniform1f(this.uOrbColorMode, p.orbColorMode as number);
		gl.uniform1f(this.uFoldStr, p.foldStr as number);
		gl.uniform1f(this.uFoldFreq, p.foldFreq as number);
		gl.uniform1f(this.uNormalStr, p.normalStr as number);
		gl.uniform1f(this.uDiffuseStr, p.diffuseStr as number);
		gl.uniform1f(this.uSpecStr, p.specStr as number);
		gl.uniform1f(this.uSpecPower, p.specPower as number);
		gl.uniform1f(this.uFresnelF0, p.fresnelF0 as number);
		gl.uniform1f(this.uEdgeGlowStr, p.edgeGlowStr as number);
		gl.uniform1f(this.uVignetteStr, p.vignetteStr as number);
		gl.uniform1f(this.uGrainStr, p.grainStr as number);

		const cs = p.colorShadow as [number, number, number];
		const cm = p.colorMid as [number, number, number];
		const cb = p.colorBright as [number, number, number];
		const ch = p.colorHot as [number, number, number];
		gl.uniform3f(this.uColorShadow, cs[0], cs[1], cs[2]);
		gl.uniform3f(this.uColorMid, cm[0], cm[1], cm[2]);
		gl.uniform3f(this.uColorBright, cb[0], cb[1], cb[2]);
		gl.uniform3f(this.uColorHot, ch[0], ch[1], ch[2]);

		gl.drawArrays(gl.TRIANGLES, 0, 3);
	}

	destroy() { this.gl.deleteProgram(this.program); }
}
