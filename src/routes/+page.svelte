<script lang="ts">
	import { shaders } from '$lib/shaders';
	import { colorSchemes, type ColorScheme } from '$lib/color-schemes';
	import ShaderCard from '$lib/components/ShaderCard.svelte';
	import Hero from '$lib/components/Hero.svelte';
	import HowToUse from '$lib/components/HowToUse.svelte';
	import Changelog from '$lib/components/Changelog.svelte';
	import Pricing from '$lib/components/Pricing.svelte';
	import Footer from '$lib/components/Footer.svelte';
	import { onMount } from 'svelte';

	let activeScheme: ColorScheme = $state(colorSchemes[0]);
	let heroVisible = $state(true);
	let heroEl: HTMLElement | undefined = $state(undefined);
	const siteUrl = 'https://radiant-shaders.com';
	const pageUrl = siteUrl;
	const shareImageUrl = `${siteUrl}/og-image.png`;

	const featuredIds = ['event-horizon', 'gilded-fracture', 'kinetic-grid', 'flow-field', 'torn-paper', 'silk-cascade'];
	const featuredShaders = $derived(
		featuredIds
			.map((id) => shaders.find((s) => s.id === id))
			.filter((s): s is NonNullable<typeof s> => s != null)
	);

	onMount(() => {
		var heroObs = new IntersectionObserver(([e]) => { heroVisible = e.isIntersecting; }, { threshold: 0.05 });
		if (heroEl) heroObs.observe(heroEl);

		return () => {
			heroObs.disconnect();
		};
	});
</script>

<svelte:head>
	<title>Radiant — Open Source Shaders & Effects</title>
	<meta name="description" content="130+ production-ready shaders and visual effects for the web. No dependencies. Just drop in." />
	<link rel="canonical" href={pageUrl} />
	<meta property="og:url" content={pageUrl} />
	<meta property="og:title" content="Radiant — Open Source Shaders & Effects" />
	<meta property="og:description" content="130+ production-ready shaders and visual effects for the web. No dependencies. Just drop in." />
	<meta property="og:image" content={shareImageUrl} />
	<meta property="og:image:type" content="image/png" />
	<meta property="og:image:alt" content="Radiant gallery preview showing multiple generative shaders and effects." />
	<meta property="og:type" content="website" />
	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:title" content="Radiant — Open Source Shaders & Effects" />
	<meta name="twitter:description" content="130+ production-ready shaders and visual effects for the web. No dependencies. Just drop in." />
	<meta name="twitter:image" content={shareImageUrl} />
	<meta name="twitter:image:alt" content="Radiant gallery preview showing multiple generative shaders and effects." />
</svelte:head>

<div bind:this={heroEl}>
	<Hero scheme={activeScheme} visible={heroVisible} onschemechange={(s) => activeScheme = s} />
</div>

<section class="featured" id="gallery">
	<header>
		<h2>Featured</h2>
		<p>A curated selection from the collection.</p>
	</header>
	<div class="featured-grid">
		{#each featuredShaders as shader (shader.id)}
			<ShaderCard {shader} scheme={activeScheme} />
		{/each}
	</div>
	<div class="browse-cta">
		<a href="/gallery" class="btn btn-solid">Browse Full Collection &rarr;</a>
	</div>
</section>

<HowToUse />

<Changelog />

<Pricing />

<Footer />

<style>
	.featured {
		scroll-margin-top: var(--nav-height, 56px);
		padding: 4rem 3rem;
	}
	.featured header {
		margin-bottom: 2rem;
	}
	.featured header h2 {
		font-size: 1.5rem;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: #c8956c;
	}
	.featured header p {
		margin-top: 0.5rem;
		font-size: 0.85rem;
		color: rgba(232, 224, 216, 0.5);
	}
	.featured-grid {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: 1.25rem;
	}
	.browse-cta {
		text-align: center;
		margin-top: 2.5rem;
	}
	.btn {
		display: inline-block;
		padding: 0.75rem 2rem;
		font-size: 0.9rem;
		font-weight: 500;
		border-radius: 6px;
		letter-spacing: 0.02em;
		transition: background 0.2s;
		cursor: pointer;
		text-decoration: none;
	}
	.btn-solid {
		background: #c8956c;
		color: #0a0a0a;
	}
	.btn-solid:hover {
		background: #d4a57c;
	}

	@media (max-width: 900px) {
		.featured-grid {
			grid-template-columns: repeat(2, 1fr);
		}
	}
	@media (max-width: 640px) {
		.featured {
			padding: 3rem 1.5rem;
		}
		.featured-grid {
			grid-template-columns: 1fr;
		}
	}
</style>
