// A timeline of one preview-e2e load, for finding the cause of a failed request check (debug runs only: `--trace`).
// Node side: the requests, failures and navigations of the page with their frame and a time in ms from the start of the load.
// Page side: what the page did to one image (`WATCH`): when it was added, removed or given a source, whether it had finished
// loading, where the scroll was. Nothing here decides a check.

/** The image file the failed runs named (a post image of the original arm). */
export const WATCH = "service-strawberry";

/** Runs in every frame before its scripts (context.addInitScript). Collects into `window.__fwTrace`. */
export const PAGE_TRACE = `(() => {
  if (window.__fwTrace) return;
  const T = (window.__fwTrace = []);
  const W = ${JSON.stringify(WATCH)};
  const hit = (s) => typeof s === "string" && s.includes(W);
  const log = (e) => T.push({ t: Date.now(), ...e });
  const stack = () => String(new Error().stack).split("\\n").slice(2, 7).map((l) => l.trim().replace(/^.*\\//, "")).join(" < ");
  const state = (img) => ({ src: img.getAttribute("src"), complete: img.complete, nw: img.naturalWidth, conn: img.isConnected, loading: img.loading, top: Math.round(img.getBoundingClientRect().top), sy: Math.round(scrollY), vw: innerWidth });
  log({ k: "init", url: location.href, top: window === window.top });
  const sd = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, "src");
  if (sd && sd.set) Object.defineProperty(HTMLImageElement.prototype, "src", { ...sd, set(v) { if (hit(String(v))) log({ k: "src-set", v: String(v), stack: stack() }); return sd.set.call(this, v); } });
  const sa = Element.prototype.setAttribute;
  Element.prototype.setAttribute = function (n, v) { if (n === "src" && this instanceof HTMLImageElement && hit(String(v))) log({ k: "setAttribute-src", stack: stack() }); return sa.call(this, n, v); };
  const imgsOf = (n) => (n.nodeType !== 1 ? [] : n.matches("img") ? [n] : [...n.querySelectorAll("img")]);
  new MutationObserver((rs) => {
    for (const r of rs) {
      if (r.type === "attributes") { if (r.target instanceof HTMLImageElement && (hit(r.target.getAttribute("src")) || hit(r.oldValue))) log({ k: "attr-" + r.attributeName, old: r.oldValue, ...state(r.target) }); continue; }
      for (const n of r.addedNodes) for (const i of imgsOf(n)) if (hit(i.getAttribute("src"))) log({ k: "added", ...state(i) });
      for (const n of r.removedNodes) for (const i of imgsOf(n)) if (hit(i.getAttribute("src"))) log({ k: "removed", ...state(i) });
    }
  }).observe(document, { childList: true, subtree: true, attributes: true, attributeOldValue: true, attributeFilter: ["src", "srcset", "loading"] });
  for (const ev of ["load", "error"]) document.addEventListener(ev, (e) => { if (e.target instanceof HTMLImageElement && hit(e.target.getAttribute("src"))) log({ k: "img-" + ev, ...state(e.target) }); }, true);
  for (const ev of ["DOMContentLoaded", "load", "pagehide"]) addEventListener(ev, () => log({ k: "win-" + ev }));
  let last = "";
  const iv = setInterval(() => {
    const s = [...document.images].filter((i) => hit(i.getAttribute("src"))).map((i) => JSON.stringify(state(i))).join(" ; ");
    if (s !== last) { last = s; log({ k: "poll", s }); }
  }, 100);
  setTimeout(() => clearInterval(iv), 20000);
})();`;

/** The node-side timeline of one load: `mark(name)` for the harness's own steps, `wire(page)` for the browser's events. */
export function makeTracer() {
  const t0 = Date.now();
  const ev = [];
  const push = (e) => ev.push({ t: Date.now() - t0, ...e });
  const where = (r) => { try { const f = r.frame(); return f === f.page().mainFrame() ? "main" : `child:${new URL(f.url()).port || f.url()}`; } catch { return "?"; } };
  const short = (u) => { const x = new URL(u); return `${x.port}${x.pathname}`; };
  return {
    t0, ev, mark: (name) => push({ k: "mark", name }),
    wire(page) {
      const pick = (r) => /service-strawberry|\.html?$|\/$/.test(new URL(r.url()).pathname);
      page.context().on("request", (r) => { if (pick(r)) push({ k: "request", u: short(r.url()), type: r.resourceType(), frame: where(r) }); });
      page.context().on("requestfinished", (r) => { if (pick(r)) push({ k: "finished", u: short(r.url()), frame: where(r) }); });
      page.context().on("requestfailed", (r) => push({ k: "FAILED", u: short(r.url()), err: r.failure()?.errorText, frame: where(r), type: r.resourceType() }));
      page.on("framenavigated", (f) => push({ k: "framenavigated", frame: f === page.mainFrame() ? "main" : "child", u: short(f.url()) }));
      page.on("load", () => push({ k: "page-load" }));
      page.on("domcontentloaded", () => push({ k: "page-domcontentloaded" }));
    },
  };
}
