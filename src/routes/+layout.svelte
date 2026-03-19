<script lang="ts">
	import Nav from '$lib/components/Nav.svelte';
	import { beforeNavigate, afterNavigate } from '$app/navigation';
	let { children } = $props();

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
	:global(*) {
		margin: 0;
		padding: 0;
		box-sizing: border-box;
	}
	:global(body) {
		background: #0a0a0a;
		color: #e8e0d8;
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
