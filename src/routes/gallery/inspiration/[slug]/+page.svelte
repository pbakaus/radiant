<script lang="ts">
	import GalleryGrid from '$lib/components/GalleryGrid.svelte';
	import GalleryHeader from '$lib/components/GalleryHeader.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>{data.title} — Radiant</title>
</svelte:head>

<GalleryHeader title={data.title} description={data.description} count={data.shaders.length} />
<GalleryGrid shaders={data.shaders} />
