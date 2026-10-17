---
id: 2026-10-17-kickoff-06-architecture-and-tooling
kind: note
title: "v2 architecture: modular loop, cheap tool adoption, reference store, helper tools, git conventions"
status: review
created: 2026-10-17
authors: [agent:kickoff-architecture]
topics: [architecture, monorepo, caching, testing, knowledge-base, tooling, git]
supersedes: []
links:
  v1_repo: ../fastwork-com-web-optimize (read-only, at eae1bb99)
---

# v2 architecture and tooling (kickoff note 06)

Scope: the repo shape for v2, how the loop is split into small parts that you can test one at a time, how a new or
changed tool avoids "re-run everything", where research, references and results live, which helper tools to adopt,
and the git/worktree rules. Other kickoff notes cover engine math, Lean and the agent-team model/effort plan. This
note touches those topics only where they meet the architecture.

Status words: **CONFIRMED** means a doc, source file or release page was checked on 2026-10-17 and is cited.
**INFERRED** means it is my design reasoning or an unverified expectation. Old-repo paths are relative to
`../fastwork-com-web-optimize` at commit `eae1bb99`.

---

## 0. Answer first

1. **Why v1 was slow and fragile came down to four structural causes, not bad luck** (§1):
   - no module contracts, so any tooling change ran the full suite;
   - real time in tests (sleeps, lock backoff);
   - a result's identity did not include the tool's version, so changing a tool meant re-measuring and A/A runs;
   - one rulebook for every role.
2. **Monorepo: pnpm workspaces + Turborepo, Node 24, Vitest** (§2). Bun is fine locally but adds risk with
   Playwright, Vite and MUI and gains little. Nx is more than this project needs.
   - Layout: `apps/{site,console-web,console-api,runner}`, `packages/{contracts,core,stats,cost-model,parts,measure-sdk,measure-chromium,measure-webkit,artifact-store,kb}`, `lean/`.
3. **Functional core, adapters at the edge (hexagonal).** Every package below `measure-sdk` is pure: no fs, no
   browser, no clock. A dependency-cruiser rule enforces this mechanically.
   - Each measurement tool is a **plugin**: an id, a `semantics` version, zod input/output schemas, a list of ports
     it needs, and a lane (`counts` | `timing` | `device`).
4. **Tool adoption is cheap because of content-addressed measurement artifacts** (§3). Each artifact's key is
   `sha256(JCS({subject, tool, engine, profile, protocol}))`.
   - **subject** is the hash of the bytes the route actually serves, taken from the Vite build manifest, so a part
     that is not on a route cannot change that route's keys.
   - **tool** carries a `semantics` version, not a code hash. A golden-trace check in CI catches a refactor that
     silently changes a tool's output.
   - The planner that decides what to re-run is a pure function, and it is the first target for a Lean
     **soundness** proof ("every measurement whose inputs changed is re-run").
5. **Test layers** (§3.4):
   - L0: Lean.
   - L1: pure unit tests, no real time, under 20 s for the whole repo.
   - L2: contract tests.
   - L3: visual tests (Playwright).
   - L4: measurements, cached by artifact key.
   - L5: the device.

   `turbo run --affected` picks packages, and `vitest --changed` picks test files inside them. The pre-commit hook
   runs only L1 and L2 on affected packages.
6. **Knowledge store** (§4), in five separate parts, each with its own frontmatter schema and one indexer/linter
   (`pnpm kb`):
   - `research/` for our notes;
   - `refs/external/` for papers, articles and specs;
   - `refs/upstream/` for pinned engine source: a lock file, short excerpts, and gitignored sparse clones made by a
     script;
   - `snapshot/` for the Fastwork original, gitignored and local only;
   - `results/` for machine-readable experiments.
7. **Helper tools, a minimal set** (§5):
   - Playwright, Perfetto trace processor, lean-lsp-mcp, chrome-devtools-mcp (exploration only, usage statistics
     off), Serena (TS + Lean, navigation plus rename only), ast-grep, knip, dependency-cruiser, Biome, lefthook.
   - Not adopted: Nx, husky, Storybook (a harness route in the site does the job), heavy custom git guards.
8. **Git** (§6):
   - Keep linear history, no agent push, never commit the snapshot, and one lander.
   - Replace v1's 842-line `git-guard.mjs` and its full-suite pre-commit with repo git config, Claude Code deny
     rules and a ~40-line lefthook config.
   - Share the Turborepo cache and the artifact store across worktrees through the git common directory.

---

## 1. What v1 teaches (evidence)

| Observation | Evidence (old repo) | Status |
|---|---|---|
| The loop's engineering went into tools, not fixes: 224 of 266 incidents were bugs in our own tools; ~38k lines of tools, ~51k lines of tests | `research/loop-distillation/README.md` §1, §5 | CONFIRMED (repo note) |
| `npm test` took 250-280 s wall (~1,640 tests), and the pre-commit hook ran it on every tooling commit | `CLAUDE.md` "Tooling is guarded by tests"; `.githooks/pre-commit` (109 lines) | CONFIRMED |
| Of 143 s of summed test time, 75 s was two fake-Chrome files waiting on real `setTimeout` sleeps, not CPU | `research/architecture/tools-speed.md` §1.3 | CONFIRMED |
| Modules could not be imported by tests: `serve.mjs` ran at top level (top-level `await`), and `fix.mjs` validated `--on` at import time | `research/architecture/tools-refactor.md` §3 (`serve.mjs`, `fix.mjs` audits) | CONFIRMED |
| Duplicate code with different meanings: 8 argv parsers, two `median`s that disagree on even n, 3 JSON I/O copies, 4 `git()` wrappers | `tools-refactor.md` TL;DR, §3 | CONFIRMED |
| Any edit to measurement code (`verify.mjs`, `cdp.mjs`, `fix.mjs ab`) broke A/B comparability, so refactors were limited to "pure moves" plus an A/A run | `tools-refactor.md` §4; `CLAUDE.md` Hard rule 6 | CONFIRMED |
| Headless Chrome gave ~2.9x throughput for functional checks with 35-38 % less CPU, once UA and DSF were fixed | `research/architecture/headless-functional.md` §1 | CONFIRMED |
| Element-level counts carry over to the full page as an absolute delta; frame time does not | `research/architecture/isolated-measurement/README.md` (answer section) | CONFIRMED (repo note; OBSERVED data) |
| Every agent loaded a 9,467-word rulebook, ~8 % of cache reads by the lead's estimate | `loop-distillation/README.md` §6.2 | CONFIRMED (estimate in note) |
| Serena vs text search: equal accuracy, text cheaper (median 170k vs 202k tokens/run). Serena helped only for alias resolution and full-name reference lists. Its 0-based lines leaked into answers | `research/code-navigation-benchmark/README.md` headline + follow-up | CONFIRMED |
| Shared state was JSON files in `.git/fastwork-mirror/` written through about 10 separate tools, with no schema | `loop-distillation/README.md` L3 | CONFIRMED |
| `research/` grew to 53 MB and 1,154 files (125 `.md`). Notes and raw data were mixed, with no frontmatter or index; memory notes did have frontmatter | `du -sh research`, `find research`; `memory/read-source-first.md` head | CONFIRMED (counted 2026-10-17) |

