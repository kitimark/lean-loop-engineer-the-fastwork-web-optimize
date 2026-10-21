// Prints every table of research/notes/2026/10-21-macos-minutes.md from jobs.json, circleci.json and facts.json.
// Usage (repo root): node research/notes/2026/macos-minutes/tables.mjs          -> every table block, in note order
//                    node research/notes/2026/macos-minutes/tables.mjs --check  -> exit 1 unless each block is in the note verbatim,
//                                                                                followed by a blank line or the note's end
// A one-off JS reduction of one measured day: a stand-in, not a Lean decision (named in the note's accepted limits).
// Minutes are summed in whole seconds of job wall (startedAt..completedAt) and rounded half up to 0.1 min at print.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => JSON.parse(readFileSync(join(here, f), "utf8"));
const J = read("jobs.json");
const C = read("circleci.json");
const F = read("facts.json");

const sec = (j) => (Date.parse(j.end) - Date.parse(j.start)) / 1000;
const sumS = (js) => js.reduce((a, j) => a + sec(j), 0);
const m1 = (s) => (Math.round(s / 6) / 10).toFixed(1);
const pct = (a, b) => `${Math.round((100 * a) / b)} %`;
/** Job-min per day at the window's rate, from seconds. */
const perDay = (s) => (s / 60) * (24 / F.window.hours);
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); const m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
const ok = (j) => j.outcome === "success";
const stepS = (j, re) => j.steps.filter(([n]) => re.test(n)).reduce((a, [, d]) => a + d, 0);
const cell = (j) => j.name.match(/, (\w+)\)$/)?.[1] ?? "";
const legOf = (j) => j.name.match(/macos-26\) (\S+)$/)?.[1] ?? "";
const row = (cells) => `| ${cells.join(" | ")} |`;
const table = (head, rows) => [row(head), row(head.map(() => "---")), ...rows.map(row)].join("\n");
const byRun = (js) => { const m = new Map(); for (const j of js) { if (!m.has(j.run)) m.set(j.run, []); m.get(j.run).push(j); } return m; };
const fail = (msg) => { console.error(`tables.mjs: ${msg}`); process.exit(2); };

const out = [];
const emit = (name, text) => out.push(`<!-- generated: tables.mjs ${name} -->\n${text}`);
const totalS = sumS(J);
const traj = J.filter((j) => j.lane === "trajectory-probe");
const sim = J.filter((j) => j.lane === "webkit-sim");

// lanes: where the window's minutes went.
{
  const line = (label, js) => {
    const bad = js.filter((j) => !ok(j));
    const disp = js.filter((j) => j.event === "workflow_dispatch");
    return [label, byRun(js).size, js.length, m1(sumS(js)), pct(sumS(js), totalS), `${m1(sumS(disp))} (${pct(sumS(disp), sumS(js))})`,
      m1(sumS(js.filter((j) => j.event === "push"))), `${bad.length} / ${m1(sumS(bad))} (${pct(sumS(bad), sumS(js))})`];
  };
  const rows = [line("trajectory-probe", traj), line("webkit-sim", sim),
    ["wktr, wktr-fixtures, engine-premises, gate-gaps, sim-speed", 0, 0, "0.0", "0 %", "0.0", "0.0", "0 / 0.0"],
    line("**all**", J),
    [`all, per day (x 24 / ${F.window.hours} h)`, "", "", perDay(totalS).toFixed(1), "", perDay(sumS(J.filter((j) => j.event === "workflow_dispatch"))).toFixed(1), "", ""]];
  emit("lanes", table(["lane", "runs", "jobs", "job-min", "share", "dispatch job-min (share)", "push job-min", "non-success jobs / job-min (share)"], rows));
}

