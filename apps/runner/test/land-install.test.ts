// Task land-install-fallback (Lean Fw.Console.LandVerdict.installKind): the land worktree's offline install falls back to the
// online install; both failing refuses the land with VERDICT install (exit 19). The decision is checked against the Lean golden
// in land-verdict.test.ts; here the glue runs with a stubbed exec.
import "./land-timeout.ts";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";
import { checkoutLandWt, landInstall, type InstallExec } from "../src/land.ts";
import { exitCode, verdictLine } from "../src/land-verdict.ts";

const OFFLINE = "pnpm install --offline --frozen-lockfile";
const ONLINE = "pnpm install --frozen-lockfile";
const stub = (ok: (cmd: string) => boolean) => {
  const calls: string[] = [];
  const exec: InstallExec = (argv) => { const c = argv.join(" "); calls.push(c); return ok(c); };
  return { calls, exec };
};

describe("land install fallback", () => {
  it("offline ok: continues, no online install", () => {
    const s = stub(() => true);
    expect(landInstall("/d", s.exec)).toBeNull();
    expect(s.calls).toEqual([OFFLINE]);
  });
  it("offline fails, online ok: continues after the online install", () => {
    const s = stub((c) => c === ONLINE);
    expect(landInstall("/d", s.exec)).toBeNull();
    expect(s.calls).toEqual([OFFLINE, ONLINE]);
  });
  it("both fail: refuses with a named reason after exactly one online try", () => {
    const s = stub(() => false);
    const why = landInstall("/d", s.exec);
    expect(why).toContain("install failed in /d");
    expect(s.calls).toEqual([OFFLINE, ONLINE]);
    expect(verdictLine("install", "t1")).toBe("VERDICT install t1");
    expect(exitCode("install")).toBe(19);
  });
  it("checkoutLandWt hands the prep refusal back to the land", () => {
    const fx = makeRepo();
    const dir = join(fx.root, "..", "land-wt-x");
    const head = fx.git(fx.root, "rev-parse", "HEAD").trim();
    expect(checkoutLandWt(fx.root, dir, head, () => "install failed in x")).toBe("install failed in x");
    expect(existsSync(dir)).toBe(true);
    expect(checkoutLandWt(fx.root, dir, head, () => null)).toBeNull();
  });
});
