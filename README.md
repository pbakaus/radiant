<p align="center">
  <img src="https://radiant-shaders.com/radiant-logo.svg" alt="Radiant" width="120">
</p>

<h1 align="center">Radiant</h1>

<p align="center">
  <strong>Open source shaders and visual effects for the web.</strong><br>
  Drop-in canvas animations — zero dependencies, zero build step.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/shaders-94-c8956c" alt="94 shaders">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <a href="https://radiant-shaders.com"><img src="https://img.shields.io/badge/live_gallery-radiant--shaders.com-c8956c" alt="Live Gallery"></a>
</p>

<p align="center">
  <a href="https://radiant-shaders.com">
    <img src="https://radiant-shaders.com/og-image.png" alt="Radiant Gallery" width="680">
  </a>
</p>

---

## Quick Start

Every shader is a self-contained HTML file — `<style>` + `<canvas>` + `<script>`. No framework, no bundler, no runtime. Use them anywhere.

### 1. Pick a shader

Browse the [gallery](https://radiant-shaders.com) or download the [shader pack](https://radiant-shaders.com/radiant-shaders.zip). You can also grab individual files from the `static/` directory in this repo.

### 2. Embed it

```html
<iframe
  src="event-horizon.html"
  style="position: fixed; inset: 0; width: 100%; height: 100%; border: 0; z-index: -1;"
></iframe>
```

That's it — a full-screen animated background in one tag.

### 3. Control it at runtime

Shaders accept live parameter updates through `postMessage`:

```js
const iframe = document.querySelector('iframe');

// Adjust any parameter on the fly
iframe.contentWindow.postMessage(
  { type: 'param', name: 'ROTATION_SPEED', value: 0.6 },
  '*'
);
```

Each shader's parameters (name, range, default) are listed in [`src/lib/shaders.ts`](src/lib/shaders.ts).

## Use Cases

- **Website backgrounds** — full-viewport ambient animation behind your content
- **Hero sections** — eye-catching landing page visuals
- **Presentations** — animated slides and speaker backdrops
- **Digital signage** — lobby screens, event displays
- **Creative coding** — remix, fork, and learn from real Canvas 2D and WebGL techniques

## What's Inside

94 shaders across Canvas 2D and WebGL, organized by visual style:

| Tag | Description |
|-----|-------------|
| `fill` | Full-canvas effects (backgrounds, textures) |
| `object` | Standalone centered elements |
| `particles` | Particle systems and swarms |
| `physics` | Physics simulations (springs, waves, gravity) |
| `noise` | Perlin/simplex noise-driven visuals |
| `organic` | Fluid, biological, and natural forms |
| `geometric` | Hard-edged patterns and tessellations |

Every shader includes:
- Mouse/touch interaction
- Tunable parameters via `postMessage`
- Visibility-based pause (saves battery)
- DPR-aware rendering (capped at 2x)
- 60fps targeting on standard hardware

## Color Schemes

The gallery supports 6 color schemes applied via CSS `filter` on the iframe — no shader modification needed:

| Scheme | Filter |
|--------|--------|
| **Amber** (default) | `none` |
| **Mono** | `grayscale(1)` |
| **Blue** | `hue-rotate(175deg)` |
| **Rose** | `hue-rotate(300deg) saturate(1.1)` |
| **Emerald** | `hue-rotate(90deg) saturate(1.2)` |
| **Arctic** | `hue-rotate(180deg) saturate(0.5) brightness(1.1)` |

## Development

```sh
npm install
npm run dev       # Start dev server
npm run build     # Production build
npm run check     # TypeScript + Svelte checks
```

The gallery frontend is SvelteKit 2 + Svelte 5. Shaders themselves require no build step.

## Contributing

See [CONTRIBUTORS.md](CONTRIBUTORS.md) for local development setup, conventions, and how to add new shaders.

## License

[MIT](LICENSE) — Copyright (c) 2025 Paul Bakaus

Use these shaders in personal projects, commercial products, client work — whatever you want. Attribution is appreciated but not required.
