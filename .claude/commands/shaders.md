# Shader Reimagination for $ARGUMENTS

You are reimagining the shader(s) inspired by **$ARGUMENTS** in this project.

## Context

Read `src/lib/shaders.ts` to find the existing shader entry (or entries) for this celebrity. Read the corresponding HTML file(s) in `static/` to understand what currently exists.

Also read 3-4 of the strongest existing shaders for reference on quality bar. The original non-celebrity shaders (01 through 09) are generally strong: flow field, topographic, generative tree, strange attractor, pendulum wave, phyllotaxis, fluid amber. Read at least 2 of those HTML files to calibrate your quality standard.

## Process

### Step 1: Celebrity Vibe Analysis

Think deeply about **$ARGUMENTS**:
- Their artistic identity, aesthetic, energy, cultural significance
- Visual motifs, textures, colors, moods associated with them
- What makes them *them* — not surface-level, but the essence

Write a short (3-5 sentence) vibe summary.

### Step 2: Generate 50 Shader Ideas

Brainstorm 50 shader concepts inspired by this celebrity. Each idea should:
- Be a technically interesting generative animation (on par with flow fields, strange attractors, fluid simulations, pendulum waves — not just "pretty colors")
- Have a clear connection to the celebrity's vibe (but abstract/artistic, not literal)
- Be feasible as a single self-contained HTML file with Canvas 2D or WebGL
- Have a evocative name (2-3 words)
- **Have high sharability potential** — think about designers and developers who would want to embed these on their own websites, apps, landing pages, or portfolios. The best shaders are ones people see and immediately think "I need this on my site." Prioritize visual impact, versatility as a background/accent, and broad aesthetic appeal over niche or overly literal concepts.

Present the full unranked list of 50 with one-line descriptions. Do NOT rank them yet.

### Step 2b: Rank the Top 5

Launch a sub-agent (using the Agent tool) whose sole job is to critically evaluate and rank the 50 ideas from Step 2. The agent should:
- Consider technical feasibility, visual impact, sharability potential, distinctiveness from each other, and connection to the celebrity's vibe
- Eliminate ideas that are too similar to existing shaders already in `shaders.ts`
- Pick the **top 5** that are most distinct from each other and would make the strongest set
- Return the ranked top 5 with a brief justification for each pick

Wait for the agent to complete and use its top 5 selection for the next step. This separation ensures genuine critical reasoning rather than just sorting the same list that was brainstormed.

### Step 3: Build Top 5

Build the top 5 shader ideas (as selected by the ranking agent) as complete, working HTML files. For each:

1. Create the HTML file in `static/` following the existing naming convention (use the existing file number prefix from `shaders.ts` since filenames are already set — if there's only one existing shader for this celeb, create the new ones with temporary filenames like `static/proposal-CELEB-1.html` through `static/proposal-CELEB-5.html`)
2. Follow the project conventions exactly:
   - Single HTML file: `<style>` + `<canvas id="canvas">` + `<script>` IIFE
   - Dark background (#0a0a0a)
   - Fixed `.label` div with shader name
   - `requestAnimationFrame` loop
   - Pause when not visible (`visibilitychange` or `IntersectionObserver`)
   - Support `postMessage` for params: `window.addEventListener('message', ...)`
   - Define 2 tunable params with sensible defaults
   - Canvas fills viewport, handles resize
3. The animation must be **visually stunning and technically sophisticated**. No simple particle systems or basic noise. Think: interesting algorithms, emergent behavior, mathematical beauty.
4. Each shader should look DISTINCT from the others — don't make 5 variations of the same idea.
5. **Design for sharability**: Each shader should work beautifully as a website background, hero section, loading screen, or decorative element. It should look intentional and polished — something a designer would proudly ship. Avoid anything that looks like a tech demo or science experiment. The goal is generative *art* that doubles as a *design asset*.
6. **Performance is critical**: Every shader must run at a smooth 60fps on normal laptops (e.g. a MacBook Air or mid-range Windows laptop). Optimize aggressively — minimize per-pixel work, avoid expensive loops, use efficient algorithms, cap particle counts, and prefer GPU-friendly approaches (WebGL fragment shaders) over CPU-heavy Canvas 2D when possible. A beautiful shader that stutters is worse than a simpler one that runs buttery smooth.

### Step 4: Visual QA via Browser

After building each shader, visually verify it using the Chrome browser automation tools:

1. Open each shader's standalone HTML file in Chrome (e.g. `http://localhost:5174/proposal-CELEB-1.html` or whatever the dev server URL is)
2. Take a screenshot and evaluate:
   - **Is it rendering at all?** (not just a black screen or error)
   - **Is it visually interesting?** (not just random noise or a static image)
   - **Is the animation smooth?** (check console for errors with `mcp__claude-in-chrome__read_console_messages`)
   - **Does it match the concept?** (does it evoke what was intended?)
3. If a shader has issues — blank screen, console errors, ugly output, boring result — **fix it and re-check**. Iterate until it looks good.
4. If after 2-3 fix attempts a shader still isn't working well, scrap it and build the next idea from the ranked list instead.

Do NOT skip this step. Every shader presented to the user must be visually confirmed as working and looking good.

### Step 5: Register and Present

Add all 5 final (QA-passed) proposals to the `shaders` array in `src/lib/shaders.ts` with appropriate metadata (id, file, title, desc, tags, params, inspiration).

Then tell the user:
- List all 5 proposals with their names and descriptions
- Suggest they view each at the dev server URL to evaluate
- Ask which ones to keep and which to discard

## Important Notes

- Build all 5 shaders in parallel using agents when possible
- The quality bar is HIGH — these should be portfolio-worthy generative art pieces that designers and developers would want to use on their own sites
- Think "sharable design asset" not "tech demo" — every shader should make someone think "I want this on my website"
- If the existing shader for this celebrity is already good, say so and ask if the user still wants alternatives
- **60fps or bust** — every shader must perform smoothly on normal laptops. Profile mentally before building: if the algorithm requires expensive per-pixel computation, use WebGL. Cap particle counts, avoid nested loops, and keep draw calls minimal.
- Warm amber accent palette (rgba(200, 149, 108, ...)) is the project default but celebrity shaders can use their own palette if it fits the vibe
