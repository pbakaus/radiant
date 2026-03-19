<script lang="ts">
	import GalleryGrid from '$lib/components/GalleryGrid.svelte';
	import GalleryHeader from '$lib/components/GalleryHeader.svelte';
	import { shaders } from '$lib/shaders';
	import { getContext } from 'svelte';
	import type { ColorScheme } from '$lib/color-schemes';
	const getScheme = getContext<() => ColorScheme>('colorScheme');
</script>

<svelte:head>
	<title>All Shaders — Radiant</title>
</svelte:head>

<GalleryHeader title="All Shaders" description="{shaders.length} production-ready shaders & effects. Click to explore, configure, and download." count={shaders.length} />
<GalleryGrid shaders={shaders} scheme={getScheme()} />
