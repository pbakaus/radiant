<script lang="ts">
	import { getShaderNumber, type Shader } from '$lib/shaders';

	let { shader }: { shader: Shader } = $props();

	const number = $derived(getShaderNumber(shader));

	let visible = $state(false);

	function observe(node: HTMLElement) {
		const observer = new IntersectionObserver(
			([entry]) => {
				visible = entry.isIntersecting;
			},
			{ rootMargin: '200px' }
		);
		observer.observe(node);
		return {
			destroy() {
				observer.disconnect();
			}
		};
	}
</script>

<a class="card" href="/shader/{shader.id}" use:observe>
	<div class="card-preview">
		{#if visible}
			<iframe src="/{shader.file}" title={shader.title}></iframe>
		{/if}
	</div>
	<div class="card-info">
		<div class="card-number">{number}{#if shader.inspiration} <span class="card-muse">— inspired by {shader.inspiration}</span>{/if}</div>
		<div class="card-title">{shader.title}</div>
		<div class="card-desc">{shader.desc}</div>
		<span class="card-action">Explore &rarr;</span>
	</div>
</a>

<style>
	.card {
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
		transition:
			border-color 0.3s ease,
			transform 0.3s ease;
		background: #111;
		display: block;
	}
	.card:hover {
		border-color: rgba(200, 149, 108, 0.4);
		transform: translateY(-2px);
	}
	.card-preview {
		aspect-ratio: 16 / 10;
		background: #0a0a0a;
		display: flex;
		align-items: center;
		justify-content: center;
		border-bottom: 1px solid rgba(200, 149, 108, 0.08);
		position: relative;
		overflow: hidden;
	}
	.card-preview iframe {
		width: 100%;
		height: 100%;
		border: none;
		pointer-events: none;
		position: absolute;
		top: 0;
		left: 0;
	}
	.card-info {
		padding: 1.2rem 1.5rem;
	}
	.card-number {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.15em;
		color: #c8956c;
		margin-bottom: 0.3rem;
	}
	.card-muse {
		text-transform: none;
		letter-spacing: 0.02em;
		color: rgba(200, 149, 108, 0.4);
		font-style: italic;
	}
	.card-title {
		font-size: 1.1rem;
		font-weight: 500;
		margin-bottom: 0.4rem;
	}
	.card-desc {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.5);
		line-height: 1.5;
	}
	.card-action {
		display: inline-block;
		margin-top: 0.8rem;
		font-size: 0.75rem;
		color: #c8956c;
		text-transform: uppercase;
		letter-spacing: 0.1em;
	}
</style>
