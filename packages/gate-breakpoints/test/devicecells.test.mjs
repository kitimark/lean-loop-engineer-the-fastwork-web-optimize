import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { loadGen } from '../src/spec.mjs';
import { fwcoreBin } from '../src/verdict.mjs';
import { gapCells } from '../src/gaps/cells.mjs';
import { deviceCells } from '../src/gaps/devicecells.mjs';

const { gen } = loadGen();
const hasCore = (() => { try { return existsSync(fwcoreBin()); } catch { return false; } })();
const withCore = (name, fn) => test(name, { skip: hasCore ? false : 'fwcore is not built (set FW_CORE_BIN)' }, fn);

const touch = { hover: false, hoverNone: true, pointerFine: false, pointerCoarse: true, pointerNone: false };
const rec = (req, mediaWidth, pointer = touch) => ({ req, gap: { mediaWidth, vvWidth: mediaWidth, innerWidth: mediaWidth, screenWidth: 430, pointer } });
const sets = (phoneWidth = (w) => Math.ceil(w)) => {
  const cells = gapCells(gen);
  const recs = [rec({ load: 0 }, 430), rec({ load: 1 }, 430),
    ...cells.filter((c) => c.kind === 'fractional').flatMap((c) => [
      rec({ variant: `vp-width-${c.probe.width}`, aimed: c.probe.width }, phoneWidth(c.probe.width)),
      rec({ variant: `aim-${c.probe.width}`, aimed: c.probe.width }, phoneWidth(c.probe.width))])];
  return { cells, recs };
};

withCore('phone equal to the Simulator and not realizing any request: all 8 cells agree (Lean says unreachable)', () => {
  const { cells, recs } = sets();
  const r = deviceCells({ cells, device: recs, sim: recs });
  assert.equal(r.agree, 8);
  assert.ok(r.cells.every((c) => c.lean.startsWith('unreachable:') && c.realizedOnPhone === false));
});

withCore('a phone that reports the fractional width, or differs from the Simulator, disagrees on exactly those cells', () => {
  const { cells, recs } = sets();
  const frac = sets((w) => w); // a phone that realized 600.5 etc.
  const r = deviceCells({ cells, device: frac.recs, sim: recs });
  assert.equal(r.cells.filter((c) => c.kind === 'fractional' && !c.agree).length, 4);
  assert.ok(r.cells.filter((c) => c.kind === 'fractional').every((c) => c.why.some((w) => /realized/.test(w))));
  const other = sets((w) => Math.floor(w));
  const r2 = deviceCells({ cells, device: other.recs, sim: recs });
  assert.ok(r2.cells.filter((c) => c.kind === 'fractional').every((c) => !c.agree && c.why.some((w) => /differ/.test(w))));
  assert.ok(r2.cells.filter((c) => c.kind === 'cross').every((c) => c.agree));
});