// widths: trajectory-probe dispatch runs with apple jobs, by the widths they walked.
{
  const all = F.allWidths.join(",");
  const groups = { two: [], single: [], subset: [] };
  for (const [run, js] of byRun(traj.filter((j) => j.event === "workflow_dispatch"))) {
    const legs = [...new Set(js.map(legOf))];
    if (legs.length === 1 && !/^\d/.test(legs[0])) {
      if (!js.every((j) => j.steps.some(([n]) => /every width/.test(n)))) fail(`run ${run}: single job without the every-width step`);
      groups.single.push({ run, js });
      continue;
    }
    const ws = [...new Set(legs.flatMap((l) => l.split("_").map(Number)))].sort((a, b) => a - b);
    (ws.join(",") === all ? groups.two : groups.subset).push({ run, js, ws });
  }
  const g = (label, xs, ids) => [label, xs.length, xs.reduce((a, x) => a + x.js.length, 0), m1(sumS(xs.flatMap((x) => x.js))), ids];
  const rows = [
    g("two legs 390_641 + 640_1280: all four widths (MEASURED, job names)", groups.two, ""),
    g("one job, step 'Walk the hero path (both arms, every width)': all four (INFERRED, step name)", groups.single, ""),
    g("a subset of the widths (MEASURED, job names)", groups.subset, groups.subset.map((x) => `${x.run} (${x.ws.join("+")})`).join(", ")),
  ];
  const n = groups.two.length + groups.single.length + groups.subset.length;
  rows.push([`**all four widths: ${groups.two.length + groups.single.length} of ${n} runs**`, n,
    rows.reduce((a, r) => a + r[2], 0), m1(sumS(traj.filter((j) => j.event === "workflow_dispatch"))), ""]);
  emit("widths", table(["trajectory-probe dispatch runs with apple jobs", "runs", "jobs", "job-min", "subset runs (widths)"], rows));
}

// series: the ci/scoped-close-start-cause dispatch series and what scoping it to one leg would have saved.
const series = traj.filter((j) => j.branch === F.series.branch && j.event === "workflow_dispatch");
const queued = series.filter((j) => !F.series.freshRuns.includes(j.run));
{
  const qRuns = byRun(queued);
  let lo = 0, hi = 0;
  for (const [run, js] of qRuns) {
    if (js.length !== 2) fail(`series run ${run}: ${js.length} jobs, expected 2 legs`);
    const s = js.map(sec).sort((a, b) => a - b);
    lo += s[0]; hi += s[1];
  }
  const rows = [
    [`all dispatch runs on ${F.series.branch}`, byRun(series).size, series.length, m1(sumS(series)), "", ""],
    ["the queued runs (5-vs-5 permutation test)", qRuns.size, queued.length, m1(sumS(queued)), "", ""],
    ["saved had each queued run walked one leg (drop its shorter .. longer leg)", qRuns.size, qRuns.size, `${m1(lo)} .. ${m1(hi)}`,
      `${perDay(lo).toFixed(0)} .. ${perDay(hi).toFixed(0)}`, `${m1(median(queued.map(sec)))} min`],
  ];
  emit("series", table(["group", "runs", "jobs", "job-min", "job-min/day at the window rate", "median job"], rows));
}

// wait: who bore the external slot wait (a free matrix slot but no runner), the external part taken as the last part
// of a job's wait. Two bases: every job's external wait, and only waits over 120 s (the measure job's list).
{
  const LIST_S = 120;
  const ext = (js, min = 0) => js.reduce((a, j) => a + ((j.waitExtS ?? 0) > min ? j.waitExtS : 0), 0);
  const qIds = new Set(queued.map((j) => j.run));
  const others = J.filter((j) => !qIds.has(j.run));
  const from = Math.min(...queued.map((j) => Date.parse(j.runCreated) / 1000));
  const to = Math.max(...queued.map((j) => Date.parse(j.end) / 1000));
  const overlap = (min) => (j) => {
    if ((j.waitExtS ?? 0) <= min) return 0;
    const e = Date.parse(j.start) / 1000;
    return Math.max(0, Math.min(e, to) - Math.max(e - j.waitExtS, from));
  };
  const ov = (min) => others.reduce((a, j) => a + overlap(min)(j), 0);
  const all = ext(J);
  const both = (label, n, f) => [label, n, `${m1(f(0))} (${pct(f(0), all)})`, `${m1(f(LIST_S))} (${pct(f(LIST_S), all)})`];
  const rows = [
    both("all macOS jobs", J.length, (m) => ext(J, m)),
    both("the queued series runs", queued.length, (m) => ext(queued, m)),
    both("every other job", others.length, (m) => ext(others, m)),
    both("  of which webkit-sim", sim.length, (m) => ext(sim, m)),
    both("  of which inside the series' span (first queued run created .. last series job end)", others.length, ov),
  ];
  emit("wait", table(["jobs", "count", "external wait job-min, every wait (share of all)", `external wait job-min, waits > ${LIST_S} s (share of all)`], rows));
}

