# Shaders

A collection of standalone canvas-based generative animations with a SvelteKit gallery frontend.

## Stack

- **Gallery**: SvelteKit 2 + Svelte 5, TypeScript, Vite
- **Shaders**: Standalone HTML files in `static/`, no build step. Each is self-contained with inline JS.
- **Rendering**: Mix of Canvas 2D and WebGL. No external dependencies.

## Structure

```
src/routes/+page.svelte        — Homepage with featured grid
src/routes/gallery/             — Gallery pages with filtering
src/routes/shader/[id]/         — Individual shader detail pages
static/*.html                   — Standalone shader pages
src/lib/shaders.ts              — Shader catalog metadata (ALL shader entries)
src/lib/color-schemes.ts        — 6 color scheme definitions
scripts/generate-previews.mjs   — Preview sprite sheet generator
static/previews/*.webp          — Generated preview sprites for gallery cards
```

## Commands

- `npm run dev` — Dev server
- `npm run build` — Production build
- `node scripts/generate-previews.mjs` — Generate all preview sprites
- `node scripts/generate-previews.mjs --only=shader-id` — Generate preview for one shader
- `node scripts/generate-videos.mjs --shader=shader-id` — Generate highlight video for one shader
- `node scripts/generate-videos.mjs --shader=shader-id --format=reel` — Generate 9:16 vertical reel
- `node scripts/generate-videos.mjs --all` — Generate videos for all shaders
  - Formats: `landscape` (1920x1080, default), `reel` (1080x1920), `square` (1080x1080)
  - Additional flags: `--fps=60`, `--output=dir` (default: `videos/`), `--no-captions`
  - Requires `puppeteer` and `ffmpeg`

## Conventions

- Each shader is a single HTML file: `<style>` + `<canvas id="canvas">` + `<script>` IIFE
- Label format: shader name in a fixed `.label` div
- Dark background (#0a0a0a), warm amber accent palette (rgba(200, 149, 108, ...))
- Respect `prefers-reduced-motion` where applicable
- Use `visibilitychange` to pause when offscreen
- Target 60fps on normal laptops — if a technique can't hit 60fps, use a different technique
- Shaders must be highly reusable — designed to drop into any website as a background, hero section, or design asset

## Adding a new shader

Every new shader requires ALL of the following:

### 1. Create the HTML file
Create `static/shader-name.html` following the existing format:
- Single HTML file: `<style>` + `<canvas id="canvas">` + `<script>` IIFE
- Dark background (#0a0a0a)
- Fixed `.label` div with shader name
- `requestAnimationFrame` loop with `visibilitychange` pause
- Handle canvas resize with DPR (capped at 2)

### 2. Add mouse/touch interaction
All shaders must respond to user input:
- `mousemove` / `touchmove` for cursor tracking
- `mouseleave` / `touchend` to reset
- The interaction should meaningfully affect the visual (not just cosmetic)

### 3. Expose tunable parameters
Define 2+ parameters controllable via `postMessage`:
```js
window.addEventListener('message', function(e) {
  if (e.data && e.data.type === 'param') {
    switch (e.data.name) {
      case 'PARAM_NAME': paramValue = e.data.value; break;
    }
  }
});
```

### 4. Support color schemes
The gallery uses 6 color schemes applied via CSS `filter` on the iframe:
- **Amber** (default): `filter: none` — shader renders in its native colors
- **Mono**: `grayscale(1)`
- **Blue**: `hue-rotate(175deg)`
- **Rose**: `hue-rotate(300deg) saturate(1.1)`
- **Emerald**: `hue-rotate(90deg) saturate(1.2)`
- **Arctic**: `hue-rotate(180deg) saturate(0.5) brightness(1.1)`

Since schemes work via hue-rotate, design native colors in warm/amber tones so other schemes produce good results. If a shader looks best in a non-amber scheme, set `defaultScheme` in its catalog entry.

### 5. Add inspiration metadata (if new celebrity)
If the shader is inspired by someone NOT already in the project, add entries to:
- `src/lib/inspiration-intros.ts` — keyed by slug (e.g. `'daft-punk'`), a 3-4 sentence poetic description of the celebrity's artistic identity and associated color palette
- `src/lib/inspiration-palettes.ts` — keyed by slug, with `primary` (hex for card border tint) and `colors` (2-4 hex colors for ambient glow on the inspiration gallery page)

### 6. Register in the catalog
Add an entry to the `shaders` array in `src/lib/shaders.ts`:
```ts
{
  id: 'shader-name',           // URL-safe kebab-case
  file: 'shader-name.html',    // filename in static/
  title: 'Shader Name',        // display name
  desc: 'Description.',        // one-line description
  inspiration: 'Celebrity',    // optional celebrity inspiration
  tags: ['fill', 'noise'],     // from: fill, object, particles, physics, noise, organic, geometric
  technique: 'webgl',          // 'webgl' or 'canvas-2d'
  defaultScheme: 'blue',       // optional: override default color scheme
  params: [
    { name: 'PARAM_NAME', label: 'Param Label', min: 0, max: 2, step: 0.1, default: 1.0 }
  ]
}
```

### 7. Generate preview sprites
Run the preview generator to create gallery card thumbnails:
```bash
node scripts/generate-previews.mjs --only=shader-name
```
This creates `static/previews/shader-name.webp` — a vertical sprite sheet with 6 frames (one per color scheme). Requires the dev server to NOT be running on the same port.

### 8. Verify
- Open `http://localhost:5173/shader/shader-name` and check it renders correctly
- Test all parameters via the detail page sliders
- Test mouse/touch interaction
- Verify 60fps performance
- Check that color scheme switching works (amber, blue, etc.)
- Verify the preview sprite shows correctly in the gallery grid
