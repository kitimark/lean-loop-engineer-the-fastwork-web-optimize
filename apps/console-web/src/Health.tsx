import { useEffect, useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { age } from "@/lib/api";

// Rendering only. States, alerts and their order are fwcore `obs.health` output (via `fw watch` -> health.jsonl);
// nothing here compares a value with a threshold.
export type HealthView = {
  at: number; now: number;
  counts: Record<"active" | "idle" | "parked" | "stalled" | "gone" | "done", number>;
  agents: { id: string; label: string; kind: string; state: string; alerts: string[]; lastAt: number | null; errTail: number;
    ctxTokens: number | null; inflight: { tool: string; since: number } | null }[];
  alerts: { code: string; subject: string; detail: string; critical: boolean }[];
  systemAlerts: string[];
  system: { diskFreeGB: number; memPressure: string; simLock: { holder: string | null; since: number | null };
    docker: { name: string; startedAt: number }[]; worktrees: number;
    ci: { workflow: string; branch: string; status: string; conclusion: string | null }[]; stale: string[] };
  gh: GhView | null;
};
export type GhView = {
  actions: string; pages: string; webhooks: string; degraded: boolean; alert: string | null;
  incidents: { name: string; status: string; impact: string; createdAt: number; updatedAt: number; body: string; actions: boolean }[];
};
export const GH_STATUS_URL = "https://www.githubstatus.com";

// Rendering only: the CircleCI verdicts and `usable` are Lean Fw.Obs.CiStatus (console-api `GET /api/ci-status`).
export type CiView = {
  readAt: number | null; now: number; fresh: boolean; error: string | null; url: string;
  states: Record<"docker" | "machine" | "pipelines" | "api" | "macos", string>;
  arm: { verdict: string; usable: boolean }; macos: { verdict: string; usable: boolean };
  incidents: { name: string; status: string; impact: string; createdAt: number; updatedAt: number; components: string[] }[];
};

const STATES = ["stalled", "active", "idle", "parked", "gone", "done"] as const; // display grouping only

function useHealth(): { health: HealthView | null | undefined; error: boolean } {
  const [health, setHealth] = useState<HealthView | null | undefined>(undefined);
  const [error, setError] = useState(false);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const r = await apiFetch("/api/health");
        const j = (await r.json()) as HealthView | null;
        if (alive) { setHealth(j); setError(false); }
      } catch { if (alive) setError(true); }
    };
    void load();
    const id = setInterval(load, 10000);
    return () => { alive = false; clearInterval(id); };
  }, []);
  return { health, error };
}

const stateVariant = (s: string) => (s === "stalled" ? "destructive" : s === "active" ? "default" : "secondary") as
  "destructive" | "default" | "secondary";

const compVariant = (s: string) => (s === "operational" ? "secondary" : s === "unknown" ? "outline" : "destructive") as
  "secondary" | "outline" | "destructive";

