#!/usr/bin/env node
/**
 * Generate social-share images for deep-dive articles.
 *
 * Renders the shader at 1200×630 with the article title, subtitle, and
 * byline overlaid on the left vignette — same composition as the article
 * hero. Saves to static/share/learn-<id>.jpg.
 *
 * Usage:
 *   node scripts/generate-share-image.mjs --shader=event-horizon
 *   node scripts/generate-share-image.mjs --all
 */

import puppeteer from 'puppeteer';
import { createServer } from 'http';
import { readFile, mkdir } from 'fs/promises';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const ROOT = join(__dirname, '..');
const STATIC = join(ROOT, 'static');
const OUT_DIR = join(STATIC, 'share');

const WIDTH = 1200;
const HEIGHT = 630;
const DPR = 2;

// Long warmup so the shader is in a settled, photogenic state.
// Rain-style shaders accumulate state over time and need more.
const WARMUP_MS = 10000;

// Per-shader capture-time parameter overrides (sent via postMessage during
// warmup). Used to push state-accumulating shaders into a richer state for
// the share image without changing their gallery defaults.
const CAPTURE_PARAMS = {
	'rain-on-glass': { RAIN_AMOUNT: 2.0 },
	'rain-umbrella': { RAIN_AMOUNT: 2.0 }
};

// ───────────────────────────────────────────────────────────────────────────
// Parse shader list + heroConfig from src/lib/shaders.ts
// ───────────────────────────────────────────────────────────────────────────
async function loadShaderList() {
	const src = await readFile(join(ROOT, 'src/lib/shaders.ts'), 'utf8');
	const entries = [];
	// Match each shader object's id, file, and optional heroConfig.params
	const objRe = /\{\s*id:\s*'([^']+)'[\s\S]*?file:\s*'([^']+)'([\s\S]*?)\n\t\}/g;
	let m;
	while ((m = objRe.exec(src)) !== null) {
		const id = m[1];
		const file = m[2];
		const rest = m[3];
		let heroParams = null;
		const heroMatch = rest.match(/heroConfig:\s*\{\s*params:\s*\[([\s\S]*?)\]\s*\}/);
		if (heroMatch) {
			heroParams = [];
			const paramRe = /\{\s*name:\s*'([^']+)',\s*value:\s*([\-\d.]+)\s*\}/g;
			let pm;
			while ((pm = paramRe.exec(heroMatch[1])) !== null) {
				heroParams.push({ name: pm[1], value: parseFloat(pm[2]) });
			}
		}
		entries.push({ id, file, heroParams });
	}
	return entries;
}

