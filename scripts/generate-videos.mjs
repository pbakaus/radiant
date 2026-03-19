#!/usr/bin/env node
/**
 * Generate highlight videos of shaders for social media.
 *
 * Records deterministic 60fps video by overriding requestAnimationFrame
 * and stepping time manually, then piping PNG frames to ffmpeg.
 *
 * Usage:
 *   node scripts/generate-videos.mjs --shader=liquid-gold
 *   node scripts/generate-videos.mjs --shader=liquid-gold --duration=15 --format=reel
 *   node scripts/generate-videos.mjs --shader=liquid-gold --format=landscape
 *   node scripts/generate-videos.mjs --all --duration=15
 *
 * Flags:
 *   --shader=id       Record a specific shader (required unless --all)
 *   --all             Record all shaders
 *   --duration=20     Total duration in seconds (default: 20)
 *   --format=reel|landscape|square  Output resolution preset (default: landscape)
 *   --fps=60          Frame rate (default: 60)
 *   --output=dir      Output directory (default: videos/)
 *   --no-captions     Disable caption burn-in
 */

import puppeteer from 'puppeteer';
import { createServer } from 'http';
import { readFile, mkdir } from 'fs/promises';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';
import { execSync, spawn } from 'child_process';

const __dirname = fileURLToPath(new URL('.', import.meta.url));
const ROOT = join(__dirname, '..');
const STATIC = join(ROOT, 'static');

// ---------------------------------------------------------------------------
// Format presets
// ---------------------------------------------------------------------------
const FORMAT_PRESETS = {
	landscape: { width: 1920, height: 1080, label: '16:9 Landscape' },
	reel:      { width: 1080, height: 1920, label: '9:16 Reel' },
	square:    { width: 1080, height: 1080, label: '1:1 Square' }
};

// ---------------------------------------------------------------------------
// Color schemes (must match src/lib/color-schemes.ts)
// ---------------------------------------------------------------------------
const COLOR_SCHEMES = [
	{ id: 'amber',      name: 'Amber',   filter: 'none' },
	{ id: 'blue',       name: 'Blue',    filter: 'hue-rotate(175deg)' },
	{ id: 'rose',       name: 'Rose',    filter: 'hue-rotate(300deg) saturate(1.1)' },
	{ id: 'emerald',    name: 'Emerald', filter: 'hue-rotate(90deg) saturate(1.2)' },
	{ id: 'arctic',     name: 'Arctic',  filter: 'hue-rotate(180deg) saturate(0.5) brightness(1.1)' },
	{ id: 'monochrome', name: 'Mono',    filter: 'grayscale(1)' }
];

// DPR for crisp output
const DPR = 2;

// Warmup frames before recording (5 seconds at 60fps)
const WARMUP_FRAMES = 300;

// ---------------------------------------------------------------------------
// Parse shader metadata from shaders.ts
// ---------------------------------------------------------------------------
async function loadShaderList() {
	const src = await readFile(join(ROOT, 'src/lib/shaders.ts'), 'utf8');
	const entries = [];

	// Match each shader object block
	const blockRe = /\{[^{}]*id:\s*'([^']+)'[\s\S]*?(?=\n\t\{|\n\];)/g;
	let block;
	while ((block = blockRe.exec(src)) !== null) {
		const text = block[0];
		const id = block[1];

		// Extract file
		const fileMatch = text.match(/file:\s*'([^']+)'/);
		if (!fileMatch) continue;

		// Extract title
		const titleMatch = text.match(/title:\s*'([^']+)'/);

		// Extract params
		const params = [];
		const paramRe = /\{\s*name:\s*'([^']+)',\s*label:\s*'([^']+)',\s*min:\s*([-\d.]+),\s*max:\s*([-\d.]+),\s*step:\s*([-\d.]+),\s*default:\s*([-\d.]+)\s*\}/g;
		let pm;
		while ((pm = paramRe.exec(text)) !== null) {
			params.push({
				name: pm[1],
				label: pm[2],
				min: parseFloat(pm[3]),
				max: parseFloat(pm[4]),
				step: parseFloat(pm[5]),
				default: parseFloat(pm[6])
			});
		}

		// Check technique
		const techMatch = text.match(/technique:\s*'([^']+)'/);

		// Check defaultScheme
		const schemeMatch = text.match(/defaultScheme:\s*'([^']+)'/);

		entries.push({
			id,
			file: fileMatch[1],
			title: titleMatch ? titleMatch[1] : id,
			technique: techMatch ? techMatch[1] : 'canvas-2d',
			defaultScheme: schemeMatch ? schemeMatch[1] : 'amber',
			params
		});
	}

	return entries;
}

