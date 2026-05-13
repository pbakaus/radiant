<script lang="ts">
	import { onMount } from 'svelte';

	let { caption }: { caption?: string } = $props();

	let dropCanvas: HTMLCanvasElement;
	let bgCanvas: HTMLCanvasElement;
	let sampleX = $state(0.5);
	let sampleY = $state(0.5);
	let isDragging = $state(false);
	let rgba = $state({ r: 128, g: 128, b: 0, a: 0 });

	const SIZE = 320;
	const dpr = typeof window !== 'undefined' ? Math.min(window.devicePixelRatio || 1, 2) : 2;

	// Cached offscreen bitmaps — generated once, not regenerated on every pointer event.
	let dropBitmap: HTMLCanvasElement | null = null;
	let bgBitmap: HTMLCanvasElement | null = null;

	// The bitmap holds the RAW drop pixels (RGB = encoded refraction, A = mask).
	// We don't pre-composite the dark background here, because sampleRGBA needs
	// to read the unmodified encoded values. The background is filled by paintDrop.
	function buildDropBitmap() {
		const c = document.createElement('canvas');
		const w = SIZE * dpr;
		c.width = c.height = w;
		const ctx = c.getContext('2d');
		if (!ctx) return c;
		const img = ctx.createImageData(w, w);
		const d = img.data;
		const cx = w / 2;
		for (let py = 0; py < w; py++) {
			for (let px = 0; px < w; px++) {
				const dx = (px - cx) / cx;
				let dy = (py - cx) / cx;
				dy *= 1.0 + dy * 0.15;
				const dist = Math.sqrt(dx * dx + dy * dy);
				if (dist > 1.0) continue;
				const nx = dist > 0.001 ? dx / dist : 0;
				const ny = dist > 0.001 ? dy / dist : 0;
				const r = Math.round(ny * 60 * dist + 128);
				const g = Math.round(nx * 60 * dist + 128);
				const depth = Math.sqrt(Math.max(0, 1.0 - dist * dist)) * 255;
				const alpha = Math.max(0, 1.0 - Math.pow(dist / 0.45, 6)) * 255;
				const idx = (py * w + px) * 4;
				d[idx] = Math.max(0, Math.min(255, r));
				d[idx + 1] = Math.max(0, Math.min(255, g));
				d[idx + 2] = Math.round(depth);
				d[idx + 3] = Math.round(Math.min(255, Math.max(0, alpha)));
			}
		}
		ctx.putImageData(img, 0, 0);
		return c;
	}

	function buildBackgroundBitmap() {
		const c = document.createElement('canvas');
		const w = SIZE * dpr;
		c.width = c.height = w;
		const ctx = c.getContext('2d');
		if (!ctx) return c;
		const grad = ctx.createLinearGradient(0, 0, w, w);
		grad.addColorStop(0, '#1a0e22');
		grad.addColorStop(0.3, '#3a1a18');
		grad.addColorStop(0.6, '#7a3818');
		grad.addColorStop(1, '#c87038');
		ctx.fillStyle = grad;
		ctx.fillRect(0, 0, w, w);
		for (let i = 0; i < 9; i++) {
			const y = (i / 9) * w * 1.3 - w * 0.15;
			ctx.strokeStyle = i % 3 === 0 ? 'rgba(255, 200, 120, 0.5)' : 'rgba(180, 220, 255, 0.18)';
			ctx.lineWidth = 14 + (i % 4) * 4;
			ctx.beginPath();
			ctx.moveTo(-50, y);
			ctx.lineTo(w + 50, y + w * 0.18);
			ctx.stroke();
		}
		return c;
	}

	function paintDrop() {
		if (!dropCanvas || !dropBitmap) return;
		dropCanvas.width = SIZE * dpr;
		dropCanvas.height = SIZE * dpr;
		const ctx = dropCanvas.getContext('2d');
		if (!ctx) return;
		// Fill dark background here (not in the bitmap), so the bitmap stays
		// pristine for sampleRGBA to read the raw encoded values.
		ctx.fillStyle = '#0d0d0d';
		ctx.fillRect(0, 0, dropCanvas.width, dropCanvas.height);
		ctx.drawImage(dropBitmap, 0, 0);

		// Sample-point marker (cheap to draw)
		const w = dropCanvas.width;
		const sx = sampleX * w;
		const sy = sampleY * w;
		ctx.strokeStyle = '#fff';
		ctx.lineWidth = 2 * dpr;
		ctx.beginPath();
		ctx.arc(sx, sy, 8 * dpr, 0, Math.PI * 2);
		ctx.stroke();
		ctx.fillStyle = 'rgba(0,0,0,0.55)';
		ctx.beginPath();
		ctx.arc(sx, sy, 8 * dpr, 0, Math.PI * 2);
		ctx.fill();
	}

	function paintBg() {
		if (!bgCanvas || !bgBitmap) return;
		bgCanvas.width = SIZE * dpr;
		bgCanvas.height = SIZE * dpr;
		const ctx = bgCanvas.getContext('2d');
		if (!ctx) return;
		ctx.drawImage(bgBitmap, 0, 0);

		const w = bgCanvas.width;
		const sx = sampleX * w;
		const sy = sampleY * w;
		const offsetX = (rgba.g / 255 - 0.5) * 2;
		const offsetY = (rgba.r / 255 - 0.5) * 2;
		const depth = rgba.b / 255;
		const scale = (256 + depth * 256) * (dpr / 2);
		const refX = sx + offsetX * scale;
		const refY = sy + offsetY * scale;

		ctx.strokeStyle = 'rgba(255, 255, 255, 0.85)';
		ctx.lineWidth = 2 * dpr;
		ctx.beginPath();
		ctx.moveTo(sx, sy);
		ctx.lineTo(refX, refY);
		ctx.stroke();

		const ang = Math.atan2(refY - sy, refX - sx);
		const ah = 10 * dpr;
		ctx.beginPath();
		ctx.moveTo(refX, refY);
		ctx.lineTo(refX - ah * Math.cos(ang - 0.4), refY - ah * Math.sin(ang - 0.4));
		ctx.lineTo(refX - ah * Math.cos(ang + 0.4), refY - ah * Math.sin(ang + 0.4));
		ctx.closePath();
		ctx.fillStyle = 'rgba(255, 255, 255, 0.85)';
		ctx.fill();

		ctx.fillStyle = 'rgba(200, 149, 108, 0.6)';
		ctx.beginPath();
		ctx.arc(sx, sy, 5 * dpr, 0, Math.PI * 2);
		ctx.fill();

		ctx.strokeStyle = '#f0e8de';
		ctx.lineWidth = 2 * dpr;
		ctx.beginPath();
		ctx.arc(refX, refY, 8 * dpr, 0, Math.PI * 2);
		ctx.stroke();
	}

	function sampleRGBA(x: number, y: number) {
		if (!dropBitmap) return;
		const ctx = dropBitmap.getContext('2d');
		if (!ctx) return;
		const px = Math.max(0, Math.min(dropBitmap.width - 1, Math.round(x * dropBitmap.width)));
		const py = Math.max(0, Math.min(dropBitmap.height - 1, Math.round(y * dropBitmap.height)));
		try {
			const data = ctx.getImageData(px, py, 1, 1).data;
			rgba = { r: data[0], g: data[1], b: data[2], a: data[3] };
		} catch {
			/* ignore */
		}
	}

	function onPointer(e: PointerEvent) {
		if (!isDragging) return;
		const rect = dropCanvas.getBoundingClientRect();
		const x = Math.max(0.02, Math.min(0.98, (e.clientX - rect.left) / rect.width));
		const y = Math.max(0.02, Math.min(0.98, (e.clientY - rect.top) / rect.height));
		sampleX = x;
		sampleY = y;
		// Update the sampled RGBA synchronously here, NOT inside an $effect.
		// Doing it in the effect creates a write-then-read cycle on `rgba`
		// (the effect writes rgba via sampleRGBA, and reads it via paintBg)
		// which Svelte 5 catches as effect_update_depth_exceeded.
		sampleRGBA(x, y);
	}

	$effect(() => {
		// Pure paint side-effect, reads state but never writes
		sampleX;
		sampleY;
		rgba;
		paintDrop();
		paintBg();
	});

	onMount(() => {
		dropBitmap = buildDropBitmap();
		bgBitmap = buildBackgroundBitmap();
		sampleRGBA(sampleX, sampleY);
		paintDrop();
		paintBg();
	});

	const offsetX = $derived(((rgba.g / 255 - 0.5) * 2).toFixed(2));
	const offsetY = $derived(((rgba.r / 255 - 0.5) * 2).toFixed(2));
	const depth = $derived((rgba.b / 255).toFixed(2));
