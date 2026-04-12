# Radiant Tweet Calendar

Schedule and template for posting one shader highlight video to X, 3× per week.
Not automated: Paul posts manually, Claude drafts the tweet on request via `/next-tweet`.

## Workflow

When it's time for a new post, run:

```
/next-tweet
```

(Or `/next-tweet 15` to force a specific post, or `/next-tweet event-horizon` to target by id.)

Claude will:

1. Find the next unchecked post in this file
2. Pull the shader's `desc` and metadata from `src/lib/shaders.ts`
3. Pull the inspiration intro from `src/lib/inspiration-intros.ts`
4. Render a tweet using the template below
5. Tell Paul which video file to attach from `videos/`

Then Paul pastes the tweet, attaches the video, posts, and ticks the checkbox below.

## Cadence

- 3× per week, Mon / Wed / Fri
- Schedule starts Mon 2026-04-13 (shift by rewriting dates if needed)
- 87 posts, 29 weeks, runs through 2026-10-30
- After 87, either loop back with fresh captions or seed with new shaders

## Video format for X

**Default: `square` (1080x1080).** Most Radiant shaders are designed to fill a viewport or look good centered. Cropping to 9:16 reel forces awkward framing on shaders with edge-important detail. Square crops cleanly on every device, works in-feed and on profile views, and respects how the shaders were composed.

Other formats are available if a specific shader calls for it:

- `landscape` (1920x1080, 16:9): for shaders with strong horizontal composition
- `reel` (1080x1920, 9:16): only for shaders that were deliberately designed to fill vertical space

Generate per shader with:

```bash
node scripts/generate-videos.mjs --shader=<id> --format=square
```

## Caption template

Tasteful minimalism. Three parts only. No promotional copy, no hashtags, no call to action.

```
{HOOK}

{INSPIRATION_LINE}

https://radiant-shaders.com/shader/{id}
```

For shaders without an inspiration, drop the middle line entirely. The tweet becomes hook plus URL.

### Field rules

**HOOK** is 1 sentence or fragment, roughly 70 to 130 characters. Present tense, active voice. Sharpen the shader's `desc` from `shaders.ts`, do not paste verbatim. Cut adjectives, pick specific verbs, drop generic nouns.

Prefer verb-first or noun-phrase openers ("Raytraced black hole bending...", "Flocking particles forming..."). Banned openers: "A stunning...", "A beautiful..." and anything else that reads as filler praise. Banned words anywhere: "stunning", "beautiful", "mesmerizing", "mind-blowing". Let the video do that.

One "how" detail is plenty (the technique that makes it impressive). Do not cram in every feature.

**INSPIRATION_LINE** must start with `Inspired by` so cold readers on X understand the framing without knowing the account concept. Three words in, they should already know this is a visual tribute to someone. Forms, in order of preference:

- `Inspired by {Name}'s {3 to 6 word aesthetic phrase}.` (preferred when the phrase fits a possessive)
- `Inspired by {Name}. {Aesthetic phrase as standalone sentence}.` (when the phrase does not fit a possessive)
- `Inspired by {Name}.` (when no phrase feels right at all)

The aesthetic phrase comes from compressing the celebrity's entry in `inspiration-intros.ts`. Name the aesthetic, do not gush. Good: `Inspired by The Weeknd at 3 AM.`, `Inspired by Margot Robbie's weaponized sunlight.`, `Inspired by Jack Black's volcanic joy.` Bad: anything that reads as fan praise, art criticism, or design jargon ("monastic calm", "elemental cool", "architectural gold").

**URL** is the bare shader page URL, no arrow, no prefix. `https://radiant-shaders.com/shader/{id}`.

### Hard rules

- **NEVER use em dashes (—) in tweets.** Use commas, periods, colons, or restructure. This is non-negotiable.
- **NEVER use hashtags.**
- **NEVER use promotional copy** like "Free and open source", "Drop into any site", "Check it out".
- Keep the whole tweet under 280 literal characters. With this template you have lots of headroom.

## Worked examples

These three are calibration: what "done" looks like.

### Post 01, event-horizon (The Weeknd)

```
Raytraced black hole bending light around its accretion disk, running live in your browser.

Inspired by The Weeknd's neon loneliness at cosmic scale.

https://radiant-shaders.com/shader/event-horizon
```

**Attach:** `videos/event-horizon-square.mp4`.

### Post 02, liquid-gold (Margot Robbie)

