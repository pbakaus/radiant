<section class="changelog" id="changelog">
	<header>
		<h2>What's New</h2>
	</header>
	<div class="entries">
		<div class="entry">
			<div class="entry-header">
				<span class="version">v1.1</span>
				<span class="date">March 19, 2026</span>
			</div>
			<ul>
				<li>Mouse & touch interactivity for all 82 shaders — move, click, or drag to interact</li>
				<li>Auto-detected interaction hints on detail pages</li>
				<li>Moonlit Ripple shader rewritten — 3D perspective camera, physically-based waves with Fresnel reflection, adjustable wave intensity (calm lake to stormy ocean), and textured moon</li>
				<li>Gallery live mode toggle — opt-in to preview all visible shaders at once</li>
				<li>Per-shader default color schemes</li>
			</ul>
		</div>
		<div class="entry">
			<div class="entry-header">
				<span class="version">v1.0</span>
				<span class="date">March 18, 2026</span>
			</div>
			<ul>
				<li>Initial release with 50+ production-ready shaders and effects</li>
				<li>Gallery with filtering by tag, technique, and inspiration</li>
				<li>Interactive homepage with color scheme selector</li>
				<li>MIT licensed, zero dependencies</li>
			</ul>
		</div>
	</div>
</section>

<style>
	.changelog {
		scroll-margin-top: var(--nav-height, 56px);
		padding: 5rem 3rem;
		max-width: 900px;
		margin: 0 auto;
		border-top: 1px solid rgba(200, 149, 108, 0.08);
	}
	header {
		margin-bottom: 2.5rem;
	}
	header h2 {
		font-size: 1.5rem;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: #c8956c;
	}
	.entries {
		display: flex;
		flex-direction: column;
		gap: 2.5rem;
	}
	.entry {
		padding-left: 1.5rem;
		border-left: 1px solid rgba(200, 149, 108, 0.15);
	}
	.entry-header {
		display: flex;
		align-items: baseline;
		gap: 1rem;
		margin-bottom: 0.75rem;
	}
	.version {
		font-size: 0.9rem;
		font-weight: 500;
		color: rgba(232, 224, 216, 0.8);
	}
	.date {
		font-size: 0.75rem;
		color: rgba(232, 224, 216, 0.3);
	}
	ul {
		list-style: none;
		padding: 0;
		margin: 0;
	}
	li {
		font-size: 0.82rem;
		line-height: 1.7;
		color: rgba(232, 224, 216, 0.45);
		padding-left: 1rem;
		position: relative;
	}
	li::before {
		content: '';
		position: absolute;
		left: 0;
		top: 0.55em;
		width: 4px;
		height: 4px;
		border-radius: 50%;
		background: rgba(200, 149, 108, 0.3);
	}
	li + li {
		margin-top: 0.25rem;
	}

	@media (max-width: 640px) {
		.changelog {
			padding: 3rem 1.5rem;
		}
	}
</style>
