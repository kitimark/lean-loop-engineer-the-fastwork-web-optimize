/** Variant `scoped` (Lean `Fw.Parts.HeroExitOpt`, section Scoped); constants checked against `hero.exit.scoped.json`. */
export const SCOPED = 'scoped';
export const SCOPE_ATTR = 'data-exit-scope';
export const SCOPED_PROPS = [
  { name: '--exit-opacity', syntax: '*', inherits: false },
  { name: '--exit-scatter', syntax: '*', inherits: false },
] as const;

export interface PropertyRegistry {
  registerProperty(def: { name: string; syntax: string; inherits: boolean }): void;
}

let registered = false;

/** Registers the exit properties once per document; a property another script registered first stays as it is. */
export function registerScoped(css: Partial<PropertyRegistry> | undefined): void {
  if (registered || typeof css?.registerProperty !== 'function') return;
  registered = true;
  for (const def of SCOPED_PROPS) {
    try {
      css.registerProperty({ ...def });
    } catch (e) {
      if (!(e instanceof DOMException && e.name === 'InvalidModificationError')) throw e;
    }
  }
}
