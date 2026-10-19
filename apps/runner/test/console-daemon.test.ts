import { afterAll, describe, expect, it } from "vitest";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { consoleCli, type ConsoleDeps } from "../src/console.ts";
import { fwcoreCall } from "../src/run.ts";

// A real detached console on a spare port with a temp .fw-console (FW_CONSOLE_KEYCHAIN=off: the keychain is never read).
const root = mkdtempSync(join(tmpdir(), "fw-daemon-"));
execFileSync("git", ["init", "-q", root]);
const dir = join(root, ".fw-console");
const free = (): Promise<number> => new Promise((res) => { const s = createServer(); s.listen(0, "127.0.0.1", () => { const p = (s.address() as { port: number }).port; s.close(() => res(p)); }); });
const outs: string[] = []; const errs: string[] = [];
const deps = (): ConsoleDeps => ({
  call: fwcoreCall(process.cwd()), cwd: root, now: Date.now,
  env: { ...process.env, FW_CONSOLE_DIR: dir, FW_CONSOLE_KEYCHAIN: "off", FW_CONSOLE_WEB_ORIGIN: "" },
  out: (l) => outs.push(l), err: (l) => errs.push(l),
});
const pidOf = (): number => (JSON.parse(readFileSync(join(dir, "api.json"), "utf8")) as { pid: number }).pid;
const alive = (pid: number) => { try { process.kill(pid, 0); return true; } catch { return false; } };

afterAll(async () => {
  try { await consoleCli(["stop"], deps()); } catch { /* already stopped */ }
  rmSync(root, { recursive: true, force: true });
});

describe("fw console (detached)", () => {
  it("start, status, refuse a second start, logs, stop; the log holds no owner link or token", async () => {
    const port = await free();
    expect(await consoleCli(["start", "--port", String(port)], deps())).toBe(0);
    const pid = pidOf();
    expect(outs.join("\n")).toContain(`pid ${pid}`);
    expect(alive(pid)).toBe(true);
    expect((await fetch(`http://127.0.0.1:${port}/api/health`)).headers.get("x-fw-console-pid")).toBe(String(pid));

    outs.length = 0;
    expect(await consoleCli(["status"], deps())).toBe(0);
    const st = outs.join("\n");
    expect(st).toContain(`pid ${pid}`); expect(st).toContain(`:${port}`); expect(st).toContain("LAN off"); expect(st).toContain("console.log");

    errs.length = 0;
    expect(await consoleCli(["start", "--port", String(port)], deps())).toBe(1);
    expect(errs.join("\n")).toMatch(/already running/);
    expect(pidOf()).toBe(pid);

    outs.length = 0;
    expect(await consoleCli(["logs", "-n", "20"], deps())).toBe(0);
    expect(outs.join("\n")).toContain("console-api listening");
    // no tty, no owner link, no token: the whole log is checked
    const text = readFileSync(join(dir, "console.log"), "utf8");
    expect(text).not.toMatch(/\/owner\?t=/);
    expect(text).not.toMatch(/owner link \(open once/);
    expect(text).not.toMatch(/[?&]t=[A-Za-z0-9_-]{12,}/);

    outs.length = 0; errs.length = 0;
    expect(await consoleCli(["stop"], deps())).toBe(0);
    expect([outs, errs, alive(pid)]).toEqual([[`console stopped (pid ${pid}); previews it owned: 0 stopped, none left`], [], false]);
    expect(existsSync(join(dir, "api.json"))).toBe(false);
    outs.length = 0;
    expect(await consoleCli(["status"], deps())).toBe(1);
    expect(outs.join("\n")).toContain("stopped");
  }, 120_000);

  it("stop signals nothing for a stale api.json whose port does not answer", async () => {
    const port = await free();
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "api.json"), JSON.stringify({ port, pid: process.pid }));
    outs.length = 0;
    expect(await consoleCli(["stop"], deps())).toBe(0);
    expect(outs.join("\n")).toContain("nothing was signalled");
    expect(alive(process.pid)).toBe(true);
    rmSync(join(dir, "api.json"));
  });

  it("restart starts a new pid and stops the old one", async () => {
    const port = await free();
    expect(await consoleCli(["restart", "--port", String(port)], deps())).toBe(0);
    const a = pidOf();
    expect(await consoleCli(["restart", "--port", String(port)], deps())).toBe(0);
    const b = pidOf();
    expect(b).not.toBe(a);
    expect(alive(a)).toBe(false);
    expect(await consoleCli(["stop"], deps())).toBe(0);
  }, 120_000);

  it("the log rotates at the limit and usage errors are refused", async () => {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "console.log"), "x".repeat(5242880));
    const port = await free();
    expect(await consoleCli(["start", "--port", String(port)], deps())).toBe(0);
    expect(existsSync(join(dir, "console.log.1"))).toBe(true);
    expect(await consoleCli(["stop"], deps())).toBe(0);
    await expect(consoleCli(["bogus"], deps())).rejects.toThrow(/usage/);
    await expect(consoleCli(["start", "--port", "x"], deps())).rejects.toThrow(/usage/);
  }, 120_000);
});
