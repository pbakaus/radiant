/**
 * MorphAudio — ambient MP3 playback through a 4-pole VCF with slow LFO.
 *
 * Signal chain:
 *   AudioBufferSourceNode (looped) → LPF1 → LPF2 → GainNode → destination
 *
 * Two cascaded BiquadFilterNodes (lowpass) give 24dB/oct rolloff.
 * Cutoff tracks a composite "sharpness" derived from the visual uniform buffer,
 * modulated by a ~0.08Hz LFO computed in JS each frame.
 */

import {
	U_FOLD_STR, U_SPEC_STR, U_SPEC_POWER,
	U_EDGE_GLOW_STR, U_RIDGE_STR, U_ORB_SHARPNESS
} from './presets';

// ── Filter / LFO constants ──
const CUTOFF_MIN_HZ = 200;
const CUTOFF_MAX_HZ = 8000;
const CUTOFF_RATIO = CUTOFF_MAX_HZ / CUTOFF_MIN_HZ; // 40
const FILTER_Q = 2.0;
const LFO_RATE_HZ = 0.08;
const LFO_DEPTH_OCTAVES = 1.0;
const TWO_PI = Math.PI * 2;
const SMOOTHING_S = 0.016; // ~1 frame exponential smoothing

// ── Volume constants ──
const DEFAULT_VOLUME = 0.35;
const VOLUME_STEP = 0.05;
const VOLUME_MIN = 0.0;
const VOLUME_MAX = 1.0;
const FADE_S = 0.5;

// ── Sharpness weights (sum to 1.0) ──
const W_ORB_SHARPNESS = 0.30;
const W_RIDGE = 0.20;
const W_SPEC = 0.15;
const W_SPEC_POWER = 0.10;
const W_EDGE_GLOW = 0.15;
const W_FOLD = 0.10;
const SPEC_POWER_NORMALIZE = 1 / 80; // spec_power range ~0-80

export class MorphAudio {
	private ctx: AudioContext;
	private buffer: AudioBuffer;
	private source: AudioBufferSourceNode | null = null;
	private lpf1: BiquadFilterNode;
	private lpf2: BiquadFilterNode;
	private gain: GainNode;
	private _started = false;
	private _muted = false;
	private _volume = DEFAULT_VOLUME;

	private constructor(ctx: AudioContext, buffer: AudioBuffer) {
		this.ctx = ctx;
		this.buffer = buffer;

		// Two cascaded lowpass filters = 4-pole (24dB/oct)
		this.lpf1 = ctx.createBiquadFilter();
		this.lpf1.type = 'lowpass';
		this.lpf1.Q.value = FILTER_Q;

		this.lpf2 = ctx.createBiquadFilter();
		this.lpf2.type = 'lowpass';
		this.lpf2.Q.value = FILTER_Q;

		this.gain = ctx.createGain();
		this.gain.gain.value = 0; // Start silent, fade in on start()

		// Wire: [source] → lpf1 → lpf2 → gain → destination
		this.lpf1.connect(this.lpf2);
		this.lpf2.connect(this.gain);
		this.gain.connect(ctx.destination);
	}

	/** Fetch + decode MP3, build audio graph. Does NOT start playback. */
	static async create(url: string): Promise<MorphAudio> {
		const ctx = new AudioContext();
		// Keep suspended until user gesture triggers start()
		if (ctx.state === 'running') await ctx.suspend();

		const resp = await fetch(url);
		const arrayBuf = await resp.arrayBuffer();
		const audioBuffer = await ctx.decodeAudioData(arrayBuf);

		return new MorphAudio(ctx, audioBuffer);
	}

	/** Resume context + start looped playback with fade-in. Idempotent. */
	async start(): Promise<void> {
		if (this._started) return;
		this._started = true;

		await this.ctx.resume();

		this.source = this.ctx.createBufferSource();
		this.source.buffer = this.buffer;
		this.source.loop = true;
		this.source.connect(this.lpf1);
		this.source.start();

		// Gentle fade-in
		const now = this.ctx.currentTime;
		this.gain.gain.setValueAtTime(0, now);
		this.gain.gain.linearRampToValueAtTime(this._volume, now + FADE_S);
		this._muted = false;
	}

	/**
	 * Called every frame from tick(). Reads sharpness uniforms from the GPU
	 * uniform buffer, computes filter cutoff with LFO modulation.
	 * Pure math — zero allocations.
	 */
	update(buf: Float32Array): void {
		if (!this._started || this._muted) return;

		// Composite sharpness: 0 (soft/blurry) → 1 (sharp/detailed)
		const sharpness =
			W_ORB_SHARPNESS * buf[U_ORB_SHARPNESS] +
			W_RIDGE * buf[U_RIDGE_STR] +
			W_SPEC * buf[U_SPEC_STR] +
			W_SPEC_POWER * buf[U_SPEC_POWER] * SPEC_POWER_NORMALIZE +
			W_EDGE_GLOW * buf[U_EDGE_GLOW_STR] +
			W_FOLD * buf[U_FOLD_STR];

		// Exponential mapping: sharpness 0→200Hz, 1→8000Hz
		const baseCutoff = CUTOFF_MIN_HZ * Math.pow(CUTOFF_RATIO, sharpness);

		// LFO: slow sine modulation ±1 octave
		const lfoPhase = performance.now() * 0.001 * LFO_RATE_HZ * TWO_PI;
		const lfoValue = Math.sin(lfoPhase);
		const cutoff = baseCutoff * Math.pow(2, lfoValue * LFO_DEPTH_OCTAVES);

		// Apply to both filter stages with exponential smoothing
		const t = this.ctx.currentTime;
		this.lpf1.frequency.setTargetAtTime(cutoff, t, SMOOTHING_S);
		this.lpf2.frequency.setTargetAtTime(cutoff, t, SMOOTHING_S);
	}

	/** Toggle mute with crossfade. Returns true if now playing. */
	toggle(): boolean {
		if (!this._started) return false;
		const now = this.ctx.currentTime;
		if (this._muted) {
			this.gain.gain.setValueAtTime(this.gain.gain.value, now);
			this.gain.gain.linearRampToValueAtTime(this._volume, now + FADE_S);
			this._muted = false;
		} else {
			this.gain.gain.setValueAtTime(this.gain.gain.value, now);
			this.gain.gain.linearRampToValueAtTime(0, now + FADE_S);
			this._muted = true;
		}
		return !this._muted;
	}

	/** Adjust volume by delta (clamped). Applies immediately if not muted. */
	adjustVolume(delta: number): number {
		this._volume = Math.max(VOLUME_MIN, Math.min(VOLUME_MAX, this._volume + delta));
		if (this._started && !this._muted) {
			const now = this.ctx.currentTime;
			this.gain.gain.setValueAtTime(this.gain.gain.value, now);
			this.gain.gain.linearRampToValueAtTime(this._volume, now + 0.05);
		}
		return this._volume;
	}

	volumeUp(): number { return this.adjustVolume(VOLUME_STEP); }
	volumeDown(): number { return this.adjustVolume(-VOLUME_STEP); }

	get isPlaying(): boolean { return this._started && !this._muted; }
	get volume(): number { return this._volume; }

	destroy(): void {
		this.source?.stop();
		this.source?.disconnect();
		this.lpf1.disconnect();
		this.lpf2.disconnect();
		this.gain.disconnect();
		this.ctx.close();
	}
}