// concurrency: this repo's macOS jobs running at once (1 s timestamps).
{
  const ev = J.flatMap((j) => [[Date.parse(j.start), 1], [Date.parse(j.end), -1]]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const at = new Map(); let n = 0, t0 = ev[0][0];
  for (const [t, d] of ev) { if (n > 0) at.set(n, (at.get(n) ?? 0) + (t - t0)); n += d; t0 = t; }
  const ks = [...at.keys()].sort((a, b) => a - b);
  emit("concurrency", table(["macOS jobs running at once", ...ks.map(String)], [["minutes", ...ks.map((k) => m1(at.get(k) / 1000))]]));
}

// lost: webkit-sim's non-success minutes by class.
{
  const bad = sim.filter((j) => !ok(j));
  const seen = new Set();
  const rows = Object.entries(F.lostClasses).map(([k, c]) => {
    const js = F.lostJobs.filter((l) => l.class === k).map((l) => {
      const m = bad.filter((j) => j.run === l.run && cell(j) === l.cell);
      if (m.length !== 1) fail(`lost job ${l.run} ${l.cell}: ${m.length} non-success matches`);
      if (k === "d" && stepS(m[0], /^Keep logs/) < 180) fail(`class d job ${l.run} ${l.cell}: Keep logs under 180 s`);
      seen.add(m[0]);
      return m[0];
    });
    return [`(${k}) ${c.label}`, js.map((j) => `${j.run} ${cell(j)} ${m1(sec(j))}`).join("; "), js.length, m1(sumS(js)), c.state, c.tag];
  });
  if (seen.size !== bad.length) fail(`${bad.length - seen.size} non-success webkit-sim jobs unclassified`);
  rows.push(["**all non-success**", "", bad.length, `${m1(sumS(bad))} of ${m1(sumS(sim))}`, "", ""]);
  emit("lost", table(["class", "jobs (run cell min)", "jobs", "job-min", "state", "tag"], rows));
}

// teardown: webkit-sim step medians over successful jobs, and the trim estimate.
{
  const good = sim.filter(ok);
  const med = (re) => median(good.map((j) => stepS(j, re)));
  const keep = med(/^Keep logs/);
  const rows = [
    ["Keep logs and host state", good.length, keep, "kept: cp feeds the upload; host state only on failure()"],
    ["Shut down and delete the Simulator", good.length, med(/^Shut down/), "skip: the VM is discarded"],
    ["ios_webkit_debug_proxy (brew install)", good.length, med(/^ios_webkit_debug_proxy$/), "cache it"],
    ["Boot the Simulator", good.length, med(/^Boot the Simulator/), "kept"],
    ["Determinism sessions (the measurement)", good.length, med(/^Determinism sessions$/), "kept"],
  ];
  const perJob = Object.values(F.teardownTrim.perJobS).reduce((a, b) => a + b, 0);
  const dJobs = F.lostJobs.filter((l) => l.class === "d").map((l) => sim.find((j) => j.run === l.run && cell(j) === l.cell && !ok(j)));
  const extra = dJobs.reduce((a, j) => a + stepS(j, /^Keep logs/) - keep, 0);
  rows.push([`trim: ${perJob} s per job x ${sim.length} jobs`, sim.length, "", `${m1(perJob * sim.length)} job-min, ${perDay(perJob * sim.length).toFixed(1)}/day`]);
  rows.push([`Keep-logs timeouts: ${dJobs.length} jobs over the median`, dJobs.length, dJobs.map((j) => stepS(j, /^Keep logs/)).join(", "), `${m1(extra)} job-min`]);
  emit("teardown", table(["webkit-sim step", "jobs", "median s", "change"], rows));
}

// circleci: credits by workflow, run level against the insights summary.
{
  const runC = (w) => C[w].runs.reduce((a, r) => a + r.credits, 0);
  const sumC = (w) => C[w].summaryJobs.reduce((a, j) => a + j.credits, 0);
  const ws = Object.keys(C);
  const total = ws.reduce((a, w) => a + runC(w), 0);
  const rows = ws.map((w) => [w, C[w].runs.length, runC(w), sumC(w)]);
  rows.push(["**all**", ws.reduce((a, w) => a + C[w].runs.length, 0), total, ws.reduce((a, w) => a + sumC(w), 0)]);
  const p = F.circleci;
  rows.push([`left of ${p.planCredits} (of ${p.altPlanCredits})`, "", `${p.planCredits - total} (${p.altPlanCredits - total})`, ""]);
  const m4 = C["webkit-sim"].runs.slice().sort((a, b) => a.created.localeCompare(b.created))
    .map((r) => [r.created.slice(0, 16).replace("T", " "), r.durationS, r.status, r.credits]);
  emit("circleci", table(["CircleCI workflow (last 30 days)", "runs", "credits, run level", "credits, insights summary"], rows));
  emit("m4pro", table(["m4pro webkit-sim pipeline (UTC)", "wall s", "status", "credits"], m4));
}

// saved: what earlier work already saved.
{
  const rows = F.saved.map((s) => [s.change, s.state, s.saved,
    s.lanes.length ? m1(sumS(J.filter((j) => s.lanes.includes(j.lane)))) : "-", s.tag]);
  emit("saved", table(["change", "state", "saved", "its lanes' job-min in this window", "tag"], rows));
}

// plan: the ranked plan after the check, with totals at the window rate.
{
  const fmt = (p) => (p.hi === 0 ? "0" : p.firm ? `~${p.lo}-${p.hi}` : `<= ~${p.hi}`);
  const rows = F.plan.map((p) => [p.rank, p.change, p.verdict, p.task, fmt(p), p.tag]);
  const firm = F.plan.filter((p) => p.firm && p.hi > 0);
  const up = F.plan.filter((p) => !p.firm).reduce((a, p) => a + p.hi, 0);
  const lo = firm.reduce((a, p) => a + p.lo, 0), hi = firm.reduce((a, p) => a + p.hi, 0);
  const rate = perDay(totalS);
  rows.push(["", `**firm (ranks ${firm.map((p) => p.rank).join(", ")})**`, "", "", `~${lo}-${hi}`, `${pct(lo, rate)} - ${pct(hi, rate)} of ${rate.toFixed(0)}/day`]);
  rows.push(["", "**with diagnostic scoping**", "", "", `~${lo}-${hi + up}`, `${pct(lo, rate)} - ${pct(hi + up, rate)} of ${rate.toFixed(0)}/day`]);
  emit("plan", table(["rank", "change", "check verdict", "task", "job-min/day (upper bound)", "tag / basis"], rows));
}

if (process.argv.includes("--check")) {
  const note = readFileSync(join(here, "..", "10-21-macos-minutes.md"), "utf8");
  // A block counts only where it ends at a blank line or at the end of the note, so a row appended by hand fails.
  const ends = (b) => {
    for (let i = note.indexOf(b); i !== -1; i = note.indexOf(b, i + 1)) {
      const rest = note.slice(i + b.length);
      if (rest === "" || rest === "\n" || rest.startsWith("\n\n")) return true;
    }
    return false;
  };
  const missing = out.filter((b) => !ends(b)).map((b) => b.split("\n")[0]);
  if (missing.length) { console.error(`not verbatim in the note, or not followed by a blank line or the end:\n${missing.join("\n")}`); process.exit(1); }
  console.log(`ok: ${out.length} tables verbatim in the note`);
} else {
  console.log(out.join("\n\n"));
}
