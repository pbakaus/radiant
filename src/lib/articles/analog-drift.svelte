<script lang="ts">
	import type { Shader } from '$lib/shaders';
	import { articleMeta } from '$lib/articles';
	import ArticleShell from '$lib/components/article/ArticleShell.svelte';
	import Sandbox from '$lib/components/article/Sandbox.svelte';
	import Code from '$lib/components/article/Code.svelte';
	import Aside from '$lib/components/article/Aside.svelte';
	import LissajousMath from '$lib/components/article/LissajousMath.svelte';

	let { shader }: { shader: Shader } = $props();
	const meta = articleMeta['analog-drift'];

	const lissajousCode = `// One frame's worth of curve. Two sines, orthogonal axes.
const N = 3000;
const coverage = 2 * Math.PI * Math.max(Math.ceil(a), Math.ceil(b));
const step = coverage / N;

ctx.beginPath();
for (let i = 0; i <= N; i++) {
  const t = i * step;
  const x = cx + Math.sin(a * t + delta) * size;
  const y = cy + Math.sin(b * t) * size;
  if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
}
ctx.stroke();`;

	const phosphorCode = `// Instead of clearing the canvas, draw black at low alpha over it.
// Every old pixel decays exponentially: brightness *= (1 − fadeAlpha)
// per frame. Smaller alpha = longer phosphor persistence.
const fadeAlpha = 0.025 * TRAIL_LENGTH;
ctx.fillStyle = \`rgba(10, 10, 10, \${fadeAlpha})\`;
ctx.fillRect(0, 0, W, H);

// Then draw this frame's curve on top. Each frame's stroke is the
// brightest layer; older frames recede toward black.
drawCurve(a, b, delta);`;

	const thicknessCode = `// Pre-compute all (x, y) into typed-array buffers, once per frame.
for (let i = 0; i <= N; i++) {
  const t = i * step;
  ptX[i] = cx + Math.sin(a * t + delta) * size;
  ptY[i] = cy + Math.sin(b * t) * size;
}

// Then stroke in batches of 20 points, with one thickness per batch
// sampled from the segment speed at the batch's midpoint.
const batch = 20;
for (let i = 0; i < N; i += batch) {
  const end = Math.min(i + batch, N);
  const mid = Math.min(i + (batch >> 1), N - 1);
  const dx = ptX[mid + 1] - ptX[mid];
  const dy = ptY[mid + 1] - ptY[mid];
  const speed = Math.sqrt(dx * dx + dy * dy);

  // The inverse-speed formula: thicker where the curve lingers.
  let mult = 1.0 / (1.0 + speed * 0.25);
  mult = 0.6 + mult * 1.2;
  ctx.lineWidth = BASE * mult;

  ctx.beginPath();
  ctx.moveTo(ptX[i], ptY[i]);
  for (let j = i + 1; j <= end; j++) ctx.lineTo(ptX[j], ptY[j]);
  ctx.stroke();
}`;

	const driftCode = `// 10 waypoints in (a, b, δ) space. Each one is a closed or
// near-closed Lissajous figure chosen by eye.
const waypoints = [
  { a: 1, b: 1, delta: Math.PI / 2 },   // circle
  { a: 1, b: 2, delta: 0 },              // figure-8
  { a: 2, b: 3, delta: Math.PI / 4 },    // trefoil
  { a: 3, b: 4, delta: Math.PI / 6 },    // rose-like
  // …six more
];

function easeCubic(x) {
  return x < 0.5 ? 4*x*x*x : 1 - Math.pow(-2*x + 2, 3) / 2;
}

function getParams(t) {
  const n = waypoints.length;
  const pos = (t % n + n) % n;
  const idx = Math.floor(pos);
  let frac = pos - idx;
  frac = easeCubic(frac);            // <-- the analog feel
  const from = waypoints[idx];
  const to   = waypoints[(idx + 1) % n];
  return {
    a:     from.a     + (to.a     - from.a)     * frac,
    b:     from.b     + (to.b     - from.b)     * frac,
    delta: from.delta + (to.delta - from.delta) * frac
  };
}`;

	const harmonicsCode = `// Sub-harmonic (drawn first, behind everything else)
drawCurve(a * 0.5, b * 0.5, delta * 0.7 - time * 0.05, 0.42,
  'rgba(180, 130, 90, 1)', 0.18, 0.6);

// 3rd harmonic
drawCurve(a * 3, b * 2, delta * 1.5 + time * 0.08, 0.32,
  'rgba(200, 149, 108, 1)', 0.20, 0.7);

// 2nd harmonic
drawCurve(a * 2, b * 2, delta + time * 0.15, 0.34,
  'rgba(200, 149, 108, 1)', 0.28, 0.9);

// Main trace (drawn last, brightest, on top)
drawCurve(a, b, delta, 0.38, 'rgba(220, 180, 130, 1)', 0.85, 1.5);`;
</script>

