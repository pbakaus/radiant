<script lang="ts">
	import ShaderCard from '$lib/components/ShaderCard.svelte';
	import type { Shader } from '$lib/shaders';
	import type { ColorScheme } from '$lib/color-schemes';
	import { prioritizeIds } from '$lib/shader-budget.svelte';
	import { onMount } from 'svelte';

	let { shaders, scheme }: { shaders: Shader[]; scheme: ColorScheme } = $props();

	let gridEl: HTMLElement | undefined = $state(undefined);

	function updatePriority() {
		if (!gridEl) return;

		var style = getComputedStyle(gridEl);
		var cols = style.gridTemplateColumns.split(' ').length;
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

		// Collect shader IDs in the center row (± 1 row)
		var ids = new Set<string>();
		for (var r = bestRow - 1; r <= bestRow + 1; r++) {
			for (var c = 0; c < cols; c++) {
				var idx = r * cols + c;
				if (idx >= 0 && idx < shaders.length) {
					ids.add(shaders[idx].id);
				}
			}
		}
		prioritizeIds(ids);
	}

	onMount(() => {
		updatePriority();
		var onScroll = () => requestAnimationFrame(updatePriority);
		window.addEventListener('scroll', onScroll, { passive: true });
		var ro = new ResizeObserver(updatePriority);
		if (gridEl) ro.observe(gridEl);

		return () => {
			window.removeEventListener('scroll', onScroll);
			ro.disconnect();
		};
	});
</script>

<div class="grid" bind:this={gridEl}>
	{#each shaders as shader (shader.id)}
		<ShaderCard {shader} {scheme} />
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
