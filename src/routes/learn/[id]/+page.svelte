<script lang="ts">
	import { articles } from '$lib/articles';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const ArticleComponent = $derived(articles[data.shader.id]);
</script>

<svelte:head>
	<title>{data.shader.title} — Deep Dive · Radiant</title>
	<meta name="description" content="Interactive deep dive into the {data.shader.title} shader." />
</svelte:head>

{#if ArticleComponent}
	<ArticleComponent shader={data.shader} />
{/if}
