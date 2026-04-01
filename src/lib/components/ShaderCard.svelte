<script lang="ts">
	import { getShaderNumber, type Shader } from '$lib/shaders';
	import { getPaletteForInspiration, hexToRgb } from '$lib/inspiration-palettes';
	import { colorSchemes, type ColorScheme } from '$lib/color-schemes';
	import { fetchShaderHtml, getLiveMode } from '$lib/shader-budget.svelte';
	import { toggleSaved, getSavedIds } from '$lib/saved-shaders.svelte';

	let { shader, scheme }: { shader: Shader; scheme: ColorScheme } = $props();

	const number = $derived(getShaderNumber(shader));
	const cardAccent = $derived(
		shader.inspiration ? hexToRgb(getPaletteForInspiration(shader.inspiration)?.primary ?? '#c8956c') : '200, 149, 108'
	);

	// Sprite background-position: 6 frames stacked vertically
	const schemeIndex = $derived(colorSchemes.findIndex((s) => s.id === scheme.id));
	const spritePosY = $derived(schemeIndex * 20);

	// ── Card state ───────────────────────────────────────────────────
	let visible = $state(false);
	let hovered = $state(false);
	let srcdoc = $state<string | null>(null);
	let loadIframe = $state(false);
	let iframeEl = $state<HTMLIFrameElement | null>(null);
	let warm = $state(false); // shader compiled + ready
	let fpsInjected = false;

	// Active when hovered, or when live mode is on and visible
	const active = $derived(hovered || (getLiveMode() && visible));

	// Show the iframe when active and warm
	const showIframe = $derived(warm && active);

	// ── Visibility tracking ──────────────────────────────────────────
	function observe(node: HTMLElement) {
		const obs = new IntersectionObserver(
			([e]) => {
				visible = e.isIntersecting;
			},
			{ rootMargin: '200px' }
		);
		obs.observe(node);
		return { destroy() { obs.disconnect(); } };
	}

	// ── React to live mode / visibility changes ─────────────────────
	$effect(() => {
		if (active && !srcdoc) {
			fetchShaderHtml(shader.file, shader.id).then((html) => { srcdoc = html; });
		}
		if (active && srcdoc && !loadIframe) {
			loadIframe = true;
		}
		if (active && warm) {
			resumeShader();
		} else if (!active && warm) {
			pauseShader();
		}
	});

	// ── Iframe lifecycle ─────────────────────────────────────────────
	function onIframeLoad(el: HTMLIFrameElement) {
		iframeEl = el;
		// Shader is ready — if active, keep it running; otherwise pause
		warm = true;
		if (!active) pauseShader();
	}

	function injectFpsCounter() {
		if (fpsInjected || !iframeEl) return;
		fpsInjected = true;
		try {
			var doc = iframeEl.contentDocument;
			if (!doc) return;
			var s = doc.createElement('script');
			s.textContent = `(function(){
				var f=0,lt=performance.now(),el=document.createElement("div");
				el.style.cssText="position:fixed;bottom:4px;right:6px;font:9px/1 monospace;color:rgba(255,255,255,0.35);z-index:999;pointer-events:none;text-shadow:0 1px 2px rgba(0,0,0,0.8)";
				document.body.appendChild(el);
				function t(){f++;var n=performance.now();if(n-lt>=1000){el.textContent=f+" fps";f=0;lt=n;}requestAnimationFrame(t);}
				requestAnimationFrame(t);
			})();`;
			doc.body.appendChild(s);
		} catch (_) {}
	}

	function resumeShader() {
		try { (iframeEl?.contentWindow as any)?.__shaderResume?.(); } catch (_) {}
		injectFpsCounter();
	}

	function pauseShader() {
		try { (iframeEl?.contentWindow as any)?.__shaderPause?.(); } catch (_) {}
	}

	// ── Hover ────────────────────────────────────────────────────────
	function onMouseEnter() {
		hovered = true;
	}

	function onMouseLeave() {
		hovered = false;
	}

	// ── Save ─────────────────────────────────────────────────────────
	const saved = $derived(getSavedIds().includes(shader.id));

	function onSave(e: MouseEvent) {
		e.preventDefault();
		e.stopPropagation();
		toggleSaved(shader.id);
	}
</script>

<a
	class="card"
	href="/shader/{shader.id}"
	style:--card-accent={cardAccent}
	onmouseenter={onMouseEnter}
	onmouseleave={onMouseLeave}
	use:observe