```
Molten gold flowing with real surface tension and PBR metallic reflections.

Inspired by Margot Robbie's weaponized sunlight.

https://radiant-shaders.com/shader/liquid-gold
```

**Attach:** needs generation first, `node scripts/generate-videos.mjs --shader=liquid-gold --format=square`.

### Post 03, murmuration (Anne Hathaway)

```
Thousands of flocking particles forming flowing ribbons of density against a twilight sky.

Inspired by Anne Hathaway's alarming vulnerability.

https://radiant-shaders.com/shader/murmuration
```

**Attach:** needs generation first, `node scripts/generate-videos.mjs --shader=murmuration --format=square`.

## Ordering rationale

- **Posts 1 through 10** are the strongest scroll stoppers: cinematic, photorealistic, or visually iconic effects that reward a 3 second glance. Bank credibility first.
- **Celebrity spacing:** no inspiration repeats within 6 posts (2 weeks). Celebrities with 4 shaders appear roughly every 15 to 25 posts. 1-shader celebrities each appear once in their natural slot.
- **Technique alternation:** WebGL and Canvas 2D are interleaved so the feed does not feel visually uniform.
- **Tag variety:** adjacent posts avoid the same primary tag (three `fill/noise/organic` in a row would blur together).
- **No-inspiration shaders** (7 total) are spaced roughly every 12 posts as pure-craft palate cleansers.

---

## Ban list

These shaders are excluded from posting until reworked. Do not schedule them or draft tweets for them.

- `murmuration` — doesn't read well in square video, slider rendering broken
- `diamond-caustics` — needs visual rework

## Schedule

Tick the checkbox after posting. Format: `post · date · \`id\` "Title" (Inspiration, technique)`.

### April 2026

- [ ] 01 · 2026-04-13 Mon · `event-horizon` "Event Horizon" (The Weeknd, webgl)
- [ ] 02 · 2026-04-15 Wed · `liquid-gold` "Liquid Gold" (Margot Robbie, webgl)
- [ ] 03 · 2026-04-17 Fri · `chromatic-bloom` "Chromatic Bloom" (Lady Gaga, webgl)
- [ ] 04 · 2026-04-20 Mon · `aurora-veil` "Aurora Veil" (Cate Blanchett, webgl)
- [ ] 05 · 2026-04-22 Wed · `rain-on-glass` "Rain on Glass" (Rihanna, webgl)
- [ ] 06 · 2026-04-24 Fri · `magma-core` "Magma Core" (Jack Black, webgl)
- [ ] 07 · 2026-04-27 Mon · `fluid-amber` "Fluid Amber" (webgl)
- [ ] 08 · 2026-04-29 Wed · `lipstick-smear` "Lipstick Smear" (Chappell Roan, webgl)

### May 2026

- [ ] 09 · 2026-05-01 Fri · `digital-rain` "Digital Rain" (Keanu Reeves, canvas-2d)
- [ ] 10 · 2026-05-04 Mon · `gilded-fracture` "Gilded Fracture" (Beyoncé, webgl)
- [ ] 11 · 2026-05-06 Wed · `murmuration` "Murmuration" (Anne Hathaway, canvas-2d)
- [ ] 12 · 2026-05-08 Fri · `strange-attractor` "Strange Attractor (Lorenz)" (canvas-2d)
- [ ] 13 · 2026-05-11 Mon · `diamond-caustics` "Diamond Caustics" (Rihanna, webgl)
- [ ] 14 · 2026-05-13 Wed · `bioluminescence` "Bioluminescence" (Zendaya, webgl)
- [ ] 15 · 2026-05-15 Fri · `thunder-sermon` "Thunder Sermon" (The Weeknd, webgl)
- [ ] 16 · 2026-05-18 Mon · `clockwork-mind` "Clockwork Mind" (Robert Downey Jr., canvas-2d)
- [ ] 17 · 2026-05-20 Wed · `champagne-fizz` "Champagne Fizz" (Sabrina Carpenter, canvas-2d)
- [ ] 18 · 2026-05-22 Fri · `neon-drive` "Neon Drive" (Ryan Gosling, webgl)
- [ ] 19 · 2026-05-25 Mon · `aurora-curtain` "Aurora Curtain" (Meryl Streep, webgl)
- [ ] 20 · 2026-05-27 Wed · `metamorphosis` "Metamorphosis" (Lady Gaga, webgl)
- [ ] 21 · 2026-05-29 Fri · `vinyl-grooves` "Vinyl Grooves" (Laufey, webgl)

