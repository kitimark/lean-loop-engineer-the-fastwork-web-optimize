/**
 * The five backdrop columns: vertical offset (a percentage of the column's own height, written as `--col-offset`) and
 * the heights in px of its images (original: inline `height`). Values restated from the original's list
 * (2.DyWL8TcE.js:12887-12935); the image sources are placeholders (a 1x1 transparent GIF), not the site's pictures.
 */
export interface Column {
  readonly offset: string;
  readonly heights: readonly number[];
}

export const COLUMNS: readonly Column[] = [
  { offset: '-30%', heights: [360, 212, 349, 167, 212] },
  { offset: '-33%', heights: [360, 360, 360, 224] },
  { offset: '-19%', heights: [295, 527, 394, 360] },
  { offset: '-33%', heights: [360, 443, 221, 525] },
  { offset: '-11%', heights: [360, 360, 417, 360] },
];

/** Gap between images inside a track, px (CSS `gap: 12px`), and the track height those give. */
export const TRACK_GAP = 12;
export const trackHeight = (c: Column): number =>
  c.heights.reduce((a, b) => a + b, 0) + TRACK_GAP * (c.heights.length - 1);

/** 1x1 transparent GIF; keeps the `<img>` boxes without any picture. */
export const BLANK_GIF = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';
