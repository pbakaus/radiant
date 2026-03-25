<script lang="ts">
	import { onMount } from 'svelte';
	import type { Shader } from '$lib/shaders';

	const { data } = $props();
	const allShaders: Shader[] = data.shaders;

	// --- Constants ---
	const DWELL_MS = 12_000;
	const MORPH_MS = 3_000;
	const PRELOAD_LEAD_MS = 2_500;
	const ZOOM_MIN = 1.0;
	const ZOOM_MAX = 1.35;
	const HUE_CYCLE_DURATION_S = 300;
	const MORPH_SOFTNESS = 0.25;
	const MORPH_NOISE_SCALE = 3.0;
	const ABOUT_BLANK = 'about:blank';

	// --- GLSL sources ---
	const VERT_SRC = `
		attribute vec2 a_pos;
		varying vec2 v_uv;
		void main() {
			v_uv = a_pos * 0.5 + 0.5;
			gl_Position = vec4(a_pos, 0.0, 1.0);
		}
	`;

	const FRAG_SRC = `
		precision highp float;
		varying vec2 v_uv;

		uniform sampler2D u_texA;
		uniform sampler2D u_texB;
		uniform float u_progress;
		uniform float u_zoom;
		uniform vec2  u_mouse;
		uniform float u_hueShift;
		uniform float u_time;

		vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
		vec2 mod289v2(vec2 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
		vec3 permute(vec3 x) { return mod289((x * 34.0 + 1.0) * x); }

		float snoise(vec2 v) {
			const vec4 C = vec4(0.211324865405187, 0.366025403784439,
			                    -0.577350269189626, 0.024390243902439);
			vec2 i = floor(v + dot(v, C.yy));
			vec2 x0 = v - i + dot(i, C.xx);
			vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
			vec4 x12 = x0.xyxy + C.xxzz;
			x12.xy -= i1;
			i = mod289v2(i);
			vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
			vec3 m = max(0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
			m = m * m; m = m * m;
			vec3 x_ = 2.0 * fract(p * C.www) - 1.0;
			vec3 h = abs(x_) - 0.5;
			vec3 ox = floor(x_ + 0.5);
			vec3 a0 = x_ - ox;
			m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
			vec3 g;
			g.x = a0.x * x0.x + h.x * x0.y;
			g.yz = a0.yz * x12.xz + h.yz * x12.yw;
			return 130.0 * dot(m, g);
		}

		vec3 hueRotate(vec3 c, float angle) {
			float cosA = cos(angle);
			float sinA = sin(angle);
			vec3 k = vec3(0.57735);
			return c * cosA + cross(k, c) * sinA + k * dot(k, c) * (1.0 - cosA);
		}

		void main() {
			vec2 uv = (v_uv - u_mouse) / u_zoom + u_mouse;
			uv = clamp(uv, 0.0, 1.0);
			vec2 texUV = vec2(uv.x, 1.0 - uv.y);

			vec4 colA = texture2D(u_texA, texUV);
			vec4 colB = texture2D(u_texB, texUV);

			if (u_progress <= 0.0) {
				gl_FragColor = vec4(hueRotate(colA.rgb, u_hueShift), 1.0);
				return;
			}
			if (u_progress >= 1.0) {
				gl_FragColor = vec4(hueRotate(colB.rgb, u_hueShift), 1.0);
				return;
			}

			float n = snoise(v_uv * ${MORPH_NOISE_SCALE.toFixed(1)} + u_time * 0.15);
			n += 0.5 * snoise(v_uv * ${(MORPH_NOISE_SCALE * 2.0).toFixed(1)} - u_time * 0.1);
			n = n * 0.5 + 0.5;

			float edge = smoothstep(
				u_progress + ${MORPH_SOFTNESS.toFixed(2)},
				u_progress - ${MORPH_SOFTNESS.toFixed(2)},
				n
			);

			vec3 blended = mix(colA.rgb, colB.rgb, edge);
			gl_FragColor = vec4(hueRotate(blended, u_hueShift), 1.0);
		}
	`;

	// --- Element refs (bound in template) ---
	let glCanvas: HTMLCanvasElement | undefined = $state();
	let iframeA: HTMLIFrameElement | undefined = $state();
	let iframeB: HTMLIFrameElement | undefined = $state();

	// --- Reactive state for UI only ---
	let displayTitle = $state('');
	let displayNumber = $state('01');
	let titleVisible = $state(true);
	let showInfo = $state(true);

	// --- Non-reactive mutable state for the animation loop ---
	let mouseNormX = 0.5;
	let mouseNormY = 0.5;

	function shuffleArray(arr: number[]): number[] {
		const a = [...arr];
		for (let i = a.length - 1; i > 0; i--) {
			const j = Math.floor(Math.random() * (i + 1));
			[a[i], a[j]] = [a[j], a[i]];
		}
		return a;
	}

	function getIframeCanvas(iframe: HTMLIFrameElement | null | undefined): HTMLCanvasElement | null {
		if (!iframe) return null;
		try {
			return iframe.contentDocument?.getElementById('canvas') as HTMLCanvasElement | null;
		} catch {
			return null;
		}
	}

	function hideLabel(iframe: HTMLIFrameElement) {
		try {
			const doc = iframe.contentDocument;
			if (doc) {
				const label = doc.querySelector('.label');
				if (label) (label as HTMLElement).style.display = 'none';
			}
		} catch { /* cross-origin */ }
	}

	function onIframeLoad(e: Event) {
		hideLabel(e.target as HTMLIFrameElement);
	}

	// --- onMount: runs once, no reactive tracking ---
	onMount(() => {
		if (!glCanvas || !iframeA || !iframeB) return;

		const order = shuffleArray(Array.from({ length: allShaders.length }, (_, i) => i));
		let seqIndex = 0;

		function getShader(idx: number): Shader {
			return allShaders[order[idx % order.length]];
		}

		// Load the first shader into iframe A
		const first = getShader(0);
		iframeA.src = `/${first.file}`;
		iframeB.src = ABOUT_BLANK;
		displayTitle = first.title;
		displayNumber = '01';
		titleVisible = true;

		// --- WebGL init ---
		const dpr = Math.min(devicePixelRatio, 2);
		function resize() {
			const w = Math.round(innerWidth * dpr);
			const h = Math.round(innerHeight * dpr);
			if (glCanvas!.width !== w || glCanvas!.height !== h) {
				glCanvas!.width = w;
				glCanvas!.height = h;
			}
		}
		resize();
		window.addEventListener('resize', resize);

		const gl = glCanvas.getContext('webgl', { alpha: false, antialias: false })!;

		function compile(type: number, src: string): WebGLShader {
			const s = gl.createShader(type)!;
			gl.shaderSource(s, src);
			gl.compileShader(s);
			if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
				console.error('Shader compile:', gl.getShaderInfoLog(s));
			}
			return s;
		}

		const prog = gl.createProgram()!;
		gl.attachShader(prog, compile(gl.VERTEX_SHADER, VERT_SRC));
		gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FRAG_SRC));
		gl.linkProgram(prog);
		if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
			console.error('Program link:', gl.getProgramInfoLog(prog));
		}
		gl.useProgram(prog);

		// Fullscreen quad
		const buf = gl.createBuffer()!;
		gl.bindBuffer(gl.ARRAY_BUFFER, buf);
		gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, -1,1, 1,1]), gl.STATIC_DRAW);
		const aPos = gl.getAttribLocation(prog, 'a_pos');
		gl.enableVertexAttribArray(aPos);
		gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

		// Textures
		function createTex(unit: number): WebGLTexture {
			const tex = gl.createTexture()!;
			gl.activeTexture(gl.TEXTURE0 + unit);
			gl.bindTexture(gl.TEXTURE_2D, tex);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
			gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
			gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE,
				new Uint8Array([0, 0, 0, 255]));
			return tex;
		}

		const texA = createTex(0);
		const texB = createTex(1);

		const uTexA = gl.getUniformLocation(prog, 'u_texA');
		const uTexB = gl.getUniformLocation(prog, 'u_texB');
		const uProgress = gl.getUniformLocation(prog, 'u_progress');
		const uZoom = gl.getUniformLocation(prog, 'u_zoom');
		const uMouse = gl.getUniformLocation(prog, 'u_mouse');
		const uHueShift = gl.getUniformLocation(prog, 'u_hueShift');
		const uTime = gl.getUniformLocation(prog, 'u_time');
		gl.uniform1i(uTexA, 0);
		gl.uniform1i(uTexB, 1);

		// --- Animation state (all non-reactive) ---
		let phase: 'dwell' | 'morph' | 'morph-done' = 'dwell';
		let activeIframe: 'A' | 'B' = 'A';
		let preloaded = false;
		let titleSwapped = false;
		let currentZoom = ZOOM_MIN;
		let zoomAtMorphStart = ZOOM_MIN;
		const globalStart = performance.now();
		let phaseStart = globalStart;

		function tick(now: number) {
			const globalElapsed = now - globalStart;
			const phaseElapsed = now - phaseStart;
			const timeSec = globalElapsed / 1000;
			const hueRad = (timeSec / HUE_CYCLE_DURATION_S) * Math.PI * 2;

			let morphProgress = 0;

			if (phase === 'dwell') {
				const zoomT = Math.min(phaseElapsed / (DWELL_MS + MORPH_MS), 1);
				currentZoom = ZOOM_MIN + (ZOOM_MAX - ZOOM_MIN) * zoomT;

				// Preload the next shader into the inactive iframe
				if (!preloaded && phaseElapsed >= DWELL_MS - PRELOAD_LEAD_MS) {
					preloaded = true;
					const next = getShader(seqIndex + 1);
					const url = `/${next.file}`;
					if (activeIframe === 'A') {
						iframeB!.src = url;
					} else {
						iframeA!.src = url;
					}
				}

				if (phaseElapsed >= DWELL_MS) {
					zoomAtMorphStart = currentZoom;
					phase = 'morph';
					phaseStart = now;
					titleVisible = false;
					titleSwapped = false;
				}
			} else if (phase === 'morph') {
				// Morph phase
				const rawT = Math.min(phaseElapsed / MORPH_MS, 1);
				morphProgress = rawT * rawT * (3 - 2 * rawT);

				// Ease zoom back to ZOOM_MIN during morph so there's no snap
				currentZoom = zoomAtMorphStart + (ZOOM_MIN - zoomAtMorphStart) * morphProgress;

				if (rawT > 0.5 && !titleSwapped) {
					titleSwapped = true;
					seqIndex++;
					const s = getShader(seqIndex);
					displayTitle = s.title;
					displayNumber = String((seqIndex % allShaders.length) + 1).padStart(2, '0');
				}

				if (rawT >= 1) {
					// Render one last frame at full progress before swapping
					morphProgress = 1;
					phase = 'morph-done';
				}
			} else {
				// morph-done: swap happened last frame, now start dwell
				if (activeIframe === 'A') {
					activeIframe = 'B';
					iframeA!.src = ABOUT_BLANK;
				} else {
					activeIframe = 'A';
					iframeB!.src = ABOUT_BLANK;
				}
				titleVisible = true;
				phase = 'dwell';
				phaseStart = now;
				preloaded = false;
				currentZoom = ZOOM_MIN;
				morphProgress = 0;
			}

			// --- Render ---
			resize();
			gl.viewport(0, 0, glCanvas!.width, glCanvas!.height);

			// Upload textures: "current" always goes to texA, "next" to texB
			const currentCanvas = getIframeCanvas(activeIframe === 'A' ? iframeA! : iframeB!);
			const nextCanvas = getIframeCanvas(activeIframe === 'A' ? iframeB! : iframeA!);

			if (currentCanvas && currentCanvas.width > 0) {
				gl.activeTexture(gl.TEXTURE0);
				gl.bindTexture(gl.TEXTURE_2D, texA);
				gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, currentCanvas);
			}

			if (morphProgress > 0 && nextCanvas && nextCanvas.width > 0) {
				gl.activeTexture(gl.TEXTURE1);
				gl.bindTexture(gl.TEXTURE_2D, texB);
				gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, nextCanvas);
			}

			gl.uniform1f(uProgress, morphProgress);
			gl.uniform1f(uZoom, currentZoom);
			gl.uniform2f(uMouse, mouseNormX, 1.0 - mouseNormY);
			gl.uniform1f(uHueShift, hueRad);
			gl.uniform1f(uTime, timeSec);

			gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);

			raf = requestAnimationFrame(tick);
		}

		let raf = requestAnimationFrame(tick);

		// Info dismiss
		const infoTimeout = setTimeout(() => { showInfo = false; }, 4000);

		return () => {
			cancelAnimationFrame(raf);
			clearTimeout(infoTimeout);
			window.removeEventListener('resize', resize);
		};
	});

	// --- Mouse tracking ---
	function handleMouseMove(e: MouseEvent) {
		mouseNormX = e.clientX / innerWidth;
		mouseNormY = e.clientY / innerHeight;
	}

	function handleTouchMove(e: TouchEvent) {
		if (!e.touches[0]) return;
		mouseNormX = e.touches[0].clientX / innerWidth;
		mouseNormY = e.touches[0].clientY / innerHeight;
	}

	function handleKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') history.back();
	}
