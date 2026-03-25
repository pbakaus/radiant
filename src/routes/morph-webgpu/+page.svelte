<script lang="ts">
	import { onMount } from 'svelte';
	import { MorphEngine } from './engine';
	import { MorphAudio } from './audio';
	import {
		UNIFORM_FLOATS,
		U_TIME, U_ZOOM, U_HUE_SHIFT, U_RES_X, U_RES_Y,
		U_MOUSE_X, U_MOUSE_Y, U_ZOOM_CENTER_X, U_ZOOM_CENTER_Y
	} from './presets';

	// All parameters drift continuously via low-frequency noise.
	// No presets, no segments, no boundaries. Just smooth wandering.

	const ZOOM_MIN = 1.0;
	const ZOOM_MAX = 1.15;
	const HUE_CYCLE_S = 300;

	const AUDIO_URL = '/audio/the-noble-hunt.mp3';

	let canvas: HTMLCanvasElement | undefined = $state();
	let mouseX = 0;
	let mouseY = 0;
	let supported = $state(true);
	let audio: MorphAudio | null = null;
	let audioLoading = false;
	let showDebug = $state(false);
	let fpsText = $state('');
	let dominantPreset = $state('');

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
			// Also notify the engine so it can recreate the half-res texture.
			onResize = function() {
				const w = Math.round(innerWidth * dpr);
				const h = Math.round(innerHeight * dpr);
				if (w !== cw || h !== ch) {
					cw = w; ch = h;
					canvas!.width = w; canvas!.height = h;
					engine?.resize(w, h);
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
			//   kaleidoStr, kaleidoSeg, chromaStr, chladniStr, chladniMode,
			//   curtainStr, curtainCount]
			const P = [
				// 0: Flowing warp (fluid-amber)
				[3, .48, 2.10, .70, 3.2, 2.5,  7,.25,0,0, 0,2, 0,0,0,40,0, .6,
				 .35, 0,2,
				 .03,.025,.01, .20,.14,.07, .78,.58,.24, .95,.85,.50, 0,0, 0,.5, 0,5, 0,8, 0, 0,3, 0,6],
				// 1: Orb field (chromatic-bloom)
				[3, .15, 2.0, .25, 0,0,  7,.30,1.5,1.0, 0,2, 0,0,0,40,0, 0,
				 0, 0,2,
				 .01,.008,.005, .04,.03,.02, .20,.15,.08, .80,.65,.35, 0,0, 0,.5, 0,5, 0,8, .15, 0,3, 0,6],
				// 2: Silk folds (silk-cascade)
				[3, .30, 2.0, .50, .15,0,  7,.25,0,0, 1.0,3.0, 1.0,.75,.85,42,.15, 0,
				 0, 0,2,
				 .04,.025,.015, .35,.18,.10, .85,.55,.30, 1.0,.88,.65, 0,0, 0,.5, 0,5, 0,8, 0, 0,3, 0,6],
				// 3: Ocean waves (bioluminescence)
				[3, .42, 2.03, .65, .8,.3,  7,.25,0,0, 0,2, .4,.25,0,40,0, 0,
				 0, .8,3.0,
				 .02,.025,.03, .08,.18,.15, .40,.60,.45, .90,.80,.55, 0,0, 0,.5, 0,5, 0,8, 0, 0,3, 0,6],
				// 4: Neon metaballs (neon-drip)
				[3, .15, 2.0, .30, 0,0,  7,.28,1.8,1.0, 0,2, 0,0,0,40,0, 0,
				 0, 0,2,
				 .005,.005,.01, .03,.02,.06, .15,.08,.30, .90,.50,.80, 1.0,0, 0,.5, 0,5, 0,8, .2, 0,3, 0,6],
				// 5: Moiré beats (moire-interference)
				[3, .15, 2.0, .40, 0,0,  7,.25,0,0, 0,2, 0,0,0,40,0, 0,
				 0, 0,2,
				 .01,.01,.008, .08,.06,.04, .50,.35,.15, .85,.75,.40, 0,1.0, 0,.5, 0,5, 0,8, .1, 0,3, 0,6],
				// 6: Burning film (burning-film)
				[3, .48, 2.10, .65, 2.5,1.8,  7,.25,0,0, 0,2, 0,0,0,40,0, .8,
				 .4, 0,2,
				 .02,.01,.005, .25,.10,.03, .80,.45,.12, 1.0,.85,.40, 0,0, 1.0,.4, 0,5, 0,8, 0, 0,3, 0,6],
				// 7: Spiral vortex (vortex)
				[3, .42, 2.05, .55, 1.0,.5,  7,.25,0,0, 0,2, 0,0,0,40,0, .2,
				 0, 0,2,
				 .02,.015,.008, .12,.08,.04, .55,.40,.18, .90,.75,.40, 0,0, 0,.5, 1.0,5, 0,8, 0, 0,3, 0,6],
				// 8: Kaleidoscope mandala (kaleidoscope-runway)
				[3, .40, 2.05, .60, 1.5,.8,  7,.25,0,0, 0,2, 0,0,0,40,0, .3,
				 .2, 0,2,
				 .02,.015,.01, .15,.10,.06, .65,.45,.20, .95,.80,.45, 0,0, 0,.5, 0,5, 1.0,8, 0, 0,3, 0,6],
				// 9: Chladni cymatics (chladni-resonance)
				[3, .15, 2.0, .40, 0,0,  7,.25,0,0, 0,2, 0,0,0,40,0, .2,
				 0, 0,2,
				 .01,.01,.008, .06,.05,.04, .45,.35,.20, .90,.80,.50, 0,0, 0,.5, 0,5, 0,8, 0, 1.0,3, 0,6],
				// 10: Aurora threads (aurora-curtain)
				[3, .15, 2.0, .35, 0,0,  7,.25,0,0, 0,2, 0,0,0,40,0, 0,
				 0, 0,2,
				 .008,.008,.005, .04,.06,.05, .25,.50,.35, .70,.90,.65, 0,0, 0,.5, 0,5, 0,8, 0, 0,3, 1.0,7],
			];

			// Map preset array index to uniform buffer index (no voronoi)
			const MAP = [
				3, 10, 11, 12, 13, 14,       // fbm + warp
				15, 16, 17, 18,                // orbs
				19, 20, 21, 22, 23, 24, 25, 26, // fold + lighting + edge
				29, 48, 49,                    // ridge, waves (skip voronoi)
				32,33,34, 36,37,38, 40,41,42, 44,45,46, // colors
				50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62 // t2+t3 params
			];

			const N_PRESETS = P.length;
			const N_PARAMS = MAP.length;
			const PRESET_NAMES = [
				'fluid-amber', 'chromatic-bloom', 'silk-cascade', 'bioluminescence',
				'neon-drip', 'moiré', 'burning-film', 'vortex', 'kaleidoscope', 'chladni',
				'aurora'
			];

			// Pre-allocate proximity array
			const prox = new Float64Array(N_PRESETS);

			// Debug HUD frame counter
			let debugFrameCount = 0;
			let firstFrame = true;

			function tick(now: number) {
				const timeSec = (now - start) / 4000; // quarter speed

				// Proximity signals
				prox[0] = drift(timeSec, 0.018, 1);
				prox[1] = drift(timeSec, 0.037, 2);
				prox[4] = drift(timeSec, 0.028, 13);
				prox[5] = drift(timeSec, 0.020, 17);
				prox[6] = drift(timeSec, 0.039, 19);
				prox[7] = drift(timeSec, 0.033, 23);
				prox[8] = drift(timeSec, 0.015, 29);
				prox[9] = drift(timeSec, 0.035, 31);
				prox[10] = drift(timeSec, 0.022, 37);
				prox[2] = drift(timeSec, 0.025, 3);
				prox[3] = drift(timeSec, 0.042, 5);

				// Power-8 winner-take-all: ~80% dominance with 11 presets
				let sum = 0.001;
				for (let i = 0; i < N_PRESETS; i++) {
					const p2 = prox[i] * prox[i];
					const p4 = p2 * p2;
					prox[i] = p4 * p4;
					sum += prox[i];
				}
				for (let i = 0; i < N_PRESETS; i++) { prox[i] /= sum; }

				// Blend toward attractors with temporal smoothing.
				// Power-8 gives sharp identity but fast leader swaps —
				// exponential smoothing (~1s transition) absorbs the jumps.
				const SMOOTH = 0.04; // ~25 frames to 63%, ~75 frames to 95%
				for (let j = 0; j < N_PARAMS; j++) {
					let v = 0;
					for (let i = 0; i < N_PRESETS; i++) { v += prox[i] * P[i][j]; }
					v *= 1.0 + (drift(timeSec, 0.12, j + 60) - 0.5) * 0.06;
					if (firstFrame) { buf[MAP[j]] = v; } else { buf[MAP[j]] += (v - buf[MAP[j]]) * SMOOTH; }
				}
				firstFrame = false;

				// Voronoi always off
				buf[30] = 0; buf[31] = 4;

				buf[27] = 0.4;
				buf[28] = 0.012;

				// Per-frame uniforms
				buf[U_TIME] = timeSec;
				// Zoom: sine-based oscillation, no modulo discontinuity
				buf[U_ZOOM] = 1.0 + (0.5 + 0.5 * Math.sin(timeSec * 0.05)) * 0.3;
				buf[U_HUE_SHIFT] = (timeSec / HUE_CYCLE_S) * Math.PI * 2;

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
			}
		}
		window.addEventListener('keydown', handleKey);

		return () => {
			cancelAnimationFrame(raf);
			window.removeEventListener('keydown', handleKey);
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

{#if showDebug}
	<div class="debug-hud">
		<span>{fpsText}</span>
		<span>{dominantPreset}</span>
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
