import { shaders } from '$lib/shaders';
import type { PageLoad } from './$types';

export const prerender = true;

export const load: PageLoad = () => {
	return { shaders };
};
