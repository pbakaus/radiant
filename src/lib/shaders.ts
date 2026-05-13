export interface ShaderParam {
	name: string;
	label: string;
	min: number;
	max: number;
	step?: number;
	default: number;
}

export type ShaderTag = 'fill' | 'object' | 'particles' | 'physics' | 'noise' | 'organic' | 'geometric';

export const tagLabels: Record<ShaderTag, string> = {
	fill: 'Full canvas',
	object: 'Standalone',
	particles: 'Particles',
	physics: 'Physics',
	noise: 'Noise',
	organic: 'Organic',
	geometric: 'Geometric'
};

export type ShaderTechnique = 'canvas-2d' | 'webgl';

export const techniqueLabels: Record<ShaderTechnique, string> = {
	'canvas-2d': 'Canvas 2D',
	'webgl': 'WebGL'
};

export interface Shader {
	id: string;
	file: string;
	title: string;
	desc: string;
	tags: ShaderTag[];
	technique: ShaderTechnique;
	params?: ShaderParam[];
	inspiration?: string;
	credit?: string;
	creditUrl?: string;
	/** Override the default color scheme for this shader (e.g. 'blue') */
	defaultScheme?: string;
	/** Custom hero layout: shader runs full-viewport with params to reposition the focal element */
	heroConfig?: {
		params: { name: string; value: number }[];
	};
	/** True if a deep-dive article exists for this shader at /learn/[id] */
	hasArticle?: boolean;
}

