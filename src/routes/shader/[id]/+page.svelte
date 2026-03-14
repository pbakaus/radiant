<script lang="ts">
	import ShaderPreview from '$lib/components/ShaderPreview.svelte';
	import SourceViewer from '$lib/components/SourceViewer.svelte';
	import { colorSchemes } from '$lib/color-schemes';
	import { generateLayoutSource } from '$lib/source-templates';
	import { getShaderNumber, type ShaderParam } from '$lib/shaders';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	type Layout = 'full' | 'hero' | 'background' | 'accent';

	const shader = $derived(data.shader);
	const number = $derived(getShaderNumber(shader));

	let activeLayout: Layout = $state('full');
	let activeScheme = $state(colorSchemes[0]);
	let showSource = $state(false);
	let rawSource = $state('');
	let sourceLoading = $state(false);
	let paramValues: Record<string, number> = $state({});

	// Initialize param values from defaults when shader changes
	$effect(() => {
		const vals: Record<string, number> = {};
		for (const p of shader.params ?? []) {
			vals[p.name] = p.default;
		}
		paramValues = vals;
	});

	const displaySource = $derived(
		rawSource ? generateLayoutSource(rawSource, shader, activeLayout, activeScheme) : ''
	);

	const layouts: { id: Layout; label: string; icon: string }[] = [
		{ id: 'full', label: 'Full screen', icon: '⬜' },
		{ id: 'hero', label: 'Hero section', icon: '◧' },
		{ id: 'background', label: 'Background', icon: '▣' },
		{ id: 'accent', label: 'Accent', icon: '◨' }
	];

	function sendParam(name: string, value: number) {
		paramValues[name] = value;
		const iframes = document.querySelectorAll<HTMLIFrameElement>('.preview iframe');
		for (const iframe of iframes) {
			iframe.contentWindow?.postMessage({ type: 'param', name, value }, '*');
		}
	}

	async function toggleSource() {
		if (!showSource && !rawSource) {
			sourceLoading = true;
			try {
				const res = await fetch(`/${shader.file}`);
				rawSource = await res.text();
			} catch {
				rawSource = '<!-- Failed to load source -->';
			}
			sourceLoading = false;
		}
		showSource = !showSource;
	}
</script>

<svelte:head>
	<title>{number} — {shader.title}</title>
</svelte:head>

