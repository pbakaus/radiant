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

export interface Shader {
	id: string;
	file: string;
	title: string;
	desc: string;
	tags: ShaderTag[];
	params?: ShaderParam[];
	inspiration?: string;
}

export const shaders: Shader[] = [
	{
		id: 'flow-field',
		file: '01-flow-field.html',
		title: 'Flow Field with Particle Trails',
		desc: 'Particles following Perlin noise currents with warm amber trails.',
		tags: ['fill', 'particles', 'noise'],
		params: [
			{ name: 'SPEED', label: 'Flow Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.2 },
			{ name: 'NOISE_SCALE', label: 'Pattern Scale', min: 0.001, max: 0.01, step: 0.0005, default: 0.0025 }
		]
	},
	{
		id: 'topographic',
		file: '02-topographic.html',
		title: 'Topographic Contour Map',
		desc: 'Living terrain map with marching squares isolines and elevation labels.',
		tags: ['fill', 'noise', 'geometric'],
		params: [
			{ name: 'NUM_CONTOURS', label: 'Contour Density', min: 4, max: 30, step: 1, default: 14 },
			{ name: 'TIME_SPEED', label: 'Animation Speed', min: 0.0, max: 0.5, step: 0.01, default: 0.15 }
		]
	},
	{
		id: 'generative-tree',
		file: '04-generative-tree.html',
		title: 'Generative Branching Tree',
		desc: 'L-system inspired tree with continuous growth and regrowth cycles.',
		tags: ['object', 'organic'],
		params: [
			{ name: 'GROWTH_SPEED_BASE', label: 'Growth Speed', min: 0.003, max: 0.025, step: 0.001, default: 0.008 },
			{ name: 'MAX_DEPTH', label: 'Branch Depth', min: 4, max: 14, step: 1, default: 9 }
		]
	},
	{
		id: 'strange-attractor',
		file: '05-strange-attractor.html',
		title: 'Strange Attractor (Lorenz)',
		desc: 'Lorenz system with 3D projection, rotation, and glowing particle trails.',
		tags: ['object', 'particles', 'physics'],
		params: [
			{ name: 'STEPS_PER_FRAME', label: 'Simulation Speed', min: 1, max: 12, step: 1, default: 4 },
			{ name: 'TRAIL_LENGTH', label: 'Trail Length', min: 500, max: 4000, step: 100, default: 2000 },
			{ name: 'RHO', label: 'Attractor Shape', min: 15, max: 50, step: 0.5, default: 28 }
		]
	},
	{
		id: 'pendulum-wave',
		file: '06-pendulum-wave.html',
		title: 'Pendulum Wave',
		desc: 'Physics-based pendulum wave creating emergent interference patterns.',
		tags: ['object', 'physics'],
		params: [
			{ name: 'NUM_PENDULUMS', label: 'Pendulum Count', min: 6, max: 40, step: 1, default: 20 },
			{ name: 'CYCLE_DURATION', label: 'Cycle Duration', min: 20, max: 120, step: 5, default: 60 }
		]
	},
	{
		id: 'phyllotaxis',
		file: '07-phyllotaxis.html',
		title: 'Phyllotaxis Spiral',
		desc: "Golden angle spiral with Fibonacci lattice connections.",
		tags: ['object', 'geometric', 'organic'],
		params: [
			{ name: 'MAX_POINTS', label: 'Point Count', min: 500, max: 5000, step: 100, default: 2000 },
			{ name: 'SPREAD', label: 'Spiral Tightness', min: 0.003, max: 0.015, step: 0.0005, default: 0.0065 }
		]
	},
	{
		id: 'fluid-amber',
		file: '09-fluid-amber.html',
		title: 'Fluid Amber',
		desc: 'Domain-warped simplex noise with layered organic flow and warm palette.',
		tags: ['fill', 'noise', 'organic'],
		params: [
			{ name: 'timeScale', label: 'Animation Speed', min: 0.0, max: 0.5, step: 0.01, default: 0.15 },
			{ name: 'ampDecay', label: 'Detail Level', min: 0.3, max: 0.7, step: 0.01, default: 0.48 }
		]
	},
	{
		id: 'champagne-fizz',
		file: '10-champagne-fizz.html',
		title: 'Champagne Fizz',
		desc: 'Effervescent bubbles rising with wobble physics, refractive highlights, and sparkle bursts.',
		inspiration: 'Sabrina Carpenter',
		tags: ['fill', 'particles', 'physics'],
		params: [
			{ name: 'BUBBLE_RATE', label: 'Bubble Rate', min: 1, max: 10, step: 1, default: 3 },
			{ name: 'RISE_SPEED', label: 'Rise Speed', min: 0.5, max: 4.0, step: 0.1, default: 1.5 }
		]
	},
	{
		id: 'resonant-strings',
		file: 'proposal-laufey-1.html',
		title: 'Resonant Strings',
		desc: 'Vibrating cello strings with standing wave harmonics, overtone interference, and rosin dust particles.',
		inspiration: 'Laufey',
		tags: ['object', 'physics'],
		params: [
			{ name: 'HARMONIC_COUNT', label: 'Harmonics', min: 1, max: 12, step: 1, default: 5 },
			{ name: 'VIBRATION_SPEED', label: 'Vibration Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'chladni-resonance',
		file: 'proposal-laufey-3.html',
		title: 'Chladni Resonance',
		desc: 'Sand patterns forming on a vibrating plate, morphing between harmonic modes with golden glow.',
		inspiration: 'Laufey',
		tags: ['object', 'geometric', 'physics'],
		params: [
			{ name: 'MODE_SPEED', label: 'Mode Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'COMPLEXITY', label: 'Complexity', min: 2, max: 8, step: 1, default: 5 }
		]
	},
	{
		id: 'bossa-nova-drift',
		file: 'proposal-laufey-5.html',
		title: 'Bossa Nova Drift',
		desc: 'Syncopated sine wave interference creating drifting moiré patterns with polyrhythmic timing.',
		inspiration: 'Laufey',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'WAVE_COMPLEXITY', label: 'Wave Complexity', min: 2, max: 8, step: 1, default: 5 },
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.4 }
		]
	},
	{
		id: 'disco-refraction',
		file: '12-disco-refraction.html',
		title: 'Disco Refraction',
		desc: 'Prismatic ring interference patterns with spectral color splitting and rhythmic pulsation.',
		inspiration: 'Dua Lipa',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'PULSE_SPEED', label: 'Pulse Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'RING_COUNT', label: 'Ring Sources', min: 1, max: 6, step: 1, default: 3 }
		]
	},
	{
		id: 'ethereal-submersion',
		file: '13-spider-silk.html',
		title: 'Ethereal Submersion',
		desc: 'Dark underwater dreamscape with floating tendrils, bioluminescent accents, and caustic light.',
		inspiration: 'Billie Eilish',
		tags: ['fill', 'noise', 'organic'],
		params: [
			{ name: 'DEPTH', label: 'Depth', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'GLOW_INTENSITY', label: 'Glow Intensity', min: 0.2, max: 1.5, step: 0.05, default: 0.8 }
		]
	},
	{
		id: 'eras',
		file: '14-eras.html',
		title: 'Eras',
		desc: 'Prismatic crystalline fractals blending multiple color palettes through a kaleidoscopic prism.',
		inspiration: 'Taylor Swift',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'COMPLEXITY', label: 'Complexity', min: 0.5, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'COLOR_SHIFT', label: 'Color Shift', min: 0.2, max: 3.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'golden-throne',
		file: '15-golden-throne.html',
		title: 'Golden Throne',
		desc: 'Sacred geometry mandala with golden ratio spirals and counter-rotating layers.',
		inspiration: 'Beyoncé',
		tags: ['object', 'geometric'],
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.0, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'COMPLEXITY', label: 'Complexity', min: 2, max: 8, step: 1, default: 5 }
		]
	},
	{
		id: 'tidal-resonance',
		file: '16-tidal-resonance.html',
		title: 'Tidal Resonance',
		desc: 'Wave interference patterns building to crescendos with height-mapped amber rendering.',
		inspiration: 'Adele',
		tags: ['fill', 'physics'],
		params: [
			{ name: 'WAVE_SPEED', label: 'Wave Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'WAVE_SOURCES', label: 'Wave Sources', min: 2, max: 7, step: 1, default: 4 }
		]
	},
	{
		id: 'tropical-heat',
		file: '17-tropical-heat.html',
		title: 'Tropical Heat',
		desc: 'Heat shimmer distortion with chromatic aberration and tropical color blooms.',
		inspiration: 'Bad Bunny',
		tags: ['fill', 'noise'],
		params: [
			{ name: 'HEAT_INTENSITY', label: 'Heat Intensity', min: 0.2, max: 2.5, step: 0.1, default: 1.0 },
			{ name: 'COLOR_VIBRANCY', label: 'Color Vibrancy', min: 0.3, max: 1.5, step: 0.05, default: 0.8 }
		]
	},
	{
		id: 'celestial-drift',
		file: '18-celestial-drift.html',
		title: 'Celestial Drift',
		desc: 'Luminous bodies in gravitational orbit with fading trails and star field.',
		inspiration: 'SZA',
		tags: ['fill', 'particles', 'physics'],
		params: [
			{ name: 'GRAVITY_STRENGTH', label: 'Gravity', min: 0.2, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'TRAIL_LENGTH', label: 'Trail Length', min: 50, max: 500, step: 25, default: 200 }
		]
	},
	{
		id: 'diamond-caustics',
		file: '19-diamond-caustics.html',
		title: 'Diamond Caustics',
		desc: 'Light refracting through rotating diamond facets casting prismatic caustic patterns.',
		inspiration: 'Rihanna',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'BRILLIANCE', label: 'Brilliance', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'metamorphosis',
		file: '20-metamorphosis.html',
		title: 'Metamorphosis',
		desc: 'Raymarched metaballs continuously merging and splitting with liquid-metal surface.',
		inspiration: 'Lady Gaga',
		tags: ['object', 'organic'],
		params: [
			{ name: 'MORPH_SPEED', label: 'Morph Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'BLOB_COUNT', label: 'Blob Count', min: 2, max: 6, step: 1, default: 4 }
		]
	},
	{
		id: 'silk-groove',
		file: '21-silk-groove.html',
		title: 'Silk Groove',
		desc: 'Flowing silk ribbons with specular highlights and cloth-like wave animation.',
		inspiration: 'Bruno Mars',
		tags: ['fill', 'organic'],
		params: [
			{ name: 'FLOW_SPEED', label: 'Flow Speed', min: 0.2, max: 2.0, step: 0.05, default: 0.8 },
			{ name: 'WAVE_AMPLITUDE', label: 'Wave Amplitude', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'after-hours',
		file: '22-after-hours.html',
		title: 'After Hours',
		desc: 'Cinematic city bokeh lights with depth layers, rain streaks, and lens flares.',
		inspiration: 'The Weeknd',
		tags: ['fill', 'particles'],
		params: [
			{ name: 'BOKEH_COUNT', label: 'Bokeh Count', min: 20, max: 120, step: 5, default: 60 },
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'shatter',
		file: '23-shatter.html',
		title: 'Shatter',
		desc: 'Glass fracturing from impact with Voronoi fragments that separate and reassemble.',
		inspiration: 'Olivia Rodrigo',
		tags: ['fill', 'geometric', 'physics'],
		params: [
			{ name: 'SHATTER_SPEED', label: 'Shatter Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'FRAGMENT_COUNT', label: 'Fragment Count', min: 15, max: 80, step: 5, default: 40 }
		]
	},
	{
		id: 'cloud-kingdom',
		file: '24-cloud-kingdom.html',
		title: 'Cloud Kingdom',
		desc: 'Raymarched volumetric clouds with warm internal glow drifting through dark sky.',
		inspiration: 'Ariana Grande',
		tags: ['fill', 'noise', 'organic'],
		params: [
			{ name: 'CLOUD_SPEED', label: 'Cloud Speed', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'CLOUD_DENSITY', label: 'Cloud Density', min: 0.2, max: 1.0, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'ink-bloom',
		file: '25-ink-bloom.html',
		title: 'Ink Bloom',
		desc: 'Symmetric inkblot patterns bleeding and branching with Rorschach symmetry.',
		inspiration: 'Post Malone',
		tags: ['fill', 'organic'],
		params: [
			{ name: 'SPREAD_SPEED', label: 'Spread Speed', min: 0.5, max: 4.0, step: 0.1, default: 1.5 },
			{ name: 'INK_DENSITY', label: 'Ink Density', min: 0.3, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'verse-particles',
		file: '26-verse-particles.html',
		title: 'Verse Particles',
		desc: 'Particles converging to form words then dissolving back into cosmic chaos.',
		inspiration: 'Kendrick Lamar',
		tags: ['fill', 'particles'],
		params: [
			{ name: 'MORPH_SPEED', label: 'Morph Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'PARTICLE_COUNT', label: 'Particle Count', min: 1000, max: 8000, step: 500, default: 3000 }
		]
	},
	{
		id: 'rhinestone-cascade',
		file: '27-rhinestone-cascade.html',
		title: 'Rhinestone Cascade',
		desc: 'Faceted crystal particles cascading with specular flashes and prismatic sparkle.',
		inspiration: 'Dolly Parton',
		tags: ['fill', 'particles', 'physics'],
		params: [
			{ name: 'SPARKLE_RATE', label: 'Sparkle Rate', min: 1, max: 15, step: 1, default: 5 },
			{ name: 'FALL_SPEED', label: 'Fall Speed', min: 0.3, max: 2.5, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'moss-and-bone',
		file: '28-moss-and-bone.html',
		title: 'Moss & Bone',
		desc: 'Cellular automata moss growth spreading across ancient stone with earthy palette.',
		inspiration: 'Hozier',
		tags: ['fill', 'organic'],
		params: [
			{ name: 'GROWTH_RATE', label: 'Growth Rate', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'SEED_COUNT', label: 'Seed Points', min: 1, max: 8, step: 1, default: 4 }
		]
	},
	{
		id: 'neon-revival',
		file: '29-neon-revival.html',
		title: 'Neon Revival',
		desc: 'Flickering neon sign with electrical buzz, dripping light particles, and wall reflections.',
		inspiration: 'Chappell Roan',
		tags: ['object', 'particles'],
		params: [
			{ name: 'FLICKER_RATE', label: 'Flicker Rate', min: 0.1, max: 1.0, step: 0.05, default: 0.5 },
			{ name: 'GLOW_SPREAD', label: 'Glow Spread', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'rubber-reality',
		file: '30-rubber-reality.html',
		title: 'Rubber Reality',
		desc: 'Elastic grid mesh deformed by traveling attractors with spring physics and snap-back.',
		inspiration: 'Jim Carrey',
		tags: ['fill', 'physics', 'geometric'],
		params: [
			{ name: 'ELASTICITY', label: 'Elasticity', min: 0.3, max: 2.5, step: 0.1, default: 1.0 },
			{ name: 'DISTORTION_POINTS', label: 'Distortion Points', min: 1, max: 6, step: 1, default: 3 }
		]
	},
	{
		id: 'magma-core',
		file: '31-magma-core.html',
		title: 'Magma Core',
		desc: 'Volcanic eruption with thermal lava particles, cooling physics, and magma pool.',
		inspiration: 'Jack Black',
		tags: ['object', 'particles', 'physics'],
		params: [
			{ name: 'ERUPTION_FORCE', label: 'Eruption Force', min: 0.3, max: 2.5, step: 0.1, default: 1.0 },
			{ name: 'ERUPTION_INTERVAL', label: 'Eruption Interval', min: 2, max: 15, step: 1, default: 6 }
		]
	},
	{
		id: 'clockwork-mind',
		file: '32-clockwork-mind.html',
		title: 'Clockwork Mind',
		desc: 'Interlocking precision gears with metallic rendering and mathematically correct meshing.',
		inspiration: 'Robert Downey Jr.',
		tags: ['object', 'geometric'],
		params: [
			{ name: 'ROTATION_SPEED', label: 'Rotation Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'GEAR_DETAIL', label: 'Gear Detail', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'shifting-veils',
		file: '33-shifting-veils.html',
		title: 'Shifting Veils',
		desc: 'Layered translucent noise curtains that morph and reveal patterns underneath.',
		inspiration: 'Meryl Streep',
		tags: ['fill', 'noise', 'organic'],
		params: [
			{ name: 'LAYER_SPEED', label: 'Layer Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'LAYER_COUNT', label: 'Layer Count', min: 3, max: 7, step: 1, default: 5 }
		]
	},
	{
		id: 'crystal-lattice',
		file: '34-crystal-lattice.html',
		title: 'Crystal Lattice',
		desc: 'Procedural crystal formations growing with faceted 3D lighting and prismatic sparkle.',
		inspiration: 'Anne Hathaway',
		tags: ['object', 'geometric'],
		params: [
			{ name: 'GROWTH_SPEED', label: 'Growth Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'BRANCH_DENSITY', label: 'Branch Density', min: 0.2, max: 0.8, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'morning-fog',
		file: '35-morning-fog.html',
		title: 'Morning Fog',
		desc: 'Volumetric light shafts cutting through layered fog with illuminated dust motes.',
		inspiration: 'Timothée Chalamet',
		tags: ['fill', 'particles', 'noise'],
		params: [
			{ name: 'FOG_DENSITY', label: 'Fog Density', min: 0.2, max: 1.0, step: 0.05, default: 0.6 },
			{ name: 'LIGHT_INTENSITY', label: 'Light Intensity', min: 0.3, max: 1.5, step: 0.05, default: 0.8 }
		]
	},
	{
		id: 'kaleidoscope-runway',
		file: '36-kaleidoscope-runway.html',
		title: 'Kaleidoscope Runway',
		desc: 'Fashion-inspired kaleidoscopic tessellations with symmetric mirror segments.',
		inspiration: 'Zendaya',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'SYMMETRY', label: 'Symmetry', min: 4, max: 16, step: 2, default: 8 },
			{ name: 'PATTERN_SPEED', label: 'Pattern Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'digital-rain',
		file: '37-digital-rain.html',
		title: 'Digital Rain',
		desc: 'Warm amber character columns dissolving into zen ripples at the water surface.',
		inspiration: 'Keanu Reeves',
		tags: ['fill', 'particles'],
		params: [
			{ name: 'FALL_SPEED', label: 'Fall Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'COLUMN_DENSITY', label: 'Column Density', min: 0.3, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'ember-garden',
		file: '38-ember-garden.html',
		title: 'Ember Garden',
		desc: 'Glowing embers rising from smoldering ground with thermal cooling and heat shimmer.',
		inspiration: 'Florence Pugh',
		tags: ['fill', 'particles', 'physics'],
		params: [
			{ name: 'EMBER_RATE', label: 'Ember Rate', min: 1, max: 12, step: 1, default: 4 },
			{ name: 'HEAT_GLOW', label: 'Heat Glow', min: 0.2, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'desert-mirage',
		file: '39-desert-mirage.html',
		title: 'Desert Mirage',
		desc: 'Layered parallax sand dunes with heat shimmer and wind-blown particles.',
		inspiration: 'Pedro Pascal',
		tags: ['fill', 'noise'],
		params: [
			{ name: 'WIND_SPEED', label: 'Wind Speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'SHIMMER_INTENSITY', label: 'Shimmer', min: 0.2, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'neon-drive',
		file: '40-neon-drive.html',
		title: 'Neon Drive',
		desc: 'Rain-slicked neon road stretching to a vanishing point with approaching headlights.',
		inspiration: 'Ryan Gosling',
		tags: ['fill', 'particles'],
		params: [
			{ name: 'DRIVE_SPEED', label: 'Drive Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'RAIN_INTENSITY', label: 'Rain Intensity', min: 0.1, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'liquid-gold',
		file: '41-liquid-gold.html',
		title: 'Liquid Gold',
		desc: 'Molten metal flow with surface tension, metallic PBR shading, and golden reflections.',
		inspiration: 'Margot Robbie',
		tags: ['fill', 'noise', 'organic'],
		params: [
			{ name: 'FLOW_SPEED', label: 'Flow Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.4 },
			{ name: 'VISCOSITY', label: 'Viscosity', min: 0.2, max: 1.0, step: 0.05, default: 0.6 }
		]
	},
	{
		id: 'dark-nebula',
		file: '42-dark-nebula.html',
		title: 'Dark Nebula',
		desc: 'Cosmic dust clouds with hidden forming stars and parallax depth.',
		inspiration: 'Oscar Isaac',
		tags: ['fill', 'noise'],
		params: [
			{ name: 'DUST_DENSITY', label: 'Dust Density', min: 0.2, max: 1.0, step: 0.05, default: 0.6 },
			{ name: 'STAR_BRIGHTNESS', label: 'Star Brightness', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'aurora-veil',
		file: '43-aurora-veil.html',
		title: 'Aurora Veil',
		desc: 'Northern lights ribbons flowing above hexagonal ice crystal formations.',
		inspiration: 'Cate Blanchett',
		tags: ['fill', 'noise', 'organic'],
		params: [
			{ name: 'AURORA_SPEED', label: 'Aurora Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'AURORA_INTENSITY', label: 'Intensity', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'chain-reaction',
		file: '44-chain-reaction.html',
		title: 'Chain Reaction',
		desc: 'Nuclear fission-inspired exponential particle cascade with shockwave rings.',
		inspiration: 'Cillian Murphy',
		tags: ['object', 'particles', 'physics'],
		params: [
			{ name: 'REACTION_SPEED', label: 'Reaction Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'SPLIT_GENERATIONS', label: 'Generations', min: 4, max: 9, step: 1, default: 7 }
		]
	},
	{
		id: 'bioluminescence',
		file: '45-bioluminescence.html',
		title: 'Bioluminescence',
		desc: 'Deep sea jellyfish pulsing with bioluminescent glow and drifting plankton.',
		inspiration: 'Sydney Sweeney',
		tags: ['fill', 'organic', 'particles'],
		params: [
			{ name: 'PULSE_SPEED', label: 'Pulse Speed', min: 0.2, max: 2.0, step: 0.1, default: 0.8 },
			{ name: 'PLANKTON_COUNT', label: 'Plankton Count', min: 50, max: 500, step: 25, default: 200 }
		]
	},
	{
		id: 'gothic-filigree',
		file: '46-gothic-filigree.html',
		title: 'Gothic Filigree',
		desc: 'Ornate fractal lace scrollwork growing from corners with dark metallic rendering.',
		inspiration: 'Jenna Ortega',
		tags: ['fill', 'organic', 'geometric'],
		params: [
			{ name: 'GROWTH_SPEED', label: 'Growth Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'CURL_TIGHTNESS', label: 'Curl Tightness', min: 0.3, max: 1.0, step: 0.05, default: 0.7 }
		]
	},
	{
		id: 'contrail-weave',
		file: '47-contrail-weave.html',
		title: 'Contrail Weave',
		desc: 'Aircraft contrails painting sweeping arcs across a warm sunset sky.',
		inspiration: 'Glen Powell',
		tags: ['fill', 'particles'],
		params: [
			{ name: 'FLIGHT_SPEED', label: 'Flight Speed', min: 0.3, max: 2.5, step: 0.1, default: 1.0 },
			{ name: 'TRAIL_FADE', label: 'Trail Fade', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'laser-precision',
		file: '48-laser-precision.html',
		title: 'Laser Precision',
		desc: 'Laser beams tracing geometric patterns with spark particles and intersection flares.',
		inspiration: 'Ana de Armas',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'DRAW_SPEED', label: 'Draw Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'LINE_BRIGHTNESS', label: 'Brightness', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'deep-current',
		file: '49-deep-current.html',
		title: 'Deep Current',
		desc: 'Underwater ocean currents with kelp fronds, rising bubbles, and caustic light.',
		inspiration: 'Jason Momoa',
		tags: ['fill', 'particles', 'organic'],
		params: [
			{ name: 'CURRENT_SPEED', label: 'Current Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'KELP_COUNT', label: 'Kelp Count', min: 2, max: 8, step: 1, default: 5 }
		]
	},
	{
		id: 'woven-radiance',
		file: '50-woven-radiance.html',
		title: 'Woven Radiance',
		desc: 'African textile-inspired weave patterns with vibrant kente cloth geometry.',
		inspiration: 'Lupita Nyong\'o',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'WEAVE_SPEED', label: 'Weave Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 },
			{ name: 'COLOR_RICHNESS', label: 'Color Richness', min: 0.3, max: 1.0, step: 0.05, default: 0.8 }
		]
	},
	{
		id: 'jazz-chaos',
		file: '51-jazz-chaos.html',
		title: 'Jazz Chaos',
		desc: 'Syncopated particle groups moving in rhythm with swing timing and solos.',
		inspiration: 'Jeff Goldblum',
		tags: ['fill', 'particles'],
		params: [
			{ name: 'TEMPO', label: 'Tempo', min: 60, max: 200, step: 5, default: 120 },
			{ name: 'SWING', label: 'Swing', min: 0.0, max: 1.0, step: 0.05, default: 0.6 }
		]
	},
	{
		id: 'firefly-meadow',
		file: '52-firefly-meadow.html',
		title: 'Firefly Meadow',
		desc: 'Gentle fireflies blinking in synchrony above a dark summer meadow.',
		inspiration: 'Tom Hanks',
		tags: ['fill', 'particles', 'organic'],
		params: [
			{ name: 'FIREFLY_COUNT', label: 'Firefly Count', min: 15, max: 80, step: 5, default: 45 },
			{ name: 'BLINK_SPEED', label: 'Blink Speed', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'tectonic',
		file: '53-tectonic.html',
		title: 'Tectonic',
		desc: 'Shifting tectonic plates revealing glowing magma in the cracks between.',
		inspiration: 'Viola Davis',
		tags: ['fill', 'physics', 'geometric'],
		params: [
			{ name: 'DRIFT_SPEED', label: 'Drift Speed', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'MAGMA_HEAT', label: 'Magma Heat', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'thunder-sermon',
		file: '54-thunder-sermon.html',
		title: 'Thunder Sermon',
		desc: 'Fractal lightning bolts with Lichtenberg branching and thunder shockwaves.',
		inspiration: 'Denzel Washington',
		tags: ['fill', 'physics'],
		params: [
			{ name: 'STRIKE_INTERVAL', label: 'Strike Interval', min: 1, max: 8, step: 0.5, default: 3 },
			{ name: 'BRANCH_COMPLEXITY', label: 'Branching', min: 0.2, max: 0.9, step: 0.05, default: 0.6 }
		]
	},
	{
		id: 'noir-smoke',
		file: '55-noir-smoke.html',
		title: 'Noir Smoke',
		desc: 'Film noir smoke curling through angled light beams with chiaroscuro contrast.',
		inspiration: 'Scarlett Johansson',
		tags: ['fill', 'noise'],
		params: [
			{ name: 'SMOKE_DENSITY', label: 'Smoke Density', min: 0.2, max: 1.0, step: 0.05, default: 0.7 },
			{ name: 'LIGHT_ANGLE', label: 'Light Angle', min: 5, max: 45, step: 1, default: 25 }
		]
	},
	{
		id: 'playful-caustics',
		file: '56-playful-caustics.html',
		title: 'Playful Caustics',
		desc: 'Dancing water caustic light patterns on a warm sunlit surface.',
		inspiration: 'Emma Stone',
		tags: ['fill', 'noise'],
		params: [
			{ name: 'WATER_SPEED', label: 'Water Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'CAUSTIC_SCALE', label: 'Caustic Scale', min: 0.5, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'wildfire',
		file: '57-wildfire.html',
		title: 'Wildfire',
		desc: 'Cellular automata fire propagation across terrain with wind influence.',
		inspiration: 'Jennifer Lawrence',
		tags: ['fill', 'physics', 'organic'],
		params: [
			{ name: 'SPREAD_SPEED', label: 'Spread Speed', min: 0.3, max: 3.0, step: 0.1, default: 1.0 },
			{ name: 'WIND_STRENGTH', label: 'Wind Strength', min: 0.0, max: 1.0, step: 0.05, default: 0.5 }
		]
	},
	{
		id: 'vinyl-grooves',
		file: '58-vinyl-grooves.html',
		title: 'Vinyl Grooves',
		desc: 'Spinning vinyl record with visible grooves, tonearm, and needle spark.',
		inspiration: 'Austin Butler',
		tags: ['object', 'geometric'],
		params: [
			{ name: 'RPM', label: 'RPM', min: 16, max: 78, step: 1, default: 33 },
			{ name: 'GROOVE_DETAIL', label: 'Groove Detail', min: 0.3, max: 2.0, step: 0.1, default: 1.0 }
		]
	},
	{
		id: 'vintage-static',
		file: '59-vintage-static.html',
		title: 'Vintage Static',
		desc: 'Retro TV color bars melting with VHS glitches and CRT scan lines.',
		inspiration: 'Harry Styles',
		tags: ['fill', 'geometric'],
		params: [
			{ name: 'GLITCH_INTENSITY', label: 'Glitch Intensity', min: 0.1, max: 1.0, step: 0.05, default: 0.5 },
			{ name: 'MELT_SPEED', label: 'Melt Speed', min: 0.1, max: 1.5, step: 0.05, default: 0.5 }
		]
	}
];

export function getShaderById(id: string): Shader | undefined {
	return shaders.find((s) => s.id === id);
}

export function getShaderNumber(shader: Shader): string {
	const idx = shaders.indexOf(shader);
	return String(idx + 1).padStart(2, '0');
}
