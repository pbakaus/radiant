#!/usr/bin/env node
/**
 * Generate highlight videos of shaders for social media.
 *
 * Records deterministic 60fps video by overriding requestAnimationFrame
 * and stepping time manually, then piping PNG frames to ffmpeg.
 *
 * Usage:
 *   node scripts/generate-videos.mjs --shader=liquid-gold
 *   node scripts/generate-videos.mjs --shader=liquid-gold --format=reel
 *   node scripts/generate-videos.mjs --shader=liquid-gold --format=landscape
 *   node scripts/generate-videos.mjs --all
 *
 * Flags:
 *   --shader=id       Record a specific shader (required unless --all)
 *   --all             Record all shaders
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

// Default warmup: 0 frames (start from the beginning)
const DEFAULT_WARMUP_FRAMES = 0;

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
// Interaction detection (mirrors ShaderPreview.svelte logic)
// ---------------------------------------------------------------------------

/**
 * Detect interaction type from shader HTML source.
 * Returns: 'hover' | 'drag' | 'click' | 'click+hover' | 'none'
 */
async function detectInteraction(shaderFile) {
	const src = await readFile(join(STATIC, shaderFile), 'utf8');
	const hasMouseDown = /addEventListener\s*\(\s*['"]mouse(down|up)['"]/.test(src);
	const hasClick = /addEventListener\s*\(\s*['"]click['"]/.test(src);
	const hasMouseMove = /addEventListener\s*\(\s*['"]mousemove['"]/.test(src);

	if (hasClick && hasMouseMove) return 'click+hover';
	if (hasMouseDown && hasMouseMove) return 'drag';
	if (hasClick) return 'click';
	if (hasMouseMove) return 'hover';
	return 'none';
}

// ---------------------------------------------------------------------------
// Caption system
// ---------------------------------------------------------------------------

/**
 * Create or update a caption overlay on the page.
 * Opacity is controlled per-frame for fade-in/fade-out.
 */
/**
 * Ensure an overlay container exists on <html> (outside body transforms).
 * Must be called once before using caption/slider/cursor overlays.
 */
async function ensureOverlayContainer(page) {
	await page.evaluate(() => {
		if (document.getElementById('__video-overlays')) return;
		const c = document.createElement('div');
		c.id = '__video-overlays';
		c.style.cssText = 'position:fixed;inset:0;z-index:999999;pointer-events:none;overflow:hidden';
		document.documentElement.appendChild(c);
	});
}

async function setCaption(page, text, opacity) {
	await page.evaluate(({ text, opacity }) => {
		const container = document.getElementById('__video-overlays') || document.body;
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
			(document.getElementById('__video-overlays') || document.body).appendChild(el);
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
 * Show/update a visual slider overlay during parameter changes.
 * Shows label, value, and an animated slider track.
 */
async function setSliderOverlay(page, label, value, min, max, opacity) {
	await page.evaluate(({ label, value, min, max, opacity }) => {
		let el = document.getElementById('__video-slider');
		if (!el) {
			el = document.createElement('div');
			el.id = '__video-slider';
			Object.assign(el.style, {
				position: 'fixed',
				bottom: '6%',
				left: '50%',
				transform: 'translateX(-50%)',
				fontFamily: '"SF Mono", "Fira Code", "Cascadia Code", "JetBrains Mono", monospace',
				padding: '14px 32px',
				borderRadius: '10px',
				backdropFilter: 'blur(12px)',
				WebkitBackdropFilter: 'blur(12px)',
				background: 'rgba(10, 10, 10, 0.6)',
				border: '1px solid rgba(200, 149, 108, 0.2)',
				zIndex: '99999',
				pointerEvents: 'none',
				whiteSpace: 'nowrap',
				transition: 'none',
				minWidth: '280px'
			});
			el.innerHTML = `
				<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:8px">
					<span id="__slider-label" style="font-size:13px;letter-spacing:0.1em;color:rgba(200,149,108,0.8);text-transform:uppercase"></span>
					<span id="__slider-value" style="font-size:13px;color:rgba(232,224,216,0.6);font-variant-numeric:tabular-nums"></span>
				</div>
				<div style="position:relative;height:4px;background:rgba(200,149,108,0.15);border-radius:2px;overflow:hidden">
					<div id="__slider-fill" style="position:absolute;left:0;top:0;height:100%;background:rgba(200,149,108,0.7);border-radius:2px;transition:none"></div>
				</div>
				<div id="__slider-thumb" style="position:absolute;width:12px;height:12px;border-radius:50%;background:rgba(200,149,108,0.9);box-shadow:0 0 8px rgba(200,149,108,0.4);transform:translateX(-50%);transition:none"></div>
			`;
			(document.getElementById('__video-overlays') || document.body).appendChild(el);
		}
		el.style.opacity = String(opacity);
		document.getElementById('__slider-label').textContent = label;
		document.getElementById('__slider-value').textContent = value.toFixed(2);
		var pct = Math.max(0, Math.min(1, (value - min) / (max - min)));
		document.getElementById('__slider-fill').style.width = (pct * 100) + '%';
		// Position thumb — account for padding (32px each side)
		var trackEl = el.querySelector('[id="__slider-fill"]').parentElement;
		var trackRect = trackEl.getBoundingClientRect();
		var elRect = el.getBoundingClientRect();
		var thumbEl = document.getElementById('__slider-thumb');
		var trackLeft = trackRect.left - elRect.left;
		var trackW = trackRect.width;
		thumbEl.style.left = (trackLeft + pct * trackW) + 'px';
		thumbEl.style.top = (trackRect.top - elRect.top + trackRect.height / 2 - 6) + 'px';
	}, { label, value, min, max, opacity });
}

async function hideSliderOverlay(page) {
	await page.evaluate(() => {
		const el = document.getElementById('__video-slider');
		if (el) el.style.opacity = '0';
	});
}

// ---------------------------------------------------------------------------
// Cursor overlay system
// ---------------------------------------------------------------------------

/**
 * Show a visual cursor at the given position.
 * state: 'move' | 'click' | 'drag'
 */
async function showCursor(page, x, y, state) {
	await page.evaluate(({ x, y, state }) => {
		// Main cursor dot
		let cursor = document.getElementById('__video-cursor');
		if (!cursor) {
			cursor = document.createElement('div');
			cursor.id = '__video-cursor';
			Object.assign(cursor.style, {
				position: 'fixed',
				width: '20px',
				height: '20px',
				borderRadius: '50%',
				background: 'rgba(200, 149, 108, 0.6)',
				border: '2px solid rgba(255, 255, 255, 0.8)',
				boxShadow: '0 0 12px rgba(200, 149, 108, 0.3)',
				zIndex: '100000',
				pointerEvents: 'none',
				transform: 'translate(-50%, -50%)',
				transition: 'none'
			});
			(document.getElementById('__video-overlays') || document.body).appendChild(cursor);
		}
		cursor.style.left = x + 'px';
		cursor.style.top = y + 'px';
		cursor.style.opacity = '1';

		// Adjust appearance based on state
		if (state === 'drag') {
			cursor.style.width = '24px';
			cursor.style.height = '24px';
			cursor.style.background = 'rgba(200, 149, 108, 0.8)';
			cursor.style.boxShadow = '0 0 20px rgba(200, 149, 108, 0.5)';
		} else if (state === 'click') {
			cursor.style.width = '20px';
			cursor.style.height = '20px';
			cursor.style.background = 'rgba(200, 149, 108, 0.6)';
			cursor.style.boxShadow = '0 0 12px rgba(200, 149, 108, 0.3)';
		} else {
			cursor.style.width = '20px';
			cursor.style.height = '20px';
			cursor.style.background = 'rgba(200, 149, 108, 0.6)';
			cursor.style.boxShadow = '0 0 12px rgba(200, 149, 108, 0.3)';
		}

		// Click ripple effect
		if (state === 'click') {
			const ripple = document.createElement('div');
			Object.assign(ripple.style, {
				position: 'fixed',
				left: x + 'px',
				top: y + 'px',
				width: '10px',
				height: '10px',
				borderRadius: '50%',
				border: '2px solid rgba(200, 149, 108, 0.8)',
				transform: 'translate(-50%, -50%)',
				zIndex: '99999',
				pointerEvents: 'none',
				animation: 'cursorRipple 0.6s ease-out forwards'
			});
			(document.getElementById('__video-overlays') || document.body).appendChild(ripple);

			// Add animation keyframes if not yet added
			if (!document.getElementById('__cursor-styles')) {
				const style = document.createElement('style');
				style.id = '__cursor-styles';
				style.textContent = `
					@keyframes cursorRipple {
						0% { width: 10px; height: 10px; opacity: 1; }
						100% { width: 60px; height: 60px; opacity: 0; }
					}
				`;
				document.head.appendChild(style);
			}

			// Clean up ripple after animation
			setTimeout(() => ripple.remove(), 700);
		}
	}, { x, y, state });
}

async function hideCursor(page) {
	await page.evaluate(() => {
		const cursor = document.getElementById('__video-cursor');
		if (cursor) cursor.style.opacity = '0';
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
function buildChoreography(shader, fps, interactionType) {
	const paramCount = shader.params ? shader.params.length : 0;
	const hasParams = paramCount > 0;

	// Duration is derived from content, not hardcoded
	const sDetail = 3;                         // Detail page UI reveal
	const sZoom = 1.5;                         // Zoom-in transition
	const s1 = 3;                              // Opening (fullscreen, with title)
	const s2 = 4;                              // Interaction
	const s3 = hasParams ? paramCount * 3 : 0; // Parameters: 3s per param
	const s4 = 4;                              // Color themes
	const s5 = 3;                              // Outro

	let scenes = [];
	let t = 0;

	scenes.push({ name: 'detailpage', startSec: t, durationSec: sDetail });
	t += sDetail;
	scenes.push({ name: 'zoom',       startSec: t, durationSec: sZoom });
	t += sZoom;
	scenes.push({ name: 'opening',    startSec: t, durationSec: s1 });
	t += s1;
	scenes.push({ name: 'interaction', startSec: t, durationSec: s2 });
	t += s2;

	if (hasParams) {
		scenes.push({ name: 'parameters', startSec: t, durationSec: s3 });
		t += s3;
	}

	scenes.push({ name: 'colors', startSec: t, durationSec: s4 });
	t += s4;

	scenes.push({ name: 'outro', startSec: t, durationSec: s5 });
	t += s5;

	const totalDuration = t;

	return {
		totalDuration,
		scenes: scenes.map(s => ({
			...s,
			startFrame: Math.round(s.startSec * fps),
			durationFrames: Math.round(s.durationSec * fps)
		}))
	};
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

	// Sweep all params, each gets an equal share of time
	const sweepParams = params;
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
	// Only apply override to shader HTML files (not SvelteKit pages)
	if (!location.pathname.endsWith('.html')) return;

	// Store the real rAF but replace with our controlled version
	const _realRAF = window.requestAnimationFrame;
	const _storedCallbacks = new Map();
	let _nextId = 1;
	let _accumulatedTime = 0;

	// Override rAF to capture ALL callbacks (shader + FPS counter, etc.)
	window.requestAnimationFrame = function(cb) {
		const id = _nextId++;
		_storedCallbacks.set(id, cb);
		return id;
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

	// Expose advance function: steps time forward by dt ms and calls ALL stored callbacks
	window.__captureAdvanceFrame = function(dt) {
		_accumulatedTime += dt;
		const currentTime = _baseTime + _accumulatedTime;
		const cbs = Array.from(_storedCallbacks.values());
		_storedCallbacks.clear();
		for (const cb of cbs) {
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
async function recordShader(page, baseUrl, devUrl, shader, options) {
	const { format, fps, enableCaptions, outputDir } = options;
	const preset = FORMAT_PRESETS[format];
	const viewportWidth = preset.width / DPR;
	const viewportHeight = preset.height / DPR;
	const dt = 1000 / fps; // ms per frame
	const outputPath = join(outputDir, `${shader.id}-${format}.mp4`);

	// Detect interaction type and build choreography
	const interactionType = await detectInteraction(shader.file);
	let { totalDuration, scenes } = buildChoreography(shader, fps, interactionType);

	// Scene filter for debugging (e.g. --scene=colors)
	const sceneFilter = options.sceneFilter;
	if (sceneFilter) {
		// Always need detailpage+zoom for setup, then the target scene
		const setupScenes = scenes.filter(s => s.name === 'detailpage' || s.name === 'zoom');
		const targetScene = scenes.find(s => s.name === sceneFilter);
		if (targetScene) {
			scenes = [...setupScenes, targetScene];
			totalDuration = targetScene.startSec + targetScene.durationSec;
		}
	}

	const totalFrames = Math.round(totalDuration * fps);
	const durationSec = totalDuration;
	const paramCount = shader.params ? shader.params.length : 0;
	process.stdout.write(`  ${durationSec}s video (${paramCount} params, ${interactionType} interaction, ${totalFrames} frames)\n`);

	// Set viewport
	await page.setViewport({
		width: viewportWidth,
		height: viewportHeight,
		deviceScaleFactor: DPR
	});

	// ── Start on the SvelteKit detail page (real UI) ──
	const detailUrl = `${devUrl}/shader/${shader.id}`;
	process.stdout.write(`  Loading detail page...`);
	await page.goto(detailUrl, { waitUntil: 'networkidle2', timeout: 15000 });
	await new Promise(r => setTimeout(r, 2000)); // let iframe shader warm up

	// Create overlay container on <html> (outside body transforms)
	await ensureOverlayContainer(page);

	// Force the preview area to match the video aspect ratio
	const videoAspect = preset.width / preset.height;
	await page.evaluate((aspect) => {
		const style = document.createElement('style');
		style.id = '__video-aspect-override';
		style.textContent = `
			.preview-area {
				display: flex !important;
				align-items: center !important;
				justify-content: center !important;
			}
			.preview-area .preview {
				aspect-ratio: ${aspect} !important;
				width: 100% !important;
				height: auto !important;
				max-height: 100% !important;
			}
			.preview-area .preview.layout-full .mock-layout {
				aspect-ratio: ${aspect} !important;
			}
		`;
		document.head.appendChild(style);
	}, videoAspect);
	await new Promise(r => setTimeout(r, 300));
	process.stdout.write(' done\n');

	// Apply default color scheme on the detail page
	const defaultScheme = COLOR_SCHEMES.find(s => s.id === shader.defaultScheme) || COLOR_SCHEMES[0];
	if (defaultScheme.id !== 'amber') {
		// Click the color scheme button
		await page.evaluate((schemeId) => {
			const btns = document.querySelectorAll('.ctrl-btn');
			for (const btn of btns) {
				if (btn.textContent.trim().toLowerCase().includes(schemeId) ||
					btn.querySelector(`[style*="${schemeId}"]`)) {
					btn.click();
					return;
				}
			}
			// Fallback: find by scheme name in title attribute
			for (const btn of btns) {
				if (btn.title && btn.title.toLowerCase() === schemeId) {
					btn.click();
					return;
				}
			}
		}, defaultScheme.id);
		await new Promise(r => setTimeout(r, 500));
	}

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
	let iframeFrameCount = 0; // Track frames rendered in iframe for seamless transition

	for (let frame = 0; frame < totalFrames; frame++) {
		const scene = getScene(scenes, frame);
		const progress = sceneProgress(scene, frame);

		// --- Apply scene-specific actions ---

		// ── Detail page scene: advance iframe shader deterministically ──
		if (scene.name === 'detailpage') {
			await page.evaluate((dt) => {
				const iframe = document.querySelector('iframe');
				if (iframe && iframe.contentWindow && iframe.contentWindow.__captureAdvanceFrame) {
					iframe.contentWindow.__captureAdvanceFrame(dt);
				}
			}, dt);
			iframeFrameCount++;
			await page.evaluate(() => new Promise(r => setTimeout(r, 0)));

			const screenshot = await page.screenshot({ type: 'png', fullPage: false, omitBackground: false });
			const canWrite = ffmpeg.stdin.write(screenshot);
			if (!canWrite) await new Promise(resolve => ffmpeg.stdin.once('drain', resolve));

			// Progress
			const percent = Math.floor((frame / totalFrames) * 100);
			if (percent !== lastPercent && percent % 5 === 0) {
				const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
				const framesPerSec = (frame / (Date.now() - startTime) * 1000).toFixed(1);
				process.stdout.write(`  Recording: ${percent}% (frame ${frame}/${totalFrames}, ${framesPerSec} fps, ${elapsed}s elapsed)\r`);
				lastPercent = percent;
			}
			continue;
		}

		// ── Zoom scene: animate preview area to fullscreen ──
		if (scene.name === 'zoom') {
			const zoomProgress = easeInOut(sceneProgress(scene, frame));

			// Advance the iframe shader
			await page.evaluate((dt) => {
				const iframe = document.querySelector('iframe');
				if (iframe && iframe.contentWindow && iframe.contentWindow.__captureAdvanceFrame) {
					iframe.contentWindow.__captureAdvanceFrame(dt);
				}
			}, dt);
			iframeFrameCount++;

			// On first zoom frame, measure the iframe rect and store it
			if (frame === scene.startFrame) {
				await page.evaluate(() => {
					const iframe = document.querySelector('iframe');
					if (iframe) {
						const r = iframe.getBoundingClientRect();
						window.__zoomStartRect = { left: r.left, top: r.top, width: r.width, height: r.height };
					}
				});
			}

			await page.evaluate((p) => {
				const r = window.__zoomStartRect;
				if (!r) return;
				const vw = window.innerWidth;
				const vh = window.innerHeight;

				// Compute scale to fill viewport from the iframe's initial rect
				const scaleX = vw / r.width;
				const scaleY = vh / r.height;
				const scale = 1 + (Math.max(scaleX, scaleY) - 1) * p;

				// Translate iframe center to viewport center
				const cx = r.left + r.width / 2;
				const cy = r.top + r.height / 2;
				const tx = (vw / 2 - cx) * p;
				const ty = (vh / 2 - cy) * p;

				// Apply to the whole page as a zoom effect
				document.body.style.transformOrigin = cx + 'px ' + cy + 'px';
				document.body.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;

				// Fade out all chrome
				const fadeOut = Math.max(0, 1 - p * 2);
				document.querySelectorAll('nav, .sidebar, .main > header, .back-link').forEach(el => {
					el.style.opacity = String(fadeOut);
				});
				// Fade out preview border
				const preview = document.querySelector('.preview');
				if (preview) {
					preview.style.borderColor = `rgba(200, 149, 108, ${0.12 * (1 - p)})`;
					preview.style.borderRadius = (8 * (1 - p)) + 'px';
				}
			}, zoomProgress);

			await page.evaluate(() => new Promise(r => setTimeout(r, 0)));

			const screenshot = await page.screenshot({ type: 'png', fullPage: false, omitBackground: false });
			const canWrite = ffmpeg.stdin.write(screenshot);
			if (!canWrite) await new Promise(resolve => ffmpeg.stdin.once('drain', resolve));

			const percent = Math.floor((frame / totalFrames) * 100);
			if (percent !== lastPercent && percent % 5 === 0) {
				const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
				const framesPerSec = (frame / (Date.now() - startTime) * 1000).toFixed(1);
				process.stdout.write(`  Recording: ${percent}% (frame ${frame}/${totalFrames}, ${framesPerSec} fps, ${elapsed}s elapsed)\r`);
				lastPercent = percent;
			}

			// At end of zoom, hide the shader label inside the iframe
			if (frame === scene.startFrame + scene.durationFrames - 1) {
				await page.evaluate(() => {
					const iframe = document.querySelector('iframe');
					if (iframe) {
						const doc = iframe.contentDocument || iframe.contentWindow.document;
						const label = doc.querySelector('.label');
						if (label) label.style.display = 'none';
					}
				});
			}

			continue;
		}

		// ── Outro: navigate to dedicated outro page ──
		if (scene.name === 'outro' && !outroLoaded) {
			outroLoaded = true;
			await hideCaption(page);
			await hideSliderOverlay(page);
			const outroUrl = `${baseUrl}/video-outro.html?name=${encodeURIComponent(shader.title)}&url=${encodeURIComponent('radiant-shaders.com/shader/' + shader.id)}`;
			// Outro is pure HTML/CSS (no canvas/rAF) — just navigate and let CSS animate
			await page.goto(outroUrl, { waitUntil: 'domcontentloaded' });
			await new Promise(r => setTimeout(r, 500));
		}

		// Mouse movement — only during interaction scene
		if (scene.name === 'interaction') {
			const mousePos = figure8(progress);
			const mx = mousePos.x * viewportWidth;
			const my = mousePos.y * viewportHeight;
			let cursorState = 'move';

			if (interactionType === 'drag') {
				if (frame === scene.startFrame) {
					await page.mouse.move(mx, my);
					await page.mouse.down();
					cursorState = 'drag';
				} else if (frame === scene.startFrame + scene.durationFrames - 1) {
					await page.mouse.move(mx, my);
					await page.mouse.up();
					cursorState = 'move';
				} else {
					await page.mouse.move(mx, my);
					cursorState = 'drag';
				}
			} else if (interactionType === 'click' || interactionType === 'click+hover') {
				await page.mouse.move(mx, my);
				await page.evaluate(({ x, y }) => {
					// Dispatch on iframe's canvas
					const iframe = document.querySelector('iframe');
					const c = iframe ? (iframe.contentDocument || iframe.contentWindow.document).getElementById('canvas') : document.getElementById('canvas');
					if (c) c.dispatchEvent(new MouseEvent('mousemove', {
						clientX: x, clientY: y, bubbles: true, view: c.ownerDocument.defaultView
					}));
				}, { x: mx, y: my });
				const framesPerClick = Math.round(1.5 * fps);
				const frameInScene = frame - scene.startFrame;
				if (frameInScene > 0 && frameInScene % framesPerClick === 0) {
					await page.mouse.click(mx, my);
					cursorState = 'click';
				}
			} else {
				await page.mouse.move(mx, my);
				await page.evaluate(({ x, y }) => {
					// Dispatch on iframe's canvas
					const iframe = document.querySelector('iframe');
					const c = iframe ? (iframe.contentDocument || iframe.contentWindow.document).getElementById('canvas') : document.getElementById('canvas');
					if (c) c.dispatchEvent(new MouseEvent('mousemove', {
						clientX: x, clientY: y, bubbles: true, view: c.ownerDocument.defaultView
					}));
				}, { x: mx, y: my });
			}

			// Show visual cursor
			await showCursor(page, mx, my, cursorState);
		} else if (scene.name !== 'outro') {
			// Move mouse off-screen and hide cursor for all other scenes
			if (frame === scene.startFrame) {
				await hideCursor(page);
				await page.mouse.move(-10, -10);
				await page.evaluate(() => {
					const iframe = document.querySelector('iframe');
					const c = iframe ? (iframe.contentDocument || iframe.contentWindow.document).getElementById('canvas') : document.getElementById('canvas');
					if (c) c.dispatchEvent(new MouseEvent('mouseleave', {
						bubbles: true, cancelable: true, view: c.ownerDocument.defaultView
					}));
				});
			}
		}

		// Parameter changes (scene: parameters) with visual slider
		if (scene.name === 'parameters' && shader.params && shader.params.length > 0) {
			const paramValues = computeParamValues(shader.params, progress);
			for (const pv of paramValues) {
				await page.evaluate(({ name, value }) => {
					const iframe = document.querySelector('iframe');
					const target = iframe ? iframe.contentWindow : window;
					target.postMessage({ type: 'param', name, value }, '*');
				}, { name: pv.name, value: pv.value });
			}
			// Show slider overlay for the active parameter
			if (enableCaptions) {
				const active = paramValues.find(pv => pv.isActive);
				if (active) {
					const param = shader.params.find(p => p.name === active.name);
					const fadeFrames = Math.round(0.5 * fps);
					const opacity = captionOpacity(frame - scene.startFrame, scene.durationFrames, fadeFrames);
					await setSliderOverlay(page, active.label, active.value, param.min, param.max, opacity);
				}
			}
		} else if (scene.name !== 'parameters') {
			// Reset params to default and hide slider
			if (frame === scene.startFrame) {
				await hideSliderOverlay(page);
				if (shader.params) {
					for (const p of shader.params) {
						await page.evaluate(({ name, value }) => {
							window.postMessage({ type: 'param', name, value }, '*');
						}, { name: p.name, value: p.default });
					}
				}
			}
		}

		// Color scheme scene: 6-panel split screen with live iframes
		if (scene.name === 'colors') {
			const frameInScene = frame - scene.startFrame;

			// On first frame, build the grid with 6 live shader iframes
			if (frameInScene === 0) {
				// Use same origin (dev server) for grid iframes to allow cross-frame access
				const gridBaseUrl = devUrl;
				await page.evaluate(({ schemes, shaderFile, baseUrl }) => {
					const container = document.getElementById('__video-overlays') || document.body;
					const grid = document.createElement('div');
					grid.id = '__color-grid';
					Object.assign(grid.style, {
						position: 'fixed',
						inset: '0',
						display: 'grid',
						gridTemplateColumns: 'repeat(3, 1fr)',
						gridTemplateRows: 'repeat(2, 1fr)',
						gap: '3px',
						background: '#0a0a0a',
						zIndex: '100000',
						opacity: '0',
						transition: 'none',
						pointerEvents: 'auto'
					});
					for (const scheme of schemes) {
						const cell = document.createElement('div');
						Object.assign(cell.style, {
							position: 'relative',
							overflow: 'hidden'
						});
						const iframe = document.createElement('iframe');
						iframe.src = baseUrl + '/' + shaderFile;
						Object.assign(iframe.style, {
							position: 'absolute',
							inset: '0',
							width: '100%',
							height: '100%',
							border: 'none',
							filter: scheme.filter,
							pointerEvents: 'none'
						});
						const label = document.createElement('div');
						Object.assign(label.style, {
							position: 'absolute',
							bottom: '8px',
							left: '50%',
							transform: 'translateX(-50%)',
							fontFamily: '"Inter", -apple-system, system-ui, sans-serif',
							fontSize: '11px',
							fontWeight: '500',
							letterSpacing: '0.08em',
							textTransform: 'uppercase',
							color: 'rgba(232, 224, 216, 0.8)',
							background: 'rgba(10, 10, 10, 0.6)',
							backdropFilter: 'blur(4px)',
							padding: '3px 10px',
							borderRadius: '4px',
							whiteSpace: 'nowrap',
							zIndex: '1'
						});
						label.textContent = scheme.name;
						cell.appendChild(iframe);
						cell.appendChild(label);
						grid.appendChild(cell);
					}
					container.appendChild(grid);
				}, { schemes: COLOR_SCHEMES, shaderFile: shader.file, baseUrl: gridBaseUrl });

				// Wait for iframes to load
				await new Promise(r => setTimeout(r, 2000));

				// Hide labels inside each grid iframe
				await page.evaluate(() => {
					const grid = document.getElementById('__color-grid');
					if (!grid) return;
					grid.querySelectorAll('iframe').forEach(iframe => {
						try {
							const doc = iframe.contentDocument || iframe.contentWindow.document;
							const label = doc.querySelector('.label');
							if (label) label.style.display = 'none';
						} catch(e) {}
					});
				});
			}

			// Advance all 6 grid iframes + the main iframe
			await page.evaluate((dt) => {
				// Advance grid iframes
				const grid = document.getElementById('__color-grid');
				if (grid) {
					grid.querySelectorAll('iframe').forEach(iframe => {
						try {
							if (iframe.contentWindow && iframe.contentWindow.__captureAdvanceFrame) {
								iframe.contentWindow.__captureAdvanceFrame(dt);
							}
						} catch(e) {}
					});
				}
			}, dt);

			// Fade in only (grid stays until outro navigates away)
			const fadeFrames = Math.round(0.5 * fps);
			const gridOpacity = Math.min(1, frameInScene / fadeFrames);
			await page.evaluate((o) => {
				const grid = document.getElementById('__color-grid');
				if (grid) grid.style.opacity = String(o);
			}, gridOpacity);

		} else if (scene.name !== 'colors') {
			if (frame === scene.startFrame) {
				await page.evaluate((f) => {
					const iframe = document.querySelector('iframe');
					if (iframe) iframe.style.filter = f;
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
					if (interactionType === 'drag') captionText = 'Drag to interact';
					else if (interactionType === 'click+hover') captionText = 'Move & click to interact';
					else if (interactionType === 'click') captionText = 'Click to interact';
					else captionText = 'Move cursor to interact';
					break;
				case 'parameters':
					// Slider overlay handles this scene — no caption needed
					break;
				case 'colors':
					captionText = '6 color themes';
					break;
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
		if (outroLoaded) {
			// Outro runs real-time
			await new Promise(r => setTimeout(r, dt));
		} else {
			// Advance the iframe's shader
			await page.evaluate((dt) => {
				const iframe = document.querySelector('iframe');
				if (iframe && iframe.contentWindow && iframe.contentWindow.__captureAdvanceFrame) {
					iframe.contentWindow.__captureAdvanceFrame(dt);
				} else if (window.__captureAdvanceFrame) {
					window.__captureAdvanceFrame(dt);
				}
			}, dt);
		}

		// Force a repaint before capture (needed for Canvas 2D shaders)
		await page.evaluate(() => new Promise(r => setTimeout(r, 0)));

		// Bail out loudly if the tab crashed — don't silently capture crash UI frames.
		if (page.__crashError) {
			throw new Error(`Chrome tab crashed at frame ${frame}/${totalFrames}: ${page.__crashError.message}`);
		}

		// Capture the frame as PNG
		const screenshot = await page.screenshot({
			type: 'png',
			fullPage: false,
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
		format: 'landscape',
		fps: 60,
		warmup: DEFAULT_WARMUP_FRAMES,
		devUrl: 'http://localhost:5173',
		scene: null, // debug: only render a specific scene
		output: join(ROOT, 'videos'),
		captions: true
	};

	for (const arg of args) {
		if (arg.startsWith('--shader=')) {
			opts.shader = arg.split('=')[1];
		} else if (arg === '--all') {
			opts.all = true;
		} else if (arg.startsWith('--warmup=')) {
			opts.warmup = parseInt(arg.split('=')[1], 10);
		} else if (arg.startsWith('--dev-url=')) {
			opts.devUrl = arg.split('=')[1];
		} else if (arg.startsWith('--scene=')) {
			opts.scene = arg.split('=')[1]; // e.g. --scene=colors
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

Duration is calculated automatically from shader content:
  4s opening + 4s interaction + 3s per param + 4s color themes + 3s outro

Options:
  --shader=ID          Record a specific shader (required unless --all)
  --all                Record all shaders
  --format=PRESET      landscape|reel|square (default: landscape)
  --fps=FPS            Frame rate (default: 60)
  --warmup=FRAMES      Warmup frames before recording (default: 0)
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
	console.log(`FPS:        ${opts.fps}`);
	console.log(`DPR:        ${DPR}x`);
	console.log(`Captions:   ${opts.captions ? 'enabled' : 'disabled'}`);
	console.log(`Duration:   auto (4s + 4s + 3s/param + 4s + 3s)`);
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

	// Crash detection. page.on('error') fires when the tab crashes (e.g. GPU process OOM,
	// shader watchdog timeout). Without this, page.screenshot() silently captures the
	// "aw snap" crash UI and encodes it into the final mp4.
	page.__crashError = null;
	page.on('error', (err) => { page.__crashError = err; });
	page.on('pageerror', (err) => {
		// Don't fail on pageerror (script errors are sometimes benign), just log.
		console.error(`  [page error] ${err.message}`);
	});

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
			const outPath = await recordShader(page, baseUrl, opts.devUrl, shader, {
				format: opts.format,
				fps: opts.fps,
				warmup: opts.warmup,
				sceneFilter: opts.scene,
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
