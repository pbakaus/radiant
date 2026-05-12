<script lang="ts">
	import { onMount } from 'svelte';

	let {
		caption,
		initialIsco = 3.0,
		initialOuter = 14.0
	}: {
		caption?: string;
		initialIsco?: number;
		initialOuter?: number;
	} = $props();

	let canvas: HTMLCanvasElement;
	// svelte-ignore state_referenced_locally
	let isco = $state(initialIsco);
	// svelte-ignore state_referenced_locally
	let outer = $state(initialOuter);
	const RS = 1.0;

	// T(r) — Novikov-Thorne profile, normalized
	function T(r: number, iscoR: number): number {
		if (r <= iscoR) return 0;
		const xr = iscoR / r;
		const profile = Math.pow(iscoR / r, 0.75) * Math.pow(Math.max(0.001, 1 - Math.sqrt(xr)), 0.25);
		const gRedshift = Math.sqrt(Math.max(0.01, 1 - RS / r));
		return profile * gRedshift;
	}

	function bbColor(temp: number): [number, number, number] {
		temp = Math.max(0, Math.min(2.5, temp));
		const lo: [number, number, number] = [1.0, 0.18, 0.0];
		const mi: [number, number, number] = [1.0, 0.55, 0.12];
		const hi: [number, number, number] = [1.0, 0.93, 0.82];
		const hot: [number, number, number] = [0.65, 0.82, 1.0];
		const ss = (a: number, b: number, x: number) => {
			const tt = Math.max(0, Math.min(1, (x - a) / (b - a)));
			return tt * tt * (3 - 2 * tt);
		};
		const mix = (a: number[], b: number[], k: number): [number, number, number] =>
			[a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k];
		let c = mix(lo, mi, ss(0.0, 0.3, temp));
		c = mix(c, hi, ss(0.3, 0.8, temp));
		c = mix(c, hot, ss(0.8, 1.8, temp));
		return c as [number, number, number];
	}

	function draw() {
		if (!canvas) return;
		const dpr = Math.min(window.devicePixelRatio || 1, 2);
		const w = canvas.clientWidth;
		const h = canvas.clientHeight;
		canvas.width = Math.round(w * dpr);
		canvas.height = Math.round(h * dpr);
		const ctx = canvas.getContext('2d');
		if (!ctx) return;
		const W = canvas.width, H = canvas.height;

		// Background
		ctx.fillStyle = '#0d0d0d';
		ctx.fillRect(0, 0, W, H);

		// Plot region with margins
		const pad = 36 * dpr;
		const px = pad;
		const py = pad * 0.6;
		const pw = W - pad * 1.5;
		const ph = H - pad * 1.7;

		// X axis: r from 0 to outer * 1.1, Y axis: T from 0 to 1.2
		const rMin = 0.0;
		const rMax = outer * 1.1;
		const tMax = 1.05;

		// Compute curve
		const N = 400;
		const pts: [number, number][] = [];
		let maxT = 0;
		for (let i = 0; i <= N; i++) {
			const r = rMin + ((rMax - rMin) * i) / N;
			const tv = T(r, isco);
			if (tv > maxT) maxT = tv;
			pts.push([r, tv]);
		}

		// Grid
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.06)';
		ctx.lineWidth = 1 * dpr;
		for (let i = 1; i <= 4; i++) {
			const yy = py + (ph * i) / 5;
			ctx.beginPath();
			ctx.moveTo(px, yy);
			ctx.lineTo(px + pw, yy);
			ctx.stroke();
		}

		// Axis lines
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.18)';
		ctx.lineWidth = 1 * dpr;
		ctx.beginPath();
		ctx.moveTo(px, py);
		ctx.lineTo(px, py + ph);
		ctx.lineTo(px + pw, py + ph);
		ctx.stroke();

		// Plot the curve as a colored line (color from T → blackbody)
		const xOf = (r: number) => px + ((r - rMin) / (rMax - rMin)) * pw;
		const yOf = (tv: number) => py + ph - (tv / tMax) * ph;

		// Fill under curve (color graded)
		for (let i = 0; i < pts.length - 1; i++) {
			const [r0, t0] = pts[i];
			const [r1, t1] = pts[i + 1];
			if (t0 <= 0 && t1 <= 0) continue;
			const tMid = (t0 + t1) / 2;
			const [cr, cg, cb] = bbColor(tMid * 1.4);
			ctx.fillStyle = `rgba(${Math.round(cr * 255)}, ${Math.round(cg * 255)}, ${Math.round(cb * 255)}, 0.7)`;
			ctx.beginPath();
			ctx.moveTo(xOf(r0), py + ph);
			ctx.lineTo(xOf(r0), yOf(t0));
			ctx.lineTo(xOf(r1), yOf(t1));
			ctx.lineTo(xOf(r1), py + ph);
			ctx.closePath();
			ctx.fill();
		}

		// Curve outline
		ctx.strokeStyle = 'rgba(232, 224, 216, 0.85)';
		ctx.lineWidth = 1.5 * dpr;
		ctx.beginPath();
		let started = false;
		for (let i = 0; i < pts.length; i++) {
			const [r, tv] = pts[i];
			if (tv <= 0) { started = false; continue; }
			if (!started) { ctx.moveTo(xOf(r), yOf(tv)); started = true; }
			else ctx.lineTo(xOf(r), yOf(tv));
		}
		ctx.stroke();

		// ISCO marker
		const iscoX = xOf(isco);
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.6)';
		ctx.setLineDash([4 * dpr, 4 * dpr]);
		ctx.lineWidth = 1 * dpr;
		ctx.beginPath();
		ctx.moveTo(iscoX, py);
		ctx.lineTo(iscoX, py + ph);
		ctx.stroke();
		ctx.setLineDash([]);

		// Outer marker
		const outX = xOf(outer);
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.25)';
		ctx.setLineDash([3 * dpr, 5 * dpr]);
		ctx.beginPath();
		ctx.moveTo(outX, py);
		ctx.lineTo(outX, py + ph);
		ctx.stroke();
		ctx.setLineDash([]);

		// Labels
		ctx.fillStyle = 'rgba(232, 224, 216, 0.45)';
		ctx.font = (10 * dpr) + 'px "SF Mono", monospace';
		ctx.textAlign = 'center';
		ctx.fillText('ISCO', iscoX, py - 4 * dpr);
		ctx.fillText(`r_out`, outX, py - 4 * dpr);

		ctx.textAlign = 'left';
		ctx.fillStyle = 'rgba(232, 224, 216, 0.35)';
		ctx.fillText('T(r)', 6 * dpr, py + 12 * dpr);
		ctx.textAlign = 'right';
		ctx.fillText('r →', px + pw, py + ph + 16 * dpr);
		ctx.textAlign = 'left';
		ctx.fillText('0', px - 14 * dpr, py + ph + 4 * dpr);
		ctx.fillText('RS', xOf(1), py + ph + 14 * dpr);
	}

	$effect(() => {
		isco; outer;
		draw();
	});
	onMount(() => {
		draw();
		const ro = new ResizeObserver(draw);
		ro.observe(canvas);
		return () => ro.disconnect();
	});
