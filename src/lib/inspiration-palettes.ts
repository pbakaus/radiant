export interface InspirationPalette {
	primary: string; // hex, used for card border tint
	colors: string[]; // 2-4 hex colors for ambient glow
}

export const inspirationPalettes: Record<string, InspirationPalette> = {
	// Musicians
	'sabrina-carpenter': {
		primary: '#E8527A',
		colors: ['#E8527A', '#8B4570', '#CD6060']
	},
	'laufey': {
		primary: '#C9A84C',
		colors: ['#F5E6C8', '#C9A84C', '#D4A055']
	},
	'dua-lipa': {
		primary: '#E03A8A',
		colors: ['#E03A8A', '#1A3A8A', '#C0C0D0']
	},
	'billie-eilish': {
		primary: '#6AE090',
		colors: ['#6AE090', '#8878AA', '#2A4A3A']
	},
	'taylor-swift': {
		primary: '#C8964C',
		colors: ['#1A2A5A', '#C8964C', '#2A6A3A']
	},
	'beyonce': {
		primary: '#D4A028',
		colors: ['#D4A028', '#A0522D', '#6A3D8A']
	},
	'bad-bunny': {
		primary: '#E87460',
		colors: ['#A0E832', '#E87460', '#5A2D82', '#40C4AA']
	},
	'sza': {
		primary: '#D4944C',
		colors: ['#D4944C', '#CC5500', '#8FAE8B']
	},
	'rihanna': {
		primary: '#9B1B30',
		colors: ['#9B1B30', '#D4A028', '#FF6B35']
	},
	'lady-gaga': {
		primary: '#C0328A',
		colors: ['#C0C0D0', '#C0328A', '#A080C0']
	},
	'bruno-mars': {
		primary: '#D4A028',
		colors: ['#D4A028', '#CC2244', '#4A2028']
	},
	'the-weeknd': {
		primary: '#B01030',
		colors: ['#B01030', '#2060CC', '#D4944C']
	},
	'ariana-grande': {
		primary: '#C8A0B8',
		colors: ['#C8A0B8', '#E8D8E8', '#8A7088']
	},
	'chappell-roan': {
		primary: '#E83878',
		colors: ['#E83878', '#88CC28', '#C8A038']
	},
	'olivia-rodrigo': {
		primary: '#8A1838',
		colors: ['#8A1838', '#6A28AA', '#E84888']
	},
	'harry-styles': {
		primary: '#B088CC',
		colors: ['#B088CC', '#E8A0A0', '#88C8A8']
	},

	// Actors
	'jim-carrey': {
		primary: '#88E828',
		colors: ['#88E828', '#E8D828', '#2888E8']
	},
	'jack-black': {
		primary: '#E87028',
		colors: ['#E87028', '#B82828', '#D4A038']
	},
	'robert-downey-jr': {
		primary: '#4890D4',
		colors: ['#6A7080', '#4890D4', '#8A2838']
	},
	'meryl-streep': {
		primary: '#7A2838',
		colors: ['#B0B0C0', '#606878', '#7A2838']
	},
	'anne-hathaway': {
		primary: '#C85878',
		colors: ['#E8E8F0', '#C85878', '#1A2048']
	},
	'zendaya': {
		primary: '#B07838',
		colors: ['#B07838', '#C08848', '#7868A0']
	},
	'keanu-reeves': {
		primary: '#3868B0',
		colors: ['#181828', '#3868B0', '#C87838']
	},
	'pedro-pascal': {
		primary: '#D4944C',
		colors: ['#D4944C', '#C06840', '#6A2030']
	},
	'ryan-gosling': {
		primary: '#E86888',
		colors: ['#E86888', '#3868CC', '#C89078']
	},
	'margot-robbie': {
		primary: '#E888A8',
		colors: ['#E888A8', '#D4A028', '#CC2828']
	},
	'cate-blanchett': {
		primary: '#B0B8D0',
		colors: ['#B0B0C0', '#B0B8D0', '#8898C0']
	},
	'jenna-ortega': {
		primary: '#5A2858',
		colors: ['#282030', '#5A2858', '#A0A0B8']
	},
	'ana-de-armas': {
		primary: '#D4A038',
		colors: ['#D4A038', '#E8E0D0', '#8A7838']
	},
	'lupita-nyong-o': {
		primary: '#2858CC',
		colors: ['#2858CC', '#D4A028', '#5A2880']
	},
	'jeff-goldblum': {
		primary: '#E87868',
		colors: ['#181838', '#E87868', '#7A2030']
	},
	'benedict-cumberbatch': {
		primary: '#C8A050',
		colors: ['#C8A050', '#E8C870', '#785020']
	},
	'daft-punk': {
		primary: '#50C8D0',
		colors: ['#50C8D0', '#C0C0D0', '#D4A040']
	},
	'brandon-sanderson': {
		primary: '#B08040',
		colors: ['#B08040', '#6A4828', '#D4A868']
	}
};

/** Convert hex (#RRGGBB) to "R, G, B" string for use in rgba() */
export function hexToRgb(hex: string): string {
	const h = hex.replace('#', '');
	const r = parseInt(h.substring(0, 2), 16);
	const g = parseInt(h.substring(2, 4), 16);
	const b = parseInt(h.substring(4, 6), 16);
	return `${r}, ${g}, ${b}`;
}

/** Look up palette by inspiration name (e.g. "Beyoncé") */
export function getPaletteForInspiration(name: string): InspirationPalette | undefined {
	const slug = name
		.toLowerCase()
		.normalize('NFD')
		.replace(/[\u0300-\u036f]/g, '')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/(^-|-$)/g, '');
	return inspirationPalettes[slug];
}

/** Look up palette by slug (e.g. "beyonce") */
export function getPaletteForSlug(slug: string): InspirationPalette | undefined {
	return inspirationPalettes[slug];
}
