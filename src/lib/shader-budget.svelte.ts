/**
 * Shader HTML utilities.
 *
 * Fetches shader HTML, injects pause/resume hooks, and caches results.
 * Exposes a shared `liveMode` toggle for gallery pages.
 */

// ── Live mode (opt-in: render all visible shaders) ───────────────────
let _liveMode = $state(false);
export function getLiveMode() { return _liveMode; }
export function setLiveMode(v: boolean) { _liveMode = v; }

// ── Pause / resume script injected into shader HTML ──────────────────
const PAUSE_SCRIPT = `<script>(function(){
var R=window.requestAnimationFrame.bind(window),P=false,H=[];
window.requestAnimationFrame=function(c){if(P){H.push(c);return -1}return R(c)};
window.__shaderPause=function(){P=true};
window.__shaderResume=function(){if(!P)return;P=false;var a=H;H=[];for(var i=0;i<a.length;i++)R(a[i])};
})();<\/script>`;

export function patchHtml(html: string): string {
	return html.replace(/<head[^>]*>/, '$&\n' + PAUSE_SCRIPT);
}

// ── HTML cache ───────────────────────────────────────────────────────
const htmlCache = new Map<string, string>();

export async function fetchShaderHtml(file: string, id: string): Promise<string> {
	const cached = htmlCache.get(id);
	if (cached) return cached;
	const res = await fetch(`/${file}`);
	const html = patchHtml(await res.text());
	htmlCache.set(id, html);
	return html;
}
