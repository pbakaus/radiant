<script lang="ts">
	import GalleryGrid from '$lib/components/GalleryGrid.svelte';
	import GalleryHeader from '$lib/components/GalleryHeader.svelte';
	import { shaders } from '$lib/shaders';
	import { getSavedIds } from '$lib/saved-shaders.svelte';
	import { getContext } from 'svelte';
	import type { ColorScheme } from '$lib/color-schemes';

	const getScheme = getContext<() => ColorScheme>('colorScheme');

	const savedShaders = $derived(shaders.filter((s) => getSavedIds().includes(s.id)));
</script>

<svelte:head>
	<title>Saved Shaders — Radiant</title>
</svelte:head>

<GalleryHeader
	title="Saved"
	description={savedShaders.length === 0
		? 'No saved shaders yet. Bookmark shaders from the gallery to collect them here.'
		: `${savedShaders.length} saved shader${savedShaders.length !== 1 ? 's' : ''}.`}
	count={savedShaders.length}
/>
<GalleryGrid shaders={savedShaders} scheme={getScheme()} />

{#if savedShaders.length === 0}
	<div class="empty-cta">
		<a href="/gallery/all">Browse all shaders &rarr;</a>
	</div>
{/if}

<style>
	.empty-cta {
		text-align: center;
		padding-bottom: 3rem;
	}
	.empty-cta a {
		font-size: 0.8rem;
		color: #c8956c;
		text-decoration: none;
		text-transform: uppercase;
		letter-spacing: 0.1em;
	}
	.empty-cta a:hover {
		text-decoration: underline;
	}
</style>
