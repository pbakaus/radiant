<script lang="ts">
	import type { Shader } from '$lib/shaders';
	import { onMount } from 'svelte';

	let {
		shader,
		title,
		subtitle,
		author,
		readingTime,
		children
	}: {
		shader: Shader;
		title: string;
		subtitle?: string;
		author?: string;
		readingTime?: string;
		children: import('svelte').Snippet;
	} = $props();

	type TocItem = { id: string; label: string; level: number };
	let toc = $state<TocItem[]>([]);
	let activeId = $state<string>('');
	let articleEl: HTMLElement;
	let heroIframe: HTMLIFrameElement;

	function applyHeroConfig() {
		if (!shader.heroConfig || !heroIframe?.contentWindow) return;
		// The catalog heroConfig is tuned for wide landscape — on narrow
		// viewports the off-center BH gets pushed off-screen, so we fall back
		// to the shader's natural centered framing.
		if (window.innerWidth < 900) return;
		for (const p of shader.heroConfig.params) {
			heroIframe.contentWindow.postMessage({ type: 'param', name: p.name, value: p.value }, '*');
		}
	}
	function onHeroLoad() {
		// Hide the .label overlay inside the iframe so it doesn't clash with our title
		try {
			const doc = heroIframe.contentDocument;
			const label = doc?.querySelector('.label') as HTMLElement | null;
			if (label) label.style.display = 'none';
		} catch {
			/* ignore */
		}
		applyHeroConfig();
	}

	onMount(() => {
		// Build TOC from h2/h3 headings inside the article
		const headings = Array.from(
			articleEl.querySelectorAll<HTMLElement>('h2[id], h3[id]')
		);
		toc = headings.map((h) => ({
			id: h.id,
			label: h.textContent ?? '',
			level: h.tagName === 'H2' ? 2 : 3
		}));

		// Find the heading most recently scrolled past the trigger line —
		// roughly a third of the way down the viewport, which feels right
		// for "the section I'm currently reading."
		let raf = 0;
		function update() {
			raf = 0;
			const trigger = Math.max(120, window.innerHeight * 0.3);
			let current = headings[0]?.id ?? '';
			for (const h of headings) {
				const top = h.getBoundingClientRect().top;
				if (top <= trigger) current = h.id;
				else break;
			}
			activeId = current;
		}
		function onScroll() {
			if (!raf) raf = requestAnimationFrame(update);
		}
		update();
		window.addEventListener('scroll', onScroll, { passive: true });
		window.addEventListener('resize', onScroll);
		return () => {
			window.removeEventListener('scroll', onScroll);
			window.removeEventListener('resize', onScroll);
			if (raf) cancelAnimationFrame(raf);
		};
	});
</script>