// ---------------------------------------------------------------------------
// Minimal static file server
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
		'.woff2': 'font/woff2',
		'.ico': 'image/x-icon'
	};

	const server = createServer(async (req, res) => {
		const url = new URL(req.url, 'http://localhost');
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
// Bezier math utilities
// ---------------------------------------------------------------------------

/** Evaluate a cubic bezier at parameter t (0..1) */
function cubicBezier(p0, p1, p2, p3, t) {
	const u = 1 - t;
	return {
		x: u * u * u * p0.x + 3 * u * u * t * p1.x + 3 * u * t * t * p2.x + t * t * t * p3.x,
		y: u * u * u * p0.y + 3 * u * u * t * p1.y + 3 * u * t * t * p2.y + t * t * t * p3.y
	};
}

/** Ease-in-out (smooth acceleration/deceleration) */
function easeInOut(t) {
	return t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
}

/** Smooth step with configurable edges */
function smoothStep(edge0, edge1, x) {
	const t = Math.max(0, Math.min(1, (x - edge0) / (edge1 - edge0)));
	return t * t * (3 - 2 * t);
}

/** Linear interpolation */
function lerp(a, b, t) {
	return a + (b - a) * t;
}

// ---------------------------------------------------------------------------
// Mouse path presets (all return normalized 0..1 coordinates)
// ---------------------------------------------------------------------------

/** Gentle drift near center */
function gentleDrift(t) {
	const angle = t * Math.PI * 2 * 0.3;
	return {
		x: 0.5 + Math.sin(angle) * 0.08 + Math.sin(angle * 2.7) * 0.04,
		y: 0.5 + Math.cos(angle * 0.7) * 0.06 + Math.cos(angle * 1.3) * 0.03
	};
}

/** Figure-8 across the canvas */
function figure8(t) {
	const angle = t * Math.PI * 2;
	return {
		x: 0.5 + Math.sin(angle) * 0.35,
		y: 0.5 + Math.sin(angle * 2) * 0.25
	};
}

/** Spiral inward from outer to center */
function spiralInward(t) {
	const revolutions = 2.5;
	const angle = t * Math.PI * 2 * revolutions;
	const radius = 0.35 * (1 - easeInOut(t));
	return {
		x: 0.5 + Math.cos(angle) * radius,
		y: 0.5 + Math.sin(angle) * radius
	};
}

/** Slow sweep from corner to corner via bezier */
function cornerSweep(t) {
	const eased = easeInOut(t);
	return cubicBezier(
		{ x: 0.15, y: 0.15 },
		{ x: 0.85, y: 0.25 },
		{ x: 0.15, y: 0.75 },
		{ x: 0.85, y: 0.85 },
		eased
	);
}

const MOUSE_PATHS = { gentleDrift, figure8, spiralInward, cornerSweep };

// ---------------------------------------------------------------------------
// Caption system
// ---------------------------------------------------------------------------

/**
 * Create or update a caption overlay on the page.
 * Opacity is controlled per-frame for fade-in/fade-out.
 */
async function setCaption(page, text, opacity) {
	await page.evaluate(({ text, opacity }) => {
		let el = document.getElementById('__video-caption');
		if (!el) {
			el = document.createElement('div');
			el.id = '__video-caption';
			Object.assign(el.style, {
				position: 'fixed',
				bottom: '6%',
				left: '50%',
				transform: 'translateX(-50%)',
				fontFamily: '"SF Mono", "Fira Code", "Cascadia Code", "JetBrains Mono", monospace',
				fontSize: '22px',
				fontWeight: '500',
				letterSpacing: '0.08em',
				color: 'rgba(200, 149, 108, 0.9)',
				textAlign: 'center',
				padding: '10px 28px',
				borderRadius: '8px',
				backdropFilter: 'blur(12px)',
				WebkitBackdropFilter: 'blur(12px)',
				background: 'rgba(10, 10, 10, 0.55)',
				border: '1px solid rgba(200, 149, 108, 0.15)',
				zIndex: '99999',
				pointerEvents: 'none',
				whiteSpace: 'nowrap',
				transition: 'none'
			});
			document.body.appendChild(el);
		}
		el.textContent = text;
		el.style.opacity = String(opacity);
	}, { text, opacity });
}

async function hideCaption(page) {
	await page.evaluate(() => {
		const el = document.getElementById('__video-caption');
		if (el) el.style.opacity = '0';
	});
}

/**
 * Compute caption opacity for a given frame within a scene.
 * Fades in over fadeFrames, holds, fades out over fadeFrames.
 */
function captionOpacity(frameInScene, sceneDurationFrames, fadeFrames = 30) {
	if (frameInScene < fadeFrames) {
		return frameInScene / fadeFrames;
	}
	if (frameInScene > sceneDurationFrames - fadeFrames) {
		return Math.max(0, (sceneDurationFrames - frameInScene) / fadeFrames);
	}
	return 1;
}

// ---------------------------------------------------------------------------
// Choreography engine
// ---------------------------------------------------------------------------

/**
 * Build a default choreography for a shader.
 * Returns an array of scene descriptors.
 */
function buildChoreography(shader, durationSec, fps) {
	const totalFrames = durationSec * fps;
	const hasParams = shader.params && shader.params.length > 0;

	// Distribute time across scenes (in seconds)
	// Adjust if no params — give more time to other scenes
	let scenes;
	if (hasParams) {
		const s1 = 4;                         // Opening
		const s2 = 4;                         // Interaction
		const s3 = 5;                         // Parameters
		const s4 = 4;                         // Color themes
		const s5 = Math.max(3, durationSec - s1 - s2 - s3 - s4); // Outro
		scenes = [
			{ name: 'opening',     startSec: 0,                  durationSec: s1 },
			{ name: 'interaction', startSec: s1,                 durationSec: s2 },
			{ name: 'parameters',  startSec: s1 + s2,            durationSec: s3 },
			{ name: 'colors',      startSec: s1 + s2 + s3,       durationSec: s4 },
			{ name: 'outro',       startSec: s1 + s2 + s3 + s4,  durationSec: s5 }
		];
	} else {
		const s1 = 5;
		const s2 = 5;
		const s4 = 5;
		const s5 = Math.max(3, durationSec - s1 - s2 - s4);
		scenes = [
			{ name: 'opening',     startSec: 0,                durationSec: s1 },
			{ name: 'interaction', startSec: s1,               durationSec: s2 },
			{ name: 'colors',      startSec: s1 + s2,          durationSec: s4 },
			{ name: 'outro',       startSec: s1 + s2 + s4,     durationSec: s5 }
		];
	}

	return scenes.map(s => ({
		...s,
		startFrame: Math.round(s.startSec * fps),
		durationFrames: Math.round(s.durationSec * fps)
	}));
}

/**
 * Get the current scene for a given frame number.
 */
function getScene(scenes, frame) {
	for (let i = scenes.length - 1; i >= 0; i--) {
		if (frame >= scenes[i].startFrame) return scenes[i];
	}
	return scenes[0];
}

/**
 * Compute frame-local progress within a scene (0..1).
 */
function sceneProgress(scene, frame) {
	return Math.min(1, (frame - scene.startFrame) / Math.max(1, scene.durationFrames - 1));
}

// ---------------------------------------------------------------------------
// Parameter sweep helpers
// ---------------------------------------------------------------------------

/**
 * Generate a smooth parameter sweep: default -> max -> default -> (next param)
 * Returns the target value for a given normalized time t within the parameters scene.
 */
function paramSweepValue(param, t) {
	// Sweep: 0..0.3 = default->max, 0.3..0.6 = max->default, 0.6..1.0 = hold default
	if (t < 0.3) {
		const st = easeInOut(t / 0.3);
		return lerp(param.default, param.max, st);
	}
	if (t < 0.6) {
		const st = easeInOut((t - 0.3) / 0.3);
		return lerp(param.max, param.default, st);
	}
	return param.default;
}

/**
 * For multiple params, split time between them.
 * Returns array of { name, value } for each param at time t (0..1).
 */
function computeParamValues(params, t) {
	if (!params || params.length === 0) return [];

	// Use at most 2 params for the sweep
	const sweepParams = params.slice(0, 2);
	const perParam = 1 / sweepParams.length;

	return sweepParams.map((p, i) => {
		const localStart = i * perParam;
		const localEnd = localStart + perParam;
		let localT;
		if (t < localStart) localT = 0;
		else if (t > localEnd) localT = 1;
		else localT = (t - localStart) / perParam;

		return { name: p.name, label: p.label, value: paramSweepValue(p, localT), isActive: t >= localStart && t <= localEnd };
	});
}

// ---------------------------------------------------------------------------
// Color scheme transition helpers
// ---------------------------------------------------------------------------

/**
 * Parse a CSS filter string into structured data for interpolation.
 * Returns { hueRotate, saturate, brightness, grayscale }.
 */
function parseFilter(filterStr) {
	const result = { hueRotate: 0, saturate: 1, brightness: 1, grayscale: 0 };
	if (filterStr === 'none') return result;

	const hueMatch = filterStr.match(/hue-rotate\((\d+)deg\)/);
	if (hueMatch) result.hueRotate = parseFloat(hueMatch[1]);

	const satMatch = filterStr.match(/saturate\(([\d.]+)\)/);
	if (satMatch) result.saturate = parseFloat(satMatch[1]);

	const briMatch = filterStr.match(/brightness\(([\d.]+)\)/);
	if (briMatch) result.brightness = parseFloat(briMatch[1]);

	const grayMatch = filterStr.match(/grayscale\(([\d.]+)\)/);
	if (grayMatch) result.grayscale = parseFloat(grayMatch[1]);

	return result;
}

/**
 * Interpolate between two parsed filters and produce a CSS filter string.
 */
function interpolateFilter(a, b, t) {
	const hue = lerp(a.hueRotate, b.hueRotate, t);
	const sat = lerp(a.saturate, b.saturate, t);
	const bri = lerp(a.brightness, b.brightness, t);
	const gray = lerp(a.grayscale, b.grayscale, t);

	const parts = [];
	if (Math.abs(hue) > 0.1) parts.push(`hue-rotate(${hue.toFixed(1)}deg)`);
	if (Math.abs(gray) > 0.001) parts.push(`grayscale(${gray.toFixed(3)})`);
	if (Math.abs(sat - 1) > 0.01) parts.push(`saturate(${sat.toFixed(3)})`);
	if (Math.abs(bri - 1) > 0.01) parts.push(`brightness(${bri.toFixed(3)})`);

	return parts.length > 0 ? parts.join(' ') : 'none';
}

/**
 * Compute the CSS filter for the color themes scene at time t (0..1).
 * Cycles through amber -> blue -> rose -> emerald with smooth transitions.
 */
function colorSceneFilter(t) {
	// Use 4 schemes for the color scene (skip monochrome and arctic for visual impact)
	const schemes = [
		COLOR_SCHEMES[0], // amber
		COLOR_SCHEMES[1], // blue
		COLOR_SCHEMES[2], // rose
		COLOR_SCHEMES[3], // emerald
	];
	const parsed = schemes.map(s => parseFilter(s.filter));

	const numSchemes = schemes.length;
	const holdPerScheme = 1 / numSchemes;
	const transitionFraction = 0.25; // 25% of each segment is transition

	const segIndex = Math.min(numSchemes - 1, Math.floor(t / holdPerScheme));
	const segT = (t - segIndex * holdPerScheme) / holdPerScheme;

	const from = parsed[segIndex];
	const to = parsed[Math.min(numSchemes - 1, segIndex + 1)];

	// Hold for (1 - transitionFraction), then transition
	if (segT < (1 - transitionFraction) || segIndex === numSchemes - 1) {
		return { filter: interpolateFilter(from, from, 0), schemeName: schemes[segIndex].name };
	}
	const blendT = easeInOut((segT - (1 - transitionFraction)) / transitionFraction);
	return {
		filter: interpolateFilter(from, to, blendT),
		schemeName: blendT > 0.5 ? schemes[Math.min(numSchemes - 1, segIndex + 1)].name : schemes[segIndex].name
	};
}

// ---------------------------------------------------------------------------
// rAF override script (injected before shader loads)
// ---------------------------------------------------------------------------
const RAF_OVERRIDE_SCRIPT = `
(function() {
	// Store the real rAF but replace with our controlled version
	const _realRAF = window.requestAnimationFrame;
	let _storedCallback = null;
	let _accumulatedTime = 0;

	// Override rAF to capture the callback
	window.requestAnimationFrame = function(cb) {
		_storedCallback = cb;
		// Return a fake ID
		return 1;
	};

	// Also override performance.now to return our controlled time
	const _origPerfNow = performance.now.bind(performance);
	let _baseTime = _origPerfNow();
	performance.now = function() {
		return _baseTime + _accumulatedTime;
	};

	// Also override Date.now for shaders that use it
	const _origDateNow = Date.now;
	let _baseDateNow = _origDateNow.call(Date);
	Date.now = function() {
		return _baseDateNow + _accumulatedTime;
	};

	// Expose advance function: steps time forward by dt ms and calls the stored callback
	window.__captureAdvanceFrame = function(dt) {
		_accumulatedTime += dt;
		const currentTime = _baseTime + _accumulatedTime;
		if (_storedCallback) {
			const cb = _storedCallback;
			_storedCallback = null;
			cb(currentTime);
		}
	};

	// Force preserveDrawingBuffer for WebGL
	const _origGetContext = HTMLCanvasElement.prototype.getContext;
	HTMLCanvasElement.prototype.getContext = function(type, attrs) {
		if (type === 'webgl' || type === 'webgl2' || type === 'experimental-webgl') {
			attrs = Object.assign({}, attrs || {}, {
				preserveDrawingBuffer: true,
				powerPreference: 'high-performance'
			});
		}
		return _origGetContext.call(this, type, attrs);
	};
})();
`;

// ---------------------------------------------------------------------------
// Record a single shader
// ---------------------------------------------------------------------------
async function recordShader(page, baseUrl, shader, options) {
	const { format, fps, durationSec, enableCaptions, outputDir } = options;
	const preset = FORMAT_PRESETS[format];
	const viewportWidth = preset.width / DPR;
	const viewportHeight = preset.height / DPR;
	const dt = 1000 / fps; // ms per frame
	const totalFrames = durationSec * fps;
	const outputPath = join(outputDir, `${shader.id}-${format}.mp4`);

	// Set viewport
	await page.setViewport({
		width: viewportWidth,
		height: viewportHeight,
		deviceScaleFactor: DPR
	});

	// Navigate to the shader
	const url = `${baseUrl}/${shader.file}`;
	await page.goto(url, { waitUntil: 'domcontentloaded' });

	// Wait a moment for script execution
	await new Promise(r => setTimeout(r, 500));

	// Hide the label
	await page.evaluate(() => {
		const label = document.querySelector('.label');
		if (label) label.style.display = 'none';
	});

	// Apply default color scheme
	const defaultScheme = COLOR_SCHEMES.find(s => s.id === shader.defaultScheme) || COLOR_SCHEMES[0];
	if (defaultScheme.filter !== 'none') {
		await page.evaluate((f) => {
			const c = document.getElementById('canvas');
			if (c) c.style.filter = f;
		}, defaultScheme.filter);
	}

	// Warmup: advance frames without recording
	process.stdout.write(`  Warming up (${WARMUP_FRAMES} frames)...`);
	for (let i = 0; i < WARMUP_FRAMES; i++) {
		await page.evaluate((dt) => {
			if (window.__captureAdvanceFrame) window.__captureAdvanceFrame(dt);
		}, dt);
	}
	process.stdout.write(' done\n');

	// Build choreography
	const scenes = buildChoreography(shader, durationSec, fps);

	// Spawn ffmpeg
	const ffmpegArgs = [
		'-y',
		'-f', 'image2pipe',
		'-framerate', String(fps),
		'-i', 'pipe:0',
		'-c:v', 'libx264',
		'-preset', 'slow',
		'-crf', '20',
		'-pix_fmt', 'yuv420p',
		'-movflags', '+faststart',
		outputPath
	];

	const ffmpeg = spawn('ffmpeg', ffmpegArgs, {
		stdio: ['pipe', 'pipe', 'pipe']
	});

	let ffmpegError = '';
	ffmpeg.stderr.on('data', (data) => {
		ffmpegError += data.toString();
	});

	const ffmpegDone = new Promise((resolve, reject) => {
		ffmpeg.on('close', (code) => {
			if (code === 0) resolve();
			else reject(new Error(`ffmpeg exited with code ${code}: ${ffmpegError.slice(-500)}`));
		});
		ffmpeg.on('error', reject);
	});

	// Record frames
	const startTime = Date.now();
	let lastPercent = -1;
	let outroLoaded = false;

	for (let frame = 0; frame < totalFrames; frame++) {
		const scene = getScene(scenes, frame);
		const progress = sceneProgress(scene, frame);

		// --- Apply scene-specific actions ---

		// ── Outro: navigate to dedicated outro page ──
		if (scene.name === 'outro' && !outroLoaded) {
			outroLoaded = true;
			const outroUrl = `${baseUrl}/video-outro.html?name=${encodeURIComponent(shader.title)}&url=${encodeURIComponent('radiant-shaders.com/shader/' + shader.id)}`;
			await page.goto(outroUrl, { waitUntil: 'domcontentloaded' });
			await new Promise(r => setTimeout(r, 300));
		}

		// Mouse movement (skip for outro — it has its own animation)
		if (scene.name !== 'outro') {
			let mousePos;
			switch (scene.name) {
				case 'opening':
					mousePos = gentleDrift(progress);
					break;
				case 'interaction':
					mousePos = figure8(progress);
					break;
				case 'parameters':
					mousePos = spiralInward(progress);
					break;
				case 'colors':
					mousePos = cornerSweep(progress);
					break;
				default:
					mousePos = gentleDrift(progress);
			}

			// Move mouse (convert normalized to viewport pixels)
			const mx = mousePos.x * viewportWidth;
			const my = mousePos.y * viewportHeight;
			await page.mouse.move(mx, my);
			await page.evaluate(({ x, y }) => {
				const c = document.getElementById('canvas');
				if (c) {
					const r = c.getBoundingClientRect();
					c.dispatchEvent(new MouseEvent('mousemove', {
						clientX: x, clientY: y,
						offsetX: x - r.left, offsetY: y - r.top,
						bubbles: true, cancelable: true, view: window
					}));
				}
			}, { x: mx, y: my });
		}

		// Parameter changes (scene: parameters)
		if (scene.name === 'parameters' && shader.params && shader.params.length > 0) {
			const paramValues = computeParamValues(shader.params, progress);
			for (const pv of paramValues) {
				await page.evaluate(({ name, value }) => {
					window.postMessage({ type: 'param', name, value }, '*');
				}, { name: pv.name, value: pv.value });
			}
		} else if (scene.name !== 'parameters') {
			// Reset params to default when not in parameters scene
			if (frame === scene.startFrame && shader.params) {
				for (const p of shader.params) {
					await page.evaluate(({ name, value }) => {
						window.postMessage({ type: 'param', name, value }, '*');
					}, { name: p.name, value: p.default });
				}
			}
		}

		// Color scheme transitions (scene: colors)
		if (scene.name === 'colors') {
			const { filter } = colorSceneFilter(progress);
			await page.evaluate((f) => {
				const c = document.getElementById('canvas');
				if (c) c.style.filter = f;
			}, filter);
		} else if (scene.name !== 'colors') {
			// Reset to default scheme outside colors scene
			if (frame === scene.startFrame) {
				await page.evaluate((f) => {
					const c = document.getElementById('canvas');
					if (c) c.style.filter = f;
				}, defaultScheme.filter);
			}
		}

		// Captions
		if (enableCaptions) {
			let captionText = '';
			const fadeFrames = Math.round(0.5 * fps); // 0.5 sec fade
			const opacity = captionOpacity(frame - scene.startFrame, scene.durationFrames, fadeFrames);

			switch (scene.name) {
				case 'opening':
					captionText = shader.title;
					break;
				case 'interaction':
					captionText = 'Move cursor to interact';
					break;
				case 'parameters': {
					if (shader.params && shader.params.length > 0) {
						const paramValues = computeParamValues(shader.params, progress);
						const active = paramValues.find(pv => pv.isActive);
						captionText = active ? active.label : shader.params[0].label;
					}
					break;
				}
				case 'colors': {
					const { schemeName } = colorSceneFilter(progress);
					captionText = `6 color themes \u00B7 ${schemeName}`;
					break;
				}
				case 'outro':
					// Outro has its own branded page — no caption needed
					break;
			}

			if (captionText && opacity > 0.01) {
				await setCaption(page, captionText, opacity);
			} else {
				await hideCaption(page);
			}
		}

		// Advance the shader by one frame
		await page.evaluate((dt) => {
			if (window.__captureAdvanceFrame) window.__captureAdvanceFrame(dt);
		}, dt);

		// Capture the frame as PNG and pipe to ffmpeg
		const screenshot = await page.screenshot({
			type: 'png',
			clip: { x: 0, y: 0, width: viewportWidth, height: viewportHeight },
			omitBackground: false
		});

		// Write to ffmpeg stdin. Handle backpressure.
		const canWrite = ffmpeg.stdin.write(screenshot);
		if (!canWrite) {
			await new Promise(resolve => ffmpeg.stdin.once('drain', resolve));
		}

		// Progress indicator
		const percent = Math.floor((frame / totalFrames) * 100);
		if (percent !== lastPercent && percent % 5 === 0) {
			const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
			const framesPerSec = (frame / (Date.now() - startTime) * 1000).toFixed(1);
			process.stdout.write(`  Recording: ${percent}% (frame ${frame}/${totalFrames}, ${framesPerSec} fps, ${elapsed}s elapsed)\r`);
			lastPercent = percent;
		}
	}

	// Close ffmpeg stdin to signal end of input
	ffmpeg.stdin.end();
	process.stdout.write('\n');

	// Wait for ffmpeg to finish
	process.stdout.write('  Encoding final...');
	await ffmpegDone;
	process.stdout.write(' done\n');

	return outputPath;
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------
function parseArgs() {
	const args = process.argv.slice(2);
	const opts = {
		shader: null,
		all: false,
		duration: 20,
		format: 'landscape',
		fps: 60,
		output: join(ROOT, 'videos'),
		captions: true
	};

	for (const arg of args) {
		if (arg.startsWith('--shader=')) {
			opts.shader = arg.split('=')[1];
		} else if (arg === '--all') {
			opts.all = true;
		} else if (arg.startsWith('--duration=')) {
			opts.duration = parseInt(arg.split('=')[1], 10);
		} else if (arg.startsWith('--format=')) {
			opts.format = arg.split('=')[1];
		} else if (arg.startsWith('--fps=')) {
			opts.fps = parseInt(arg.split('=')[1], 10);
		} else if (arg.startsWith('--output=')) {
			opts.output = arg.split('=')[1];
		} else if (arg === '--no-captions') {
			opts.captions = false;
		} else if (arg === '--help' || arg === '-h') {
			console.log(`
Usage: node scripts/generate-videos.mjs [options]

Options:
  --shader=ID          Record a specific shader (required unless --all)
  --all                Record all shaders
  --duration=SECONDS   Total duration (default: 20)
  --format=PRESET      landscape|reel|square (default: landscape)
  --fps=FPS            Frame rate (default: 60)
  --output=DIR         Output directory (default: videos/)
  --no-captions        Disable caption burn-in
  --help, -h           Show this help
`);
			process.exit(0);
		}
	}

	return opts;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
	const opts = parseArgs();

	// Validate
	if (!opts.shader && !opts.all) {
		console.error('Error: specify --shader=ID or --all');
		process.exit(1);
	}

	if (!FORMAT_PRESETS[opts.format]) {
		console.error(`Error: unknown format "${opts.format}". Use: landscape, reel, or square`);
		process.exit(1);
	}

	// Check ffmpeg
	try {
		execSync('which ffmpeg', { stdio: 'pipe' });
	} catch {
		console.error('Error: ffmpeg not found. Install it: brew install ffmpeg');
		process.exit(1);
	}

	// Load shaders
	let allShaders = await loadShaderList();

	if (opts.shader) {
		allShaders = allShaders.filter(s => s.id === opts.shader);
		if (allShaders.length === 0) {
			console.error(`Error: shader "${opts.shader}" not found`);
			console.error('Available shaders:');
			const full = await loadShaderList();
			for (const s of full) {
				console.error(`  ${s.id}`);
			}
			process.exit(1);
		}
	}

	// Ensure output directory
	await mkdir(opts.output, { recursive: true });

	const preset = FORMAT_PRESETS[opts.format];
	console.log(`Radiant Video Generator`);
	console.log(`-----------------------`);
	console.log(`Shaders:    ${allShaders.length}`);
	console.log(`Format:     ${preset.label} (${preset.width}x${preset.height})`);
	console.log(`Duration:   ${opts.duration}s @ ${opts.fps}fps (${opts.duration * opts.fps} frames)`);
	console.log(`DPR:        ${DPR}x`);
	console.log(`Captions:   ${opts.captions ? 'enabled' : 'disabled'}`);
	console.log(`Output:     ${opts.output}/`);
	console.log('');

	// Start server
	const server = await startServer();
	const port = server.address().port;
	const baseUrl = `http://127.0.0.1:${port}`;
	console.log(`Static server on port ${port}\n`);

	// Launch browser
	const browser = await puppeteer.launch({
		headless: true,
		args: [
			'--enable-webgl',
			'--enable-gpu',
			'--no-sandbox',
			'--disable-setuid-sandbox',
			`--window-size=${preset.width},${preset.height}`
		]
	});

	const page = await browser.newPage();

	// Inject the rAF override before any page loads
	await page.evaluateOnNewDocument(RAF_OVERRIDE_SCRIPT);

	// Graceful Ctrl+C cleanup
	let cleaningUp = false;
	const cleanup = async () => {
		if (cleaningUp) return;
		cleaningUp = true;
		console.log('\n\nInterrupted. Cleaning up...');
		try { await browser.close(); } catch {}
		server.close();
		process.exit(1);
	};
	process.on('SIGINT', cleanup);
	process.on('SIGTERM', cleanup);

	// Record each shader
	let done = 0;
	const results = [];
	for (const shader of allShaders) {
		console.log(`[${++done}/${allShaders.length}] ${shader.id} (${shader.title})`);
		try {
			const outPath = await recordShader(page, baseUrl, shader, {
				format: opts.format,
				fps: opts.fps,
				durationSec: opts.duration,
				enableCaptions: opts.captions,
				outputDir: opts.output
			});
			const stat = await import('fs/promises').then(fs => fs.stat(outPath));
			const sizeMB = (stat.size / (1024 * 1024)).toFixed(1);
			console.log(`  Output: ${outPath} (${sizeMB} MB)\n`);
			results.push({ id: shader.id, path: outPath, size: sizeMB });
		} catch (err) {
			console.error(`  FAILED: ${err.message}\n`);
			results.push({ id: shader.id, error: err.message });
		}
	}

	// Summary
	console.log('------- Summary -------');
	for (const r of results) {
		if (r.error) {
			console.log(`  FAIL  ${r.id}: ${r.error}`);
		} else {
			console.log(`  OK    ${r.id} -> ${r.path} (${r.size} MB)`);
		}
	}

	await browser.close();
	server.close();
	console.log('\nDone.');
}

main().catch((err) => {
	console.error(err);
	process.exit(1);
});
