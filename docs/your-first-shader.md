# Your First Radiant Shader

In this tutorial, you'll build a complete Radiant shader from scratch — a **Pulse Grid** of animated circles that breathe, shift color, and react to your cursor. By the end, it'll be registered in the gallery with previews and tunable parameters.

No prior Canvas experience required. We'll use the Canvas 2D API (no WebGL), and everything lives in a single HTML file.

**What you'll learn:**

- The Radiant shader HTML structure
- Canvas setup with device pixel ratio (DPR) handling
- Animation with `requestAnimationFrame`
- Mouse and touch interactivity
- Tunable parameters via `postMessage`
- Registering in the shader catalog

## Step 1: The HTML Shell

Every Radiant shader is a standalone HTML file in the `static/` directory. Create `static/pulse-grid.html` and start with this boilerplate:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Pulse Grid</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; background: #0a0a0a; }
  canvas { display: block; width: 100vw; height: 100vh; }
  .label {
    position: fixed;
    top: 20px;
    left: 24px;
    font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
    font-size: 11px;
    letter-spacing: 0.15em;
    text-transform: uppercase;
    color: rgba(200, 149, 108, 0.5);
    z-index: 10;
    pointer-events: none;
    user-select: none;
  }
</style>
</head>
<body>
<div class="label">Pulse Grid</div>
<canvas id="canvas"></canvas>
<script>
// Your shader code goes here
</script>
</body>
</html>
```

This is the same structure every Radiant shader uses:

- **Dark background** (`#0a0a0a`) — the gallery expects it
- **Full-viewport canvas** — fills the entire window
- **Label div** — fixed-position shader name in warm amber, non-interactive
- **Single `<script>` block** — all logic inline, no imports

## Step 2: Canvas Setup and DPR Handling

Replace the `// Your shader code goes here` comment with an IIFE (Immediately Invoked Function Expression) that sets up the canvas:

```js
(function() {
  const canvas = document.getElementById('canvas');
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(window.devicePixelRatio || 1, 2);

  let W, H;

  function resize() {
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width = W * dpr;
    canvas.height = H * dpr;
    canvas.style.width = W + 'px';
    canvas.style.height = H + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  window.addEventListener('resize', resize);
  resize();
})();
```

**Why an IIFE?** It keeps all variables scoped to the function, avoiding globals. Every Radiant shader uses this pattern.

**Why DPR handling?** On high-DPI screens (Retina, etc.), a CSS pixel maps to 2+ physical pixels. Without DPR scaling, your shader looks blurry. We:

1. Set the canvas resolution to `width * dpr` (physical pixels)
2. Set the CSS size to the viewport dimensions (CSS pixels)
3. Use `ctx.setTransform` so all drawing coordinates stay in CSS pixels

We cap DPR at 2 to keep performance solid — higher values rarely look noticeably better but can halve your frame rate.

## Step 3: Draw Something

Let's draw a grid of circles. Add this inside the IIFE, after the `resize()` call:

```js
  // ── Grid config ──
  var SPACING = 40;
  var BASE_RADIUS = 4;

  function draw() {
    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, W, H);

    const cols = Math.ceil(W / SPACING) + 1;
    const rows = Math.ceil(H / SPACING) + 1;

    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const x = col * SPACING;
        const y = row * SPACING;

        ctx.beginPath();
        ctx.arc(x, y, BASE_RADIUS, 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(200, 149, 108, 0.6)';
        ctx.fill();
      }
    }
  }

  draw();
```

Open the file in your browser. You should see a static grid of warm amber dots on a dark background.

## Step 4: Animate It

A static grid isn't very interesting. Let's make the circles pulse by adding time-based animation. Replace the `draw()` function and its call:

