import { quietTypes } from './quiet.gen';

const quiet: ReadonlySet<string> = new Set(quietTypes);

export const QUIET_VARIANT = 'quiet';

/** Does the quiet root let a listener of this type through? Lean `Fw.Parts.ReactRootOpt.admit`. */
export const admit = (type: string): boolean => !quiet.has(type);

/** The container's own `addEventListener` drops the quiet types; React registers its root listeners through it. */
export function quietContainer(el: EventTarget): void {
  const add = el.addEventListener;
  el.addEventListener = function (this: EventTarget, type: string, listener: EventListenerOrEventListenerObject | null, options?: boolean | AddEventListenerOptions) {
    if (!admit(type)) return;
    add.call(this, type, listener, options);
  } as EventTarget['addEventListener'];
}
