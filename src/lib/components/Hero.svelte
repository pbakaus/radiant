<script lang="ts">
	let iframeEl: HTMLIFrameElement;
	let chromatic = $state(0);
	let intensity = $state(1.0);
	let speed = $state(0.3);

	/** Hides the .label overlay inside the shader iframe. */
	function hideLabel(node: HTMLIFrameElement) {
		function onLoad() {
			try {
				const label = node.contentDocument?.querySelector('.label') as HTMLElement | null;
				if (label) label.style.display = 'none';
			} catch {
				/* cross-origin — ignore */
			}
		}
		node.addEventListener('load', onLoad);
		return { destroy() { node.removeEventListener('load', onLoad); } };
	}

	/** Sends heroConfig params to reposition the black hole. */
	function sendHeroParams(node: HTMLIFrameElement) {
		iframeEl = node;
		const params = [
			{ name: 'BH_CENTER_X', value: 0.73 },
			{ name: 'BH_CENTER_Y', value: 0.45 },
			{ name: 'BH_SCALE', value: 2.4 },
			{ name: 'DISK_INTENSITY', value: intensity },
			{ name: 'ROTATION_SPEED', value: speed },
			{ name: 'CHROMATIC', value: chromatic }
		];
		function onLoad() {
			for (const p of params) {
				node.contentWindow?.postMessage({ type: 'param', name: p.name, value: p.value }, '*');
			}
		}
		node.addEventListener('load', onLoad);
		return { destroy() { node.removeEventListener('load', onLoad); } };
	}

	function sendParam(name: string, value: number) {
		iframeEl?.contentWindow?.postMessage({ type: 'param', name, value }, '*');
	}

	// Mouse-based tilt/rotate
	let targetTilt = 0;
	let targetRotate = 0;
	let currentTilt = 0;
	let currentRotate = 0;
	let rafId = 0;

	function onMouseMove(e: MouseEvent) {
		const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
		const nx = (e.clientX - rect.left) / rect.width * 2 - 1;  // -1 to 1
		const ny = (e.clientY - rect.top) / rect.height * 2 - 1;  // -1 to 1
		targetRotate = nx * 0.4;
		targetTilt = -ny * 0.25;
	}

	function onMouseLeave() {
		targetRotate = 0;
		targetTilt = 0;
	}

	function smoothUpdate() {
		const lerp = 0.06;
		currentTilt += (targetTilt - currentTilt) * lerp;
		currentRotate += (targetRotate - currentRotate) * lerp;
		sendParam('TILT', currentTilt);
		sendParam('ROTATE', currentRotate);
		rafId = requestAnimationFrame(smoothUpdate);
	}

	$effect(() => {
		rafId = requestAnimationFrame(smoothUpdate);
		return () => cancelAnimationFrame(rafId);
	});

	function onChromatic(e: Event) {
		chromatic = parseFloat((e.target as HTMLInputElement).value);
		sendParam('CHROMATIC', chromatic);
	}
	function onIntensity(e: Event) {
		intensity = parseFloat((e.target as HTMLInputElement).value);
		sendParam('DISK_INTENSITY', intensity);
	}
	function onSpeed(e: Event) {
		speed = parseFloat((e.target as HTMLInputElement).value);
		sendParam('ROTATION_SPEED', speed);
	}
</script>

<section class="hero" onmousemove={onMouseMove} onmouseleave={onMouseLeave}>
	<iframe
		use:hideLabel
		use:sendHeroParams
		src="/event-horizon.html"
		title="Event Horizon"
	></iframe>
	<div class="overlay"></div>
	<div class="content">
		<h1>Radiant</h1>
		<p class="tagline">Production-ready generative animations for the web. No dependencies. Just drop in.</p>
		<div class="ctas">
			<a href="#gallery" class="btn btn-solid">Browse Collection</a>
			<a href="#pricing" class="btn btn-ghost">View Pricing</a>
		</div>
	</div>
	<div class="controls">
		<label class="control">
			<span>Chromatic</span>
			<input type="range" min="0" max="1" step="0.02" value={chromatic} oninput={onChromatic} />
		</label>
		<label class="control">
			<span>Intensity</span>
			<input type="range" min="0.3" max="2" step="0.05" value={intensity} oninput={onIntensity} />
		</label>
		<label class="control">
			<span>Speed</span>
			<input type="range" min="0.05" max="1" step="0.05" value={speed} oninput={onSpeed} />
		</label>
		<span class="hint">Move mouse to rotate</span>
	</div>