```js
  // ── Grid config ──
  var SPACING = 40;
  var BASE_RADIUS = 4;
  var PULSE_SPEED = 1.0;

  // ── Animation ──
  let time = 0;
  let running = true;

  function draw() {
    if (!running) return;

    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, W, H);

    time += 0.02 * PULSE_SPEED;

    const cols = Math.ceil(W / SPACING) + 1;
    const rows = Math.ceil(H / SPACING) + 1;

    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const x = col * SPACING;
        const y = row * SPACING;

        // Each circle gets a phase offset based on its position
        const phase = (col + row) * 0.3;
        const pulse = Math.sin(time + phase);

        // Map pulse [-1, 1] to radius and opacity
        const radius = BASE_RADIUS + pulse * 2;
        const alpha = 0.3 + pulse * 0.2;

        ctx.beginPath();
        ctx.arc(x, y, Math.max(0.5, radius), 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(200, 149, 108, ' + alpha + ')';
        ctx.fill();
      }
    }

    requestAnimationFrame(draw);
  }

  // Pause when tab is hidden (saves CPU/battery)
  document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
      running = false;
    } else {
      running = true;
      requestAnimationFrame(draw);
    }
  });

  requestAnimationFrame(draw);
```

Now the circles breathe — expanding and fading in waves across the grid. A few things to note:

- **`requestAnimationFrame`** runs at 60fps and syncs with the display refresh. Always use this, never `setInterval`.
- **`visibilitychange`** pauses animation when the tab is hidden. This is required for all Radiant shaders.
- **Phase offset** (`(col + row) * 0.3`) makes the pulse ripple diagonally. Try changing the multiplier.
- The **time increment** (`0.02`) controls overall animation speed.

## Step 5: Add Mouse/Touch Interaction

All Radiant shaders must respond to user input. Let's make the circles react to the cursor — circles near the mouse will grow larger and glow brighter.

Add the mouse/touch tracking before the `draw()` function:

```js
  // ── Mouse/touch tracking ──
  const mouse = { x: -9999, y: -9999, active: false };

  window.addEventListener('mousemove', function(e) {
    mouse.x = e.clientX;
    mouse.y = e.clientY;
    mouse.active = true;
  });
  window.addEventListener('mouseleave', function() {
    mouse.active = false;
  });
  window.addEventListener('touchmove', function(e) {
    mouse.x = e.touches[0].clientX;
    mouse.y = e.touches[0].clientY;
    mouse.active = true;
  }, { passive: true });
  window.addEventListener('touchend', function() {
    mouse.active = false;
  });
```

Now update the inner loop of `draw()` to include the mouse influence. Replace the section where you compute `radius` and `alpha`:

```js
        // Each circle gets a phase offset based on its position
        const phase = (col + row) * 0.3;
        const pulse = Math.sin(time + phase);

        // Mouse influence — circles near cursor grow and brighten
        let mouseInfluence = 0;
        if (mouse.active) {
          const dx = x - mouse.x;
          const dy = y - mouse.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          mouseInfluence = Math.max(0, 1 - dist / 150);
        }

        const radius = BASE_RADIUS + pulse * 2 + mouseInfluence * 8;
        const alpha = 0.3 + pulse * 0.2 + mouseInfluence * 0.4;

        ctx.beginPath();
        ctx.arc(x, y, Math.max(0.5, radius), 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(200, 149, 108, ' + Math.min(1, alpha) + ')';
        ctx.fill();
```

Move your cursor over the grid — circles swell and glow as you pass over them. The interaction uses a simple distance falloff: full effect at the cursor position, fading to zero at 150px away.

## Step 6: Add postMessage Parameters

The Radiant gallery lets users tweak shader parameters via sliders. Shaders receive these as `postMessage` events. Add this at the end of the IIFE (before the closing `})();`):

```js
  // ── Parameter control via postMessage ──
  window.addEventListener('message', function(e) {
    if (e.data && e.data.type === 'param') {
      switch (e.data.name) {
        case 'SPACING': SPACING = e.data.value; break;
        case 'PULSE_SPEED': PULSE_SPEED = e.data.value; break;
      }
    }
  });
```

