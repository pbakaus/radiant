import type { Shader } from './shaders';
import type { ColorScheme } from './color-schemes';

type Layout = 'full' | 'hero' | 'background' | 'accent';

export function generateLayoutSource(
	rawSource: string,
	shader: Shader,
	layout: Layout,
	scheme: ColorScheme
): string {
	if (layout === 'full') {
		if (scheme.filter === 'none') return rawSource;
		return rawSource.replace(
			'</style>',
			`  /* Color scheme: ${scheme.name} */\n  canvas { filter: ${scheme.filter}; }\n</style>`
		);
	}

	const shaderEmbed = prepareShaderForEmbed(rawSource);
	const filterStyle = scheme.filter !== 'none' ? ` style="filter: ${scheme.filter}"` : '';

	switch (layout) {
		case 'hero':
			if (shader.heroConfig) {
				return heroCustomTemplate(shader, shaderEmbed, filterStyle);
			}
			return heroTemplate(shader, shaderEmbed, filterStyle);
		case 'background':
			return backgroundTemplate(shader, shaderEmbed, filterStyle);
		case 'accent':
			return accentTemplate(shader, shaderEmbed, filterStyle);
	}
}

/**
 * Prepares shader HTML for embedding inside a JS template literal that gets
 * assigned to iframe.srcdoc. Handles:
 * - Removing the label overlay (not needed in layout context)
 * - Escaping for template literal safety
 * - Preventing premature </script> tag closure
 */
function prepareShaderForEmbed(rawSource: string): string {
	let s = rawSource;
	// Remove label div
	s = s.replace(/<div class="label">.*?<\/div>\n?/g, '');
	// Remove .label CSS block
	s = s.replace(/\s*\.label\s*\{[^}]*\}\n?/g, '');
	// Escape backslashes, backticks, and template expressions for JS template literal
	s = s.replace(/\\/g, '\\\\');
	s = s.replace(/`/g, '\\`');
	s = s.replace(/\$\{/g, '\\${');
	// Prevent browser from matching </script> inside the outer script block
	s = s.replace(/<\/script>/gi, '<\\/script>');
	return s;
}

function shaderScript(shaderEmbed: string, filterStyle: string): string {
	return `  <script>
    // Shader source is embedded below — edit colors and parameters directly.
    // The shader runs in an iframe so it gets its own viewport context.
    document.getElementById('shader').srcdoc = \`${shaderEmbed}\`;
  <\/script>`;
	// Note: the <\/script> above is intentional — it prevents the browser
	// from prematurely closing this script block in the generated HTML.
}

function heroTemplate(shader: Shader, shaderEmbed: string, filterStyle: string): string {
	// We need to use raw closing script tag for the OUTER script, but we're
	// generating source as a string, not rendering it. So </script> is fine
	// for the outer block — it will be correct when saved as a file.
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Hero — ${shader.title}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0a0a0a;
    color: #e8e0d8;
    font-family: system-ui, -apple-system, sans-serif;
    min-height: 100vh;
  }
  nav {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem 3rem;
  }
  nav .logo { font-weight: 600; color: #c8956c; letter-spacing: 0.05em; }
  nav .links { display: flex; gap: 2rem; font-size: 0.9rem; color: rgba(232,224,216,0.5); }
  nav .links a { color: inherit; text-decoration: none; }

  .hero {
    display: flex;
    align-items: center;
    gap: 3rem;
    padding: 3rem;
    max-width: 1200px;
    margin: 0 auto;
    min-height: 60vh;
  }
  .hero-content {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .hero-content h1 {
    font-size: 2.5rem;
    font-weight: 500;
    line-height: 1.2;
    margin-bottom: 1rem;
  }
  .hero-content p {
    color: rgba(232,224,216,0.5);
    line-height: 1.6;
    max-width: 36ch;
  }
  .hero-content .btn {
    display: inline-block;
    margin-top: 1.5rem;
    padding: 0.75rem 1.5rem;
    background: #c8956c;
    color: #0a0a0a;
    border-radius: 6px;
    font-weight: 500;
    text-decoration: none;
  }
  .hero-shader {
    flex: 0 0 420px;
    aspect-ratio: 4 / 3;
    overflow: hidden;
    position: relative;
  }
  .hero-shader iframe {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    border: none;
    display: block;
  }
</style>
</head>
<body>
  <nav>
    <div class="logo">acme</div>
    <div class="links">
      <a href="#">Features</a>
      <a href="#">Pricing</a>
      <a href="#">About</a>
    </div>
  </nav>
  <section class="hero">
    <div class="hero-content">
      <h1>Your next big idea starts here</h1>
      <p>A beautiful landing page with a generative shader that makes your product stand out.</p>
      <a href="#" class="btn">Get Started</a>
    </div>
    <div class="hero-shader">
      <iframe id="shader"${filterStyle}></iframe>
    </div>
  </section>

  <script>
    document.getElementById('shader').srcdoc = \`${shaderEmbed}\`;
  </script>
</body>
</html>`;
}

function heroCustomTemplate(shader: Shader, shaderEmbed: string, filterStyle: string): string {
	const params = shader.heroConfig!.params;
	const paramMessages = params
		.map((p) => `      frame.contentWindow.postMessage({ type: 'param', name: '${p.name}', value: ${p.value} }, '*');`)
		.join('\n');
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Hero — ${shader.title}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0a0a0a;
    color: #e8e0d8;
    font-family: system-ui, -apple-system, sans-serif;
    min-height: 100vh;
    overflow: hidden;
  }
  .shader-bg {
    position: fixed;
    inset: 0;
    z-index: 0;
  }
  .shader-bg iframe {
    width: 100%;
    height: 100%;
    border: none;
    display: block;
  }
  .page {
    position: relative;
    z-index: 1;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
  }
  nav {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 1.5rem 3rem;
  }
  nav .logo { font-weight: 600; color: #c8956c; letter-spacing: 0.05em; }
  nav .links { display: flex; gap: 2rem; font-size: 0.9rem; color: rgba(232,224,216,0.5); }
  nav .links a { color: inherit; text-decoration: none; }

  .hero {
    display: flex;
    align-items: center;
    gap: 3rem;
    padding: 3rem;
    max-width: 600px;
    flex: 1;
  }
  .hero-content {
    flex: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
  }
  .hero-content h1 {
    font-size: 2.5rem;
    font-weight: 500;
    line-height: 1.2;
    margin-bottom: 1rem;
  }
  .hero-content p {
    color: rgba(232,224,216,0.5);
    line-height: 1.6;
    max-width: 36ch;
  }
  .hero-content .btn {
    display: inline-block;
    margin-top: 1.5rem;
    padding: 0.75rem 1.5rem;
    background: #c8956c;
    color: #0a0a0a;
    border-radius: 6px;
    font-weight: 500;
    text-decoration: none;
  }
</style>
</head>
<body>
  <div class="shader-bg">
    <iframe id="shader"${filterStyle}></iframe>
  </div>
  <div class="page">
    <nav>
      <div class="logo">acme</div>
      <div class="links">
        <a href="#">Features</a>
        <a href="#">Pricing</a>
        <a href="#">About</a>
      </div>
    </nav>
    <section class="hero">
      <div class="hero-content">
        <h1>Your next big idea starts here</h1>
        <p>A beautiful landing page with a generative shader that makes your product stand out.</p>
        <a href="#" class="btn">Get Started</a>
      </div>
    </section>
  </div>

  <script>
    var frame = document.getElementById('shader');
    frame.srcdoc = \`${shaderEmbed}\`;
    frame.addEventListener('load', function() {
${paramMessages}
    });
  <\\/script>
</body>
</html>`;
}

function backgroundTemplate(shader: Shader, shaderEmbed: string, filterStyle: string): string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Background — ${shader.title}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0a0a0a;
    color: #e8e0d8;
    font-family: system-ui, -apple-system, sans-serif;
  }
  .viewport {
    position: relative;
    width: 100%;
    height: 100vh;
    overflow: hidden;
  }
  .viewport iframe {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    border: none;
  }
  .viewport .overlay {
    position: absolute;
    inset: 0;
    background: rgba(10, 10, 10, 0.7);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    z-index: 1;
    pointer-events: none;
  }
  .overlay-content {
    display: flex;
    flex-direction: column;
    align-items: center;
    pointer-events: auto;
  }
  .overlay h1 {
    font-size: 3rem;
    font-weight: 500;
    margin-bottom: 1rem;
  }
  .overlay p {
    color: rgba(232,224,216,0.6);
    font-size: 1.1rem;
    line-height: 1.6;
    max-width: 42ch;
  }
  .overlay .btn {
    display: inline-block;
    margin-top: 2rem;
    padding: 0.75rem 2rem;
    background: #c8956c;
    color: #0a0a0a;
    border-radius: 6px;
    font-weight: 500;
    text-decoration: none;
    font-size: 1rem;
  }
</style>
</head>
<body>
  <section class="viewport">
    <iframe id="shader"${filterStyle}></iframe>
    <div class="overlay">
      <div class="overlay-content">
        <h1>Welcome</h1>
        <p>Content overlaid on a full-viewport shader background with a darkening layer.</p>
        <a href="#" class="btn">Call to Action</a>
      </div>
    </div>
  </section>

  <script>
    document.getElementById('shader').srcdoc = \`${shaderEmbed}\`;
  </script>
</body>
</html>`;
}

