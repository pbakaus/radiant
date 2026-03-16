<script lang="ts">
	import ShaderCard from '$lib/components/ShaderCard.svelte';
	import type { Shader } from '$lib/shaders';
	import { onMount } from 'svelte';

	let { shaders, filter = 'none' }: { shaders: Shader[]; filter?: string } = $props();

	let activeRow = $state(0);
	let numColumns = $state(3);
	let gridEl: HTMLElement | undefined = $state(undefined);

	function updateActiveRow() {
		if (!gridEl) return;

		var style = getComputedStyle(gridEl);
		var cols = style.gridTemplateColumns.split(' ').length;
		numColumns = cols;

		var viewportCenter = window.innerHeight / 2;
		var cards = gridEl.children;
		var bestRow = 0;
		var bestDist = Infinity;

		for (var i = 0; i < cards.length; i += cols) {
			var rect = cards[i].getBoundingClientRect();
			var cardCenter = rect.top + rect.height / 2;
			var dist = Math.abs(cardCenter - viewportCenter);
			var row = Math.floor(i / cols);
			if (dist < bestDist) {
				bestDist = dist;
				bestRow = row;
			}
		}

		activeRow = bestRow;
	}

	onMount(() => {
		updateActiveRow();

		var onScroll = () => requestAnimationFrame(updateActiveRow);
		window.addEventListener('scroll', onScroll, { passive: true });

		var ro = new ResizeObserver(updateActiveRow);
		if (gridEl) ro.observe(gridEl);

		return () => {
			window.removeEventListener('scroll', onScroll);
			ro.disconnect();
		};
	});
</script>

<div class="grid" bind:this={gridEl}>
	{#each shaders as shader, i (shader.id)}
		{@const row = Math.floor(i / numColumns)}
		<ShaderCard {shader} active={row === activeRow} preload={row === activeRow - 1 || row === activeRow + 1} {filter} />
	{/each}
</div>

{#if shaders.length === 0}
	<div class="empty">No shaders match the selected filters.</div>
{/if}

<style>
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
		gap: 1.5rem;
		padding: 2rem 3rem;
	}

	.empty {
		text-align: center;
		padding: 4rem 2rem;
		color: rgba(232, 224, 216, 0.3);
		font-size: 0.9rem;
	}

	@media (max-width: 640px) {
		.grid {
			grid-template-columns: 1fr;
			gap: 1rem;
			padding: 1rem;
		}
	}
</style>
