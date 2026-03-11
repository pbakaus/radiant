<script lang="ts">
	import { shaders, tagLabels, type ShaderTag } from '$lib/shaders';
	import ShaderCard from '$lib/components/ShaderCard.svelte';
	import { onMount } from 'svelte';

	let activeTags: Set<ShaderTag> = $state(new Set());
	let activeRow = $state(0);
	let numColumns = $state(3);
	let gridEl: HTMLElement | undefined = $state(undefined);

	const allTags = $derived(
		Object.keys(tagLabels) as ShaderTag[]
	);

	const filteredShaders = $derived(
		activeTags.size === 0
			? shaders
			: shaders.filter((s) => s.tags.some((t) => activeTags.has(t)))
	);

	function toggleTag(tag: ShaderTag) {
		const next = new Set(activeTags);
		if (next.has(tag)) {
			next.delete(tag);
		} else {
			next.add(tag);
		}
		activeTags = next;
	}

	function updateActiveRow() {
		if (!gridEl) return;

		// Determine number of columns from the computed grid style
		var style = getComputedStyle(gridEl);
		var cols = style.gridTemplateColumns.split(' ').length;
		numColumns = cols;

		var viewportCenter = window.innerHeight / 2;
		var cards = gridEl.children;
		var bestRow = 0;
		var bestDist = Infinity;

		// Check the first card of each row to find the most centered row
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

<svelte:head>
	<title>Shaders — Canvas Animations</title>
</svelte:head>

<header>
	<div class="header-top">
		<h1>Shaders</h1>
		<p>A collection of canvas-based generative animations. Click to explore, configure, and download.</p>
	</div>
	<div class="filters">
		{#each allTags as tag}
			<button
				class="filter-btn"
				class:active={activeTags.has(tag)}
				onclick={() => toggleTag(tag)}
			>
				{tagLabels[tag]}
			</button>
		{/each}
		{#if activeTags.size > 0}
			<button class="filter-btn clear-btn" onclick={() => (activeTags = new Set())}>
				Clear
			</button>
		{/if}
	</div>
</header>

<div class="grid" bind:this={gridEl}>
	{#each filteredShaders as shader, i (shader.id)}
		<ShaderCard {shader} active={Math.floor(i / numColumns) === activeRow} />
	{/each}
</div>

{#if filteredShaders.length === 0}
	<div class="empty">No shaders match the selected filters.</div>
{/if}

<style>
	header {
		padding: 2rem 3rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.15);
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}
	header h1 {
		font-size: 1.5rem;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: #c8956c;
	}
	header p {
		margin-top: 0.5rem;
		font-size: 0.85rem;
		color: rgba(232, 224, 216, 0.5);
	}

	/* Filter bar */
	.filters {
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
	}
	.filter-btn {
		padding: 0.35rem 0.7rem;
		font-size: 0.7rem;
		font-family: inherit;
		letter-spacing: 0.03em;
		color: rgba(232, 224, 216, 0.5);
		background: transparent;
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 100px;
		cursor: pointer;
		transition:
			border-color 0.2s,
			color 0.2s,
			background 0.2s;
	}
	.filter-btn:hover {
		border-color: rgba(200, 149, 108, 0.35);
		color: #e8e0d8;
	}
	.filter-btn.active {
		border-color: rgba(200, 149, 108, 0.6);
		color: #c8956c;
		background: rgba(200, 149, 108, 0.08);
	}
	.clear-btn {
		color: rgba(232, 224, 216, 0.3);
		border-color: transparent;
	}
	.clear-btn:hover {
		color: rgba(232, 224, 216, 0.6);
	}

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
</style>
