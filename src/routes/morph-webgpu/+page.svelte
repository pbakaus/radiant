<script lang="ts">
	import { onMount } from 'svelte';
	import { MorphEngine } from './engine';
	import { MorphAudio } from './audio';
	import {
		UNIFORM_FLOATS,
		U_TIME, U_ZOOM, U_HUE_SHIFT, U_RES_X, U_RES_Y,
		U_MOUSE_X, U_MOUSE_Y, U_ZOOM_CENTER_X, U_ZOOM_CENTER_Y,
		U_COLOUR_VAR_STR
	} from './presets';

	// All parameters drift continuously via low-frequency noise.
	// No presets, no segments, no boundaries. Just smooth wandering.

	const ZOOM_MIN = 1.0;
	const ZOOM_MAX = 1.15;
	const HUE_CYCLE_S = 300;
	// Colour patch variation: full cycle 20s, positive half = colourful, negative half = monotone
	const COLOUR_VAR_CYCLE_S = 20;

	const AUDIO_URL = '/audio/the-noble-hunt.mp3';

	let canvas: HTMLCanvasElement | undefined = $state();
	let rainCanvas: HTMLCanvasElement | undefined = $state(); // rain overlay
	let mouseX = 0;
	let mouseY = 0;
	let supported = $state(true);
	let audio: MorphAudio | null = null;
	let audioLoading = false;
	let showDebug = $state(false);
	let fpsText = $state('');
	let dominantPreset = $state('');
	let faded = $state(false); // true = fully faded to black/silent
	let showUI = $state(true); // attribution + key guide visibility
	let showSoundHint = $state(false); // mobile: "double tap for sound"
	let soundFeedback = $state(''); // "Sound on" / "Sound off"
	let soundFeedbackVisible = $state(false);

	const FADE_DURATION_S = 10;
	const MOBILE_CREDITS_MS = 15_000;
	const SOUND_HINT_MS = 15 * 60 * 1000; // 15 minutes
	const SOUND_FEEDBACK_MS = 5_000;

	// Grid-free drift using incommensurate sine sums.
	// No cell boundaries, infinitely smooth derivatives, zero discontinuities.
	function drift(time: number, speed: number, seed: number): number {
		const t = time * speed;
		const s = seed * 1.3717;
		const v = 0.25 * (
			Math.sin(t * 1.0 + s * 2.399) +
			Math.sin(t * 1.6180339 + s * 3.147) +
			Math.sin(t * 2.2360679 + s * 1.893) +
			Math.sin(t * 0.7320508 + s * 4.261)
		);
		return v * 0.5 + 0.5; // 0..1
	}

	// Same as drift but with a contrast curve that pushes values toward 0 and 1.
	// Spends more time at extremes, passes through the middle quickly.
	// Still infinitely smooth (composition of smooth functions).
	function driftBold(time: number, speed: number, seed: number): number {
		const v = drift(time, speed, seed);
		// Cubic contrast: steeper in the middle, flatter at extremes
		return v * v * (3 - 2 * v);
	}

	function driftRange(time: number, speed: number, seed: number, min: number, max: number): number {
		return min + drift(time, speed, seed) * (max - min);
	}

	function driftColor(
		time: number, speed: number, seed: number,
		r0: number, g0: number, b0: number,
		r1: number, g1: number, b1: number,
		buf: Float32Array, offset: number
	): void {
		const t = drift(time, speed, seed);
		buf[offset] = r0 + (r1 - r0) * t;
		buf[offset + 1] = g0 + (g1 - g0) * t;
		buf[offset + 2] = b0 + (b1 - b0) * t;
	}

	onMount(() => {
		if (!canvas) return;
		if (!navigator.gpu) { supported = false; return; }

		const buf = new Float32Array(UNIFORM_FLOATS); // 64 floats = 256 bytes
		let raf = 0;
		let engine: MorphEngine | null = null;
		let onResize: (() => void) | null = null;

		// Shared snap canvas: morph writes here after each render, rain reads from it.
		// Bridges WebGPU → WebGL without cross-context timing issues.
		const morphSnap = document.createElement('canvas');
		const morphSnapCtx = morphSnap.getContext('2d')!;

		(async () => {
			try {
				engine = await MorphEngine.create(canvas!);
			} catch (e) {
				console.error('WebGPU init failed:', e);
				supported = false;
				return;
			}

			const dpr = 1;
			let cw = Math.round(innerWidth * dpr);
			let ch = Math.round(innerHeight * dpr);
			canvas!.width = cw;
			canvas!.height = ch;

			// Only resize on actual window resize events, never in the tick loop.
			// Setting canvas.width clears the WebGPU surface → black frame.
			onResize = function() {
				const w = Math.round(innerWidth * dpr);
				const h = Math.round(innerHeight * dpr);
				if (w !== cw || h !== ch) {
					cw = w; ch = h;
					canvas!.width = w; canvas!.height = h;
				}
			}
			window.addEventListener('resize', onResize);

			const start = performance.now();

			// ── Presets as attractors ──
			// Matched to original gallery shaders. Each preset's "hero" feature is
			// at full strength; competing features are zeroed so intermediate blends
			// still read as one effect fading into another, not paint mixing.
			// Colors stay in the warm-amber family (hue_shift provides variety).
			// Integer uniforms (octaves=3, orbs=7) held constant across all presets.
			// No voronoi. Layout: [oct, decay, fmul, scale, w1, w2,
			//   orbN, orbR, orbI, orbMode, fold, foldF, norm, diff, spec, specP, fres, edge,
			//   ridge, waveStr, waveF,
			//   sR,sG,sB, mR,mG,mB, bR,bG,bB, hR,hG,hB,
			//   orbSharp, moireStr, burnStr, burnSpeed, spiralStr, spiralArms,
			//   kaleidoStr, kaleidoSeg, chromaStr, chladniStr, chladniMode]
			const P = [
				// 0: Flowing warp (fluid-amber)
				[3, .48, 2.10, .70, 3.2, 2.5,  7,.25,0,0, 0,2, 0,0,0,40,0, .6,
				 .35, 0,2,
				 .03,.025,.01, .20,.14,.07, .78,.58,.24, .95,.85,.50, 0,0, 0,.5, 0,5, 0,8, 0, 0,3],
				// 1: Orb field (chromatic-bloom)
				[3, .15, 2.0, .25, 0,0,  7,.30,1.5,1.0, 0,2, 0,0,0,40,0, 0,
				 0, 0,2,
				 .01,.008,.005, .04,.03,.02, .20,.15,.08, .80,.65,.35, 0,0, 0,.5, 0,5, 0,8, .15, 0,3],
				// 2: Silk folds (silk-cascade)
				[3, .30, 2.0, .50, .15,0,  7,.25,0,0, 1.0,3.0, 1.0,.75,.85,42,.15, 0,
				 0, 0,2,
				 .04,.025,.015, .35,.18,.10, .85,.55,.30, 1.0,.88,.65, 0,0, 0,.5, 0,5, 0,8, 0, 0,3],
				// 3: Ocean waves (bioluminescence)
				[3, .42, 2.03, .65, .8,.3,  7,.25,0,0, 0,2, .4,.25,0,40,0, 0,
				 0, .8,3.0,
				 .02,.025,.03, .08,.18,.15, .40,.60,.45, .90,.80,.55, 0,0, 0,.5, 0,5, 0,8, 0, 0,3],
				// 4: Neon metaballs (neon-drip)
				[3, .15, 2.0, .30, 0,0,  7,.28,1.8,1.0, 0,2, 0,0,0,40,0, 0,
				 0, 0,2,
				 .005,.005,.01, .03,.02,.06, .15,.08,.30, .90,.50,.80, 1.0,0, 0,.5, 0,5, 0,8, .2, 0,3],
				// 5: Moiré beats (moire-interference)
				[3, .15, 2.0, .40, 0,0,  7,.25,0,0, 0,2, 0,0,0,40,0, 0,
				 0, 0,2,
				 .01,.01,.008, .08,.06,.04, .50,.35,.15, .85,.75,.40, 0,1.0, 0,.5, 0,5, 0,8, .1, 0,3],
				// 6: Burning film (burning-film)
				[3, .48, 2.10, .65, 2.5,1.8,  7,.25,0,0, 0,2, 0,0,0,40,0, .8,
				 .4, 0,2,
				 .02,.01,.005, .25,.10,.03, .80,.45,.12, 1.0,.85,.40, 0,0, 1.0,.4, 0,5, 0,8, 0, 0,3],
				// 7: Spiral vortex (vortex)
				[3, .42, 2.05, .55, 1.0,.5,  7,.25,0,0, 0,2, 0,0,0,40,0, .2,
				 0, 0,2,
				 .02,.015,.008, .12,.08,.04, .55,.40,.18, .90,.75,.40, 0,0, 0,.5, 1.0,5, 0,8, 0, 0,3],
				// 8: Kaleidoscope mandala (kaleidoscope-runway)
				[3, .40, 2.05, .60, 1.5,.8,  7,.25,0,0, 0,2, 0,0,0,40,0, .3,
				 .2, 0,2,
				 .02,.015,.01, .15,.10,.06, .65,.45,.20, .95,.80,.45, 0,0, 0,.5, 0,5, 1.0,8, 0, 0,3],
				// 9: Chladni cymatics (chladni-resonance)
				[3, .15, 2.0, .40, 0,0,  7,.25,0,0, 0,2, 0,0,0,40,0, .2,
				 0, 0,2,
				 .01,.01,.008, .06,.05,.04, .45,.35,.20, .90,.80,.50, 0,0, 0,.5, 0,5, 0,8, 0, 1.0,3],
			];

			// Map preset array index to uniform buffer index (no voronoi)
			const MAP = [
				3, 10, 11, 12, 13, 14,       // fbm + warp
				15, 16, 17, 18,                // orbs
				19, 20, 21, 22, 23, 24, 25, 26, // fold + lighting + edge
				29, 48, 49,                    // ridge, waves (skip voronoi)
				32,33,34, 36,37,38, 40,41,42, 44,45,46, // colors
				50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60 // t2+t3 params
			];

			const N_PRESETS = P.length;
			const N_PARAMS = MAP.length;
			const PRESET_NAMES = [
				'fluid-amber', 'chromatic-bloom', 'silk-cascade', 'bioluminescence',
				'neon-drip', 'moiré', 'burning-film', 'vortex', 'kaleidoscope', 'chladni'
			];

			// Pre-allocate proximity array
			const prox = new Float64Array(N_PRESETS);

			// Debug HUD frame counter
			let debugFrameCount = 0;

			function tick(now: number) {
				const timeSec = (now - start) / 4000; // quarter speed

				// Proximity signals
				prox[0] = drift(timeSec, 0.018, 1);
				prox[1] = drift(timeSec, 0.037, 2);
				prox[4] = drift(timeSec, 0.028, 13);
				prox[5] = drift(timeSec, 0.020, 17);
				prox[6] = drift(timeSec, 0.039, 19);
				prox[7] = drift(timeSec, 0.033, 23);
				prox[8] = drift(timeSec, 0.025, 29);
				prox[9] = drift(timeSec, 0.035, 31);
				prox[2] = drift(timeSec, 0.025, 3);
				prox[3] = drift(timeSec, 0.042, 5);

				// Power-8 winner-take-all: ~80% dominance with 10 presets
				let sum = 0.001;
				for (let i = 0; i < N_PRESETS; i++) {
					const p2 = prox[i] * prox[i];
					const p4 = p2 * p2;
					prox[i] = p4 * p4;
					sum += prox[i];
				}
				for (let i = 0; i < N_PRESETS; i++) { prox[i] /= sum; }

				// Blend toward attractors
				for (let j = 0; j < N_PARAMS; j++) {
					let v = 0;
					for (let i = 0; i < N_PRESETS; i++) { v += prox[i] * P[i][j]; }
					v *= 1.0 + (drift(timeSec, 0.12, j + 60) - 0.5) * 0.06;
					buf[MAP[j]] = v;
				}

				// Voronoi always off
				buf[30] = 0; buf[31] = 4;

				// Suppress kaleido at startup — ramp 0→1 over first 60 real seconds
				// timeSec = elapsed_ms / 4000, so 60s real = timeSec 15
				const ke = Math.min(1, timeSec / 15);
				buf[56] *= ke * ke * (3 - 2 * ke); // smoothstep

				buf[27] = 0.4;
				buf[28] = 0.012;

				// Per-frame uniforms
				buf[U_TIME] = timeSec;
				// Zoom: sine-based oscillation, no modulo discontinuity
				buf[U_ZOOM] = 1.0 + (0.5 + 0.5 * Math.sin(timeSec * 0.05)) * 0.3;
				buf[U_HUE_SHIFT] = (timeSec / HUE_CYCLE_S) * Math.PI * 2;
				// Colour patch oscillation: silent (monotone) for half the cycle, peaks at ~0.9
				buf[U_COLOUR_VAR_STR] = Math.max(0, Math.sin((timeSec / COLOUR_VAR_CYCLE_S) * Math.PI * 2)) * 0.9;

				buf[U_RES_X] = cw;
				buf[U_RES_Y] = ch;
				buf[U_MOUSE_X] = mouseX * dpr;
				buf[U_MOUSE_Y] = (innerHeight - mouseY) * dpr;
				// Zoom center: slowly drifts around center, mouse nudges it gently
				const hasMouseInput = mouseX > 0 || mouseY > 0;
				const cx = hasMouseInput ? 0.3 + (mouseX / innerWidth) * 0.4 : 0.5;
				const cy = hasMouseInput ? 0.3 + (1.0 - mouseY / innerHeight) * 0.4 : 0.5;
				buf[U_ZOOM_CENTER_X] = cx + drift(timeSec, 0.025, 31) * 0.15 - 0.075;
				buf[U_ZOOM_CENTER_Y] = cy + drift(timeSec, 0.02, 32) * 0.15 - 0.075;

				audio?.update(buf);
				engine!.render(buf);
				// Snap morph frame for rain refraction (same rAF = guaranteed content)
				if (morphSnap.width !== canvas!.width || morphSnap.height !== canvas!.height) {
					morphSnap.width  = canvas!.width;
					morphSnap.height = canvas!.height;
				}
				morphSnapCtx.drawImage(canvas!, 0, 0);

				// Debug HUD: update every 30 frames to avoid reactive overhead
				if (showDebug && ++debugFrameCount >= 30) {
					debugFrameCount = 0;
					let maxW = 0, maxI = 0;
					for (let i = 0; i < N_PRESETS; i++) {
						if (prox[i] > maxW) { maxW = prox[i]; maxI = i; }
					}
					fpsText = `${engine!.gpuFps} gpu fps`;
					dominantPreset = `${PRESET_NAMES[maxI]} ${Math.round(maxW * 100)}%`;
				}
				raf = requestAnimationFrame(tick);
			}

			raf = requestAnimationFrame(tick);
		})();

		async function handleKey(e: KeyboardEvent) {
			if (e.key === ' ') {
				e.preventDefault();
				if (!audio && !audioLoading) {
					audioLoading = true;
					try {
						audio = await MorphAudio.create(AUDIO_URL);
						await audio.start();
					} catch (err) {
						console.warn('Audio init failed:', err);
						audio = null;
					}
					audioLoading = false;
				} else if (audio) {
					audio.toggle();
				}
			} else if (e.key === '=' || e.key === '+') {
				audio?.volumeUp();
			} else if (e.key === '-' || e.key === '_') {
				audio?.volumeDown();
			} else if (e.key === 'd') {
				showDebug = !showDebug;
			} else if (e.key === 'f') {
				faded = !faded;
				if (faded) {
					audio?.rampGain(0, FADE_DURATION_S);
				} else {
					audio?.rampGain(audio.volume, FADE_DURATION_S);
				}
			}
		}
		window.addEventListener('keydown', handleKey);

		// ── Rain overlay ────────────────────────────────────────────────────────
		// Full physics port from static/rain-on-glass.html: drop merging,
		// collision, trail spawning, micro-droplet clusters. Canvas 2D only
		// (no WebGL refraction). Delete this block + rainCanvas binding +
		// <canvas class="rain-canvas"> to remove entirely.
		let rainRaf = 0;
		if (rainCanvas) {
			const rc = rainCanvas;

			// ── Helpers (ported verbatim) ──
			function rnd(from = 0, to = 1, interp?: (n: number) => number): number {
				const delta = to - from;
				const fn = interp ?? ((n: number) => n);
				return from + fn(Math.random()) * delta;
			}
			function chance(c: number): boolean { return Math.random() <= c; }
			function mkCanvas(w: number, h: number): HTMLCanvasElement {
				const c = document.createElement('canvas');
				c.width = w; c.height = h; return c;
			}

			// ── Drop shape bitmaps (64×64 alpha mask + glass tint) ──
			const DROP_SIZE = 64;

			function genDropAlpha(size: number): HTMLCanvasElement {
				const c = mkCanvas(size, size);
				const ctx = c.getContext('2d')!;
				const img = ctx.createImageData(size, size);
				const cx = size / 2, cy = size / 2;
				for (let py = 0; py < size; py++) {
					for (let px = 0; px < size; px++) {
						let dx = (px - cx) / cx, dy = (py - cy) / cy;
						dy *= 1.0 + dy * 0.15;
						const dist = Math.sqrt(dx * dx + dy * dy);
						if (dist > 1.0) continue;
						const alpha = Math.max(0, 1.0 - Math.pow(dist / 0.35, 6)) * 255;
						const i = (py * size + px) * 4;
						img.data[i] = img.data[i+1] = img.data[i+2] = 255;
						img.data[i+3] = Math.round(Math.min(255, Math.max(0, alpha)));
					}
				}
				ctx.putImageData(img, 0, 0); return c;
			}

			// RGB normal map: R=vertical refraction offset, G=horizontal, B=depth
			// Neutral value = 128. Ported verbatim from generateDropColor().
			function genDropColor(size: number): HTMLCanvasElement {
				const c = mkCanvas(size, size);
				const ctx = c.getContext('2d')!;
				const img = ctx.createImageData(size, size);
				const cx = size / 2, cy = size / 2;
				for (let py = 0; py < size; py++) {
					for (let px = 0; px < size; px++) {
						let dx = (px - cx) / cx, dy = (py - cy) / cy;
						dy *= 1.0 + dy * 0.15;
						const dist = Math.sqrt(dx * dx + dy * dy);
						if (dist > 1.0) continue;
						const nx = dist > 0.001 ? dx / dist : 0;
						const ny = dist > 0.001 ? dy / dist : 0;
						const strength = dist;
						const i = (py * size + px) * 4;
						img.data[i]   = Math.max(0, Math.min(255, Math.round(ny * 60 * strength + 128)));
						img.data[i+1] = Math.max(0, Math.min(255, Math.round(nx * 60 * strength + 128)));
						img.data[i+2] = Math.round(Math.sqrt(Math.max(0, 1 - dist * dist)) * 255);
						img.data[i+3] = 255;
					}
				}
				ctx.putImageData(img, 0, 0); return c;
			}

			// Combine: alpha mask clips the normal map. 255 depth variants (ported verbatim).
			function genDropsGfx(alphaTex: HTMLCanvasElement, colorTex: HTMLCanvasElement): HTMLCanvasElement[] {
				const buf = mkCanvas(DROP_SIZE, DROP_SIZE);
				const bufCtx = buf.getContext('2d')!;
				const gfx: HTMLCanvasElement[] = [];
				for (let i = 0; i < 255; i++) {
					const drop = mkCanvas(DROP_SIZE, DROP_SIZE);
					const dropCtx = drop.getContext('2d')!;
					bufCtx.clearRect(0, 0, DROP_SIZE, DROP_SIZE);
					bufCtx.globalCompositeOperation = 'source-over';
					bufCtx.drawImage(colorTex, 0, 0, DROP_SIZE, DROP_SIZE);
					bufCtx.globalCompositeOperation = 'screen';
					bufCtx.fillStyle = `rgba(0,0,${i},1)`;
					bufCtx.fillRect(0, 0, DROP_SIZE, DROP_SIZE);
					dropCtx.globalCompositeOperation = 'source-over';
					dropCtx.drawImage(alphaTex, 0, 0, DROP_SIZE, DROP_SIZE);
					dropCtx.globalCompositeOperation = 'source-in';
					dropCtx.drawImage(buf, 0, 0, DROP_SIZE, DROP_SIZE);
					gfx.push(drop);
				}
				return gfx;
			}

			// Clearing stamp for micro-droplets layer
			function genClearStamp(): HTMLCanvasElement {
				const c = mkCanvas(128, 128);
				const ctx = c.getContext('2d')!;
				ctx.fillStyle = '#000';
				ctx.beginPath();
				ctx.arc(64, 64, 64, 0, Math.PI * 2);
				ctx.fill();
				return c;
			}

			const dropAlphaTex = genDropAlpha(DROP_SIZE);
			const dropColorTex = genDropColor(DROP_SIZE);
			const dropsGfx     = genDropsGfx(dropAlphaTex, dropColorTex);
			const clearStamp   = genClearStamp();

			// ── Physics options (ported verbatim) ──
			const opts = {
				minR: 20, maxR: 50, maxDrops: 900,
				rainChance: 0.35, rainLimit: 6,
				dropletsRate: 25, dropletsSize: [2, 4] as [number, number],
				dropletsCleaningRadiusMultiplier: 0.28,
				globalTimeScale: 1, trailRate: 1,
				autoShrink: true, spawnArea: [-0.1, 0.95] as [number, number],
				trailScaleRange: [0.25, 0.35] as [number, number],
				collisionRadius: 0.45, collisionRadiusIncrease: 0.0002,
				dropFallMultiplier: 1, collisionBoostMultiplier: 0.05, collisionBoost: 1,
			};

			// ── State ──
			interface RDrop {
				x: number; y: number; r: number;
				spreadX: number; spreadY: number;
				momentum: number; momentumX: number;
				lastSpawn: number; nextSpawn: number;
				parent: RDrop | null; isNew: boolean;
				killed: boolean; shrink: number;
			}

			let rdW = 0, rdH = 0, rdScale = 1;
			let rdCanvas: HTMLCanvasElement, rdCtx: CanvasRenderingContext2D;
			let dropletsCanvas: HTMLCanvasElement, dropletsCtx: CanvasRenderingContext2D;
			const dropletsPixelDensity = 1;
			let dropletsCounter = 0;
			let drops: RDrop[] = [];
			let rdLastRender: number | null = null;

			const deltaR = () => opts.maxR - opts.minR;
			const area   = () => (rdW * rdH) / rdScale;
			const areaMul = () => Math.sqrt(area() / (1024 * 768));

			function drawRdDrop(ctx: CanvasRenderingContext2D, drop: RDrop) {
				if (dropsGfx.length === 0) return;
				const { x, y, r, spreadX, spreadY } = drop;
				const scaleX = 1, scaleY = 1.5;
				let d = Math.max(0, Math.min(1, ((r - opts.minR) / deltaR()) * 0.9));
				d *= 1 / (((spreadX + spreadY) * 0.5) + 1);
				const idx = Math.floor(d * (dropsGfx.length - 1));
				ctx.globalAlpha = 1;
				ctx.globalCompositeOperation = 'source-over';
				ctx.drawImage(
					dropsGfx[idx],
					(x - r * scaleX * (spreadX + 1)) * rdScale,
					(y - r * scaleY * (spreadY + 1)) * rdScale,
					(r * 2 * scaleX * (spreadX + 1)) * rdScale,
					(r * 2 * scaleY * (spreadY + 1)) * rdScale,
				);
			}

			function drawDroplet(x: number, y: number, r: number) {
				drawRdDrop(dropletsCtx, {
					x: x * dropletsPixelDensity, y: y * dropletsPixelDensity,
					r: r * dropletsPixelDensity,
					spreadX: 0, spreadY: 0,
					momentum: 0, momentumX: 0, lastSpawn: 0, nextSpawn: 0,
					parent: null, isNew: false, killed: false, shrink: 0,
				});
			}

			function clearDroplets(x: number, y: number, r = 30) {
				dropletsCtx.globalCompositeOperation = 'destination-out';
				dropletsCtx.drawImage(
					clearStamp,
					(x - r) * dropletsPixelDensity * rdScale,
					(y - r) * dropletsPixelDensity * rdScale,
					r * 2 * dropletsPixelDensity * rdScale,
					r * 2 * dropletsPixelDensity * rdScale * 1.5,
				);
			}

			function createDrop(o: Partial<RDrop>): RDrop | null {
				if (drops.length >= opts.maxDrops * areaMul()) return null;
				return {
					x: 0, y: 0, r: 0, spreadX: 0, spreadY: 0,
					momentum: 0, momentumX: 0, lastSpawn: 0, nextSpawn: 0,
					parent: null, isNew: true, killed: false, shrink: 0,
					...o,
				};
			}

			// Rain amount: oscillates 0.1→1.1 over a 10s sine cycle
			let rainAmount = 0.6;
			const RAIN_CYCLE_S = 10_000;

			function updateRain(ts: number): RDrop[] {
				rainAmount = 0.1 + 0.5 + 0.5 * Math.sin((Date.now() / RAIN_CYCLE_S) * Math.PI * 2);
				const result: RDrop[] = [];
				const limit = opts.rainLimit * ts * areaMul() * rainAmount;
				let count = 0;
				while (chance(opts.rainChance * ts * areaMul() * rainAmount) && count < limit) {
					count++;
					const r = rnd(opts.minR, opts.maxR, (n) => Math.pow(n, 3));
					const d = createDrop({
						x: rnd(rdW / rdScale), y: rnd((rdH / rdScale) * opts.spawnArea[0], (rdH / rdScale) * opts.spawnArea[1]),
						r, momentum: 1 + (r - opts.minR) * 0.1 + rnd(2),
						spreadX: 1.5, spreadY: 1.5,
					});
					if (d) result.push(d);
				}
				return result;
			}

			function updateDroplets(ts: number) {
				dropletsCounter += opts.dropletsRate * ts * areaMul() * rainAmount;
				let total = Math.floor(dropletsCounter);
				dropletsCounter -= total;
				while (total > 0) {
					if (chance(0.8) && total >= 4) {
						const clusterSize = Math.min(total, 4 + Math.floor(Math.random() * 5));
						const cx = rnd(rdW / rdScale), cy = rnd(rdH / rdScale);
						const spread = 4 + Math.random() * 8;
						for (let ci = 0; ci < clusterSize; ci++) {
							const angle = Math.random() * Math.PI * 2;
							drawDroplet(cx + Math.cos(angle) * Math.random() * spread, cy + Math.sin(angle) * Math.random() * spread,
								rnd(opts.dropletsSize[0], opts.dropletsSize[1], (n) => n * n));
						}
						total -= clusterSize;
					} else {
						drawDroplet(rnd(rdW / rdScale), rnd(rdH / rdScale),
							rnd(opts.dropletsSize[0], opts.dropletsSize[1], (n) => n * n));
						total--;
					}
				}
				rdCtx.drawImage(dropletsCanvas, 0, 0, rdW, rdH);
			}

			function updateDrops(ts: number) {
				let newDrops: RDrop[] = [];
				updateDroplets(ts);
				newDrops = newDrops.concat(updateRain(ts));

				drops.sort((a, b) => {
					const va = a.y * (rdW / rdScale) + a.x;
					const vb = b.y * (rdW / rdScale) + b.x;
					return va > vb ? 1 : va < vb ? -1 : 0;
				});

				for (let i = 0; i < drops.length; i++) {
					const drop = drops[i];
					if (drop.killed) continue;

					if (chance((drop.r - opts.minR * opts.dropFallMultiplier) * (0.1 / deltaR()) * ts))
						drop.momentum += rnd((drop.r / opts.maxR) * 4);
					if (opts.autoShrink && drop.r <= opts.minR && chance(0.05 * ts))
						drop.shrink += 0.01;
					drop.r -= drop.shrink * ts;
					if (drop.r <= 0) { drop.killed = true; continue; }

					// Trail spawning
					drop.lastSpawn += drop.momentum * ts * opts.trailRate;
					if (drop.lastSpawn > drop.nextSpawn) {
						const trail = createDrop({
							x: drop.x + rnd(-drop.r, drop.r) * 0.1,
							y: drop.y - drop.r * 0.01,
							r: drop.r * rnd(opts.trailScaleRange[0], opts.trailScaleRange[1]),
							spreadY: drop.momentum * 0.1, parent: drop,
						});
						if (trail) {
							newDrops.push(trail);
							drop.r *= Math.pow(0.97, ts);
							drop.lastSpawn = 0;
							drop.nextSpawn = rnd(opts.minR, opts.maxR) - drop.momentum * 2 * opts.trailRate + (opts.maxR - drop.r);
						}
					}

					drop.spreadX *= Math.pow(0.4, ts);
					drop.spreadY *= Math.pow(0.7, ts);

					const moved = drop.momentum > 0;
					if (moved && !drop.killed) {
						drop.y += drop.momentum * opts.globalTimeScale;
						drop.x += drop.momentumX * opts.globalTimeScale;
						if (drop.y > rdH / rdScale + drop.r) drop.killed = true;
					}

					// Collision detection + merging
					if ((moved || drop.isNew) && !drop.killed) {
						const end = Math.min(i + 70, drops.length);
						for (let j = i + 1; j < end; j++) {
							const d2 = drops[j];
							if (drop === d2 || drop.r <= d2.r || drop.parent === d2 || d2.parent === drop || d2.killed) continue;
							const dx = d2.x - drop.x, dy = d2.y - drop.y;
							const dist = Math.sqrt(dx * dx + dy * dy);
							if (dist < (drop.r + d2.r) * (opts.collisionRadius + drop.momentum * opts.collisionRadiusIncrease * ts)) {
								const targetR = Math.min(opts.maxR, Math.sqrt((Math.PI * drop.r * drop.r + Math.PI * d2.r * d2.r * 0.8) / Math.PI));
								drop.r = targetR;
								drop.momentumX += dx * 0.1;
								drop.spreadX = drop.spreadY = 0;
								d2.killed = true;
								drop.momentum = Math.max(d2.momentum, Math.min(40, drop.momentum + targetR * opts.collisionBoostMultiplier + opts.collisionBoost));
							}
						}
					}
					drop.isNew = false;
					drop.momentum -= Math.max(1, opts.minR * 0.5 - drop.momentum) * 0.1 * ts;
					if (drop.momentum < 0) drop.momentum = 0;
					drop.momentumX *= Math.pow(0.7, ts);

					if (!drop.killed) {
						newDrops.push(drop);
						if (moved && opts.dropletsRate > 0)
							clearDroplets(drop.x, drop.y, drop.r * opts.dropletsCleaningRadiusMultiplier);
						drawRdDrop(rdCtx, drop);
					}
				}
				drops = newDrops;
			}

			function initRd(w: number, h: number, scale: number) {
				rdW = w; rdH = h; rdScale = scale;
				rdCanvas = mkCanvas(rdW, rdH);
				rdCtx = rdCanvas.getContext('2d')!;
				dropletsCanvas = mkCanvas(rdW * dropletsPixelDensity, rdH * dropletsPixelDensity);
				dropletsCtx = dropletsCanvas.getContext('2d')!;
				drops = []; dropletsCounter = 0; rdLastRender = null;
			}

			// ── WebGL refraction renderer ──
			// Refracts morphSnap (written by morph's own rAF) through the drop normal map.

			// Opaque: WebGL owns the full frame — blurred bg everywhere, sharp refracted fg through drops.
			const gl = rc.getContext('webgl', { alpha: false, antialias: false })!;

			const vertSrc = `
				attribute vec2 a_pos;
				void main() { gl_Position = vec4(a_pos, 0.0, 1.0); }
			`;
			const fragSrc = `
				precision mediump float;
				uniform sampler2D u_waterMap;
				uniform sampler2D u_textureFg;
				uniform sampler2D u_textureBg;
				uniform vec2  u_resolution;
				uniform float u_minRefraction;
				uniform float u_refractionDelta;
				uniform float u_brightness;
				uniform float u_alphaMultiply;
				uniform float u_alphaSubtract;

				vec2 tc() {
					return vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y) / u_resolution;
				}
				void main() {
					vec2  uv   = tc();
					vec2  px   = 1.0 / u_resolution;
					vec4  cur  = texture2D(u_waterMap, uv);
					float d    = cur.b;
					float a    = clamp(cur.a * u_alphaMultiply - u_alphaSubtract, 0.0, 1.0);
					vec4  bg   = texture2D(u_textureBg, uv);

					if (a <= 0.0) { gl_FragColor = bg; return; }

					// Drop shadow: sample water map offset downward, darken bg at rim
					float shadowA = clamp(texture2D(u_waterMap, uv + vec2(0.0, -d * 6.0 * px.y)).a
					                      * u_alphaMultiply - (u_alphaSubtract + 0.5), 0.0, 1.0) * 0.35;
					bg = mix(bg, vec4(0.0, 0.0, 0.0, 1.0), shadowA);

					// Refracted foreground through drop lens
					vec2  refr    = (vec2(cur.g, cur.r) - 0.5) * 2.0;
					vec2  refrPos = uv + px * refr * (u_minRefraction + d * u_refractionDelta);
					vec4  fg      = vec4(texture2D(u_textureFg, refrPos).rgb * u_brightness, a);

					float ia = 1.0 - fg.a;
					gl_FragColor = vec4(fg.rgb * fg.a + bg.rgb * ia, 1.0);
				}
			`;

			function compileShader(type: number, src: string): WebGLShader {
				const s = gl.createShader(type)!;
				gl.shaderSource(s, src); gl.compileShader(s); return s;
			}
			const prog = gl.createProgram()!;
			gl.attachShader(prog, compileShader(gl.VERTEX_SHADER,   vertSrc));
			gl.attachShader(prog, compileShader(gl.FRAGMENT_SHADER, fragSrc));
			gl.linkProgram(prog); gl.useProgram(prog);

			const quadBuf = gl.createBuffer()!;
			gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
			gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, -1,1, 1,-1, 1,1]), gl.STATIC_DRAW);
			const aPos = gl.getAttribLocation(prog, 'a_pos');
			gl.enableVertexAttribArray(aPos);
			gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

			const uLoc = {
				resolution:      gl.getUniformLocation(prog, 'u_resolution'),
				minRefraction:   gl.getUniformLocation(prog, 'u_minRefraction'),
				refractionDelta: gl.getUniformLocation(prog, 'u_refractionDelta'),
				brightness:      gl.getUniformLocation(prog, 'u_brightness'),
				alphaMultiply:   gl.getUniformLocation(prog, 'u_alphaMultiply'),
				alphaSubtract:   gl.getUniformLocation(prog, 'u_alphaSubtract'),
				waterMap:        gl.getUniformLocation(prog, 'u_waterMap'),
				textureFg:       gl.getUniformLocation(prog, 'u_textureFg'),
				textureBg:       gl.getUniformLocation(prog, 'u_textureBg'),
			};

			function initTex(unit: number, source?: TexImageSource): WebGLTexture {
				const tex = gl.createTexture()!;
				gl.activeTexture(gl.TEXTURE0 + unit);
				gl.bindTexture(gl.TEXTURE_2D, tex);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
				gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
				if (source) gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
				return tex;
			}

			const waterTex = initTex(0);  // drop normal map — updated each frame
			const fgTex    = initTex(1);  // full-res morphSnap — refracted through drop lens
			const bgTex    = initTex(2);  // 1/8-scale morphSnap — blurred bg between drops

			// Small canvas for cheap blur: drawImage at 1/8 scale, bilinear upscale = free gaussian
			const blurCanvas = mkCanvas(2, 2);
			const blurCtx    = blurCanvas.getContext('2d')!;

			// ── Resize + init ──
			function resizeRain() {
				rc.width  = innerWidth;
				rc.height = innerHeight;
				gl.viewport(0, 0, rc.width, rc.height);
				blurCanvas.width  = Math.max(1, Math.floor(rc.width  / 8));
				blurCanvas.height = Math.max(1, Math.floor(rc.height / 8));
				initRd(rc.width, rc.height, 1);
			}
			resizeRain();
			window.addEventListener('resize', resizeRain);

			// ── Render loop ──
			function tickRain() {
				rainRaf = requestAnimationFrame(tickRain);
				if (document.hidden || !canvas) return;

				// Physics tick
				rdCtx.clearRect(0, 0, rdW, rdH);
				const now = Date.now();
				if (rdLastRender == null) rdLastRender = now;
				let ts = Math.min((now - rdLastRender) / (1000 / 60), 1.1) * opts.globalTimeScale;
				rdLastRender = now;
				updateDrops(ts);

				// Upload water map (drop normal map)
				gl.activeTexture(gl.TEXTURE0);
				gl.bindTexture(gl.TEXTURE_2D, waterTex);
				gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, rdCanvas);

				if (morphSnap.width > 1) {
					// fg: full-res — sharp through drop lens
					gl.activeTexture(gl.TEXTURE1);
					gl.bindTexture(gl.TEXTURE_2D, fgTex);
					gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, morphSnap);

					// bg: 1/8-scale — blurred, shows between drops (frosted glass feel)
					blurCtx.drawImage(morphSnap, 0, 0, blurCanvas.width, blurCanvas.height);
					gl.activeTexture(gl.TEXTURE2);
					gl.bindTexture(gl.TEXTURE_2D, bgTex);
					gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, blurCanvas);
				}

				// Uniforms
				gl.useProgram(prog);
				gl.uniform2f(uLoc.resolution,      rc.width, rc.height);
				gl.uniform1f(uLoc.minRefraction,    716.8); // 256 * 2.8 (max refraction)
				gl.uniform1f(uLoc.refractionDelta,  716.8);
				gl.uniform1f(uLoc.brightness,       1.04);
				gl.uniform1f(uLoc.alphaMultiply,    6.0);
				gl.uniform1f(uLoc.alphaSubtract,    3.0);
				gl.uniform1i(uLoc.waterMap,   0);
				gl.uniform1i(uLoc.textureFg,  1);
				gl.uniform1i(uLoc.textureBg,  2);

				gl.bindBuffer(gl.ARRAY_BUFFER, quadBuf);
				gl.drawArrays(gl.TRIANGLES, 0, 6);
			}
			rainRaf = requestAnimationFrame(tickRain);
		}
		// ── End rain overlay ─────────────────────────────────────────────────

		// ── Mobile vs desktop UI behaviour ──────────────────────────────────
		const isMobile = 'ontouchstart' in window;
		let cursorTimer: ReturnType<typeof setTimeout>;
		let soundFeedbackTimer: ReturnType<typeof setTimeout>;
		let cleanupCursor = () => {};

		if (isMobile) {
			// Credits visible for 15s then fade
			setTimeout(() => { showUI = false; }, MOBILE_CREDITS_MS);
			// Sound hint appears immediately, fades after 15 min
			showSoundHint = true;
			setTimeout(() => { showSoundHint = false; }, SOUND_HINT_MS);

			// Double-tap to toggle audio
			let lastTap = 0;
			async function handleTouchEnd() {
				const now = Date.now();
				if (now - lastTap < 350) {
					lastTap = 0;
					showSoundHint = false;
					if (!audio && !audioLoading) {
						audioLoading = true;
						try {
							audio = await MorphAudio.create(AUDIO_URL);
							await audio.start();
							soundFeedback = 'Sound on';
						} catch { audio = null; soundFeedback = 'Sound off'; }
						audioLoading = false;
					} else if (audio) {
						soundFeedback = audio.toggle() ? 'Sound on' : 'Sound off';
					}
					clearTimeout(soundFeedbackTimer);
					soundFeedbackVisible = true;
					soundFeedbackTimer = setTimeout(() => { soundFeedbackVisible = false; }, SOUND_FEEDBACK_MS);
				} else {
					lastTap = now;
				}
			}
			window.addEventListener('touchend', handleTouchEnd);
			cleanupCursor = () => window.removeEventListener('touchend', handleTouchEnd);
		} else {
			// Desktop: hide cursor + UI after 3s inactivity
			const CURSOR_HIDE_MS = 3000;
			function resetCursorTimer() {
				showUI = true;
				document.body.classList.remove('cursor-hidden');
				clearTimeout(cursorTimer);
				cursorTimer = setTimeout(() => {
					showUI = false;
					document.body.classList.add('cursor-hidden');
				}, CURSOR_HIDE_MS);
			}
			window.addEventListener('mousemove', resetCursorTimer);
			resetCursorTimer();
			cleanupCursor = () => {
				window.removeEventListener('mousemove', resetCursorTimer);
				clearTimeout(cursorTimer);
				document.body.classList.remove('cursor-hidden');
			};
		}

		return () => {
			cancelAnimationFrame(raf);
			cancelAnimationFrame(rainRaf);
			window.removeEventListener('keydown', handleKey);
			cleanupCursor();
			clearTimeout(soundFeedbackTimer);
			if (onResize) window.removeEventListener('resize', onResize);
			audio?.destroy();
			engine?.destroy();
		};
	});
