<script lang="ts">
	import type { Shader } from '$lib/shaders';
	import { articleMeta } from '$lib/articles';
	import ArticleShell from '$lib/components/article/ArticleShell.svelte';
	import Sandbox from '$lib/components/article/Sandbox.svelte';
	import Code from '$lib/components/article/Code.svelte';
	import Aside from '$lib/components/article/Aside.svelte';
	import Math from '$lib/components/article/Math.svelte';
	import Blackbody from '$lib/components/article/Blackbody.svelte';
	import TemperaturePlot from '$lib/components/article/TemperaturePlot.svelte';
	import Compare from '$lib/components/article/Compare.svelte';

	let { shader }: { shader: Shader } = $props();
	const meta = articleMeta['event-horizon'];

	// ─── Code excerpts ────────────────────────────────────────────
	const geodesicCode = `// Schwarzschild geodesic step (in fragment shader)
// d²x/dλ² = -1.5 · RS · L² / r⁵ · x   where L = |x × v|
vec3 Lvec = cross(pos, vel);
float L2 = dot(Lvec, Lvec);
float gravCoeff = -1.5 * RS * L2;

for (int i = 0; i < 200; i++) {
  float r = length(pos);
  float h = 0.16 * clamp(r - 0.4 * RS, 0.06, 3.5);  // adaptive step

  // a(x) = gravCoeff / r⁵ · x
  float invR5 = 1.0 / (r*r*r*r*r);
  vec3 acc  = (gravCoeff * invR5) * pos;

  // Velocity-Verlet — symplectic, conserves energy
  vec3 p1 = pos + vel * h + 0.5 * acc * h * h;
  float invR15 = 1.0 / pow(length(p1), 5.0);
  vec3 acc1 = (gravCoeff * invR15) * p1;
  vec3 v1 = vel + 0.5 * (acc + acc1) * h;

  if (length(p1) < RS * 0.35) { absorbed = true; break; }
  pos = p1; vel = v1;
}`;

	const noviCode = `// Novikov-Thorne temperature profile (1973)
// T(r) ∝ r^(-3/4) · (1 − √(r_isco / r))^(1/4)
float xr = ISCO / r;
float tProfile = pow(ISCO / r, 0.75)
               * pow(max(0.001, 1.0 - sqrt(xr)), 0.25);

// Gravitational redshift: light from deep in the well loses energy
float gRedshift = sqrt(max(0.01, 1.0 - RS / r));
tProfile *= gRedshift;

vec3 col = blackbodyColor(tProfile);`;

	const dopplerCode = `// Doppler beaming from Keplerian orbital motion.
// orbDir is tangent to the orbit at this point on the disk.
float orbSpeed = sqrt(0.5 * RS / max(r, DISK_IN));
vec3  orbDir   = normalize(vec3(-hit.z, 0.0, hit.x));

float dop = 1.0 + 2.0 * dot(normalize(vel), orbDir) * orbSpeed;
dop = max(0.15, dop);

// Brightness scales as Doppler^3 (relativistic beaming).
// Frequency shifts blue-ward on approach, red on retreat.
float boost     = dop * dop * dop;
float colorTemp = tProfile * pow(dop, 1.8) * 1.2;
vec3  col       = blackbodyColor(colorTemp) * intensity * boost;`;

	const crossingCode = `// A ray can cross the y=0 disk plane MULTIPLE times after lensing.
// Crossing 1: the disk in front of the hole.
// Crossing 2: the back of the disk, wrapped over the top.
// Crossing 3+: the photon ring — light orbiting near r=1.5·RS.
if (pos.y * p1.y < 0.0 && diskAccum.a < 0.97) {
  float t = pos.y / (pos.y - p1.y);
  vec3 hit = mix(pos, p1, t);
  vec4 dc = shadeDisk(hit, vel, time);

  // Crisp 1px photon ring would alias horribly; attenuate later passes.
  if (diskCrossings >= 2) { dc.rgb *= 0.15; dc.a *= 0.15; }

  // Alpha-over compositing (front-to-back).
  diskAccum.rgb += dc.rgb * dc.a * (1.0 - diskAccum.a);
  diskAccum.a   += dc.a * (1.0 - diskAccum.a);
  diskCrossings++;
}`;
</script>

