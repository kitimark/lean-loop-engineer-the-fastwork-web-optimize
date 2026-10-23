
export const pathSearch = (layer) => `?fwl=${encodeURIComponent(layer).replace(/%2C/gi, ',')}:c`;

export const laneOffsets = (maxY) => Array.from({ length: 9 }, (_, i) => Math.floor((i * maxY) / 8));

export const exitOffsets = (T, n) => [T, T + 1, T + Math.floor(n / 4), T + Math.floor(n / 2), T + Math.floor((n * 19) / 20), T + Math.floor((n * 19) / 20) + 1, T + n - 1, T + n, T + n + 1];

export const armPin = () => 'accent-hook';
export const hookSearch = (search) => (search ? `${search}&fwpin=accent` : '?fwpin=accent');
export const pinAt = (arm, _i) => armPin(arm);
export const accentPinned = (served, start, stop, n) => n === 1 && start === served && stop === served;

export const exitClockPinned = (_engine) => true;
export const clockNow = (pinned, epoch, vnow) => (pinned ? epoch : epoch + vnow);
export const secondsLeft = (target, now) => Math.floor(Math.max(0, target - now) / 1000);
