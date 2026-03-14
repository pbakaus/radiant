<script lang="ts">
	import type { Shader } from '$lib/shaders';

	let {
		shader,
		layout = 'full',
		filter = 'none'
	}: {
		shader: Shader;
		layout: 'full' | 'hero' | 'background' | 'accent';
		filter: string;
	} = $props();

	/** Hides the .label overlay and injects FPS counter inside the shader iframe. */
	function hideLabel(node: HTMLIFrameElement) {
		function onLoad() {
			try {
				const doc = node.contentDocument;
				if (!doc) return;
				const label = doc.querySelector('.label') as HTMLElement | null;
				if (label) label.style.display = 'none';

				// Inject FPS counter
				if (!doc.getElementById('fps-counter')) {
					const el = doc.createElement('div');
					el.id = 'fps-counter';
					el.style.cssText = 'position:fixed;top:8px;right:10px;font:10px/1 monospace;color:rgba(200,149,108,0.4);z-index:99;pointer-events:none;';
					doc.body.appendChild(el);
					const script = doc.createElement('script');
					script.textContent = `(function(){var f=0,lt=performance.now(),el=document.getElementById('fps-counter');function t(){f++;var n=performance.now();if(n-lt>=1000){el.textContent=f+" fps";f=0;lt=n;}requestAnimationFrame(t);}requestAnimationFrame(t);})();`;
					doc.body.appendChild(script);
				}
			} catch {
				/* cross-origin or security restriction — ignore */
			}
		}
		node.addEventListener('load', onLoad);
		return {
			destroy() {
				node.removeEventListener('load', onLoad);
			}
		};
	}

	/** Sends heroConfig params to the iframe once it loads. */
	function sendHeroParams(node: HTMLIFrameElement) {
		if (!shader.heroConfig) return { destroy() {} };
		const params = shader.heroConfig.params;
		function onLoad() {
			for (const p of params) {
				node.contentWindow?.postMessage({ type: 'param', name: p.name, value: p.value }, '*');
			}
		}
		node.addEventListener('load', onLoad);
		return {
			destroy() {
				node.removeEventListener('load', onLoad);
			}
		};
	}

	const hasCustomHero = !!shader.heroConfig;
</script>

