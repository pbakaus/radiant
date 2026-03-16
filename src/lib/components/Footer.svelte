<footer>
	<div class="footer-top">
		<div class="wordmark">Radiant</div>
		<nav class="footer-links">
			<a href="/gallery">Gallery</a>
			<a href="#pricing">Pricing</a>
		</nav>
		<div class="social">
			<a href="https://x.com/pbakaus" target="_blank" rel="noopener noreferrer" aria-label="X (Twitter)">
				<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
					<path d="M4 4l6.5 8L4 20h2.5l5-6.2L16 20h4l-7-8.7L19.5 4H17l-4.5 5.6L9 4H4z"/>
				</svg>
			</a>
			<a href="https://linkedin.com/in/paulbakaus" target="_blank" rel="noopener noreferrer" aria-label="LinkedIn">
				<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
					<path d="M16 8a6 6 0 0 1 6 6v7h-4v-7a2 2 0 0 0-4 0v7h-4v-7a6 6 0 0 1 6-6z"/>
					<rect x="2" y="9" width="4" height="12"/>
					<circle cx="4" cy="4" r="2"/>
				</svg>
			</a>
		</div>
	</div>
	<div class="footer-bottom">
		<a href="https://paulbakaus.com" target="_blank" rel="noopener noreferrer" class="copyright">
			&copy; 2025 Paul Bakaus
		</a>
		<a href="https://polyformproject.org/licenses/noncommercial/1.0.0/" target="_blank" rel="noopener noreferrer" class="license">
			PolyForm Noncommercial 1.0.0
		</a>
	</div>
</footer>

<style>
	footer {
		border-top: 1px solid rgba(200, 149, 108, 0.1);
		padding: 2rem 3rem;
		font-family: inherit;
	}
	.footer-top {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: 1.25rem;
	}
	.wordmark {
		font-size: 1rem;
		font-weight: 500;
		letter-spacing: 0.05em;
		color: #c8956c;
	}
	.footer-links {
		display: flex;
		gap: 1.5rem;
	}
	.footer-links a {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.5);
		text-decoration: none;
		transition: color 0.2s;
	}
	.footer-links a:hover {
		color: #e8e0d8;
	}
	.social {
		display: flex;
		gap: 1rem;
	}
	.social a {
		color: rgba(232, 224, 216, 0.4);
		transition: color 0.2s;
	}
	.social a:hover {
		color: #c8956c;
	}
	.footer-bottom {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding-top: 1rem;
		border-top: 1px solid rgba(200, 149, 108, 0.06);
	}
	.footer-bottom a {
		font-size: 0.7rem;
		color: rgba(232, 224, 216, 0.3);
		text-decoration: none;
		transition: color 0.2s;
	}
	.footer-bottom a:hover {
		color: rgba(232, 224, 216, 0.6);
	}

	@media (max-width: 560px) {
		footer {
			padding: 1.5rem;
		}
		.footer-top {
			flex-direction: column;
			gap: 1rem;
			align-items: flex-start;
		}
		.footer-bottom {
			flex-direction: column;
			gap: 0.5rem;
			align-items: flex-start;
		}
	}
</style>
