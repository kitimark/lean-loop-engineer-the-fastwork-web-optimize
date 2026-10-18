import { describe, expect, it } from 'vitest';
import { goldenConformance } from '../../engine/golden.testutil';
import * as L from './logic';

const form = (o: Record<string, unknown>) => o as unknown as L.Form;

goldenConformance('overlays.signup', {
  dir: (i) => L.dir(i.x as number, i.y as number),
  openDir: (i) => L.openDir({ x: i.x as number, y: i.y as number }),
  openDirNone: () => L.openDir(null),
  frame: (i) => L.frame(i.dx as number, i.dy as number, i.elapsed as number, i.reduced as boolean),
  react: (i) => L.react(i.source as L.Source, i.purpose as L.Purpose, i.self as boolean, i.composing as boolean, i.layered as boolean),
  closeAllowed: (i) => L.closeAllowed(i.submitting as boolean),
  sync: (i) => L.sync(i.isOpen as boolean, i.domOpen as boolean),
  valid: (i) => L.valid(i.name as string, i.email as string),
  submit: (i) => {
    const r = L.submit(form(i.form), i.valid as boolean, i.hasHandler as boolean);
    return { form: r.form, send: r.send };
  },
  settle: (i) => L.settle(form(i.form), i.ok as boolean),
});

describe('overlays.signup logic', () => {
  it('the enter animation starts offset and small and ends in place', () => {
    expect(L.frame(0, 16, 0, false)).toEqual({ opacity: 0, tx: 0, ty: 16, scale: 0.95 });
    expect(L.frame(0, 16, 400, false)).toEqual({ opacity: 1, tx: 0, ty: 0, scale: 1 });
    expect(L.frame(0, 16, 0, true)).toEqual({ opacity: 1, tx: 0, ty: 0, scale: 1 });
  });
  it('the direction rounds like Math.round', () => {
    expect(L.dir(3, 4)).toEqual([10, 13]);
    expect(L.openDir(null)).toEqual([0, 16]);
    expect(L.triggerOffset({ left: 100, top: 20, width: 80, height: 40 }, 1000, 800)).toEqual({ x: -360, y: -360 });
  });
  it('the close guard follows the submitting flag', () => {
    const sent = L.submit(L.FORM_INIT, true, true);
    expect(sent.send).toBe(true);
    expect(L.closeAllowed(sent.form.submitting)).toBe(false);
    expect(L.closeAllowed(L.settle(sent.form, true).submitting)).toBe(true);
  });
});