**Root causes** (INFERRED from the evidence above):

- **R1, no seams.** Tools were CLIs with side effects at import time. Tests could only spawn them end to end, so
  the only safe gate was the full suite.
- **R2, time in tests.** Sleeps and lock backoff used the real clock, and there was no Clock port.
- **R3, results had no identity.** A result did not record which tool semantics produced it. A tool change
  therefore invalidated *everything*, and the protocol answered with A/A runs and "pure moves only".
- **R4, scarce devices became locks, and locks became code.** `lib/lock.mjs` alone is 1,685 lines (`wc -l tools/lib/lock.mjs`).
- **R5, rules per incident, loaded by everyone.**

v2 removes R1-R3 by design (§2-§3). R4 shrinks because most measurement moves to the counts lane, which needs no
quiet host (another kickoff note covers the engine math). R5 is handled with per-package `CLAUDE.md` files and a
short root file (§6.4).

---

## 2. Monorepo design

### 2.1 Package manager and task runner

| Option | For | Against | Verdict |
|---|---|---|---|
| **pnpm 10 workspaces** (local 10.34.5) | Strict `node_modules`, so no phantom deps (the old repo had none, but React/MUI apps will); content-addressed global store shared by every worktree; `catalog:` pins one version of React/MUI/zod for all packages; first-class in Turborepo | Slightly slower installs than bun | **Adopt** |
| bun workspaces (local 1.3.4) | Fast installs and test runner | `bun test` is not Vitest-compatible for browser-mode tests; Playwright, Vite and Lean tooling expect Node; two runtimes double the "which runtime ran this number" question in measurement | Use only as an optional local script runner, never for measurement or CI (INFERRED) |
| **Turborepo 2.11.x** (npm `turbo` 2.11.9) | One `turbo.json`; tasks hashed on declared `inputs`/`env`/`dependsOn`; `--affected`; `--summarize` explains cache misses; `--dry=json` lets the console show the plan | Package-level granularity only | **Adopt** |
| Nx 23.3 | Finer project graph, plugins, `nx affected` | More config and concepts for agents to read (read cost was a v1 problem, `tools-refactor.md` §2); plugin magic is harder to prove things about | Skip |

