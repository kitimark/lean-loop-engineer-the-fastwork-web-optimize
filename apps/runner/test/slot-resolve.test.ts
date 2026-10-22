import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import { SLOT_MAIN_REL, mainCheckout, resolveSlotMain } from "../src/slot-resolve.ts";

const dirs: string[] = [];
afterEach(() => { for (const d of dirs.splice(0)) rmSync(d, { recursive: true, force: true }); });
const run = (cwd: string, ...a: string[]) => execFileSync("git", ["-c", "user.name=t", "-c", "user.email=t@t", ...a], { cwd, stdio: "ignore" });

describe("resolveSlotMain", () => {
  it("prefers the main checkout's file", () => {
    expect(resolveSlotMain("/wt/slot-main.ts", "/main", () => true)).toBe(join("/main", SLOT_MAIN_REL));
  });
  it("falls back to the local file when main's is missing or there is no main", () => {
    expect(resolveSlotMain("/wt/slot-main.ts", "/main", () => false)).toBe("/wt/slot-main.ts");
    expect(resolveSlotMain("/wt/slot-main.ts", null, () => true)).toBe("/wt/slot-main.ts");
  });
  it("a worktree on an older branch resolves to the main checkout's file", () => {
    const root = realpathSync(mkdtempSync(join(tmpdir(), "slotres-")));
    dirs.push(root);
    const main = join(root, "main");
    mkdirSync(join(main, "apps/runner/src"), { recursive: true });
    writeFileSync(join(main, SLOT_MAIN_REL), "// new\n");
    run(main, "init", "-q", "-b", "main");
    run(main, "add", ".");
    run(main, "commit", "-qm", "a");
    const wt = join(root, "wt");
    run(main, "worktree", "add", "-q", "-b", "old", wt);
    writeFileSync(join(wt, SLOT_MAIN_REL), "// old\n");
    expect(mainCheckout(wt)).toBe(main);
    expect(resolveSlotMain(join(wt, SLOT_MAIN_REL), mainCheckout(wt))).toBe(join(main, SLOT_MAIN_REL));
    expect(mainCheckout(root)).toBeNull();
  });
});
