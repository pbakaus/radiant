/**
 * Presets as flat Float32Arrays for zero-allocation GPU upload.
 *
 * Layout matches the WGSL uniform struct exactly (192 bytes / 48 floats):
 *
 *  0: time           1: zoom           2: hue_shift      3: fbm_octaves
 *  4: res.x          5: res.y          6: mouse.x        7: mouse.y
 *  8: zoom_center.x  9: zoom_center.y 10: fbm_decay     11: fbm_freq_mul
 * 12: warp_scale    13: warp1_str     14: warp2_str     15: orb_count
 * 16: orb_radius    17: orb_intensity 18: orb_color_mode 19: fold_str
 * 20: fold_freq     21: normal_str    22: diffuse_str   23: spec_str
 * 24: spec_power    25: fresnel_f0    26: edge_glow_str 27: vignette_str
 * 28: grain_str     29: _pad          30: _pad          31: _pad
 * 32-35: color_shadow (vec4)
 * 36-39: color_mid (vec4)
 * 40-43: color_bright (vec4)
 * 44-47: color_hot (vec4)
 */

export const UNIFORM_FLOATS = 48;
export const UNIFORM_BYTES = UNIFORM_FLOATS * 4;

// Indices for per-frame uniforms (set by JS each frame)
export const U_TIME = 0;
export const U_ZOOM = 1;
export const U_HUE_SHIFT = 2;
export const U_RES_X = 4;
export const U_RES_Y = 5;
export const U_MOUSE_X = 6;
export const U_MOUSE_Y = 7;
export const U_ZOOM_CENTER_X = 8;
export const U_ZOOM_CENTER_Y = 9;

// Indices for preset params (interpolated)
const P_FBM_OCTAVES = 3;
const P_FBM_DECAY = 10;
const P_FBM_FREQ_MUL = 11;
const P_WARP_SCALE = 12;
const P_WARP1_STR = 13;
const P_WARP2_STR = 14;
const P_ORB_COUNT = 15;
const P_ORB_RADIUS = 16;
const P_ORB_INTENSITY = 17;
const P_ORB_COLOR_MODE = 18;
const P_FOLD_STR = 19;
const P_FOLD_FREQ = 20;
const P_NORMAL_STR = 21;
const P_DIFFUSE_STR = 22;
const P_SPEC_STR = 23;
const P_SPEC_POWER = 24;
const P_FRESNEL_F0 = 25;
const P_EDGE_GLOW_STR = 26;
const P_VIGNETTE_STR = 27;
const P_GRAIN_STR = 28;
// 29-31: padding
const P_COLOR_SHADOW = 32; // 32,33,34 (35=pad)
const P_COLOR_MID = 36;
const P_COLOR_BRIGHT = 40;
const P_COLOR_HOT = 44;

// All interpolatable param indices (floats)
const FLOAT_INDICES = [
	P_FBM_OCTAVES, P_FBM_DECAY, P_FBM_FREQ_MUL,
	P_WARP_SCALE, P_WARP1_STR, P_WARP2_STR,
	P_ORB_COUNT, P_ORB_RADIUS, P_ORB_INTENSITY, P_ORB_COLOR_MODE,
	P_FOLD_STR, P_FOLD_FREQ,
	P_NORMAL_STR, P_DIFFUSE_STR, P_SPEC_STR, P_SPEC_POWER, P_FRESNEL_F0,
	P_EDGE_GLOW_STR, P_VIGNETTE_STR, P_GRAIN_STR
];

const VEC3_INDICES = [P_COLOR_SHADOW, P_COLOR_MID, P_COLOR_BRIGHT, P_COLOR_HOT];

export interface Preset {
	name: string;
	title: string;
	data: Float32Array; // 48 floats, only preset slots filled
}

