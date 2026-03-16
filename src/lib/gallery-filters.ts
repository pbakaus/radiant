import { shaders, tagLabels, techniqueLabels, type Shader, type ShaderTag, type ShaderTechnique } from './shaders';

export type FilterDimension = 'all' | 'tag' | 'technique' | 'inspiration';

export interface FilterCategory {
	dimension: FilterDimension;
	slug: string;
	label: string;
	count: number;
	href: string;
}

export interface FilterSection {
	title: string;
	categories: FilterCategory[];
}

export function toSlug(name: string): string {
	return name
		.toLowerCase()
		.normalize('NFD')
		.replace(/[\u0300-\u036f]/g, '') // strip accents (Beyoncé → Beyonce)
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/(^-|-$)/g, '');
}

export function fromSlug(slug: string, dimension: FilterDimension): string {
	if (dimension === 'tag') {
		// Tags are already slugs (fill, object, particles, etc.)
		return slug;
	}
	if (dimension === 'technique') {
		return slug; // canvas-2d, webgl
	}
	if (dimension === 'inspiration') {
		// Find the original inspiration name that matches this slug
		const match = getInspirations().find((i) => i.slug === slug);
		return match?.label ?? slug;
	}
	return slug;
}

export function getInspirations(): { slug: string; label: string; count: number }[] {
	const map = new Map<string, { label: string; count: number }>();
	for (const s of shaders) {
		if (s.inspiration) {
			const slug = toSlug(s.inspiration);
			const existing = map.get(slug);
			if (existing) {
				existing.count++;
			} else {
				map.set(slug, { label: s.inspiration, count: 1 });
			}
		}
	}
	return Array.from(map.entries())
		.map(([slug, { label, count }]) => ({ slug, label, count }))
		.sort((a, b) => a.label.localeCompare(b.label));
}

export function filterShaders(dimension: FilterDimension, slug: string): Shader[] {
	if (dimension === 'all') return shaders;
	if (dimension === 'tag') {
		return shaders.filter((s) => s.tags.includes(slug as ShaderTag));
	}
	if (dimension === 'technique') {
		return shaders.filter((s) => s.technique === slug);
	}
	if (dimension === 'inspiration') {
		const label = fromSlug(slug, 'inspiration');
		return shaders.filter((s) => s.inspiration && toSlug(s.inspiration) === slug);
	}
	return shaders;
}

export function getFilterTitle(dimension: FilterDimension, slug: string): string {
	if (dimension === 'all') return 'All Shaders';
	if (dimension === 'tag') return tagLabels[slug as ShaderTag] ?? slug;
	if (dimension === 'technique') return techniqueLabels[slug as ShaderTechnique] ?? slug;
	if (dimension === 'inspiration') {
		const insp = getInspirations().find((i) => i.slug === slug);
		return insp?.label ?? slug;
	}
	return slug;
}

export function getFilterDescription(dimension: FilterDimension, slug: string, count: number): string {
	if (dimension === 'all') return `${count} canvas-based generative animations. Click to explore, configure, and download.`;
	if (dimension === 'tag') return `${count} shaders tagged "${tagLabels[slug as ShaderTag]}"`;
	if (dimension === 'technique') return `${count} shaders built with ${techniqueLabels[slug as ShaderTechnique]}`;
	if (dimension === 'inspiration') {
		const name = getFilterTitle('inspiration', slug);
		return `${count} shader${count !== 1 ? 's' : ''} inspired by ${name}`;
	}
	return '';
}

export function getSidebarSections(): FilterSection[] {
	const sections: FilterSection[] = [];

	// Browse
	sections.push({
		title: 'Browse',
		categories: [
			{
				dimension: 'all',
				slug: 'all',
				label: 'All Shaders',
				count: shaders.length,
				href: '/gallery/all'
			}
		]
	});

	// Style (tags)
	const tagCounts = new Map<ShaderTag, number>();
	for (const s of shaders) {
		for (const t of s.tags) {
			tagCounts.set(t, (tagCounts.get(t) ?? 0) + 1);
		}
	}
	sections.push({
		title: 'Style',
		categories: (Object.keys(tagLabels) as ShaderTag[]).map((tag) => ({
			dimension: 'tag' as FilterDimension,
			slug: tag,
			label: tagLabels[tag],
			count: tagCounts.get(tag) ?? 0,
			href: `/gallery/tag/${tag}`
		}))
	});

	// Technique
	const techCounts = new Map<string, number>();
	for (const s of shaders) {
		techCounts.set(s.technique, (techCounts.get(s.technique) ?? 0) + 1);
	}
	sections.push({
		title: 'Technique',
		categories: (['webgl', 'canvas-2d'] as ShaderTechnique[]).map((tech) => ({
			dimension: 'technique' as FilterDimension,
			slug: tech,
			label: techniqueLabels[tech],
			count: techCounts.get(tech) ?? 0,
			href: `/gallery/technique/${tech}`
		}))
	});

	// Inspiration
	const inspirations = getInspirations();
	sections.push({
		title: 'Inspiration',
		categories: inspirations.map((i) => ({
			dimension: 'inspiration' as FilterDimension,
			slug: i.slug,
			label: i.label,
			count: i.count,
			href: `/gallery/inspiration/${i.slug}`
		}))
	});

	return sections;
}

// Generate all possible gallery entry paths for prerendering
export function getAllGalleryEntries(): { dimension: string; slug: string }[] {
	const entries: { dimension: string; slug: string }[] = [];

	// Tags
	for (const tag of Object.keys(tagLabels)) {
		entries.push({ dimension: 'tag', slug: tag });
	}

	// Techniques
	entries.push({ dimension: 'technique', slug: 'webgl' });
	entries.push({ dimension: 'technique', slug: 'canvas-2d' });

	// Inspirations
	for (const insp of getInspirations()) {
		entries.push({ dimension: 'inspiration', slug: insp.slug });
	}

	return entries;
}
