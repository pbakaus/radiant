<script lang="ts">
	import AmbientGlow from './AmbientGlow.svelte';
	import type { InspirationPalette } from '$lib/inspiration-palettes';
	import { getLiveMode, setLiveMode } from '$lib/shader-budget.svelte';

	let { title, description, count, intro, palette }: { title: string; description: string; count: number; intro?: string; palette?: InspirationPalette } = $props();

	const live = $derived(getLiveMode());

	function toggleLive() {
		setLiveMode(!getLiveMode());
	}
</script>

<header class="gallery-header" class:has-glow={!!palette}>
	{#if palette}
		<AmbientGlow colors={palette.colors} />
	{/if}
	<div class="header-top">
		<div class="header-title-row">
			<div>
				<h1>{title}</h1>
				<p>{description}</p>
			</div>
			<button class="live-toggle" class:active={live} onclick={toggleLive} title={live ? 'Disable live previews' : 'Enable live previews for all visible shaders'} aria-label={live ? 'Disable live previews' : 'Enable live previews'} aria-pressed={live}>
				<span class="live-dot"></span>
				<span class="live-label">Live</span>
			</button>
		</div>
		{#if intro}
			<p class="intro">{intro}</p>
		{/if}
	</div>
</header>

<style>
	.gallery-header {
		padding: 2rem 3rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.15);
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}
	.gallery-header.has-glow {
		position: relative;
		overflow: hidden;
	}
	.gallery-header.has-glow .header-top {
		position: relative;
		z-index: 1;
	}
	.header-title-row {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}
	.live-toggle {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		padding: 0.35rem 0.7rem;
		border: 1px solid rgba(200, 149, 108, 0.25);
		border-radius: 4px;
		background: transparent;
		color: rgba(232, 224, 216, 0.5);
		font-family: inherit;
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.12em;
		cursor: pointer;
		transition: border-color 0.2s, color 0.2s;
		white-space: nowrap;
		flex-shrink: 0;
		margin-top: 0.3rem;
	}
	.live-toggle:hover {
		border-color: rgba(200, 149, 108, 0.5);
		color: rgba(232, 224, 216, 0.7);
	}
	.live-toggle.active {
		border-color: rgba(220, 60, 60, 0.6);
		color: rgba(232, 224, 216, 0.85);
	}
	.live-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: rgba(232, 224, 216, 0.3);
		transition: background 0.2s, box-shadow 0.2s;
	}
	.live-toggle.active .live-dot {
		background: #dc3c3c;
		box-shadow: 0 0 6px rgba(220, 60, 60, 0.6);
	}
	.gallery-header h1 {
		font-size: 1.5rem;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: #c8956c;
	}
	.gallery-header p {
		margin-top: 0.5rem;
		font-size: 0.85rem;
		color: rgba(232, 224, 216, 0.5);
	}
	.gallery-header .intro {
		margin-top: 1rem;
		font-size: 0.9rem;
		line-height: 1.7;
		color: rgba(232, 224, 216, 0.65);
		font-style: italic;
		max-width: 72ch;
	}

	@media (max-width: 640px) {
		.gallery-header {
			padding: 1.5rem 1rem;
		}
	}
</style>
