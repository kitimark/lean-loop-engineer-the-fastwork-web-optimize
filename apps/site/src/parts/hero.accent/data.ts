/**
 * Per-word artwork frame of the accent: the SVG view box, the paint insets (percent strings written inline) and the label,
 * restated from the original's word list (nodes/2.DyWL8TcE.js:3484-3665, hidden words removed; index -1 is the base word).
 * The strokes are NOT the original's paths: a plain stand-in wave per frame (svg-extract reads the real ones at build time).
 */
export interface WordArt {
  readonly viewBox: readonly [number, number];
  readonly inset: { readonly top: string; readonly right: string; readonly bottom: string; readonly left: string };
  readonly label: string;
}

export const BASE_ART: WordArt = {
  viewBox: [114.25, 83.2543],
  inset: { top: '0', right: '0', bottom: '-12.51%', left: '-7.78%' },
  label: 'you',
};

/** Cursor order 0..5 (matches `WORD_WIDTHS`). */
export const WORD_ART: readonly WordArt[] = [
  {
    viewBox: [98, 87],
    inset: { top: '10.14%', right: '5.8%', bottom: '-27.7%', left: '6.7%' },
    label: 'คุณ',
  },
  {
    viewBox: [64, 71],
    inset: { top: '6.05%', right: '10.63%', bottom: '-2%', left: '9.38%' },
    label: '你',
  },
  {
    viewBox: [67, 75],
    inset: { top: '3.38%', right: '15.63%', bottom: '-4.73%', left: '14.58%' },
    label: '너',
  },
  {
    viewBox: [134, 59],
    inset: { top: '10.16%', right: '-0.37%', bottom: '10.11%', left: '0.37%' },
    label: 'あなた',
  },
  {
    viewBox: [151, 62],
    inset: { top: '11.49%', right: '3.42%', bottom: '4.73%', left: '2.8%' },
    label: 'kamu',
  },
  {
    viewBox: [103, 82],
    inset: { top: '-2.03%', right: '7.08%', bottom: '-8.78%', left: '7.08%' },
    label: 'du',
  },
];

export const artOf = (cursor: number): WordArt => (cursor < 0 ? BASE_ART : (WORD_ART[cursor] ?? BASE_ART));

/** Plain stand-in stroke for a view box: one wave with a small per-frame wobble (the 3 boil frames). */
export function standInPath(w: number, h: number, frame: number): string {
  const j = frame * 1.2;
  const f = (x: number, y: number) => `${(x * w + j).toFixed(2)} ${(y * h - j).toFixed(2)}`;
  return `M${f(0.12, 0.55)}C${f(0.3, 0.1)} ${f(0.45, 0.9)} ${f(0.62, 0.45)}S${f(0.85, 0.3)} ${f(0.9, 0.6)}`;
}
