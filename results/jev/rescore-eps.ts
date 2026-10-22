import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fwcoreCall } from "../../apps/runner/src/run.ts";
import { datasetsDir, logPathFor, pickedRows, redactNames } from "../../apps/runner/src/oracle.ts";
import { jevAnswers } from "../../apps/runner/src/oracle-score.ts";
import type { FwCall, Json } from "@fw/oracle";

const cwd = process.cwd();
const oldBin = process.argv[2]!;
const oldCore: FwCall = (req) => {
  const r = spawnSync(oldBin, [], { input: JSON.stringify({ ...req, id: 0 }) + "\n", maxBuffer: 1 << 30 });
  const { id: _id, ...rest } = JSON.parse(r.stdout.toString().trim().split("\n")[0]!) as Record<string, unknown>;
  return rest as Json;
};
const newCore = fwcoreCall(cwd);

type Verdict = { ok: boolean; failure?: { detail?: string }; answer?: { pick?: string } };
const tally = (vs: Verdict[]) => {
  const invalid: Record<string, number> = {};
  for (const v of vs) if (!v.ok) invalid[String(v.failure?.detail)] = (invalid[String(v.failure?.detail)] ?? 0) + 1;
  return { valid: vs.filter((v) => v.ok).length, invalid };
};

const out: Record<string, Json> = {};
for (const set of ["d1", "d2"]) {
  const picked = pickedRows(newCore, set, datasetsDir(cwd));
  if (typeof picked === "string") throw new Error(picked);
  const answers = jevAnswers(newCore, picked.question, redactNames(cwd), picked.rows, logPathFor(cwd)) as
    { id: string; reply?: string }[];
  const byId = new Map(picked.rows.map((r) => [r.id, r]));
  const replies = answers.filter((a) => typeof a.reply === "string");
  const verdicts = replies.map((a) => {
    const req = { op: "oracle.validate", name: picked.question, reply: a.reply! };
    return { a, old: oldCore(req) as Verdict, now: newCore(req) as Verdict };
  });
  const parts: Record<string, Json> = {};
  for (const part of ["all", ...new Set(picked.rows.map((r) => r.part))]) {
    const vs = verdicts.filter((v) => part === "all" || byId.get(v.a.id)?.part === part);
    parts[part] = { replies: vs.length, old: tally(vs.map((v) => v.old)), new: tally(vs.map((v) => v.now)) };
  }
  out[set] = {
    question: picked.question, rows: picked.rows.length, parts,
    flipped: verdicts.filter((v) => !v.old.ok && v.now.ok).map((v) => ({
      id: v.a.id, part: byId.get(v.a.id)?.part, label: byId.get(v.a.id)?.label, pick: v.now.answer?.pick,
      oldReason: v.old.failure?.detail })),
    rejectedNow: verdicts.filter((v) => v.old.ok && !v.now.ok).length,
  };
}

const arms: Record<string, Json> = {};
for (const set of ["d1", "d2"]) {
  const question = String((out[set] as { question: string }).question);
  const model = JSON.parse(String(newCore({ op: "oracle.request", name: question, names: [], state: {} }).bodyText)).model;
  for (const arm of ["haiku", "sonnet"]) {
    const file = `results/jev-arms-clean/${set}-${arm}.answers.jsonl`;
    const xs = readFileSync(file, "utf8").split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l) as
      { choice?: string; probabilities?: Json });
    const reqs = xs.filter((x) => x.probabilities !== undefined).map((x) => ({ op: "oracle.validate", name: question,
      reply: JSON.stringify({ model, answers: { [question]: { type: "choice", choice: x.choice,
        probabilities: x.probabilities } } }) }));
    const vs = reqs.map((r) => ({ old: oldCore(r) as Verdict, now: newCore(r) as Verdict }));
    arms[`${set}-${arm}`] = { file, answers: xs.length, withProbabilities: reqs.length,
      old: tally(vs.map((v) => v.old)), new: tally(vs.map((v) => v.now)),
      rejectedNow: vs.filter((v) => v.old.ok && !v.now.ok).length };
  }
}

process.stdout.write(JSON.stringify({ jev: out, claudeArms: arms }, null, 2) + "\n");
