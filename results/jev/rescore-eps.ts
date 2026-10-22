import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { fwcoreCall } from "../../apps/runner/src/run.ts";
import { datasetsDir, logPathFor, pickedRows, redactNames } from "../../apps/runner/src/oracle.ts";
import { jevAnswers, scoreArm } from "../../apps/runner/src/oracle-score.ts";
import type { FwCall, Json } from "@fw/oracle";

const data = process.cwd();
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const oldBin = process.argv[2]!;
const write = process.argv.includes("--write");
const oldCore: FwCall = (req) => {
  const r = spawnSync(oldBin, [], { input: JSON.stringify({ ...req, id: 0 }) + "\n", maxBuffer: 1 << 30 });
  const { id: _id, ...rest } = JSON.parse(r.stdout.toString().trim().split("\n")[0]!) as Record<string, unknown>;
  return rest as Json;
};
const newCore = fwcoreCall(root);
const arms = join(root, "results/jev-arms-clean");

type Verdict = { ok: boolean; failure?: { detail?: string; kind?: string }; answer?: { pick?: string } };
type Answer = { id: string; reply?: string; choice?: string; probabilities?: Json };
type Score = { all: { right: number; rows: number }; holdout: { right: number; rows: number };
  holdoutCert: { hits: number; covered: number; options: { option: string; hits: number; advised: number }[] } };
const tally = (vs: Verdict[]) => {
  const invalid: Record<string, number> = {};
  for (const v of vs) if (!v.ok) {
    const k = String(v.failure?.detail ?? v.failure?.kind);
    invalid[k] = (invalid[k] ?? 0) + 1;
  }
  return { valid: vs.filter((v) => v.ok).length, invalid };
};
const readJsonl = (file: string): Answer[] => existsSync(file)
  ? readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l) as Answer) : [];
const certify = (s: Score) => {
  const advised = s.holdoutCert.options.filter((o) => o.advised > 0).map((o) => `${o.option} ${o.hits}/${o.advised}`);
  return advised.length ? `${s.holdoutCert.hits}/${s.holdoutCert.covered}: ${advised.join(", ")}` : "none";
};

