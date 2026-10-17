import { panelFilterState, panelFlags, type PanelFilterState, type PanelFlags } from './logic';

interface AttrNode {
  setAttribute(n: string, v: string): void;
  removeAttribute(n: string): void;
}
/** The nodes the flags are written on. `cta` may be absent before it is mounted. */
export interface PanelNodes {
  panel: AttrNode;
  cta: AttrNode | null;
}

/**
 * Write the morph-dependent attributes (original: Svelte effects, 13196-13199): `data-start-selling-scene`, `aria-hidden`
 * on the panel, `tabindex` on the call-to-action, and `data-expanded` (stands for the nav's `.is-expanded` class that
 * gives the panel `pointer-events: auto`). Writes only attributes whose value changed since the last call, so a tween
 * driving it per frame touches the DOM only at the 0.001, 0.35, 0.55 and 0.92 crossings. No React state.
 */
export function createPanelWriter(nodes: PanelNodes, opts: { rest?: boolean } = {}) {
  let last: PanelFlags | null = null;
  let lastState: PanelFilterState | null = null;
  return {
    apply(morph: number): PanelFlags {
      const f = panelFlags(morph);
      if (!last || last.scene !== f.scene) nodes.panel.setAttribute('data-start-selling-scene', f.scene);
      if (!last || last.ariaHidden !== f.ariaHidden) nodes.panel.setAttribute('aria-hidden', String(f.ariaHidden));
      if (!last || last.expanded !== f.expanded) {
        if (f.expanded) nodes.panel.setAttribute('data-expanded', '');
        else nodes.panel.removeAttribute('data-expanded');
      }
      if (nodes.cta && (!last || last.ctaTabindexOff !== f.ctaTabindexOff)) {
        if (f.ctaTabindexOff) nodes.cta.setAttribute('tabindex', '-1');
        else nodes.cta.removeAttribute('tabindex');
      }
      if (opts.rest) {
        // variant `rest`: `data-fw-filter` is `rest` (CSS: filter none) or `fade` (CSS: own layer); written only at the toggle
        const s = panelFilterState(morph);
        if (s !== lastState) nodes.panel.setAttribute('data-fw-filter', s);
        lastState = s;
      }
      last = f;
      return f;
    },
  };
}
