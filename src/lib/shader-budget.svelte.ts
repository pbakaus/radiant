/**
 * Shader progressive-enhancement budget manager.
 *
 * Coordinates preloading (up to 3 concurrent iframes) and live promotion
 * (immediate if FPS budget allows, with continuous monitoring that demotes
 * if performance drops).
 */
import { browser } from '$app/environment';

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

// ── Row prioritization ──────────────────────────────────────────────
let currentPriorityIds = new Set<string>();

export function prioritizeIds(ids: Set<string>) {
	currentPriorityIds = ids;
	// Re-sort existing queues
	preloadQueue.sort((a, b) => {
		return (currentPriorityIds.has(a.id) ? 0 : 1) - (currentPriorityIds.has(b.id) ? 0 : 1);
	});
}

// ── Preload queue (up to MAX_CONCURRENT iframes at once) ─────────────

const MAX_CONCURRENT_PRELOAD = 3;

type PreloadCb = () => void;
interface PreloadEntry { id: string; cb: PreloadCb; }

let preloadQueue: PreloadEntry[] = [];
let preloadActive = new Set<string>();
let processTimer: ReturnType<typeof setTimeout> | null = null;

function processPreloadQueue() {
	while (preloadActive.size < MAX_CONCURRENT_PRELOAD && preloadQueue.length > 0) {
		// Pick a priority item first
		let idx = preloadQueue.findIndex((p) => currentPriorityIds.has(p.id));
		if (idx === -1) idx = 0;
		const [next] = preloadQueue.splice(idx, 1);
		preloadActive.add(next.id);
		next.cb();
	}
}

function scheduleProcess() {
	if (processTimer) return;
	processTimer = setTimeout(() => {
		processTimer = null;
		processPreloadQueue();
	}, 30);
}

export function requestPreload(id: string, cb: PreloadCb, priority = false) {
	cancelPreload(id);
	if (priority) {
		preloadQueue.unshift({ id, cb });
		// Priority (hover) skips debounce
		if (preloadActive.size < MAX_CONCURRENT_PRELOAD) {
			if (processTimer) { clearTimeout(processTimer); processTimer = null; }
			processPreloadQueue();
		}
	} else if (currentPriorityIds.has(id)) {
		const firstNonPriority = preloadQueue.findIndex((p) => !currentPriorityIds.has(p.id));
		if (firstNonPriority === -1) preloadQueue.push({ id, cb });
		else preloadQueue.splice(firstNonPriority, 0, { id, cb });
		scheduleProcess();
	} else {
		preloadQueue.push({ id, cb });
		scheduleProcess();
	}
}

export function preloadDone(id: string) {
	preloadActive.delete(id);
	processPreloadQueue(); // no debounce — fill the slot immediately
}

export function cancelPreload(id: string) {
	preloadQueue = preloadQueue.filter((p) => p.id !== id);
	if (preloadActive.has(id)) {
		preloadActive.delete(id);
		processPreloadQueue();
	}
}

// ── FPS monitor ──────────────────────────────────────────────────────

let fps = 60;
let fpsFrames = 0;
let fpsLast = 0;
let fpsRunning = false;

function startFpsMonitor() {
	if (fpsRunning) return;
	fpsRunning = true;
	fpsLast = performance.now();
	const tick = (now: number) => {
		fpsFrames++;
		if (now - fpsLast >= 1000) {
			fps = fpsFrames;
			fpsFrames = 0;
			fpsLast = now;
			checkBudget();
		}
		requestAnimationFrame(tick);
	};
	requestAnimationFrame(tick);
}

if (browser) startFpsMonitor();

// ── Live promotion ───────────────────────────────────────────────────

interface LiveCallbacks { promote: () => void; demote: () => void; }

// Warm cards waiting for promotion (only used when budget is exhausted)
let warmQueue: { id: string; cbs: LiveCallbacks }[] = [];
// Currently live cards
let liveEntries = new Map<string, LiveCallbacks>();
let maxLive = 50; // reduced if FPS drops

/**
 * Card is warm. Promote immediately if budget allows, otherwise queue.
 */
export function requestLive(id: string, promote: () => void, demote: () => void) {
	releaseLive(id);
	const cbs: LiveCallbacks = { promote, demote };

	if (liveEntries.size < maxLive && fps >= 55) {
		// Budget allows — go live immediately
		liveEntries.set(id, cbs);
		promote();
	} else {
		// Queue for later (budget will promote when FPS is healthy)
		if (currentPriorityIds.has(id)) {
			const firstNonPriority = warmQueue.findIndex((e) => !currentPriorityIds.has(e.id));
			if (firstNonPriority === -1) warmQueue.push({ id, cbs });
			else warmQueue.splice(firstNonPriority, 0, { id, cbs });
		} else {
			warmQueue.push({ id, cbs });
		}
	}
}

export function releaseLive(id: string) {
	warmQueue = warmQueue.filter((e) => e.id !== id);
	liveEntries.delete(id);
}

/**
 * Called every second by the FPS monitor.
 * Promotes from warm queue when healthy, demotes when struggling.
 */
function checkBudget() {
	if (fps < 45 && liveEntries.size > 0) {
		// Emergency: demote the most recent card
		const entries = [...liveEntries.entries()];
		const [lastId, lastCbs] = entries[entries.length - 1];
		liveEntries.delete(lastId);
		lastCbs.demote();
		maxLive = Math.max(0, liveEntries.size);
	} else if (fps >= 58 && warmQueue.length > 0 && liveEntries.size < maxLive) {
		// Headroom available — promote next warm card
		let idx = warmQueue.findIndex((e) => currentPriorityIds.has(e.id));
		if (idx === -1) idx = 0;
		const [entry] = warmQueue.splice(idx, 1);
		liveEntries.set(entry.id, entry.cbs);
		entry.cbs.promote();
	}
}