<ArticleShell
	{shader}
	title={meta.title}
	subtitle={meta.subtitle}
	author={meta.author}
	readingTime={meta.readingTime}
>
	<p>
		Two sines, plotted against each other on a 2D canvas. Don't clear the canvas between frames.
		That's the whole effect. Everything else is decoration on top of those two facts.
	</p>

	<p>
		The shape comes from <strong>Lissajous figures</strong>, the curve you get when you feed one
		oscillating waveform into the X deflection of a cathode-ray tube and another into the Y. The
		glow comes from <strong>phosphor persistence</strong>, the property that made CRT screens look
		analog: the screen keeps emitting light for a moment after the beam moves on. We fake both.
	</p>

	<Aside type="note" title="Why bother?">
		{#snippet children()}
			<p>
				The Radiant <a href="/shader/analog-drift">Analog Drift</a> shader looks like an
				oscilloscope readout from a piece of audio gear. The technique generalizes to any
				phosphor-trail effect: route planners, time-series scrubbers, audio visualizers, the
				HUD of a fictional spaceship. Two functions, one buffer.
			</p>
		{/snippet}
	</Aside>

	<h2 id="lissajous">A.k.a. Lissajous</h2>

	<p>
		Named for Jules Antoine Lissajous, who studied them in the 1850s by reflecting light off
		mirrors attached to tuning forks. The parametric form is two sines:
	</p>

	<p class="equation">
		<code>x(t) = sin(a·t + δ)</code>
		<br />
		<code>y(t) = sin(b·t)</code>
	</p>

	<p>
		Three parameters. <code>a</code> is how often the X coordinate cycles per unit of <code>t</code>;
		<code>b</code> is the same for Y; <code>δ</code> is the phase offset between them. Plug those
		into a 2D plot and step <code>t</code> from 0 to 2π·max(a, b) to draw a full loop. Drag the
		knobs below to feel it.
	</p>

	<LissajousMath caption="Three sliders, one equation. Integer ratios (1:1, 2:3, 3:5) produce closed curves; non-integer ratios produce dense fills that never close." />

	<p>
		The ratio <code>a:b</code> determines the figure's shape. 1:1 with δ = π/2 is a circle; 1:1
		with δ = 0 is a diagonal line. 1:2 is a figure-8. 2:3 is a trefoil. The numerator counts X
		loops per period, the denominator counts Y loops. As the integers grow, the figure gets
		denser. Irrational ratios fill the box uniformly and never quite close, which is its own
		visual signature.
	</p>

	<p>
		The phase δ controls how the two oscillations line up. Slide it from 0 to π/2 on a 1:2 figure
		and you see the figure-8 dissolve into a parabola, then into a tilted figure-8 on the other
		side. The shape is alive in three dimensions of parameter space.
	</p>

	<Code code={lissajousCode} lang="js" caption="One frame's drawing. 3000 points along the parameter range, one beginPath, one stroke. Canvas 2D handles the rest." />

	<Sandbox
		src="/learn/analog-drift/01-one-lissajous.html"
		title="Step 01 — one Lissajous"
		caption="A single Lissajous curve, hard-cleared every frame. No phosphor, no thickness modulation, no drift. Slide a and b through small integers to feel the closed-curve family."
		aspect="16/9"
		params={[
			{ name: 'A', label: 'a (x frequency)', min: 1, max: 6, step: 1, default: 1 },
			{ name: 'B', label: 'b (y frequency)', min: 1, max: 6, step: 1, default: 2 },
			{ name: 'DELTA', label: 'δ (phase)', min: 0, max: Math.PI, step: 0.05, default: Math.PI / 2 }
		]}
	/>

	<h2 id="phosphor">Phosphor persistence</h2>

	<p>
		A static Lissajous is a math plot. The CRT look is what you get when you stop clearing the
		canvas between frames. Instead of <code>ctx.clearRect</code> or <code>fillRect(black)</code>
		at full opacity, draw black at <em>low</em> alpha. Each old pixel decays toward black a
		little per frame; new pixels arrive at full brightness. Older parts of the trace fade away
		while the leading edge stays bright.
	</p>

	<p>
		The math is straight exponential decay. If you blend a frame against a black overlay with
		alpha <code>α</code>, the pixel value after <code>n</code> frames is
		<code>v · (1 − α)^n</code>. At α = 0.025, after 60 frames a pixel is at
		<code>(0.975)^60 ≈ 0.22</code> of its initial brightness, so the trail is visible for about a
		second before fading below perceptible. Crank α to 1 and you get a hard clear (no trail at
		all). Crank it to 0 and pixels never fade (the screen burns in).
	</p>

	<Code code={phosphorCode} lang="js" caption="The whole phosphor-persistence trick. Three lines of meaningful code." />

	<Sandbox
		src="/learn/analog-drift/02-phosphor-trail.html"
		title="Step 02 — phosphor trail"
		caption="The toggle switches between hard clear (no memory) and phosphor fade (exponential decay). Watch what happens to the same animating curve when you flip it."
		aspect="16/9"
		params={[
			{ name: 'FADE', label: 'Fade alpha', min: 0.005, max: 0.1, step: 0.005, default: 0.025 },
			{ name: 'SPEED', label: 'Phase speed', min: 0.1, max: 3.0, step: 0.05, default: 1.0 }
		]}
		toggle={{ name: 'PHOSPHOR', label: 'Phosphor persistence', onValue: 1, offValue: 0, default: true }}
	/>

	<p>
		There's no real physics here: a real CRT phosphor has a non-exponential decay curve with a
		fast initial component and a long tail. The exponential we use is close enough that nobody
		notices. The visual signature lives in two things: that the trail fades smoothly to black, and
		that the leading edge of the trace is always the brightest pixel on screen. Both come free
		with one <code>fillRect</code>.
	</p>

	<h2 id="thickness">Velocity tells brightness</h2>

	<p>
		Watch a real oscilloscope. The trace is brighter where the curve loops back on itself and
		dimmer where it sweeps across long distances quickly. The reason is physical: the electron
		beam moves at constant angular speed but the trace it draws goes faster through some regions
		than others, and pixel brightness depends on how long the beam dwells per pixel. Slow regions
		accumulate more photons.
	</p>

	<p>
		The shortcut: sample the segment speed periodically and scale the line width inversely. Where
		the curve moves slowly between consecutive points, the stroke is fat. Where it sprints, thin.
		One formula:
	</p>

	<p class="equation">
		<code>thickness = base · (0.6 + 1.2 / (1 + speed · 0.25))</code>
	</p>

	<p>
		Tuning is empirical. The 0.6 floor keeps fast regions from disappearing entirely. The 1.2
		multiplier sets how much variation you get. The 0.25 scale on speed sets the speed at which
		the falloff kicks in. None of these are derivable; you find them by sliding numbers until the
		trace looks right.
	</p>

	<Code code={thicknessCode} lang="js" caption="Compute all points into typed arrays first, then stroke them in batches of 20 with one thickness per batch. Batching keeps Canvas 2D's draw count manageable; without it, calling lineWidth per segment would be ~150× more expensive." />

	<Sandbox
		src="/learn/analog-drift/03-velocity-thickness.html"
		title="Step 03 — velocity thickness"
		caption="Same 3:2 figure either way. Toggle modulation on and watch the slow lobes get fat while the fast sweeps stay thin. The strength slider exaggerates or softens the effect."
		aspect="16/9"
		params={[
			{ name: 'STRENGTH', label: 'Modulation strength', min: 0.0, max: 1.0, step: 0.02, default: 0.25 }
		]}
		toggle={{ name: 'MODULATE', label: 'Velocity-modulated thickness', onValue: 1, offValue: 0, default: true }}
	/>

	<p>
		With modulation off, the trace looks like a CSS border drawn around an SVG shape: technically
		correct, visually flat. With modulation on, the figure suddenly has weight. The same 3000
		points, the same colors, the same phosphor fade. The only difference is that the renderer now
		respects how long the beam spent at each location.
	</p>

	<h2 id="drift">Drifting through parameter space</h2>

	<p>
		A frozen Lissajous figure is a math demo. The full Analog Drift effect comes from slowly
		animating <code>(a, b, δ)</code> through a sequence of curated waypoints, so the trace
		morphs between known-nice figures over a span of tens of seconds. The phosphor persistence
		makes the transitions visible: old waypoints are still glowing while the new one draws itself
		on top.
	</p>

	<p>
		Picking waypoints is curation, not math. Ten figures, hand-chosen: a circle, a figure-8, a
		trefoil, a few rose-like ones, then back to a diagonal line that almost dissolves to nothing
		before the loop restarts. Random parameter sweeps look chaotic; a curated tour reads as
		intentional.
	</p>

	<p>
		The interpolation matters too. Linear interpolation between waypoints feels mechanical: it
		moves at the same speed through the whole transition, arriving at the new waypoint at the
		same velocity it left the old one. <strong>Ease-in-out cubic</strong> is what sells the analog
		feeling: slow at both ends of the transition, fastest in the middle. The same curve a
		mechanical control knob would make if you turned it smoothly without overshooting.
	</p>

	<Code code={driftCode} lang="js" caption="Waypoint storage, easing curve, and interpolation. The ease-in-out cubic is the one place where the choice of math directly affects how 'analog' the result feels." />

	<Sandbox
		src="/learn/analog-drift/04-drift.html"
		title="Step 04 — waypoint drift"
		caption="The figure drifts through ten waypoints on a loop. Toggle easing off and the transitions feel like a software animation; turn it back on and it feels like a knob being turned by hand. The readout in the top-right shows live (a, b, δ)."
		aspect="16/9"
		params={[
			{ name: 'SPEED', label: 'Drift speed', min: 0.1, max: 3.0, step: 0.05, default: 1.0 }
		]}
		toggle={{ name: 'EASING', label: 'Ease-in-out cubic', onValue: 1, offValue: 0, default: true }}
	/>

	<h2 id="harmonics">Harmonic overtones</h2>

	<p>
		One more layer. Stack three additional Lissajous curves behind the main one, each at a
		multiple of the base frequencies. The 2× harmonic <code>(2a, 2b)</code> is denser and tighter,
		drawn at about 30% alpha. The 3× harmonic <code>(3a, 2b)</code> is denser still, dimmer. A
		sub-harmonic <code>(a/2, b/2)</code> goes the other way: larger, slower, even dimmer, drifting
		behind everything.
	</p>

	<p>
		All four curves share the same drift waypoints, so they morph together. The harmonics
		multiply or halve the frequencies, but they're locked to the same δ progression. The visual
		effect is that the figure looks <em>fuller</em> without looking busy, the same way an audio
		signal with harmonic overtones sounds richer than a pure sine wave at the same fundamental.
	</p>

	<Code code={harmonicsCode} lang="js" caption="Layer order matters: draw back-to-front, so the brightest layer ends up on top. Each harmonic gets its own alpha, thickness, and time-shift, so they don't all phase-lock into one congealed shape." />

	<Sandbox
		src="/learn/analog-drift/05-harmonics.html"
		title="Step 05 — harmonics"
		caption="A held 2:3 figure with the three harmonic layers toggleable. Turn them off one at a time. The 2nd is the most visually impactful; the sub-harmonic is the most felt-but-not-seen."
		aspect="16/9"
		toggle={{ name: 'H2', label: '2× harmonic', onValue: 1, offValue: 0, default: true }}
	/>

	<p>
		The harmonics aren't a single toggle in the production shader; each is configurable
		independently. Together they account for maybe 5% of the visible image but 30% of the
		impression that the signal is rich, not synthetic.
	</p>

	<h2 id="final">Everything together</h2>

	<p>
		Add a faint oscilloscope grid behind the trace (subtle, breathing). Add a Gaussian-bloom layer
		under the main curve using <code>shadowBlur</code> for CRT phosphor glow. Add an offset cyan
		shimmer trace at <code>δ + 0.01</code> over the amber base for a hint of chromatic
		aberration. Add 40 brightly-cored phosphor dots distributed along the curve, pulsing
		independently of the trace. None of those is essential. All of them are easy.
	</p>

	<Sandbox
		src="/learn/analog-drift/06-final.html"
		title="Step 06 — all together"
		caption="The full effect: waypoint drift, phosphor fade, velocity thickness, harmonics, bloom, cyan accent, dot phosphors, grid. Drift speed and trail length are exposed; everything else is hard-coded to taste."
		aspect="16/9"
		params={[
			{ name: 'DRIFT_SPEED', label: 'Drift speed', min: 0.1, max: 2.0, step: 0.05, default: 0.5 },
			{ name: 'TRAIL_LENGTH', label: 'Trail length', min: 0.3, max: 2.0, step: 0.05, default: 1.0 }
		]}
	/>

	<h2 id="performance">Why this is fast</h2>

	<p>
		Four curves of 3000 points each, redrawn 60 times per second, is 720K points per second
		through Canvas 2D. None of it is intuitively cheap.
	</p>

	<p>
		<strong>Pre-allocated typed arrays.</strong> Point coordinates go into two <code>Float64Array(4001)</code>
		buffers allocated once at startup. No per-frame garbage. The browser's GC never sees this
		hot loop.
	</p>

	<p>
		<strong>Batched strokes per thickness.</strong> Naive line-width-per-segment would call
		<code>beginPath</code>, <code>stroke</code>, and a state-change 3000 times per curve. Sampling
		one thickness per 20-point batch is 150 strokes per curve, with the path itself still drawn
		as one continuous <code>moveTo</code>/<code>lineTo</code> sequence per batch.
	</p>

	<p>
		<strong>Bloom only where it pays.</strong> <code>shadowBlur</code> is one of Canvas 2D's most
		expensive operations: it forces a software pass for the entire stroke. We apply it only to
		the main trace and the cyan accent (the two layers the eye lingers on), and skip it entirely
		on the three harmonics.
	</p>

	<p>
		The whole shader holds 60fps on a 2019 laptop with the dev tools open. The bottleneck isn't
		math or memory; it's how many times we ask Canvas 2D to flush its state.
	</p>

	<h2 id="where-to-go">Where to go from here</h2>

	<p>
		Lissajous on
		<a href="https://en.wikipedia.org/wiki/Lissajous_curve" target="_blank" rel="noopener noreferrer">Wikipedia</a>
		covers the math thoroughly, including the closed-curve conditions and the rational/irrational
		distinction. <a href="https://mathworld.wolfram.com/LissajousCurve.html" target="_blank" rel="noopener noreferrer">MathWorld</a>
		has a more compact treatment with the parametric forms.
	</p>

	<p>
		If you want a deeper rabbit hole, the underlying technique generalizes to any 2D parametric
		curve. Replace the sines with rose curves <code>r = cos(k·θ)</code>, with epicycloids, with
		audio waveforms sampled in real time. The phosphor-fade-plus-velocity-thickness rendering
		layer is independent of what's being plotted. Feed it any function; it'll look like that
		function as seen through an oscilloscope.
	</p>

	<p>
		The whole analog-drift shader is 434 lines of HTML. Roughly half is the curve math and
		harmonics. A third is the rendering setup. The rest is parameter wiring and the bit of
		oscilloscope chrome that sells the illusion. Drop it on any page; it has no dependencies.
	</p>
</ArticleShell>

<style>
	.equation {
		font-family: 'SF Mono', monospace;
		font-size: 0.95em;
		text-align: center;
		padding: 0.8rem 0;
		color: rgba(232, 224, 216, 0.85);
	}
	.equation code {
		background: none;
		padding: 0;
		font-size: inherit;
	}
</style>
