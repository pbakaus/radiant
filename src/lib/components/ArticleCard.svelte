<script lang="ts">
	import type { Shader } from '$lib/shaders';
	import type { ArticleMeta } from '$lib/articles';

	let { id, shader, meta }: { id: string; shader: Shader; meta: ArticleMeta } = $props();
</script>

<a class="card" href="/learn/{id}">
	<div
		class="cover"
		style:background-image="url(/previews/{shader.id}.webp)"
		role="img"
		aria-label="{shader.title} shader preview"
	></div>
	<div class="body">
		<div class="eyebrow">Deep dive · {shader.title}</div>
		<h2 class="title">{meta.title}</h2>
		<p class="subtitle">{meta.subtitle}</p>
		<div class="meta">
			<span class="byline">By {meta.author}</span>
			<span class="sep">·</span>
			<span>{meta.readingTime}</span>
		</div>
	</div>
</a>

<style>
	.card {
		display: block;
		background: #111;
		border: 1px solid rgba(200, 149, 108, 0.18);
		border-radius: 10px;
		overflow: hidden;
		text-decoration: none;
		transition:
			border-color 0.25s ease,
			transform 0.25s ease;
	}
	.card:hover,
	.card:focus-within {
		border-color: rgba(200, 149, 108, 0.5);
		transform: translateY(-3px);
	}
	/* Cover uses the shader's preview sprite — first frame (amber scheme)
	   in a 6-frame vertical strip, so background-size: 100% 600% pins the top. */
	.cover {
		aspect-ratio: 16 / 10;
		background: #0a0a0a no-repeat top center;
		background-size: 100% 600%;
		border-bottom: 1px solid rgba(200, 149, 108, 0.12);
	}
	.body {
		padding: 1.5rem 1.6rem 1.6rem;
	}
	.eyebrow {
		font-family: 'SF Mono', 'Fira Code', monospace;
		font-size: 0.7rem;
		letter-spacing: 0.16em;
		text-transform: uppercase;
		color: rgba(200, 149, 108, 0.75);
		margin-bottom: 0.7rem;
	}
	.title {
		font-size: 1.45rem;
		font-weight: 500;
		letter-spacing: -0.015em;
		line-height: 1.2;
		color: #e8e0d8;
		margin: 0 0 0.6rem;
	}
	.subtitle {
		font-size: 0.9rem;
		line-height: 1.55;
		color: rgba(232, 224, 216, 0.6);
		margin: 0 0 1.1rem;
		display: -webkit-box;
		-webkit-line-clamp: 3;
		line-clamp: 3;
		-webkit-box-orient: vertical;
		overflow: hidden;
	}
	.meta {
		display: flex;
		flex-wrap: wrap;
		gap: 0.45rem;
		font-family: 'SF Mono', 'Fira Code', monospace;
		font-size: 0.72rem;
		letter-spacing: 0.04em;
		color: rgba(232, 224, 216, 0.45);
	}
	.byline {
		color: rgba(200, 149, 108, 0.7);
	}
	.sep {
		color: rgba(232, 224, 216, 0.25);
	}

	@media (max-width: 640px) {
		.title {
			font-size: 1.25rem;
		}
		.body {
			padding: 1.2rem 1.25rem 1.4rem;
		}
	}
</style>
