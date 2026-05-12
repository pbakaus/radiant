import { error } from '@sveltejs/kit';
import { getShaderById } from '$lib/shaders';
import { hasArticle, articles, articleMeta } from '$lib/articles';
import type { PageLoad } from './$types';

export const prerender = true;

export const load: PageLoad = ({ params }) => {
	const shader = getShaderById(params.id);
	if (!shader) {
		throw error(404, 'Shader not found');
	}
	if (!hasArticle(params.id)) {
		throw error(404, 'No deep dive written for this shader yet');
	}
	const meta = articleMeta[params.id];
	return { shader, meta };
};

export function entries() {
	return Object.keys(articles).map((id) => ({ id }));
}
