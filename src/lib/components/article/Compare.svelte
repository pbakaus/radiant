<script lang="ts">
	import { onMount } from 'svelte';

	let {
		aSrc,
		bSrc,
		aLabel,
		bLabel,
		caption,
		aspect = '16/9',
		wide = true
	}: {
		aSrc: string;
		bSrc: string;
		aLabel: string;
		bLabel: string;
		caption?: string;
		aspect?: string;
		wide?: boolean;
	} = $props();

	let figureEl: HTMLElement;
	let mounted = $state(false);

	onMount(() => {
		const obs = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) {
						mounted = true;
						obs.disconnect();
						return;
					}
				}
			},
			{ rootMargin: '600px 0px' }
		);
		obs.observe(figureEl);
		return () => obs.disconnect();
	});
</script>

<figure class="compare" class:wide style:--aspect={aspect} bind:this={figureEl}>
	<div class="grid">
		<div class="cell">
			<div class="label">{aLabel}</div>
			{#if mounted}
				<iframe src={aSrc} title={aLabel} loading="lazy"></iframe>
			{/if}
		</div>
		<div class="cell">
			<div class="label">{bLabel}</div>
			{#if mounted}
				<iframe src={bSrc} title={bLabel} loading="lazy"></iframe>
			{/if}
		</div>
	</div>
	{#if caption}
		<figcaption>{caption}</figcaption>
	{/if}
</figure>

<style>
	.compare {
		margin: 2rem 0;
		background: #0d0d0d;
		border: 1px solid rgba(200, 149, 108, 0.1);
		border-radius: 8px;
		overflow: hidden;
	}
	.grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 1px;
		background: rgba(200, 149, 108, 0.1);
	}
	.cell {
		position: relative;
		aspect-ratio: var(--aspect, 16 / 9);
		background: #0a0a0a;
	}
	iframe {
		width: 100%;
		height: 100%;
		border: 0;
		display: block;
	}
	.label {
		position: absolute;
		top: 8px;
		left: 12px;
		font-family: 'SF Mono', monospace;
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.14em;
		color: rgba(200, 149, 108, 0.7);
		background: rgba(10, 10, 10, 0.6);
		padding: 3px 8px;
		border-radius: 3px;
		z-index: 1;
		pointer-events: none;
		backdrop-filter: blur(6px);
	}
	figcaption {
		padding: 0.7rem 1.1rem 0.9rem;
		font-size: 0.78rem;
		line-height: 1.5;
		color: rgba(232, 224, 216, 0.45);
		font-style: italic;
	}

	@media (max-width: 640px) {
		.grid {
			grid-template-columns: 1fr;
		}
	}
</style>