This listens for messages like `{ type: 'param', name: 'SPACING', value: 60 }` and updates the corresponding variable in real time. The gallery UI sends these automatically based on the parameter definitions you'll add to the catalog next.

**Important:** The variable names in the `switch` cases must exactly match the `name` field in your catalog entry's `params` array.

## Step 7: The Complete Shader

Here's the full `static/pulse-grid.html` with everything assembled:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Pulse Grid</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; background: #0a0a0a; }
  canvas { display: block; width: 100vw; height: 100vh; }
  .label {
    position: fixed;
    top: 20px;
    left: 24px;
    font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
    font-size: 11px;
    letter-spacing: 0.15em;
    text-transform: uppercase;
    color: rgba(200, 149, 108, 0.5);
    z-index: 10;
    pointer-events: none;
    user-select: none;
  }
</style>
</head>
<body>
<div class="label">Pulse Grid</div>
<canvas id="canvas"></canvas>
<script>
(function() {
  const canvas = document.getElementById('canvas');
  const ctx = canvas.getContext('2d');
  const dpr = Math.min(window.devicePixelRatio || 1, 2);

  let W, H;

  function resize() {
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width = W * dpr;
    canvas.height = H * dpr;
    canvas.style.width = W + 'px';
    canvas.style.height = H + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }

  window.addEventListener('resize', resize);
  resize();

  // ── Mouse/touch tracking ──
  const mouse = { x: -9999, y: -9999, active: false };

  window.addEventListener('mousemove', function(e) {
    mouse.x = e.clientX;
    mouse.y = e.clientY;
    mouse.active = true;
  });
  window.addEventListener('mouseleave', function() {
    mouse.active = false;
  });
  window.addEventListener('touchmove', function(e) {
    mouse.x = e.touches[0].clientX;
    mouse.y = e.touches[0].clientY;
    mouse.active = true;
  }, { passive: true });
  window.addEventListener('touchend', function() {
    mouse.active = false;
  });

  // ── Grid config ──
  var SPACING = 40;
  var BASE_RADIUS = 4;
  var PULSE_SPEED = 1.0;

  // ── Animation ──
  let time = 0;
  let running = true;

  function draw() {
    if (!running) return;

    ctx.fillStyle = '#0a0a0a';
    ctx.fillRect(0, 0, W, H);

    time += 0.02 * PULSE_SPEED;

    const cols = Math.ceil(W / SPACING) + 1;
    const rows = Math.ceil(H / SPACING) + 1;

    for (let row = 0; row < rows; row++) {
      for (let col = 0; col < cols; col++) {
        const x = col * SPACING;
        const y = row * SPACING;

        // Each circle gets a phase offset based on position
        const phase = (col + row) * 0.3;
        const pulse = Math.sin(time + phase);

        // Mouse influence — circles near cursor grow and brighten
        let mouseInfluence = 0;
        if (mouse.active) {
          const dx = x - mouse.x;
          const dy = y - mouse.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          mouseInfluence = Math.max(0, 1 - dist / 150);
        }

        const radius = BASE_RADIUS + pulse * 2 + mouseInfluence * 8;
        const alpha = 0.3 + pulse * 0.2 + mouseInfluence * 0.4;

        ctx.beginPath();
        ctx.arc(x, y, Math.max(0.5, radius), 0, Math.PI * 2);
        ctx.fillStyle = 'rgba(200, 149, 108, ' + Math.min(1, alpha) + ')';
        ctx.fill();
      }
    }

    requestAnimationFrame(draw);
  }

  // Pause when tab is hidden
  document.addEventListener('visibilitychange', function() {
    if (document.hidden) {
      running = false;
    } else {
      running = true;
      requestAnimationFrame(draw);
    }
  });

  requestAnimationFrame(draw);

  // ── Parameter control via postMessage ──
  window.addEventListener('message', function(e) {
    if (e.data && e.data.type === 'param') {
      switch (e.data.name) {
        case 'SPACING': SPACING = e.data.value; break;
        case 'PULSE_SPEED': PULSE_SPEED = e.data.value; break;
      }
    }
  });
})();
</script>
</body>
</html>
```

## Step 8: Register in the Catalog

Open `src/lib/shaders.ts` and add your shader to the `shaders` array:

```ts
{
  id: 'pulse-grid',
  file: 'pulse-grid.html',
  title: 'Pulse Grid',
  desc: 'A breathing grid of circles that ripple with phase-offset sine waves and react to your cursor.',
  tags: ['fill', 'geometric'],
  technique: 'canvas-2d',
  params: [
    { name: 'SPACING', label: 'Grid Spacing', min: 20, max: 80, step: 2, default: 40 },
    { name: 'PULSE_SPEED', label: 'Pulse Speed', min: 0.2, max: 3.0, step: 0.1, default: 1.0 }
  ]
}
```

A few things to get right:

- **`id`** must be URL-safe kebab-case and match your filename (minus `.html`)
- **`tags`** describe the visual style — pick from: `fill`, `object`, `particles`, `physics`, `noise`, `organic`, `geometric`
- **`technique`** is `'canvas-2d'` for Canvas 2D or `'webgl'` for WebGL shaders
- **`params`** define the sliders shown on the detail page — `name` must match the `postMessage` switch cases exactly

## Step 9: Generate Preview Sprites

The gallery uses sprite sheets for the card thumbnails — one vertical strip with 6 frames (one per color scheme). Generate yours:

```bash
# Make sure the dev server is NOT running on the same port
node scripts/generate-previews.mjs --only=pulse-grid
```

This launches a headless browser, renders your shader under each color scheme's CSS filter, and saves `static/previews/pulse-grid.webp`.

## Step 10: Verify

Start the dev server and check everything:

```bash
npm run dev
```

Then verify:

1. **Renders correctly** — Visit `http://localhost:5174/shader/pulse-grid`
2. **Parameters work** — Move the sliders and confirm Grid Spacing and Pulse Speed respond
3. **Mouse interaction** — Hover over the canvas and confirm circles react
4. **Color schemes** — Switch between Amber, Mono, Blue, Rose, Emerald, and Arctic
5. **Performance** — Open DevTools Performance tab, confirm you're hitting 60fps
6. **Gallery preview** — Go to the gallery page, check your preview sprite renders on the card