<div class="page" class:source-open={showSource}>
	{#if showSource}
		<SourceViewer source={displaySource} loading={sourceLoading} onclose={() => (showSource = false)} />
	{/if}

	<div class="main">
		<header>
			<a href="/#gallery" class="back">&larr; Gallery</a>
			<div class="shader-id">{number} — {shader.title}</div>
		</header>
		<div class="preview-area">
			<ShaderPreview {shader} layout={activeLayout} filter={activeScheme.filter} />
		</div>
	</div>

	<aside class="sidebar">
		<div class="sidebar-inner">
			{#if shader.inspiration}
			<div class="sidebar-section inspiration-section">
				<span class="sidebar-label">Inspired by</span>
				<div class="inspiration-name">{shader.inspiration}</div>
			</div>
			{/if}

			{#if shader.credit}
			<div class="sidebar-section credit-section">
				{#if shader.creditUrl}
					<a class="credit-link" href={shader.creditUrl} target="_blank" rel="noopener noreferrer">{shader.credit}</a>
				{:else}
					<div class="credit-text">{shader.credit}</div>
				{/if}
			</div>
			{/if}

			<div class="sidebar-section">
				<span class="sidebar-label">Layout</span>
				<div class="sidebar-buttons">
					{#each layouts as layout}
						<button
							class="ctrl-btn"
							class:active={activeLayout === layout.id}
							onclick={() => (activeLayout = layout.id)}
							title={layout.label}
						>
							<span class="ctrl-icon">{layout.icon}</span>
							<span class="ctrl-text">{layout.label}</span>
						</button>
					{/each}
				</div>
			</div>

			<div class="sidebar-section">
				<span class="sidebar-label">Color scheme</span>
				<div class="sidebar-buttons">
					{#each colorSchemes as scheme}
						<button
							class="ctrl-btn"
							class:active={activeScheme.id === scheme.id}
							onclick={() => (activeScheme = scheme)}
							title={scheme.name}
						>
							<span class="scheme-swatch" style:background={scheme.swatch}></span>
							<span class="ctrl-text">{scheme.name}</span>
						</button>
					{/each}
				</div>
			</div>

			{#if shader.params?.length}
			<div class="sidebar-section">
				<span class="sidebar-label">Parameters</span>
				<div class="param-controls">
					{#each shader.params as param}
						<label class="param-row">
							<span class="param-label">{param.label}</span>
							<input
								type="range"
								class="param-slider"
								min={param.min}
								max={param.max}
								step={param.step ?? 0.01}
								value={paramValues[param.name] ?? param.default}
								oninput={(e) => sendParam(param.name, parseFloat(e.currentTarget.value))}
							/>
							<span class="param-value">{(paramValues[param.name] ?? param.default).toFixed(param.step && param.step >= 1 ? 0 : param.step && param.step >= 0.1 ? 1 : param.step && param.step >= 0.01 ? 2 : 3)}</span>
						</label>
					{/each}
				</div>
			</div>
			{/if}

			<div class="sidebar-section actions-section">
				<button class="action-btn" class:active={showSource} onclick={toggleSource}>
					{showSource ? 'Hide' : 'View'} Source
				</button>
				<a class="action-btn" href="/{shader.file}" download={shader.file}>
					Download
				</a>
				<a class="action-btn" href="/{shader.file}" target="_blank">
					Fullscreen &rarr;
				</a>
			</div>
		</div>
	</aside>
</div>

<style>
	/* App shell — viewport-filling grid */
	.page {
		display: grid;
		grid-template-columns: 1fr 240px;
		height: 100vh;
		overflow: hidden;
	}
	.page.source-open {
		grid-template-columns: minmax(320px, 2fr) 3fr 240px;
	}

	/* Main area: header + preview stacked */
	.main {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
	}

	/* Header — pinned top */
	header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: calc(var(--nav-height, 56px) + 0.75rem) 1.5rem 0.75rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.1);
		flex-shrink: 0;
	}
	.back {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.5);
		transition: color 0.2s;
	}
	.back:hover {
		color: #c8956c;
	}
	.shader-id {
		font-size: 0.8rem;
		color: #c8956c;
		letter-spacing: 0.05em;
	}

	/* Preview — fills remaining space */
	.preview-area {
		flex: 1;
		min-height: 0;
		display: flex;
		align-items: stretch;
		justify-content: center;
		padding: 1.5rem;
	}
	.preview-area > :global(*) {
		width: 100%;
		height: 100%;
	}

	/* Sidebar — anchored right, full height */
	.sidebar {
		border-left: 1px solid rgba(200, 149, 108, 0.1);
		overflow-y: auto;
		scrollbar-width: thin;
		scrollbar-color: rgba(200, 149, 108, 0.15) transparent;
	}
	.sidebar::-webkit-scrollbar {
		width: 5px;
	}
	.sidebar::-webkit-scrollbar-track {
		background: transparent;
	}
	.sidebar::-webkit-scrollbar-thumb {
		background: rgba(200, 149, 108, 0.15);
		border-radius: 3px;
	}
	.sidebar-inner {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
		padding: 1.25rem 1rem;
	}

	/* Inspiration */
	.inspiration-name {
		font-size: 0.85rem;
		font-weight: 500;
		color: #c8956c;
		font-style: italic;
	}

	/* Credit */
	.credit-link,
	.credit-text {
		font-size: 0.7rem;
		color: rgba(232, 224, 216, 0.4);
		font-style: italic;
		line-height: 1.4;
	}
	.credit-link {
		text-decoration: none;
		transition: color 0.2s;
	}
	.credit-link:hover {
		color: #c8956c;
	}

	/* Sidebar sections */
	.sidebar-section {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}
	.sidebar-label {
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.12em;
		color: rgba(232, 224, 216, 0.35);
	}
	.sidebar-buttons {
		display: flex;
		flex-wrap: wrap;
		gap: 0.25rem;
	}

	/* Control buttons */
	.ctrl-btn {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.3rem 0.55rem;
		background: transparent;
		border: 1px solid rgba(200, 149, 108, 0.1);
		border-radius: 4px;
		color: rgba(232, 224, 216, 0.5);
		font-size: 0.65rem;
		font-family: inherit;
		cursor: pointer;
		transition:
			border-color 0.2s,
			color 0.2s,
			background 0.2s;
	}
	.ctrl-btn:hover {
		border-color: rgba(200, 149, 108, 0.3);
		color: #e8e0d8;
	}
	.ctrl-btn.active {
		border-color: rgba(200, 149, 108, 0.5);
		color: #c8956c;
		background: rgba(200, 149, 108, 0.06);
	}
	.ctrl-icon {
		font-size: 0.8rem;
		line-height: 1;
	}
	.ctrl-text {
		display: inline;
	}

	/* Color scheme swatch */
	.scheme-swatch {
		display: block;
		width: 10px;
		height: 10px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	/* Parameter controls */
	.param-controls {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
	}
	.param-row {
		display: flex;
		flex-direction: column;
		gap: 0.2rem;
	}
	.param-label {
		font-size: 0.65rem;
		color: rgba(232, 224, 216, 0.5);
	}
	.param-row:has(.param-slider:active) .param-label {
		color: #c8956c;
	}
	.param-value {
		font-size: 0.6rem;
		color: rgba(232, 224, 216, 0.3);
		font-variant-numeric: tabular-nums;
		align-self: flex-end;
		margin-top: -0.15rem;
	}
	.param-slider {
		-webkit-appearance: none;
		appearance: none;
		width: 100%;
		height: 4px;
		background: rgba(200, 149, 108, 0.12);
		border-radius: 2px;
		outline: none;
		cursor: pointer;
	}
	.param-slider::-webkit-slider-thumb {
		-webkit-appearance: none;
		appearance: none;
		width: 12px;
		height: 12px;
		background: #c8956c;
		border-radius: 50%;
		cursor: pointer;
		transition: transform 0.15s;
	}
	.param-slider::-webkit-slider-thumb:hover {
		transform: scale(1.2);
	}
	.param-slider::-moz-range-thumb {
		width: 12px;
		height: 12px;
		background: #c8956c;
		border: none;
		border-radius: 50%;
		cursor: pointer;
	}

	/* Action buttons */
	.actions-section {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		padding-top: 0.75rem;
		border-top: 1px solid rgba(200, 149, 108, 0.08);
	}
	.action-btn {
		padding: 0.4rem 0.75rem;
		font-size: 0.65rem;
		font-family: inherit;
		font-weight: 500;
		letter-spacing: 0.03em;
		color: #c8956c;
		background: transparent;
		border: 1px solid rgba(200, 149, 108, 0.2);
		border-radius: 4px;
		cursor: pointer;
		transition:
			border-color 0.2s,
			background 0.2s;
		text-decoration: none;
		display: inline-block;
	}
	.action-btn:hover {
		border-color: rgba(200, 149, 108, 0.5);
		background: rgba(200, 149, 108, 0.06);
	}
	.action-btn.active {
		border-color: rgba(200, 149, 108, 0.5);
		background: rgba(200, 149, 108, 0.08);
	}
</style>
