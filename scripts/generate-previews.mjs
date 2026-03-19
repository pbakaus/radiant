#!/usr/bin/env node
/**
 * Generate preview sprite sheets for all shaders.
 *
 * Each sprite is a vertical strip of 6 frames (one per color scheme)
 * stored as WebP in static/previews/{shader-id}.webp.
 *
 * Usage:  node scripts/generate-previews.mjs [--only=shader-id]
 */

import puppeteer from 'puppeteer';
import sharp from 'sharp';
import { createServer } from 'http';
import { readFile, mkdir, stat } from 'fs/promises';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const ROOT = join(__dirname, '..');
const STATIC = join(ROOT, 'static');
const OUT_DIR = join(STATIC, 'previews');

// Preview dimensions per frame (16:10 aspect, at 2x DPI)
// Viewport is 480x300, but deviceScaleFactor: 2 captures at 960x600 real pixels
const WIDTH = 480;
const HEIGHT = 300;
const DPR = 2;

// How long to let the shader warm up (ms). ~500 frames at 60fps ≈ 8.3s
const WARMUP_MS = 8500;

// Color schemes (must match src/lib/color-schemes.ts order)
const COLOR_SCHEMES = [
	{ id: 'amber', filter: 'none' },
	{ id: 'monochrome', filter: 'grayscale(1)' },
	{ id: 'blue', filter: 'hue-rotate(175deg)' },
	{ id: 'rose', filter: 'hue-rotate(300deg) saturate(1.1)' },
	{ id: 'emerald', filter: 'hue-rotate(90deg) saturate(1.2)' },
	{ id: 'arctic', filter: 'hue-rotate(180deg) saturate(0.5) brightness(1.1)' }
];

// ---------------------------------------------------------------------------
// Parse shader entries from shaders.ts
// ---------------------------------------------------------------------------
async function loadShaderList() {
	const src = await readFile(join(ROOT, 'src/lib/shaders.ts'), 'utf8');
	const entries = [];
	const re = /id:\s*'([^']+)'[\s\S]*?file:\s*'([^']+)'/g;
	let m;
	while ((m = re.exec(src)) !== null) {
		entries.push({ id: m[1], file: m[2] });
	}
	return entries;
}

// ---------------------------------------------------------------------------
// Minimal static file server for the shaders
// ---------------------------------------------------------------------------
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
		server.listen(port, '127.0.0.1', () => {
			resolve(server);
		});
	});
}

// ---------------------------------------------------------------------------
// Capture one shader into a sprite
// ---------------------------------------------------------------------------
async function captureShader(page, baseUrl, shader) {
	const url = `${baseUrl}/${shader.file}`;
	await page.goto(url, { waitUntil: 'domcontentloaded' });

	// Wait for the shader to warm up (~500 frames)
	await new Promise((r) => setTimeout(r, WARMUP_MS));

	const frames = [];
	const pxWidth = WIDTH * DPR;
	const pxHeight = HEIGHT * DPR;

	for (const scheme of COLOR_SCHEMES) {
		// Apply CSS filter to the canvas
		await page.evaluate((filter) => {
			const c = document.getElementById('canvas');
			if (c) c.style.filter = filter;
		}, scheme.filter);

		// Small delay for the filter to render
		await new Promise((r) => setTimeout(r, 50));

		// Screenshot the viewport (Puppeteer respects deviceScaleFactor automatically)
		const buf = await page.screenshot({
			type: 'png',
			clip: { x: 0, y: 0, width: WIDTH, height: HEIGHT }
		});
		frames.push(buf);

		// Remove filter
		await page.evaluate(() => {
			const c = document.getElementById('canvas');
			if (c) c.style.filter = '';
		});
	}

	// Combine frames into a vertical sprite
	const sprite = await sharp({
		create: {
			width: pxWidth,
			height: pxHeight * COLOR_SCHEMES.length,
			channels: 3,
			background: { r: 10, g: 10, b: 10 }
		}
	})
		.composite(
			frames.map((buf, i) => ({
				input: buf,
				top: i * pxHeight,
				left: 0
			}))
		)
		.webp({ quality: 85 })
		.toBuffer();

	return sprite;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
	const onlyId = process.argv.find((a) => a.startsWith('--only='))?.split('=')[1];

	let allShaders = await loadShaderList();
	if (onlyId) {
		allShaders = allShaders.filter((s) => s.id === onlyId);
		if (allShaders.length === 0) {
			console.error(`Shader "${onlyId}" not found`);
			process.exit(1);
		}
	}

	await mkdir(OUT_DIR, { recursive: true });

	const server = await startServer();
	const port = server.address().port;
	const baseUrl = `http://127.0.0.1:${port}`;
	console.log(`Static server on port ${port}`);
	console.log(`Capture: ${WIDTH}x${HEIGHT} @ ${DPR}x DPR → ${WIDTH * DPR}x${HEIGHT * DPR}px per frame`);
	console.log(`Warmup: ${WARMUP_MS}ms (~${Math.round(WARMUP_MS / 16.67)} frames)`);

	const browser = await puppeteer.launch({
		headless: true,
		args: [
			'--enable-webgl',
			'--enable-gpu',
			'--no-sandbox',
			`--window-size=${WIDTH},${HEIGHT}`
		]
	});

	const page = await browser.newPage();
	await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: DPR });

	let done = 0;
	for (const shader of allShaders) {
		const outPath = join(OUT_DIR, `${shader.id}.webp`);
		process.stdout.write(`[${++done}/${allShaders.length}] ${shader.id} ... `);
		try {
			const sprite = await captureShader(page, baseUrl, shader);
			await sharp(sprite).toFile(outPath);
			const kb = (sprite.byteLength / 1024).toFixed(1);
			console.log(`${kb} KB`);
		} catch (err) {
			console.log(`FAILED: ${err.message}`);
		}
	}

	await browser.close();
	server.close();
	console.log(`\nDone. Sprites saved to static/previews/`);
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
