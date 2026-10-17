import { project, apply } from "../src/core/reducer.ts";
import { cases, ev } from "./cases.ts";

/** table cases + duplicate cases, as { request, response } pairs for `console.apply` */
export function goldenCases() {
  const out = cases().map((c) => {
    const state = project(c.setup);
    return { name: c.name, request: { state, event: c.event }, response: apply(state, c.event) };
  });
  const setup = [ev({ type: "card.open", actor: "owner", card: "A", owner: "o", needsDevice: false }, "dup-key")];
  const state = project(setup);
  out.push({ name: "duplicate key is a no-op", request: { state, event: setup[0]! }, response: apply(state, setup[0]!) });
  return out;
}
