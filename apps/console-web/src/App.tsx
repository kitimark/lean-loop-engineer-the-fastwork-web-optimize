import { useState } from "react";
import type { LiveBoard as Board, Step, StepKind } from "@fw/contracts";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { PlanView } from "./Plan";
import { HealthView } from "./Health";
import { BuildsView } from "./Builds";
import { age, sendAsUser, useBoard, useNow } from "@/lib/api";

/** The tab and note a login landing asks for (`/?tab=builds&note=stopped`); anything else is the console tab. */
export function landingOf(search: string): { tab: "console" | "builds"; note: string | null } {
  const q = new URLSearchParams(search);
  if (q.get("tab") !== "builds") return { tab: "console", note: null };
  return { tab: "builds", note: q.get("note") === "stopped" ? "That preview has stopped; press Open." : null };
}

export function App() {
  const { board, offset, live } = useBoard();
  const now = useNow(offset);
  const [error, setError] = useState<string | null>(null);
  const landed = landingOf(typeof window === "undefined" ? "" : window.location.search);
  const [tab, setTab] = useState<"console" | "plan" | "builds" | "health">(landed.tab);
  const [note] = useState(landed.note);

  // every click is a typed command that the reducer may refuse; the reason is shown, never hidden
  const act = async (cmd: Record<string, unknown>) => {
    const r = await sendAsUser(cmd);
    setError(r.ok ? null : `Refused: ${r.reason}`);
  };

  return (
    <main className={`mx-auto space-y-6 p-6 ${tab === "plan" ? "max-w-7xl" : "max-w-5xl"}`}>
      <header className="flex items-center justify-between">
        <h1 className="text-xl font-semibold">fw console</h1>
        <nav className="flex gap-1" aria-label="views">
          <Button size="sm" variant={tab === "console" ? "default" : "outline"} onClick={() => setTab("console")}>Console</Button>
          <Button size="sm" variant={tab === "plan" ? "default" : "outline"} onClick={() => setTab("plan")}>
            Plan{board ? ` (${board.plan.tasks.filter((t) => t.state === "ready").length} ready)` : ""}</Button>
          <Button size="sm" variant={tab === "builds" ? "default" : "outline"} onClick={() => setTab("builds")}>Builds</Button>
          <Button size="sm" variant={tab === "health" ? "default" : "outline"} onClick={() => setTab("health")}>Health</Button>
        </nav>
        <Badge variant={live ? "default" : "destructive"}>{live ? "live" : "reconnecting"}</Badge>
      </header>
      {note && tab === "builds" && <p role="status" className="rounded border p-2 text-sm">{note}</p>}
      {error && <p role="alert" className="rounded border border-destructive p-2 text-sm text-destructive">{error}</p>}
      {!board ? <p className="text-muted-foreground">Waiting for console-api...</p> : (
        tab === "plan" ? <PlanView board={board} /> : tab === "builds" ? <BuildsView /> : tab === "health" ? <HealthView now={now} /> : (
          <>
            <Steps board={board} act={act} now={now} />
            <StatusBoard board={board} now={now} />
          </>
        )
      )}
    </main>
  );
}

type Act = (cmd: Record<string, unknown>) => Promise<void>;

