<script lang="ts">
	import GalleryGrid from '$lib/components/GalleryGrid.svelte';
	import GalleryHeader from '$lib/components/GalleryHeader.svelte';
	import { getContext } from 'svelte';
	import type { ColorScheme } from '$lib/color-schemes';

	let { data } = $props();
	const getScheme = getContext<() => ColorScheme>('colorScheme');
</script>

<svelte:head>
	<title>{data.title} — Radiant</title>
</svelte:head>

<GalleryHeader title={data.title} description={data.description} count={data.shaders.length} intro={data.intro} palette={data.palette} />
<GalleryGrid shaders={data.shaders} scheme={getScheme()} />