</script>

<svelte:window
	onkeydown={(e) => { if (e.key === 'Escape') history.back(); }}
	onmousemove={(e) => { mouseX = e.clientX; mouseY = e.clientY; }}
	ontouchmove={(e) => { if (e.touches[0]) { mouseX = e.touches[0].clientX; mouseY = e.touches[0].clientY; } }}
/>

<svelte:head>
	<title>Morph — Radiant</title>
	<style>
		nav { display: none !important; }
		body { overflow: hidden; }
	</style>
</svelte:head>

{#if !supported}
	<div class="fallback">
		<p>WebGPU is not available in this browser.</p>
		<p class="subtle">Try Chrome or Edge.</p>
		<a href="/morph">Try WebGL version</a>
	</div>
{/if}

<canvas class="gl-canvas" bind:this={canvas}></canvas>
<canvas class="rain-canvas" bind:this={rainCanvas}></canvas>
<div class="fade-overlay" class:faded></div>

{#if showDebug}
	<div class="debug-hud">
		<span>{fpsText}</span>
		<span>{dominantPreset}</span>
	</div>
{/if}

<div class="attribution" class:ui-hidden={!showUI}>
	<a href="https://github.com/boxabirds/radiant" target="_blank" rel="noopener">By Julian Harris</a>
	<span class="sep">|</span>
	<a href="https://radiant-shaders.com" target="_blank" rel="noopener">Based on Radiant</a>
</div>
<div class="key-guide" class:ui-hidden={!showUI}>
	<span><kbd>f</kbd> fade</span>
	<span class="sep">·</span>
	<span><kbd>space</kbd> sound</span>
	<span class="sep">·</span>
	<span><kbd>-</kbd><kbd>=</kbd> volume</span>
</div>

{#if showSoundHint}
	<div class="sound-hint">
		<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
			<path d="M11 5L6 9H2v6h4l5 4V5z"/>
			<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
			<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
		</svg>
		Double tap for sound
	</div>
{/if}

{#if soundFeedbackVisible}
	<div class="sound-feedback">
		{#if soundFeedback === 'Sound on'}
			<svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2">
				<path d="M11 5L6 9H2v6h4l5 4V5z"/>
				<path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>
				<path d="M19.07 4.93a10 10 0 0 1 0 14.14"/>
			</svg>
		{:else}
			<svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.2">
				<path d="M11 5L6 9H2v6h4l5 4V5z"/>
				<line x1="23" y1="9" x2="17" y2="15"/>
				<line x1="17" y1="9" x2="23" y2="15"/>
			</svg>
		{/if}
		<span>{soundFeedback}</span>
	</div>
{/if}

<style>
	.gl-canvas {
		position: fixed;
		inset: 0;
		width: 100vw;
		height: 100vh;
		z-index: 9999;
		cursor: none;
		display: block;
	}

	.fallback {
		position: fixed;
		inset: 0;
		z-index: 99999;
		background: #0a0a0a;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 12px;
		color: rgba(232, 224, 216, 0.8);
		font-size: 16px;
		font-weight: 300;
	}
	.fallback .subtle { font-size: 13px; color: rgba(232, 224, 216, 0.4); }
	.fallback a { color: #c8956c; text-decoration: underline; margin-top: 8px; }

	.attribution {
		position: fixed;
		top: 20px;
		right: 20px;
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 12px;
		font-weight: 300;
		letter-spacing: 0.03em;
		color: rgba(232, 224, 216, 0.5);
		background: rgba(10, 10, 10, 0.4);
		padding: 6px 12px;
		border-radius: 20px;
		z-index: 10003;
		pointer-events: auto;
		opacity: 1;
		transition: opacity 0.4s ease;
	}

	.attribution.ui-hidden {
		opacity: 0;
		pointer-events: none;
	}

	.attribution a {
		color: inherit;
		text-decoration: none;
		cursor: pointer;
	}
	.attribution a:hover { color: rgba(232, 224, 216, 0.9); }

	.attribution .sep { opacity: 0.35; }

	.key-guide {
		position: fixed;
		bottom: 20px;
		left: 50%;
		transform: translateX(-50%);
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 11px;
		font-weight: 300;
		letter-spacing: 0.04em;
		color: rgba(232, 224, 216, 0.4);
		background: rgba(10, 10, 10, 0.4);
		padding: 5px 14px;
		border-radius: 20px;
		z-index: 10003;
		white-space: nowrap;
		opacity: 1;
		transition: opacity 0.4s ease;
	}

	.key-guide.ui-hidden {
		opacity: 0;
	}

	.key-guide kbd {
		font-family: inherit;
		font-size: 10px;
		background: rgba(232, 224, 216, 0.12);
		border: 1px solid rgba(232, 224, 216, 0.15);
		border-radius: 4px;
		padding: 1px 5px;
	}

	.key-guide .sep { opacity: 0.3; }

	.sound-hint {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		z-index: 10003;
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: 14px;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: rgba(232, 224, 216, 0.6);
		background: rgba(10, 10, 10, 0.5);
		padding: 12px 20px;
		border-radius: 30px;
		pointer-events: none;
		animation: hint-pulse 3s ease-in-out infinite;
	}

	@keyframes hint-pulse {
		0%, 100% { opacity: 0.5; }
		50% { opacity: 1; }
	}

	.sound-feedback {
		position: fixed;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		z-index: 10004;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 12px;
		color: rgba(232, 224, 216, 0.9);
		pointer-events: none;
		animation: feedback-fade 5s ease forwards;
	}

	.sound-feedback span {
		font-size: 18px;
		font-weight: 300;
		letter-spacing: 0.08em;
	}

	@keyframes feedback-fade {
		0% { opacity: 0; transform: translate(-50%, -50%) scale(0.9); }
		15% { opacity: 1; transform: translate(-50%, -50%) scale(1); }
		70% { opacity: 1; }
		100% { opacity: 0; }
	}

	.rain-canvas {
		position: fixed;
		inset: 0;
		width: 100vw;
		height: 100vh;
		z-index: 10000;
		pointer-events: none;
		/* Opaque — owns the full frame. Morph canvas hidden beneath. */
	}
	:global(body:has(.rain-canvas)) .gl-canvas {
		visibility: hidden;
	}

	:global(body.cursor-hidden),
	:global(body.cursor-hidden *) {
		cursor: none !important;
	}

	.fade-overlay {
		position: fixed;
		inset: 0;
		z-index: 10002;
		background: #000;
		opacity: 0;
		pointer-events: none;
		transition: opacity 10s linear;
	}
	.fade-overlay.faded {
		opacity: 1;
	}

	.debug-hud {
		position: fixed;
		bottom: 16px;
		left: 16px;
		z-index: 10001;
		display: flex;
		flex-direction: column;
		gap: 2px;
		font: 11px/1.3 monospace;
		color: rgba(232, 224, 216, 0.5);
		pointer-events: none;
	}
</style>
