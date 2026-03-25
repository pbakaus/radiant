/** Each preset is a snapshot of all uber-shader parameters for one visual effect. */

export interface Preset {
	name: string;
	title: string;
	params: Record<string, number | [number, number, number]>;
}

// Keys cached once at module level — never re-allocated
const FLOAT_KEYS = [
	'noiseBlend', 'fbmOctaves', 'fbmDecay', 'fbmFreqMul',
	'warpScale', 'warp1Str', 'warp2Str',
	'orbCount', 'orbRadius', 'orbIntensity', 'orbColorMode',
	'foldStr', 'foldFreq',
	'normalStr', 'diffuseStr', 'specStr', 'specPower', 'fresnelF0',
	'edgeGlowStr', 'vignetteStr', 'grainStr'
];

const VEC3_KEYS = ['colorShadow', 'colorMid', 'colorBright', 'colorHot'];

/**
 * Pre-allocate a lerp buffer. Call once at init.
 */
export function createLerpBuffer(template: Preset): Record<string, number | [number, number, number]> {
	const buf: Record<string, number | [number, number, number]> = {};
	for (let i = 0; i < FLOAT_KEYS.length; i++) {
		buf[FLOAT_KEYS[i]] = template.params[FLOAT_KEYS[i]] as number;
	}
	for (let i = 0; i < VEC3_KEYS.length; i++) {
		const v = template.params[VEC3_KEYS[i]] as [number, number, number];
		buf[VEC3_KEYS[i]] = [v[0], v[1], v[2]];
	}
	return buf;
}

/**
 * Lerp into pre-allocated buffer. ZERO allocations — no Object.keys,
 * no iterators, no for-of, just indexed loops over cached key arrays.
 */
export function lerpPresetsInto(
	out: Record<string, number | [number, number, number]>,
	a: Preset,
	b: Preset,
	t: number
): void {
	for (let i = 0; i < FLOAT_KEYS.length; i++) {
		const k = FLOAT_KEYS[i];
		out[k] = (a.params[k] as number) + ((b.params[k] as number) - (a.params[k] as number)) * t;
	}
	for (let i = 0; i < VEC3_KEYS.length; i++) {
		const k = VEC3_KEYS[i];
		const va = a.params[k] as [number, number, number];
		const vb = b.params[k] as [number, number, number];
		const o = out[k] as [number, number, number];
		o[0] = va[0] + (vb[0] - va[0]) * t;
		o[1] = va[1] + (vb[1] - va[1]) * t;
		o[2] = va[2] + (vb[2] - va[2]) * t;
	}
}

export const fluidAmber: Preset = {
	name: 'fluid-amber',
	title: 'Fluid Amber',
	params: {
		// Noise
		noiseBlend: 0.0,         // simplex
		fbmOctaves: 5.0,
		fbmDecay: 0.55,
		fbmFreqMul: 2.1,
		// Domain warp
		warpScale: 1.0,
		warp1Str: 4.0,
		warp2Str: 3.5,
		// Orbs
		orbCount: 0.0,
		orbRadius: 0.0,
		orbIntensity: 0.0,
		orbColorMode: 0.0,       // 0=off, 1=additive color
		// Fold
		foldStr: 0.0,
		foldFreq: 2.0,
		// Lighting
		normalStr: 0.0,
		diffuseStr: 0.0,
		specStr: 0.0,
		specPower: 40.0,
		fresnelF0: 0.0,
		// Edge glow
		edgeGlowStr: 0.0,
		// Color palette
		colorShadow: [0.075, 0.065, 0.055],
		colorMid: [0.20, 0.14, 0.07],
		colorBright: [0.78, 0.58, 0.24],
		colorHot: [0.95, 0.75, 0.35],
		// Post
		vignetteStr: 0.5,
		grainStr: 0.0,
	}
};

