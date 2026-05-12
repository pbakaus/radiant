<script lang="ts">
	let {
		display = false,
		children
	}: {
		display?: boolean;
		children: import('svelte').Snippet;
	} = $props();
</script>

{#if display}
	<div class="math-display">
		{@render children()}
	</div>
{:else}
	<span class="math-inline">{@render children()}</span>
{/if}

<style>
	.math-inline {
		font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
		font-size: 0.92em;
		font-style: italic;
		color: #d4a888;
		padding: 0 0.1em;
	}
	.math-display {
		display: block;
		margin: 1.75rem auto;
		padding: 1rem 1.25rem;
		font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
		font-size: 0.95rem;
		font-style: italic;
		text-align: center;
		color: #e0c4a0;
		background: rgba(200, 149, 108, 0.04);
		border: 1px solid rgba(200, 149, 108, 0.08);
		border-radius: 6px;
		overflow-x: auto;
		line-height: 1.7;
		letter-spacing: 0.03em;
	}
</style>
