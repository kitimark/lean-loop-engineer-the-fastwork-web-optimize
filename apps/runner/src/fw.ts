#!/usr/bin/env node
import { Command } from "@fw/contracts";
import { UsageError, apiBase, renderBoard, send, stepCommand } from "./lib.ts";

const [group, ...rest] = process.argv.slice(2);
try {
  const base = apiBase(process.env);
  if (group === "status") {
    const b = await (await fetch(`${base}/api/board`)).json();
    console.log(renderBoard(b as never));
  } else if (group === "step" || group === "send") {
    // `fw send '<json command>'` is the escape hatch for card.* and run.* commands
    const cmd = group === "step" ? stepCommand(rest, process.env) : Command.parse(JSON.parse(rest[0] ?? "{}"));
    const { body } = await send(base, cmd);
    if (body.ok) console.log(body.duplicate ? "duplicate (already applied)" : `ok seq ${body.seq}`);
    else { console.error(`refused: ${body.reason}`); process.exitCode = 2; }
  } else {
    throw new UsageError("usage: fw status | fw step post|start|answer|done|cancel ... | fw send '<json>'");
  }
} catch (e) {
  console.error(e instanceof Error ? e.message : String(e));
  process.exitCode ||= e instanceof UsageError ? 64 : 1;
}