</script>

<svelte:window onkeydown={handleKeydown} />

<svelte:head>
	<title>Zoom — Radiant</title>
	<style>
		nav { display: none !important; }
		body { overflow: hidden; }
	</style>
</svelte:head>

<!-- WebGL compositing canvas -->
<canvas
	class="gl-canvas"
	bind:this={glCanvas}
	onmousemove={handleMouseMove}
	ontouchmove={handleTouchMove}
></canvas>

<!-- Iframes: on-screen behind the opaque GL canvas so browsers render their canvases -->
<div class="iframe-stash">
	<iframe
		bind:this={iframeA}
		src={ABOUT_BLANK}
		title="Shader A"
		onload={onIframeLoad}
	></iframe>
	<iframe
		bind:this={iframeB}
		src={ABOUT_BLANK}
		title="Shader B"
		onload={onIframeLoad}
	></iframe>
</div>

<!-- UI overlay (outside GL so it's not hue-shifted) -->
<div class="zoom-ui">
	<div class="shader-title" class:visible={titleVisible}>
		<span class="title-number">{displayNumber}</span>
		<span class="title-text">{displayTitle}</span>
	</div>

	<div class="info-overlay" class:hidden={!showInfo}>
		<p>Move your mouse to guide the zoom</p>
		<p class="subtle">Press <kbd>Esc</kbd> to exit</p>
	</div>

	<a href="/gallery/all" class="close-btn" aria-label="Close">
		<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
			<path d="M18 6L6 18M6 6l12 12" />
		</svg>
	</a>
</div>

<style>
	.gl-canvas {
		position: fixed;
		inset: 0;
		width: 100vw;
		height: 100vh;
		z-index: 9999;
		cursor: none;
		display: block;
	}

	.iframe-stash {
		position: fixed;
		inset: 0;
		width: 100vw;
		height: 100vh;
		pointer-events: none;
		z-index: 1;
	}

	.iframe-stash iframe {
		width: 100%;
		height: 100%;
		border: none;
		position: absolute;
		inset: 0;
	}

	.zoom-ui {
		position: fixed;
		inset: 0;
		z-index: 10000;
		pointer-events: none;
	}

	.shader-title {
		position: fixed;
		bottom: 32px;
		left: 32px;
		display: flex;
		align-items: baseline;
		gap: 12px;
		opacity: 0;
		transition: opacity 1.2s ease;
	}

	.shader-title.visible {
		opacity: 0.6;
	}

	.title-number {
		font-size: 12px;
		font-weight: 300;
		letter-spacing: 0.05em;
		color: rgba(200, 149, 108, 0.5);
		font-variant-numeric: tabular-nums;
	}

	.title-text {
		font-size: 14px;
		font-weight: 300;
		letter-spacing: 0.03em;
		color: rgba(232, 224, 216, 0.7);
	}

	.info-overlay {
		position: fixed;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 8px;
		background: rgba(10, 10, 10, 0.6);
		opacity: 1;
		transition: opacity 1.5s ease;
	}

	.info-overlay.hidden {
		opacity: 0;
	}

	.info-overlay p {
		font-size: 16px;
		font-weight: 300;
		letter-spacing: 0.04em;
		color: rgba(232, 224, 216, 0.8);
	}

	.info-overlay .subtle {
		font-size: 13px;
		color: rgba(232, 224, 216, 0.4);
	}

	.info-overlay kbd {
		display: inline-block;
		padding: 2px 6px;
		border: 1px solid rgba(200, 149, 108, 0.3);
		border-radius: 3px;
		font-family: inherit;
		font-size: 12px;
		color: rgba(200, 149, 108, 0.7);
	}

	.close-btn {
		position: fixed;
		top: 20px;
		right: 20px;
		width: 40px;
		height: 40px;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: 50%;
		background: rgba(10, 10, 10, 0.5);
		color: rgba(232, 224, 216, 0.5);
		transition: color 0.3s, background 0.3s;
		pointer-events: auto;
		cursor: pointer;
	}

	.close-btn:hover {
		color: rgba(232, 224, 216, 0.9);
		background: rgba(10, 10, 10, 0.8);
	}
</style>
