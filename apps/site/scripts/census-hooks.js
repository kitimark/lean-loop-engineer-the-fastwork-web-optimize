// Injected before any page script (evaluateOnNewDocument). Records every way a page can change its style sheets.
// Events carry the phase and whether `__fw.markMeasureStart()` has been called ("armed").
(() => {
  const c = (window.__census = { armed: false, phase: 'load', events: [] });
  const rec = (kind, detail) =>
    c.events.push({ kind, phase: c.phase, armed: c.armed, detail: String(detail ?? '').slice(0, 100) });

  window.addEventListener('fw:measure-start', () => {
    c.flush(); // attribute pending DOM mutations to the phase they happened in
    c.start = c.snapshot();
    c.armed = true;
    c.phase = 'scroll';
  });

  const wrap = (proto, name, kind) => {
    const orig = proto && proto[name];
    if (typeof orig !== 'function') return;
    proto[name] = function (...args) {
      rec(kind, `${name}(${typeof args[0] === 'string' ? args[0] : ''})`);
      return orig.apply(this, args);
    };
  };
  for (const n of ['insertRule', 'deleteRule', 'addRule', 'removeRule', 'replace', 'replaceSync'])
    wrap(window.CSSStyleSheet?.prototype, n, 'CSSStyleSheet');
  for (const n of ['insertRule', 'deleteRule']) wrap(window.CSSGroupingRule?.prototype, n, 'CSSGroupingRule');

  // Writes through an existing rule's style (not inline element styles).
  const sd = window.CSSStyleDeclaration?.prototype;
  if (sd) {
    for (const n of ['setProperty', 'removeProperty']) {
      const orig = sd[n];
      sd[n] = function (...args) {
        if (this.parentRule) rec('rule.style', `${n}(${args[0]})`);
        return orig.apply(this, args);
      };
    }
  }

  // adoptedStyleSheets setter on Document and ShadowRoot.
  for (const proto of [window.Document?.prototype, window.ShadowRoot?.prototype]) {
    const d = proto && Object.getOwnPropertyDescriptor(proto, 'adoptedStyleSheets');
    if (d && d.set) {
      Object.defineProperty(proto, 'adoptedStyleSheets', {
        ...d,
        set(v) {
          rec('adoptedStyleSheets', `length=${v.length}`);
          return d.set.call(this, v);
        },
      });
    }
  }

  // <style> / <link rel=stylesheet> insertions, removals, moves, text edits, and <html> attribute writes.
  const isSheetNode = (n) =>
    n.nodeType === 1 && (n.tagName === 'STYLE' || (n.tagName === 'LINK' && /stylesheet/i.test(n.rel || '')));
  const onRecords = (records) => {
    for (const r of records) {
      if (r.type === 'childList') {
        for (const n of r.addedNodes) if (isSheetNode(n)) rec('style-node-added', n.outerHTML.slice(0, 60));
        for (const n of r.removedNodes) if (isSheetNode(n)) rec('style-node-removed', n.outerHTML.slice(0, 60));
        const t = r.target;
        if (t.nodeType === 1 && t.tagName === 'STYLE') rec('style-text-edit', 'childList in <style>');
      } else if (r.type === 'characterData') {
        const p = r.target.parentNode;
        if (p && p.tagName === 'STYLE') rec('style-text-edit', 'characterData');
      } else if (r.type === 'attributes') {
        if (r.target === document.documentElement) rec('html-attribute', r.attributeName);
        else if (isSheetNode(r.target)) rec('style-attr', r.attributeName);
      }
    }
  };
  const mo = new MutationObserver(onRecords);
  mo.observe(document, { childList: true, subtree: true, characterData: true, attributes: true });
  c.flush = () => {
    const pending = mo.takeRecords();
    onRecords(pending);
    return pending.length;
  };

  c.snapshot = () => {
    let rules = 0;
    const walk = (list) => {
      for (const r of list) {
        rules++;
        if (r.cssRules) walk(r.cssRules);
      }
    };
    for (const s of document.styleSheets) {
      try {
        walk(s.cssRules);
      } catch {
        /* cross-origin */
      }
    }
    return {
      sheets: document.styleSheets.length,
      adopted: document.adoptedStyleSheets.length,
      rules,
      styleTags: document.querySelectorAll('style').length,
    };
  };
})();