// Rendering only: whether Actions is flagged is `gh.degraded` (fwcore, alert sys.ghDegraded).
export function GhCard({ gh, now }: { gh: GhView; now: number }) {
  return (
    <Card data-testid="gh-status">
      <CardHeader>
        <CardTitle className="flex flex-wrap items-center gap-2">
          GitHub {gh.degraded && <Badge variant="destructive">sys.ghDegraded</Badge>}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <Table>
          <TableBody>
            {([["Actions", gh.actions], ["Pages", gh.pages], ["Webhooks", gh.webhooks]] as const).map(([name, st]) => (
              <TableRow key={name}>
                <TableCell className="font-medium">{name}</TableCell>
                <TableCell><Badge variant={compVariant(st)}>{st}</Badge></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        {gh.alert && <p className="text-sm text-muted-foreground">{gh.alert}</p>}
        {gh.incidents.length === 0 && <p className="text-sm text-muted-foreground">No open incident on these components.</p>}
        {gh.incidents.map((i) => (
          <div key={`${i.name}-${i.createdAt}`} className="space-y-1 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="destructive">{i.impact || "incident"}</Badge><span className="font-medium">{i.name}</span>
              <span className="text-muted-foreground">{i.status}, opened {age(now - i.createdAt)} ago, last update {age(now - i.updatedAt)} ago</span>
            </div>
            {i.body && <p className="text-muted-foreground">{i.body}</p>}
          </div>
        ))}
        <a className="text-sm underline" href={GH_STATUS_URL} target="_blank" rel="noreferrer">githubstatus.com</a>
      </CardContent>
    </Card>
  );
}

const verdictVariant = (v: string) => (v === "healthy" ? "secondary" : v === "unknown" ? "outline" : "destructive") as
  "secondary" | "outline" | "destructive";

export function CiCard({ ci }: { ci: CiView }) {
  const lanes = [["Linux Arm", ci.arm], ["macOS", ci.macos]] as const;
  const comps = [["Docker Jobs", ci.states.docker], ["Machine Jobs", ci.states.machine], ["Pipelines & Workflows", ci.states.pipelines],
    ["CircleCI API", ci.states.api], ["macOS Jobs", ci.states.macos]] as const;
  return (
    <Card data-testid="circleci-status">
      <CardHeader>
        <CardTitle className="flex flex-wrap items-center gap-2">
          CircleCI {lanes.map(([n, l]) => <Badge key={n} variant={verdictVariant(l.verdict)}>{n} {l.verdict}{l.usable ? ", usable" : ""}</Badge>)}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-3">
        <Table>
          <TableBody>
            {comps.map(([name, st]) => (
              <TableRow key={name}>
                <TableCell className="font-medium">{name}</TableCell>
                <TableCell><Badge variant={compVariant(st)}>{st}</Badge></TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
        <p className="text-sm text-muted-foreground">
          {ci.readAt === null ? "Not read yet." : `Read ${age(ci.now - ci.readAt)} ago${ci.fresh ? "" : " (stale)"}.`}
          {ci.error && ` Last read failed: ${ci.error}.`}
        </p>
        {ci.incidents.length === 0 && <p className="text-sm text-muted-foreground">No open incident on these components.</p>}
        {ci.incidents.map((i) => (
          <div key={`${i.name}-${i.createdAt}`} className="flex flex-wrap items-center gap-2 text-sm">
            <Badge variant="destructive">{i.impact || "incident"}</Badge><span className="font-medium">{i.name}</span>
            <span className="text-muted-foreground">{i.status}, {i.components.join(", ")}, opened {age(ci.now - i.createdAt)} ago</span>
          </div>
        ))}
        <a className="text-sm underline" href={ci.url} target="_blank" rel="noreferrer">status.circleci.com</a>
      </CardContent>
    </Card>
  );
}

function useCiStatus(): CiView | null {
  const [ci, setCi] = useState<CiView | null>(null);
  useEffect(() => {
    let alive = true;
    const load = async () => {
      try {
        const r = await apiFetch("/api/ci-status");
        const j = (await r.json()) as CiView;
        if (alive) setCi(j);
      } catch { /* the card stays as it was */ }
    };
    void load();
    const id = setInterval(load, 60000);
    return () => { alive = false; clearInterval(id); };
  }, []);
  return ci;
}

export function HealthView({ now }: { now: number }) {
  const { health, error } = useHealth();
  const ci = useCiStatus();
  if (health === undefined) return <p className="text-muted-foreground">{error ? "Cannot reach console-api." : "Loading..."}</p>;
  if (health === null) return <p className="text-muted-foreground">No health check yet. Run <code>pnpm fw watch</code>.</p>;
  const rows = [...health.agents].sort((a, b) => STATES.indexOf(a.state as typeof STATES[number]) - STATES.indexOf(b.state as typeof STATES[number]));
  const has = (code: string) => health.systemAlerts.includes(code);
  const stale = (k: string) => health.system.stale.includes(k);
  const s = health.system;
  const sysRows: { name: string; value: string; codes: string[]; stale: boolean }[] = [
    { name: "Disk", value: `${s.diskFreeGB} GB free`, codes: ["sys.diskLow"], stale: false },
    { name: "Memory", value: s.memPressure, codes: ["sys.memCritical"], stale: false },
    { name: "Sim lock", value: s.simLock.holder ? `held by ${s.simLock.holder}${s.simLock.since ? `, ${age(health.now - s.simLock.since)}` : ""}` : "free",
      codes: ["sim.lockLong", "sim.lockOrphan"], stale: false },
    { name: "CI", value: s.ci.length === 0 ? "no runs" : s.ci.slice(0, 5).map((r) => `${r.workflow}@${r.branch} ${r.conclusion ?? r.status}`).join("; "),
      codes: ["ci.failed"], stale: stale("ci") },
    { name: "Docker", value: s.docker.length === 0 ? "no containers" : s.docker.map((c) => c.name).join(", "), codes: ["docker.orphan"], stale: stale("docker") },
    { name: "Worktrees", value: String(s.worktrees), codes: ["worktrees.many"], stale: false },
  ];
  return (
    <div className="space-y-6">
      <p className="text-xs text-muted-foreground">
        Checked {age(now - health.at)} ago. Decided by fwcore (obs.health); this view only renders it.
      </p>
      <Card>
        <CardHeader><CardTitle>Alerts ({health.alerts.length})</CardTitle></CardHeader>
        <CardContent className="space-y-1">
          {health.alerts.length === 0 && <p className="text-sm text-muted-foreground">No alerts.</p>}
          {health.alerts.map((a, i) => (
            <div key={i} className="flex flex-wrap items-center gap-2 text-sm">
              {a.critical && <Badge variant="outline">critical path</Badge>}<Badge variant="destructive">{a.code}</Badge><span className="font-medium">{a.subject}</span>
              <span className="text-muted-foreground">{a.detail}</span>
            </div>
          ))}
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>Timings ({health.alerts.filter((a) => a.code === "timing.slow").length} slow)</CardTitle></CardHeader>
        <CardContent className="space-y-1">
          {health.alerts.filter((a) => a.code === "timing.slow").length === 0 && (
            <p className="text-sm text-muted-foreground">No slow step (verdicts: Fw.Obs.Timing via fw watch).</p>
          )}
          {health.alerts.filter((a) => a.code === "timing.slow").map((a) => (
            <div key={a.subject} className="flex flex-wrap items-center gap-2 text-sm">
              <Badge variant="destructive">slow</Badge><span className="font-medium">{a.subject}</span>
              <span className="text-muted-foreground">NEXT investigate step={a.subject}</span>
            </div>
          ))}
        </CardContent>
      </Card>
      <Card>
        <CardHeader><CardTitle>System</CardTitle></CardHeader>
        <CardContent>
          <Table>
            <TableBody>
              {sysRows.map((r) => {
                const hit = r.codes.filter(has);
                return (
                  <TableRow key={r.name}>
                    <TableCell className="font-medium">{r.name}</TableCell>
                    <TableCell>{r.value} {r.stale && <Badge variant="secondary">stale</Badge>}</TableCell>
                    <TableCell>{hit.length > 0 ? hit.map((c) => <Badge key={c} variant="destructive">{c}</Badge>) : <Badge variant="secondary">ok</Badge>}</TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
      {health.gh && <GhCard gh={health.gh} now={health.now} />}
      {ci && <CiCard ci={ci} />}
      <Card>
        <CardHeader>
          <CardTitle className="flex flex-wrap gap-2">
            Agents {STATES.map((k) => <Badge key={k} variant={stateVariant(k)}>{k} {health.counts[k]}</Badge>)}
          </CardTitle>
        </CardHeader>
        <CardContent>
          <Table>
            <TableHeader>
              <TableRow><TableHead>Agent</TableHead><TableHead>Kind</TableHead><TableHead>State</TableHead><TableHead>Last event</TableHead>
                <TableHead>In flight</TableHead><TableHead>Alerts</TableHead></TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((a) => (
                <TableRow key={a.id}>
                  <TableCell className="font-medium">{a.label}</TableCell>
                  <TableCell>{a.kind}</TableCell>
                  <TableCell><Badge variant={stateVariant(a.state)}>{a.state}</Badge></TableCell>
                  <TableCell>{a.lastAt ? `${age(health.now - a.lastAt)} ago` : "-"}</TableCell>
                  <TableCell>{a.inflight ? `${a.inflight.tool} ${age(health.now - a.inflight.since)}` : "-"}</TableCell>
                  <TableCell>{a.alerts.length ? a.alerts.map((c) => <Badge key={c} variant="destructive">{c}</Badge>) : "-"}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </div>
  );
}
