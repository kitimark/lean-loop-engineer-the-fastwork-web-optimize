import { PERIOD_MS, color, phase, pos } from './logic';

export const VARIANT = 'layer-sweep';
export const FLAG = 'platform.sweep:layer-sweep';

export const FROM_PCT = 0.666667;
export const LAYERS = 4;
export const BUDGET_BYTES = 8 * 1024 * 1024;

export const layerX = ({ w, t }: { w: number; t: number }): number => -(2 / 3) * (3 * w) * (1 - phase({ t }));

export const layerXCss = ({ w, t }: { w: number; t: number }): number => -FROM_PCT * (3 * w) * (1 - phase({ t }));

export const bgOffset = ({ w, t }: { w: number; t: number }): number => -2 * w * pos({ t });

export const bandU = ({ w, x, v }: { w: number; x: number; v: number }): number => (v * w - x) / (3 * w);

export const imageU = ({ v, p }: { v: number; p: number }): number => (v + 2 * p) / 3;

export { PERIOD_MS, color };
