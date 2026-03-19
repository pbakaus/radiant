<script lang="ts">
	import ShaderCard from '$lib/components/ShaderCard.svelte';
	import type { Shader } from '$lib/shaders';
	import type { ColorScheme } from '$lib/color-schemes';

	let { shaders, scheme }: { shaders: Shader[]; scheme: ColorScheme } = $props();
</script>

<div class="grid">
	{#each shaders as shader (shader.id)}
		<ShaderCard {shader} {scheme} />
	{/each}
</div>

{#if shaders.length === 0}
	<div class="empty">No shaders match the selected filters.</div>
{/if}

<style>
	.grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(380px, 1fr));
		gap: 1.5rem;
		padding: 2rem 3rem;
	}

	.empty {
		text-align: center;
		padding: 4rem 2rem;
		color: rgba(232, 224, 216, 0.3);
		font-size: 0.9rem;
	}

	@media (max-width: 640px) {
		.grid {
			grid-template-columns: 1fr;
			gap: 1rem;
			padding: 1rem;
		}
	}
</style>
