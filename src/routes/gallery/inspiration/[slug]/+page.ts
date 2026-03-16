import { error } from '@sveltejs/kit';
import { getInspirations, filterShaders, getFilterTitle, getFilterDescription } from '$lib/gallery-filters';
import type { PageLoad } from './$types';

export const prerender = true;

export const load: PageLoad = ({ params }) => {
	const slug = params.slug;
	const inspirations = getInspirations();
	const match = inspirations.find((i) => i.slug === slug);
	if (!match) throw error(404, 'Unknown inspiration');
	const filtered = filterShaders('inspiration', slug);
	return {
		shaders: filtered,
		title: getFilterTitle('inspiration', slug),
		description: getFilterDescription('inspiration', slug, filtered.length)
	};
};

export function entries() {
	return getInspirations().map((i) => ({ slug: i.slug }));
}
