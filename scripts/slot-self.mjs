#!/usr/bin/env node
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const KINDS = new Set(["check", "test"]);
const SLOT_MAIN = join(here, "..", "apps", "runner", "src", "slot-main.ts");

// `nested` is the token rule's answer (nestedHeld in apps/runner/src/slot.ts, from nestedSkips in lean/Fw/Sup/Nested.lean):
// true only when FW_SLOT_TOKEN names a live held entry of this owner. FW_SLOT_HELD alone decides nothing.
export function plan(env, args, nested = false) {
  const [kind, sep, ...cmd] = args;
  if (!KINDS.has(kind) || sep !== "--" || cmd.length === 0) return { error: "usage: slot-self.mjs <check|test> -- <cmd...>" };
  const direct = nested || Boolean(env.CI) || env.FW_SLOT_SELF === "off";
  if (direct) return { argv: cmd, routed: false };
  return { slot: ["run", "--kind", kind, "--", ...cmd], routed: true };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let nested = false;
  if (process.env.FW_SLOT_TOKEN) {
    const { enforceNodePin } = await import(pathToFileURL(join(here, "..", "apps", "runner", "src", "node-guard.ts")).href);
    enforceNodePin();
    const { nestedHeld, realDeps } = await import(pathToFileURL(join(here, "..", "apps", "runner", "src", "slot.ts")).href);
    nested = nestedHeld(realDeps(process.cwd()), process.argv[2]);
  }
  const p = plan(process.env, process.argv.slice(2), nested);
  if (p.error) { process.stderr.write(`${p.error}\n`); process.exit(2); }
  if (p.routed) {
    const { enforceNodePin } = await import(pathToFileURL(join(here, "..", "apps", "runner", "src", "node-guard.ts")).href);
    enforceNodePin();
    const { slotMainPath } = await import(pathToFileURL(join(here, "..", "apps", "runner", "src", "slot.ts")).href);
    const { slotMain } = await import(pathToFileURL(slotMainPath(SLOT_MAIN, process.cwd())).href).catch(() => import(pathToFileURL(SLOT_MAIN).href));
    const { begin } = await import(pathToFileURL(join(here, "..", "apps", "runner", "src", "timing.ts")).href);
    const { slotStep, writesOwnSpans } = await import(pathToFileURL(join(here, "..", "apps", "runner", "src", "slot-span.ts")).href);
    if (!writesOwnSpans(p.slot)) {
      const end = begin("fw", slotStep(p.slot));
      process.once("exit", (c) => end(c));
    }
    process.exitCode = await slotMain(p.slot, process.cwd());
  } else {
    const child = spawn(p.argv[0], p.argv.slice(1), { stdio: "inherit", env: { ...process.env, FW_SLOT_SELF_IN: "1" } });
    for (const s of ["SIGINT", "SIGTERM"]) process.on(s, () => child.kill(s));
    child.on("error", (e) => { process.stderr.write(`slot-self: ${e.message}\n`); process.exit(127); });
    child.on("close", (code, sig) => process.exit(code ?? (sig ? 128 + 15 : 1)));
  }
}
