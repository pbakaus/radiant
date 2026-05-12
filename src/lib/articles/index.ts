import type { Component } from 'svelte';
import type { Shader } from '$lib/shaders';
import EventHorizon from './event-horizon.svelte';

export type ArticleComponent = Component<{ shader: Shader }>;

export const articles: Record<string, ArticleComponent> = {
	'event-horizon': EventHorizon
};

export function hasArticle(id: string): boolean {
	return id in articles;
}
