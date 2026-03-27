<script lang="ts">
	import { onMount } from 'svelte';
	import { MorphEngine } from './engine';
	import { allPresets, createLerpBuffer, lerpPresetsInto } from './presets';

	const MORPH_MS = 8_000; // each transition takes 8s, then immediately next
	const ZOOM_MIN = 1.0;
	const ZOOM_MAX = 1.25;
	const HUE_CYCLE_S = 300;

	let canvas: HTMLCanvasElement | undefined = $state();
	let mouseX = 0;
	let mouseY = 0;

	function shuffleArray<T>(arr: T[]): T[] {
		const a = [...arr];
		for (let i = a.length - 1; i > 0; i--) {
			const j = Math.floor(Math.random() * (i + 1));
			[a[i], a[j]] = [a[j], a[i]];
		}
		return a;
	}

	onMount(() => {
		if (!canvas) return;

		const presets = shuffleArray(allPresets);
		const engine = new MorphEngine(canvas);
		const paramBuf = createLerpBuffer(presets[0]);
		const mouseBuf: [number, number] = [0, 0];
		const zoomCenterBuf: [number, number] = [0.5, 0.5];

		const titleEl = document.getElementById('morph-title');
		const numberEl = document.getElementById('morph-number');
		const textEl = document.getElementById('morph-text');

		if (titleEl) titleEl.classList.add('visible');
		if (textEl) textEl.textContent = presets[0].title;
		if (numberEl) numberEl.textContent = '01';

		let canvasW = 0, canvasH = 0;
		function resize() {
			const w = Math.round(innerWidth);
			const h = Math.round(innerHeight);
			if (w !== canvasW || h !== canvasH) {
				canvasW = w; canvasH = h;
				canvas!.width = w; canvas!.height = h;
				engine.resize(w, h);
			}
		}
		resize();
		window.addEventListener('resize', resize);

		const globalStart = performance.now();
		const len = presets.length;
		let lastIdx = -1;

		function tick(now: number) {
			const elapsed = now - globalStart;
			const timeSec = elapsed / 1000;

			// Continuous morph: total elapsed drives which pair we're between
			const totalProgress = elapsed / MORPH_MS;
			const segIndex = Math.floor(totalProgress);
			const t = totalProgress - segIndex; // 0→1 within current segment
			const smoothT = t * t * (3 - 2 * t);

			const aIdx = segIndex % len;
			const bIdx = (segIndex + 1) % len;

			// Update title when segment changes
			if (segIndex !== lastIdx) {
				lastIdx = segIndex;
				if (textEl) textEl.textContent = presets[bIdx].title;
				if (numberEl) numberEl.textContent = (bIdx + 1).toString().padStart(2, '0');
			}

			// Zoom: ping-pong within each segment
			const zoomT = Math.sin(t * Math.PI); // 0→1→0
			const zoom = ZOOM_MIN + (ZOOM_MAX - ZOOM_MIN) * zoomT;

			const hueRad = (timeSec / HUE_CYCLE_S) * Math.PI * 2;

			resize();

			lerpPresetsInto(paramBuf, presets[aIdx], presets[bIdx], smoothT);
			mouseBuf[0] = mouseX;
			mouseBuf[1] = innerHeight - mouseY;
			zoomCenterBuf[0] = mouseX / innerWidth;
			zoomCenterBuf[1] = 1.0 - mouseY / innerHeight;

			engine.render(paramBuf, timeSec, mouseBuf, zoom, zoomCenterBuf, hueRad);

			raf = requestAnimationFrame(tick);
		}

		let raf = requestAnimationFrame(tick);

		return () => {
			cancelAnimationFrame(raf);
			window.removeEventListener('resize', resize);
			engine.destroy();
		};
	});

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') history.back();
	}
</script>

<svelte:window
	onkeydown={handleKeydown}
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

<canvas class="gl-canvas" bind:this={canvas}></canvas>

<div class="morph-ui">
	<div id="morph-title" class="shader-title">
		<span id="morph-number" class="title-number">01</span>
		<span id="morph-text" class="title-text"></span>
	</div>

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

	.morph-ui {
		position: fixed;
		inset: 0;
		z-index: 10000;
		pointer-events: none;
	}

	.shader-title {
		position: fixed;
		bottom: 32px;
		left: 32px;
		display: flex;
		align-items: baseline;
		gap: 12px;
		opacity: 0;
		transition: opacity 1.2s ease;
	}

	.shader-title:global(.visible) { opacity: 0.6; }

	.title-number {
		font-size: 12px;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: rgba(200, 149, 108, 0.5);
		font-variant-numeric: tabular-nums;
	}

	.title-text {
		font-size: 14px;
		font-weight: 300;
		letter-spacing: 0.03em;
		color: rgba(232, 224, 216, 0.7);
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
