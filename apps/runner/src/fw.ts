#!/usr/bin/env node
import { enforceNodePin } from "./node-guard.ts";

enforceNodePin();
if (process.argv[2] === "slot") {
  const { begin } = await import("./timing.ts");
  const end = begin("fw", "slot");
  process.once("exit", (c) => end(c));
  const { slotMainPath } = await import("./slot.ts");
  const { pathToFileURL } = await import("node:url");
  const local = new URL("./slot-main.ts", import.meta.url).pathname;
  const { slotMain } = await import(pathToFileURL(slotMainPath(local, process.cwd())).href);
  process.exitCode = await slotMain(process.argv.slice(3), process.cwd());
} else {
  await import("./fw-main.ts");
}
