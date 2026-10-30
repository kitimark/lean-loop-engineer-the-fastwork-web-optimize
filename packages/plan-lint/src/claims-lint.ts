import { spawn, execFileSync, type ChildProcessWithoutNullStreams } from "node:child_process";
import { createInterface } from "node:readline";
import { existsSync, readFileSync } from "node:fs";
import { isAbsolute, join, normalize } from "node:path";

export type Finding = { line: number; code: string; detail: string };
export type Artifact = { path: string; json: unknown } | { path: string; lines: string[] };
export type NoteFindings = { path: string; findings: Finding[] };

export class ClaimsServer {
  private proc: ChildProcessWithoutNullStreams;
  private waiting: { ok: (v: unknown) => void; fail: (e: Error) => void }[] = [];
  private dead: Error | null = null;

  constructor(root: string) {
    this.proc = spawn("lake", ["env", "lean", "--run", "scripts/ClaimsGolden.lean", "--serve"], { cwd: join(root, "lean") });
    this.proc.stderr.pipe(process.stderr);
    createInterface({ input: this.proc.stdout }).on("line", (l) => {
      const w = this.waiting.shift();
      if (!w) return;
      try { w.ok(JSON.parse(l)); } catch (e) { w.fail(e as Error); }
    });
    this.proc.on("close", (code) => {
      this.dead = new Error(`claims server exited with ${code}`);
      for (const w of this.waiting.splice(0)) w.fail(this.dead);
    });
  }

  ask(req: object): Promise<unknown> {
    if (this.dead) return Promise.reject(this.dead);
    return new Promise((ok, fail) => {
      this.waiting.push({ ok, fail });
      this.proc.stdin.write(JSON.stringify(req) + "\n");
    });
  }

  close(): void { this.proc.stdin.end(); }
}

export function readArtifact(root: string, path: string): Artifact | null {
  const rel = normalize(path);
  if (isAbsolute(rel) || rel.startsWith("..")) return null;
  const abs = join(root, rel);
  if (!existsSync(abs)) return null;
  const text = readFileSync(abs, "utf8");
  if (rel.endsWith(".json")) {
    try { return { path, json: JSON.parse(text) }; } catch { return null; }
  }
  return { path, lines: text.split("\n") };
}

export const trackedFiles = (root: string): Set<string> =>
  new Set(execFileSync("git", ["ls-files", "-z"], { cwd: root, encoding: "utf8", maxBuffer: 1 << 28 }).split("\0").filter(Boolean));

export const NOTE_RE = /^research\/notes\/.*\.md$|^docs\/team\/handoffs\/[^/]+\.md$/;

export const defaultTargets = (tracked: Set<string>): string[] => [...tracked].filter((p) => NOTE_RE.test(p)).sort();

export async function lintNote(server: ClaimsServer, root: string, path: string, text: string, tracked: Set<string>): Promise<Finding[]> {
  const r = (await server.ask({ op: "claims.reads", text })) as { reads: string[]; paths: string[] };
  const files = r.reads.map((p) => readArtifact(root, p)).filter((a): a is Artifact => a !== null);
  const committed = r.paths.filter((p) => tracked.has(p));
  const res = (await server.ask({ op: "claims.lint", text, committed, files })) as { findings?: Finding[]; error?: string };
  if (!res.findings) throw new Error(`${path}: ${res.error ?? "no findings field"}`);
  return res.findings;
}

export async function lintPaths(root: string, paths: string[], tracked = trackedFiles(root)): Promise<NoteFindings[]> {
  if (!paths.length) return [];
  execFileSync("lake", ["build", "+Fw.Plan.Claims"], { cwd: join(root, "lean"), stdio: ["ignore", 2, 2] });
  const server = new ClaimsServer(root);
  try {
    const out: NoteFindings[] = [];
    for (const p of paths) out.push({ path: p, findings: await lintNote(server, root, p, readFileSync(join(root, p), "utf8"), tracked) });
    return out;
  } finally {
    server.close();
  }
}
