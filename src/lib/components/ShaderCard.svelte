<script lang="ts">
	import { getShaderNumber, type Shader } from '$lib/shaders';
	import { onMount } from 'svelte';

	let { shader, active = false, preload = false, filter = 'none' }: { shader: Shader; active?: boolean; preload?: boolean; filter?: string } = $props();

	const number = $derived(getShaderNumber(shader));

	let inViewport = $state(false);
	let posterUrl: string | null = $state(null);

	// Load iframe when in viewport AND (active row OR preloading adjacent row for poster capture)
	const shouldLoad = $derived(inViewport && (active || preload));

	function observe(node: HTMLElement) {
		const observer = new IntersectionObserver(
			([entry]) => {
				inViewport = entry.isIntersecting;
			},
			{ rootMargin: '200px' }
		);
		observer.observe(node);
		return {
			destroy() {
				observer.disconnect();
			}
		};
	}

	function onIframeLoad(el: HTMLIFrameElement) {
		try {
			var doc = el.contentDocument;
			if (!doc) return;

			// Inject FPS counter
			var fpsScript = doc.createElement('script');
			fpsScript.textContent = `(function(){
				var f=0,lt=performance.now(),el=document.createElement("div");
				el.style.cssText="position:fixed;bottom:4px;right:6px;font:9px/1 monospace;color:rgba(255,255,255,0.35);z-index:999;pointer-events:none;text-shadow:0 1px 2px rgba(0,0,0,0.8)";
				document.body.appendChild(el);
				function t(){f++;var n=performance.now();if(n-lt>=1000){el.textContent=f+" fps";f=0;lt=n;}requestAnimationFrame(t);}
				requestAnimationFrame(t);
			})();`;
			doc.body.appendChild(fpsScript);

			// Inject poster capture script — captures after ~30 frames for a warmed-up look
			// Captures synchronously right after drawArrays so the buffer is still valid
			// even with preserveDrawingBuffer: false
			var sid = shader.id.replace(/[^a-z0-9_-]/gi, '');
			var captureScript = doc.createElement('script');
			captureScript.textContent = `(function(){
				var captured=false;
				function send(c){
					if(captured)return; captured=true;
					try{
						var url=c.toDataURL("image/jpeg",0.65);
						parent.postMessage({type:"shaderFrame",id:"${sid}",dataUrl:url},"*");
					}catch(e){}
				}
				var c=document.getElementById("canvas");
				if(!c)return;
				var gl=null;
				try{gl=c.getContext("webgl")||c.getContext("webgl2");}catch(e){}
				if(gl){
					var fc=0,orig=WebGLRenderingContext.prototype.drawArrays;
					gl.drawArrays=function(){
						orig.apply(this,arguments);
						fc++;
						if(fc>=30&&!captured){gl.drawArrays=orig;send(c);}
					};
				}
				setTimeout(function(){send(c);},600);
			})();`;
			doc.body.appendChild(captureScript);
		} catch (e) {
			// cross-origin or blocked — silently ignore
		}
	}

	// Listen for poster capture messages from this card's iframe
	onMount(() => {
		function handler(e: MessageEvent) {
			if (e.data && e.data.type === 'shaderFrame' && e.data.id === shader.id && !posterUrl) {
				posterUrl = e.data.dataUrl;
			}
		}
		window.addEventListener('message', handler);
		return () => window.removeEventListener('message', handler);
	});
</script>

<a class="card" href="/shader/{shader.id}" use:observe>
	<div class="card-preview" class:inactive={!active} style:filter={active ? filter : undefined}>
		{#if posterUrl}
			<img src={posterUrl} alt={shader.title} class="poster" />
		{/if}
		{#if shouldLoad}
			<iframe
				class:capturing={!active}
				src="/{shader.file}"
				title={shader.title}
				onload={(e) => onIframeLoad(e.currentTarget as HTMLIFrameElement)}
			></iframe>
		{/if}
	</div>
	<div class="card-info">
		<div class="card-number">{number}{#if shader.inspiration} <span class="card-muse">— inspired by {shader.inspiration}</span>{/if}</div>
		<div class="card-title">{shader.title}</div>
		<div class="card-desc">{shader.desc}</div>
		<span class="card-action">Explore &rarr;</span>
	</div>
</a>

<style>
	.card {
		border: 1px solid rgba(200, 149, 108, 0.12);
		border-radius: 8px;
		overflow: hidden;
		transition:
			border-color 0.3s ease,
			transform 0.3s ease;
		background: #111;
		display: block;
	}
	.card:hover {
		border-color: rgba(200, 149, 108, 0.4);
		transform: translateY(-2px);
	}
	.card-preview {
		aspect-ratio: 16 / 10;
		background: #0a0a0a;
		display: flex;
		align-items: center;
		justify-content: center;
		border-bottom: 1px solid rgba(200, 149, 108, 0.08);
		position: relative;
		overflow: hidden;
		transition: filter 0.5s ease;
	}
	.card-preview.inactive {
		filter: grayscale(1) brightness(0.4);
	}
	.card-preview iframe {
		width: 100%;
		height: 100%;
		border: none;
		pointer-events: none;
		position: absolute;
		top: 0;
		left: 0;
		z-index: 1;
	}
	.card-preview iframe.capturing {
		visibility: hidden;
	}
	.card-preview .poster {
		width: 100%;
		height: 100%;
		object-fit: cover;
		position: absolute;
		top: 0;
		left: 0;
	}
	.card-info {
		padding: 1.2rem 1.5rem;
	}
	.card-number {
		font-size: 0.7rem;
		text-transform: uppercase;
		letter-spacing: 0.15em;
		color: #c8956c;
		margin-bottom: 0.3rem;
	}
	.card-muse {
		text-transform: none;
		letter-spacing: 0.02em;
		color: rgba(200, 149, 108, 0.4);
		font-style: italic;
	}
	.card-title {
		font-size: 1.1rem;
		font-weight: 500;
		margin-bottom: 0.4rem;
	}
	.card-desc {
		font-size: 0.8rem;
		color: rgba(232, 224, 216, 0.5);
		line-height: 1.5;
	}
	.card-action {
		display: inline-block;
		margin-top: 0.8rem;
		font-size: 0.75rem;
		color: #c8956c;
		text-transform: uppercase;
		letter-spacing: 0.1em;
	}
</style>
