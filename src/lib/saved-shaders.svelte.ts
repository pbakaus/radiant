import { browser } from '$app/environment';
import { showToast } from './toast.svelte';

const STORAGE_KEY = 'radiant_saved_shaders';

let _ids = $state<string[]>([]);

export function initSavedShaders() {
	if (!browser) return;
	try {
		const stored = localStorage.getItem(STORAGE_KEY);
		if (stored) {
			_ids = JSON.parse(stored) as string[];
		}
	} catch {}
}

function persist() {
	if (browser) {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(_ids));
	}
}

export function toggleSaved(id: string): void {
	if (_ids.includes(id)) {
		_ids = _ids.filter((i) => i !== id);
		showToast('Removed from collection');
	} else {
		_ids = [..._ids, id];
		showToast('Saved to collection');
	}
	persist();
}

export function getSavedIds(): string[] {
	return _ids;
}
