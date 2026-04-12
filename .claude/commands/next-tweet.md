# Prep next Radiant tweet, $ARGUMENTS

Draft the next scheduled tweet for the Radiant shaders X account. One-shot render: gather data, render the tweet, present it. Do not ask questions, do not modify files, do not show scratchwork.

## Step 1: Pick the target post

The user passed: `$ARGUMENTS`

- **Empty**: read `docs/tweet-calendar.md`, scan the Schedule section, find the first unchecked row (`- [ ] NN · ...`). That is the target.
- **A number** (e.g. `15`): find the row matching post number `15` regardless of checkbox state.
- **A shader id** (e.g. `event-horizon`): find the row containing that shader id.

Extract: post number (NN), date, shader id, title, inspiration (or none), technique.

If nothing matches, stop and tell the user.

## Step 2: Gather shader data

Read `src/lib/shaders.ts`, find the entry where `id` matches. Pull:

- `desc`: raw material for the hook (sharpen, don't paste verbatim)
- `inspiration`: full celebrity name (if any)

If the shader has an `inspiration`, read `src/lib/inspiration-intros.ts` and pull the entry for that celebrity (keyed by kebab-case slug: "Robert Downey Jr." becomes `robert-downey-jr`, "Lupita Nyong'o" becomes `lupita-nyong-o`, "The Weeknd" becomes `the-weeknd`, "Beyoncé" becomes `beyonce`, "Jeff Goldblum" becomes `jeff-goldblum`). Compress this intro to a 3 to 6 word aesthetic phrase for the INSPIRATION_LINE.

## Step 3: Check for an existing video

Look in `videos/` for, in order of preference:

1. `{id}-square.mp4` (preferred default, most shaders weren't designed for vertical crop)
2. `{id}-landscape.mp4`
3. `{id}-reel.mp4`

Pick the first that exists. If none exist, the user needs to run:

```
node scripts/generate-videos.mjs --shader={id} --format=square
```

## Step 4: Render the tweet

Tasteful minimalism. Three parts. Nothing else.

```
{HOOK}

{INSPIRATION_LINE}

https://radiant-shaders.com/shader/{id}
```

No promotional copy. No hashtags. No call to action. No arrow before the URL. Let the content and the link speak for themselves.

### HOOK rules

- 1 sentence or fragment, roughly 70 to 130 characters
- Present tense, active voice
- Sharpen the shader's `desc`: cut adjectives, pick specific verbs, drop generic nouns
- Prefer verb-first or noun-phrase openers ("Raytraced black hole bending...", "Flocking particles forming..."). Filler adjective openers are banned ("A stunning...", "A beautiful..."). Factual "A raytraced..." is fine.
- Never use "stunning", "beautiful", "mesmerizing", "mind-blowing". Let the video do that.
- One "how" detail is plenty. Do not cram in every feature.
- **NEVER use em dashes (—).** Use commas, periods, colons, or restructure. This is non-negotiable.

### INSPIRATION_LINE rules

The line must start with `Inspired by` so cold readers on X understand the framing without having to know the account concept. Three words in, they should already know this is a visual tribute to someone.

- **With inspiration:** `Inspired by {Name}'s {3 to 6 word aesthetic phrase}.` or `Inspired by {Name} {situational phrase}.`
  - Examples: `Inspired by The Weeknd at 3 AM.`, `Inspired by Margot Robbie's weaponized sunlight.`, `Inspired by Jack Black's volcanic joy.`
  - Use plain, accessible language. No art-critic vocabulary, no design jargon, no $5 words. If a phrase needs a liberal arts degree to parse, rewrite it. "Icy glow" over "elemental cool". "Quiet focus" over "monastic calm". "Hot-pink everything" over "hot-pink maximalism".
  - Do not gush, do not hero-worship.
  - If no phrase feels right, just write `Inspired by {Name}.`
  - If no phrase feels right at all, just write `Inspired by {Name}.`
- **No inspiration:** omit this line entirely. The tweet becomes two parts (hook and URL). Do not insert filler. The hook itself describes a generative visual, which is self-explanatory without framing.

### Character budget

Keep the whole tweet under 280 literal characters. With the minimal template you have lots of headroom.

## Step 5: Present the output

Output exactly this, nothing else (no preamble, no recap):

---

**Post {NN}, {date}**: `{id}` ({technique})

```
{the full rendered tweet}
```

_{count} chars literal_

**Attach:** `{path to existing video}` OR generate first: `node scripts/generate-videos.mjs --shader={id} --format=square`

**After posting:** tick the checkbox for post {NN} in `docs/tweet-calendar.md`.

---

## Notes

- This is a read-only render. Do NOT tick the checkbox yourself. The user does that after actually posting.
- Absolute prohibition: no em dashes (—) anywhere in the tweet or in the output. Replace with commas, periods, colons, or restructure.
- If the inspiration phrase would feel like fan gushing, pick a more neutral, specific one. Aesthetic over sentiment.
- If the user already ran this command earlier for the same post, redraft fresh. Do not reference the earlier version.
