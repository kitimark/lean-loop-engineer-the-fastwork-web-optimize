#!/usr/bin/env node
import { enforceNodePin } from "./node-guard.ts";

enforceNodePin();
if (process.argv[2] === "slot") {
  const { begin } = await import("./timing.ts");
  const end = begin("fw", "slot");
  process.once("exit", (c) => end(c));
  const { slotMain } = await import("./slot-main.ts");
  process.exitCode = await slotMain(process.argv.slice(3), process.cwd());
} else {
  await import("./fw-main.ts");
}
