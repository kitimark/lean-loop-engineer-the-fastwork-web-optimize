import { useState } from "react";
import { apiFetch } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { previewBase, refusedText } from "./TaskDetail";

// Rendering and the open loop only (review-preview-devices). Which arm and search a button opens, which device the viewport width
// means and what the card still asks for are Lean `console.reviewPreview` (console-api `POST /api/reviews/<flag>/preview`,
// `GET /api/reviews`). The build is opened through the task-preview machinery (`POST /api/builds/open`), and the link is built from
// this page's own host, so the buttons work on the phone over the LAN.
export type PreviewState = { open: boolean; desktop: boolean; phone: boolean; missing: string[]; asks: string[] };
type View = "flag" | "faithful" | "compare";
const VIEWS: { view: View; label: string; hint: string }[] = [
  { view: "flag", label: "Flag", hint: "main with only this flag on" },
  { view: "faithful", label: "Faithful", hint: "the faithful rewrite, no flag" },
  { view: "compare", label: "Compare", hint: "the original and the flag side by side" },
];
const J = { "content-type": "application/json" };
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const yn = (b: boolean) => (b ? "yes" : "no");

/** The address of an arm page on the preview port, from the page's own host. */
export const armHref = (port: number | null | undefined, path: string, loc?: { protocol: string; hostname: string }) => `${previewBase(port, loc)}${path}`;

/** "Previewed on: desktop yes/no, phone yes/no" and, while a device is missing, the lines Lean words. */
export function PreviewStatus({ p }: { p: PreviewState }) {
  return (
    <div className="space-y-1 text-xs" data-testid="previewed">
      <p data-testid="previewed-on">Previewed on: desktop {yn(p.desktop)}, phone {yn(p.phone)}</p>
      {p.asks.map((a) => <p key={a} className="break-words text-muted-foreground" data-testid="preview-ask">{a}</p>)}
    </div>
  );
}

/** The Preview section of an open look-change card: three buttons and the device line. */
export function ReviewPreview({ flag, preview, onChanged }: { flag: string; preview: PreviewState | null | undefined; onChanged?: () => void }) {
  const [busy, setBusy] = useState<View | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [opened, setOpened] = useState<{ view: View; href: string } | null>(null);
  if (!preview || !preview.open) return null;
  const route = `/api/reviews/${encodeURIComponent(flag)}/preview`;

  /** Ask Lean for the plan, open (or reuse) the main build with it, send the tab there and then record the preview. */
  async function run(view: View) {
    setMsg(null); setBusy(view);
    const w = window.open("about:blank", "_blank"); // on the click, so a pop-up blocker allows it
    if (w) w.opener = null;
    const fail = (m: string) => { w?.close(); setMsg(m); };
    const body = { view, width: window.innerWidth };
    try {
      const plan = await (await apiFetch(route, { method: "POST", headers: J, body: JSON.stringify(body) })).json();
      if (!plan.ok) return fail(String(plan.reason));
      const until = Date.now() + 10 * 60_000;
      while (Date.now() < until) {
        const j = await (await apiFetch("/api/builds/open", { method: "POST", headers: J, body: JSON.stringify({ search: plan.search, arm: plan.arm }) })).json();
        if (!j.ok) return fail(j.reason === "search refused" ? "That search is not valid; nothing was opened." : refusedText(String(j.reason)));
        if (j.state === "open") {
          const href = armHref(plan.previewPort, String(j.path));
          if (w) w.location.href = href; else setMsg(`Pop-up blocked: open ${href}`);
          setOpened({ view, href });
          await apiFetch(route, { method: "POST", headers: J, body: JSON.stringify({ ...body, done: true }) });
          onChanged?.();
          return;
        }
        const id = String(j.preview);
        while (Date.now() < until) { // pending: wait until the build serves (or is gone), then ask again
          await sleep(2000);
          const l = await (await apiFetch("/api/previews")).json();
          const p = (l.previews ?? []).find((x: { id: string; phase: string }) => x.id === id);
          if (p?.phase === "serving") break;
          if (!p) { const f = (l.failed ?? []).find((x: { id: string }) => x.id === id); return fail(f ? `The build failed: ${f.error}` : "The build stopped before it was ready."); }
        }
      }
      fail("Timed out waiting for the build.");
    } catch (e) { fail((e as Error).message); } finally { setBusy(null); }
  }

  return (
    <div className="space-y-2" data-testid="review-preview">
      <h4 className="text-sm font-medium">Preview</h4>
      <div className="flex flex-wrap gap-2">
        {VIEWS.map((v) => (
          <Button key={v.view} className="min-h-11 flex-1 sm:flex-none" variant="outline" disabled={busy !== null} title={v.hint} data-testid={`preview-${v.view}`} onClick={() => void run(v.view)}>
            {busy === v.view ? "Opening..." : `Preview: ${v.label}`}
          </Button>
        ))}
      </div>
      <PreviewStatus p={preview} />
      {opened ? <p className="break-all text-xs" data-testid="preview-opened">Opened ({opened.view}): <a className="underline" href={opened.href} target="_blank" rel="noreferrer">{opened.href}</a></p> : null}
      {msg ? <p className="break-words text-xs text-destructive" role="alert">{msg}</p> : null}
    </div>
  );
}