function makePreset(
	name: string, title: string,
	fbmOctaves: number, fbmDecay: number, fbmFreqMul: number,
	warpScale: number, warp1Str: number, warp2Str: number,
	orbCount: number, orbRadius: number, orbIntensity: number, orbColorMode: number,
	foldStr: number, foldFreq: number,
	normalStr: number, diffuseStr: number, specStr: number, specPower: number, fresnelF0: number,
	edgeGlowStr: number, vignetteStr: number, grainStr: number,
	cS: [number, number, number], cM: [number, number, number],
	cB: [number, number, number], cH: [number, number, number]
): Preset {
	const d = new Float32Array(UNIFORM_FLOATS);
	d[P_FBM_OCTAVES] = fbmOctaves; d[P_FBM_DECAY] = fbmDecay; d[P_FBM_FREQ_MUL] = fbmFreqMul;
	d[P_WARP_SCALE] = warpScale; d[P_WARP1_STR] = warp1Str; d[P_WARP2_STR] = warp2Str;
	d[P_ORB_COUNT] = orbCount; d[P_ORB_RADIUS] = orbRadius;
	d[P_ORB_INTENSITY] = orbIntensity; d[P_ORB_COLOR_MODE] = orbColorMode;
	d[P_FOLD_STR] = foldStr; d[P_FOLD_FREQ] = foldFreq;
	d[P_NORMAL_STR] = normalStr; d[P_DIFFUSE_STR] = diffuseStr;
	d[P_SPEC_STR] = specStr; d[P_SPEC_POWER] = specPower; d[P_FRESNEL_F0] = fresnelF0;
	d[P_EDGE_GLOW_STR] = edgeGlowStr; d[P_VIGNETTE_STR] = vignetteStr; d[P_GRAIN_STR] = grainStr;
	d[P_COLOR_SHADOW] = cS[0]; d[P_COLOR_SHADOW + 1] = cS[1]; d[P_COLOR_SHADOW + 2] = cS[2];
	d[P_COLOR_MID] = cM[0]; d[P_COLOR_MID + 1] = cM[1]; d[P_COLOR_MID + 2] = cM[2];
	d[P_COLOR_BRIGHT] = cB[0]; d[P_COLOR_BRIGHT + 1] = cB[1]; d[P_COLOR_BRIGHT + 2] = cB[2];
	d[P_COLOR_HOT] = cH[0]; d[P_COLOR_HOT + 1] = cH[1]; d[P_COLOR_HOT + 2] = cH[2];
	return { name, title, data: d };
}

/** Lerp preset params into a pre-allocated Float32Array. Zero allocations. */
export function lerpPresetsInto(out: Float32Array, a: Float32Array, b: Float32Array, t: number): void {
	for (let i = 0; i < FLOAT_INDICES.length; i++) {
		const idx = FLOAT_INDICES[i];
		out[idx] = a[idx] + (b[idx] - a[idx]) * t;
	}
	for (let i = 0; i < VEC3_INDICES.length; i++) {
		const idx = VEC3_INDICES[i];
		out[idx] = a[idx] + (b[idx] - a[idx]) * t;
		out[idx + 1] = a[idx + 1] + (b[idx + 1] - a[idx + 1]) * t;
		out[idx + 2] = a[idx + 2] + (b[idx + 2] - a[idx + 2]) * t;
	}
}

export const fluidAmber = makePreset('fluid-amber', 'Fluid Amber',
	5, 0.55, 2.1, 1.0, 4.0, 3.5,
	0, 0, 0, 0,
	0, 2.0,
	0, 0, 0, 40, 0,
	0, 0.5, 0,
	[0.075, 0.065, 0.055], [0.20, 0.14, 0.07], [0.78, 0.58, 0.24], [0.95, 0.75, 0.35]
);

export const inkDissolve = makePreset('ink-dissolve', 'Ink Dissolve',
	4, 0.45, 2.02, 0.8, 2.5, 2.2,
	3, 0.75, 0.8, 0,
	0, 2.0,
	0, 0, 0, 40, 0,
	1.0, 0.5, 0,
	[0.02, 0.015, 0.01], [0.06, 0.035, 0.014], [0.42, 0.28, 0.14], [1.0, 0.82, 0.52]
);

export const chromaticBloom = makePreset('chromatic-bloom', 'Chromatic Bloom',
	0, 0.5, 2.0, 1.0, 0, 0,
	7, 0.28, 1.4, 1.0,
	0, 2.0,
	0, 0, 0, 40, 0,
	0, 0.5, 0.04,
	[0.0, 0.0, 0.0], [0.03, 0.10, 1.0], [1.0, 0.42, 0.03], [0.85, 0.93, 1.0]
);

export const liquidGold = makePreset('liquid-gold', 'Liquid Gold',
	6, 0.45, 2.15, 2.0, 3.0, 2.5,
	5, 0.15, 0.15, 0,
	0, 2.0,
	1.0, 1.0, 0.5, 120, 0.8,
	0, 0.65, 0,
	[0.18, 0.10, 0.02], [0.55, 0.35, 0.08], [0.83, 0.61, 0.22], [1.0, 0.84, 0.45]
);

export const silkCascade = makePreset('silk-cascade', 'Silk Cascade',
	3, 0.5, 2.0, 1.0, 0.55, 0,
	0, 0, 0, 0,
	1.0, 3.2,
	1.0, 0.75, 1.0, 40, 0,
	0, 0.4, 0.015,
	[0.08, 0.03, 0.04], [0.42, 0.18, 0.22], [0.72, 0.38, 0.42], [1.0, 0.82, 0.86]
);

export const allPresets: Preset[] = [
	fluidAmber, inkDissolve, chromaticBloom, liquidGold, silkCascade
];
