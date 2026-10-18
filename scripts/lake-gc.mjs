#!/usr/bin/env node
// Lake artifact cache report (task lean-bin-slim), the same as `pnpm -s fw lake-gc` without the fw runner:
//   node scripts/lake-gc.mjs [--list | --json] [--check] [--age-floor <s>] [--root <cache>/artifacts]
// Facts are gathered by apps/runner/src/lake-gc.ts; the list and the budget verdict are Lean (`fwcore` ops.lakeGc,
// lean/Fw/Ops/LakeGc.lean). It never deletes. Docs: docs/team/tools/lake-gc.md.
import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { LakeGcUsage, lakeGcCli } from "../apps/runner/src/lake-gc.ts";

export const top = join(dirname(fileURLToPath(import.meta.url)), "..");

/** One request to the fwcore binary `bin`, one reply; an `error` reply or a failed run throws. */
export function coreCall(bin) {
  if (!existsSync(bin)) throw new Error(`fwcore not built: sh scripts/fwcore-build.sh (${bin})`);
  return (req) => {
    const r = spawnSync(bin, [], { input: JSON.stringify({ ...req, id: 0 }) + "\n", encoding: "utf8", maxBuffer: 1 << 30 });
    if (r.status !== 0) throw new Error(`fwcore exited with ${r.status ?? r.signal}: ${r.stderr}`);
    const { id: _id, ...rest } = JSON.parse(r.stdout.split("\n")[0]);
    if (typeof rest.error === "string") throw new Error(`fwcore ${req.op}: ${rest.error}`);
    return rest;
  };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    process.exitCode = lakeGcCli(process.argv.slice(2), top, coreCall(process.env.FW_CORE_BIN ?? join(top, "lean/.lake/build/bin/fwcore")));
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    process.exitCode = e instanceof LakeGcUsage ? 64 : 1;
  }
}
