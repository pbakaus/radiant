<script lang="ts">
	let {
		type = 'note',
		title,
		children
	}: {
		type?: 'note' | 'tip' | 'definition' | 'warning';
		title?: string;
		children: import('svelte').Snippet;
	} = $props();

	const labels = {
		note: 'Note',
		tip: 'Tip',
		definition: 'Definition',
		warning: 'Watch out'
	};
</script>

<aside class="aside">
	<div class="head">
		<span class="label">{title ?? labels[type]}</span>
		<span class="rule" aria-hidden="true"></span>
	</div>
	<div class="body">
		{@render children()}
	</div>
</aside>

<style>
	.aside {
		margin: 2.75rem 0;
	}
	.head {
		display: flex;
		align-items: center;
		gap: 0.85rem;
		margin-bottom: 0.85rem;
	}
	.label {
		font-family: 'SF Mono', 'Fira Code', monospace;
		font-size: 0.68rem;
		text-transform: uppercase;
		letter-spacing: 0.2em;
		color: rgba(200, 149, 108, 0.75);
		white-space: nowrap;
	}
	.rule {
		flex: 1;
		height: 1px;
		background: linear-gradient(
			to right,
			rgba(200, 149, 108, 0.25) 0%,
			rgba(200, 149, 108, 0.05) 80%,
			rgba(200, 149, 108, 0) 100%
		);
	}

	/* Body sits slightly inset and a touch quieter than the main prose,
	   so it reads as a sidenote without being walled off in a box. */
	.body {
		padding-left: 1.5rem;
	}
	.body :global(p) {
		font-size: 0.92rem;
		line-height: 1.65;
		color: rgba(232, 224, 216, 0.65);
		margin: 0 0 0.65rem;
	}
	.body :global(p:last-child) {
		margin-bottom: 0;
	}
	.body :global(code) {
		font-family: 'SF Mono', monospace;
		font-size: 0.85em;
		background: rgba(200, 149, 108, 0.08);
		color: #d4a888;
		padding: 0.05em 0.3em;
		border-radius: 2px;
	}

	@media (max-width: 640px) {
		.body {
			padding-left: 0.85rem;
		}
	}
</style>
