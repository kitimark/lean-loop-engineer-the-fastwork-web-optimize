import { useEffect, useState } from "react";
import { apiFetch } from "@/lib/auth";
import type { LiveBoard, Plan, PlanTask } from "@fw/contracts";
import { Smartphone } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { TaskDetail, wantsDetail } from "./TaskDetail";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";

/** Plan tab. Every number and column is the board's `plan` (derived by fwcore); this file only lays it out. */
export function PlanView({ board }: { board: LiveBoard }) {
  const p = board.plan;
  if (p.tasks.length === 0) {
    return <p className="text-sm text-muted-foreground">No plan yet. Run <code>pnpm fw plan sync docs/team/work-graph.json</code>.</p>;
  }
  return (
    <div className="space-y-6">
      <DeviceLane plan={p} />
      <Milestones plan={p} />
      <Columns plan={p} />
      <Dag plan={p} />
    </div>
  );
}

function Milestones({ plan }: { plan: Plan }) {
  return (
    <Card>
      <CardHeader><CardTitle>Milestones</CardTitle></CardHeader>
      <CardContent className="space-y-2">
        {plan.milestones.map((m) => (
          <div key={m.id} className="flex items-center gap-3 text-sm">
            <span className="w-8 font-medium">{m.id}</span>
            <div className="h-2 w-48 shrink-0 overflow-hidden rounded bg-muted" role="progressbar" aria-valuemin={0} aria-valuemax={m.total} aria-valuenow={m.done} aria-label={`${m.id} progress`}>
              <div className="h-full bg-primary" style={{ width: `${m.total === 0 ? 0 : (100 * m.done) / m.total}%` }} />
            </div>
            <span className="w-12 tabular-nums">{m.done}/{m.total}</span>
            <span className="min-w-0 truncate text-muted-foreground">{m.title}</span>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}

const Task = ({ t, extra }: { t: PlanTask; extra?: React.ReactNode }) => (
  <li className={`rounded border p-2 text-sm${t.state === "cut" ? " opacity-50" : ""}`} title={t.title} data-state={t.state}>
    <div className="font-medium">{t.id}</div>
    <div className="truncate text-xs text-muted-foreground">{t.title}</div>
    <div className="mt-1 flex flex-wrap gap-1 text-xs">
      <Badge variant="secondary">{t.owner}</Badge>
      {t.milestone && <Badge variant="outline">{t.milestone}</Badge>}
      {t.lane === "device" && <DeviceBadge />}
      {extra}
    </div>
    {wantsDetail(t.id) && <TaskDetail id={t.id} />}
  </li>
);

export const DeviceBadge = () => (
  <Badge variant="outline" data-testid="device-badge"><Smartphone className="size-3" aria-hidden />needs you + iPhone</Badge>
);

/** Device lane: tasks the API marks `lane: "device"`. Lane and ready state come from fwcore; absent lane shows nothing. */
export function DeviceLane({ plan }: { plan: Plan }) {
  const dev = plan.tasks.filter((t) => t.lane === "device");
  if (dev.length === 0) return null;
  const ready = dev.filter((t) => t.state === "ready");
  const open = dev.filter((t) => t.state === "blocked" || t.state === "running");
  const done = dev.filter((t) => t.state === "done");
  return (
    <Card data-testid="device-lane">
      <CardHeader><CardTitle>Device lane ({dev.length}): needs you and the iPhone</CardTitle></CardHeader>
      <CardContent className="space-y-3">
        <section>
          <h3 className="mb-1 text-xs font-medium">Ready: bring the phone ({ready.length})</h3>
          <ul className="space-y-2">{ready.map((t) => <Task key={t.id} t={t} />)}</ul>
          {ready.length === 0 && <p className="text-sm text-muted-foreground">No device task is ready.</p>}
        </section>
        {open.length > 0 && (
          <section>
            <h3 className="mb-1 text-xs font-medium">Not ready ({open.length})</h3>
            <ul className="space-y-2">
              {open.map((t) => <Task key={t.id} t={t} extra={t.blockers.length > 0 && <span className="text-muted-foreground">waits on {t.blockers.join(", ")}</span>} />)}
            </ul>
          </section>
        )}
        {done.length > 0 && (
          <details>
            <summary className="cursor-pointer text-xs font-medium">Done ({done.length})</summary>
            <ul className="mt-2 space-y-2">{done.map((t) => <Task key={t.id} t={t} extra={t.evidence && <Evidence sha={t.evidence} />} />)}</ul>
          </details>
        )}
      </CardContent>
    </Card>
  );
}

/** The four columns; cut tasks (fwcore state "cut") are listed greyed under Done, nowhere else. */
export function Columns({ plan }: { plan: Plan }) {
  const by = new Map(plan.tasks.map((t) => [t.id, t]));
  const of = (s: string) => plan.tasks.filter((t) => t.state === s);
  const running = of("running"), blocked = of("blocked"), done = of("done"), cut = of("cut");
  return (
    <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
      <Card>
        <CardHeader><CardTitle>Ready ({of("ready").length})</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          {plan.parallelSafe.map((g, i) => (
            <div key={g.join(",")}>
              <div className="mb-1 text-xs text-muted-foreground">Group {i + 1}: these {g.length} can run in parallel</div>
              <ul className="space-y-2">{g.map((id) => by.get(id)).filter((t): t is PlanTask => !!t).map((t) => <Task key={t.id} t={t} />)}</ul>
            </div>
          ))}
          {plan.parallelSafe.length === 0 && <p className="text-sm text-muted-foreground">Nothing ready.</p>}
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>Running ({running.length})</CardTitle></CardHeader>
        <CardContent><ul className="space-y-2">{running.map((t) => <Task key={t.id} t={t} extra={<Badge>agent {t.agent}</Badge>} />)}</ul>
          {running.length === 0 && <p className="text-sm text-muted-foreground">No agent is on a task.</p>}</CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>Blocked ({blocked.length})</CardTitle></CardHeader>
        <CardContent><ul className="space-y-2">
          {blocked.map((t) => <Task key={t.id} t={t} extra={<span className="text-muted-foreground">waits on {t.blockers.join(", ")}</span>} />)}</ul></CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>Done ({done.length})</CardTitle></CardHeader>
        <CardContent><ul className="space-y-2">
          {done.map((t) => <Task key={t.id} t={t} extra={t.evidence && <Evidence sha={t.evidence} />} />)}</ul>
          {cut.length > 0 && <>
            <div className="mb-1 mt-3 text-xs text-muted-foreground">Cut from the plan ({cut.length})</div>
            <ul className="space-y-2">{cut.map((t) => <Task key={t.id} t={t} />)}</ul>
          </>}</CardContent>
      </Card>
    </div>
  );
}

let repoCommit: Promise<string | null> | undefined;
/** GET /api/repo once: the commit URL prefix from origin, or null (no origin / fetch failed). */
const fetchRepoCommit = () =>
  (repoCommit ??= fetch("/api/repo")
    .then((r) => (r.ok ? r.json() : null))
    .then((j) => (typeof j?.commit === "string" ? j.commit : null))
    .catch(() => null));

/** Evidence is the short commit id; a link to the public commit when /api/repo knows the origin, else plain text. */
function Evidence({ sha }: { sha: string }) {
  const [base, setBase] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void fetchRepoCommit().then((c) => live && setBase(c));
    return () => { live = false; };
  }, []);
  const short = sha.slice(0, 9);
  return base
    ? <a href={`${base}${sha}`} target="_blank" rel="noreferrer" className="underline"><code>{short}</code></a>
    : <code title={`git show ${sha}`}>{short}</code>;
}

// ---- layered DAG (inline SVG) ----------------------------------------------------------

export type Layout = { nodes: { id: string; layer: number; row: number }[]; layers: number; rows: number };

/** Longest-path layering of the undone tasks: layer = 1 + the deepest undone dep (done deps do not count). Cut tasks
 *  are left out. */
export function layout(tasks: PlanTask[]): Layout {
  const undone = tasks.filter((t) => t.state !== "done" && t.state !== "cut");
  const ids = new Set(undone.map((t) => t.id));
  const by = new Map(undone.map((t) => [t.id, t]));
  const memo = new Map<string, number>();
  const layerOf = (id: string): number => {
    const hit = memo.get(id);
    if (hit !== undefined) return hit;
    memo.set(id, 0); // the reducer refuses cycles; this only guards a malformed board
    const l = Math.max(-1, ...by.get(id)!.deps.filter((d) => ids.has(d)).map(layerOf)) + 1;
    memo.set(id, l);
    return l;
  };
  const used = new Map<number, number>();
  const nodes = undone.map((t) => {
    const layer = layerOf(t.id), row = used.get(layer) ?? 0;
    used.set(layer, row + 1);
    return { id: t.id, layer, row };
  });
  return { nodes, layers: Math.max(0, ...nodes.map((n) => n.layer + 1)), rows: Math.max(0, ...used.values()) };
}

const W = 150, H = 22, GX = 40, GY = 8;

function Dag({ plan }: { plan: Plan }) {
  const lay = layout(plan.tasks);
  const pos = new Map(lay.nodes.map((n) => [n.id, { x: n.layer * (W + GX), y: n.row * (H + GY) }]));
  const crit = new Set(plan.criticalPath);
  const critEdge = (a: string, b: string) => { const i = plan.criticalPath.indexOf(a); return i >= 0 && plan.criticalPath[i + 1] === b; };
  const state = new Map(plan.tasks.map((t) => [t.id, t.state]));
  const width = lay.layers * (W + GX) - GX, height = lay.rows * (H + GY) - GY;
  const fill = (s: string | undefined) => (s === "running" ? "var(--primary)" : s === "ready" ? "var(--secondary)" : "var(--background)");
  const edges = plan.tasks.flatMap((t) => (pos.has(t.id) ? t.deps.filter((d) => pos.has(d)).map((d) => ({ a: d, b: t.id })) : []));
  return (
    <Card>
      <CardHeader><CardTitle>Dependencies of the {lay.nodes.length} unfinished tasks</CardTitle></CardHeader>
      <CardContent>
        <p className="mb-2 text-xs text-muted-foreground">
          Left to right: a task sits right of everything it waits on. Red = the critical path ({plan.criticalPath.length} tasks, the longest chain left).
          Filled = running, grey = ready.
        </p>
        <div className="overflow-x-auto">
          <svg width={width + 2} height={height + 2} role="img" aria-label="dependency graph of unfinished tasks" className="text-xs">
            {edges.map(({ a, b }) => {
              const p = pos.get(a)!, q = pos.get(b)!, hot = critEdge(a, b);
              const x1 = p.x + W, y1 = p.y + H / 2, x2 = q.x, y2 = q.y + H / 2, mx = (x1 + x2) / 2;
              return <path key={`${a}>${b}`} d={`M${x1} ${y1} C${mx} ${y1} ${mx} ${y2} ${x2} ${y2}`} fill="none"
                stroke={hot ? "var(--destructive)" : "var(--border)"} strokeWidth={hot ? 2 : 1} />;
            })}
            {lay.nodes.map((n) => {
              const p = pos.get(n.id)!, hot = crit.has(n.id), s = state.get(n.id);
              return (
                <g key={n.id} transform={`translate(${p.x} ${p.y})`}>
                  <title>{n.id} ({s})</title>
                  <rect width={W} height={H} rx={4} fill={fill(s)} stroke={hot ? "var(--destructive)" : "var(--ring)"} strokeWidth={hot ? 2 : 1} />
                  <text x={6} y={15} fill={s === "running" ? "var(--primary-foreground)" : "var(--foreground)"}>{n.id.length > 22 ? `${n.id.slice(0, 21)}…` : n.id}</text>
                </g>
              );
            })}
          </svg>
        </div>
      </CardContent>
    </Card>
  );
}