function Steps({ board, act, now }: { board: Board; act: Act; now: number }) {
  const open = board.steps.filter((s) => s.status === "waiting" || s.status === "started");
  const closed = board.steps.filter((s) => !open.includes(s)).slice(-5).reverse();
  return (
    <Card>
      <CardHeader><CardTitle>Your steps ({open.length})</CardTitle></CardHeader>
      <CardContent className="space-y-3">
        {open.length === 0 && <p className="text-sm text-muted-foreground">Nothing needs you.</p>}
        {open.map((s) => <StepRow key={s.id} step={s} act={act} now={now} />)}
        <PostForm act={act} />
        {closed.length > 0 && (
          <ul className="border-t pt-2 text-sm text-muted-foreground">
            {closed.map((s) => <li key={s.id}>{s.status}: {s.title}{s.answer ? ` (${s.answer})` : ""}</li>)}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

function StepRow({ step, act, now }: { step: Step; act: Act; now: number }) {
  const [text, setText] = useState("");
  const isAction = step.kind === "action";
  return (
    <div className="flex flex-wrap items-center gap-2 rounded border p-2">
      <div className="min-w-0 flex-1">
        <div className="font-medium">{step.title}</div>
        <div className="text-xs text-muted-foreground">
          {step.id}{step.card ? ` / card ${step.card}` : ""} / {step.status} / posted {age(now - step.postedAt)} ago
        </div>
      </div>
      {step.status === "waiting" && <Button size="sm" variant="outline" onClick={() => act({ type: "step.start", step: step.id })}>Start</Button>}
      {isAction && step.status === "started" && <Button size="sm" onClick={() => act({ type: "step.done", step: step.id })}>Done</Button>}
      {step.kind === "yes_no" && ["yes", "no"].map((a) => (
        <Button key={a} size="sm" onClick={() => act({ type: "step.answer", step: step.id, answer: a })}>{a}</Button>))}
      {step.kind === "choice" && (step.options ?? []).map((o) => (
        <Button key={o} size="sm" onClick={() => act({ type: "step.answer", step: step.id, answer: o })}>{o}</Button>))}
      {step.kind === "text" && (
        <>
          <input className="rounded border px-2 py-1 text-sm" value={text} onChange={(e) => setText(e.target.value)} placeholder="answer" />
          <Button size="sm" disabled={!text} onClick={() => act({ type: "step.answer", step: step.id, answer: text }).then(() => setText(""))}>Answer</Button>
        </>
      )}
      {step.status === "started" && step.kind !== "action" && (
        <Button size="sm" variant="ghost" onClick={() => act({ type: "step.done", step: step.id })}>Done</Button>)}
    </div>
  );
}

function PostForm({ act }: { act: Act }) {
  const [title, setTitle] = useState("");
  const [kind, setKind] = useState<StepKind>("action");
  const [options, setOptions] = useState("");
  const [card, setCard] = useState("");
  const submit = async () => {
    await act({ type: "step.post", step: `web-${crypto.randomUUID().slice(0, 8)}`, card: card || null, title, kind,
      options: kind === "choice" ? options.split(",").map((o) => o.trim()).filter(Boolean) : null });
    setTitle("");
  };
  return (
    <form className="flex flex-wrap gap-2 border-t pt-3" onSubmit={(e) => { e.preventDefault(); void submit(); }}>
      <input className="min-w-48 flex-1 rounded border px-2 py-1 text-sm" placeholder="Post a step for yourself" value={title} onChange={(e) => setTitle(e.target.value)} />
      <select className="rounded border px-2 py-1 text-sm" value={kind} onChange={(e) => setKind(e.target.value as StepKind)}>
        <option value="action">action</option><option value="yes_no">yes/no</option>
        <option value="choice">choice</option><option value="text">text</option>
      </select>
      {kind === "choice" && <input className="rounded border px-2 py-1 text-sm" placeholder="A, B" value={options} onChange={(e) => setOptions(e.target.value)} />}
      <input className="w-28 rounded border px-2 py-1 text-sm" placeholder="card (opt.)" value={card} onChange={(e) => setCard(e.target.value)} />
      <Button type="submit" size="sm" disabled={!title}>Post</Button>
    </form>
  );
}

function StatusBoard({ board, now }: { board: Board; now: number }) {
  return (
    <Card>
      <CardHeader><CardTitle>Status ({board.cards.length} cards, event #{board.seq})</CardTitle></CardHeader>
      <CardContent>
        <p className="mb-2 text-xs text-muted-foreground">Every field is derived from the event log; nothing here can be edited.</p>
        <Table>
          <TableHeader>
            <TableRow><TableHead>Card</TableHead><TableHead>Stage</TableHead><TableHead>Owner</TableHead>
              <TableHead>Next</TableHead><TableHead>Last event</TableHead><TableHead>Needs you</TableHead></TableRow>
          </TableHeader>
          <TableBody>
            {board.cards.map((c) => (
              <TableRow key={c.id}>
                <TableCell className="font-medium">{c.id} {c.violation && <Badge variant="destructive">violation</Badge>}</TableCell>
                <TableCell><Badge variant="secondary">{c.stage}</Badge></TableCell>
                <TableCell>{c.owner}</TableCell>
                <TableCell>{c.next.who}: <code>{c.next.command}</code></TableCell>
                <TableCell>{age(now - c.lastAt)} ago {c.stale && <Badge variant="destructive">stale</Badge>}</TableCell>
                <TableCell>{c.needsYou ? <Badge>{c.needsYou.action}</Badge> : "-"}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </CardContent>
    </Card>
  );
}
