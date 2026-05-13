<script lang="ts">
	import { onMount } from 'svelte';

	let { caption }: { caption?: string } = $props();

	let canvas: HTMLCanvasElement;
	// svelte-ignore state_referenced_locally
	let a = $state(3);
	// svelte-ignore state_referenced_locally
	let b = $state(2);
	// svelte-ignore state_referenced_locally
	let delta = $state(Math.PI / 4);

	const ASPECT = 16 / 9;

	function draw() {
		if (!canvas) return;
		const dpr = Math.min(window.devicePixelRatio || 1, 2);
		const cssW = canvas.clientWidth;
		const cssH = cssW / ASPECT;
		canvas.width = Math.round(cssW * dpr);
		canvas.height = Math.round(cssH * dpr);
		canvas.style.height = cssH + 'px';
		const ctx = canvas.getContext('2d');
		if (!ctx) return;
		const w = canvas.width;
		const h = canvas.height;

		ctx.fillStyle = '#0d0d0d';
		ctx.fillRect(0, 0, w, h);

		const cx = w / 2;
		const cy = h / 2;
		const size = Math.min(w, h) * 0.38;

		// Faint axes
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.12)';
		ctx.lineWidth = 1 * dpr;
		ctx.beginPath();
		ctx.moveTo(cx - size, cy);
		ctx.lineTo(cx + size, cy);
		ctx.moveTo(cx, cy - size);
		ctx.lineTo(cx, cy + size);
		ctx.stroke();
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.15)';
		ctx.strokeRect(cx - size, cy - size, size * 2, size * 2);

		// Curve
		const N = 2400;
		const coverage = Math.PI * 2 * Math.max(Math.ceil(a), Math.ceil(b), 1);
		const step = coverage / N;
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.95)';
		ctx.lineWidth = 1.4 * dpr;
		ctx.lineCap = 'round';
		ctx.lineJoin = 'round';
		ctx.beginPath();
		for (let i = 0; i <= N; i++) {
			const t = i * step;
			const x = cx + Math.sin(a * t + delta) * size;
			const y = cy + Math.sin(b * t) * size;
			if (i === 0) ctx.moveTo(x, y);
			else ctx.lineTo(x, y);
		}
		ctx.stroke();
	}

	$effect(() => {
		a;
		b;
		delta;
		draw();
	});

	onMount(() => {
		draw();
		const ro = new ResizeObserver(draw);
		ro.observe(canvas);
		return () => ro.disconnect();
	});

	const ratio = $derived(() => {
		// gcd for friendly ratio display when a,b are integers
		const ai = Math.round(a);
		const bi = Math.round(b);
		if (Math.abs(a - ai) > 0.01 || Math.abs(b - bi) > 0.01) return null;
		const gcd = (x: number, y: number): number => (y === 0 ? x : gcd(y, x % y));
		const g = gcd(Math.max(ai, 1), Math.max(bi, 1));
		return `${ai / g}:${bi / g}`;
	});
</script>

<figure class="lissajous">
	<canvas bind:this={canvas} aria-label="Interactive Lissajous figure"></canvas>
	<div class="controls">
		<label class="row">
			<span class="label">a (x frequency)</span>
			<input
				type="range"
				min="1"
				max="6"
				step="1"
				value={a}
				oninput={(e) => (a = parseFloat(e.currentTarget.value))}
			/>
			<span class="value">{a.toFixed(0)}</span>
		</label>
		<label class="row">
			<span class="label">b (y frequency)</span>
			<input
				type="range"
				min="1"
				max="6"
				step="1"
				value={b}
				oninput={(e) => (b = parseFloat(e.currentTarget.value))}
			/>
			<span class="value">{b.toFixed(0)}</span>
		</label>
		<label class="row">
			<span class="label">δ (phase, radians)</span>
			<input
				type="range"
				min="0"
				max={Math.PI.toFixed(4)}
				step="0.01"
				value={delta}
				oninput={(e) => (delta = parseFloat(e.currentTarget.value))}
			/>
			<span class="value">{delta.toFixed(2)}</span>
		</label>
		<div class="formula">
			x = sin({a.toFixed(0)}·t + {delta.toFixed(2)})  ·  y = sin({b.toFixed(0)}·t){#if ratio()}
				  ·  ratio <strong>{ratio()}</strong>{/if}
		</div>
	</div>
	{#if caption}<figcaption>{caption}</figcaption>{/if}
</figure>

<style>
	.lissajous {
		margin: 2rem 0;
		background: #0d0d0d;
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
	}
	canvas {
		display: block;
		width: 100%;
		aspect-ratio: 16 / 9;
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
		grid-template-columns: minmax(160px, 30%) 1fr 48px;
		align-items: center;
		gap: 0.75rem;
	}
	.label {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.6);
	}
	.value {
		text-align: right;
		font-family: 'SF Mono', monospace;
		font-size: 0.75rem;
		color: rgba(200, 149, 108, 0.7);
		font-variant-numeric: tabular-nums;
	}
	.formula {
		margin-top: 0.4rem;
		padding-top: 0.55rem;
		border-top: 1px dashed rgba(200, 149, 108, 0.08);
		font-family: 'SF Mono', monospace;
		font-size: 0.78rem;
		color: rgba(232, 224, 216, 0.6);
	}
	.formula strong {
		color: #c8956c;
		font-weight: 500;
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