const jev: Record<string, Json> = {};
const runs: Record<string, Json> = {};
for (const set of ["d1", "d2"]) {
  const picked = pickedRows(newCore, set, datasetsDir(data));
  if (typeof picked === "string") throw new Error(picked);
  const q = picked.question;
  const byId = new Map(picked.rows.map((r) => [r.id, r]));
  const model = JSON.parse(String(newCore({ op: "oracle.request", name: q, names: [], state: {} }).bodyText)).model;
  const reqOf = (a: Answer) => ({ op: "oracle.validate", name: q, reply: a.reply ?? JSON.stringify({ model,
    answers: { [q]: { type: "choice", choice: a.choice, probabilities: a.probabilities } } }) });
  const choiceOf = (a: Answer) => a.choice ?? (() => {
    try { return String(JSON.parse(a.reply!).answers?.[q]?.choice); } catch { return undefined; }
  })();

  const jevAll = (jevAnswers(newCore, q, redactNames(data), picked.rows, logPathFor(data)) as Answer[]);
  const replies = jevAll.filter((a) => typeof a.reply === "string");
  const verdicts = replies.map((a) => ({ a, old: oldCore(reqOf(a)) as Verdict, now: newCore(reqOf(a)) as Verdict }));
  const parts: Record<string, Json> = {};
  for (const part of ["all", ...new Set(picked.rows.map((r) => r.part))]) {
    const vs = verdicts.filter((v) => part === "all" || byId.get(v.a.id)?.part === part);
    parts[part] = { replies: vs.length, old: tally(vs.map((v) => v.old)), new: tally(vs.map((v) => v.now)) };
  }
  jev[set] = {
    question: q, rows: picked.rows.length, parts,
    flipped: verdicts.filter((v) => !v.old.ok && v.now.ok).map((v) => ({
      id: v.a.id, part: byId.get(v.a.id)?.part, label: byId.get(v.a.id)?.label, pick: v.now.answer?.pick,
      oldReason: v.old.failure?.detail })),
    rejectedNow: verdicts.filter((v) => v.old.ok && !v.now.ok).length,
  };

  const sources: [string, string, string | null, Answer[]][] = [["jev", "recorded", null, jevAll]];
  for (const arm of ["haiku", "sonnet"]) {
    sources.push([arm, "first", `results/jev-arms-clean/first-run/${set}-${arm}.jsonl`,
      readJsonl(join(arms, "first-run", `${set}-${arm}.jsonl`))]);
    sources.push([arm, "clean", `results/jev-arms-clean/${set}-${arm}.answers.jsonl`,
      readJsonl(join(arms, `${set}-${arm}.answers.jsonl`))]);
  }
  for (const [arm, run, file, answers] of sources) {
    const scored = answers.filter((a) => a.reply !== undefined || a.choice !== undefined);
    const vs = scored.map((a) => ({ a, old: oldCore(reqOf(a)) as Verdict, now: newCore(reqOf(a)) as Verdict }));
    const right = (sel: (v: (typeof vs)[number]) => boolean) =>
      vs.filter((v) => sel(v) && choiceOf(v.a) === String(byId.get(v.a.id)?.label)).length;
    const so = scoreArm(oldCore, q, arm, picked.rows, answers as Json[]) as Score;
    const sn = scoreArm(newCore, q, arm, picked.rows, answers as Json[]) as Score;
    runs[`${set}:${arm}:${run}`] = {
      file: file ?? "logged Jev replies", rows: picked.rows.length, answers: scored.length,
      right: { old: so.all.right, new: sn.all.right }, holdoutRight: { old: so.holdout.right, new: sn.holdout.right },
      holdoutRows: sn.holdout.rows,
      valid: { old: vs.filter((v) => v.old.ok).length, new: vs.filter((v) => v.now.ok).length },
      validRight: { old: right((v) => v.old.ok), new: right((v) => v.now.ok) },
      certify: { old: certify(so), new: certify(sn) },
      invalid: { old: tally(vs.map((v) => v.old)).invalid, new: tally(vs.map((v) => v.now)).invalid },
      rejectedNow: vs.filter((v) => v.old.ok && !v.now.ok).length,
    };
  }
}

const BEGIN = "<!-- oracle-eps re-validation: node results/jev/rescore-eps.ts <old fwcore> --write -->";
const END = "<!-- /oracle-eps -->";
type Run = { rows: number; answers: number; right: { old: number; new: number }; valid: { old: number; new: number };
  validRight: { old: number; new: number }; certify: { old: string; new: string } };
const md = [BEGIN,
  "Re-validated under `Fw.Oracle.Core.sumOk` (task oracle-eps) from the answer files above, no re-runs and no sends; " +
  "the invalid column of the first table is the old `eps` rule.", "",
  "| set | arm | run | answers | valid, old eps | valid, sumOk | right of valid, old eps | right of valid, sumOk | " +
  "right / rows (both rules) | certify, old eps | certify, sumOk |",
  "|---|---|---|---|---|---|---|---|---|---|---|"];
for (const [k, v] of Object.entries(runs) as [string, Run][]) {
  const [set, arm, run] = k.split(":");
  const right = v.right.old === v.right.new ? `${v.right.new} / ${v.rows}` : `${v.right.old} → ${v.right.new} / ${v.rows}`;
  md.push(`| ${set} | ${arm} | ${run} | ${v.answers} | ${v.valid.old} | ${v.valid.new} | ${v.validRight.old} | ` +
    `${v.validRight.new} | ${right} | ${v.certify.old} | ${v.certify.new} |`);
}
md.push(END);

const json = JSON.stringify({ jev, runs }, null, 2) + "\n";
if (write) {
  writeFileSync(join(root, "results/jev/eps-rescore.json"), json);
  const tablePath = join(arms, "table.md");
  const prev = readFileSync(tablePath, "utf8");
  const a = prev.indexOf(BEGIN);
  const base = a < 0 ? prev : prev.slice(0, a) + prev.slice(prev.indexOf(END) + END.length + 1);
  writeFileSync(tablePath, base.trimEnd() + "\n\n" + md.join("\n") + "\n");
} else process.stdout.write(json);