<!-- Full-viewport cinematic hero — sits outside the centered page grid -->
<header class="hero">
	<iframe
		bind:this={heroIframe}
		src="/{shader.file}"
		title={shader.title}
		loading="eager"
		onload={onHeroLoad}
	></iframe>
	<div class="hero-vignette"></div>
	<div class="hero-fade-bottom"></div>
	<div class="hero-inner">
		<div class="hero-content">
			<div class="hero-eyebrow">
				<a href="/" class="eyebrow-link">Radiant</a>
				<span class="eyebrow-sep">/</span>
				<a href="/learn" class="eyebrow-link">Deep dive</a>
				<span class="eyebrow-sep">/</span>
				<span>{shader.title}</span>
			</div>
			<h1>{title}</h1>
			{#if subtitle}<p class="subtitle">{subtitle}</p>{/if}
			{#if author || readingTime}
				<div class="meta">
					{#if author}<span class="byline">By {author}</span>{/if}
					{#if author && readingTime}<span class="meta-sep">·</span>{/if}
					{#if readingTime}<span>{readingTime}</span>{/if}
				</div>
			{/if}
		</div>
		<div class="hero-scroll-hint">
			<span>Scroll</span>
			<svg width="12" height="18" viewBox="0 0 12 18" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
				<rect x="0.75" y="0.75" width="10.5" height="16.5" rx="5.25" stroke="currentColor" stroke-width="1.2"/>
				<circle class="scroll-dot" cx="6" cy="5.5" r="1.4" fill="currentColor"/>
			</svg>
		</div>
	</div>
</header>

<div class="page">
	<aside class="toc" aria-label="Table of contents">
		<div class="toc-inner">
			<a href="/gallery" class="back">&larr; Gallery</a>
			<div class="toc-label">Contents</div>
			<nav>
				{#each toc as item}
					<a
						href="#{item.id}"
						class="toc-item"
						class:level-3={item.level === 3}
						class:active={activeId === item.id}
					>
						{item.label}
					</a>
				{/each}
			</nav>
			<div class="toc-footer">
				<a class="footer-link" href="/shader/{shader.id}">Open playground →</a>
				<a class="footer-link" href="/{shader.file}" target="_blank">Fullscreen →</a>
			</div>
		</div>
	</aside>

	<article bind:this={articleEl}>
		<div class="prose">
			{@render children()}
		</div>

		<footer class="article-footer">
			<a class="cta" href="/shader/{shader.id}">Open the playground →</a>
			<a class="cta secondary" href="/{shader.file}" target="_blank">View source</a>
			<a class="cta secondary" href="/gallery">More shaders</a>
		</footer>
	</article>
</div>

<style>
	/* Cinematic hero — full viewport width, anchored above the page grid */
	.hero {
		position: relative;
		width: 100%;
		height: clamp(580px, 88vh, 920px);
		overflow: hidden;
		background: #050505;
		margin-top: calc(-1 * var(--nav-height, 56px));
	}
	.hero iframe {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		border: 0;
		display: block;
	}
	/* Soft left-side vignette so the title text always has contrast */
	.hero-vignette {
		position: absolute;
		inset: 0;
		background:
			radial-gradient(ellipse at 0% 50%, rgba(10, 10, 10, 0.72) 0%, rgba(10, 10, 10, 0.5) 25%, rgba(10, 10, 10, 0) 55%),
			linear-gradient(to right, rgba(10, 10, 10, 0.55) 0%, rgba(10, 10, 10, 0.0) 45%);
		pointer-events: none;
	}
	/* Smooth fade into the article below */
	.hero-fade-bottom {
		position: absolute;
		inset: auto 0 0 0;
		height: 35%;
		background: linear-gradient(180deg, rgba(10, 10, 10, 0) 0%, rgba(10, 10, 10, 0.85) 70%, #0a0a0a 100%);
		pointer-events: none;
	}
	.hero-inner {
		position: relative;
		height: 100%;
		max-width: 1200px;
		margin: 0 auto;
		padding: calc(var(--nav-height, 56px) + 2rem) 2rem 3rem;
		display: flex;
		flex-direction: column;
		justify-content: center;
		/* Let mouse drags pass through to the iframe — children that need
		   to be clickable opt back in below. */
		pointer-events: none;
	}
	.hero-content {
		max-width: 560px;
		position: relative;
		z-index: 2;
	}
	/* Re-enable interaction on the breadcrumb link only */
	.hero-inner a {
		pointer-events: auto;
	}
	.hero-eyebrow {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.55rem;
		font-family: 'SF Mono', 'Fira Code', monospace;
		font-size: 0.7rem;
		letter-spacing: 0.16em;
		text-transform: uppercase;
		color: rgba(200, 149, 108, 0.7);
		margin-bottom: 1.5rem;
	}
	.eyebrow-link {
		color: inherit;
		border-bottom: 0 !important;
		transition: color 0.2s;
	}
	.eyebrow-link:hover {
		color: #e8e0d8;
	}
	.eyebrow-sep {
		color: rgba(200, 149, 108, 0.35);
	}
	.hero h1 {
		font-size: clamp(2.4rem, 5.5vw, 4.2rem);
		font-weight: 400;
		letter-spacing: -0.025em;
		line-height: 1.02;
		color: #f0e8de;
		margin: 0 0 1.4rem;
		text-shadow: 0 2px 32px rgba(0, 0, 0, 0.5);
	}
	.hero .subtitle {
		font-size: clamp(1.05rem, 1.4vw, 1.25rem);
		line-height: 1.55;
		color: rgba(232, 224, 216, 0.78);
		max-width: 520px;
		margin: 0 0 1.5rem;
		text-shadow: 0 1px 12px rgba(0, 0, 0, 0.5);
	}
	.hero .meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.55rem;
		font-family: 'SF Mono', monospace;
		font-size: 0.75rem;
		letter-spacing: 0.05em;
		color: rgba(232, 224, 216, 0.45);
	}
	.hero .byline {
		color: rgba(200, 149, 108, 0.65);
	}
	.hero .meta-sep {
		color: rgba(232, 224, 216, 0.25);
	}
	.hero-scroll-hint {
		position: absolute;
		bottom: 1.75rem;
		left: 50%;
		transform: translateX(-50%);
		display: inline-flex;
		align-items: center;
		gap: 0.6rem;
		font-family: 'SF Mono', monospace;
		font-size: 0.65rem;
		letter-spacing: 0.18em;
		text-transform: uppercase;
		color: rgba(232, 224, 216, 0.45);
		pointer-events: none;
		z-index: 3;
	}
	.hero-scroll-hint svg {
		display: block;
	}
	.scroll-dot {
		animation: scroll-bob 1.8s ease-in-out infinite;
		transform-origin: center;
	}
	@keyframes scroll-bob {
		0%, 100% { transform: translateY(0); opacity: 0.9; }
		50%      { transform: translateY(4px); opacity: 0.35; }
	}
	@media (prefers-reduced-motion: reduce) {
		.scroll-dot { animation: none; }
	}

	.page {
		display: grid;
		grid-template-columns: 240px minmax(0, 1fr);
		max-width: 1200px;
		margin: 0 auto;
		padding-top: 0;
		gap: 2rem;
	}

	/* TOC sidebar */
	.toc {
		position: sticky;
		top: calc(var(--nav-height, 56px) + 1rem);
		align-self: start;
		max-height: calc(100vh - var(--nav-height, 56px) - 2rem);
		overflow-y: auto;
		padding: 2rem 0 2rem 1.5rem;
		scrollbar-width: thin;
		scrollbar-color: rgba(200, 149, 108, 0.15) transparent;
	}
	.toc-inner {
		display: flex;
		flex-direction: column;
		gap: 1rem;
	}
	.back {
		font-size: 0.75rem;
		color: rgba(232, 224, 216, 0.4);
		transition: color 0.2s;
	}
	.back:hover {
		color: #c8956c;
	}
	.toc-label {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.14em;
		color: rgba(232, 224, 216, 0.3);
		padding-bottom: 0.4rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.08);
	}
	.toc nav {
		display: flex;
		flex-direction: column;
		gap: 0.45rem;
	}
	.toc-item {
		font-size: 0.78rem;
		line-height: 1.4;
		color: rgba(232, 224, 216, 0.5);
		transition: color 0.2s;
		padding-left: 0.5rem;
		border-left: 1px solid transparent;
	}
	.toc-item.level-3 {
		padding-left: 1.25rem;
		font-size: 0.72rem;
		color: rgba(232, 224, 216, 0.35);
	}
	.toc-item:hover {
		color: #e8e0d8;
	}
	.toc-item.active {
		color: #c8956c;
		border-left-color: rgba(200, 149, 108, 0.45);
	}
	.toc-footer {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-top: 0.5rem;
		padding-top: 1rem;
		border-top: 1px solid rgba(200, 149, 108, 0.08);
	}
	.footer-link {
		font-size: 0.75rem;
		color: rgba(232, 224, 216, 0.5);
		transition: color 0.2s;
	}
	.footer-link:hover {
		color: #c8956c;
	}

	/* Article */
	article {
		min-width: 0;
		padding: 3rem 2rem 6rem;
	}

	/* Prose column — text elements are width-capped individually so .wide
	   blocks can break out and use the full article column. */
	.prose :global(:where(p, h2, h3, h4, ul, ol, blockquote)) {
		max-width: 720px;
	}
	.prose :global(h2) {
		font-size: 1.55rem;
		font-weight: 500;
		letter-spacing: -0.01em;
		color: #e8e0d8;
		margin: 4rem 0 1rem;
		scroll-margin-top: calc(var(--nav-height, 56px) + 1rem);
	}
	.prose :global(h3) {
		font-size: 1.15rem;
		font-weight: 500;
		color: #e8e0d8;
		margin: 2.5rem 0 0.75rem;
		scroll-margin-top: calc(var(--nav-height, 56px) + 1rem);
	}
	.prose :global(p) {
		font-size: 1rem;
		line-height: 1.7;
		color: rgba(232, 224, 216, 0.78);
		margin: 0 0 1.15rem;
	}
	.prose :global(p code),
	.prose :global(li code) {
		font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
		font-size: 0.88em;
		background: rgba(200, 149, 108, 0.08);
		color: #d4a888;
		padding: 0.1em 0.35em;
		border-radius: 3px;
	}
	.prose :global(a) {
		color: #c8956c;
		border-bottom: 1px solid rgba(200, 149, 108, 0.3);
		transition: border-color 0.2s;
	}
	.prose :global(a:hover) {
		border-bottom-color: #c8956c;
	}
	.prose :global(strong) {
		color: #e8e0d8;
		font-weight: 600;
	}
	.prose :global(em) {
		color: rgba(232, 224, 216, 0.9);
	}
	.prose :global(ul),
	.prose :global(ol) {
		padding-left: 1.5rem;
		margin: 0 0 1.15rem;
	}
	.prose :global(li) {
		font-size: 1rem;
		line-height: 1.7;
		color: rgba(232, 224, 216, 0.78);
		margin-bottom: 0.4rem;
	}
	.prose :global(li::marker) {
		color: rgba(200, 149, 108, 0.5);
	}

	/* Wide elements (Sandbox/Compare) use the full article column width
	   instead of the 720px prose cap. */
	.prose :global(.wide) {
		max-width: 100%;
		width: 100%;
	}

	/* Article footer */
	.article-footer {
		display: flex;
		flex-wrap: wrap;
		gap: 0.75rem;
		margin-top: 5rem;
		padding-top: 2.5rem;
		border-top: 1px solid rgba(200, 149, 108, 0.1);
	}
	.cta {
		display: inline-block;
		padding: 0.6rem 1.1rem;
		font-size: 0.85rem;
		font-weight: 500;
		color: #0a0a0a;
		background: #c8956c;
		border-radius: 4px;
		text-decoration: none;
		transition: background 0.2s;
	}
	.cta:hover {
		background: #d4a888;
	}
	.cta.secondary {
		color: #c8956c;
		background: transparent;
		border: 1px solid rgba(200, 149, 108, 0.3);
	}
	.cta.secondary:hover {
		background: rgba(200, 149, 108, 0.06);
		border-color: rgba(200, 149, 108, 0.5);
	}

	@media (max-width: 900px) {
		/* Mobile hero stacks vertically: shader banner up top, text content
		   below in normal flow. Overlay vignettes don't work at this width —
		   the BH dominates the frame and competes with the title. */
		.hero {
			height: auto;
			min-height: 0;
			margin-top: 0;
			padding-top: var(--nav-height, 56px);
			overflow: visible;
		}
		.hero iframe {
			position: relative;
			width: 100%;
			height: auto;
			aspect-ratio: 16 / 10;
			display: block;
		}
		.hero-vignette,
		.hero-fade-bottom,
		.hero-scroll-hint {
			display: none;
		}
		.hero-inner {
			position: relative;
			height: auto;
			max-width: none;
			padding: 1.75rem 1.25rem 1.25rem;
			display: block;
			pointer-events: auto;
		}
		.hero-content {
			max-width: 100%;
		}
		.hero h1 {
			font-size: clamp(1.8rem, 7vw, 2.4rem);
			text-shadow: none;
		}
		.hero .subtitle {
			font-size: 1rem;
			text-shadow: none;
		}
		.hero-eyebrow {
			margin-bottom: 1rem;
		}

		.page {
			grid-template-columns: 1fr;
			gap: 0;
		}
		.toc {
			display: none;
		}
		article {
			padding: 1.5rem 1.25rem 4rem;
		}
		.prose :global(.wide) {
			margin-left: -1.25rem;
			margin-right: -1.25rem;
			max-width: calc(100% + 2.5rem);
			width: calc(100% + 2.5rem);
		}
	}
</style>
