<script lang="ts">
	import { getSidebarSections } from '$lib/gallery-filters';

	let { currentPath }: { currentPath: string } = $props();

	const sections = getSidebarSections();
</script>

<aside class="sidebar">
	{#each sections as section}
		<div class="section">
			<h3>{section.title}</h3>
			{#each section.categories as cat}
				<a href={cat.href} class:active={currentPath === cat.href}>
					<span class="label">{cat.label}</span>
					<span class="count">{cat.count}</span>
				</a>
			{/each}
		</div>
	{/each}
</aside>

<style>
	.sidebar {
		width: 240px;
		height: calc(100vh - var(--nav-height, 56px));
		position: sticky;
		top: var(--nav-height, 56px);
		overflow-y: auto;
		background: #0f0f0f;
		border-right: 1px solid rgba(200, 149, 108, 0.1);
		padding: 1.5rem 0;
		flex-shrink: 0;
	}
	.section {
		margin-bottom: 1.5rem;
	}
	.section h3 {
		font-size: 0.6rem;
		text-transform: uppercase;
		letter-spacing: 0.15em;
		color: #c8956c;
		padding: 0 1rem;
		margin-bottom: 0.5rem;
		font-weight: 500;
	}
	.section a {
		display: flex;
		align-items: center;
		justify-content: space-between;
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.5);
		padding: 0.4rem 1rem;
		border-left: 2px solid transparent;
		transition: color 0.2s, background 0.2s, border-color 0.2s;
		text-decoration: none;
	}
	.section a:hover {
		color: #e8e0d8;
	}
	.section a.active {
		color: #c8956c;
		background: rgba(200, 149, 108, 0.08);
		border-left-color: #c8956c;
	}
	.count {
		font-size: 0.65rem;
		color: rgba(232, 224, 216, 0.25);
	}
	.section a.active .count {
		color: rgba(200, 149, 108, 0.5);
	}

	/* Scrollbar for sidebar */
	.sidebar::-webkit-scrollbar {
		width: 4px;
	}
	.sidebar::-webkit-scrollbar-track {
		background: transparent;
	}
	.sidebar::-webkit-scrollbar-thumb {
		background: rgba(200, 149, 108, 0.15);
		border-radius: 2px;
	}

	@media (max-width: 768px) {
		.sidebar {
			display: none;
		}
	}
</style>
