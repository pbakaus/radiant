<script lang="ts">
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
		const params = [
			{ name: 'BH_CENTER_X', value: 0.73 },
			{ name: 'BH_CENTER_Y', value: 0.45 },
			{ name: 'BH_SCALE', value: 2.4 },
			{ name: 'DISK_INTENSITY', value: 1.0 },
			{ name: 'ROTATION_SPEED', value: 0.3 }
		];
		function onLoad() {
			for (const p of params) {
				node.contentWindow?.postMessage({ type: 'param', name: p.name, value: p.value }, '*');
			}
		}
		node.addEventListener('load', onLoad);
		return { destroy() { node.removeEventListener('load', onLoad); } };
	}
</script>

<section class="hero">
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
</section>

<style>
	.hero {
		position: relative;
		height: 100dvh;
		overflow: hidden;
	}
	iframe {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		border: none;
		display: block;
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

	@media (max-width: 640px) {
		.content {
			padding: 0 1.5rem;
		}
	}
</style>
