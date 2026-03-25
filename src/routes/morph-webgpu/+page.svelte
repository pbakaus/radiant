<script lang="ts">
	import { onMount } from 'svelte';
	import { MorphEngine } from './engine';
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

	let canvas: HTMLCanvasElement | undefined = $state();
	let mouseX = 0;
	let mouseY = 0;
	let supported = $state(true);

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

		const buf = new Float32Array(UNIFORM_FLOATS);
		let raf = 0;
		let engine: MorphEngine | null = null;

		(async () => {
			try {
				engine = await MorphEngine.create(canvas!);
			} catch (e) {
				console.error('WebGPU init failed:', e);
				supported = false;
				return;
			}

			const dpr = 1;
			let cw = 0, ch = 0;
			function resize() {
				const w = Math.round(innerWidth * dpr);
				const h = Math.round(innerHeight * dpr);
				if (w !== cw || h !== ch) {
					cw = w; ch = h;
					canvas!.width = w; canvas!.height = h;
				}
			}
			resize();
			window.addEventListener('resize', resize);

			const start = performance.now();

			// Pure continuous drift. No segments, no modes, no floor().
			// Parameters are grouped by shared oscillators so they correlate.
			// Three slow "master" signals drive structure, orbs, and lighting.
			// Everything is sine-sum based — infinitely smooth, zero discontinuities.

			function tick(now: number) {
				const timeSec = (now - start) / 1000;

				// Three master signals with contrast curve — spend time at 0 and 1,
				// not stuck in the middle. Different speeds so they decorrelate.
				const mWarp = driftBold(timeSec, 0.05, 1);  // warp dominance
				const mOrbs = driftBold(timeSec, 0.038, 2); // orb dominance
				const mFold = driftBold(timeSec, 0.03, 3);  // fold+lighting dominance

				// When warp is dominant, suppress orbs and fold (and vice versa)
				// This ensures distinct visual phases instead of everything at 50%
				const warpFade = mWarp * (1.0 - 0.5 * mOrbs) * (1.0 - 0.5 * mFold);
				const orbsFade = mOrbs * (1.0 - 0.5 * mWarp);
				const foldFade = mFold * (1.0 - 0.5 * mWarp);

				// FBM
				buf[3]  = 2.0 + warpFade * 1.0;                  // octaves: 2-3
				buf[10] = 0.48 + drift(timeSec, 0.03, 10) * 0.06;
				buf[11] = 2.0 + drift(timeSec, 0.02, 11) * 0.1;

				// Warp: scale LOW when warp HIGH → big shapes
				buf[12] = 0.5 + (1.0 - warpFade) * 0.6;         // scale: 0.5-1.1
				buf[13] = 0.3 + warpFade * 4.0;                  // warp1: 0.3-4.3
				buf[14] = warpFade * 3.0;                         // warp2: 0-3.0

				// Orbs
				buf[15] = orbsFade * 6.0;                         // count: 0-6
				buf[16] = 0.20 + orbsFade * 0.15;                // radius: 0.20-0.35
				buf[17] = orbsFade * 1.2;                         // intensity: 0-1.2
				buf[18] = orbsFade * 0.85;                        // color_mode: 0-0.85

				// Fold + lighting
				buf[19] = foldFade * 0.9;                         // fold_str: 0-0.9
				buf[20] = 2.0 + foldFade * 1.5;                  // fold_freq: 2-3.5
				buf[21] = foldFade * 0.9;                         // normal_str: 0-0.9
				buf[22] = foldFade * 0.7;                         // diffuse_str: 0-0.7
				buf[23] = foldFade * 0.8;                         // spec_str: 0-0.8
				buf[24] = 30.0 + foldFade * 30.0;                // spec_power: 30-60
				buf[25] = foldFade * 0.2;                         // fresnel: 0-0.2

				// Edge glow: warp + not orbs
				buf[26] = warpFade * (1.0 - orbsFade) * 0.6;

				buf[27] = 0.4;
				buf[28] = 0.012;

				// Colors: three distinct palettes blended by dominance
				// Warp → deep teal/cyan, Orbs → violet/blue, Fold → magenta/rose
				const w = warpFade, o = orbsFade, f = foldFade;
				const total = Math.max(w + o + f, 0.01);
				const nw = w / total, no = o / total, nf = f / total;

				// Shadow
				buf[32] = nw * 0.02 + no * 0.02 + nf * 0.04;
				buf[33] = nw * 0.04 + no * 0.01 + nf * 0.01;
				buf[34] = nw * 0.05 + no * 0.04 + nf * 0.03;
				// Mid
				buf[36] = nw * 0.05 + no * 0.12 + nf * 0.35;
				buf[37] = nw * 0.18 + no * 0.06 + nf * 0.08;
				buf[38] = nw * 0.22 + no * 0.30 + nf * 0.18;
				// Bright
				buf[40] = nw * 0.15 + no * 0.45 + nf * 0.85;
				buf[41] = nw * 0.65 + no * 0.30 + nf * 0.35;
				buf[42] = nw * 0.60 + no * 0.80 + nf * 0.55;
				// Hot
				buf[44] = nw * 0.40 + no * 0.70 + nf * 1.00;
				buf[45] = nw * 0.90 + no * 0.55 + nf * 0.70;
				buf[46] = nw * 0.85 + no * 0.95 + nf * 0.80;

				// Per-frame uniforms
				buf[U_TIME] = timeSec;
				// Continuous slow zoom in (resets periodically to avoid precision loss)
				const zoomCycle = (timeSec * 0.008) % 1.0; // 0→1 over ~125s
				buf[U_ZOOM] = 1.0 + zoomCycle * 0.4; // 1.0→1.4
				buf[U_HUE_SHIFT] = (timeSec / HUE_CYCLE_S) * Math.PI * 2;

				resize();
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

				engine!.render(buf);
				raf = requestAnimationFrame(tick);
			}

			raf = requestAnimationFrame(tick);
		})();

		return () => {
			cancelAnimationFrame(raf);
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

<div class="morph-ui">
	<a href="/gallery/all" class="close-btn" aria-label="Close">
		<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
			<path d="M18 6L6 18M6 6l12 12" />
		</svg>
	</a>
</div>

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

	.morph-ui {
		position: fixed;
		inset: 0;
		z-index: 10000;
		pointer-events: none;
	}

	.close-btn {
		position: fixed;
		top: 20px;
		right: 20px;
		width: 40px;
		height: 40px;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: 50%;
		background: rgba(10, 10, 10, 0.5);
		color: rgba(232, 224, 216, 0.5);
		transition: color 0.3s, background 0.3s;
		pointer-events: auto;
		cursor: pointer;
	}

	.close-btn:hover {
		color: rgba(232, 224, 216, 0.9);
		background: rgba(10, 10, 10, 0.8);
	}
</style>
