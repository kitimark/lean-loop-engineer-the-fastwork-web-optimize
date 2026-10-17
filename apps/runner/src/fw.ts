#!/usr/bin/env node
import { Command } from "@fw/contracts";
import { UsageError, apiBase, renderBoard, send, stepCommand } from "./lib.ts";
import { CARD_USAGE, cardCommand } from "./card.ts";
import { httpFor, land } from "./land.ts";
import { watchMain } from "./watch.ts";

const [group, ...rest] = process.argv.slice(2);
try {
  const base = apiBase(process.env);
  if (group === "watch") {
    process.exitCode = await watchMain(rest, process.cwd());
  } else if (group === "status") {
    const b = await (await fetch(`${base}/api/board`)).json();
    console.log(renderBoard(b as never));
  } else if (group === "land") {
    if (!rest[0]) throw new UsageError("usage: fw land <card/branch>");
    const res = await land(rest[0], { http: httpFor(base), cwd: process.cwd(), argv: process.argv.slice(2),
      // FW_LAND_CHECKS='[["cmd","arg"]]' replaces the default fast checks (used by the e2e script on a temp repo)
      checks: process.env.FW_LAND_CHECKS ? JSON.parse(process.env.FW_LAND_CHECKS) : undefined });
    for (const l of res.lines) (res.ok ? console.log : console.error)(l);
    if (!res.ok) process.exitCode = 2;
  } else if (group === "step" || group === "card" || group === "send") {
    // `fw send '<json command>'` is the escape hatch for run.* commands
    const cmd = group === "step" ? stepCommand(rest, process.env)
      : group === "card" ? cardCommand(rest, process.env)
      : Command.parse(JSON.parse(rest[0] ?? "{}"));
    const { body } = await send(base, cmd, process.argv.slice(2));
    if (body.ok) console.log(body.duplicate ? "duplicate (already applied)" : `ok seq ${body.seq}`);
    else { console.error(`refused: ${body.reason}`); process.exitCode = 2; }
  } else {
    throw new UsageError(`usage: fw status | fw watch [--json] [--interval s] [--until-alert] | fw land <card/branch> | fw step post|start|answer|done|cancel ... | fw send '<json>'\n${CARD_USAGE}`);
  }
} catch (e) {
  console.error(e instanceof Error ? e.message : String(e));
  process.exitCode ||= e instanceof UsageError ? 64 : 1;
}
