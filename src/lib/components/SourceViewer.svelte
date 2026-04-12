<script lang="ts">
	let {
		source,
		loading = false,
		onclose
	}: {
		source: string;
		loading?: boolean;
		onclose: () => void;
	} = $props();

	let copied = $state(false);

	async function copySource() {
		await navigator.clipboard.writeText(source);
		copied = true;
		setTimeout(() => (copied = false), 2000);
	}
</script>

<aside class="panel">
	<div class="panel-header">
		<span class="panel-title">Source</span>
		<div class="panel-actions">
			<button class="panel-btn" onclick={copySource}>
				{copied ? 'Copied!' : 'Copy'}
			</button>
			<button class="panel-btn close-btn" onclick={onclose} aria-label="Close source viewer">&times;</button>
		</div>
	</div>
	<div class="panel-body">
		{#if loading}
			<div class="loading">Loading source...</div>
		{:else}
			<pre><code>{source}</code></pre>
		{/if}
	</div>
</aside>

<style>
	.panel {
		display: flex;
		flex-direction: column;
		height: 100vh;
		background: #0d0d0d;
		border-right: 1px solid rgba(200, 149, 108, 0.12);
	}
	.panel-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.75rem 1rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.1);
		flex-shrink: 0;
	}
	.panel-title {
		font-size: 0.75rem;
		text-transform: uppercase;
		letter-spacing: 0.12em;
		color: rgba(232, 224, 216, 0.4);
	}
	.panel-actions {
		display: flex;
		gap: 0.25rem;
	}
	.panel-btn {
		padding: 0.3rem 0.6rem;
		font-size: 0.75rem;
		font-family: inherit;
		color: #c8956c;
		background: transparent;
		border: 1px solid rgba(200, 149, 108, 0.15);
		border-radius: 3px;
		cursor: pointer;
		transition:
			border-color 0.2s,
			background 0.2s;
	}
	.panel-btn:hover {
		border-color: rgba(200, 149, 108, 0.4);
		background: rgba(200, 149, 108, 0.06);
	}
	.close-btn {
		font-size: 1rem;
		line-height: 1;
		padding: 0.15rem 0.5rem;
	}
	.panel-body {
		flex: 1;
		overflow: auto;

		/* Firefox */
		scrollbar-width: thin;
		scrollbar-color: rgba(200, 149, 108, 0.2) transparent;
	}
	/* Webkit (Chrome, Safari, Edge) */
	.panel-body::-webkit-scrollbar {
		width: 6px;
		height: 6px;
	}
	.panel-body::-webkit-scrollbar-track {
		background: transparent;
	}
	.panel-body::-webkit-scrollbar-thumb {
		background: rgba(200, 149, 108, 0.2);
		border-radius: 3px;
	}
	.panel-body::-webkit-scrollbar-thumb:hover {
		background: rgba(200, 149, 108, 0.35);
	}

	.loading {
		padding: 1.5rem;
		color: rgba(232, 224, 216, 0.4);
		font-size: 0.8rem;
	}
	pre {
		margin: 0;
		padding: 1rem;
		overflow-x: auto;

		scrollbar-width: thin;
		scrollbar-color: rgba(200, 149, 108, 0.2) transparent;
	}
	pre::-webkit-scrollbar {
		width: 6px;
		height: 6px;
	}
	pre::-webkit-scrollbar-track {
		background: transparent;
	}
	pre::-webkit-scrollbar-thumb {
		background: rgba(200, 149, 108, 0.15);
		border-radius: 3px;
	}
	pre::-webkit-scrollbar-thumb:hover {
		background: rgba(200, 149, 108, 0.3);
	}
	code {
		font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
		font-size: 0.7rem;
		line-height: 1.7;
		color: rgba(232, 224, 216, 0.65);
		tab-size: 2;
		white-space: pre;
	}
</style>
