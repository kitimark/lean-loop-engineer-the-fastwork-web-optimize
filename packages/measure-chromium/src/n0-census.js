// N0 census (PLAN 6.7), page side. Injected after the clock shim and before any page script
// (Page.addScriptToEvaluateOnNewDocument). Records every way a page can change its style sheets after it was written:
// the CSSOM write APIs and the sheet nodes of <head>. Each event is stamped with the VIRTUAL time (performance.now(),
// the shim's clock), so the driver can put it in a frame afterwards; nothing is read while a frame is running.
// Written for this experiment from the public specs; contains no site code.
//
// Neutrality: the wrappers call the original and return its result. The only observers are MutationObservers on
// <html>/<head>/<body> child lists (not subtree) and, per <style>/<link> node, on its own text and attributes. They
// fire only when a sheet node is added, removed or edited, so a page that never touches its sheets gets no callback and
// no extra trace event from this script.
(() => {
  if (globalThis.__fwN0) return;
  const events = [];
  const now = () => performance.now();
  const rec = (kind, detail) => events.push({ kind, vt: now(), detail: String(detail ?? '').slice(0, 80) });

  const wrap = (proto, name, kind) => {
    const orig = proto && proto[name];
    if (typeof orig !== 'function') return;
    proto[name] = function (...args) { rec(kind, `${name}(${typeof args[0] === 'string' ? args[0] : ''})`); return orig.apply(this, args); };
  };
  const wrapSetter = (proto, name, kind, only) => {
    const d = proto && Object.getOwnPropertyDescriptor(proto, name);
    if (!d || !d.set) return;
    Object.defineProperty(proto, name, { ...d, set(v) { if (!only || only(this)) rec(kind, `set ${name}`); return d.set.call(this, v); } });
  };

  for (const n of ['insertRule', 'deleteRule', 'addRule', 'removeRule', 'replace', 'replaceSync']) wrap(self.CSSStyleSheet?.prototype, n, 'cssom.sheet');
  for (const n of ['insertRule', 'deleteRule']) wrap(self.CSSGroupingRule?.prototype, n, 'cssom.grouping');
  for (const n of ['appendRule', 'deleteRule']) wrap(self.CSSKeyframesRule?.prototype, n, 'cssom.keyframes');
  wrapSetter(self.CSSStyleRule?.prototype, 'selectorText', 'cssom.selectorText');
  wrapSetter(self.StyleSheet?.prototype, 'disabled', 'cssom.sheetDisabled');
  for (const n of ['appendMedium', 'deleteMedium']) wrap(self.MediaList?.prototype, n, 'cssom.media');
  wrapSetter(self.MediaList?.prototype, 'mediaText', 'cssom.media');
  // Writes through a RULE's style (parentRule != null); inline element styles stay allowed.
  const sd = self.CSSStyleDeclaration?.prototype;
  if (sd) {
    for (const n of ['setProperty', 'removeProperty']) {
      const orig = sd[n];
      if (typeof orig === 'function') sd[n] = function (...args) { if (this.parentRule) rec('cssom.ruleStyle', `${n}(${args[0]})`); return orig.apply(this, args); };
    }
    for (const name of Object.getOwnPropertyNames(sd)) wrapSetter(sd, name, 'cssom.ruleStyle', (self_) => !!self_.parentRule);
  }
  for (const proto of [self.Document?.prototype, self.ShadowRoot?.prototype]) wrapSetter(proto, 'adoptedStyleSheets', 'adoptedStyleSheets');

  // Sheet nodes: <style> and <link rel=stylesheet>.
  const isSheetNode = (n) => n && n.nodeType === 1 && (n.tagName === 'STYLE' || (n.tagName === 'LINK' && /stylesheet/i.test(n.rel || '')));
  const own = new WeakSet();
  const watchNode = (n) => {
    if (own.has(n)) return;
    own.add(n);
    new MutationObserver((rs) => { for (const r of rs) rec(r.type === 'attributes' ? 'sheetNode.attr' : 'sheetNode.text', r.attributeName || r.type); })
      .observe(n, { childList: true, characterData: true, subtree: true, attributes: true });
  };
  const onChildren = (rs) => {
    for (const r of rs) {
      for (const n of r.addedNodes) if (isSheetNode(n)) { rec('sheetNode.added', n.tagName); watchNode(n); }
      for (const n of r.removedNodes) if (isSheetNode(n)) rec('sheetNode.removed', n.tagName);
    }
    attach(); // a <head> or <body> may have just been created
  };
  const childMo = new MutationObserver(onChildren);
  const watched = new WeakSet();
  const watchChildren = (el) => { if (el && !watched.has(el)) { watched.add(el); childMo.observe(el, { childList: true }); for (const c of el.children) if (isSheetNode(c)) watchNode(c); } };
  const attach = () => {
    const de = document.documentElement;
    if (!de) return;
    watchChildren(de);
    watchChildren(document.head);
    watchChildren(document.body);
  };
  // <html>, <head> and <body> do not exist yet when this script runs: one observer on the document itself, plus the
  // children observer above, finds them as the parser creates them (load window only, never recorded).
  const boot = new MutationObserver(() => { attach(); if (document.body) boot.disconnect(); });
  boot.observe(document, { childList: true });
  attach();

  // Shape of every style sheet at a window edge: counts and a hash of the rule texts in order (FNV-1a, 32 bit).
  const shape = () => {
    let rules = 0, h = 0x811c9dc5;
    const feed = (s) => { for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 0x01000193) >>> 0; } };
    const walk = (list) => { for (const r of list) { rules++; feed(r.cssText); } };
    const sheets = [...document.styleSheets, ...(document.adoptedStyleSheets || [])];
    for (const s of sheets) { try { walk(s.cssRules); feed('|'); } catch { feed('x'); } }
    return {
      sheets: document.styleSheets.length, adopted: (document.adoptedStyleSheets || []).length, rules, ruleHash: h.toString(16),
      styleTags: document.querySelectorAll('style').length, linkSheets: document.querySelectorAll('link[rel~=stylesheet]').length,
    };
  };
  const flush = () => { const rs = childMo.takeRecords(); if (rs.length) onChildren(rs); };
  globalThis.__fwN0 = { events, shape, flush, read: () => { flush(); return { events: events.slice(), shape: shape() }; } };
})();
