import { note } from "../chunks/shared.fix1.js";
export function start(app) {
  globalThis.__fixtureHydrations = (globalThis.__fixtureHydrations || 0) + 1;
  document.getElementById("mount").textContent = `hydrated ${note} ${app.nodes.length}`;
  document.documentElement.setAttribute("data-hydrated", String(globalThis.__fixtureHydrations));
}
