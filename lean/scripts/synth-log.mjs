// A synthetic console event log (no real ids) for the fwcore query timing and golden check (task fwcore-query-speed).
// usage: node lean/scripts/synth-log.mjs <tasks> > synth.jsonl
// Shape: 8 milestones, a task graph with 1 to 3 deps on earlier tasks, write globs that overlap in 7 families, a device
// task in 20, labels and spawns for every task, stops for half, evidence for a third, hand-backs for a tenth.
const n = Number(process.argv[2] ?? 500);
let seq = 0;
let ts = 1_700_000_000_000;
const out = [];
const ev = (e) => out.push(JSON.stringify({ ...e, seq: ++seq, ts: (ts += 1000) }));
for (let m = 0; m < 8; m++) ev({ type: "milestone.define", key: `m:${m}`, actor: "lead", milestone: `M${m}`, title: `Milestone ${m}` });
for (let i = 0; i < n; i++) {
  const deps = [];
  if (i > 0) deps.push(`t${i - 1}`);
  if (i > 3 && i % 3 === 0) deps.push(`t${i - 4}`);
  if (i > 9 && i % 7 === 0) deps.push(`t${i - 10}`);
  const done = i % 3 === 0;
  ev({
    type: "task.define", key: `d:${i}`, actor: "lead", task: `t${i}`, title: `Task ${i}`, stream: `s${i % 5}`,
    milestone: `M${i % 8}`, deps, owner: "builder", writes: [`area${i % 7}/sub${i % 11}/**`, `docs/n${i}.md`],
    devices: i % 20 === 0 ? ["phone"] : [], evidence: done ? `abc${i}` : null,
  });
}
for (let i = 0; i < n; i++) {
  ev({ type: "agent.label", key: `lab:${i}`, actor: "hook", agent: `key${i}`, name: `t${i}` });
  ev({ type: "agent.spawn", key: `sp:${i}`, actor: "hook", agent: `key${i}` });
  ev({ type: "agent.spawn", key: `sp2:${i}`, actor: "hook", agent: `key${i}` });
  if (i % 2 === 0) ev({ type: "agent.stop", key: `st:${i}`, actor: "hook", agent: `key${i}` });
  if (i % 10 === 0) ev({ type: "task.handback", key: `hb:${i}`, actor: "lead", task: `t${i}`, agent: `key${i}`, tip: "abc1234" });
}
process.stdout.write(out.join("\n") + "\n");
