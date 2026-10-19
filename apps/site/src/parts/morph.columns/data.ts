/**
 * The five backdrop columns: vertical offset (a percentage of the column's own height, written as `--col-offset`) and
 * the heights in px of its images (original: inline `height`). Values restated from the original's list
 * (2.DyWL8TcE.js:12887-12935); the images are the snapshot's own files (21 of them).
 */
export interface Column {
  readonly offset: string;
  readonly heights: readonly number[];
  /** the picture of each image, same order as `heights` (the snapshot's own files, served under /selling/) */
  readonly srcs: readonly string[];
}

export const COLUMNS: readonly Column[] = [
  { offset: '-30%', heights: [360, 212, 349, 167, 212], srcs: ['/selling/media/post-1.png', '/selling/media/cover-cafe.jpg', '/selling/roles/graphic-designer.png', '/selling/media/service-kitchen.png', '/selling/work/work-a.jpg'] },
  { offset: '-33%', heights: [360, 360, 360, 224], srcs: ['/selling/media/post-2.png', '/selling/profile/portfolio-1.jpg', '/selling/media/post-4.jpg', '/selling/roles/architect.png'] },
  { offset: '-19%', heights: [295, 527, 394, 360], srcs: ['/selling/media/avatar-cat.png', '/selling/media/post-3.png', '/selling/work/work-c.jpg', '/selling/media/service-cafe.png'] },
  { offset: '-33%', heights: [360, 443, 221, 525], srcs: ['/selling/roles/software-engineer.png', '/selling/media/post-5.jpg', '/selling/work/work-e.jpg', '/selling/profile/portfolio-2.jpg'] },
  { offset: '-11%', heights: [360, 360, 417, 360], srcs: ['/selling/roles/web-developer.png', '/selling/profile/portfolio-3.jpg', '/selling/work/work-f.jpg', '/selling/roles/project-manager.png'] },
];

/** Gap between images inside a track, px (CSS `gap: 12px`), and the track height those give. */
export const TRACK_GAP = 12;
export const trackHeight = (c: Column): number =>
  c.heights.reduce((a, b) => a + b, 0) + TRACK_GAP * (c.heights.length - 1);

/** 1x1 transparent GIF; keeps the `<img>` boxes without any picture. */
