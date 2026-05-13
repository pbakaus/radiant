<script lang="ts">
	import type { Shader } from '$lib/shaders';
	import { articleMeta } from '$lib/articles';
	import ArticleShell from '$lib/components/article/ArticleShell.svelte';
	import Sandbox from '$lib/components/article/Sandbox.svelte';
	import Code from '$lib/components/article/Code.svelte';
	import Aside from '$lib/components/article/Aside.svelte';
	import RefractionDecoder from '$lib/components/article/RefractionDecoder.svelte';
	import DropMerger from '$lib/components/article/DropMerger.svelte';

	let { shader }: { shader: Shader } = $props();
	const meta = articleMeta['rain-on-glass'];

	// ─── Code excerpts ──────────────────────────────────────
	const bitmapCode = `// Bake the drop's refraction normals into RGB once, at init time.
// R = vertical offset (centered at 128 = 'no offset')
// G = horizontal offset (same convention)
// B = depth into the drop — scales refraction strength
// A = the visible-area mask
for (var py = 0; py < SIZE; py++) {
  for (var px = 0; px < SIZE; px++) {
    var dx = (px - cx) / cx;
    var dy = (py - cy) / cy;
    dy *= 1.0 + dy * 0.15;            // slight tear shape
    var dist = Math.sqrt(dx * dx + dy * dy);
    if (dist > 1.0) continue;

    var nx = dist > 0.001 ? dx / dist : 0;
    var ny = dist > 0.001 ? dy / dist : 0;
    var r     = Math.round(ny * 60 * dist + 128);
    var g     = Math.round(nx * 60 * dist + 128);
    var depth = Math.sqrt(Math.max(0, 1.0 - dist*dist)) * 255;
    var alpha = Math.max(0, 1.0 - Math.pow(dist / 0.45, 6)) * 255;

    var idx = (py * SIZE + px) * 4;
    d[idx]     = r;        // → texture.r in the shader
    d[idx + 1] = g;        // → texture.g
    d[idx + 2] = depth;    // → texture.b
    d[idx + 3] = alpha;    // → texture.a
  }
}`;

	const shaderCode = `precision mediump float;
uniform sampler2D u_waterMap;
uniform sampler2D u_background;
uniform vec2  u_res;
uniform float u_refraction;

void main() {
  vec2 uv      = gl_FragCoord.xy / u_res;
  vec4 water   = texture2D(u_waterMap, vec2(uv.x, 1.0 - uv.y));

  // ─── The whole technique, six lines ───
  vec2  offset      = (vec2(water.g, water.r) - 0.5) * 2.0;
  float depth       = water.b;
  vec2  refractedUV = uv + offset * (256.0 + depth * 256.0) / u_res.x * u_refraction;
  vec4  bg          = texture2D(u_background, refractedUV);

  // Outside a drop: show the background as-is. Inside: show the lensed lookup.
  gl_FragColor = mix(
    texture2D(u_background, uv),
    bg,
    clamp(water.a * 4.0 - 1.0, 0.0, 1.0)
  );
}`;

	const physicsCode = `// Most of the time, do nothing. That's a feature.
// Drops only start sliding when something kicks them — modeled as
// a probability that grows with drop size. Surface tension is just
// "low probability of kick for small drops; higher for big ones."
if (Math.random() < drop.r / (100 * dpr) * dt * 0.5 / SURFACE_TENSION) {
  drop.momentum += rand(0.5, 2.5);
}

// Once moving, fall and shed trail drops behind us.
drop.y += drop.momentum * dt;
drop.momentum *= Math.pow(0.95, dt);  // friction

if (drop.momentum > 0.5 && drop.lastSpawn > 20) {
  spawnTrailDrop(drop);  // a smaller drop, in our slipstream
  drop.r *= 0.97;        // we lose a little water making it
  drop.lastSpawn = 0;
}`;

	const shapeCode = `// The drop's drawn size has three components.
//   scaleY is constant — a real drop on glass is taller than wide.
//   spreadX/Y are transient "splat" factors set on spawn or collision.
//   Both spreads decay every frame, which is surface tension settling.
function drawDrop(d) {
  const SHAPE_TEARDROP = 1.5;
  const w = d.r * 2 * (1 + d.spreadX);
  const h = d.r * 2 * SHAPE_TEARDROP * (1 + d.spreadY);
  ctx.drawImage(dropBitmap, d.x - w/2, d.y - h/2, w, h);
}

// Per frame, in updatePhysics:
drop.spreadX *= Math.pow(0.4, dt);   // rapid X collapse
drop.spreadY *= Math.pow(0.7, dt);   // slower Y settling`;

	const collisionCode = `// Sort by y so we only check nearby drops (O(n·k), not O(n²))
drops.sort((a, b) => a.y - b.y);

for (var i = 0; i < drops.length; i++) {
  var d1 = drops[i];
  for (var j = i + 1; j < Math.min(i + 30, drops.length); j++) {
    var d2 = drops[j];
    if (d1.r <= d2.r) continue;  // only the bigger one absorbs

    var dx = d2.x - d1.x, dy = d2.y - d1.y;
    if (dx*dx + dy*dy < ((d1.r + d2.r) * 0.45) ** 2) {
      // Area conservation with an 0.8 loss factor — some water
      // gets left behind as the merger happens.
      var a1 = Math.PI * d1.r * d1.r;
      var a2 = Math.PI * d2.r * d2.r;
      d1.r = Math.sqrt((a1 + a2 * 0.8) / Math.PI);
      d1.momentum += 1.5;   // mergers snowball
      d1.spreadX = Math.max(d1.spreadX, 0.25);  // small settle wobble
      d1.spreadY = Math.max(d1.spreadY, 0.15);
      d2.killed = true;
    }
  }
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
		What looks like a single water effect is actually two pipelines, glued together. Canvas 2D
		builds a "water map" of where drops are and what shape each one bends light by. A WebGL
		fragment shader reads that water map and uses it to refract a background image. Take away
		either side and you don't have rain.
	</p>

	<p>
		The trick that makes this fast is that <strong>refraction is a texture lookup, not a
		computation</strong>. The shader does almost no per-pixel math. The drop's refraction profile
		is pre-baked into an RGBA bitmap once, at startup, and then stamped wherever a drop should
		appear. That's the article.
	</p>

	<Aside type="note" title="Prior art">
		{#snippet children()}
			<p>
				The technique is from
				<a href="https://github.com/codrops/RainEffect" target="_blank" rel="noopener noreferrer">Lucas
				Bebber's RainEffect</a>, published on Codrops in 2015 and still one of the most-cited
				examples of clever Canvas-2D-as-texture-source compositing. The Radiant version is a
				rewrite for the shader catalog. The shape of the algorithm (the bitmap encoding, the
				physics model, the wet-glass two-background trick) is his.
			</p>
		{/snippet}
	</Aside>

	<h2 id="a-drop-is-a-lens">A drop is a lens</h2>

	<p>
		Hold a water drop on a window in front of a city light. The light through the drop is
		flipped, distorted, and concentrated. Different parts of the drop pull different parts of the
		background into your eye. That's what we have to fake.
	</p>

	<p>
		For real refraction we'd compute Snell's law per pixel: the angle of incidence, the index of
		refraction, the path the light takes through curved glass. Doable in a fragment shader. Slow,
		and overkill. Real raindrops on a real window aren't perfect spheres. They're squished blobs
		with surface tension. The "lens" math gets dirty fast.
	</p>

	<p>
		The shortcut: for each pixel of a drop, just remember where it should sample from. That's a
		2D offset. Store it. The shader reads the offset and samples. No Snell, no per-pixel math.
	</p>

	<h2 id="encoding-refraction">Encoding refraction as a texture</h2>

	<p>
		Here's the drop, drawn once into a 256×256 Canvas 2D bitmap. The RGB channels each carry a
		different piece of the refraction recipe. Drag the marker on the left to see what gets
		encoded at each point.
	</p>

	<RefractionDecoder
		caption="Click and drag inside the drop. R encodes the vertical offset, G the horizontal, B the depth into the drop. The arrow on the right shows where that pixel will end up sampling from on the background."
	/>

	<p>
		The encoding is intentionally simple: a point at distance <code>d</code> from the drop's
		center stores an offset that points <em>outward</em> from the center, with magnitude
		proportional to <code>d</code>. That's the shape a real lens makes: the rim bends light most,
		the center barely. The B channel stores depth (a half-sphere falloff), used later as a
		multiplier so the shader can dial refraction strength up where the drop is thickest.
	</p>

	<Code code={bitmapCode} lang="js" caption="The drop bitmap, built once at init. This is plain Canvas 2D, no shader, no GPU. We're filling an ImageData buffer by hand because we need full control over individual channels." />

	<p>
		Two things to notice about line 13. First, the visible portion of the bitmap is much smaller
		than the drawn radius: the <code>pow(dist / 0.45, 6)</code> alpha falloff means only the
		inner ~45% of the bitmap is opaque. That's deliberate. The bitmap gets drawn at many
		different scales, and the rest of the 256×256 frame is unused padding for safe blending at
		the edges. Second, the <code>dy *= 1 + dy * 0.15</code> on line 7 gives the drop a slight
		teardrop shape, taller than wide. Surface tension does that on real glass.
	</p>

	<Sandbox
		src="/learn/rain-on-glass/02-normal-map.html"
		title="Step 02 — the drop normal map"
		caption="Pure Canvas 2D, no shader. Left: the drop's alpha channel (the visible-area mask). Right: the RGB channels (refraction offsets and depth, all in one image)."
		aspect="16/9"
	/>

	<h2 id="the-shader">The shader: one lookup, two textures</h2>

	<p>
		Now we use the bitmap. The fragment shader needs two textures: the
		<strong>water map</strong> (where drops are, drawn by Canvas 2D each frame), and the
		<strong>background</strong> (whatever we're refracting: a photograph, a procedural city
		scene). Each pixel reads the water map, decodes RG as a 2D offset, scales it by the depth
		channel, and samples the background at offset position.
	</p>

	<Code code={shaderCode} lang="glsl" caption="The whole refraction shader. Six lines of actual work between the uniforms and the final blend." />

	<p>
		Line 12 is the decode: <code>(g, r) − 0.5</code> shifts the 0..1 stored offset back into a
		signed −1..1 range, the <code>* 2.0</code> recovers the original scale. The pixel-to-UV
		conversion on line 14 uses <code>256 / u_res.x</code> as the base offset and adds another
		<code>256 · depth</code> on top, so a pixel at the drop's deepest point can pull from up to
		512 pixels away. On a 1400-pixel-wide canvas that's roughly a third of the screen, which
		looks like a real drop's lensing.
	</p>

	<p>
		Below: a single drop, mouse-positioned, refracting a procedural background. Move your cursor
		anywhere. The toggle flips between the rendered drop and the raw normal map texture, so you
		can see the encoded image directly.
	</p>

	<Sandbox
		src="/learn/rain-on-glass/01-single-drop.html"
		title="Step 01 — one drop"
		caption="Move your cursor to position the drop. The 'show normal map' toggle reveals the raw RGB bitmap the shader is decoding."
		aspect="16/9"
		params={[
			{ name: 'REFRACTION', label: 'Refraction strength', min: 0.1, max: 3.0, step: 0.05, default: 1.0 },
			{ name: 'DROP_SIZE', label: 'Drop size', min: 200, max: 600, step: 10, default: 380 }
		]}
		toggle={{ name: 'SHOW_NORMAL_MAP', label: 'Show normal map texture', onValue: 1, offValue: 0, default: false }}
	/>

	<h2 id="many-drops">A water map of many drops</h2>

	<p>
		One drop is a curiosity. A windowful is the point. Each frame we clear a Canvas 2D buffer
		(the water map), draw every drop's bitmap into it at the drop's current position and size,
		and upload the result as a WebGL texture. The shader does the same lookup for every pixel; it
		doesn't know or care that there are now two hundred drops instead of one.
	</p>

	<p>
		The drawing loop is literally this:
	</p>

	<Code code={`waterCtx.clearRect(0, 0, w, h);
