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
  counts: z.object({ active: Num, idle: Num, parked: Num, stalled: Num, done: Num }),
  alerts: z.array(z.object({ code: Str, subject: Str, detail: Str })),
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
  let fd: number;
  try { fd = openSync(join(dir, "health.jsonl"), "r"); } catch { return null; }
  try {
    const size = fstatSync(fd).size;
    for (let span = 1 << 18; ; span *= 4) {
      const len = Math.min(size, span);
      const buf = Buffer.alloc(len);
      readSync(fd, buf, 0, len, size - len);
      const lines = buf.toString("utf8").split("\n").filter((l) => l.trim());
      // the first chunk line may be cut when we did not read from byte 0
      const usable = len < size ? lines.slice(1) : lines;
      for (let i = usable.length - 1; i >= 0; i--) {
        try {
          const p = Line.safeParse(JSON.parse(usable[i]!));
          if (p.success) return project(p.data);
        } catch { /* skip a torn line */ }
      }
      if (len >= size) return null;
    }
  } finally { closeSync(fd); }
}
