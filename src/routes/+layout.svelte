<script lang="ts">
	import Nav from '$lib/components/Nav.svelte';
	import { beforeNavigate, afterNavigate } from '$app/navigation';
	import { onMount } from 'svelte';
	import { initSavedShaders } from '$lib/saved-shaders.svelte';
	let { children } = $props();

	onMount(() => {
		initSavedShaders();
	});

	// Disable smooth scroll during back/forward navigation so
	// the browser's scroll restoration works instantly.
	beforeNavigate(({ type }) => {
		if (type === 'popstate') {
			document.documentElement.classList.add('restoring-scroll');
		}
	});
	afterNavigate(({ type }) => {
		if (type === 'popstate') {
			// Remove after a tick so the restored position sticks
			requestAnimationFrame(() => {
				document.documentElement.classList.remove('restoring-scroll');
			});
		}
	});
</script>

<svelte:head>
	<link rel="preconnect" href="https://fonts.googleapis.com" />
	<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin="anonymous" />
	<link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600&display=swap" rel="stylesheet" />
</svelte:head>

<Nav />
{@render children()}

<style>
	:root {
		--color-bg: #0a0a0a;
		--color-surface: #111;
		--color-accent: #c8956c;
		--color-accent-rgb: 200, 149, 108;
		--color-text: #e8e0d8;
		--color-text-muted: rgba(232, 224, 216, 0.5);
		--color-border: rgba(200, 149, 108, 0.1);
	}
	:global(*) {
		margin: 0;
		padding: 0;
		box-sizing: border-box;
	}
	:global(:focus-visible) {
		outline: 2px solid var(--color-accent);
		outline-offset: 2px;
		border-radius: 2px;
	}
	:global(body) {
		background: var(--color-bg);
		color: var(--color-text);
		font-family: 'Inter', -apple-system, system-ui, sans-serif;
		min-height: 100vh;
	}
	:global(a) {
		color: inherit;
		text-decoration: none;
	}
	/* Scrollbar — Webkit */
	:global(::-webkit-scrollbar) {
		width: 6px;
		height: 6px;
	}
	:global(::-webkit-scrollbar-track) {
		background: transparent;
	}
	:global(::-webkit-scrollbar-thumb) {
		background: rgba(200, 149, 108, 0.2);
		border-radius: 3px;
	}
	:global(::-webkit-scrollbar-thumb:hover) {
		background: rgba(200, 149, 108, 0.35);
	}
	/* Scrollbar — Firefox */
	:global(html) {
		scrollbar-width: thin;
		scrollbar-color: rgba(200, 149, 108, 0.2) transparent;
		--nav-height: 56px;
	}
	@media (prefers-reduced-motion: no-preference) {
		:global(html:not(.restoring-scroll)) {
			scroll-behavior: smooth;
		}
	}
</style>
