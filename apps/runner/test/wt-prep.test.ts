import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// scripts/wt-prep.sh --build-pids: which `ps -axo pid=,args=` lines count as a running `lake build` (the Lean LSP does not)
const script = join(dirname(fileURLToPath(import.meta.url)), "../../../scripts/wt-prep.sh");
const pids = (ps: string) => spawnSync("sh", [script, "--build-pids"], { input: ps, encoding: "utf8" }).stdout.split("\n").filter(Boolean);

describe("wt-prep: only a real lake build counts as a build", () => {
  it("lake serve (the LSP), lake env, lean workers and look-alikes do not count", () => {
    expect(pids([
      " 5836 /opt/elan/toolchains/t/bin/lake serve -- -Dserver.reportDelayMs=0",
      " 6000 lake env lean Fw/X.lean",
      " 6001 /x/bin/lean --server build",
      " 6002 .lake/build/bin/mathview --lint --out o",
      " 6003 vim lake build",
      " 6004 lake",
      " 6005 /x/bin/lake exe fwcore",
    ].join("\n"))).toEqual([]);
  });
  it("lake build counts, by absolute path, bare name, with a target, and after -d/--dir", () => {
    expect(pids([
      " 100 /opt/elan/bin/lake build",
      " 101 lake build fwtest",
      " 102 lake -d lean build",
      " 103 lake --dir lean build Fw",
      " 104 lake serve",
    ].join("\n"))).toEqual(["100", "101", "102", "103"]);
  });
});