## Design Tips for Radiant Shaders

**Color palette:** Design in warm amber/gold tones. The gallery applies color schemes via CSS `hue-rotate` filters, so warm base colors produce good results across all 6 schemes. If your shader looks best in a different scheme, set `defaultScheme` in your catalog entry.

**Performance:** Target 60fps on a normal laptop. If you're drawing thousands of elements per frame, consider:
- Reducing draw calls by batching paths
- Using simpler shapes (rectangles are cheaper than arcs)
- Lowering element counts at smaller screen sizes

**Reusability:** Radiant shaders are designed to drop into any website as backgrounds, hero sections, or design assets. Keep them visually flexible — avoid hard-coded positions and rely on the full canvas dimensions.

**Interaction depth:** The mouse/touch interaction should meaningfully affect the visual, not just add a cosmetic overlay. In our Pulse Grid, the cursor physically expands the circles — it feels like touching the surface.

## What's Next?

Now that you know the basics, try these challenges:

- **Add a third parameter** — control the mouse influence radius
- **Use `noise`** — replace the sine wave with Simplex noise for more organic motion (see `flow-field.html` for a noise implementation)
- **Try WebGL** — rewrite the shader using fragment shaders for GPU-powered rendering
- **Add color variation** — give each circle a slightly different hue based on its grid position

Explore the existing shaders in `static/` for inspiration. Each one is self-contained and readable.