for (const drop of drops) {
  const size = drop.r * 2;
  waterCtx.drawImage(
    dropBitmap,
    drop.x - size/2, drop.y - size/2,
    size, size
  );
}`} lang="js" />

	<p>
		One <code>drawImage</code> call per drop. Canvas 2D is extremely good at this, orders of
		magnitude faster than computing refraction in a shader, because the drop bitmap is already
		correctly composited (the alpha channel masks the shape, the RGB channels carry the
		refraction). Stamping a 60×60 pixel sprite is something the browser's 2D pipeline has been
		optimized to death for.
	</p>

	<Sandbox
		src="/learn/rain-on-glass/03-static-field.html"
		title="Step 03 — a static field"
		caption="200 drops, no motion, just stamping. Adjust the count, size range, and refraction. Reshuffle to see different random placements."
		aspect="16/9"
		params={[
			{ name: 'DROP_COUNT', label: 'Drop count', min: 20, max: 600, step: 10, default: 200 },
			{ name: 'DROP_SIZE_MIN', label: 'Min size', min: 10, max: 60, step: 1, default: 30 },
			{ name: 'DROP_SIZE_MAX', label: 'Max size', min: 40, max: 150, step: 5, default: 90 },
			{ name: 'REFRACTION', label: 'Refraction', min: 0.1, max: 3.0, step: 0.05, default: 1.0 },
			{ name: 'RESHUFFLE', label: 'Shuffle seed', min: 1, max: 99, step: 1, default: 1 }
		]}
	/>

	<h2 id="drops-that-move">Drops that move</h2>

	<p>
		Real drops on glass mostly sit still. Surface tension is stronger than gravity at the scales
		we care about. Then something (a vibration, an arriving drop, a temperature gradient) tips
		the balance and the drop suddenly starts sliding. Once it's moving, it gains momentum, sheds
		smaller drops in its wake, and either makes it to the bottom or fuses with another drop and
		passes its mass along.
	</p>

	<p>
		Modeling all that physically would be a research project. We model it as <em>probability</em>.
		Each frame, every drop has some chance of getting a momentum kick. Bigger drops get kicked
		more often (their weight wins against tension sooner). Once moving, drops decay back toward
		stillness unless they get kicked again or run into another drop.
	</p>

	<Code code={physicsCode} lang="js" caption="The whole physics loop for one drop. Surface tension is not a force here; it's the inverse of a probability." />

	<Sandbox
		src="/learn/rain-on-glass/04-rolling-drop.html"
		title="Step 04 — a rolling drop"
		caption="A single drop with physics. Notice the teardrop shape — drops aren't round. Crank surface tension down to see drops slide more easily; crank trail rate up to see them shed mass faster."
		aspect="16/9"
		params={[
			{ name: 'GRAVITY', label: 'Gravity', min: 0.3, max: 3.0, step: 0.05, default: 1.0 },
			{ name: 'SURFACE_TENSION', label: 'Surface tension', min: 0.1, max: 4.0, step: 0.05, default: 1.0 },
			{ name: 'TRAIL_RATE', label: 'Trail rate', min: 0.0, max: 3.0, step: 0.05, default: 1.0 },
			{ name: 'REFRACTION', label: 'Refraction', min: 0.1, max: 2.0, step: 0.05, default: 1.0 }
		]}
	/>

	<p>
		Watch what happens when surface tension drops to 0.2: the kicks happen constantly, drops never
		really sit still, and the glass becomes a wash of streaks. Crank it up to 3 and drops freeze
		in place after a brief slide. Real plausibility is somewhere around 0.7–1.5.
	</p>

	<h2 id="shape">Drops aren't round</h2>

	<p>
		Look closely at the rolling drop above. It's not a circle. A real water drop on glass is taller
		than it is wide, with a flattened bottom — gravity pulls the bottom down, surface tension pulls
		the top back up, and the steady-state shape is a teardrop. The drops in our shader cheat the
		same way real drops do.
	</p>

	<p>
		The shape is two factors stacked together. <code>scaleY</code> is constant — every drop is
		drawn ~1.5x taller than wide. That's the teardrop baseline. On top of that, <code>spreadX</code>
		and <code>spreadY</code> are transient "splat" factors. A freshly-spawned drop hits the glass
		spread out; a freshly-merged drop bulges from the impact. Both spreads decay every frame, which
		is what surface tension does in real life.
	</p>

	<Code code={shapeCode} lang="js" caption="Drop shape in three lines: a constant teardrop multiplier, transient spreads, and per-frame decay back to the baseline." />

	<p>
		The decay rates matter. <code>pow(0.4, dt)</code> on X means horizontal spread collapses in
		~3 frames. <code>pow(0.7, dt)</code> on Y means vertical settling takes ~6 frames. Drops snap
		back narrow first, then settle vertically — the same asymmetry you see in a real droplet
		flattening on glass.
	</p>

	<p>
		Without this, a merge looks like two circles snapping into one bigger circle. With it, the
		bigger circle <em>bulges</em> for a moment and then pulls itself back together. That bulge is
		the difference between "fake" and "real" in this shader.
	</p>

	<h2 id="merging">Drops that merge</h2>

	<p>
		Two drops meet. Surface tension at the contact point collapses; the smaller drop folds into
		the bigger. The bigger one's radius grows, but not by the full sum of the two: a little
		water gets left behind as residue. Volume is roughly conserved.
	</p>

	<p>In code:</p>

	<Code code={collisionCode} lang="js" caption="Collision detection and merging. The y-sort plus a window of 30 neighbors keeps the inner loop bounded, close enough to O(n) in practice." />

	<p>
		The area-conservation formula on line 13 is the only piece of real geometry in the whole
		shader. Two drops with radii <code>r₁</code> and <code>r₂</code> have combined area
		<code>π·r₁² + π·r₂²</code>. The merged drop has the same area minus a fudge factor (we use
		0.8) for water lost in the merge, so its radius is the square root of all that divided by π.
		The slider below has it live:
	</p>

	<DropMerger caption="Two drops with adjustable radii and the merged result. The 0.8 factor on r₂² is the 'some water doesn't make it' loss." />

	<Sandbox
		src="/learn/rain-on-glass/05-merging-field.html"
		title="Step 05 — drops that merge"
		caption="Drops spawn over time, slide when surface tension lets go, and absorb the smaller drops they touch. Watch for the moment of impact — the merged drop spreads briefly before pulling itself back into a teardrop. That's what makes the merge read as physical instead of as one circle eating another."
		aspect="16/9"
		params={[
			{ name: 'SPAWN_RATE', label: 'Spawn rate', min: 0.1, max: 3.0, step: 0.05, default: 1.0 },
			{ name: 'COLLISION_RADIUS', label: 'Collision radius', min: 0.1, max: 0.9, step: 0.05, default: 0.45 },
			{ name: 'REFRACTION', label: 'Refraction', min: 0.1, max: 2.0, step: 0.05, default: 1.0 }
		]}
	/>

	<p>
		The momentum boost on line 16 is what makes this look right. Without it, a drop that absorbs
		five smaller drops on its way down would arrive at the bottom at the same speed it started.
		With it, every merger adds a small kick and the drop accelerates, exactly the
		snowballing-bowling-ball trajectory real raindrops make.
	</p>

	<h2 id="wet-glass">The wet-glass trick</h2>

	<p>
		The production shader has one more visual sleight of hand worth mentioning: <strong>two
		different background textures</strong>. The "no drop here" pixels sample a heavily-blurred
		version of the scene; the "you're looking through a drop" pixels sample a less-blurred
		version. The drop's alpha mask switches between them.
	</p>

	<p>
		The effect is psychological. Wet glass is hazy because the water on the surface is itself
		acting as a million tiny micro-lenses, each one slightly blurring what's behind. But the
		moment a real drop forms, it concentrates that view back into focus, like a magnifying glass.
		Our drops feel like portals: they reveal <em>more</em> detail than the surrounding glass,
		not less.
	</p>

	<p>
		The Radiant production shader does this with a 384×256 heavy-blur background and a 96×64
		lighter-blur foreground, both procedurally generated cityscapes. The teaching variants above
		skip this for clarity (one background, one lookup); the final shader puts it back.
	</p>

	<h2 id="two-layers">Two layers of drops</h2>

	<p>
		One last thing the production shader does that the teaching variants don't. There are
		actually two separate "drops" systems running in parallel: the <code>drops[]</code> array of
		big, physics-having drops we've been talking about, plus a second Canvas 2D layer of tiny
		static "spray" droplets, the kind that mist up the glass between real drops without
		individually moving.
	</p>

	<p>
		Spray drops never collide and never have momentum. They just exist as a fine speckle on the
		water map. Big drops, as they slide, <em>erase</em> spray drops underneath them via Canvas
		2D's <code>destination-out</code> composite operation: clean tracks of glass appear behind
		moving drops, while the rest of the window stays misty. It's the visual signature of the
		whole effect.
	</p>

	<h2 id="umbrella">Same trick, different surface</h2>

	<p>
		The rain-on-umbrella shader in the Radiant catalog uses the exact same drop bitmap, the
		exact same refraction shader, and a barely-modified physics loop. The differences are all in
		the spawn surface and the trajectories: drops spawn on a curved dome, slide radially outward
		from the center of the umbrella, and inherit a small "walking" jitter that makes the whole
		image bob as if you're walking under it.
	</p>

	<p>
		Open it side by side with this one and switch between them. The look is wildly different.
		The pipeline is identical.
	</p>

	<Sandbox
		src="/rain-umbrella.html"
		title="Rain on umbrella"
		caption="Same drop bitmap, same shader, different surface. The dome curvature determines initial drop momentum and direction; the walk-speed parameter adds the umbrella-shake jitter."
		aspect="16/9"
		params={[
			{ name: 'RAIN_AMOUNT', label: 'Rain amount', min: 0.1, max: 2.0, step: 0.05, default: 1.0 },
			{ name: 'REFRACTION', label: 'Refraction', min: 0.1, max: 3.0, step: 0.05, default: 1.0 },
			{ name: 'WALK_SPEED', label: 'Walk speed', min: 0.0, max: 3.0, step: 0.05, default: 1.0 }
		]}
	/>

	<h2 id="performance">Why this is fast</h2>

	<p>
		A windowful of rain is two hundred drops, each with its own physics update, plus a few
		thousand static spray droplets, plus a per-pixel refraction lookup. None of that is
		intuitively cheap. Three things keep it real-time.
	</p>

	<p>
		<strong>The bitmap is pre-baked.</strong> The drop's normal map is computed once, at init.
		255 depth variants pre-rendered as separate sprites so the shader can pick the right one
		for any drop size without extra math. After init, drawing a drop is one
		<code>drawImage</code>. There's no per-frame texture generation.
	</p>

	<p>
		<strong>Canvas 2D is the right tool for the water map.</strong> A WebGL implementation of
		"stamp two hundred sprites onto a canvas" would need batched draw calls, instanced
		quads, and texture atlases. Canvas 2D does it natively, on the CPU, at speed, with no
		bookkeeping. The water map gets uploaded to the GPU as one texture per frame. That's the
		only cross-domain transfer.
	</p>

	<p>
		<strong>The physics loop is O(n)-ish.</strong> Collision detection sorts drops by y and only
		checks each one against its 30 nearest neighbors. With drops sorted, the y-sort is nearly
		stable across frames (a near-sorted insertion sort is O(n)), and each drop's collision check
		is bounded. No spatial hash, no quadtree. Two hundred drops, six thousand cheap distance
		checks per frame.
	</p>

	<h2 id="where-to-go">Where to go from here</h2>

	<p>
		<a href="https://tympanus.net/codrops/2015/11/04/rain-water-effect-experiments/" target="_blank" rel="noopener noreferrer">Lucas
		Bebber's original article</a> at Codrops covers the technique with more depth on the production
		setup, including the depth-variant pre-baking, the parallax handling, and the shine/shadow
		that make the drops look 3D rather than purely flat. The source for Radiant's version is the
		same algorithm; it differs mostly in the procedural background and the interaction details
		(click to splash, drag to wipe).
	</p>

	<p>
		If you want a deeper rabbit hole, look up
		<a href="https://en.wikipedia.org/wiki/Normal_mapping" target="_blank" rel="noopener noreferrer">normal
		mapping</a> in general 3D rendering. The drop bitmap is exactly a 2D normal map: each pixel
		stores a surface normal direction encoded in the RGB channels, and the shader uses it to
		offset something else. Drops on glass are one application; bumpy floors in video games, water
		surfaces, and bricks on walls are others. The encoding trick generalizes.
	</p>

	<p>
		The whole rain-on-glass file is about 1000 lines of HTML. Half is the physics. A quarter is
		the procedural background. A tenth is the fragment shader. Drop it on any page; it has no
		dependencies.
	</p>
</ArticleShell>
