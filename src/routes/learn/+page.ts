import { articles, articleMeta } from '$lib/articles';
import { getShaderById } from '$lib/shaders';
import type { PageLoad } from './$types';

export const prerender = true;

export const load: PageLoad = () => {
	const entries = Object.keys(articles)
		.map((id) => {
			const shader = getShaderById(id);
			const meta = articleMeta[id];
			if (!shader || !meta) return null;
			return { id, shader, meta };
		})
		.filter((e): e is NonNullable<typeof e> => e != null);
	return { entries };
};
