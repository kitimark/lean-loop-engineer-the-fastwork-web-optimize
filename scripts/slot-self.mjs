#!/usr/bin/env node
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const KINDS = new Set(["check", "test"]);

export function plan(env, args, fwPath = join(here, "..", "apps", "runner", "src", "fw.ts")) {
  const [kind, sep, ...cmd] = args;
  if (!KINDS.has(kind) || sep !== "--" || cmd.length === 0) return { error: "usage: slot-self.mjs <check|test> -- <cmd...>" };
  const direct = Boolean(env.FW_SLOT_HELD) || Boolean(env.CI) || env.FW_SLOT_SELF === "off";
  if (direct) return { argv: cmd, routed: false };
  return { argv: [process.execPath, fwPath, "slot", "run", "--kind", kind, "--", ...cmd], routed: true };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const p = plan(process.env, process.argv.slice(2));
  if (p.error) { process.stderr.write(`${p.error}\n`); process.exit(2); }
  const child = spawn(p.argv[0], p.argv.slice(1), { stdio: "inherit" });
  for (const s of ["SIGINT", "SIGTERM"]) process.on(s, () => child.kill(s));
  child.on("error", (e) => { process.stderr.write(`slot-self: ${e.message}\n`); process.exit(127); });
  child.on("close", (code, sig) => process.exit(code ?? (sig ? 128 + 15 : 1)));
}
