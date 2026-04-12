let _message = $state<string | null>(null);
let _timer: ReturnType<typeof setTimeout> | null = null;

export function showToast(msg: string, duration = 2000) {
	_message = msg;
	if (_timer) clearTimeout(_timer);
	_timer = setTimeout(() => {
		_message = null;
	}, duration);
}

export function getToast(): string | null {
	return _message;
}
