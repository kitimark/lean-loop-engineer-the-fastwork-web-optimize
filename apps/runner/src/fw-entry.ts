import { enforceNodePin } from "./node-guard.ts";

/** Entry of `pnpm fw`. `fw slot ...` loads only slot-main.ts (a queued waiter stays small); every other group loads
 *  fw.ts, which reads process.argv itself. Dispatch on the first word only; no decision here. */
enforceNodePin();
if (process.argv[2] === "slot") {
  const { begin } = await import("./timing.ts");
  const end = begin("fw", "slot"); // the same span fw.ts writes for this group
  process.once("exit", (c) => end(c));
  const { slotMain } = await import("./slot-main.ts");
  process.exitCode = await slotMain(process.argv.slice(3), process.cwd());
} else {
  await import("./fw.ts");
}
