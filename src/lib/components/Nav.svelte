<nav>
	<a href="/" class="logo">Radiant</a>
	<div class="links">
		<a href="/gallery">Gallery</a>
		<a href="/zoom">Zoom</a>
		<a href="/morph">Morph</a>
		<a href="/morph-webgpu">Morph GPU</a>
		<a href="/#how-to-use">How to Use</a>
		<a href="https://github.com/pbakaus/radiant" target="_blank" rel="noopener noreferrer">GitHub</a>
	</div>
</nav>

<style>
	nav {
		position: fixed;
		top: 0;
		left: 0;
		right: 0;
		z-index: 100;
		height: var(--nav-height, 56px);
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 2rem;
		background: rgba(10, 10, 10, 0.85);
		backdrop-filter: blur(12px);
		-webkit-backdrop-filter: blur(12px);
		border-bottom: 1px solid rgba(200, 149, 108, 0.1);
	}
	.logo {
		font-size: 1.1rem;
		font-weight: 300;
		color: #c8956c;
		letter-spacing: 0.05em;
	}
	.links {
		display: flex;
		gap: 1.5rem;
	}
	.links a {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.5);
		transition: color 0.2s;
	}
	.links a:hover {
		color: #c8956c;
	}

	@media (max-width: 640px) {
		nav {
			padding: 0 1rem;
		}
		.links {
			gap: 1rem;
		}
	}
</style>
