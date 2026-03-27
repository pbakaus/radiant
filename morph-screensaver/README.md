# Morph Screensaver

Native macOS screensaver using Metal. Port of the [morph-webgpu](../src/routes/morph-webgpu/) shader.

## Build & Install

```bash
make build      # Compile → build/MorphSS*.saver
make install    # Copy to ~/Library/Screen Savers/, kill caches
make test       # Install + open System Settings > Screen Saver
make uninstall  # Remove from ~/Library/Screen Savers/
make clean      # Delete build/
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## Architecture

- **`Sources/Shaders.metal`** — Full Metal fragment shader: simplex noise, FBM, domain warping, orbs, waves, fabric fold, voronoi, chladni, spiral, moire, burn, kaleidoscope, lighting, ACES tonemap, chromatic aberration, colour patches, grain, vignette.
- **`Sources/MorphScreenSaverView.swift`** — `ScreenSaverView` subclass with `CAMetalLayer`. 10 presets, power-8 winner-take-all blending, incommensurate sine drift.
- **`Makefile`** — Universal binary (arm64 + x86_64), Metal precompilation with source fallback, ad-hoc codesign.

## How It Works

Ten procedural presets drift between each other using power-8 winner-take-all blending driven by incommensurate sine sums (no grid boundaries, no visible transitions). Each preset activates a different combination of visual features. The animation runs at quarter speed for organic, slow-moving visuals.

## Troubleshooting

- **Log file:** `~/morph-screensaver.log` — the screensaver sandbox suppresses NSLog, so all diagnostics go here.
- **Not appearing in System Settings:** Run `make install` again. macOS caches screensaver bundles aggressively; the Makefile kills `legacyScreenSaver` and `WallpaperAgent` to force a refresh.
- **Black screen:** Check the log file for Metal device or shader compilation errors.