// ───────────────────────────────────────────────────────────────────────────
// Parse article metadata from src/lib/articles/index.ts
// ───────────────────────────────────────────────────────────────────────────
async function loadArticleMeta() {
	const src = await readFile(join(ROOT, 'src/lib/articles/index.ts'), 'utf8');
	const out = {};
	// Each entry: 'id': { title: '...', subtitle: '...', author: '...', readingTime: '...', shareImage: '...' }
	const entryRe = /'([a-z0-9-]+)':\s*\{([\s\S]*?)\n\t\}/g;
	let m;
	while ((m = entryRe.exec(src)) !== null) {
		const id = m[1];
		const body = m[2];
		const get = (key) => {
			// Allow plain quoted strings or multi-line strings with continuations
			const re = new RegExp(`${key}:\\s*\\n?\\s*'((?:[^'\\\\]|\\\\.)*)'`, 's');
			const mm = body.match(re);
			return mm ? mm[1].replace(/\\'/g, "'") : null;
		};
		const title = get('title');
		const subtitle = get('subtitle');
		const author = get('author');
		const shareImage = get('shareImage');
		if (title) {
			out[id] = { title, subtitle, author, shareImage };
		}
	}
	return out;
}

// ───────────────────────────────────────────────────────────────────────────
// Static server for /static
// ───────────────────────────────────────────────────────────────────────────
function startServer(port = 0) {
	const MIME = {
		'.html': 'text/html',
		'.js': 'application/javascript',
		'.css': 'text/css',
		'.png': 'image/png',
		'.jpg': 'image/jpeg',
		'.webp': 'image/webp',
		'.svg': 'image/svg+xml',
		'.woff2': 'font/woff2'
	};
	const server = createServer(async (req, res) => {
		const url = new URL(req.url, `http://localhost`);
		const filePath = join(STATIC, decodeURIComponent(url.pathname));
		try {
			const data = await readFile(filePath);
			const ext = extname(filePath);
			res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
			res.end(data);
		} catch {
			res.writeHead(404);
			res.end('Not found');
		}
	});
	return new Promise((resolve) => {
		server.listen(port, '127.0.0.1', () => resolve(server));
	});
}

// ───────────────────────────────────────────────────────────────────────────
// Capture one share image
// ───────────────────────────────────────────────────────────────────────────
async function captureShareImage(page, baseUrl, shader, meta) {
	const url = `${baseUrl}/${shader.file}`;
	await page.goto(url, { waitUntil: 'domcontentloaded' });

	// Combine hero config with capture-time overrides (latter wins)
	const captureOverrides = CAPTURE_PARAMS[shader.id] || {};
	const combinedParams = [...(shader.heroParams || [])];
	for (const [name, value] of Object.entries(captureOverrides)) {
		const existing = combinedParams.find((p) => p.name === name);
		if (existing) existing.value = value;
		else combinedParams.push({ name, value });
	}

	// Hide the shader's own label, apply params, inject fonts + overlay.
	await page.evaluate(
		(heroParams, meta) => {
			// Hide the shader's built-in label
			const label = document.querySelector('.label');
			if (label) label.style.display = 'none';

			// Apply hero config (e.g. positions the BH off-center to the right)
			if (heroParams) {
				for (const p of heroParams) {
					window.postMessage({ type: 'param', name: p.name, value: p.value }, '*');
				}
			}

			// Google Fonts — Inter for the title, system mono for the meta lines
			const preconnect1 = document.createElement('link');
			preconnect1.rel = 'preconnect';
			preconnect1.href = 'https://fonts.googleapis.com';
			document.head.appendChild(preconnect1);
			const preconnect2 = document.createElement('link');
			preconnect2.rel = 'preconnect';
			preconnect2.href = 'https://fonts.gstatic.com';
			preconnect2.crossOrigin = 'anonymous';
			document.head.appendChild(preconnect2);
			const fontLink = document.createElement('link');
			fontLink.rel = 'stylesheet';
			fontLink.href =
				'https://fonts.googleapis.com/css2?family=Inter:wght@400;500&family=JetBrains+Mono:wght@400;500&display=swap';
			document.head.appendChild(fontLink);

			// Overlay style + content
			const style = document.createElement('style');
			style.textContent = `
				.share-vignette {
					position: fixed; inset: 0; z-index: 5; pointer-events: none;
					background:
						radial-gradient(ellipse 70% 100% at 0% 50%, rgba(10,10,10,0.85) 0%, rgba(10,10,10,0.45) 35%, rgba(10,10,10,0) 65%),
						linear-gradient(to right, rgba(10,10,10,0.55) 0%, rgba(10,10,10,0) 50%),
						linear-gradient(to bottom, rgba(10,10,10,0) 50%, rgba(10,10,10,0.35) 100%);
				}
				.share-content {
					position: fixed;
					top: 50%; left: 64px;
					transform: translateY(-50%);
					max-width: 560px;
					z-index: 6;
					font-family: 'Inter', system-ui, sans-serif;
				}
				.share-eyebrow {
					font-family: 'JetBrains Mono', 'SF Mono', 'Monaco', monospace;
					font-size: 14px;
					font-weight: 500;
					letter-spacing: 0.22em;
					text-transform: uppercase;
					color: rgba(200, 149, 108, 0.85);
					margin-bottom: 28px;
				}
				.share-title {
					font-size: 64px;
					font-weight: 400;
					letter-spacing: -0.025em;
					line-height: 1.04;
					color: #f0e8de;
					margin: 0 0 20px;
					text-shadow: 0 2px 32px rgba(0,0,0,0.6);
				}
				.share-subtitle {
					font-size: 19px;
					line-height: 1.5;
					color: rgba(232, 224, 216, 0.78);
					margin: 0 0 28px;
					text-shadow: 0 1px 16px rgba(0,0,0,0.5);
					max-width: 480px;
				}
				.share-byline {
					font-family: 'JetBrains Mono', 'SF Mono', monospace;
					font-size: 14px;
					letter-spacing: 0.04em;
					color: rgba(200, 149, 108, 0.75);
				}
				.share-brand {
					position: fixed; bottom: 36px; right: 44px;
					z-index: 6;
					font-family: 'JetBrains Mono', 'SF Mono', monospace;
					font-size: 15px;
					font-weight: 500;
					letter-spacing: 0.28em;
					text-transform: uppercase;
					color: rgba(200, 149, 108, 0.65);
				}
			`;
			document.head.appendChild(style);

			const vignette = document.createElement('div');
			vignette.className = 'share-vignette';
			document.body.appendChild(vignette);

			const content = document.createElement('div');
			content.className = 'share-content';
			content.innerHTML = `
				<div class="share-eyebrow">Radiant · Deep dive</div>
				<h1 class="share-title">${meta.title}</h1>
				${meta.subtitle ? `<p class="share-subtitle">${meta.subtitle}</p>` : ''}
				${meta.author ? `<div class="share-byline">By ${meta.author}</div>` : ''}
			`;
			document.body.appendChild(content);

			const brand = document.createElement('div');
			brand.className = 'share-brand';
			brand.textContent = 'Radiant';
			document.body.appendChild(brand);
		},
		combinedParams,
		meta
	);

	// Wait for the fonts to actually load, then for the shader to settle.
	await page.evaluate(() => document.fonts.ready);
	await new Promise((r) => setTimeout(r, WARMUP_MS));

	const buf = await page.screenshot({
		type: 'jpeg',
		quality: 92,
		clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT }
	});
	return buf;
}