CONFIRMED (Turborepo `run` reference, https://turborepo.dev/docs/reference/run):

- `--affected` "Filter[s] to only packages that are affected by changes on the current branch". By default it is
  `--filter=...[main...HEAD]`, overridable with `TURBO_SCM_BASE`/`TURBO_SCM_HEAD`.
- With `futureFlags.affectedUsingTaskInputs`, it filters by each task's `inputs` globs.
- A too-shallow checkout makes every package count as changed.
- `--summarize` writes run JSON to `.turbo/runs`.
- `--dry=json` prints the plan without running it.

Runtime: Node 24 (local v24.14.0). Tool scripts are `.ts` files run with Node's built-in type stripping, so there is
no build step for scripts (INFERRED that this fits; check in the bootstrap spike).

TypeScript: npm `latest` is 7.0.2 (native port, published 2026-07-08); 6.0.3 is the last 6.x (CONFIRMED,
`npm view typescript time`). Many tools (knip, dependency-cruiser, typescript-eslint, Serena's TS server) use the
TypeScript JS API. Whether each one works with 7.x is **UNRESOLVED**. Proposal: pin `typescript@6.0.3` in the
catalog for tool compatibility, and try `tsgo`/7.x for `typecheck` only if the spike shows it works.

### 2.2 Layout

```
fastwork-com-web-optimize-lean/
├─ CLAUDE.md                     ≤1,500 words: hard rules, each with its enforcer; where to look
├─ .claude/                      settings.json (committed: env, permissions, hooks), agents/*.md
├─ .mcp.json                     project MCP servers (serena, lean-lsp, chrome-devtools, playwright)
├─ .serena/project.yml           languages: typescript, lean4 (§5.2)
├─ lefthook.yml                  git hooks (§6.2)
├─ turbo.json  pnpm-workspace.yaml  package.json  biome.json  .dependency-cruiser.cjs  knip.json
├─ apps/
│  ├─ site/                      React + MUI + Vite: the rewrite; part harness routes (/__harness/:part)
│  ├─ console-web/               React + shadcn/ui + Tailwind 4
│  ├─ console-api/               Hono on Node; SQLite; typed RPC; the only writer of shared state
│  └─ runner/                    CLI `fw`: plan | run | report | kb | src:fetch  (thin: wires adapters)
├─ packages/
│  ├─ contracts/                 zod schemas + generated JSON Schema + golden fixtures (leaf; no deps)
│  ├─ core/                      PURE: canonical JSON, artifact keys, planner, verdict rules, flag resolution
│  ├─ stats/                     PURE: medians (one definition), HL shift, Mann-Whitney, bootstrap
│  ├─ cost-model/                PURE: engine math (frame budget, layer bytes, tiling thresholds), versioned per engine
│  ├─ parts/                     part/flag registry types + React provider + resolver (uses core)
│  ├─ measure-sdk/               plugin interface, ports (Browser, TraceQuery, Clock, ArtifactStore, Lock)
│  ├─ measure-chromium/          adapters (Playwright/CDP, Perfetto) + plugins
│  ├─ measure-webkit/            adapters (Playwright WebKit, Safari Web Inspector/WIP) + plugins
│  ├─ artifact-store/            fs adapter for the content-addressed store
│  └─ kb/                        frontmatter schemas, indexer, linter for research/refs/results
├─ lean/                         Lake project: Spec/, Proofs/, Oracle (lean_exe), tests (lake test)
├─ research/  refs/  results/    knowledge store (§4)
├─ snapshot/                     GITIGNORED: Fastwork original, local only (§4.5)
└─ .cache/                       GITIGNORED: upstream sparse clones, raw trace blobs, kb index
```

### 2.3 Dependency rules (layers)

```
apps/*  ──►  measure-chromium / measure-webkit / artifact-store / kb  ──►  measure-sdk  ──►  core, stats, cost-model, parts  ──►  contracts
                                                                                                 ▲
lean/  ── reads contracts/fixtures, emits oracle answers (JSON) ─────────────────────────────────┘
```

- **Pure zone:** `contracts`, `core`, `stats`, `cost-model` and the non-React part of `parts` must not import
  `node:*`, `playwright*`, `fs`, `child_process`, `Date.now`, `setTimeout` or `Math.random`. Time and randomness come
  in as parameters.
  - Enforced by dependency-cruiser `forbidden` rules (imports) and ast-grep rules (globals).
  - INFERRED: this is the single most important rule against R1/R2. Pure code is what Lean can specify and what
    Vitest can run in milliseconds.
- **No app imports another app. No package imports an app.** This is a dependency-cruiser rule.
- **Ports & adapters** (hexagonal; Cockburn, https://alistair.cockburn.us/hexagonal-architecture/; "functional
  core, imperative shell", Bernhardt, https://www.destroyallsoftware.com/screencasts/catalog/functional-core-imperative-shell):
  - `measure-sdk` defines ports as TS interfaces.
  - Each adapter package implements them.
  - Every port has a **fake** adapter in `measure-sdk/testing` that replays recorded traces, so plugins are
    unit-tested without a browser.
- **Size guard** (from `tools-refactor.md` §2 M3): files over 300 lines or functions over 40 lines fail lint in the
  pure zone, and warn elsewhere. Each package README opens with the v1 "contract header" idea (`tools-refactor.md`
  §5.1): purpose, used-by, contract, invariants.

### 2.4 Measurement plugin contract

INFERRED design. The shape is what matters; the names are proposals.

```ts
// packages/measure-sdk/src/plugin.ts
export interface MeasurePlugin<I extends z.ZodType, O extends z.ZodType> {
  id: `${'chromium' | 'webkit' | 'any'}.${string}`;   // e.g. "chromium.trace-counts"
  semantics: number;            // bump when the meaning of the output changes (§3.2)
  lane: 'counts' | 'timing' | 'device';  // counts: parallel, headless, cacheable; timing: lock + samples; device: phone/user
  input: I;  output: O;         // zod; JSON Schema generated into contracts/schemas/
  needs: readonly PortName[];   // e.g. ['browser.chromium', 'traceQuery', 'clock']
  run(input: z.infer<I>, ports: Ports): Promise<z.infer<O>>;   // impure shell, thin
  reduce?(raw: unknown): z.infer<O>;                            // pure; most logic lives here, unit-tested
}
```

- The runner validates input before `run` and output after it. An output that fails its own schema is a tool
  incident, never a result.
- A plugin is registered in the runner's static table. There is no dynamic loading, so knip and dependency-cruiser
  can see it.
- `lane` decides scheduling:
  - `counts` runs N-way parallel in headless (v1 `headless-functional.md` showed it is valid for counts once UA and
    DSF are fixed);
  - `timing` takes the single quiet-host lock;
  - `device` produces a console step for the user.

### 2.5 Contracts across TS and Lean

- **The source of truth is zod in `packages/contracts`.** `z.toJSONSchema()` (CONFIRMED, https://zod.dev/json-schema,
  Draft 2020-12 default) generates `contracts/schemas/*.json`, which is committed so diffs are reviewable.
  `z.fromJSONSchema()` is experimental (CONFIRMED, same page), so we never round-trip in that direction.
- **Lean side:** hand-written `structure`s with `deriving ToJson, FromJson` (Lean core
  `src/Lean/Data/Json/FromToJson.lean`, CONFIRMED to exist). They mirror only the types Lean reasons about: artifact
  key inputs, planner input/output, verdict input/output, flag sets and the console state machine.
- **Contract test** (L2): `contracts/fixtures/*.json` are golden examples, and each one must survive two round trips:
  - TS `schema.parse` → `JSON.stringify` (canonical) must be byte-equal to the input;
  - `lake exe oracle decode-encode` must also be byte-equal.

  Drift between zod and Lean fails CI.
- **Differential (oracle) tests:** fast-check (npm 4.10.2) generates inputs. The TS `core` function and the compiled
  Lean reference (`lake exe oracle <fn>` over JSON lines) must agree.
  - Lean *proves* properties of its reference implementation.
  - The differential test ties the shipped TS to that proven reference.
  - INFERRED: this is the cheapest honest way to make "provable" reach production TS code. Lean code does not run in
    the browser or the console backend.
- Lake has first-class `lake test` / `lake lint` drivers (`testDriver`, `lintDriver`, CONFIRMED in
  `src/lake/README.md` of leanprover/lean4), so Lean fits the same `turbo run test` call through a thin
  `lean/package.json` wrapper.
  - Lean 4 latest stable: v4.35.0 (2026-10-12, CONFIRMED GitHub releases). The pin goes in `lean/lean-toolchain`.

---

## 3. Making tool adoption cheap

### 3.1 Content-addressed measurement artifacts

**Key** (INFERRED design):

```
artifactKey = sha256( JCS({
  v: "fw.measure.key/1",
  subject:  { route, partSet: [{part, variant}] (sorted), servedHash },   // servedHash: see below
  tool:     { plugin: "chromium.trace-counts", semantics: 3 },
  engine:   { name: "chromium", version: "<exact build>", flags: [...sorted] },
  profile:  { id: "iphone15pm-portrait", viewport, dpr, cpuThrottle, input: "<scroll script hash>" },
  protocol: { runs, warmup, seed }
}))
```

- **JCS** is RFC 8785 JSON Canonicalization (https://www.rfc-editor.org/rfc/rfc8785). It makes the key independent
  of key order and number formatting. INFERRED: this is a good first Lean target, since canonicalization is
  deterministic and injective on the schema's value space.
- **`servedHash` = hash over the sorted content hashes of every file the route can load.** These are the route's
  entry chunk, its static imports, its CSS and its assets, as listed in Vite's `build.manifest`. The manifest lists
  `file`, `imports`, `dynamicImports`, `css` and `assets` per entry (CONFIRMED, https://vite.dev/guide/backend-integration).
  - Consequence: editing part A changes the keys of every route that serves A's bytes (the full page and A's harness
    route), and of no other route. Unaffected harness measurements are cache hits with no git-diff reasoning.
  - Dynamic imports are included conservatively (INFERRED: this over-invalidates and never under-invalidates).
- **`tool.semantics`, not the code hash.** Refactoring a plugin must not invalidate its cache, and changing what it
  measures must. A golden check (§3.2) tells the two apart mechanically. This replaces v1's "pure moves only + A/A"
  rule (`tools-refactor.md` §4).
- **`engine.version` is the exact browser build.** Playwright pins its browser builds per release, which gives a
  stable Chromium/WebKit identity (Playwright 1.64.1 on npm, CONFIRMED). For Safari on a device, it is the iOS +
  Safari build.

**Store** (INFERRED):

```
<git-common-dir>/fw/artifacts/ab/cd/<key>/
  manifest.json      # key inputs (verbatim), plugin output (schema-validated), created, host snapshot, runner commit
  raw/               # traces (.pftrace/.json.gz), screenshots — never committed
results/index/       # committed: one small JSON line per accepted artifact (key, plugin, subject, summary)
```

- The store sits in the **git common directory**, so all worktrees share it, as v1's shared state did
  (`loop-distillation` L3). Writes are atomic (write to a temp file, then rename). Artifacts are immutable, so
  concurrent writers of the same key are harmless: the last rename wins with identical meaning.
- **Counts-lane artifacts are reused as they are.** Timing-lane artifacts hold samples, so a re-run *appends*
  samples under the same key instead of replacing them, and the verdict reads all of them. The host-load snapshot
  stays in the manifest so a gate can drop contaminated samples (v1 I-017 lesson,
  `postmortem-2026-09-30-overload.md`).
- `fw plan` is pure. It takes `(requested measurements, store index)` and returns `{hits, todo}`. The console shows
  the plan (`turbo --dry=json` for builds, `fw plan --json` for measurements) before anything runs.

**Why not use Turborepo's cache for measurements?** Turbo caches one output per (package, task) keyed on files and
env. Measurements form a matrix (parts × variants × engines × profiles), depend on non-file inputs (browser build,
device), and the timing lane must append samples. INFERRED: the right split is turbo for build/test and the artifact
store for measurement, with `fw plan` running as an uncached turbo task.

### 3.2 Changing a tool safely: the golden-semantics gate

Each plugin ships `fixtures/` with recorded raw inputs (a small Chromium trace, a WebKit timeline export) and the
expected `reduce()` output.

| Change to a plugin | Golden output | `semantics` bumped? | CI result | Cache effect |
|---|---|---|---|---|
| Refactor | same | no | pass | all artifacts stay valid |
| Behaviour change | differs | no | **fail**: "output changed; bump semantics or revert" | none |
| Behaviour change | differs | yes | pass; fixtures updated in the same commit | only this plugin's artifacts become stale; `fw plan` lists exactly them |
| New plugin | n/a | starts at 1 | pass | nothing else re-runs |

This turns v1's prose Hard rule 6 ("call out measurement-code changes") into a mechanism, which follows principle 3
in `loop-distillation/README.md` §1. INFERRED.

### 3.3 What invalidates what

| Change | Turbo re-runs | Measurements re-run |
|---|---|---|
| A part's source (e.g. `apps/site/src/parts/hero/*`) | `site` build/typecheck/unit, `site` visual tests for that part | every route whose `servedHash` changed: the hero harness, plus full-page routes that include hero |
| A flag default only | `site` unit | routes whose `partSet` changed |
| `packages/stats` | stats + every dependant's unit tests | none (verdicts are recomputed from stored samples, which is pure and cheap) |
| `cost-model` constants | cost-model + dependants | none: the model is applied to stored counts at report time |
| A plugin refactor | that plugin's tests + golden | none |
| A plugin semantics bump | same | that plugin's artifacts only |
| Browser upgrade (Playwright bump) | measure-* tests | everything on that engine. That is correct; it is a new instrument. Old artifacts stay for comparison |
| `research/`, `refs/` | `kb lint` only | none |

### 3.4 Test layers

| Layer | What | Tool | Budget | When |
|---|---|---|---|---|
| L0 | Lean proofs + `lake test` | Lake | cached by Lake's own build trace | pre-land, CI; locally when `lean/` is affected |
| L1 | Pure unit + property tests (fast-check) | Vitest 5 (npm 5.0.5), `projects` per package | whole repo < 20 s cold, ~1 s on turbo cache hit | pre-commit (affected) |
| L2 | Contract tests: zod ⇄ JSON Schema ⇄ Lean round-trip; port fakes vs adapter contract suite; console API schema | Vitest + `lake exe oracle` | < 30 s | pre-commit (affected) |
| L3 | Visual parity of parts against the reference screenshots; component behaviour | Playwright test (`toHaveScreenshot`, animations frozen) | per part < 10 s | pre-land, affected parts only |
| L4 | Measurement plugins on real engines | `fw run` (counts lane in parallel headless; timing lane under lock) | cache hit = 0 | on demand / pre-land for touched parts |
| L5 | Device (iPhone Safari) + user's finger | console steps | rare | milestone gates only |

Rules (INFERRED, each with its enforcer):

- **No real time below L3.** `Clock` is a port. Vitest fake timers are allowed. Enforced by an ast-grep rule
  banning `setTimeout`, `setInterval`, `Date.now`, `performance.now` and `new Date()` in the pure zone, and by a
  Vitest per-test timeout of 2 s in L1. This directly removes the v1 cost in `tools-speed.md` §1.3.
- **Test selection:** `turbo run test:unit test:contract --affected` picks packages. Inside a package,
  `vitest --changed` uses git plus the module graph (CONFIRMED in the Vitest CLI docs: "Run tests that are affected
  by the changed files"; `--related` works with static imports only). The lander still runs the full affected set
  on the rebased commit.
- **Contract suites for ports.** Each port has one shared test suite. The fake adapter and the real adapter both
  run it: the fake in L1, the real one in L4. A fake that drifts from reality fails the real adapter's run of the
  same suite. INFERRED: this is what makes fakes trustworthy enough to keep L1 fast.

---

## 4. The knowledge store

### 4.1 Layout

```
research/                    OUR notes. One file per note.
  kickoff/NN-<slug>.md       (this round; kept as-is)
  notes/YYYY/MM-DD-<slug>.md general research notes
  decisions/YYYY-MM-DD-<slug>.md   ADR-style decisions (context, options, decision, enforcer)
  INDEX.md                   GENERATED by `pnpm kb index` (not hand-edited; see 4.4)
refs/
  external/<slug>.md         one per paper / article / spec / talk / doc page: metadata + link + our short notes
  upstream/
    sources.lock.yaml        pinned repos: name, url, commit, date, sparse paths, license
    excerpts/<repo>/<path>@<sha7>#L<a>-L<b>.md    ≤ 40 lines, permalink, why it matters
  v1/<slug>.md               pointers into the old repo (path + commit + summary); never copies
results/
  experiments/<date>-<slug>/ card.md (pre-registered reading) + result.json (schema-validated)
  index/*.jsonl              committed artifact index lines (§3.1)
snapshot/                    GITIGNORED — Fastwork original (4.5)
.cache/upstream/<repo>@<sha7>/   GITIGNORED — sparse blobless clones made by `fw src:fetch`
.cache/artifacts -> <git-common-dir>/fw/artifacts   GITIGNORED symlink for convenience
```

### 4.2 Frontmatter schema (zod in `packages/kb`, validated by `pnpm kb lint`)

```yaml
id: 2026-10-17-webkit-style-difference      # date + slug: collision-free across parallel worktrees
kind: note | decision | ref | source-excerpt | experiment | v1-pointer
title: "…"
status: draft | review | accepted | superseded | archived       # notes/decisions
created: 2026-10-17
updated: 2026-10-17
authors: [agent:<role>-<topic>, user]
topics: [measurement, webkit, compositor]  # controlled vocabulary in packages/kb/topics.ts
engines: [webkit, chromium]                # optional
parts: [hero, nav]                         # optional; must exist in the part registry
supersedes: [<id>]                         # optional
links: { refs: [<id>], sources: [<id>], experiments: [<id>], v1: [<id>] }
# kind-specific:
url: https://…            # ref
accessed: 2026-10-17      # ref
license: "BSD-2-Clause"   # ref, source-excerpt
repo: webkit  commit: ea4cc38efe  path: Source/WebCore/style/StyleDifference.cpp  lines: [210, 212]   # source-excerpt
claims: [{ text: "…", status: CONFIRMED | OBSERVED | INFERRED | UNRESOLVED | REFUTED, cite: "<id or url>" }]   # optional, notes
```

- **IDs are `date-slug`, not counters.** v1 allocated incident and thread numbers from shared state in the git
  common dir (`loop-distillation` L3). Two worktrees adding "N-0007" on separate branches would collide at rebase.
  A date-slug never does. INFERRED.
- **Claim status words** keep v1's vocabulary (CONFIRMED / OBSERVED / UNRESOLVED / REFUTED; `CLAUDE.md` "Platform
  claims", `memory/verify-platform-claims.md`) and add INFERRED for design reasoning.

### 4.3 Upstream source references

- `fw src:fetch webkit` reads `refs/upstream/sources.lock.yaml` and runs a **shallow, blobless, sparse** clone at the
  pinned commit into `.cache/upstream/webkit@<sha7>/`.
  - v1 did this by hand for 6 repos at 278 MB in total (`research/tooling-landscape/README.md`, "Files read from
    cloned source"). That shows the approach works and is small.
  - Single files can come from `gh api` (v1 `memory/github-via-gh.md`).
- **Only excerpts are committed**: ≤ 40 lines with the license header noted, a permalink
  (`https://github.com/WebKit/WebKit/blob/<sha>/<path>#L210-L212`) and a "why" paragraph.
  - WebKit (BSD/LGPL files), Chromium (BSD) and Lean (Apache-2.0) are open source. Short attributed excerpts for
    research are low-risk.
  - INFERRED, not legal advice. The `license` field makes it auditable.
- **Version tags are mandatory.** The v1 landscape found WebKit rules that differ between iOS 26 and WebKit main
  (`tooling-landscape` §5 rules 10-11). An excerpt without a commit is rejected by `kb lint`.
- `refs/v1/` holds pointers into the old repo with its commit (`eae1bb99`). The v1 repo is the user's own, but
  pointers keep the two studies distinct, and v1 text that quotes Fastwork code never gets copied.

### 4.4 Index and search for agents

`pnpm kb index` walks `research/`, `refs/` and `results/` and writes two things:

- **`research/INDEX.md`**: one table per kind (id, title, status, topics, updated).
- **`.cache/kb.json`**: the full graph (nodes plus `links`).

`pnpm kb find --topic webkit --status accepted --kind source-excerpt` prints matching ids and titles, ~1 line each.
INFERRED: this gives agents a cheap, exact lookup instead of grepping 1,000+ files, which was the v1 shape.

`pnpm kb lint` runs in L1 and checks:

- schema validity;
- unique ids;
- every `links` target exists;
- every `parts` value exists in the registry;
- every source-excerpt has a commit and a line range;
- no file under `research/` or `refs/` larger than 200 kB (raw data belongs in `results/` or `.cache/`).

`INDEX.md` is generated on demand and by the lander after landing. It is not hand-edited, which avoids rebase
conflicts between worktrees (INFERRED). The console API can serve `kb.json` for a "Library" tab.

v1's benchmark says agents ignore optional maps (`code-navigation-benchmark/README.md` b5: "Offered: 0 of 8 helpers
read them"). So `kb find` must be named in the per-role `CLAUDE.md` as *the* way to look things up, and the index
must be small.

### 4.5 The Fastwork original snapshot

- It lives in `snapshot/`, which is gitignored, and is pinned by `snapshot.lock.json` (committed: id, tree hash,
  capture date, source URL; no content).
  - This keeps v1's baseline-pin idea (`loop-distillation` L1) without committing third-party property.
  - v1 itself moved `site/` and `site-pretty/` out of git on 2026-10-13 (`CLAUDE.md` Hard rule 3; old `.gitignore`).
- **Uses:**
  - L3 visual-parity reference screenshots, generated locally from the snapshot and stored in the artifact store,
    not git;
  - side-by-side "original vs rewrite" measurement routes served by the runner.
- **Guards:**
  - `.gitignore`;
  - a lefthook pre-commit glob that refuses `snapshot/**`;
  - Serena `ignored_paths`;
  - a `kb lint` rule that refuses any excerpt whose `repo` is the snapshot.

---

## 5. Helper tools (minimal set)

### 5.1 Adopt

| Tool | Version checked | Why | Config / caveat | Status |
|---|---|---|---|---|
| **Playwright** (`@playwright/test`) | 1.64.1 | Drives Chromium and WebKit with pinned builds; screenshot tests with frozen animations; traces | Its WebKit is not iOS Safari, and tracing/CDP are Chromium-only (v1 `tooling-landscape` §2.3, CONFIRMED there from playwright.dev/docs/browsers) | CONFIRMED |
| **Perfetto trace processor** | v58.2 (2026-08-24); PyPI `perfetto` 0.58.2 | SQL over Chrome traces; stdlib `chrome_scrolls_v4`, `scroll_jank_v4`, `event_latency` | Run via `uvx`/`uv` (uv is installed) or a pinned `trace_processor_shell` behind the `TraceQuery` port; pin in `sources.lock.yaml` | CONFIRMED (GitHub release, PyPI; stdlib files per v1 `tooling-landscape` §2.2) |
| **lean-lsp-mcp** | v0.31.0 (2026-09-30) | Gives agents proof state and diagnostics: `lean_goal`, `lean_diagnostic_messages`, `lean_hover_info`, `lean_build`, `lean_verify`, `lean_local_search`, plus remote search (`lean_leansearch`, `lean_loogle`, `lean_leanfinder`) | Needs `uv` and a built Lake project first. `LEAN_MCP_DISABLED_TOOLS` can switch off `lean_run_code` / remote search. The README warns of filesystem and network access | CONFIRMED (repo README, docs/tools.md) |
| **chrome-devtools-mcp** | 1.11.0 | Interactive exploration: snapshots, CSS, console, Lighthouse, ad-hoc traces | **Usage statistics are on by default**: pass `--no-usage-statistics` (CONFIRMED README), per v1 Hard rule 12. Use `--isolated`. Its numbers never count as results: results come only from `fw run`. v1 denied its perf traces because they hung for ~1 h and ignored the lock (`CLAUDE.md` Hard rule 8) | CONFIRMED |
| **Serena** | v2.0.0 (2026-10-13) | Symbol navigation in TS and Lean; cross-package rename | See §5.2 | CONFIRMED |
| **ast-grep** (`@ast-grep/cli`, devDependency, no global install) | 0.51.0 | Structural lint rules: pure-zone globals, "no layout read inside rAF/scroll callbacks" in parts (v1 lesson 1), "MUI `sx` must not animate layout props" | Rules in `rules/*.yml`, run in L1 | CONFIRMED (npm) |
| **knip** | 6.41.0 | Unused files, exports and deps across the workspace. Keeps read cost down after refactors | Uses the TS API (see the TS 7 risk, §2.1) | CONFIRMED (npm) |
| **dependency-cruiser** | 18.6.0 | Enforces the layer rules in §2.3 | `.dependency-cruiser.cjs`; L1 | CONFIRMED (npm) |
| **Biome** | 2.5.15 | One fast formatter and linter for TS/JSON; fewer configs than ESLint+Prettier | Keep stylelint only if CSS files appear. MUI styles are mostly in JS, so ast-grep carries the CSS-in-JS perf rules | CONFIRMED (npm); fit INFERRED |
| **lefthook** | 2.2.2 | Committed, parallel git hooks, one YAML file; replaces `.githooks/` + `npm run setup` | `lefthook install` once per clone | CONFIRMED (npm) |
| **fast-check** | 4.10.2 | Property tests in L1; inputs for Lean differential tests | | CONFIRMED (npm) |

### 5.2 Serena: configuration and the read-only vs editing tradeoff

- **Current state of the new repo:** `.serena/project.yml` has `language_servers: []`, `read_only: false` and
  `ignore_all_files_in_gitignore: true` (read 2026-10-17). It indexes nothing yet.
- **Proposed settings:**
  - `language_servers: [typescript, lean4]`;
  - `ignored_paths: [snapshot/, .cache/, results/, "**/dist/", "**/.turbo/", lean/.lake/]`.
- **Serena's `lean4` server** runs `lean --server` and takes `LEAN_PATH` from `lake env`. It raises an error if
  `lean` is not on PATH (CONFIRMED, `src/solidlsp/language_servers/lean4_language_server.py` in oraios/serena).
  - elan is not installed here, so the Lean server will fail until the user installs elan.
  - lean-lsp-mcp covers Lean better anyway (proof goals). Serena's Lean value is only symbol navigation.
- **Serena v2.0.0 changes:**
  - the app is now GPL-3.0-or-later (SolidLSP stays MIT);
  - a REPL interface was added;
  - since the latest changelog, the project's own `node_modules/typescript` tsserver loads only in **trusted**
    projects.

  All three are CONFIRMED (CHANGELOG.md, oraios/serena). No impact on us beyond trusting the project, since we
  don't redistribute Serena (INFERRED).
- **v1 tradeoff.** Read-only was right in v1 because Serena edits would bypass the overlay rules (`CLAUDE.md` Hard
  rule 11), and text search was cheaper (`code-navigation-benchmark`).
- **In v2 there are no overlays.** The React code is our own, typed, multi-package TypeScript, which is exactly
  where an LSP's `rename_symbol` and `find_referencing_symbols` beat grep (renames across packages, re-exports).
  INFERRED.
- **Recommendation:**
  - allow `find_symbol`, `find_referencing_symbols`, `find_declaration`, `get_symbols_overview`,
    `get_diagnostics_for_file` and **`rename_symbol`**;
  - keep `replace_symbol_body`, `insert_*`, `replace_content`, `replace_in_files`, `safe_delete_symbol` and memory
    writes excluded. The Edit tool shows a diff and goes through Claude Code permissions. Memories belong in the kb,
    not in `.serena/memories/`.
  - Keep text search as the default navigation (v1 data). The per-role `CLAUDE.md` names the two cases where Serena
    pays: alias resolution and all references.
  - Remind agents that Serena's line numbers are 0-based (v1's most common error).

### 5.3 Not adopted (and why)

| Tool | Reason |
|---|---|
| Nx | §2.1: more surface than turbo for no needed feature |
| husky | lefthook does the same with one file and parallel jobs |
| Storybook / Ladle | The site's `/__harness/:part?variant=…` route gives part isolation *in the real app build*. That route is what measurements need anyway, because Storybook's iframe and decorators would change what is measured (INFERRED). Revisit if designers need it |
| A custom 800-line shell-command parser hook (v1 `git-guard.mjs`) | §6: deny rules + git config + small hooks cover the same rules; the parser was itself code with gaps (`loop-distillation` §6.3) |
| Lighthouse CI (`@lhci/cli`) | v1 found it lags Lighthouse 13 and is navigation-oriented (`tooling-landscape` §2.2). Use Lighthouse user flows from a plugin if needed |
| A static per-property ms table | v1: costs are conditional and engine-version dependent (`tooling-landscape` §6 "Not worth building"). The cost-model package instead encodes *conditions with source citations*, versioned per engine |

---

## 6. Git, branching and worktrees

### 6.1 Rules kept, and their v2 enforcer

| Rule (v1 source) | v1 enforcer | v2 enforcer (proposal) | Keep? |
|---|---|---|---|
| Rebase + fast-forward only; 0 merge commits (`CLAUDE.md` HR1) | 5 git hooks + 842-line git-guard + deny rules | repo config `merge.ff=only`, `pull.rebase=true`; lefthook `pre-merge-commit` refuses; deny `Bash(git merge --no-ff*)`, `Bash(git merge --squash*)` | Keep (cheap; v1 record: 0 merges in 2,483) |
| Agents never push (HR2) | deny rules + git-guard + `pre-push` scrub | deny `Bash(git push*)`, `Bash(git -C * push*)`, `Bash(gh repo create*)`, `Bash(gh release*)`, `Bash(gh pr create*)`; lefthook `pre-push` runs the scrub check (for the user's own push) | Keep |
| Never commit third-party or secret files (HR3) | gitignore + pre-commit + scope guard | gitignore + lefthook pre-commit glob refuse (`snapshot/**`, `.cache/**`, `*.pem`, raw traces); deny `Bash(git add -f*)` | Keep |
| Personal data stays local (HR12) | convention | lefthook pre-commit + pre-push scrub (regexes for emails, LAN IPs, device ids, from a gitignored known-values file); `--no-usage-statistics` on MCPs | Keep, now enforced |
| Tooling guarded by tests (HR6) | full `npm test` on every tooling commit (250-280 s) | pre-commit: `turbo run lint typecheck test:unit test:contract --affected` (target < 30 s); the lander runs `turbo run test --affected` + `lake build` + golden-semantics on the rebased commit | Keep, much cheaper |
| Measure only under the lock (HR7) | `chrome-measure` lock, 1,685-line lib | the runner takes a lock only for `lane: timing`; counts run headless in parallel. The lock is one small module whose state machine is specified in Lean (no two holders; a dead holder is reclaimed) | Keep, smaller |
| Long foreground commands make agents deaf (fg-guard) | 230-line PreToolUse hook | a ~30-line hook that only asks for `run_in_background` on known long commands (`fw run`, `pnpm build`, cold `lake build`) | Keep, small (INFERRED; check whether current Claude Code makes it unnecessary) |
| Serena read-only (HR11) | project.yml + deny | §5.2: navigation + rename only | Changed |
| Baseline pin and exit-3 refusals (HR3/4) | 4 tools refuse | `snapshot.lock.json` checked by the runner only for snapshot routes. The rewrite is pinned by its own git commit plus `servedHash` | Simplified |

### 6.2 lefthook sketch (INFERRED)

```yaml
pre-commit:
  parallel: true
  commands:
    forbidden-paths: { run: node scripts/forbid-paths.ts {staged_files} }
    scrub:           { run: node scripts/scrub.ts {staged_files} }
    fast-tests:      { run: pnpm turbo run lint typecheck test:unit test:contract --affected --output-logs=errors-only }
pre-merge-commit:
  commands: { refuse: { run: "echo 'merge commits are refused: rebase + ff-only' && exit 1" } }
pre-push:
  commands: { scrub-range: { run: node scripts/scrub.ts --range '@{push}..HEAD' } }
```

### 6.3 Worktrees for parallel agents

- **Naming:** `.claude/worktrees/<role>-<topic>/` on branch `<role>/<topic>`. One string serves as the name for
  messages, lock owner, console author and status (v1 `loop-distillation` §6.4, "Names are the nervous system").
- **Teammates never call `EnterWorktree`.** In a team it switches the whole session (v1 I-272, `CLAUDE.md` "Parallel
  agents"). The lead creates the worktree, and the teammate uses absolute paths.
  - CONFIRMED from current docs: teammates load the project `CLAUDE.md`, MCP servers and skills, but not the lead's
    history.
  - CONFIRMED: from a subagent definition they get `tools`, `model`, and for in-process teammates `effort`.
  - CONFIRMED: there are no nested teams.

  Source: https://code.claude.com/docs/en/agent-teams.
- **One owner per package directory at a time.** The docs warn that two teammates editing one file overwrite each
  other (same page). Package boundaries make ownership mechanical: a teammate's brief names its packages, and a
  `TaskCompleted` hook can refuse completion if the branch touched packages outside the brief. The hook exists per
  docs (CONFIRMED); using it this way is INFERRED.
- **Shared caches across worktrees:**
  - The pnpm store is global by design.
  - Turborepo local cache: point `cacheDir` / `TURBO_CACHE_DIR` at `<git-common-dir>/fw/turbo-cache` so a package
    built in one worktree is a hit in the others. INFERRED: verify the option name and absolute-path support in the
    spike.
  - The artifact store lives at `<git-common-dir>/fw/artifacts` (§3.1).
- **One lander (the lead):** `git rebase main` on the branch, run the affected suite, then `git merge --ff-only` in
  the main checkout. Docs-only (`research/**`, `refs/**`) can be landed by any role after `kb lint`, which keeps
  v1's mgmt-ops shortcut as a rule rather than a role.
- **`worktree.baseRef: "head"`** stays (v1 `.claude/settings.json`): commit tooling before spawning, because a
  worktree only has committed files.

### 6.4 Rulebook shape (against R5)

- Root `CLAUDE.md` ≤ 1,500 words. It holds the hard rules with an "Enforced:" line each, the trust boundary,
  `kb find`, and the lanes. This matches v1's own recommendation (`loop-distillation` §6.6 point 2).
- Each `apps/*/CLAUDE.md` and `packages/*/CLAUDE.md` holds that package's contract and test command. INFERRED, to be
  confirmed in the spike: Claude Code loads subdirectory `CLAUDE.md` files when it works in that directory, so
  per-package rules reach only agents who touch that package.
- Lock and lane fine print lives in `fw --help`, not in any `CLAUDE.md` (v1 §6.6).
- Meta-rule: a new rule must remove or merge an old one, or explain why it can't (v1 §7).

---

## 7. Bootstrap order (proposal for the plan architect)

| Step | Deliverable | Proves |
|---|---|---|
| S0 (½ day) | pnpm + turbo + Biome + dependency-cruiser + knip + lefthook + `.claude/settings.json` + root `CLAUDE.md` + `packages/contracts`, `core` (JCS, artifact key), `kb` (schema, index, lint) | the gates run in < 30 s; kb lint passes on the kickoff notes |
| S1 (1 day; **needs the user to install elan**) | `lean/` Lake project: `Spec.ArtifactKey`, `Spec.Planner` with the soundness theorem, `oracle` exe; fast-check differential test against `core` | the TS ⇄ Lean contract loop works end to end |
| S2 | `apps/site` skeleton (Vite + MUI), `packages/parts` registry, one part + harness route; L3 parity test against the local snapshot | part isolation and `servedHash` from the Vite manifest |
| S3 | `measure-sdk` + `measure-chromium` counts plugin (Playwright trace → Perfetto SQL) + `artifact-store`; golden fixtures | cache hits on an unchanged part; only the changed part re-runs |
| S4 | `console-api` (Hono + SQLite) + `console-web` (shadcn): plan view, results, kb library, user steps | one writer of shared state |
| S5 | `measure-webkit` (Playwright WebKit counts; Safari Web Inspector path for device) | second engine through the same port |

---

## 8. Risks

- **The TS 7 / tool API mismatch** could break knip, dependency-cruiser or Serena's TS server (UNRESOLVED; pin 6.0.3).
- **`servedHash` misses runtime-fetched assets** (fonts, images loaded by URL in JS), so the key under-invalidates.
  Mitigations:
  - the site may load assets only through Vite imports (an ast-grep rule);
  - the runner records every network request per run and refuses a result whose set of requests contains a URL
    that is not in the manifest closure (INFERRED).
- **Golden fixtures rot.** A golden set that does not exercise a code path lets a semantics change through. Each
  plugin needs coverage of `reduce()` ≥ 90 % plus fixtures from both an original-snapshot run and a rewrite run.
- **Lean proofs about a model, not the shipped code.** The differential test is the only bridge, so it must run in L2
  on every `core` change, not nightly.
- **Over-engineering before the first measurement.** v1's day 1 was 38 % process commits (`loop-distillation` §5).
  S0-S3 should finish before any console polish.
- **Shared caches in the git common dir are invisible to the git hooks and to backups.** Document `fw cache prune`
  and size caps (v1 hit a full disk, I-095, `loop-distillation` §2).

## 9. Open questions for the user

1. May the user install **elan** (Lean toolchain manager, user-level) and **uv** stays as-is? Lean, lean-lsp-mcp and
   Serena's lean4 server all need `lean`/`lake` on PATH.
2. Should **raw traces** ever be committed (e.g. via git LFS), or only manifests and summaries, with raw files local?
   This note assumes local only.
3. Should Serena's **`rename_symbol`** be enabled (v2 recommendation), or should it stay fully read-only as in v1?
4. Will this repo be **public** like v1 (`kitimark/loop-engineer-the-fastwork-web-optimize`)? That decides how strict
   the pre-push scrub and the excerpt-license checks must be.
5. Should lean-lsp-mcp's **remote search tools** (LeanSearch, Loogle, LeanFinder: queries leave the machine) be
   enabled? They are on by default.
6. pnpm + Turborepo over bun: confirm. Bun stays available as an optional local script runner only.

## Sources

- Old repo (read-only, `eae1bb99`):
  - `research/architecture/tools-refactor.md`, `tools-speed.md`, `automated-benchmarks.md` §0,
    `headless-functional.md` §1, `isolated-measurement/README.md`, `postmortem-2026-09-30-overload.md` §1;
  - `research/loop-distillation/README.md`, `research/tooling-landscape/README.md`,
    `research/code-navigation-benchmark/README.md`;
  - `CLAUDE.md` (Hard rules, Tooling, Parallel agents, Serena), `.claude/settings.json`, `.claude/hooks/*`,
    `.githooks/*`, `.serena/project.yml`, `.gitignore`, `package.json`, `memory/README.md`; line counts via `wc -l`.
- Turborepo run reference: https://turborepo.dev/docs/reference/run (fetched 2026-10-17).
- Vitest CLI: https://vitest.dev/guide/cli (fetched 2026-10-17).
- Zod JSON Schema: https://zod.dev/json-schema (fetched 2026-10-17).
- Vite backend integration (manifest): https://vite.dev/guide/backend-integration.
- RFC 8785 JCS: https://www.rfc-editor.org/rfc/rfc8785.
- Claude Code agent teams: https://code.claude.com/docs/en/agent-teams (fetched 2026-10-17).
- Serena: github.com/oraios/serena, `src/solidlsp/ls_config.py` (`LEAN4 = "lean4"`),
  `src/solidlsp/language_servers/lean4_language_server.py`, `CHANGELOG.md` (v2.0.0, 2026-10-13); via `gh api`.
- lean-lsp-mcp: github.com/oOo0oOo/lean-lsp-mcp README and `docs/tools.md`; release v0.31.0 (2026-09-30).
- Lean 4: github.com/leanprover/lean4 releases (v4.35.0, 2026-10-12); `src/lake/README.md` (test/lint drivers);
  `src/Lean/Data/Json/FromToJson.lean`.
- chrome-devtools-mcp: github.com/ChromeDevTools/chrome-devtools-mcp README (usage statistics, `--isolated`, `--slim`).
- Perfetto: github.com/google/perfetto releases (v58.2); pypi.org/project/perfetto (0.58.2).
- npm registry (`npm view`, 2026-10-17): turbo 2.11.9, nx 23.3.0, vitest 5.0.5, knip 6.41.0, @ast-grep/cli 0.51.0,
  chrome-devtools-mcp 1.11.0, @playwright/test 1.64.1, zod 4.6.7, vite 8.3.4, @mui/material 9.5.0, shadcn 4.22.0,
  tailwindcss 4.3.3, hono 4.13.13, lefthook 2.2.2, @biomejs/biome 2.5.15, dependency-cruiser 18.6.0, fast-check
  4.10.2, typescript 7.0.2 (6.0.3 last 6.x).
- Hexagonal architecture: https://alistair.cockburn.us/hexagonal-architecture/; functional core / imperative shell:
  https://www.destroyallsoftware.com/screencasts/catalog/functional-core-imperative-shell.