</script>

<figure class="plot">
	<canvas bind:this={canvas}></canvas>
	<div class="controls">
		<label class="row">
			<span class="label">ISCO radius <span class="hint">(in RS)</span></span>
			<input
				type="range"
				min="2"
				max="9"
				step="0.05"
				value={isco}
				oninput={(e) => (isco = parseFloat(e.currentTarget.value))}
			/>
			<span class="value">{isco.toFixed(2)}</span>
		</label>
		<label class="row">
			<span class="label">Outer edge</span>
			<input
				type="range"
				min="8"
				max="25"
				step="0.5"
				value={outer}
				oninput={(e) => (outer = parseFloat(e.currentTarget.value))}
			/>
			<span class="value">{outer.toFixed(1)}</span>
		</label>
	</div>
	{#if caption}<figcaption>{caption}</figcaption>{/if}
</figure>

<style>
	.plot {
		margin: 2rem 0;
		background: #0d0d0d;
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
	}
	canvas {
		display: block;
		width: 100%;
		aspect-ratio: 16 / 8;
	}
	.controls {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		padding: 0.9rem 1.1rem 1rem;
		border-top: 1px solid rgba(200, 149, 108, 0.08);
		background: rgba(200, 149, 108, 0.02);
	}
	.row {
		display: grid;
		grid-template-columns: minmax(150px, 30%) 1fr 48px;
		align-items: center;
		gap: 0.75rem;
	}
	.label {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.6);
	}
	.hint {
		color: rgba(232, 224, 216, 0.35);
		font-size: 0.72em;
	}
	.value {
		text-align: right;
		font-family: 'SF Mono', monospace;
		font-size: 0.75rem;
		color: rgba(200, 149, 108, 0.7);
		font-variant-numeric: tabular-nums;
	}
	input[type='range'] {
		-webkit-appearance: none;
		appearance: none;
		width: 100%;
		height: 4px;
		background: rgba(200, 149, 108, 0.15);
		border-radius: 2px;
		outline: none;
		cursor: pointer;
	}
	input[type='range']::-webkit-slider-thumb {
		-webkit-appearance: none;
		appearance: none;
		width: 14px;
		height: 14px;
		background: #c8956c;
		border-radius: 50%;
		cursor: pointer;
	}
	input[type='range']::-moz-range-thumb {
		width: 14px;
		height: 14px;
		background: #c8956c;
		border: none;
		border-radius: 50%;
		cursor: pointer;
	}
	figcaption {
		padding: 0.7rem 1.1rem 0.9rem;
		font-size: 0.78rem;
		line-height: 1.5;
		color: rgba(232, 224, 216, 0.45);
		font-style: italic;
	}
</style>