### June 2026

- [ ] 22 · 2026-06-01 Mon · `hologram-glitch` "Hologram Glitch" (Daft Punk, webgl)
- [ ] 23 · 2026-06-03 Wed · `gothic-filigree` "Gothic Filigree" (Jenna Ortega, webgl)
- [ ] 24 · 2026-06-05 Fri · `tropical-heat` "Tropical Heat" (Bad Bunny, webgl)
- [ ] 25 · 2026-06-08 Mon · `moonlit-ripple` "Moonlit Ripple" (SZA, webgl)
- [ ] 26 · 2026-06-10 Wed · `sequin-wave` "Sequin Wave" (Taylor Swift, webgl)
- [ ] 27 · 2026-06-12 Fri · `woven-radiance` "Woven Radiance" (Lupita Nyong'o, canvas-2d)
- [ ] 28 · 2026-06-15 Mon · `gilt-mosaic` "Gilt Mosaic" (Beyoncé, webgl)
- [ ] 29 · 2026-06-17 Wed · `crystal-lattice` "Crystal Lattice" (Anne Hathaway, webgl)
- [ ] 30 · 2026-06-19 Fri · `glitter-storm` "Glitter Storm" (Chappell Roan, canvas-2d)
- [ ] 31 · 2026-06-22 Mon · `rain-umbrella` "Rain on Umbrella" (Rihanna, webgl)
- [ ] 32 · 2026-06-24 Wed · `kinetic-grid` "Kinetic Grid" (Dua Lipa, canvas-2d)
- [ ] 33 · 2026-06-26 Fri · `smolder` "Smolder" (Pedro Pascal, webgl)
- [ ] 34 · 2026-06-29 Mon · `ink-dissolve` "Ink Dissolve" (Billie Eilish, webgl)

### July 2026

- [ ] 35 · 2026-07-01 Wed · `sacred-strange` "Sacred Strange" (Benedict Cumberbatch, webgl)
- [ ] 36 · 2026-07-03 Fri · `silk-groove` "Silk Groove" (Bruno Mars, webgl)
- [ ] 37 · 2026-07-06 Mon · `flow-field` "Flow Field with Particle Trails" (canvas-2d)
- [ ] 38 · 2026-07-08 Wed · `stardust-veil` "Stardust Veil" (Ariana Grande, webgl)
- [ ] 39 · 2026-07-10 Fri · `shifting-veils` "Shifting Veils" (Meryl Streep, webgl)
- [ ] 40 · 2026-07-13 Mon · `feedback-loop` "Feedback Loop" (Daft Punk, webgl)
- [ ] 41 · 2026-07-15 Wed · `edge-of-chaos` "Edge of Chaos" (Robert Downey Jr., webgl)
- [ ] 42 · 2026-07-17 Fri · `polaroid-burn` "Polaroid Burn" (Olivia Rodrigo, webgl)
- [ ] 43 · 2026-07-20 Mon · `kaleidoscope-runway` "Kaleidoscope Runway" (Zendaya, webgl)
- [ ] 44 · 2026-07-22 Wed · `burning-film` "Burning Film" (The Weeknd, webgl)
- [ ] 45 · 2026-07-24 Fri · `velvet-spotlight` "Velvet Spotlight" (Anne Hathaway, canvas-2d)
- [ ] 46 · 2026-07-27 Mon · `neon-drip` "Neon Drip" (Bad Bunny, webgl)
- [ ] 47 · 2026-07-29 Wed · `jazz-chaos` "Jazz Chaos" (Jeff Goldblum, canvas-2d)
- [ ] 48 · 2026-07-31 Fri · `eclipse-glow` "Eclipse Glow" (SZA, webgl)

### August 2026

- [ ] 49 · 2026-08-03 Mon · `shattered-plains` "Shattered Plains" (Brandon Sanderson, webgl)
- [ ] 50 · 2026-08-05 Wed · `vortex` "Vortex" (Lupita Nyong'o, webgl)
- [ ] 51 · 2026-08-07 Fri · `tesseract-shadow` "Tesseract Shadow" (Benedict Cumberbatch, canvas-2d)
- [ ] 52 · 2026-08-10 Mon · `signal-decay` "Signal Decay" (Billie Eilish, webgl)
- [ ] 53 · 2026-08-12 Wed · `rubber-reality` "Rubber Reality" (Jim Carrey, canvas-2d)
- [ ] 54 · 2026-08-14 Fri · `voltage-arc` "Voltage Arc" (Bad Bunny, webgl)
- [ ] 55 · 2026-08-17 Mon · `painted-strata` "Painted Strata" (Laufey, webgl)
- [ ] 56 · 2026-08-19 Wed · `pendulum-wave` "Pendulum Wave" (canvas-2d)
- [ ] 57 · 2026-08-21 Fri · `silk-cascade` "Silk Cascade" (Ariana Grande, webgl)
- [ ] 58 · 2026-08-24 Mon · `laser-precision` "Laser Precision" (Ana de Armas, canvas-2d)
- [ ] 59 · 2026-08-26 Wed · `magnetic-field` "Magnetic Field" (Cate Blanchett, webgl)
- [ ] 60 · 2026-08-28 Fri · `vertigo` "Vertigo" (The Weeknd, webgl)
- [ ] 61 · 2026-08-31 Mon · `topographic` "Topographic Contour Map" (canvas-2d)

### September 2026

- [ ] 62 · 2026-09-02 Wed · `gilt-thread` "Gilt Thread" (Bruno Mars, webgl)
- [ ] 63 · 2026-09-04 Fri · `neon-revival` "Neon Revival" (Chappell Roan, webgl)
- [ ] 64 · 2026-09-07 Mon · `moire-interference` "Moiré Interference" (Benedict Cumberbatch, webgl)
- [ ] 65 · 2026-09-09 Wed · `vintage-static` "Vintage Static" (Harry Styles, canvas-2d)
- [ ] 66 · 2026-09-11 Fri · `chladni-resonance` "Chladni Resonance" (Laufey, webgl)
- [ ] 67 · 2026-09-14 Mon · `strobe-geometry` "Strobe Geometry" (Dua Lipa, webgl)
- [ ] 68 · 2026-09-16 Wed · `scream-wave` "Scream Wave" (Olivia Rodrigo, webgl)
- [ ] 69 · 2026-09-18 Fri · `radiant-geometry` "Radiant Geometry" (Beyoncé, webgl)
- [ ] 70 · 2026-09-21 Mon · `magnetic-sand` "Magnetic Sand" (Ana de Armas, canvas-2d)
- [ ] 71 · 2026-09-23 Wed · `ink-calligraphy` "Ink Calligraphy" (Anne Hathaway, canvas-2d)
- [ ] 72 · 2026-09-25 Fri · `artpop-iridescence` "Artpop Iridescence" (Lady Gaga, webgl)
- [ ] 73 · 2026-09-28 Mon · `luminous-silt` "Luminous Silt" (Lupita Nyong'o, canvas-2d)
- [ ] 74 · 2026-09-30 Wed · `phase-transition` "Phase Transition" (Benedict Cumberbatch, canvas-2d)

### October 2026

- [ ] 75 · 2026-10-02 Fri · `dither-gradient` "Dither Gradient" (Daft Punk, webgl)
- [ ] 76 · 2026-10-05 Mon · `torn-paper` "Torn Paper" (Olivia Rodrigo, webgl)
- [ ] 77 · 2026-10-07 Wed · `resonant-strings` "Resonant Strings" (Laufey, canvas-2d)
- [ ] 78 · 2026-10-09 Fri · `sugar-glass` "Sugar Glass" (Sabrina Carpenter, webgl)
- [ ] 79 · 2026-10-12 Mon · `generative-tree` "Generative Branching Tree" (canvas-2d)
- [ ] 80 · 2026-10-14 Wed · `laser-labyrinth` "Laser Labyrinth" (Dua Lipa, webgl)
- [ ] 81 · 2026-10-16 Fri · `golden-throne` "Golden Throne" (Beyoncé, webgl)
- [ ] 82 · 2026-10-19 Mon · `synth-ribbon` "Synth Ribbon" (Chappell Roan, canvas-2d)
- [ ] 83 · 2026-10-21 Wed · `lens-whisper` "Lens Whisper" (Ryan Gosling, webgl)
- [ ] 84 · 2026-10-23 Fri · `analog-drift` "Analog Drift" (Daft Punk, canvas-2d)
- [ ] 85 · 2026-10-26 Mon · `spark-chamber` "Spark Chamber" (Robert Downey Jr., canvas-2d)
- [ ] 86 · 2026-10-28 Wed · `phyllotaxis` "Phyllotaxis Spiral" (canvas-2d)
- [ ] 87 · 2026-10-30 Fri · `bass-ripple` "Bass Ripple" (Dua Lipa, webgl)
