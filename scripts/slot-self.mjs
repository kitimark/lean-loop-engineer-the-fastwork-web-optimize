#!/usr/bin/env node
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const KINDS = new Set(["check", "test"]);
const SLOT_MAIN = join(here, "..", "apps", "runner", "src", "slot-main.ts");

/** What to do for `slot-self.mjs <kind> -- <cmd...>`. Routed: `slot` holds the `fw slot run` arguments, which this
 *  process runs itself (slot-waiter-light: the wait loop lives in this one node process, no second fw process).
 *  Direct (held, CI, FW_SLOT_SELF=off): `argv` is the command. */
export function plan(env, args) {
  const [kind, sep, ...cmd] = args;
  if (!KINDS.has(kind) || sep !== "--" || cmd.length === 0) return { error: "usage: slot-self.mjs <check|test> -- <cmd...>" };
  const direct = Boolean(env.FW_SLOT_HELD) || Boolean(env.CI) || env.FW_SLOT_SELF === "off";
  if (direct) return { argv: cmd, routed: false };
  return { slot: ["run", "--kind", kind, "--", ...cmd], routed: true };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const p = plan(process.env, process.argv.slice(2));
  if (p.error) { process.stderr.write(`${p.error}\n`); process.exit(2); }
  if (p.routed) {
    const { slotMain } = await import(pathToFileURL(SLOT_MAIN).href);
    const { begin } = await import(pathToFileURL(join(here, "..", "apps", "runner", "src", "timing.ts")).href);
    const end = begin("fw", "slot"); // the span `fw slot run` wrote before
    process.once("exit", (c) => end(c));
    process.exitCode = await slotMain(p.slot, process.cwd()); // exitCode, not exit(): piped output flushes
  } else {
    const child = spawn(p.argv[0], p.argv.slice(1), { stdio: "inherit" });
    for (const s of ["SIGINT", "SIGTERM"]) process.on(s, () => child.kill(s));
    child.on("error", (e) => { process.stderr.write(`slot-self: ${e.message}\n`); process.exit(127); });
    child.on("close", (code, sig) => process.exit(code ?? (sig ? 128 + 15 : 1)));
  }
}
