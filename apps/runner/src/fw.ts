#!/usr/bin/env node
import { enforceNodePin } from "./node-guard.ts";

/** Entry of `pnpm fw` and of the Monitor command line `node apps/runner/src/fw.ts ...`. `fw slot ...` loads only
 *  slot-main.ts (a queued waiter stays small); every other group loads fw-main.ts (contracts, land, ci, plan: about
 *  120 MB), which reads process.argv itself. Dispatch on the first word only; no decision here. */
enforceNodePin();
if (process.argv[2] === "slot") {
  const { begin } = await import("./timing.ts");
  const end = begin("fw", "slot"); // the same span fw-main.ts writes for this group
  process.once("exit", (c) => end(c));
  const { slotMain } = await import("./slot-main.ts");
  process.exitCode = await slotMain(process.argv.slice(3), process.cwd());
} else {
  await import("./fw-main.ts");
}