</section>

<style>
	.hero {
		position: relative;
		height: 100dvh;
		overflow: hidden;
		cursor: crosshair;
	}
	iframe {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		border: none;
		display: block;
		pointer-events: none;
	}
	.overlay {
		position: absolute;
		inset: 0;
		background: linear-gradient(to right, rgba(10, 10, 10, 0.55) 0%, rgba(10, 10, 10, 0.15) 45%, transparent 70%);
		pointer-events: none;
	}
	.content {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		justify-content: center;
		height: 100%;
		padding: 0 3rem;
		max-width: 600px;
		pointer-events: none;
	}
	.content .ctas {
		pointer-events: auto;
	}
	h1 {
		font-size: clamp(3rem, 8vw, 6rem);
		font-weight: 300;
		color: #c8956c;
		letter-spacing: 0.03em;
		line-height: 1.1;
	}
	.tagline {
		margin-top: 1rem;
		font-size: clamp(0.95rem, 2vw, 1.15rem);
		color: rgba(232, 224, 216, 0.7);
		line-height: 1.6;
	}
	.ctas {
		display: flex;
		gap: 0.75rem;
		margin-top: 2rem;
		flex-wrap: wrap;
	}
	.btn {
		padding: 0.65rem 1.5rem;
		font-size: 0.85rem;
		font-weight: 500;
		border-radius: 6px;
		letter-spacing: 0.02em;
		transition: background 0.2s, border-color 0.2s;
		cursor: pointer;
	}
	.btn-solid {
		background: #c8956c;
		color: #0a0a0a;
	}
	.btn-solid:hover {
		background: #d4a57c;
	}
	.btn-ghost {
		background: transparent;
		border: 1px solid rgba(200, 149, 108, 0.4);
		color: #c8956c;
	}
	.btn-ghost:hover {
		border-color: rgba(200, 149, 108, 0.7);
	}

	/* Controls bar */
	.controls {
		position: absolute;
		bottom: 2rem;
		left: 50%;
		transform: translateX(-50%);
		z-index: 2;
		display: flex;
		align-items: center;
		gap: 1.5rem;
		padding: 0.6rem 1.25rem;
		background: rgba(10, 10, 10, 0.5);
		backdrop-filter: blur(12px);
		-webkit-backdrop-filter: blur(12px);
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 40px;
	}
	.control {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		cursor: pointer;
	}
	.control span {
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.1em;
		color: rgba(200, 149, 108, 0.5);
		white-space: nowrap;
		user-select: none;
	}
	.control input[type="range"] {
		-webkit-appearance: none;
		appearance: none;
		width: 70px;
		height: 3px;
		background: rgba(200, 149, 108, 0.15);
		border-radius: 2px;
		outline: none;
		cursor: pointer;
	}
	.control input[type="range"]::-webkit-slider-thumb {
		-webkit-appearance: none;
		appearance: none;
		width: 10px;
		height: 10px;
		background: #c8956c;
		border-radius: 50%;
		cursor: pointer;
		transition: transform 0.15s;
	}
	.control input[type="range"]::-webkit-slider-thumb:hover {
		transform: scale(1.3);
	}
	.control input[type="range"]::-moz-range-thumb {
		width: 10px;
		height: 10px;
		background: #c8956c;
		border: none;
		border-radius: 50%;
		cursor: pointer;
	}
	.hint {
		font-size: 0.55rem;
		text-transform: uppercase;
		letter-spacing: 0.1em;
		color: rgba(200, 149, 108, 0.3);
		white-space: nowrap;
		user-select: none;
	}

	@media (max-width: 640px) {
		.content {
			padding: 0 1.5rem;
		}
		.controls {
			gap: 0.75rem;
			padding: 0.5rem 1rem;
			flex-wrap: wrap;
			justify-content: center;
			border-radius: 16px;
			width: calc(100% - 2rem);
		}
		.hint {
			display: none;
		}
	}
</style>
