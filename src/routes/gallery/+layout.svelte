<script lang="ts">
	import GallerySidebar from '$lib/components/GallerySidebar.svelte';
	import Footer from '$lib/components/Footer.svelte';
	import { colorSchemes, type ColorScheme } from '$lib/color-schemes';
	import { page } from '$app/state';
	import { onMount, setContext } from 'svelte';
	const currentPath = $derived(page.url.pathname as string);
	import { getToast } from '$lib/toast.svelte';

	let { children } = $props();
	let activeScheme: ColorScheme = $state(colorSchemes[0]);
	const toast = $derived(getToast());

	// Share active scheme with child pages via context
	setContext('colorScheme', () => activeScheme);
	let galleryEl: HTMLElement | undefined = $state(undefined);
	let galleryInView = $state(false);
	let sidebarOpen = $state(false);

	onMount(() => {
		var galObs = new IntersectionObserver(([e]) => { galleryInView = e.isIntersecting; }, { threshold: 0.01 });
		if (galleryEl) galObs.observe(galleryEl);

		return () => {
			galObs.disconnect();
		};
	});
</script>

<div class="gallery-layout">
	<!-- Mobile sidebar toggle -->
	<button class="sidebar-toggle" class:open={sidebarOpen} onclick={() => sidebarOpen = !sidebarOpen} aria-label="Toggle sidebar">
		<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
			{#if sidebarOpen}
				<line x1="18" y1="6" x2="6" y2="18" />
				<line x1="6" y1="6" x2="18" y2="18" />
			{:else}
				<line x1="3" y1="12" x2="21" y2="12" />
				<line x1="3" y1="6" x2="21" y2="6" />
				<line x1="3" y1="18" x2="21" y2="18" />
			{/if}
		</svg>
	</button>

	<!-- Mobile sidebar overlay -->
	{#if sidebarOpen}
		<button class="sidebar-overlay" onclick={() => sidebarOpen = false} aria-label="Close sidebar"></button>
	{/if}

	<div class="sidebar-wrapper" class:open={sidebarOpen}>
		<GallerySidebar {currentPath} />
	</div>

	<main class="gallery-main" bind:this={galleryEl}>
		{@render children()}
	</main>
</div>

{#if galleryInView}
<div class="floating-controls">
	{#each colorSchemes as scheme}
		<button
			class="scheme-btn"
			class:active={activeScheme.id === scheme.id}
			onclick={() => activeScheme = scheme}
			title={scheme.name}
		>
			<span class="swatch" style:background={scheme.swatch}></span>
			<span class="label">{scheme.name}</span>
		</button>
	{/each}
</div>
{/if}

<!-- Toast notification -->
{#if toast}
	<div class="toast">{toast}</div>
{/if}


<Footer />

<style>
	.gallery-layout {
		display: grid;
		grid-template-columns: 240px 1fr;
		min-height: calc(100vh - var(--nav-height, 56px));
		margin-top: var(--nav-height, 56px);
		position: relative;
	}

	.sidebar-wrapper {
		display: contents;
	}

	.gallery-main {
		min-width: 0;
	}

	.sidebar-toggle {
		display: none;
		position: fixed;
		top: calc(var(--nav-height, 56px) + 0.75rem);
		left: 0.75rem;
		z-index: 60;
		width: 36px;
		height: 36px;
		align-items: center;
		justify-content: center;
		background: rgba(10, 10, 10, 0.85);
		backdrop-filter: blur(8px);
		-webkit-backdrop-filter: blur(8px);
		border: 1px solid rgba(200, 149, 108, 0.2);
		border-radius: 8px;
		color: rgba(232, 224, 216, 0.6);
		cursor: pointer;
		transition: border-color 0.2s, color 0.2s;
		padding: 0;
	}
	.sidebar-toggle:hover {
		border-color: rgba(200, 149, 108, 0.4);
		color: #c8956c;
	}
	.sidebar-toggle.open {
		color: #c8956c;
	}

	.sidebar-overlay {
		display: none;
		border: none;
		padding: 0;
		cursor: pointer;
	}

	/* Floating color scheme controls */
	.floating-controls {
		position: fixed;
		bottom: 1.5rem;
		left: 50%;
		transform: translateX(-50%);
		z-index: 50;
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.5rem 1rem;
		background: rgba(10, 10, 10, 0.6);
		backdrop-filter: blur(12px);
		-webkit-backdrop-filter: blur(12px);
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 40px;
		animation: fadeUp 0.3s ease;
	}
	@keyframes fadeUp {
		from { opacity: 0; transform: translateX(-50%) translateY(10px); }
		to { opacity: 1; transform: translateX(-50%) translateY(0); }
	}
	.scheme-btn {
		display: flex;
		align-items: center;
		gap: 0.35rem;
		padding: 0.3rem 0.55rem;
		background: transparent;
		border: 1px solid transparent;
		border-radius: 20px;
		color: rgba(232, 224, 216, 0.4);
		font-size: 0.75rem;
		font-family: inherit;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		cursor: pointer;
		transition: border-color 0.2s, color 0.2s;
	}
	.scheme-btn:hover {
		border-color: rgba(200, 149, 108, 0.25);
		color: #e8e0d8;
	}
	.scheme-btn.active {
		border-color: rgba(200, 149, 108, 0.5);
		color: #c8956c;
	}
	.scheme-btn .swatch {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	@media (max-width: 768px) {
		.gallery-layout {
			grid-template-columns: 1fr;
		}

		.sidebar-toggle {
			display: flex;
		}

		.sidebar-wrapper {
			display: block;
			position: fixed;
			top: var(--nav-height, 56px);
			left: 0;
			bottom: 0;
			z-index: 55;
			transform: translateX(-100%);
			transition: transform 0.3s ease;
		}
		.sidebar-wrapper.open {
			transform: translateX(0);
		}

		.sidebar-overlay {
			display: block;
			position: fixed;
			inset: 0;
			z-index: 54;
			background: rgba(0, 0, 0, 0.5);
		}
	}

	/* Toast */
	.toast {
		position: fixed;
		bottom: 6.5rem;
		left: 50%;
		transform: translateX(-50%);
		z-index: 100;
		padding: 0.5rem 1.1rem;
		background: rgba(20, 20, 20, 0.92);
		backdrop-filter: blur(10px);
		-webkit-backdrop-filter: blur(10px);
		border: 1px solid rgba(200, 149, 108, 0.3);
		border-radius: 20px;
		font-size: 0.75rem;
		color: #e8e0d8;
		white-space: nowrap;
		animation: fadeUp 0.2s ease;
		pointer-events: none;
	}

	/* Saved FAB */
	.saved-fab {
		position: fixed;
		bottom: 1.5rem;
		right: 1.5rem;
		z-index: 50;
		display: flex;
		align-items: center;
		gap: 0.45rem;
		padding: 0.5rem 1rem;
		background: rgba(200, 149, 108, 0.12);
		backdrop-filter: blur(12px);
		-webkit-backdrop-filter: blur(12px);
		border: 1px solid rgba(200, 149, 108, 0.35);
		border-radius: 20px;
		color: #c8956c;
		font-size: 0.7rem;
		font-family: inherit;
		text-transform: uppercase;
		letter-spacing: 0.08em;
		text-decoration: none;
		transition: background 0.2s, border-color 0.2s;
		animation: fadeUp 0.3s ease;
	}
	.saved-fab:hover {
		background: rgba(200, 149, 108, 0.2);
		border-color: rgba(200, 149, 108, 0.6);
	}

	@media (max-width: 640px) {
		.floating-controls {
			gap: 0.25rem;
			padding: 0.4rem 0.75rem;
			border-radius: 30px;
		}
		.scheme-btn .label {
			display: none;
		}
		.scheme-btn {
			padding: 0.3rem;
		}
	}
</style>
