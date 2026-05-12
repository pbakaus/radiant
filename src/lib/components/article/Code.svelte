<script lang="ts">
	let {
		code,
		lang = 'glsl',
		caption,
		highlight
	}: {
		code: string;
		lang?: string;
		caption?: string;
		highlight?: number[]; // 1-indexed line numbers
	} = $props();

	const lines = $derived(code.replace(/\n$/, '').split('\n'));
	const highlightSet = $derived(new Set(highlight ?? []));

	// Very lightweight token highlighting for GLSL/JS. Not perfect, just legible.
	const KEYWORDS = new Set([
		'if', 'else', 'for', 'while', 'return', 'void', 'in', 'out', 'inout',
		'const', 'uniform', 'attribute', 'varying', 'break', 'continue',
		'function', 'var', 'let', 'true', 'false', 'discard'
	]);
	const TYPES = new Set([
		'float', 'int', 'bool', 'vec2', 'vec3', 'vec4', 'mat2', 'mat3', 'mat4',
		'sampler2D', 'samplerCube'
	]);
	const BUILTINS = new Set([
		'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'pow', 'exp', 'log', 'sqrt',
		'abs', 'sign', 'floor', 'ceil', 'fract', 'mod', 'min', 'max', 'clamp',
		'mix', 'step', 'smoothstep', 'length', 'dot', 'cross', 'normalize',
		'reflect', 'refract', 'distance', 'texture', 'texture2D', 'gl_FragCoord',
		'gl_FragColor', 'gl_Position'
	]);

	function tokenize(line: string): { kind: string; text: string }[] {
		const out: { kind: string; text: string }[] = [];
		const re = /(\/\/.*$)|(\/\*[\s\S]*?\*\/)|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')|(\b\d+\.?\d*\b)|(\b[A-Za-z_][A-Za-z0-9_]*\b)|([{}()[\];,])|(\s+)|(.)/g;
		let m: RegExpExecArray | null;
		while ((m = re.exec(line))) {
			if (m[1]) out.push({ kind: 'comment', text: m[1] });
			else if (m[2]) out.push({ kind: 'comment', text: m[2] });
			else if (m[3]) out.push({ kind: 'string', text: m[3] });
			else if (m[4]) out.push({ kind: 'number', text: m[4] });
			else if (m[5]) {
				const w = m[5];
				if (KEYWORDS.has(w)) out.push({ kind: 'kw', text: w });
				else if (TYPES.has(w)) out.push({ kind: 'type', text: w });
				else if (BUILTINS.has(w)) out.push({ kind: 'builtin', text: w });
				else out.push({ kind: 'id', text: w });
			} else if (m[6]) out.push({ kind: 'punct', text: m[6] });
			else if (m[7]) out.push({ kind: 'ws', text: m[7] });
			else if (m[8]) out.push({ kind: 'op', text: m[8] });
		}
		return out;
	}
</script>

<figure class="code-block">
	<div class="code-header">
		<span class="lang">{lang}</span>
	</div>
	<pre><code>{#each lines as line, i}<div class="line" class:hl={highlightSet.has(i + 1)}><span class="ln">{i + 1}</span><span class="content">{#each tokenize(line) as t}<span class="tok-{t.kind}">{t.text}</span>{/each}{#if line.length === 0}{' '}{/if}</span></div>{/each}</code></pre>
	{#if caption}
		<figcaption>{caption}</figcaption>
	{/if}
</figure>

<style>
	.code-block {
		margin: 2rem 0;
		background: #0d0d0d;
		border: 1px solid rgba(200, 149, 108, 0.1);
		border-radius: 6px;
		overflow: hidden;
	}
	.code-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: 0.4rem 0.9rem;
		background: rgba(200, 149, 108, 0.04);
		border-bottom: 1px solid rgba(200, 149, 108, 0.06);
	}
	.lang {
		font-family: 'SF Mono', monospace;
		font-size: 0.65rem;
		text-transform: uppercase;
		letter-spacing: 0.15em;
		color: rgba(200, 149, 108, 0.6);
	}
	pre {
		margin: 0;
		padding: 0.75rem 0;
		overflow-x: auto;
		font-family: 'SF Mono', 'Fira Code', 'Cascadia Code', monospace;
		font-size: 0.78rem;
		line-height: 1.6;
		color: rgba(232, 224, 216, 0.85);
		scrollbar-width: thin;
	}
	code {
		display: block;
	}
	.line {
		display: grid;
		grid-template-columns: 2.5rem 1fr;
		padding: 0 0.9rem 0 0;
	}
	.line.hl {
		background: rgba(200, 149, 108, 0.06);
		box-shadow: inset 2px 0 0 rgba(200, 149, 108, 0.5);
	}
	.ln {
		text-align: right;
		padding-right: 0.7rem;
		color: rgba(232, 224, 216, 0.2);
		user-select: none;
		font-variant-numeric: tabular-nums;
	}
	.content {
		white-space: pre;
	}
	figcaption {
		padding: 0.6rem 0.9rem 0.75rem;
		font-size: 0.75rem;
		line-height: 1.5;
		color: rgba(232, 224, 216, 0.45);
		font-style: italic;
		border-top: 1px solid rgba(200, 149, 108, 0.05);
	}

	/* Token colors — warm-amber palette */
	:global(.code-block .tok-comment) { color: rgba(232, 224, 216, 0.35); font-style: italic; }
	:global(.code-block .tok-string)  { color: #d4a888; }
	:global(.code-block .tok-number)  { color: #e0b88a; }
	:global(.code-block .tok-kw)      { color: #c8956c; }
	:global(.code-block .tok-type)    { color: #b88c66; }
	:global(.code-block .tok-builtin) { color: #d4a888; }
	:global(.code-block .tok-punct)   { color: rgba(232, 224, 216, 0.4); }
	:global(.code-block .tok-op)      { color: rgba(232, 224, 216, 0.6); }
	:global(.code-block .tok-id)      { color: rgba(232, 224, 216, 0.85); }
</style>