export const inkDissolve: Preset = {
	name: 'ink-dissolve',
	title: 'Ink Dissolve',
	params: {
		noiseBlend: 0.0,
		fbmOctaves: 4.0,
		fbmDecay: 0.45,
		fbmFreqMul: 2.02,
		warpScale: 0.8,
		warp1Str: 2.5,
		warp2Str: 2.2,
		orbCount: 3.0,
		orbRadius: 0.75,
		orbIntensity: 0.8,
		orbColorMode: 0.0,       // mask mode
		foldStr: 0.0,
		foldFreq: 2.0,
		normalStr: 0.0,
		diffuseStr: 0.0,
		specStr: 0.0,
		specPower: 40.0,
		fresnelF0: 0.0,
		edgeGlowStr: 1.0,
		colorShadow: [0.02, 0.015, 0.01],
		colorMid: [0.06, 0.035, 0.014],
		colorBright: [0.42, 0.28, 0.14],
		colorHot: [1.0, 0.82, 0.52],
		vignetteStr: 0.5,
		grainStr: 0.0,
	}
};

export const chromaticBloom: Preset = {
	name: 'chromatic-bloom',
	title: 'Chromatic Bloom',
	params: {
		noiseBlend: 1.0,
		fbmOctaves: 0.0,        // no noise field
		fbmDecay: 0.5,
		fbmFreqMul: 2.0,
		warpScale: 1.0,
		warp1Str: 0.0,
		warp2Str: 0.0,
		orbCount: 7.0,
		orbRadius: 0.28,
		orbIntensity: 1.4,
		orbColorMode: 1.0,       // additive color mode
		foldStr: 0.0,
		foldFreq: 2.0,
		normalStr: 0.0,
		diffuseStr: 0.0,
		specStr: 0.0,
		specPower: 40.0,
		fresnelF0: 0.0,
		edgeGlowStr: 0.0,
		colorShadow: [0.0, 0.0, 0.0],
		colorMid: [0.03, 0.10, 1.0],
		colorBright: [1.0, 0.42, 0.03],
		colorHot: [0.85, 0.93, 1.0],
		vignetteStr: 0.5,
		grainStr: 0.04,
	}
};

export const liquidGold: Preset = {
	name: 'liquid-gold',
	title: 'Liquid Gold',
	params: {
		noiseBlend: 1.0,         // value noise
		fbmOctaves: 6.0,
		fbmDecay: 0.45,
		fbmFreqMul: 2.15,
		warpScale: 2.0,
		warp1Str: 3.0,
		warp2Str: 2.5,
		orbCount: 5.0,           // metaballs
		orbRadius: 0.15,
		orbIntensity: 0.15,
		orbColorMode: 0.0,       // height-add via intensity
		foldStr: 0.0,
		foldFreq: 2.0,
		normalStr: 1.0,
		diffuseStr: 1.0,
		specStr: 0.5,            // blinn-phong
		specPower: 120.0,
		fresnelF0: 0.8,
		edgeGlowStr: 0.0,
		colorShadow: [0.18, 0.10, 0.02],
		colorMid: [0.55, 0.35, 0.08],
		colorBright: [0.83, 0.61, 0.22],
		colorHot: [1.0, 0.84, 0.45],
		vignetteStr: 0.65,
		grainStr: 0.0,
	}
};

export const silkCascade: Preset = {
	name: 'silk-cascade',
	title: 'Silk Cascade',
	params: {
		noiseBlend: 1.0,         // value noise
		fbmOctaves: 3.0,
		fbmDecay: 0.5,
		fbmFreqMul: 2.0,
		warpScale: 1.0,
		warp1Str: 0.55,
		warp2Str: 0.0,
		orbCount: 0.0,
		orbRadius: 0.0,
		orbIntensity: 0.0,
		orbColorMode: 0.0,
		foldStr: 1.0,
		foldFreq: 3.2,
		normalStr: 1.0,
		diffuseStr: 0.75,
		specStr: 1.0,            // anisotropic
		specPower: 40.0,
		fresnelF0: 0.0,
		edgeGlowStr: 0.0,
		colorShadow: [0.08, 0.03, 0.04],
		colorMid: [0.42, 0.18, 0.22],
		colorBright: [0.72, 0.38, 0.42],
		colorHot: [1.0, 0.82, 0.86],
		vignetteStr: 0.4,
		grainStr: 0.015,
	}
};

export const allPresets: Preset[] = [
	fluidAmber,
	inkDissolve,
	chromaticBloom,
	liquidGold,
	silkCascade
];