<ArticleShell
	{shader}
	title={meta.title}
	subtitle={meta.subtitle}
	author={meta.author}
	readingTime={meta.readingTime}
>
	<p>
		The image in the header is not a texture, a video, or a 3D model. It's the output of a fragment
		shader that takes every pixel on the screen, shoots an imaginary photon backwards into the
		scene, and asks: <em>where would this photon have come from if light were bending around a one
		solar mass of curvature here?</em>
	</p>

	<p>
		That's a lot of work for one pixel. We do it sixty times a second, for two million pixels at
		once, on a laptop GPU, with no precomputed lookup tables.
	</p>

	<p>You can poke every step. Drag inside any sandbox to look around.</p>

	<Aside type="tip" title="How to read this">
		{#snippet children()}
			<p>
				Each section adds <em>one</em> piece of physics on top of the previous one. The sandboxes
				are real partial shaders, not the final one with features toggled off. If something
				doesn't make sense in the prose, scrub the slider until it does.
			</p>
		{/snippet}
	</Aside>

	<h2 id="straight-rays">Starting from nothing: straight rays</h2>

	<p>
		Before we add a black hole, here's the baseline. Each pixel shoots a ray into space. The ray
		goes in a straight line. It samples a procedural starfield: bright sparse stars, a denser
		field underneath, and a faint nebula on top of that. No physics, just trigonometry and a
		hash function.
	</p>

	<Sandbox
		src="/learn/event-horizon/01-rays.html"
		title="Step 01 — straight rays through space"
		caption="Drag inside the frame to look around. The camera orbits at a fixed distance; rays go in straight lines. This is the canvas we'll start bending."
		aspect="16/8"
		params={[
			{ name: 'ROTATE_SPEED', label: 'Auto rotate', min: 0, max: 1, step: 0.05, default: 0.5 },
			{ name: 'NEBULA', label: 'Nebula strength', min: 0, max: 1.5, step: 0.05, default: 1.0 }
		]}
	/>

	<p>
		Now we curve those rays. From here on, everything we add is just a question of <em>what the
		ray hits along the way</em>.
	</p>

	<h2 id="gravity">Gravity, by itself</h2>

	<p>
		Massive objects curve spacetime. Light follows the shortest path through that curvature, called
		a <strong>geodesic</strong>. Far from a mass, geodesics look like straight lines. Close to a
		mass, they bend. Close enough to a black hole, they wrap.
	</p>

	<p>
		Before any of that becomes a fragment shader, it helps to see geodesics in a flat top-down
		view. Each line in the playground is a photon launched from the left edge, aimed straight to
		the right. Without gravity, they'd all be parallel. With gravity, the ones that pass closer to
		the central mass curve inward. The closest ones are captured.
	</p>

	<Sandbox
		src="/learn/event-horizon/geodesic-2d.html"
		title="2D geodesic playground"
		caption="Top-down view. Click and drag anywhere in the frame to launch your own ray. White rays escape, red rays fell past the photon sphere and were absorbed. The dashed circle at r = 1.5·RS is the photon sphere: light entering tangent to it can briefly orbit before deciding which way to go."
		aspect="16/9"
		params={[
			{ name: 'MASS', label: 'Mass (RS)', min: 0.2, max: 2.0, step: 0.05, default: 1.0 }
		]}
	/>

	<p>
		The bend angle is set almost entirely by the <em>impact parameter</em> (how close the ray came
		to the mass), not by where the ray started. And the transition between escape and capture is
		sharp: rays just outside the photon sphere swerve and escape, rays just inside it spiral in.
		That cliff is what creates the hard black silhouette around a real black hole.
	</p>

	<h3 id="the-equation">The equation we'll integrate</h3>

	<p>
		For a Schwarzschild (non-rotating, uncharged) black hole, a photon's spatial trajectory obeys
	</p>

	<Math display>
		{#snippet children()}d²x / dλ² = −(3/2) · RS · L² / r⁵ · x{/snippet}
	</Math>

	<p>
		where <Math>{#snippet children()}x{/snippet}</Math> is the photon's position relative to the
		hole, <Math>{#snippet children()}r = |x|{/snippet}</Math>, <Math>{#snippet children()}RS{/snippet}</Math>
		is the Schwarzschild radius (the event horizon), and
		<Math>{#snippet children()}L = |x × v|{/snippet}</Math> is the angular momentum. L is conserved
		along the geodesic, so we compute it once.
	</p>

	<p>
		In code, we integrate this with <strong>velocity-Verlet</strong>: a symplectic, energy-conserving
		integrator that lets us take big steps far from the hole and small ones near it without the
		trajectory blowing up.
	</p>

	<Code code={geodesicCode} lang="glsl" caption="The whole gravitational physics, inside a per-pixel loop. The trick that makes this real-time is the adaptive step size on line 4. Far away we coast, close in we sample finely." />

	<p>
		Replace the straight ray from Step 01 with this loop and you get gravitational lensing for
		free. No disk yet, just stars seen through curved spacetime.
	</p>

	<Sandbox
		src="/learn/event-horizon/02-bending.html"
		title="Step 02 — bending light"
		caption="Same starfield as Step 01, but each ray now follows the Schwarzschild geodesic. Crank the mass up: stars near the silhouette stretch and a faint Einstein ring of duplicated stars forms around the rim. The grid toggle shows the geometry without speckle noise."
		aspect="16/8"
		params={[
			{ name: 'ROTATE_SPEED', label: 'Auto rotate', min: 0, max: 1, step: 0.05, default: 0.3 },
			{ name: 'MASS', label: 'Mass (RS)', min: 0.3, max: 2.0, step: 0.05, default: 1.0 },
			{ name: 'STEPS', label: 'Integration steps', min: 30, max: 200, step: 5, default: 200 }
		]}
		toggle={{ name: 'SHOW_GRID', label: 'Show background grid', default: false }}
	/>

	<p>
		Pull the step count down to 30 and you'll see the integration break: light begins to wobble and
		stars near the rim shimmer as the integrator skips important geometry. 200 steps is what we
		use in production. Adaptive step size means it only pays that cost near the hole, and most
		rays terminate in 20 or 30 iterations anyway.
	</p>

	<Aside type="definition" title="Schwarzschild radius">
		{#snippet children()}
			<p>
				<Math>{#snippet children()}RS = 2GM / c²{/snippet}</Math>. For our Sun: 3 km. For Sagittarius
				A*: 12 million km. For the entire observable universe: about 14 billion light years
				(coincidence?). In this shader we set <code>RS = 1.0</code> as the scene's natural unit and
				measure everything else in those units.
			</p>
		{/snippet}
	</Aside>

	<h2 id="the-disk">A disk of glowing plasma</h2>

	<p>
		Real black holes aren't lit. They're black. What we see in famous images, and what we'll
		render here, is the <strong>accretion disk</strong>: a thin layer of plasma spiralling inward,
		heated by friction, glowing in the X-ray and visible band before it falls past the event horizon.
	</p>

	<p>
		The temperature isn't uniform. Plasma orbiting closer to the hole is moving faster, has lost
		more potential energy, and radiates more brightly. Novikov and Thorne worked out the radial
		profile in 1973:
	</p>

	<Math display>
		{#snippet children()}T(r) ∝ r^(−3/4) · (1 − √(r_isco / r))^(1/4){/snippet}
	</Math>

	<p>
		The <Math>{#snippet children()}r_isco{/snippet}</Math> is the <strong>innermost stable circular
		orbit</strong>. Inside it, plasma can't hold an orbit and plunges straight into the hole. For
		a non-spinning Schwarzschild hole, <Math>{#snippet children()}r_isco = 3·RS{/snippet}</Math>.
		Plasma at exactly the ISCO has zero temperature (the second factor goes to zero); the disk
		peaks slightly outside it and falls off as <Math>{#snippet children()}r^(−3/4){/snippet}</Math>
		going out.
	</p>

	<TemperaturePlot
		caption="Disk temperature vs. radius for the Novikov-Thorne profile. The fill is graded with the actual blackbody color we map each temperature to. Move the ISCO slider and the whole disk dims and shifts outward as the inner edge moves out."
	/>

	<p>
		Temperature is then mapped to color through a blackbody approximation. Hot things glow blue,
		moderate things glow white, cold things glow red. The shader doesn't compute Planck's law from
		first principles. That would be expensive and wrong-looking under tone mapping anyway, so
		instead it uses a hand-fit four-color gradient that lines up with the real curve in the
		visible range.
	</p>

	<Blackbody caption="Scrub the slider to see what color a given effective temperature becomes after the shader's tone mapping. Around T ≈ 0.3 it's deep red; at T ≈ 0.8 it's white; past 1.0 it shifts cool-blue." />

	<p>
		The full disk shader combines the temperature profile with a few extra layers: FBM turbulence
		oriented along Keplerian streamlines (so it flows correctly), concentric ring modulation for
		visible structure, and a soft inner/outer fade. Here's the temperature half on its own,
		<em>without any gravitational lensing yet</em>:
	</p>

	<Code code={noviCode} lang="glsl" caption="Inside the disk shading function: temperature profile and blackbody color. The redshift factor sqrt(1 − RS/r) on line 6 is the same redshift you'd compute for any light source in a gravitational well." />

	<Sandbox
		src="/learn/event-horizon/03-disk-flat.html"
		title="Step 03 — the disk by itself (no lensing)"
		caption="Top-down view of just the accretion disk. No gravitational bending, no perspective tricks. You're looking straight down at the equatorial plane. Move the ISCO slider to watch the inner edge migrate and the brightness peak shift outward."
		aspect="16/9"
		params={[
			{ name: 'ISCO', label: 'ISCO radius', min: 2.0, max: 6.0, step: 0.05, default: 3.0 },
			{ name: 'INNER', label: 'Inner glow edge', min: 1.5, max: 4.0, step: 0.05, default: 2.2 },
			{ name: 'OUTER', label: 'Outer edge', min: 8, max: 22, step: 0.5, default: 14 },
			{ name: 'TURBULENCE', label: 'Turbulence', min: 0, max: 1, step: 0.05, default: 1.0 },
			{ name: 'RINGS', label: 'Ring contrast', min: 0, max: 1, step: 0.05, default: 1.0 },
			{ name: 'SPEED', label: 'Rotation speed', min: 0.1, max: 3, step: 0.1, default: 1.0 }
		]}
	/>

	<h2 id="lensing-disk">Wrapping the disk around the hole</h2>

	<p>
		Now we put the two pieces together. Same geodesic loop as Step 02, but each time a ray crosses
		the disk's plane (the y=0 equator) we sample its color and accumulate it. Light from the far
		side of the disk gets bent upward by the hole's gravity, around the silhouette, and into our
		eye as a halo arching <em>over the top</em> of what should be empty space. That halo is what
		makes a black hole look like a black hole instead of a dark circle.
	</p>

	<Sandbox
		src="/learn/event-horizon/04-disk-lensed.html"
		title="Step 04 — disk + gravitational lensing (no Doppler yet)"
		caption="Tilt the camera and watch the disk's far side rise over the silhouette. At this stage both sides of the disk are equally bright. We've done gravity to the geometry, but not yet relativity to the motion."
		wide
		aspect="16/8"
		params={[
			{ name: 'ROTATION_SPEED', label: 'Camera orbit', min: 0, max: 1, step: 0.05, default: 0.3 },
			{ name: 'TILT', label: 'Tilt', min: -0.6, max: 0.6, step: 0.02, default: 0.0 },
			{ name: 'ROTATE', label: 'Roll', min: -3.14, max: 3.14, step: 0.05, default: 0.0 },
			{ name: 'DISK_INTENSITY', label: 'Disk brightness', min: 0.3, max: 2, step: 0.1, default: 1.0 }
		]}
	/>

	<p>
		Lower the tilt to near zero and the disk becomes a flat band crossing the silhouette. Increase
		it and the top arc thickens. The disk isn't getting wider; you're seeing <em>more of the back
		of the disk</em> being lensed up into view.
	</p>

	<h2 id="doppler">Why one side is brighter</h2>

	<p>
		Compare the previous sandbox to the hero shader at the top of this article. They look almost
		the same. Almost. The hero is brighter on one side, and that asymmetry is the most photogenic
		bit of physics in the whole thing.
	</p>

	<p>
		The plasma in the disk isn't sitting still. It's orbiting at a meaningful fraction of the speed
		of light. The side moving <em>toward</em> us is Doppler-boosted: its photons arrive more
		frequently, blue-shifted, and the relativistic beaming concentrates them in our direction. The
		side moving <em>away</em> is the inverse: red-shifted, dimmed, defocused.
	</p>

	<p>
		The brightness boost goes as the Doppler factor cubed. Small velocity differences become large
		brightness differences.
	</p>

	<Code code={dopplerCode} lang="glsl" caption="Doppler beaming and frequency shift, inside the disk shader. orbSpeed comes from a Keplerian orbit (v ≈ √(GM/r), in our units √(0.5·RS/r))." />

	<Sandbox
		src="/learn/event-horizon/05-doppler.html"
		title="Step 05 — disk + lensing + Doppler beaming"
		caption="The DOPPLER slider scales the asymmetry from 0 (Step 04's symmetric disk) to 1 (full relativistic beaming). Drag the camera to a side view: the difference between approaching and receding sides is dramatic. Press the toggle to flip Doppler on and off cleanly."
		wide
		aspect="16/8"
		params={[
			{ name: 'TILT', label: 'Tilt', min: -0.6, max: 0.6, step: 0.02, default: 0.0 },
			{ name: 'ROTATE', label: 'Roll', min: -3.14, max: 3.14, step: 0.05, default: 0.0 },
			{ name: 'ROTATION_SPEED', label: 'Camera orbit', min: 0, max: 1, step: 0.05, default: 0.25 },
			{ name: 'DISK_INTENSITY', label: 'Disk brightness', min: 0.3, max: 2, step: 0.1, default: 1.0 }
		]}
		toggle={{ name: 'DOPPLER', label: 'Relativistic Doppler beaming', onValue: 1, offValue: 0, default: true }}
	/>

	<Aside type="note" title="What's a real-world black hole actually look like?">
		{#snippet children()}
			<p>
				The 2019 Event Horizon Telescope image of M87 shows exactly this asymmetry: one side of
				the ring much brighter than the other. The 2022 image of Sgr A* shows it too, plus some
				time-varying structure from the matter swirling around it.
			</p>
			<p>
				Real ones also wobble (the spin axis precesses), sometimes shoot polar jets, and have
				far more complex disk physics than Novikov-Thorne. The bright asymmetric ring on a dark
				silhouette is the signature you can see in our shader.
			</p>
		{/snippet}
	</Aside>

	<h2 id="photon-ring">The photon ring</h2>

	<p>
		If you stare at Step 05 with the camera tilted sharply, you'll notice a thin bright line right
		on the edge of the silhouette. That's the <strong>photon ring</strong>: light that orbited the
		hole once (or twice, or more) before escaping. Photons that pass right at the photon sphere can
		make a half-loop, three-quarters, even a full loop, picking up successive views of the disk on
		each pass.
	</p>

	<p>
		In code this falls out naturally from one detail: a ray can cross the disk plane more than
		once. The first crossing is the disk in front of the hole. The second is the back of the disk,
		wrapped over the top. The third, fourth, fifth get progressively concentrated near r ≈ 1.5·RS,
		forming a stack of ever-thinner rings hugging the silhouette.
	</p>

	<Code code={crossingCode} lang="glsl" caption="The disk-crossing handler inside the integration loop. The third-and-later crossings get knocked down to 15% intensity. Otherwise they alias into a buzzing 1-pixel ring." />

	<Aside type="warning" title="Anti-aliasing crisp features">
		{#snippet children()}
			<p>
				The photon ring is a real, infinitely thin feature. Sampling it at one pixel of width
				creates a crawling moiré pattern that flickers between frames. The cheap fix is to lower
				the intensity of later crossings: they still contribute a glow but don't strobe.
				The expensive fix is to supersample around the silhouette edge. For real-time rendering
				the cheap fix is right.
			</p>
		{/snippet}
	</Aside>

	<h2 id="performance">Making it 60fps on a laptop</h2>

	<p>
		Every pixel of a 1080p screen runs the whole ray-marching loop, sixty times a second. The
		worst-lit pixels (the rays near the hole) do up to 200 Verlet steps each, which works out to
		around 124 million steps per second for the dense pixels alone.
	</p>

	<p>
		The biggest savings come from variable step size. Far from the hole, geodesics are nearly
		straight and we coast in strides as large as <code>h = 3.5</code> in scene units. Close in,
		curvature is steep and we drop to <code>h ≈ 0.06</code>. The expression
		<code>h = 0.16 · clamp(r − 0.4·RS, 0.06, 3.5)</code> picks the size each step. Almost all rays
		spend almost all of their iterations far from the hole, so the average step is large even
		though the worst-case step is small.
	</p>

	<p>
		Loop invariants are pulled out: angular momentum <Math>{#snippet children()}L²{/snippet}</Math>
		and the constant factor in the acceleration are computed once per ray. Inside the loop the
		only divisions are <code>1/r²</code> and <code>1/r⁵</code>, and the latter is reused as
		<code>(invR²)² / r</code> to save a multiply. Small savings, two million pixels, a hundred
		iterations each.
	</p>

	<p>
		Termination is aggressive. A ray outside r = 25 and still moving outward isn't coming back, so
		we break. A ray past r = 55 is gone regardless. A ray inside <code>0.35·RS</code> has crossed
		the event horizon; we mark it absorbed and break. Most pixels exit in fewer than 50 of the 200
		nominal iterations.
	</p>

	<Aside type="tip" title="What about Kerr (rotating) black holes?">
		{#snippet children()}
			<p>
				Schwarzschild is the easy case. A rotating Kerr black hole drags spacetime around with it
				(frame dragging) and has a more complex metric with two distinct null surfaces. The Verlet
				integrator still works, but the acceleration is harder to write down and the geometry
				includes effects like the ergosphere, where light is forced to co-rotate. For most visual
				purposes Schwarzschild gets you 90% of the look at 30% of the math.
			</p>
		{/snippet}
	</Aside>

	<h2 id="putting-together">Putting it all together</h2>

	<p>
		The full shader stitches every step together: star field for the sky, geodesic integration for
		the bending, Novikov-Thorne plus blackbody for the disk's color, alpha-over compositing for
		multiple crossings, Doppler beaming for the asymmetry, filmic tone curve at the end. About
		560 lines of HTML total, half of which is the GLSL fragment shader. Drop it in an
		<code>&lt;iframe&gt;</code> anywhere and it just runs.
	</p>

	<p>
		Everything is turned on here, every parameter exposed. Try the chromatic dispersion slider:
		it's a spectral hue mapping on the disk we didn't cover in the article, but it's the same
		blackbody mapping with an extra dimension.
	</p>

	<Sandbox
		src="/{shader.file}"
		title="The final shader"
		caption="Everything together. Same file as /shader/event-horizon. Fullscreen-ready, all parameters live, all 60fps."
		wide
		aspect="16/8"
		params={[
			{ name: 'ROTATION_SPEED', label: 'Camera orbit', min: 0.05, max: 1.0, step: 0.05, default: 0.3 },
			{ name: 'DISK_INTENSITY', label: 'Disk brightness', min: 0.3, max: 2.0, step: 0.1, default: 1.0 },
			{ name: 'TILT', label: 'Tilt', min: -1.5, max: 1.5, step: 0.05, default: 0.0 },
			{ name: 'ROTATE', label: 'Roll', min: -3.14, max: 3.14, step: 0.05, default: 0.0 },
			{ name: 'CHROMATIC', label: 'Chromatic dispersion', min: 0, max: 1, step: 0.05, default: 0.0 }
		]}
	/>

	<h2 id="reading">Where to go from here</h2>

	<p>
		Two papers and one implementation, in escalating commitment. rantonels'
		<a href="https://rantonels.github.io/starless/" target="_blank" rel="noopener noreferrer">Starless</a>
		is the more rigorous offline cousin of this shader, with full Kerr support and beautiful
		explanatory diagrams. The Wikipedia article on
		<a href="https://en.wikipedia.org/wiki/Schwarzschild_geodesics" target="_blank" rel="noopener noreferrer">Schwarzschild
		geodesics</a> derives the equation we used from the metric tensor in three pages of pleasant
		tensor calculus. And the
		<em>Interstellar</em>
		look is documented in Kip Thorne's
		<a href="https://arxiv.org/abs/1502.03808" target="_blank" rel="noopener noreferrer">Gravitational
		Lensing by Spinning Black Holes in Astrophysics</a>: roughly this article, plus a year of work
		and a Nobel laureate.
	</p>

	<p>
		The source is under 600 lines of HTML. View it, copy it, save it. The whole file works as a
		standalone background, hero, or wallpaper without any build step.
	</p>
</ArticleShell>