export const shaders: Shader[] = [
	{
		id: 'flow-field',
		file: 'flow-field.html',
		title: 'Flow Field with Particle Trails',
		desc: 'Particles following Perlin noise currents with warm amber trails.',
		tags: ['fill', 'particles', 'noise'],
		technique: 'canvas-2d',
		params: [
			{ name: 'SPEED', label: 'Flow Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.2 },
			{ name: 'NOISE_SCALE', label: 'Pattern Scale', min: 0.001, max: 0.01, step: 0.0005, default: 0.0025 }
		]
	},
	{
		id: 'topographic',
		file: 'topographic.html',
		title: 'Topographic Contour Map',
		desc: 'Living terrain map with marching squares isolines and elevation labels.',
		tags: ['fill', 'noise', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'NUM_CONTOURS', label: 'Contour Density', min: 4, max: 30, step: 1, default: 14 },
			{ name: 'TIME_SPEED', label: 'Animation Speed', min: 0.0, max: 0.5, step: 0.01, default: 0.15 }
		]
	},
	{
		id: 'generative-tree',
		file: 'generative-tree.html',
		title: 'Generative Branching Tree',
		desc: 'L-system inspired tree with continuous growth and regrowth cycles.',
		tags: ['object', 'organic'],
		technique: 'canvas-2d',
		params: [
			{ name: 'GROWTH_SPEED_BASE', label: 'Growth Speed', min: 0.003, max: 0.025, step: 0.001, default: 0.008 },
			{ name: 'MAX_DEPTH', label: 'Branch Depth', min: 4, max: 14, step: 1, default: 9 }
		]
	},
	{
		id: 'strange-attractor',
		file: 'strange-attractor.html',
		title: 'Strange Attractor (Lorenz)',
		desc: 'Lorenz system with 3D projection, rotation, and glowing particle trails.',
		tags: ['object', 'particles', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'STEPS_PER_FRAME', label: 'Simulation Speed', min: 1, max: 12, step: 1, default: 4 },
			{ name: 'TRAIL_LENGTH', label: 'Trail Length', min: 500, max: 4000, step: 100, default: 2000 },
			{ name: 'RHO', label: 'Attractor Shape', min: 15, max: 50, step: 0.5, default: 28 }
		]
	},
	{
		id: 'pendulum-wave',
		file: 'pendulum-wave.html',
		title: 'Pendulum Wave',
		desc: 'Physics-based pendulum wave creating emergent interference patterns.',
		tags: ['object', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'NUM_PENDULUMS', label: 'Pendulum Count', min: 6, max: 40, step: 1, default: 20 },
			{ name: 'CYCLE_DURATION', label: 'Cycle Duration', min: 20, max: 120, step: 5, default: 60 }
		]
	},
	{
		id: 'phyllotaxis',
		file: 'phyllotaxis.html',
		title: 'Phyllotaxis Spiral',
		desc: "Golden angle spiral with Fibonacci lattice connections.",
		tags: ['object', 'geometric', 'organic'],
		technique: 'canvas-2d',
		params: [
			{ name: 'MAX_POINTS', label: 'Point Count', min: 500, max: 5000, step: 100, default: 2000 },
			{ name: 'SPREAD', label: 'Spiral Tightness', min: 0.003, max: 0.015, step: 0.0005, default: 0.0065 }
		]
	},
	{
		id: 'fluid-amber',
		file: 'fluid-amber.html',
		title: 'Fluid Amber',
		desc: 'Domain-warped simplex noise with layered organic flow and warm palette.',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'timeScale', label: 'Animation Speed', min: 0.0, max: 0.5, step: 0.01, default: 0.15 },
			{ name: 'ampDecay', label: 'Detail Level', min: 0.3, max: 0.7, step: 0.01, default: 0.48 }
		]
	},
	{
		id: 'champagne-fizz',
		file: 'champagne-fizz.html',
		title: 'Champagne Fizz',
		desc: 'Effervescent bubbles rising with wobble physics, refractive highlights, and sparkle bursts.',
		inspiration: 'Sabrina Carpenter',
		tags: ['fill', 'particles', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'BUBBLE_RATE', label: 'Bubble Rate', min: 1, max: 10, step: 1, default: 3 },
			{ name: 'RISE_SPEED', label: 'Rise Speed', min: 0.5, max: 4.0, step: 0.1, default: 1.5 }
		]
	},
	{
		id: 'sugar-glass',
		file: 'sugar-glass.html',
		title: 'Sugar Glass',
		desc: 'Caramelized sugar glass with Voronoi fracture patterns and golden light bleeding through cracks.',
		inspiration: 'Sabrina Carpenter',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'CRACK_SPEED', label: 'Crack Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'LIGHT_BLEED', label: 'Light Bleed', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'resonant-strings',
		file: 'resonant-strings.html',
		title: 'Resonant Strings',
		desc: 'Vibrating cello strings with standing wave harmonics, overtone interference, and rosin dust particles.',
		inspiration: 'Laufey',
		tags: ['object', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'HARMONIC_COUNT', label: 'Harmonics', min: 1, max: 12, step: 1, default: 5 },
			{ name: 'VIBRATION_SPEED', label: 'Vibration Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'chladni-resonance',
		file: 'chladni-resonance.html',
		title: 'Chladni Resonance',
		desc: 'Sand patterns forming on a vibrating plate, morphing between harmonic modes with golden glow.',
		inspiration: 'Laufey',
		tags: ['object', 'geometric', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'MODE_SPEED', label: 'Mode Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'COMPLEXITY', label: 'Complexity', min: 2, max: 8, step: 1, default: 5 }
		]
	},
	{
		id: 'kinetic-grid',
		file: 'kinetic-grid.html',
		title: 'Kinetic Grid',
		desc: 'Spring-connected grid mesh with traveling force impulses, tension-colored connections in cyan and magenta.',
		inspiration: 'Dua Lipa',
		tags: ['fill', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'IMPULSE_RATE', label: 'Impulse Rate', min: 0.3, max: 3.0, step: 0.1, default: 0.7 },
			{ name: 'SPRING_TENSION', label: 'Spring Tension', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'IMPULSE_STRENGTH', label: 'Impulse Force', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'DAMPING', label: 'Damping', min: 0.95, max: 0.995, step: 0.001, default: 0.978 },
			{ name: 'RETURN_FORCE', label: 'Return Force', min: 0.001, max: 0.01, step: 0.001, default: 0.003 }
		]
	},
	{
		id: 'strobe-geometry',
		file: 'strobe-geometry.html',
		title: 'Strobe Geometry',
		desc: 'Sharp neon geometric shapes flashing in choreographed sequence with cyan-to-magenta afterglow decay.',
		inspiration: 'Dua Lipa',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'FLASH_RATE', label: 'Flash Rate', min: 0.3, max: 2.0, step: 0.1, default: 0.7 },
			{ name: 'GLOW_INTENSITY', label: 'Glow', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'laser-labyrinth',
		file: 'laser-labyrinth.html',
		title: 'Laser Labyrinth',
		desc: 'Volumetric laser beams crossing in a dark void with prismatic colors and intersection flares.',
		inspiration: 'Dua Lipa',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'SWEEP_SPEED', label: 'Sweep Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'BEAM_INTENSITY', label: 'Beam Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'bass-ripple',
		file: 'bass-ripple.html',
		title: 'Bass Ripple',
		desc: 'Vibrating speaker mesh with beat-synced wave displacement and metallic specular sheen.',
		inspiration: 'Dua Lipa',
		tags: ['fill', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'BASS_FREQ', label: 'Beat Speed', min: 0.1, max: 2.0, step: 0.1, default: 0.4 },
			{ name: 'BASS_INTENSITY', label: 'Bass Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'ink-dissolve',
		file: 'ink-dissolve.html',
		title: 'Ink Dissolve',
		desc: 'Dense ink tendrils spreading through amber liquid with reaction-diffusion branching patterns.',
		inspiration: 'Billie Eilish',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'SPREAD_SPEED', label: 'Spread Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.4 },
			{ name: 'TENDRIL_DETAIL', label: 'Tendril Detail', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'sequin-wave',
		file: 'sequin-wave.html',
		title: 'Sequin Wave',
		desc: 'Grid of metallic sequin discs catching sweeping light with specular reflections and warm shimmer.',
		inspiration: 'Taylor Swift',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'WAVE_SPEED', label: 'Wave Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.8 },
			{ name: 'SPARKLE_INTENSITY', label: 'Sparkle', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'gilt-mosaic',
		file: 'gilt-mosaic.html',
		title: 'Gilt Mosaic',
		desc: 'Byzantine golden mosaic wall with individually shimmering tiles catching candlelight.',
		inspiration: 'Beyoncé',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'ANIM_MODE', label: 'Wave Flip', min: 0.0, max: 1.0, step: 1.0, default: 1.0 },
			{ name: 'TILE_SCALE', label: 'Tile Scale', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'WAVE_SPEED', label: 'Wave Speed', min: 0.5, max: 6.0, step: 0.1, default: 4.0 },
			{ name: 'WAVE_DELAY', label: 'Wave Delay', min: 0.5, max: 4.0, step: 0.1, default: 1.5 },
			{ name: 'WAVE_DIR', label: 'Wave Direction', min: 0.0, max: 3.0, step: 1.0, default: 0.0 }
		]
	},
	{
		id: 'gilded-fracture',
		file: 'gilded-fracture.html',
		title: 'Gilded Fracture',
		desc: 'Kintsugi-inspired golden cracks spreading across dark surface with molten gold light bleeding through.',
		inspiration: 'Beyoncé',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'CRACK_SPEED', label: 'Crack Speed', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'GLOW_INTENSITY', label: 'Glow Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'radiant-geometry',
		file: 'radiant-geometry.html',
		title: 'Radiant Geometry',
		desc: 'Animated Islamic geometric art with layered golden star patterns and counter-rotating tracery.',
		inspiration: 'Beyoncé',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'PATTERN_COMPLEXITY', label: 'Complexity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'golden-throne',
		file: 'golden-throne.html',
		title: 'Golden Throne',
		desc: 'Sacred geometry mandala with golden ratio spirals and counter-rotating layers.',
		inspiration: 'Beyoncé',
		tags: ['object', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.0, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'COMPLEXITY', label: 'Complexity', min: 2, max: 8, step: 1, default: 5 }
		]
	},
	{
		id: 'sacred-strange',
		file: 'sacred-strange.html',
		title: 'Sacred Strange',
		desc: 'Fractal golden geometry with overlapping star motifs creating Doctor Strange-like dimensional patterns.',
		inspiration: 'Benedict Cumberbatch',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'PATTERN_COMPLEXITY', label: 'Complexity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'PATTERN', label: 'Dimensional Shift', min: 0.0, max: 0.15, step: 0.01, default: 0.05 }
		]
	},
	{
		id: 'tropical-heat',
		file: 'tropical-heat.html',
		title: 'Tropical Heat',
		desc: 'Heat shimmer distortion with chromatic aberration and tropical color blooms.',
		inspiration: 'Bad Bunny',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'HEAT_INTENSITY', label: 'Heat Intensity', min: 0.2, max: 2.5, step: 0.1, default: 1.0 },
			{ name: 'COLOR_VIBRANCY', label: 'Color Vibrancy', min: 0.3, max: 1.5, step: 0.05, default: 0.8 }
		]
	},
	{
		id: 'neon-drip',
		file: 'neon-drip.html',
		title: 'Neon Drip',
		desc: 'Metaball blobs dripping upward with surface tension physics and trailing tendrils.',
		inspiration: 'Bad Bunny',
		tags: ['fill', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'DRIP_SPEED', label: 'Drip Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'BLOB_COUNT', label: 'Blob Count', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'voltage-arc',
		file: 'voltage-arc.html',
		title: 'Voltage Arc',
		desc: 'Electric plasma arcs crackling between floating conductor points with warm glow.',
		inspiration: 'Bad Bunny',
		tags: ['object', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'ARC_INTENSITY', label: 'Arc Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'CRACKLE_SPEED', label: 'Crackle Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'moonlit-ripple',
		file: 'moonlit-ripple.html',
		title: 'Moonlit Ripple',
		desc: 'Moon reflection on dark water with multi-directional waves, Fresnel reflection, and 3D perspective.',
		inspiration: 'SZA',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		defaultScheme: 'blue',
		params: [
			{ name: 'RIPPLE_SPEED', label: 'Ripple Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'MOON_GLOW', label: 'Moon Glow', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'CAMERA_TILT', label: 'Camera Tilt', min: -0.3, max: 1.0, step: 0.01, default: 0.15 },
			{ name: 'WAVE_INTENSITY', label: 'Wave Intensity', min: 0.0, max: 3.0, step: 0.01, default: 1.0 }
		]
	},
	{
		id: 'eclipse-glow',
		file: 'eclipse-glow.html',
		title: 'Eclipse Glow',
		desc: 'Solar eclipse corona with radial noise rays, diamond ring effect, and streaming solar wind.',
		inspiration: 'SZA',
		tags: ['object', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'CORONA_SIZE', label: 'Corona Size', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'RAY_INTENSITY', label: 'Ray Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'diamond-caustics',
		file: 'diamond-caustics.html',
		title: 'Diamond Caustics',
		desc: 'Light refracting through rotating diamond facets casting prismatic caustic patterns.',
		inspiration: 'Rihanna',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'BRILLIANCE', label: 'Brilliance', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'rain-on-glass',
		file: 'rain-on-glass.html',
		title: 'Rain on Glass',
		desc: 'Ultra-realistic water droplets on a window, refracting a blurred city night with realistic trail physics.',
		inspiration: 'Rihanna',
		credit: 'Inspired by the excellent work of Lucas Bebber',
		creditUrl: 'https://github.com/codrops/RainEffect',
		tags: ['fill', 'physics', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'RAIN_AMOUNT', label: 'Rain Amount', min: 0.1, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'REFRACTION', label: 'Refraction Strength', min: 0.1, max: 3.0, step: 0.1, default: 1.0 }
		],
		hasArticle: true
	},
	{
		id: 'rain-umbrella',
		file: 'rain-umbrella.html',
		title: 'Rain on Umbrella',
		desc: 'Looking up through a translucent umbrella at city lights, with refractive drops sliding down the dome and a slow walking drift.',
		inspiration: 'Rihanna',
		credit: 'Inspired by the excellent work of Lucas Bebber',
		creditUrl: 'https://github.com/codrops/RainEffect',
		tags: ['fill', 'physics', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'RAIN_AMOUNT', label: 'Rain Amount', min: 0.1, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'REFRACTION', label: 'Refraction Strength', min: 0.1, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'WALK_SPEED', label: 'Walk Speed', min: 0.0, max: 3.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'metamorphosis',
		file: 'metamorphosis.html',
		title: 'Metamorphosis',
		desc: 'Raymarched metaballs continuously merging and splitting with liquid-metal surface.',
		inspiration: 'Lady Gaga',
		tags: ['object', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'MORPH_SPEED', label: 'Morph Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'BLOB_COUNT', label: 'Blob Count', min: 2, max: 6, step: 1, default: 4 }
		]
	},
	{
		id: 'artpop-iridescence',
		file: 'artpop-iridescence.html',
		title: 'Artpop Iridescence',
		desc: 'Holographic membrane with thin-film interference creating prismatic color shifts across an undulating surface.',
		inspiration: 'Lady Gaga',
		tags: ['fill', 'organic', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'FILM_THICKNESS', label: 'Film Thickness', min: 0.5, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'FLOW_SPEED', label: 'Flow Speed', min: 0.1, max: 2.0, step: 0.1, default: 0.5 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.68 },
				{ name: 'CENTER_Y', value: 0.5 },
				{ name: 'SCALE', value: 0.45 }
			]
		}
	},
	{
		id: 'silk-groove',
		file: 'silk-groove.html',
		title: 'Silk Groove',
		desc: 'Flowing silk ribbons with specular highlights and cloth-like wave animation.',
		inspiration: 'Bruno Mars',
		tags: ['fill', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'FLOW_SPEED', label: 'Flow Speed', min: 0.2, max: 2.0, step: 0.05, default: 0.8 },
			{ name: 'WAVE_AMPLITUDE', label: 'Wave Amplitude', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'gilt-thread',
		file: 'gilt-thread.html',
		title: 'Gilt Thread',
		desc: 'Golden threads tracing intricate parametric curves with metallic sheen and sparkle tips.',
		inspiration: 'Bruno Mars',
		tags: ['object', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'SHAPE', label: 'Shape', min: 1, max: 4, step: 1, default: 1 },
			{ name: 'DRAW_SPEED', label: 'Draw Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'THREAD_COUNT', label: 'Thread Count', min: 2, max: 8, step: 1, default: 5 }
		]
	},
	{
		id: 'event-horizon',
		file: 'event-horizon.html',
		title: 'Event Horizon',
		desc: 'Physics-based black hole with raytraced gravitational lensing, volumetric accretion disk, and Doppler beaming.',
		inspiration: 'The Weeknd',
		tags: ['object', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'DISK_INTENSITY', label: 'Disk Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'TILT', label: 'Tilt', min: -1.5, max: 1.5, step: 0.05, default: 0.0 },
			{ name: 'ROTATE', label: 'Rotate', min: -3.14, max: 3.14, step: 0.05, default: 0.0 },
			{ name: 'CHROMATIC', label: 'Chromatic', min: 0.0, max: 1.0, step: 0.05, default: 0.0 }
		],
		heroConfig: {
			params: [
				{ name: 'BH_CENTER_X', value: 0.68 },
				{ name: 'BH_CENTER_Y', value: 0.45 },
				{ name: 'BH_SCALE', value: 2.4 }
			]
		},
		hasArticle: true
	},
	{
		id: 'burning-film',
		file: 'burning-film.html',
		title: 'Burning Film',
		desc: 'Celluloid film stock catching fire with spreading amber burn holes, glowing edges, and ember field.',
		inspiration: 'The Weeknd',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'BURN_SPEED', label: 'Burn Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'EMBER_GLOW', label: 'Ember Glow', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'vertigo',
		file: 'vertigo.html',
		title: 'Vertigo',
		desc: 'Slow hypnotic tunnel with crimson ring segments, wave-based illumination, and dark void center.',
		inspiration: 'The Weeknd',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'TUNNEL_SPEED', label: 'Tunnel Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'SPIRAL_INTENSITY', label: 'Spiral', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'stardust-veil',
		file: 'stardust-veil.html',
		title: 'Stardust Veil',
		desc: 'Dense cosmic stardust with parallax depth layers, aurora ribbons, constellation threads, and brightness waves.',
		inspiration: 'Ariana Grande',
		tags: ['fill', 'particles', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.4 },
			{ name: 'STAR_DENSITY', label: 'Star Density', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'silk-cascade',
		file: 'silk-cascade.html',
		title: 'Silk Cascade',
		desc: 'Flowing layered silk fabric with anisotropic specular highlights, parallax depth, and warm translucent overlap.',
		inspiration: 'Ariana Grande',
		tags: ['fill', 'organic', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'FLOW_SPEED', label: 'Flow Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.4 },
			{ name: 'SHEEN_INTENSITY', label: 'Sheen Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'smolder',
		file: 'smolder.html',
		title: 'Smolder',
		desc: 'Radial warmth radiating through animated turbulence with heat shimmer, ember particles, and cool blue edges.',
		inspiration: 'Pedro Pascal',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'HEAT_INTENSITY', label: 'Heat Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'TURBULENCE', label: 'Turbulence', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.68 },
				{ name: 'CENTER_Y', value: 0.45 },
				{ name: 'SCALE', value: 0.5 }
			]
		}
	},
	{
		id: 'signal-decay',
		file: 'signal-decay.html',
		title: 'Signal Decay',
		desc: 'Clean amber waveforms progressively degrading into gorgeous warm noise — order dissolving into beautiful chaos.',
		inspiration: 'Billie Eilish',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'SIGNAL_SPEED', label: 'Signal Speed', min: 0.2, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'DECAY_INTENSITY', label: 'Decay', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'neon-revival',
		file: 'neon-revival.html',
		title: 'Neon Revival',
		desc: 'Flickering neon sign with electrical buzz, dripping light particles, and wall reflections.',
		inspiration: 'Chappell Roan',
		tags: ['object', 'particles'],
		technique: 'webgl',
		params: [
			{ name: 'SHAPE', label: 'Shape', min: 1, max: 4, step: 1, default: 1 },
			{ name: 'FLICKER_RATE', label: 'Flicker Rate', min: 0.1, max: 1.0, step: 0.05, default: 0.5 },
			{ name: 'GLOW_SPREAD', label: 'Glow Spread', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.68 },
				{ name: 'CENTER_Y', value: 0.5 },
				{ name: 'SCALE', value: 0.55 }
			]
		}
	},
	{
		id: 'lipstick-smear',
		file: 'lipstick-smear.html',
		title: 'Lipstick Smear',
		desc: 'Viscous fluid simulation in hot pink and crimson — bold pigment streaking and blending with metallic sheen.',
		inspiration: 'Chappell Roan',
		tags: ['fill', 'physics', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'VISCOSITY', label: 'Viscosity', min: 0.1, max: 2.0, step: 0.05, default: 0.8 },
			{ name: 'COLOR_INTENSITY', label: 'Color Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'glitter-storm',
		file: 'glitter-storm.html',
		title: 'Glitter Storm',
		desc: 'Dense field of tumbling metallic glitter flakes catching rotating spotlights with specular flash physics.',
		inspiration: 'Chappell Roan',
		tags: ['fill', 'particles', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'SPARKLE_RATE', label: 'Sparkle Rate', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'DENSITY', label: 'Density', min: 0.3, max: 4.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'rubber-reality',
		file: 'rubber-reality.html',
		title: 'Rubber Reality',
		desc: 'Elastic grid mesh deformed by traveling attractors with spring physics and snap-back.',
		inspiration: 'Jim Carrey',
		tags: ['fill', 'physics', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'ELASTICITY', label: 'Elasticity', min: 0.3, max: 2.5, step: 0.1, default: 1.0 },
			{ name: 'DISTORTION_POINTS', label: 'Distortion Points', min: 1, max: 6, step: 1, default: 3 }
		]
	},
	{
		id: 'magma-core',
		file: 'magma-core.html',
		title: 'Magma Core',
		desc: 'Volcanic eruption with thermal lava particles, cooling physics, and magma pool.',
		inspiration: 'Jack Black',
		tags: ['object', 'particles', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'ERUPTION_FORCE', label: 'Eruption Force', min: 0.3, max: 2.5, step: 0.1, default: 1.0 },
			{ name: 'ERUPTION_INTERVAL', label: 'Eruption Interval', min: 2, max: 15, step: 1, default: 6 }
		]
	},
	{
		id: 'clockwork-mind',
		file: 'clockwork-mind.html',
		title: 'Clockwork Mind',
		desc: 'Interlocking precision gears with metallic rendering and mathematically correct meshing.',
		inspiration: 'Robert Downey Jr.',
		tags: ['object', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'GEAR_DETAIL', label: 'Gear Detail', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.68 },
				{ name: 'CENTER_Y', value: 0.5 },
				{ name: 'SCALE', value: 0.7 }
			]
		}
	},
	{
		id: 'edge-of-chaos',
		file: 'edge-of-chaos.html',
		title: 'Edge of Chaos',
		desc: 'Reaction-diffusion maze with golden edge glow and organic pop-and-regrow cycle.',
		inspiration: 'Robert Downey Jr.',
		tags: ['fill', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'PATTERN_SPEED', label: 'Evolution Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'POP_RATE', label: 'Pop Frequency', min: 0.2, max: 3.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'spark-chamber',
		file: 'spark-chamber.html',
		title: 'Spark Chamber',
		desc: 'Charged particles spiraling through a magnetic field, leaving curved trails like cloud chamber photography.',
		inspiration: 'Robert Downey Jr.',
		tags: ['fill', 'particles', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'EMISSION_RATE', label: 'Emission Rate', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'FIELD_STRENGTH', label: 'Field Strength', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'shifting-veils',
		file: 'shifting-veils.html',
		title: 'Shifting Veils',
		desc: 'Layered translucent noise curtains that morph and reveal patterns underneath.',
		inspiration: 'Meryl Streep',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'LAYER_SPEED', label: 'Layer Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'LAYER_COUNT', label: 'Layer Count', min: 3, max: 7, step: 1, default: 5 }
		]
	},
	{
		id: 'crystal-lattice',
		file: 'crystal-lattice.html',
		title: 'Crystal Lattice',
		desc: 'Procedural crystal formations growing with faceted 3D lighting and prismatic sparkle.',
		inspiration: 'Anne Hathaway',
		tags: ['object', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'GROWTH_SPEED', label: 'Crystal Count', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'REFRACTION', label: 'Prismatic', min: 0.0, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'TILT_X', label: 'Tilt X', min: -1.5, max: 1.5, step: 0.1, default: 0.0 },
			{ name: 'TILT_Y', label: 'Tilt Y', min: -0.5, max: 0.5, step: 0.1, default: 0.0 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.68 },
				{ name: 'CENTER_Y', value: 0.45 },
				{ name: 'SCALE', value: 0.55 }
			]
		}
	},
	{
		id: 'kaleidoscope-runway',
		file: 'kaleidoscope-runway.html',
		title: 'Kaleidoscope Runway',
		desc: 'Fashion-inspired kaleidoscopic tessellations with symmetric mirror segments.',
		inspiration: 'Zendaya',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'SYMMETRY', label: 'Symmetry', min: 4, max: 16, step: 2, default: 8 },
			{ name: 'PATTERN_SPEED', label: 'Pattern Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'digital-rain',
		file: 'digital-rain.html',
		title: 'Digital Rain',
		desc: 'Warm amber character columns dissolving into zen ripples at the water surface.',
		inspiration: 'Keanu Reeves',
		tags: ['fill', 'particles'],
		technique: 'canvas-2d',
		params: [
			{ name: 'FALL_SPEED', label: 'Fall Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'COLUMN_DENSITY', label: 'Column Density', min: 0.3, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'neon-drive',
		file: 'neon-drive.html',
		title: 'Neon Drive',
		desc: 'Rain-slicked neon road stretching to a vanishing point with approaching headlights.',
		inspiration: 'Ryan Gosling',
		tags: ['fill', 'particles'],
		technique: 'webgl',
		params: [
			{ name: 'DRIVE_SPEED', label: 'Drive Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'RAIN_INTENSITY', label: 'Rain Intensity', min: 0.1, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'liquid-gold',
		file: 'liquid-gold.html',
		title: 'Liquid Gold',
		desc: 'Molten metal flow with surface tension, metallic PBR shading, and golden reflections.',
		inspiration: 'Margot Robbie',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'FLOW_SPEED', label: 'Flow Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.4 },
			{ name: 'VISCOSITY', label: 'Viscosity', min: 0.2, max: 1.0, step: 0.05, default: 0.6 }
		]
	},
	{
		id: 'aurora-veil',
		file: 'aurora-veil.html',
		title: 'Aurora Veil',
		desc: 'Northern lights ribbons flowing above hexagonal ice crystal formations.',
		inspiration: 'Cate Blanchett',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'AURORA_SPEED', label: 'Aurora Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'AURORA_INTENSITY', label: 'Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'bioluminescence',
		file: 'bioluminescence.html',
		title: 'Bioluminescence',
		desc: 'Deep sea jellyfish pulsing with bioluminescent glow and drifting plankton.',
		inspiration: 'Zendaya',
		tags: ['fill', 'organic', 'particles'],
		technique: 'webgl',
		defaultScheme: 'blue',
		params: [
			{ name: 'GLOW_INTENSITY', label: 'Glow Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'WAVE_SPEED', label: 'Wave Speed', min: 0.2, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'gothic-filigree',
		file: 'gothic-filigree.html',
		title: 'Gothic Filigree',
		desc: 'Ornate fractal lace scrollwork growing from corners with dark metallic rendering.',
		inspiration: 'Jenna Ortega',
		tags: ['fill', 'organic', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'GROWTH_SPEED', label: 'Growth Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'CURL_TIGHTNESS', label: 'Curl Tightness', min: 0.3, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'laser-precision',
		file: 'laser-precision.html',
		title: 'Laser Precision',
		desc: 'Laser beams tracing geometric patterns with spark particles and intersection flares.',
		inspiration: 'Ana de Armas',
		tags: ['fill', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'DRAW_SPEED', label: 'Draw Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'LINE_BRIGHTNESS', label: 'Brightness', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'SHAPE', label: 'Shape', min: 1, max: 7, step: 1, default: 1 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.68 },
				{ name: 'CENTER_Y', value: 0.5 },
				{ name: 'SCALE', value: 0.65 }
			]
		}
	},
	{
		id: 'magnetic-sand',
		file: 'magnetic-sand.html',
		title: 'Magnetic Sand',
		desc: 'Thousands of particles aligning along invisible magnetic field lines with warm golden glow.',
		inspiration: 'Ana de Armas',
		tags: ['fill', 'particles', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'FIELD_STRENGTH', label: 'Field Strength', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'PARTICLE_COUNT', label: 'Particle Count', min: 1000, max: 5000, step: 500, default: 3000 }
		]
	},
	{
		id: 'woven-radiance',
		file: 'woven-radiance.html',
		title: 'Woven Radiance',
		desc: 'African textile-inspired weave patterns with vibrant kente cloth geometry.',
		inspiration: 'Lupita Nyong\'o',
		tags: ['fill', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'WEAVE_SPEED', label: 'Weave Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'COLOR_RICHNESS', label: 'Color Richness', min: 0.3, max: 1.0, step: 0.05, default: 0.8 }
		]
	},
	{
		id: 'jazz-chaos',
		file: 'jazz-chaos.html',
		title: 'Jazz Chaos',
		desc: 'Syncopated particle groups moving in rhythm with swing timing and solos.',
		inspiration: 'Jeff Goldblum',
		tags: ['fill', 'particles'],
		technique: 'canvas-2d',
		params: [
			{ name: 'TEMPO', label: 'Tempo', min: 60, max: 200, step: 5, default: 120 },
			{ name: 'SWING', label: 'Swing', min: 0.0, max: 1.0, step: 0.05, default: 0.6 }
		]
	},
	{
		id: 'thunder-sermon',
		file: 'thunder-sermon.html',
		title: 'Thunder Sermon',
		desc: 'Fractal lightning bolts with Lichtenberg branching and thunder shockwaves.',
		inspiration: 'The Weeknd',
		tags: ['fill', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'STRIKE_INTERVAL', label: 'Strike Interval', min: 1, max: 8, step: 0.5, default: 3 },
			{ name: 'BRANCH_COMPLEXITY', label: 'Branching', min: 0.2, max: 0.9, step: 0.05, default: 0.6 }
		]
	},
	{
		id: 'vinyl-grooves',
		file: 'vinyl-grooves.html',
		title: 'Vinyl Grooves',
		desc: 'Spinning vinyl record with visible grooves, tonearm, and needle spark.',
		inspiration: 'Laufey',
		tags: ['object', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'RPM', label: 'RPM', min: 16, max: 78, step: 1, default: 33 },
			{ name: 'GROOVE_DETAIL', label: 'Groove Detail', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'vintage-static',
		file: 'vintage-static.html',
		title: 'Vintage Static',
		desc: 'Retro TV color bars melting with VHS glitches and CRT scan lines.',
		inspiration: 'Harry Styles',
		tags: ['fill', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'GLITCH_INTENSITY', label: 'Glitch Intensity', min: 0.1, max: 1.0, step: 0.05, default: 0.5 },
			{ name: 'MELT_SPEED', label: 'Melt Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'torn-paper',
		file: 'torn-paper.html',
		title: 'Torn Paper',
		desc: 'Paper surface tearing apart with fibrous edges revealing warm volumetric light underneath, then reforming.',
		inspiration: 'Olivia Rodrigo',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'TEAR_SPEED', label: 'Tear Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'GLOW_INTENSITY', label: 'Glow Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'polaroid-burn',
		file: 'polaroid-burn.html',
		title: 'Polaroid Burn',
		desc: 'Scattered polaroid photos developing warm abstract memories, overexposing, and burning out with ember edges.',
		inspiration: 'Olivia Rodrigo',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'BURN_SPEED', label: 'Burn Speed', min: 0.2, max: 2.0, step: 0.05, default: 0.6 },
			{ name: 'PHOTO_COUNT', label: 'Photo Count', min: 3, max: 8, step: 1, default: 5 }
		]
	},
	{
		id: 'scream-wave',
		file: 'scream-wave.html',
		title: 'Scream Wave',
		desc: 'Glowing waveform building from gentle sine to distorted scream with chromatic aberration and collapse.',
		inspiration: 'Olivia Rodrigo',
		tags: ['object', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'INTENSITY', label: 'Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'WAVE_SPEED', label: 'Wave Speed', min: 0.3, max: 2.0, step: 0.1, default: 0.8 }
		]
	},
	{
		id: 'ink-calligraphy',
		file: 'ink-calligraphy.html',
		title: 'Ink Calligraphy',
		desc: 'Abstract gestural ink strokes with organic diffusion on textured paper and luminous gold leaf highlights.',
		inspiration: 'Anne Hathaway',
		tags: ['fill', 'organic'],
		technique: 'canvas-2d',
		params: [
			{ name: 'STROKE_SPEED', label: 'Stroke Speed', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'INK_DENSITY', label: 'Ink Density', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'GOLD_AMOUNT', label: 'Gold Leaf', min: 0.0, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'PALETTE', label: 'Dark Mode', min: 0.0, max: 1.0, step: 1.0, default: 0.0 }
		]
	},
	{
		id: 'velvet-spotlight',
		file: 'velvet-spotlight.html',
		title: 'Velvet Spotlight',
		desc: 'Theatrical dust particles caught in sweeping spotlight cones with volumetric rays and warm scattering haze.',
		inspiration: 'Anne Hathaway',
		tags: ['fill', 'particles'],
		technique: 'canvas-2d',
		params: [
			{ name: 'DUST_DENSITY', label: 'Dust Density', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'SWEEP_SPEED', label: 'Sweep Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'murmuration',
		file: 'murmuration.html',
		title: 'Murmuration',
		desc: 'Thousands of flocking particles forming flowing ribbons with emergent density waves against a warm twilight sky.',
		inspiration: 'Anne Hathaway',
		tags: ['fill', 'particles', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'FLOCK_SIZE', label: 'Flock Size', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'COHESION', label: 'Cohesion', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'PALETTE', label: 'Twilight', min: 0.0, max: 1.0, step: 1.0, default: 1.0 }
		]
	},
	{
		id: 'tesseract-shadow',
		file: 'tesseract-shadow.html',
		title: 'Tesseract Shadow',
		desc: '4D hypercube projected into 2D with depth-faded wireframe, axis-mapped colors, and rotation trails.',
		inspiration: 'Benedict Cumberbatch',
		tags: ['object', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'PROJECTION_DEPTH', label: 'Projection Depth', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.68 },
				{ name: 'CENTER_Y', value: 0.5 },
				{ name: 'SCALE', value: 0.7 }
			]
		}
	},
	{
		id: 'moire-interference',
		file: 'moire-interference.html',
		title: 'Moiré Interference',
		desc: 'Overlapping concentric ring patterns creating hypnotic emergent moiré interference in blue-violet and teal.',
		inspiration: 'Benedict Cumberbatch',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'RING_DENSITY', label: 'Ring Density', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'phase-transition',
		file: 'phase-transition.html',
		title: 'Phase Transition',
		desc: 'Particles oscillating between crystalline lattice order and chaotic turbulence with a traveling phase wavefront.',
		inspiration: 'Benedict Cumberbatch',
		tags: ['fill', 'particles', 'physics'],
		technique: 'canvas-2d',
		params: [
			{ name: 'WAVE_SPEED', label: 'Wave Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'PARTICLE_DENSITY', label: 'Particle Density', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'magnetic-field',
		file: 'magnetic-field.html',
		title: 'Magnetic Field',
		desc: 'Dipole field lines curving between slowly rotating poles with silk-thread glow rendering.',
		inspiration: 'Cate Blanchett',
		tags: ['fill', 'geometric', 'physics'],
		technique: 'webgl',
		params: [
			{ name: 'WAVE_SPEED', label: 'Animation Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'LINE_COUNT', label: 'Field Lines', min: 3, max: 12, step: 1, default: 8 }
		]
	},
	{
		id: 'aurora-curtain',
		file: 'aurora-curtain.html',
		title: 'Aurora Curtain',
		desc: 'Vertical luminous threads swaying like aurora borealis curtains with warm-to-cool color gradient.',
		inspiration: 'Meryl Streep',
		tags: ['fill', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'WAVE_SPEED', label: 'Wave Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'LINE_COUNT', label: 'Curtains', min: 3, max: 12, step: 1, default: 6 },
			{ name: 'AMPLITUDE', label: 'Amplitude', min: 0.2, max: 2.0, step: 0.05, default: 1.0 },
			{ name: 'ROTATION', label: 'Rotation', min: -1.57, max: 1.57, step: 0.05, default: 0.0 }
		]
	},
	{
		id: 'vortex',
		file: 'vortex.html',
		title: 'Vortex',
		desc: 'Logarithmic spiral arms converging on a drifting center with silk-thread glow and undulating perturbation.',
		inspiration: 'Lupita Nyong\'o',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'WAVE_SPEED', label: 'Animation Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'LINE_COUNT', label: 'Spiral Arms', min: 3, max: 10, step: 1, default: 6 }
		]
	},
	{
		id: 'chromatic-bloom',
		file: 'chromatic-bloom.html',
		title: 'Chromatic Bloom',
		desc: 'Luminous color orbs drifting on pure black with Gaussian glow, additive blending, film grain, and cinematic vignette.',
		inspiration: 'Lady Gaga',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'GRAIN_AMOUNT', label: 'Film Grain', min: 0.0, max: 1.0, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'lens-whisper',
		file: 'lens-whisper.html',
		title: 'Lens Whisper',
		desc: 'Anamorphic lens flares with chromatic color separation, horizontal streaks, bokeh halos, and cinematic film grain on pure black.',
		inspiration: 'Ryan Gosling',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'FLARE_SPREAD', label: 'Flare Spread', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'luminous-silt',
		file: 'luminous-silt.html',
		title: 'Luminous Silt',
		desc: 'Dense field of 18K particles creating soft color clouds through alpha accumulation over a noise-driven flow field.',
		inspiration: 'Lupita Nyong\'o',
		tags: ['fill', 'particles', 'noise'],
		technique: 'canvas-2d',
		params: [
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.6 },
			{ name: 'DENSITY', label: 'Density', min: 0.3, max: 2.0, step: 0.05, default: 1.0 }
		]
	},
	{
		id: 'synth-ribbon',
		file: 'synth-ribbon.html',
		title: 'Synth Ribbon',
		desc: 'Flowing metallic ribbons twisting through 3D space with chrome reflections in hot pink and cyan.',
		inspiration: 'Chappell Roan',
		tags: ['fill', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'RIBBON_COUNT', label: 'Ribbon Count', min: 0.5, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'TWIST_SPEED', label: 'Twist Speed', min: 0.1, max: 2.0, step: 0.05, default: 1.0 }
		]
	},
	{
		id: 'hologram-glitch',
		file: 'hologram-glitch.html',
		title: 'Hologram Glitch',
		desc: 'Abstract holographic texture with chromatic aberration, scanlines, and controlled glitch bursts.',
		inspiration: 'Daft Punk',
		tags: ['fill', 'noise'],
		technique: 'webgl',
		params: [
			{ name: 'GLITCH_INTENSITY', label: 'Glitch Intensity', min: 0.0, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'SCAN_SPEED', label: 'Scan Speed', min: 0.1, max: 2.0, step: 0.05, default: 1.0 }
		]
	},
	{
		id: 'shattered-plains',
		file: 'shattered-plains.html',
		title: 'Shattered Plains',
		desc: 'Storm-carved chasms branching through ancient sandstone plateaus with depth-revealed strata.',
		inspiration: 'Brandon Sanderson',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'CHANNEL_SPEED', label: 'Channel Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'CHANNEL_DEPTH', label: 'Channel Depth', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'GRAIN', label: 'Grain Texture', min: 0.0, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'painted-strata',
		file: 'painted-strata.html',
		title: 'Painted Strata',
		desc: 'Flowing layered bands with washi paper textures, slow tectonic folding, and fibrous grain — like a handcrafted landscape scroll.',
		inspiration: 'Laufey',
		tags: ['fill', 'noise', 'organic'],
		technique: 'webgl',
		params: [
			{ name: 'FOLD_SPEED', label: 'Fold Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'LAYER_COUNT', label: 'Layer Count', min: 8, max: 24, step: 1, default: 16 }
		]
	},
	{
		id: 'feedback-loop',
		file: 'feedback-loop.html',
		title: 'Feedback Loop',
		desc: 'Recursive video feedback tunnel with holographic color cycling, geometric seed shapes, and infinite fractal depth.',
		inspiration: 'Daft Punk',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'ZOOM_SPEED', label: 'Zoom Speed', min: 0.5, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'dither-gradient',
		file: 'dither-gradient.html',
		title: 'Dither Gradient',
		desc: 'Smooth gradients decomposed into shifting ordered dithering patterns with chromatic separation and bit-depth waves.',
		inspiration: 'Daft Punk',
		tags: ['fill', 'geometric'],
		technique: 'webgl',
		params: [
			{ name: 'DITHER_SCALE', label: 'Dither Scale', min: 0.5, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'BIT_DEPTH', label: 'Bit Depth', min: 0.3, max: 2.0, step: 0.05, default: 1.0 }
		]
	},
	{
		id: 'analog-drift',
		file: 'analog-drift.html',
		title: 'Analog Drift',
		desc: 'Morphing Lissajous figures with phosphor persistence trails, harmonic overtones, and oscilloscope grid.',
		inspiration: 'Daft Punk',
		tags: ['object', 'geometric'],
		technique: 'canvas-2d',
		params: [
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'TRAIL_LENGTH', label: 'Trail Length', min: 0.3, max: 2.0, step: 0.05, default: 1.0 }
		],
		heroConfig: {
			params: [
				{ name: 'CENTER_X', value: 0.72 },
				{ name: 'CENTER_Y', value: 0.5 },
				{ name: 'SCALE', value: 0.85 }
			]
		},
		hasArticle: true
	},
];

export function getShaderById(id: string): Shader | undefined {
	return shaders.find((s) => s.id === id);
}

export function getShaderNumber(shader: Shader): string {
	const idx = shaders.indexOf(shader);
	return String(idx + 1).padStart(2, '0');
}
