<script lang="ts">
	import { onMount } from 'svelte';

	let { caption }: { caption?: string } = $props();

	let canvas: HTMLCanvasElement;
	// svelte-ignore state_referenced_locally
	let r1 = $state(40);
	// svelte-ignore state_referenced_locally
	let r2 = $state(28);

	const ASPECT = 16 / 9;
	const LOSS = 0.8; // fraction of the smaller drop's water that joins

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

		// Background
		ctx.fillStyle = '#0d0d0d';
		ctx.fillRect(0, 0, w, h);

		// Layout: r1 on the left, r2 on its right (smaller), merged on the right.
		// Split horizontally into "before" (60%) and "after" (40%) regions.
		const beforeRight = w * 0.6;
		const beforeMidY = h / 2;
		const afterMidX = w * 0.8;
		const afterMidY = h / 2;

		const drawCircle = (x: number, y: number, r: number, label: string, color: string) => {
			ctx.beginPath();
			ctx.arc(x, y, r * dpr, 0, Math.PI * 2);
			ctx.fillStyle = color;
			ctx.fill();
			ctx.strokeStyle = 'rgba(255, 255, 255, 0.4)';
			ctx.lineWidth = 1 * dpr;
			ctx.stroke();
			// Label
			ctx.font = `${11 * dpr}px "SF Mono", monospace`;
			ctx.fillStyle = 'rgba(232, 224, 216, 0.85)';
			ctx.textAlign = 'center';
			ctx.fillText(label, x, y + r * dpr + 22 * dpr);
		};

		// Position r1 and r2 inside the "before" half — gap chosen so they
		// look like two adjacent drops about to merge
		const gap = 14 * dpr;
		const r1px = r1 * dpr;
		const r2px = r2 * dpr;
		const totalWidth = r1px * 2 + r2px * 2 + gap;
		const startX = (beforeRight - totalWidth) / 2;
		const x1 = startX + r1px;
		const x2 = startX + r1px * 2 + gap + r2px;

		drawCircle(x1, beforeMidY, r1, 'r₁ = ' + r1.toFixed(0), 'rgba(200, 149, 108, 0.5)');
		drawCircle(x2, beforeMidY, r2, 'r₂ = ' + r2.toFixed(0), 'rgba(180, 220, 255, 0.5)');

		// Arrow
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.5)';
		ctx.lineWidth = 1.5 * dpr;
		ctx.beginPath();
		ctx.moveTo(beforeRight + 10 * dpr, beforeMidY);
		ctx.lineTo(beforeRight + 36 * dpr, beforeMidY);
		ctx.stroke();
		const ah = 7 * dpr;
		ctx.beginPath();
		ctx.moveTo(beforeRight + 36 * dpr, beforeMidY);
		ctx.lineTo(beforeRight + 30 * dpr, beforeMidY - ah);
		ctx.lineTo(beforeRight + 30 * dpr, beforeMidY + ah);
		ctx.closePath();
		ctx.fillStyle = 'rgba(200, 149, 108, 0.5)';
		ctx.fill();

		// Merged circle (area-conserving with the 0.8 loss factor)
		const a1 = Math.PI * r1 * r1;
		const a2 = Math.PI * r2 * r2;
		const mergedR = Math.sqrt((a1 + a2 * LOSS) / Math.PI);
		drawCircle(afterMidX, afterMidY, mergedR, 'r = ' + mergedR.toFixed(1), 'rgba(200, 149, 108, 0.7)');

		// Vertical divider
		ctx.strokeStyle = 'rgba(200, 149, 108, 0.1)';
		ctx.lineWidth = 1 * dpr;
		ctx.beginPath();
		ctx.moveTo(beforeRight + 50 * dpr, 0);
		ctx.lineTo(beforeRight + 50 * dpr, h);
		ctx.stroke();
	}

	$effect(() => {
		r1;
		r2;
		draw();
	});
	onMount(() => {
		draw();
		const ro = new ResizeObserver(draw);
		ro.observe(canvas);
		return () => ro.disconnect();
	});

	const mergedR = $derived(Math.sqrt((Math.PI * r1 * r1 + Math.PI * r2 * r2 * 0.8) / Math.PI));
</script>

<figure class="merger">
	<canvas bind:this={canvas} aria-label="Drop merger area-conservation visualization"></canvas>
	<div class="controls">
		<label class="row">
			<span class="label">r₁ (the bigger drop)</span>
			<input
				type="range"
				min="20"
				max="80"
				step="1"
				value={r1}
				oninput={(e) => (r1 = parseFloat(e.currentTarget.value))}
			/>
			<span class="value">{r1.toFixed(0)}</span>
		</label>
		<label class="row">
			<span class="label">r₂ (the smaller drop)</span>
			<input
				type="range"
				min="6"
				max="60"
				step="1"
				value={r2}
				oninput={(e) => (r2 = parseFloat(e.currentTarget.value))}
			/>
			<span class="value">{r2.toFixed(0)}</span>
		</label>
		<div class="formula">
			r = √((π·r₁² + 0.8·π·r₂²) / π) = <strong>{mergedR.toFixed(1)}</strong>
		</div>
	</div>
	{#if caption}<figcaption>{caption}</figcaption>{/if}
</figure>

<style>
	.merger {
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