>
	<div class="card-preview">
		<!-- Static sprite preview -->
		<div
			class="preview-sprite"
			class:hidden={showIframe}
			style:background-image={visible ? `url(/previews/${shader.id}.webp)` : 'none'}
			style:background-position="0 {spritePosY}%"
		></div>

		<!-- Bookmark button -->
		<button
			class="save-btn"
			class:saved={saved}
			onclick={onSave}
			aria-label={saved ? 'Remove from saved' : 'Save shader'}
			title={saved ? 'Remove from saved' : 'Save'}
		>
			<svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" fill={saved ? 'currentColor' : 'none'} stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
				<path d="M19 21l-7-5-7 5V5a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>
			</svg>
		</button>

		<!-- Hover hint: fades when active -->
		{#if !getLiveMode()}
			<div class="hover-hint" class:hide={hovered}>
				<span>Hover to preview</span>
			</div>
		{/if}

		<!-- Iframe: created once HTML is fetched + preload slot granted -->
		{#if loadIframe && srcdoc}
			<iframe
				class:show={showIframe}
				{srcdoc}
				title={shader.title}
				style:filter={scheme.filter}
				onload={(e) => onIframeLoad(e.currentTarget as HTMLIFrameElement)}
			></iframe>
		{/if}
	</div>
	<div class="card-info">
		<div class="card-number">{number}{#if shader.inspiration} <span class="card-muse">— inspired by {shader.inspiration}</span>{/if}</div>
		<div class="card-title">{shader.title}</div>
		<div class="card-desc">{shader.desc}</div>
		<span class="card-action">Explore &rarr;</span>
	</div>
</a>

<style>
	.card {
		border: 1px solid rgba(var(--card-accent, 200, 149, 108), 0.25);
		border-radius: 8px;
		overflow: hidden;
		transition:
			border-color 0.3s ease,
			transform 0.3s ease;
		background: #111;
		display: block;
	}
	.card:hover {
		border-color: rgba(var(--card-accent, 200, 149, 108), 0.55);
		transform: translateY(-2px);
	}
	.card-preview {
		aspect-ratio: 16 / 10;
		background: #0a0a0a;
		display: flex;
		align-items: center;
		justify-content: center;
		border-bottom: 1px solid rgba(var(--card-accent, 200, 149, 108), 0.15);
		position: relative;
		overflow: hidden;
	}
	.preview-sprite {
		position: absolute;
		inset: 0;
		background-size: 100% 600%;
		background-repeat: no-repeat;
		z-index: 2;
		transition: opacity 0.4s ease;
	}
	.preview-sprite.hidden {
		opacity: 0;
	}
	.save-btn {
		position: absolute;
		top: 0.6rem;
		right: 0.6rem;
		z-index: 4;
		width: 36px;
		height: 36px;
		display: flex;
		align-items: center;
		justify-content: center;
		background: rgba(10, 10, 10, 0.6);
		backdrop-filter: blur(4px);
		-webkit-backdrop-filter: blur(4px);
		border: 1px solid rgba(200, 149, 108, 0.2);
		border-radius: 6px;
		color: rgba(232, 224, 216, 0.4);
		cursor: pointer;
		opacity: 0;
		transition: opacity 0.2s, color 0.2s, border-color 0.2s;
		padding: 0;
	}
	.card:hover .save-btn {
		opacity: 1;
	}
	.save-btn:hover {
		color: #c8956c;
		border-color: rgba(200, 149, 108, 0.5);
	}
	.save-btn.saved {
		opacity: 1;
		color: #c8956c;
		border-color: rgba(200, 149, 108, 0.5);
	}

	.hover-hint {
		position: absolute;
		bottom: 0.6rem;
		left: 50%;
		transform: translateX(-50%);
		z-index: 3;
		opacity: 1;
		transition: opacity 0.3s ease;
		pointer-events: none;
	}
	.hover-hint.hide {
		opacity: 0;
	}
	.hover-hint span {
		font-size: 0.6rem;
		font-family: inherit;
		text-transform: uppercase;
		letter-spacing: 0.12em;
		color: rgba(232, 224, 216, 0.5);
		background: rgba(10, 10, 10, 0.6);
		backdrop-filter: blur(4px);
		-webkit-backdrop-filter: blur(4px);
		padding: 0.3rem 0.65rem;
		border-radius: 3px;
		border: 1px solid rgba(200, 149, 108, 0.12);
		white-space: nowrap;
	}
	.card-preview iframe {
		width: 100%;
		height: 100%;
		border: none;
		pointer-events: none;
		position: absolute;
		top: 0;
		left: 0;
		z-index: 1;
		opacity: 0;
		transition: opacity 0.4s ease;
	}
	.card-preview iframe.show {
		opacity: 1;
	}
	.card-info {
		padding: 1.2rem 1.5rem;
	}
	.card-number {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.15em;
		color: #c8956c;
		margin-bottom: 0.3rem;
	}
	.card-muse {
		text-transform: none;
		letter-spacing: 0.02em;
		color: rgba(200, 149, 108, 0.4);
		font-style: italic;
	}
	.card-title {
		font-size: 1.1rem;
		font-weight: 500;
		margin-bottom: 0.4rem;
	}
	.card-desc {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.5);
		line-height: 1.5;
	}
	.card-action {
		display: inline-block;
		margin-top: 0.8rem;
		font-size: 0.75rem;
		color: #c8956c;
		text-transform: uppercase;
		letter-spacing: 0.1em;
	}
</style>
