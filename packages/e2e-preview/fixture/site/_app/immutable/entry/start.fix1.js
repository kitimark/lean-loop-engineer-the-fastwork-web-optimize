import { note } from "../chunks/shared.fix1.js";
export function start(app) {
  globalThis.__fixtureHydrations = (globalThis.__fixtureHydrations || 0) + 1;
  document.getElementById("mount").textContent = `hydrated ${note} ${app.nodes.length}`;
  document.documentElement.setAttribute("data-hydrated", String(globalThis.__fixtureHydrations));
  // client-side navigation: an internal link loads its route's node module by a root-absolute dynamic import, then pushes the URL
  document.addEventListener("click", async (ev) => {
    const a = ev.target.closest && ev.target.closest("a[data-route]");
    if (!a || ev.defaultPrevented || ev.metaKey || ev.ctrlKey) return;
    ev.preventDefault();
    const node = await import(`/_app/immutable/nodes/${a.dataset.route}.fix1.js`);
    history.pushState({}, "", a.getAttribute("href"));
    document.getElementById("title").textContent = node.title;
    document.documentElement.setAttribute("data-route", a.dataset.route);
  });
}
