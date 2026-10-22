
export const pathSearch = (layer) => `?fwl=${encodeURIComponent(layer).replace(/%2C/gi, ',')}:c`;

export const laneOffsets = (maxY) => Array.from({ length: 9 }, (_, i) => Math.floor((i * maxY) / 8));
