<script lang="ts">
	import { onMount } from 'svelte';

	type ParamDef = {
		name: string;
		label: string;
		min: number;
		max: number;
		step?: number;
		default: number;
		format?: (v: number) => string;
	};

	let {
		src,
		params = [],
		preset = {},
		caption,
		aspect = '16/9',
		title = 'Sandbox',
		wide = true,
		toggle
	}: {
		src: string;
		params?: ParamDef[];
		preset?: Record<string, number>;
		caption?: string;
		aspect?: string;
		title?: string;
		wide?: boolean;
		toggle?: { name: string; label: string; offValue?: number; onValue?: number; default?: boolean };
	} = $props();

	let iframeEl: HTMLIFrameElement;
	// svelte-ignore state_referenced_locally
	let values = $state<Record<string, number>>(
		Object.fromEntries(params.map((p) => [p.name, p.default]))
	);
	// svelte-ignore state_referenced_locally
	let toggleOn = $state(toggle?.default ?? true);
	let loaded = $state(false);

	function applyAll() {
		if (!iframeEl?.contentWindow) return;
		// Preset first (sets up the scene), then current slider values
		for (const [name, value] of Object.entries(preset)) {
			iframeEl.contentWindow.postMessage({ type: 'param', name, value }, '*');
		}
		for (const [name, value] of Object.entries(values)) {
			iframeEl.contentWindow.postMessage({ type: 'param', name, value }, '*');
		}
		if (toggle) {
			const v = toggleOn ? (toggle.onValue ?? 1) : (toggle.offValue ?? 0);
			iframeEl.contentWindow.postMessage({ type: 'param', name: toggle.name, value: v }, '*');
		}
	}

	function sendParam(name: string, value: number) {
		values[name] = value;
		iframeEl?.contentWindow?.postMessage({ type: 'param', name, value }, '*');
	}

	function setToggle(on: boolean) {
		toggleOn = on;
		if (!toggle) return;
		const v = on ? (toggle.onValue ?? 1) : (toggle.offValue ?? 0);
		iframeEl?.contentWindow?.postMessage({ type: 'param', name: toggle.name, value: v }, '*');
	}

	function reset() {
		for (const p of params) {
			values[p.name] = p.default;
			iframeEl?.contentWindow?.postMessage({ type: 'param', name: p.name, value: p.default }, '*');
		}
		if (toggle) setToggle(toggle.default ?? true);
	}

	function onLoad() {
		loaded = true;
		// Hide the .label overlay inside the iframe (matches ShaderPreview pattern)
		try {
			const doc = iframeEl.contentDocument;
			const label = doc?.querySelector('.label') as HTMLElement | null;
			if (label) label.style.display = 'none';
		} catch {
			/* ignore cross-origin */
		}
		applyAll();
	}

	onMount(() => {
		// In case iframe already loaded
		if (iframeEl?.contentDocument?.readyState === 'complete') onLoad();
	});

	function digitsForStep(step?: number): number {
		if (!step) return 2;
		if (step >= 1) return 0;
		if (step >= 0.1) return 1;
		if (step >= 0.01) return 2;
		return 3;
	}

	function fmt(p: ParamDef): string {
		const v = values[p.name] ?? p.default;
		if (p.format) return p.format(v);
		return v.toFixed(digitsForStep(p.step));
	}
</script>

