# STYLE.md

Editorial brief for Radiant. Read this before writing or editing user-facing copy: the homepage, gallery descriptions, shader catalog blurbs, and deep-dive articles.

The bar: **for every paragraph, point to the sentence that makes it specifically about this shader, this technique, this trade-off.** If you can't, the paragraph is AI by default, even if a human typed it.

## Principles

1. **Open with a concrete fact, not a frame.** The first sentence of an article should already be teaching, not setting up. No "in this article", no "let's start by".
2. **Take a position someone could disagree with.** "The cheap fix is right for real-time" is a stance. "There are tradeoffs to consider" is not.
3. **Name names. Use numbers.** Real techniques (Verlet, Novikov-Thorne, Schwarzschild), real line counts ("under 600 lines"), real fps targets, real file names. Cut "lightweight"; write "54 KB".
4. **Show the math when it pays off.** One equation that earns its place beats three paragraphs hedging around it. Don't reach for math to look credible; reach for it when it's faster than prose.
5. **Verbs lead. Nouns follow.** Imperative is fine. Active voice. Cut nominalizations ("the calculation of the temperature" → "computing the temperature").
6. **Vary sentence length on purpose.** Long, long, short. Uniform rhythm is the deepest AI tell. Short fragments are allowed. Five words. Confidence signal.
7. **Prose carries the load; sandboxes and code support it.** Don't bullet what would be tighter as a sentence. Don't use a sandbox where a sentence is enough.
8. **Plain words. Technical terms only when something specifically rests on them.** "Symplectic integrator" is fine when it's the reason the simulation doesn't drift. "Holistic approach" is never fine.
9. **Respect the reader's competence.** No "developers should consider"; just "you don't need that". The audience can handle vectors, exponents, and the word "geodesic".
10. **Read it aloud. Fix anything you stumble over.**
11. **Concrete over comprehensive.** Coverage is an AI obsession. Leave things out. Pick the one trick worth explaining and explain it well.
12. **Close by handing off the next move.** Don't summarize. End on the strongest sentence, give a directive ("now scrub the slider"), or point to the source.

## Denylist

Patterns to remove on sight. Add a row when you ban a new one. Don't silently allowlist; either it's banned or it isn't.

### Marketing voice

Adjectives and verbs that gesture at quality without doing the work.

| Banned | Why | Use instead |
|---|---|---|
| `seamless`, `seamlessly` | Hollow positive. | Say what specifically works without friction. |
| `robust`, `robustness` | Hollow positive. | Name the failure mode it survives. |
| `elevate`, `elevates` | Marketing verb. | Use the specific verb. |
| `empower`, `empowers` | Marketing verb. | "Let you", "make possible". |
| `underscore`, `underscores` | AI tell. | "Show", "make clear". |
| `pivotal`, `crucial`, `essential` | Hollow superlative. | If it's essential, the absence is testable; say what breaks without it. |
| `powerful` | Means nothing. | Numbers. fps, line counts, frame budgets. |
| `beautiful`, `stunning`, `gorgeous` | The visuals do this work; the prose shouldn't try. | Describe the specific visual element. |
| `tapestry`, `landscape`, `realm` | AI scenery noun. | Cut. |

### Throat-clearing

Sentences that delay the point. Almost nothing of value is lost when you cut them.

| Banned | Why | Use instead |
|---|---|---|
| `in today's …` | Generic opener. | Start at the actual point. |
| `let's dive in`, `let's explore`, `let's take a look` | Throat-clearing. | Just start. |
| `whether you're …` | Audience-pandering; addresses no one. | Pick one reader. Write to them. |
| `it's worth noting that` | The thing you're about to say is what's worth noting. | Drop the preface. |

### Verbs

| Banned | Why | Use instead |
|---|---|---|
| `delve`, `delves`, `delved`, `delving` | The most-flagged AI tell. | "Look at", or delete the verb entirely. |
| `leverage` (as a verb) | Consultant-speak. | "Use". |

### Closers

| Banned | Why | Use instead |
|---|---|---|
| `in summary`, `in conclusion`, `to summarize` | Restates what you just said. | End on the strongest sentence. |
| `at the end of the day` | Filler. | Cut. |

### Transitions

| Banned | Why | Use instead |
|---|---|---|
| `moreover`, `furthermore`, `additionally` | Metronome transition crutch. | Drop, or use "also", or restructure. |

### Punctuation

| Banned | Why | Use instead |
|---|---|---|
| Em dash `—` (and HTML entities `&mdash;`, `&#8212;`, `&#x2014;`) | Decision-avoidance: the writer didn't pick a relationship between the clauses. | Comma, colon, semicolon, period, parentheses. Pick the relationship. |
| ` -- ` (double hyphen as em-dash substitute) | Worse than the em dash. Signals failed cleanup. | Real punctuation. |

The em-dash ban is contentious. Keep it anyway. Most prose improves when you have to commit to a punctuation mark that means something specific.

## Patterns the regex can't catch

The above are the easy ones. The deeper issues require judgment on every paragraph.

- **Negation pivot.** "It's not just X, it's Y." "Less about X, more about Y." Now a stronger AI tell than any vocabulary item. Use once per article maximum. Most instances should become a direct positive claim.
- **Triadic everything.** Every list exactly three items. Every adjective in groups of three ("fast, simple, and powerful"). Vary count: use 2 or 4. Use 1. If a list naturally wants to be three, fine; if you're padding to three, cut it.
- **The "three things make this work" pattern.** Same shape as triadic everything, with extra throat-clearing. "Three things make this tractable: A. B. C." → just describe A, B, C as paragraphs.
- **"First... Second... Finally..."** Numbered enumeration in prose, usually disguising that you have only one real point. Cut to the one point, or make them three actual paragraphs.
- **Uniform paragraph length.** Insert a 4-word sentence. Insert a one-line paragraph.
- **The five-paragraph essay shape.** Intro → 3 sections → conclusion, every time. Mix it up. Lead with the example. Skip the conclusion. Let some sections be one sentence.
- **Synthetic balance.** Both sides presented as equal when one is clearly right. Write the recommendation; note real exceptions briefly.
- **Hollow confidence.** "Powerful technique" without numbers. Replace with a concrete fact.
- **Hedging stacks.** "It might potentially be useful to consider..." Each hedge is fine; stacked, they sound trained.
- **Generic CTA endings.** "Read it, fork it, drop it on your hero section." Pick the one verb. Or just stop.
- **Interchangeable copy.** Swap "Radiant" for "ShaderToy" or "Codepen". If nothing becomes false, the copy is generic. The article should be unrunnable on any other site.

## Radiant-specific guidance

- **Articles are not papers.** Don't simulate academic structure. No abstract, no "this article will show...". Drop in at the interesting moment.
- **Sandboxes are not figures.** Don't write "as shown in the sandbox below". The sandbox shows itself. Refer to what it does, not that it exists.
- **Code excerpts earn their lines.** If a 30-line excerpt could be three lines, show three lines. The eye glazes over the rest anyway.
- **Math is allowed.** This audience can read `T(r) ∝ r^(−3/4)`. Don't apologize for it. Don't translate it into English right after writing it.
- **Don't explain that the shader exists.** The reader is already on the page. Start with what's happening, not what they're about to read.

## When in doubt

Read the paragraph aloud. If you stumble, rewrite. If a sentence describes nothing specific to this shader, this technique, or this trade-off, cut it.
