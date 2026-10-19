import { afterAll, describe, expect, it, vi } from "vitest";
import { execFileSync, spawn } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync, mkdirSync, renameSync, appendFileSync } from "node:fs";
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
    // FW_CONSOLE_KEYCHAIN=off: login is disabled, so start prints the keychain hint, not the sign-in line
    expect(outs.join("\n")).toContain("owner login is DISABLED");
    expect(outs.join("\n")).toContain("security add-generic-password");
    expect(outs.join("\n")).not.toContain("sign in with the owner passphrase");
    expect(alive(pid)).toBe(true);
    expect((await fetch(`http://127.0.0.1:${port}/api/health`)).headers.get("x-fw-console-pid")).toBe(String(pid));

    outs.length = 0;
    expect(await consoleCli(["status"], deps())).toBe(0);
    const st = outs.join("\n");
    expect(st).toContain(`pid ${pid}`); expect(st).toContain(`:${port}`); expect(st).toContain("LAN off"); expect(st).toContain("console.log"); expect(st).toMatch(/\(\d+\.\d MiB\)/);

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

  it("start refuses when api.json names a live pid that did not answer", async () => {
    const port = await free();
    const quiet = spawn("sleep", ["60"], { stdio: "ignore", detached: true });
    try {
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, "api.json"), JSON.stringify({ port, pid: quiet.pid }));
      errs.length = 0;
      expect(await consoleCli(["start", "--port", String(port)], deps())).toBe(1);
      expect(errs.join("\n")).toMatch(/alive but did not answer/);
      outs.length = 0;
      expect(await consoleCli(["status"], deps())).toBe(1);
      expect(outs.join("\n")).toContain("UNRESPONSIVE");
      expect(alive(quiet.pid!)).toBe(true); // nothing was signalled
    } finally { process.kill(quiet.pid!, "SIGKILL"); rmSync(join(dir, "api.json"), { force: true }); }
  });

  it("stop checks the preview process group: a left-over group is reported, a reused pid is not", async () => {
    const port = await free();
    expect(await consoleCli(["start", "--port", String(port)], deps())).toBe(0);
    // a fake preview: a shell leader in its own group with a child, as a build or server grandchild would be
    const leader = spawn("sh", ["-c", "sleep 60 & wait"], { stdio: "ignore", detached: true });
    const lp = leader.pid!;
    try {
      const pstart = execFileSync("ps", ["-o", "lstart=", "-p", String(lp)]).toString().trim();
      writeFileSync(join(dir, "preview", "table.json"), JSON.stringify([
        { id: "fake1", pid: lp, pstart },
        { id: "reused", pid: lp, pstart: "Thu Jan  1 00:00:00 1970" },
      ]));
      outs.length = 0; errs.length = 0;
      expect(await consoleCli(["stop"], deps())).toBe(1);
      expect(errs.join("\n")).toContain(`fake1(${lp})`);
      expect(errs.join("\n")).not.toContain("reused(");
      // kill the group and the leader (the pid the test started); the group is then gone and stop finds none
      process.kill(-lp, "SIGKILL");
      for (let i = 0; i < 50 && alive(lp); i++) await new Promise((r) => setTimeout(r, 100));
    } finally { try { process.kill(-lp, "SIGKILL"); } catch { /* gone */ } }
    expect(alive(lp)).toBe(false);
  }, 120_000);

  it("logs -f reopens the log after a restart rotated it", async () => {
    mkdirSync(dir, { recursive: true });
    const log = join(dir, "console.log");
    writeFileSync(log, "old line\n");
    const seen: string[] = [];
    const w = vi.spyOn(process.stdout, "write").mockImplementation(((c: string | Uint8Array) => { seen.push(String(c)); return true; }) as typeof process.stdout.write);
    try {
      const done = consoleCli(["logs", "-n", "1", "-f"], deps());
      await new Promise((r) => setTimeout(r, 700));
      renameSync(log, `${log}.1`);
      writeFileSync(log, "after rotation\n");
      await new Promise((r) => setTimeout(r, 1000));
      appendFileSync(log, "more\n");
      await new Promise((r) => setTimeout(r, 800));
      process.emit("SIGINT");
      expect(await done).toBe(0);
    } finally { w.mockRestore(); }
    expect(seen.join("")).toContain("after rotation");
    expect(seen.join("")).toContain("more");
  });
});
