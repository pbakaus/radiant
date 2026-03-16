<script lang="ts">
	import GalleryGrid from '$lib/components/GalleryGrid.svelte';
	import GalleryHeader from '$lib/components/GalleryHeader.svelte';
	import { shaders } from '$lib/shaders';
</script>

<svelte:head>
	<title>All Shaders — Radiant</title>
</svelte:head>

<GalleryHeader title="All Shaders" description="{shaders.length} canvas-based generative animations. Click to explore, configure, and download." count={shaders.length} />
<GalleryGrid shaders={shaders} />