</script>

<figure class="decoder">
	<div class="panes">
		<div class="pane">
			<div class="pane-label">Drop normal map (encoded RGB)</div>
			<canvas
				bind:this={dropCanvas}
				aria-label="Drop's refraction normal map. Drag to move the sample point."
				onpointerdown={(e) => {
					isDragging = true;
					(e.currentTarget as HTMLCanvasElement).setPointerCapture(e.pointerId);
					onPointer(e);
				}}
				onpointermove={onPointer}
				onpointerup={(e) => {
					isDragging = false;
					(e.currentTarget as HTMLCanvasElement).releasePointerCapture(e.pointerId);
				}}
			></canvas>
		</div>
		<div class="pane">
			<div class="pane-label">Background, with sampling arrow</div>
			<canvas bind:this={bgCanvas} aria-hidden="true"></canvas>
		</div>
	</div>
	<div class="readout">
		<div class="row">
			<span class="key">R (y-offset)</span>
			<span class="val">{rgba.r}</span>
			<span class="key">G (x-offset)</span>
			<span class="val">{rgba.g}</span>
			<span class="key">B (depth)</span>
			<span class="val">{rgba.b}</span>
		</div>
		<div class="row formula">
			offset = ((G − 128) / 128, (R − 128) / 128) = ({offsetX}, {offsetY}) · depth {depth}
		</div>
	</div>
	{#if caption}<figcaption>{caption}</figcaption>{/if}
</figure>

<style>
	.decoder {
		margin: 2rem 0;
		background: #0d0d0d;
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
	}
	.panes {
		display: grid;
		grid-template-columns: 1fr 1fr;
	}
	.pane + .pane {
		border-left: 1px solid rgba(200, 149, 108, 0.08);
	}
	.pane {
		position: relative;
		display: flex;
		flex-direction: column;
	}
	.pane-label {
		font-family: 'SF Mono', monospace;
		font-size: 0.66rem;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: rgba(200, 149, 108, 0.55);
		padding: 0.65rem 1rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.06);
	}
	canvas {
		display: block;
		width: 100%;
		aspect-ratio: 1;
		touch-action: none;
		cursor: crosshair;
	}
	.readout {
		padding: 0.85rem 1.1rem 1rem;
		border-top: 1px solid rgba(200, 149, 108, 0.08);
		background: rgba(200, 149, 108, 0.02);
		font-family: 'SF Mono', monospace;
		font-size: 0.75rem;
		color: rgba(232, 224, 216, 0.7);
	}
	.row {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem 0.9rem;
		align-items: baseline;
	}
	.row.formula {
		margin-top: 0.55rem;
		padding-top: 0.55rem;
		border-top: 1px dashed rgba(200, 149, 108, 0.08);
		font-size: 0.72rem;
		color: rgba(232, 224, 216, 0.55);
	}
	.key {
		color: rgba(200, 149, 108, 0.7);
	}
	.val {
		color: #e8e0d8;
		min-width: 2.5em;
		font-variant-numeric: tabular-nums;
	}
	figcaption {
		padding: 0.7rem 1.1rem 0.9rem;
		font-size: 0.78rem;
		line-height: 1.5;
		color: rgba(232, 224, 216, 0.45);
		font-style: italic;
		border-top: 1px solid rgba(200, 149, 108, 0.05);
	}
	@media (max-width: 640px) {
		.panes {
			grid-template-columns: 1fr;
		}
		.pane + .pane {
			border-left: 0;
			border-top: 1px solid rgba(200, 149, 108, 0.08);
		}
	}
</style>
