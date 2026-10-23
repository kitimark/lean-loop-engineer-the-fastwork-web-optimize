// The swap-window report: per window and event kind, the crop against the faithful passes, with the A/A floor of the two
// faithful captures. The verdict of one cell is swap.mjs `cell` (Lean `cell`); nothing is pooled over windows or kinds.
import { PERIODS, KINDS, FRAMES_60, validAt, cell } from './swap.mjs';

/** The count of phase `p` and kind `ty` in a capture, or null when its window `k` is not valid (a rest also needs the next window). */
export function countOf(cap, k, p, ty) {
  if (!cap) return undefined;
  const ok = validAt(cap.ws, k) && (p.startsWith('swap:') || k + 1 < cap.ws.length);
  if (!ok) return null;
  return cap.cells.find((x) => x[0] === p && x[1] === ty)?.[2] ?? null;
}

/**
 * The cells of all passes: for each phase `swap:k` / `rest:k` and each kind, the faithful counts of slot a (a1) and slot b (a2),
 * the crop counts of both slots (c), and the captures dropped as invalid. A failed capture adds no sample and no drop.
 */
export function windowCells(passes, periods = PERIODS) {
  const out = [];
  for (const phase of ['swap', 'rest']) {
    for (let k = 0; k < (phase === 'swap' ? periods : periods - 1); k++) {
      for (const ty of KINDS) {
        const p = `${phase}:${k}`;
        const a1 = [], a2 = [], c = [];
        let dropped = 0;
        const take = (cap, into) => {
          const n = countOf(cap, k, p, ty);
          if (n === undefined) return;
          if (n === null) dropped++; else into.push(n);
        };
        for (const s of passes) {
          const caps = s.captures;
          take(caps['faithful-a'], a1);
          take(caps['faithful-b'], a2);
          take(caps['crop-a'], c);
          take(caps['crop-b'], c);
        }
        out.push({ phase: p, kind: ty, a1, a2, crop: c, dropped, cell: cell(a1, a2, c, dropped) });
      }
    }
  }
  return out;
}

const range = (xs) => (xs.length === 0 ? '-' : `${Math.min(...xs)}${Math.min(...xs) === Math.max(...xs) ? '' : `-${Math.max(...xs)}`} (n=${xs.length})`);

/** Passes of the swap lane from lag JSON files. */
export const swapPassesOf = (docs) => docs.flatMap((d) => d.passes.map((p) => p.cost?.swap).filter(Boolean));

/** One table per kind: the swap windows (the unit of decision), then the rest windows as the control. */
export function swapMd(cells, sources) {
  const lines = [`Sources: ${sources.join('; ')}`, '', `Model (INFERRED from the Lean part model): a faithful swap shows ${FRAMES_60} Layout frames at 60 Hz, the crop none.`, ''];
  for (const ty of KINDS) {
    lines.push(`### ${ty}`, '', '| window | faithful a | faithful b (A/A floor) | crop | dropped | verdict |', '|---|---|---|---|---|---|');
    for (const x of cells.filter((y) => y.kind === ty)) lines.push(`| ${x.phase} | ${range(x.a1)} | ${range(x.a2)} | ${range(x.crop)} | ${x.dropped} | ${x.cell} |`);
    lines.push('');
  }
  const swaps = cells.filter((x) => x.phase.startsWith('swap:'));
  const tally = (ty) => ['win', 'loss', 'unresolved'].map((w) => swaps.filter((x) => x.kind === ty && x.cell.startsWith(w)).length);
  lines.push('Swap windows decided one by one (win / loss / unresolved of ' + PERIODS + ' per kind):', '', '| kind | win | loss | unresolved |', '|---|---|---|---|');
  for (const ty of KINDS) lines.push(`| ${ty} | ${tally(ty).join(' | ')} |`);
  return lines.join('\n');
}
