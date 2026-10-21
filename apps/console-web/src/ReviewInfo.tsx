import { useEffect, useState } from "react";
import katex from "katex";
import "katex/dist/katex.min.css";
import { apiFetch } from "@/lib/auth";

// Rendering only. The gain table, the code ranges, the mechanism and the formulas are Lean `console.reviewInfo`
// (Fw.Console.ReviewInfo), served by console-api `GET /api/reviews/<flag>/info`, which also reads the code lines. Every formula
// is shown next to the Lean declaration it was written from.
export type Status =
  | { kind: "measured"; runs: string[]; aa: string[] }
  | { kind: "modelled"; theorem: string; golden: string }
  | { kind: "unknown"; why: string };
export type Gain = {
  metric: string; engine: string; push: string; viewport: string; before: [number, number] | null; after: [number, number] | null;
  noise: number; unit: string; status: Status; shown: { kind: "gain" | "noSaving" | "inNoise" | "overlap" | "worse" | "unknown"; n?: number; text: string };
};
export type Excerpt = { id: string; side: string; file: string; first: number; last: number; anchor: string; note: string } &
  ({ ok: true; lines: { n: number; text: string }[] } | { ok: false; reason: string });
export type Source = { claim: string; status: string; cite: string };
export type Formula = { id: string; tex: string; says: string; decl: string; file: string; line: number; kind: string };
export type InfoData =
  | { ok: false; reason: string }
  | { ok: true; flag: string; summary: string; gains: Gain[]; excerpts: Excerpt[]; mechanism: string[]; sources: Source[]; formulas: Formula[] };

/** The info of a flag, fetched once. `null` while loading; the refusal when the flag has no table. */
export function useReviewInfo(flag: string): InfoData | null {
  const [data, setData] = useState<InfoData | null>(null);
  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await apiFetch(`/api/reviews/${encodeURIComponent(flag)}/info`);
        const j = (await r.json()) as InfoData;
        if (live) setData(j);
      } catch { if (live) setData({ ok: false, reason: "the information could not be loaded" }); }
    })();
    return () => { live = false; };
  }, [flag]);
  return data;
}

const range = (r: [number, number] | null) => (r === null ? "-" : r[0] === r[1] ? String(r[0]) : `${r[0]}-${r[1]}`);
const PUSH: Record<string, string> = { open: "button leaves", close: "button comes back" };

/** The status of a row in words; a number never appears without it. */
export function statusText(s: Status): string {
  switch (s.kind) {
    case "measured": return `MEASURED (CI runs ${s.runs.join(", ")}; A/A runs ${s.aa.join(", ")})`;
    case "modelled": return `MODELLED (Lean ${s.theorem}; golden ${s.golden})`;
    case "unknown": return `UNKNOWN: ${s.why}`;
  }
}

/** One formula as KaTeX markup. A formula KaTeX cannot parse throws; the test renders every formula. */
export function mathHtml(tex: string): string {
  return katex.renderToString(tex, { displayMode: true, throwOnError: true, output: "htmlAndMathml" });
}