<figure class="sandbox" class:wide style:--aspect={aspect}>
	<div class="frame">
		<iframe
			bind:this={iframeEl}
			{src}
			{title}
			loading="lazy"
			onload={onLoad}
		></iframe>
		{#if !loaded}
			<div class="loading">Loading sandbox…</div>
		{/if}
	</div>

	{#if params.length || toggle}
		<div class="controls">
			<div class="controls-header">
				<span class="controls-label">Try it</span>
				<button class="reset" onclick={reset} title="Reset to defaults">Reset</button>
			</div>
			{#if toggle}
				<div class="toggle-row">
					<button
						class="toggle"
						class:on={toggleOn}
						onclick={() => setToggle(!toggleOn)}
						aria-pressed={toggleOn}
					>
						<span class="toggle-track"><span class="toggle-knob"></span></span>
						<span class="toggle-label">{toggle.label}</span>
					</button>
				</div>
			{/if}
			{#each params as p}
				<label class="row">
					<span class="row-label">{p.label}</span>
					<input
						type="range"
						min={p.min}
						max={p.max}
						step={p.step ?? 0.01}
						value={values[p.name] ?? p.default}
						oninput={(e) => sendParam(p.name, parseFloat(e.currentTarget.value))}
					/>
					<span class="row-value">{fmt(p)}</span>
				</label>
			{/each}
		</div>
	{/if}

	{#if caption}
		<figcaption>{caption}</figcaption>
	{/if}
</figure>

<style>
	.sandbox {
		margin: 2rem 0;
		display: flex;
		flex-direction: column;
		background: #0d0d0d;
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
	}

	.frame {
		position: relative;
		aspect-ratio: var(--aspect, 16 / 9);
		background: #0a0a0a;
	}
	iframe {
		position: absolute;
		inset: 0;
		width: 100%;
		height: 100%;
		border: 0;
		display: block;
	}
	.loading {
		position: absolute;
		inset: 0;
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 0.75rem;
		color: rgba(232, 224, 216, 0.3);
		font-family: 'SF Mono', monospace;
		letter-spacing: 0.05em;
	}

	.controls {
		display: flex;
		flex-direction: column;
		gap: 0.6rem;
		padding: 0.9rem 1.1rem 1rem;
		border-top: 1px solid rgba(200, 149, 108, 0.08);
		background: rgba(200, 149, 108, 0.02);
	}
	.controls-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: 0.1rem;
	}
	.controls-label {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.16em;
		color: rgba(200, 149, 108, 0.7);
	}
	.reset {
		background: transparent;
		border: 1px solid rgba(200, 149, 108, 0.15);
		color: rgba(232, 224, 216, 0.5);
		font-family: inherit;
		font-size: 0.7rem;
		padding: 0.2rem 0.55rem;
		border-radius: 3px;
		cursor: pointer;
		transition: all 0.15s;
	}
	.reset:hover {
		color: #c8956c;
		border-color: rgba(200, 149, 108, 0.4);
	}

	/* Toggle */
	.toggle-row {
		padding: 0.15rem 0 0.25rem;
	}
	.toggle {
		display: inline-flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.2rem 0;
		background: transparent;
		border: 0;
		cursor: pointer;
		color: rgba(232, 224, 216, 0.7);
		font-family: inherit;
		font-size: 0.85rem;
	}
	.toggle-track {
		display: inline-block;
		position: relative;
		width: 32px;
		height: 16px;
		background: rgba(200, 149, 108, 0.15);
		border-radius: 8px;
		transition: background 0.15s;
	}
	.toggle.on .toggle-track {
		background: rgba(200, 149, 108, 0.6);
	}
	.toggle-knob {
		position: absolute;
		top: 2px;
		left: 2px;
		width: 12px;
		height: 12px;
		background: #e8e0d8;
		border-radius: 50%;
		transition: transform 0.15s;
	}
	.toggle.on .toggle-knob {
		transform: translateX(16px);
	}
	.toggle-label {
		color: rgba(232, 224, 216, 0.75);
	}

	.row {
		display: grid;
		grid-template-columns: minmax(110px, 30%) 1fr 48px;
		align-items: center;
		gap: 0.75rem;
	}
	.row-label {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.6);
	}
	.row-value {
		text-align: right;
		font-family: 'SF Mono', monospace;
		font-size: 0.75rem;
		color: rgba(200, 149, 108, 0.7);
		font-variant-numeric: tabular-nums;
	}
	input[type='range'] {
		-webkit-appearance: none;
		appearance: none;
		width: 100%;
		height: 4px;
		background: rgba(200, 149, 108, 0.15);
		border-radius: 2px;
		outline: none;
		cursor: pointer;
	}
	input[type='range']::-webkit-slider-thumb {
		-webkit-appearance: none;
		appearance: none;
		width: 14px;
		height: 14px;
		background: #c8956c;
		border-radius: 50%;
		cursor: pointer;
		transition: transform 0.15s;
	}
	input[type='range']::-webkit-slider-thumb:hover {
		transform: scale(1.15);
	}
	input[type='range']::-moz-range-thumb {
		width: 14px;
		height: 14px;
		background: #c8956c;
		border: none;
		border-radius: 50%;
		cursor: pointer;
	}

	figcaption {
		padding: 0.7rem 1.1rem 0.9rem;
		font-size: 0.78rem;
		line-height: 1.5;
		color: rgba(232, 224, 216, 0.45);
		font-style: italic;
		border-top: 1px solid rgba(200, 149, 108, 0.05);
	}

	@media (max-width: 640px) {
		.row {
			grid-template-columns: 1fr 1fr 40px;
			gap: 0.5rem;
		}
		.row-label {
			font-size: 0.72rem;
		}
	}
</style>