// ───────────────────────────────────────────────────────────────────────────
// Main
// ───────────────────────────────────────────────────────────────────────────
async function main() {
	const args = process.argv.slice(2);
	const onlyId = args.find((a) => a.startsWith('--shader='))?.split('=')[1];
	const all = args.includes('--all');

	if (!onlyId && !all) {
		console.error('Usage: node scripts/generate-share-image.mjs --shader=<id>  |  --all');
		process.exit(1);
	}

	const shaderList = await loadShaderList();
	const metaMap = await loadArticleMeta();
	const articleIds = Object.keys(metaMap);
	const targets = (onlyId ? [onlyId] : articleIds)
		.map((id) => {
			const shader = shaderList.find((s) => s.id === id);
			const meta = metaMap[id];
			if (!shader || !meta) return null;
			return { id, shader, meta };
		})
		.filter(Boolean);

	if (!targets.length) {
		console.error('No matching article + shader pairs found.');
		process.exit(1);
	}

	await mkdir(OUT_DIR, { recursive: true });

	const server = await startServer();
	const port = server.address().port;
	const baseUrl = `http://127.0.0.1:${port}`;
	console.log(`Static server on port ${port}`);
	console.log(`Capture: ${WIDTH}×${HEIGHT} @ ${DPR}x DPR  ·  warmup ${WARMUP_MS}ms`);

	const browser = await puppeteer.launch({
		headless: true,
		args: ['--enable-webgl', '--enable-gpu', '--no-sandbox', `--window-size=${WIDTH},${HEIGHT}`]
	});
	const page = await browser.newPage();
	await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: DPR });
	// Some shaders honor prefers-reduced-motion by skipping frames. Headless
	// puppeteer sometimes reports `reduce` by default — force it off so the
	// shader animates normally during warmup.
	await page.emulateMediaFeatures([{ name: 'prefers-reduced-motion', value: 'no-preference' }]);

	let done = 0;
	for (const t of targets) {
		const outPath = join(OUT_DIR, `learn-${t.id}.jpg`);
		process.stdout.write(`[${++done}/${targets.length}] ${t.id} ... `);
		try {
			const buf = await captureShareImage(page, baseUrl, t.shader, t.meta);
			const fs = await import('fs/promises');
			await fs.writeFile(outPath, buf);
			const kb = (buf.byteLength / 1024).toFixed(1);
			console.log(`${kb} KB  →  ${outPath.replace(ROOT + '/', '')}`);
		} catch (err) {
			console.log(`FAILED: ${err.message}`);
		}
	}

	await browser.close();
	server.close();
	console.log(`\nDone.`);
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
