<script lang="ts">
	import { onMount } from 'svelte';

	let {
		caption,
		initial = 0.6
	}: {
		caption?: string;
		initial?: number;
	} = $props();

	let canvas: HTMLCanvasElement;
	// svelte-ignore state_referenced_locally
	let t = $state(initial);

	// Mirror of the shader's bbColor function (returns 0..1 rgb)
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

	function tempLabel(v: number): string {
		// Map [0, 2.5] roughly to [1500K, 18000K]
		const k = Math.round(1500 + v * 6600);
		return `${k} K`;
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

		// Strip gradient
		const stripH = canvas.height;
		const img = ctx.createImageData(canvas.width, stripH);
		for (let x = 0; x < canvas.width; x++) {
			const temp = (x / (canvas.width - 1)) * 2.5;
			let [r, g, b] = bbColor(temp);
			// gentle filmic tonemap to match in-shader appearance
			r = r / (r + 0.4);
			g = g / (g + 0.4);
			b = b / (b + 0.4);
			r = Math.pow(r, 0.85);
			g = Math.pow(g, 0.85);
			b = Math.pow(b, 0.85);
			for (let y = 0; y < stripH; y++) {
				const i = (y * canvas.width + x) * 4;
				img.data[i] = Math.round(r * 255);
				img.data[i + 1] = Math.round(g * 255);
				img.data[i + 2] = Math.round(b * 255);
				img.data[i + 3] = 255;
			}
		}
		ctx.putImageData(img, 0, 0);

		// Marker
		const mx = (t / 2.5) * canvas.width;
		ctx.strokeStyle = 'rgba(10,10,10,0.85)';
		ctx.lineWidth = 3 * dpr;
		ctx.beginPath();
		ctx.moveTo(mx, 0);
		ctx.lineTo(mx, canvas.height);
		ctx.stroke();
		ctx.strokeStyle = 'rgba(232,224,216,0.95)';
		ctx.lineWidth = 1.5 * dpr;
		ctx.beginPath();
		ctx.moveTo(mx, 0);
		ctx.lineTo(mx, canvas.height);
		ctx.stroke();
	}

	$effect(() => {
		// Re-draw when t changes
		t;
		draw();
	});
	onMount(() => {
		draw();
		const ro = new ResizeObserver(draw);
		ro.observe(canvas);
		return () => ro.disconnect();
	});

	let [r, g, b] = $derived(bbColor(t));
	let swatch = $derived(
		`rgb(${Math.round(r * 255)}, ${Math.round(g * 255)}, ${Math.round(b * 255)})`
	);
</script>

<figure class="blackbody">
	<div class="frame">
		<canvas bind:this={canvas}></canvas>
		<div class="readout">
			<span class="swatch" style:background={swatch}></span>
			<span class="temp">{tempLabel(t)}</span>
		</div>
	</div>
	<label class="row">
		<span class="label">Effective temperature</span>
		<input
			type="range"
			min="0"
			max="2.5"
			step="0.01"
			value={t}
			oninput={(e) => (t = parseFloat(e.currentTarget.value))}
		/>
	</label>
	{#if caption}<figcaption>{caption}</figcaption>{/if}
</figure>

<style>
	.blackbody {
		margin: 2rem 0;
		background: #0d0d0d;
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
	}
	.frame {
		position: relative;
		height: 120px;
	}
	canvas {
		display: block;
		width: 100%;
		height: 100%;
	}
	.readout {
		position: absolute;
		top: 10px;
		right: 12px;
		display: flex;
		align-items: center;
		gap: 8px;
		background: rgba(10, 10, 10, 0.65);
		backdrop-filter: blur(6px);
		padding: 5px 9px;
		border-radius: 4px;
		font-family: 'SF Mono', monospace;
		font-size: 0.7rem;
		color: rgba(232, 224, 216, 0.85);
		letter-spacing: 0.05em;
	}
	.swatch {
		display: inline-block;
		width: 12px;
		height: 12px;
		border-radius: 50%;
		border: 1px solid rgba(255, 255, 255, 0.15);
	}
	.row {
		display: grid;
		grid-template-columns: minmax(150px, 30%) 1fr;
		align-items: center;
		gap: 0.75rem;
		padding: 0.9rem 1.1rem 1rem;
		border-top: 1px solid rgba(200, 149, 108, 0.08);
		background: rgba(200, 149, 108, 0.02);
	}
	.label {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.6);
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
