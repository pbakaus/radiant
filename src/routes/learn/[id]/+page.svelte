<script lang="ts">
	import { articles } from '$lib/articles';
	import type { PageData } from './$types';

	let { data }: { data: PageData } = $props();

	const ArticleComponent = $derived(articles[data.shader.id]);

	const siteUrl = 'https://radiant-shaders.com';
	const pageUrl = $derived(`${siteUrl}/learn/${data.shader.id}`);
	const shareImageVersion = '1';
	const shareImageUrl = $derived(`${siteUrl}${data.meta.shareImage}?v=${shareImageVersion}`);
	const xHandle = '@pbakaus';
	const pageTitle = $derived(`${data.meta.title} — Radiant`);
</script>

<svelte:head>
	<title>{pageTitle}</title>
	<meta name="description" content={data.meta.subtitle} />
	<link rel="canonical" href={pageUrl} />
	<meta property="og:url" content={pageUrl} />
	<meta property="og:site_name" content="Radiant" />
	<meta property="og:title" content={pageTitle} />
	<meta property="og:description" content={data.meta.subtitle} />
	<meta property="og:image" content={shareImageUrl} />
	<meta property="og:image:type" content="image/jpeg" />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />
	<meta property="og:image:alt" content="{data.meta.title} — a Radiant deep dive on the {data.shader.title} shader." />
	<meta property="og:type" content="article" />
	<meta property="article:author" content={data.meta.author} />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:url" content={pageUrl} />
	<meta name="twitter:site" content={xHandle} />
	<meta name="twitter:creator" content={xHandle} />
	<meta name="twitter:title" content={pageTitle} />
	<meta name="twitter:description" content={data.meta.subtitle} />
	<meta name="twitter:image" content={shareImageUrl} />
	<meta name="twitter:image:alt" content="{data.meta.title} — a Radiant deep dive on the {data.shader.title} shader." />
</svelte:head>

{#if ArticleComponent}
	<ArticleComponent shader={data.shader} />
{/if}
