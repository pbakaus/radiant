<script lang="ts">
	import { hexToRgb } from '$lib/inspiration-palettes';

	let { colors }: { colors: string[] } = $props();

	const gradients = $derived(() => {
		const c = colors.map((hex) => hexToRgb(hex));
		const parts: string[] = [];
		// Wide, flat ellipses along the top edge, spilling downward like an aurora
		if (c[0]) parts.push(`radial-gradient(ellipse 70% 55% at 20% 0%, rgba(${c[0]}, 0.22) 0%, transparent 70%)`);
		if (c[1]) parts.push(`radial-gradient(ellipse 55% 50% at 80% 0%, rgba(${c[1]}, 0.18) 0%, transparent 70%)`);
		if (c[2]) parts.push(`radial-gradient(ellipse 45% 40% at 50% 0%, rgba(${c[2]}, 0.14) 0%, transparent 65%)`);
		return parts.join(', ');
	});
</script>

<div class="ambient-glow" style:background={gradients()}></div>

<style>
	.ambient-glow {
		position: absolute;
		inset: 0;
		pointer-events: none;
		animation: glow-breathe 20s ease-in-out infinite;
		z-index: 0;
	}

	@keyframes glow-breathe {
		0%, 100% {
			opacity: 1;
			transform: scaleX(1);
		}
		33% {
			opacity: 0.65;
			transform: scaleX(1.08);
		}
		66% {
			opacity: 0.85;
			transform: scaleX(0.95);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.ambient-glow {
			animation: none;
		}
	}
</style>
