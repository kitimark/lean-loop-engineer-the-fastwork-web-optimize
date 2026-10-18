// Health tab data: the latest line of .fw-console/health.jsonl ({at, input, output}, written by `fw watch`).
// The decisions (states, alerts, their order) are fwcore's `obs.health` output, passed through unchanged;
// this file only joins output rows to the input's names and facts. No thresholds here.
import { closeSync, fstatSync, openSync, readSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";

const Str = z.string();
const Num = z.number();
const Output = z.object({
  agents: z.array(z.object({ id: Str, state: Str, alerts: z.array(Str) })),
  system: z.object({ alerts: z.array(Str) }),
  counts: z.object({ active: Num, idle: Num, parked: Num, stalled: Num, gone: Num.default(0), done: Num }), // gone/critical: watch-slow; older lines lack them
  alerts: z.array(z.object({ code: Str, subject: Str, detail: Str, critical: z.boolean().default(false) })),
});
const Input = z.object({
  now: Num,
  agents: z.array(z.object({
    id: Str, name: Str.nullish(), task: Str.nullish(), kind: Str.optional(), lastAt: Num.optional(),
    errTail: Num.optional(), inflight: z.object({ tool: Str, since: Num }).nullish(), ctxTokens: Num.nullish(),
  }).passthrough()),
  system: z.object({
    diskFreeGB: Num, memPressure: Str.optional(),
    simLock: z.object({ holder: Str.nullish(), since: Num.nullish() }).optional(),
    docker: z.array(z.object({ name: Str, startedAt: Num }).passthrough()).optional(),
    worktrees: Num.optional(),
    ci: z.array(z.object({ workflow: Str, branch: Str, status: Str, conclusion: Str.nullish(), startedAt: Num }).passthrough()).optional(),
    stale: z.array(Str).optional(),
  }).passthrough(),
});
const Line = z.object({ at: Num, input: Input, output: Output });

export type HealthView = ReturnType<typeof project>;

function project(line: z.infer<typeof Line>) {
  const { input, output } = line;
  const byId = new Map(input.agents.map((a) => [a.id, a]));
  return {
    at: line.at,
    now: input.now,
    counts: output.counts,
    agents: output.agents.map((r) => {
      const a = byId.get(r.id);
      return {
        id: r.id, label: a?.name ?? a?.task ?? r.id, kind: a?.kind ?? "subagent", state: r.state, alerts: r.alerts,
        lastAt: a?.lastAt ?? null, errTail: a?.errTail ?? 0, ctxTokens: a?.ctxTokens ?? null,
        inflight: a?.inflight ?? null,
      };
    }),
    alerts: output.alerts, // already sorted and deduplicated by Lean
    systemAlerts: output.system.alerts,
    system: {
      diskFreeGB: input.system.diskFreeGB,
      memPressure: input.system.memPressure ?? "normal",
      simLock: { holder: input.system.simLock?.holder ?? null, since: input.system.simLock?.since ?? null },
      docker: (input.system.docker ?? []).map((c) => ({ name: c.name, startedAt: c.startedAt })),
      worktrees: input.system.worktrees ?? 0,
      ci: (input.system.ci ?? []).map((r) => ({ workflow: r.workflow, branch: r.branch, status: r.status, conclusion: r.conclusion ?? null })),
      stale: input.system.stale ?? [],
    },
  };
}

/** Read the last complete line of health.jsonl (tail only; the file grows without bound). */
export function readLatestHealth(dir: string): HealthView | null {
  const l = readLatestLine(dir);
  return l ? project(l) : null;
}

/** The newest complete health line that satisfies `keep` (default: any), reading at most `cap` bytes from the end. */
function readLatestLine(dir: string, keep: (l: z.infer<typeof Line>) => boolean = () => true,
  cap = Number.POSITIVE_INFINITY): z.infer<typeof Line> | null {
  let fd: number;
  try { fd = openSync(join(dir, "health.jsonl"), "r"); } catch { return null; }
  try {
    const size = fstatSync(fd).size;
    for (let span = 1 << 18; ; span *= 4) {
      const len = Math.min(size, span, cap);
      const buf = Buffer.alloc(len);
      readSync(fd, buf, 0, len, size - len);
      const lines = buf.toString("utf8").split("\n").filter((l) => l.trim());
      // the first chunk line may be cut when we did not read from byte 0
      const usable = len < size ? lines.slice(1) : lines;
      for (let i = usable.length - 1; i >= 0; i--) {
        try {
          const p = Line.safeParse(JSON.parse(usable[i]!));
          if (p.success && keep(p.data)) return p.data;
        } catch { /* skip a torn line */ }
      }
      if (len >= size || len >= cap) return null;
    }
  } finally { closeSync(fd); }
}

/** Agent id -> the name `fw watch` last recorded for it (input.agents[].name of health.jsonl): only a label (sent as
 *  `agent.label`, Lean `Fw.Ops.Obs.labelOf`) that binds the id's life to the task of that name; liveness itself is by id
 *  (task-state-truth round 3). Task task-state-truth: the old
 *  lookup re-read up to 64 MB of health.jsonl backwards for every stop; this index reads the file once and then only
 *  the bytes appended since (a shorter file, i.e. a rotation, starts over). Empty names are skipped; Lean
 *  `Fw.Ops.Obs.lifeOf` decides whether a name is usable. Reads only. */
export class NameIndex {
  private names = new Map<string, string>();
  private offset = 0;
  private readonly path: string;
  constructor(dir: string) { this.path = join(dir, "health.jsonl"); }

  /** Read the complete lines appended since the last call, in 4 MB chunks (a torn last line waits). */
  refresh(): void {
    let fd: number;
    try { fd = openSync(this.path, "r"); } catch { return; }
    try {
      const size = fstatSync(fd).size;
      if (size < this.offset) { this.offset = 0; this.names.clear(); }
      let carry = Buffer.alloc(0);
      while (this.offset + carry.length < size) {
        const len = Math.min(4 << 20, size - this.offset - carry.length);
        const buf = Buffer.alloc(len);
        readSync(fd, buf, 0, len, this.offset + carry.length);
        const all = carry.length ? Buffer.concat([carry, buf]) : buf;
        const end = all.lastIndexOf(10) + 1;
        if (end > 0) this.scan(all.subarray(0, end).toString("utf8"));
        this.offset += end;
        carry = all.subarray(end);
      }
    } finally { closeSync(fd); }
  }

  private scan(text: string): void {
    for (const l of text.split("\n")) {
      if (!l.includes('"agents"')) continue;
      try {
        const agents = (JSON.parse(l) as { input?: { agents?: { id?: unknown; name?: unknown }[] } }).input?.agents ?? [];
        for (const a of agents) if (typeof a.id === "string" && typeof a.name === "string" && a.name) this.names.set(a.id, a.name);
      } catch { /* torn or foreign line: skip */ }
    }
  }

  /** The newest indexed name of agent id `id`, or null (call `refresh` first). */
  get(id: string): string | null { return this.names.get(id) ?? null; }
  /** Every (agent id, newest name) pair indexed so far (call `refresh` first). */
  entries(): [string, string][] { return [...this.names]; }
  get size(): number { return this.names.size; }
}
