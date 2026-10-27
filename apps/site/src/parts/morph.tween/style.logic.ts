export { FLIP_CLASS } from '../morph.geom/tree';

/** Lean `Fw.Parts.MorphStyle.writes`: the flip skips the per-frame style writes it has no reader for while `m > 0`. */
export const writes = (flip: boolean, m: number): boolean => !(flip && m > 0);
