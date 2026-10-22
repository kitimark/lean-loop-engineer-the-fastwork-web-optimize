#!/usr/bin/env node
import { enforceNodePin } from "./node-guard.ts";

enforceNodePin();
if (process.argv[2] === "slot") {
  const { begin } = await import("./timing.ts");
  const { slotStep, writesOwnSpans } = await import("./slot-span.ts");
  if (!writesOwnSpans(process.argv.slice(3))) {
    const { queueExtra } = await import("./slot-queue.ts");
    const end = begin("fw", slotStep(process.argv.slice(3)));
    process.once("exit", (c) => end(c, queueExtra()));
  }
  const { slotMainPath } = await import("./slot.ts");
  const { fileURLToPath, pathToFileURL } = await import("node:url");
  const local = fileURLToPath(new URL("./slot-main.ts", import.meta.url));
  const { slotMain } = await import(pathToFileURL(slotMainPath(local, process.cwd())).href).catch(() => import(pathToFileURL(local).href));
  process.exitCode = await slotMain(process.argv.slice(3), process.cwd());
} else {
  await import("./fw-main.ts");
}