function accentTemplate(shader: Shader, shaderEmbed: string, filterStyle: string): string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Accent — ${shader.title}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    background: #0a0a0a;
    color: #e8e0d8;
    font-family: system-ui, -apple-system, sans-serif;
  }
  .viewport {
    position: relative;
    width: 100%;
    height: 100vh;
    overflow: hidden;
  }
  .viewport iframe {
    position: absolute;
    top: 0;
    left: 50%;
    width: 100%;
    height: 100%;
    border: none;
  }
  .content {
    position: relative;
    z-index: 1;
    display: flex;
    flex-direction: column;
    justify-content: center;
    height: 100%;
    max-width: 40%;
    padding: 4rem;
  }
  .content h1 {
    font-size: 2.5rem;
    font-weight: 500;
    line-height: 1.2;
    margin-bottom: 1rem;
  }
  .content p {
    color: rgba(232,224,216,0.5);
    line-height: 1.6;
    max-width: 36ch;
  }
  .content .btn {
    display: inline-block;
    margin-top: 1.5rem;
    padding: 0.75rem 1.5rem;
    background: #c8956c;
    color: #0a0a0a;
    border-radius: 6px;
    font-weight: 500;
    text-decoration: none;
    width: fit-content;
  }
</style>
</head>
<body>
  <section class="viewport">
    <iframe id="shader"${filterStyle}></iframe>
    <div class="content">
      <h1>Creative Studio</h1>
      <p>The shader fades in from the right as a dramatic accent, creating depth alongside your content.</p>
      <a href="#" class="btn">Learn More</a>
    </div>
  </section>

  <script>
    document.getElementById('shader').srcdoc = \`${shaderEmbed}\`;
  </script>
</body>
</html>`;
}