<div class="preview layout-{layout}">
	{#if layout === 'hero' && hasCustomHero}
		<div class="mock-layout hero-custom-layout">
			<iframe use:hideLabel use:sendHeroParams src="/{shader.file}" title={shader.title} style:filter></iframe>
			<div class="hero-custom-overlay">
				<div class="mock-nav">
					<span class="mock-logo">acme</span>
					<span class="mock-links">
						<span>Features</span>
						<span>Pricing</span>
						<span>About</span>
					</span>
				</div>
				<div class="hero-body">
					<div class="mock-content">
						<h2>Your next big idea starts here</h2>
						<p>A beautiful landing page with a generative shader that makes your product stand out.</p>
						<div class="mock-btn">Get Started</div>
					</div>
				</div>
			</div>
		</div>
	{:else if layout === 'hero'}
		<div class="mock-layout hero-layout">
			<div class="mock-nav">
				<span class="mock-logo">acme</span>
				<span class="mock-links">
					<span>Features</span>
					<span>Pricing</span>
					<span>About</span>
				</span>
			</div>
			<div class="hero-body">
				<div class="mock-content">
					<h2>Your next big idea starts here</h2>
					<p>A beautiful landing page with a generative shader that makes your product stand out.</p>
					<div class="mock-btn">Get Started</div>
				</div>
				<div class="hero-shader">
					<iframe use:hideLabel src="/{shader.file}?p=1.8" title={shader.title} style:filter></iframe>
				</div>
			</div>
		</div>
	{:else if layout === 'background'}
		<div class="mock-layout bg-layout">
			<iframe use:hideLabel src="/{shader.file}" title={shader.title} style:filter></iframe>
			<div class="mock-overlay">
				<h2>Welcome</h2>
				<p>Content overlaid on a full-viewport shader background with a darkening layer.</p>
				<div class="mock-btn">Call to Action</div>
			</div>
		</div>
	{:else if layout === 'accent'}
		<div class="mock-layout accent-layout">
			<iframe use:hideLabel src="/{shader.file}" title={shader.title} style:filter></iframe>
			<div class="mock-content">
				<h2>Creative Studio</h2>
				<p>The shader fades in from the right as a dramatic accent, creating depth alongside your content.</p>
				<div class="mock-btn">Learn More</div>
			</div>
		</div>
	{:else}
		<div class="mock-layout full-layout">
			<iframe use:hideLabel src="/{shader.file}" title={shader.title} style:filter></iframe>
		</div>
	{/if}
</div>

<style>
	.preview {
		width: 100%;
		background: #0a0a0a;
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
	}

	.mock-layout {
		position: relative;
		width: 100%;
		aspect-ratio: 16 / 9;
	}
	.full-layout {
		aspect-ratio: unset;
		height: 100%;
	}

	iframe {
		border: none;
		display: block;
	}

	/* Full layout */
	.full-layout iframe {
		width: 100%;
		height: 100%;
		position: absolute;
		inset: 0;
	}

	/* Hero layout: nav on top, content left + frameless shader right */
	.hero-layout {
		display: flex;
		flex-direction: column;
		background: #0a0a0a;
	}
	.mock-nav {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 1rem 2rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.06);
		flex-shrink: 0;
	}
	.mock-logo {
		font-weight: 600;
		font-size: 0.9rem;
		color: #c8956c;
		letter-spacing: 0.05em;
	}
	.mock-links {
		display: flex;
		gap: 1rem;
		font-size: 0.7rem;
		color: rgba(232, 224, 216, 0.35);
	}
	.hero-body {
		display: flex;
		align-items: center;
		gap: 1rem;
		padding: 2rem 6rem;
		flex: 1;
		min-height: 0;
	}
	.hero-body .mock-content {
		flex: 1;
		padding: 0 1rem;
	}
	.hero-shader {
		flex: 0 0 40%;
		align-self: stretch;
		position: relative;
	}
	.hero-shader iframe {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
	}

	/* Custom hero layout: full-viewport shader with content overlaid */
	.hero-custom-layout {
		background: #0a0a0a;
	}
	.hero-custom-layout > iframe {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
	}
	.hero-custom-overlay {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		height: 100%;
	}
	.hero-custom-overlay .mock-nav {
		border-bottom-color: rgba(200, 149, 108, 0.1);
	}
	.hero-custom-overlay .hero-body {
		flex: 1;
		min-height: 0;
	}

	/* Background layout: shader behind content, strong darkening */
	.bg-layout iframe {
		width: 100%;
		height: 100%;
		position: absolute;
		inset: 0;
	}
	.mock-overlay {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		text-align: center;
		background: rgba(10, 10, 10, 0.7);
		padding: 2rem;
		z-index: 1;
	}

	/* Accent layout: shader's left side visible, anchored to right edge */
	.accent-layout {
		overflow: hidden;
	}
	.accent-layout iframe {
		width: 100%;
		height: 100%;
		position: absolute;
		top: 0;
		left: 50%;
		-webkit-mask-image: linear-gradient(to right, transparent 0%, black 40%);
		mask-image: linear-gradient(to right, transparent 0%, black 40%);
	}
	.accent-layout > .mock-content {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		justify-content: center;
		height: 100%;
		max-width: 45%;
		padding: 2rem 2.5rem;
	}

	/* Shared mock content styles */
	.mock-content h2,
	.mock-overlay h2 {
		font-size: 1.3rem;
		font-weight: 500;
		margin-bottom: 0.6rem;
		color: #e8e0d8;
	}
	.mock-content p,
	.mock-overlay p {
		font-size: 0.75rem;
		color: rgba(232, 224, 216, 0.5);
		line-height: 1.6;
		max-width: 30ch;
	}
	.mock-overlay p {
		max-width: 42ch;
	}
	.mock-btn {
		display: inline-block;
		margin-top: 1rem;
		padding: 0.45rem 1rem;
		font-size: 0.7rem;
		font-weight: 500;
		color: #0a0a0a;
		background: #c8956c;
		border-radius: 4px;
		letter-spacing: 0.03em;
		width: fit-content;
	}
</style>
