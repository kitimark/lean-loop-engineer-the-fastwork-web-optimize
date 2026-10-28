// Task ci-push-render-guard: the pre-push hook (scripts/hooks/pre-push -> src/ci-push.ts) refuses a push of any ref but main whose
// origin/main..HEAD adds media outside snapshot/ (Lean console.landRenderGuard), also after a later removal; main pushes pass.
import "./land-timeout.ts";
import { execFileSync, spawnSync } from "node:child_process";
import { join, resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { makeRepo } from "../../console-api/test/reconcile-fixture.ts";

const HOOKS = resolve(import.meta.dirname, "../../../scripts/hooks");

function setup() {
  const fx = makeRepo();
  const bare = join(fx.root, "..", "origin.git");
  execFileSync("git", ["init", "-q", "--bare", bare]);
  fx.git(fx.root, "remote", "add", "origin", bare);
  const push = (ref: string) => spawnSync("git", ["-c", `core.hooksPath=${HOOKS}`, "push", "origin", ref], { cwd: fx.root, encoding: "utf8" });
  expect(push("main").status).toBe(0);
  fx.git(fx.root, "checkout", "-q", "-b", "ci/x");
  return { fx, push, remoteHas: (ref: string) => fx.git(fx.root, "ls-remote", bare, ref) !== "" };
}

describe("ci push render guard", () => {
  it("refuses a ci push whose range adds a render, also after a later removal", () => {
    const { fx, push, remoteHas } = setup();
    const add = fx.commit(fx.root, "results/x.png", "\x89PNG\r\n");
    let r = push("ci/x");
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("REFUSED: ci push render guard:");
    expect(r.stderr).toContain(`results/x.png (image) in ${add}`);
    expect(remoteHas("refs/heads/ci/x")).toBe(false);
    fx.git(fx.root, "rm", "-q", "--", "results/x.png");
    fx.git(fx.root, "commit", "-q", "-m", "remove the render");
    r = push("ci/x");
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("results/x.png (image)");
    expect(remoteHas("refs/heads/ci/x")).toBe(false);
  });

  it("refuses a tag and a non-ci branch whose range adds a render", () => {
    const { fx, push, remoteHas } = setup();
    fx.commit(fx.root, "results/t.png", "\x89PNG\r\n");
    fx.git(fx.root, "tag", "v1");
    const t = push("v1");
    expect(t.status).not.toBe(0);
    expect(t.stderr).toContain("results/t.png (image)");
    expect(remoteHas("refs/tags/v1")).toBe(false);
    fx.git(fx.root, "branch", "feature/y");
    const b = push("feature/y");
    expect(b.status).not.toBe(0);
    expect(b.stderr).toContain("REFUSED: ci push render guard:");
    expect(remoteHas("refs/heads/feature/y")).toBe(false);
  });

  it("pushes a clean ci branch and a snapshot/ render", () => {
    const { fx, push, remoteHas } = setup();
    fx.commit(fx.root, "src/a.ts");
    fx.commit(fx.root, "snapshot/hero.png", "\x89PNG\r\n");
    fx.commit(fx.root, "packages/measure-wktr/a.mjs", "x\n");
    fx.git(fx.root, "commit", "-q", "--amend", "-m", "measure [ci:wktr]");
    const r = push("ci/x");
    expect(r.status, r.stderr).toBe(0);
    expect(remoteHas("refs/heads/ci/x")).toBe(true);
  });

  it("does not block a main push that carries a render (the lead's scan covers main)", () => {
    const { fx, push, remoteHas } = setup();
    fx.git(fx.root, "checkout", "-q", "main");
    fx.commit(fx.root, "results/m.png", "\x89PNG\r\n");
    const r = push("main");
    expect(r.status, r.stderr).toBe(0);
    expect(remoteHas("refs/heads/main")).toBe(true);
  });
});
