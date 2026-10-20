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

/** Lean `readers`, selected by the attributes their parts render; scoped.test.ts checks it against the reader classes. */
export const READER_SELECTOR = '[data-fw="hero"], [data-fw="hero-cue"], [data-orbit-id], [data-fw="hero-deck"] > article';

export interface ReaderList {
  get(): readonly HTMLElement[];
  stop(): void;
}

/** The readers under `root`, queried again after a child-list or reader-attribute change below it. */
export function liveReaders(root: Element): ReaderList {
  const query = () => [...root.querySelectorAll<HTMLElement>(READER_SELECTOR)];
  let list = query();
  const mo = new MutationObserver(() => {
    list = query();
  });
  mo.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-fw', 'data-orbit-id'] });
  const get = () => {
    if (mo.takeRecords().length) list = query();
    return list;
  };
  return { get, stop: () => mo.disconnect() };
}

/** Lean `readerWrites`: what the driver writes on each reader for the stage write `opacity`. */
export function readerWrites(reduced: boolean, opacity: string): [string, string][] {
  return [
    ['--exit-opacity', opacity],
    ['--exit-scatter', reduced ? '0' : `calc(1 - ${opacity})`],
  ];
}
