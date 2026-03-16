<script lang="ts">
	let { title, description, count }: { title: string; description: string; count: number } = $props();
</script>

<header class="gallery-header">
	<div class="header-top">
		<h1>{title}</h1>
		<p>{description}</p>
	</div>
</header>

<style>
	.gallery-header {
		padding: 2rem 3rem;
		border-bottom: 1px solid rgba(200, 149, 108, 0.15);
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
	}
	.gallery-header h1 {
		font-size: 1.5rem;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: #c8956c;
	}
	.gallery-header p {
		margin-top: 0.5rem;
		font-size: 0.85rem;
		color: rgba(232, 224, 216, 0.5);
	}

	@media (max-width: 640px) {
		.gallery-header {
			padding: 1.5rem 1rem;
		}
	}
</style>