function GainTable({ gains }: { gains: Gain[] }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-left text-xs" data-testid="gain-table">
        <thead>
          <tr className="border-b">
            {["Metric", "Engine", "Push", "Viewport", "Before (faithful)", "After (flag)", "Delta", "Unit", "Status"].map((h) => <th key={h} className="py-1 pr-2 font-medium">{h}</th>)}
          </tr>
        </thead>
        <tbody>
          {gains.map((g, i) => (
            <tr key={i} className="border-b align-top" data-testid="gain-row" data-shown={g.shown.kind} data-status={g.status.kind}>
              <td className="py-1 pr-2">{g.metric}</td>
              <td className="py-1 pr-2">{g.engine}</td>
              <td className="py-1 pr-2">{PUSH[g.push] ?? g.push}</td>
              <td className="py-1 pr-2">{g.viewport}</td>
              <td className="py-1 pr-2 font-mono">{range(g.before)}</td>
              <td className="py-1 pr-2 font-mono">{range(g.after)}</td>
              <td className="py-1 pr-2" data-testid="gain-delta">{g.shown.text}</td>
              <td className="py-1 pr-2">{g.unit}</td>
              <td className="py-1 break-words" data-testid="gain-status">{statusText(g.status)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function Code({ e }: { e: Excerpt }) {
  return (
    <figure className="space-y-1" data-testid={`excerpt-${e.id}`}>
      <figcaption className="text-xs">
        <span className="font-medium">{e.side === "faithful" ? "Faithful (both arms)" : e.side === "flag" ? "Flag" : "Both"}</span>{" "}
        <span className="font-mono">{e.file}:{e.first}{e.last > e.first ? `-${e.last}` : ""}</span>
      </figcaption>
      {e.ok
        ? <pre className="overflow-x-auto rounded bg-muted p-2 text-xs">{e.lines.map((l) => `${String(l.n).padStart(4)}  ${l.text}`).join("\n")}</pre>
        : <p className="text-xs" data-testid="excerpt-error">Not shown: {e.reason}</p>}
      <p className="text-xs">{e.note}</p>
    </figure>
  );
}

/** The information panel of a look-change review card (task review-info). */
export function ReviewInfo({ flag, data }: { flag: string; data: InfoData | null }) {
  if (!data) return <p className="text-xs" data-testid="review-info-loading">Loading what {flag} changes...</p>;
  if (!data.ok) return <p className="text-xs" data-testid="review-info-none">No information is written for {flag}: {data.reason}</p>;
  return (
    <div className="space-y-4" data-testid="review-info">
      <section className="space-y-2" data-testid="info-gain">
        <h3 className="text-sm font-medium">What you get if you keep it</h3>
        <p className="text-sm" data-testid="info-summary">{data.summary}</p>
        <GainTable gains={data.gains} />
        <p className="text-xs">A gain is the lowest faithful count minus the highest flag count; a loss (N more) is the highest faithful count minus the lowest flag count; ranges that share a count show no difference. A delta inside the A/A noise of the same metric (MEASURED from the two A/A runs of each row) is not shown. The 640 and 641 close pushes are left out (their close-push opacity loss is in the summary line) (the research note lists only their open rows). MEASURED rows are CI runs; MODELLED rows are Lean counts, checked against their golden; UNKNOWN rows say why.</p>
      </section>
      <section className="space-y-2" data-testid="info-code">
        <h3 className="text-sm font-medium">What changed in the code</h3>
        {data.excerpts.map((e) => <Code key={e.id} e={e} />)}
      </section>
      <section className="space-y-2" data-testid="info-math">
        <h3 className="text-sm font-medium">Why it is less work, and the math</h3>
        <ol className="list-decimal space-y-1 pl-5 text-sm" data-testid="info-mechanism">
          {data.mechanism.map((m, i) => <li key={i}>{m}</li>)}
        </ol>
        <ul className="space-y-1 text-xs" data-testid="info-sources">
          {data.sources.map((s, i) => <li key={i}>{s.claim} ({s.status}; <span className="font-mono">{s.cite}</span>)</li>)}
        </ul>
        <p className="text-xs">Notation: g<sub>k</sub> is the computed value at frame k, t<sub>k</sub> its time, δ and d the delay and duration of the transition, on<sub>k</sub> whether the property is listed in transition.</p>
        {data.formulas.map((f) => (
          <div key={f.id} className="space-y-1" data-testid={`formula-${f.id}`}>
            <div className="overflow-x-auto" dangerouslySetInnerHTML={{ __html: mathHtml(f.tex) }} />
            <p className="text-xs">{f.says} Lean {f.kind === "guard" ? "#guard" : f.kind} <span className="font-mono">{f.decl}</span> (<span className="font-mono">{f.file}:{f.line}</span>)</p>
          </div>
        ))}
      </section>
    </div>
  );
}
