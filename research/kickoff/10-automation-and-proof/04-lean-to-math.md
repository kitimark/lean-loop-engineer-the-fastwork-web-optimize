# 04 · Lean → math: tooling, a pipeline that keeps them in sync, and every `Fw/Spec` theorem as math

Status: research note for plan rev 4+ (2026-10-17). Scope: (a) tooling and a recommended pipeline;
(b) a translation of every theorem and key definition in `research/kickoff/05-lean-sketch/Fw/Spec/*.lean`;
(c) a sample page, `math-view-sample.html`, in this directory.
Labels: **CONFIRMED** = read in source/README/API, **MEASURED** = I ran it here (command given),
**INFERRED** = my reasoning, not checked.

---

## 0. TL;DR

1. **Write the math in the Lean docstring.** Each declaration's docstring has a one-sentence English
   reading and one `$$…$$` block. doc-gen4 (MathJax), verso-blueprint (KaTeX) and our own page
   (KaTeX) all render that form, so the math lives once, next to the code.
2. **Generate the "math view"; never hand-maintain it.** A ~225-line Lean metaprogram
   (`lake exe mathview`, prototype in `lean-scratch/04-mathview/`, MEASURED on Lean 4.35.0) walks
   the compiled environment and exports one JSON entry per declaration. Each entry holds the
   docstring math, the English line, the pretty-printed Lean signature, a **mechanical LaTeX
   rendering of the Lean type** (no LLM involved), a **deep statement hash**, the axioms used
   (`sorryAx` ⇒ not proved) and the source line. A static KaTeX page is built from that JSON on
   every build.
3. **The page has two layers of math, and a lint keeps them honest.**
   - *Mechanical math* is generated from the Lean term, so it is in sync by construction. It is
     faithful but plain.
   - *Curated math* is the readable docstring version. It is guarded by a lock file
     (`math.lock.json`) that stores the deep statement hash each docstring was reviewed against.
   - `mathview lint` fails CI when a theorem has no `$$` math, uses `sorry`, or its statement
     hash no longer matches the lock (STALE: re-review).
   - The deep hash also covers the bodies of every `Fw.*` definition the statement reaches. So
     changing `minRuns := 3` to `4` marks `better_needs_runs` stale, even though its printed
     signature is byte-identical (MEASURED, §2.4).
4. **Review is a back-translation check by a separate agent role, not a human chore.** The
   reviewer writes math from the Lean signature and mechanical form *without* seeing the
   docstring, then compares the two clause by clause against an edge-case checklist (empty
   lists, ties, ⌊⌋ and truncation, `= true`, override order). Only `mathview accept` writes the
   lock. Agents never edit hashes by hand.
5. **Adopt Verso Blueprint later, not now.** It already does docstring → KaTeX, dependency graph
   and sorry-tracking (`@[blueprint]`). But it has no release tags, its `main` pins
   `v4.35.0-rc4` (we are on `v4.35.0`), and it pulls in verso, subverso and ProofWidgets. It
   also has **no statement-hash staleness check** (CONFIRMED by grep of its manual), and that
   check is the thing we need most. Re-evaluate at M4.
6. **Translating found 7 places where a comment claims more than the theorem proves** (§5). The
   most important: the lease has **no starvation-freedom theorem**, and it is false as written,
   because a holder can renew forever. MEASURED counterexample in §5.

---

## 1. Tooling survey (checked 2026-10-17 with `gh api repos/<r>`)

| tool | what it does | activity / version | fit here |
|---|---|---|---|
| **Lean Blueprint** `PatrickMassot/leanblueprint` | plasTeX plugin. You write LaTeX with `\lean{decl}`, `\leanok`, `\uses{}`; it builds a web page plus a dependency graph. | CONFIRMED: 389★, last push 2025-12-23, tag `v0.0.20`. | Math lives in a separate `.tex` file, so it drifts from the Lean. It needs Python, plasTeX and a LaTeX toolchain. `\leanok` is *hand-set* (the `checkdecls` tool only checks that names exist). **Not chosen.** |
| **Verso Blueprint** `leanprover/verso-blueprint` | Blueprints written in Verso. `@[blueprint "label"]` on a declaration makes "the declaration docstring supply the informal statement". KaTeX rendering, KaTeX lint during elaboration, sorry-aware progress, dependency graph, `autoDeps` inference, `lake exe vbp query`, JSON manifest export. | CONFIRMED: created 2026-02-22, last push 2026-10-10, 35★. **0 tags.** `main` pins `leanprover/lean4:v4.35.0-rc4` and requires verso, verso-slides, subverso, ProofWidgets4 and lean-vir (its `lakefile.lean`). README: [github.com/leanprover/verso-blueprint](https://github.com/leanprover/verso-blueprint). | Best long-term fit: docstring-as-statement is exactly our convention. **Gaps:** (1) it does not detect when a statement changed after its prose was written (grep of `doc/MANUAL.md` for hash/stale/drift finds nothing); (2) we would have to pin an untagged commit, and its rc4 vs final toolchain mismatch is unverified (INFERRED risk); (3) a heavy dependency stack. **Later, optional.** |
| **Verso** `leanprover/verso` | Documentation authoring with checked Lean code. | CONFIRMED: last push 2026-10-16, tag `v4.35.0`. | Needed only through verso-blueprint. |
| **Lean core Verso docstrings** | `set_option doc.verso true` parses docstrings as Verso, with structured math nodes `Inline.math (mode) (string)` "to be rendered by an engine such as TeX or KaTeX". | CONFIRMED in the toolchain: `Lean/DocString/Extension.lean:115`, `Lean/DocString/Types.lean:52-56` (v4.35.0). Default `false`. | Later upgrade path: the exporter would read structured math nodes instead of splitting on `$$`. The syntax differs (``$$`…` ``), so the switch is a mechanical rewrite. |
| **doc-gen4** `leanprover/doc-gen4` | API docs from docstrings. Math via **MathJax** with `$…$` / `$$…$$` (`static/mathjax-config.js`). | CONFIRMED: last push 2026-10-14, tag `v4.35.0`. | Free bonus: the same `$$` docstrings render in API docs. No staleness checks, no review state. Its JSON (`declaration-data`) has no type hashes. **Optional, for API docs.** |
| **LeanInk** + **Alectryon** | Interleaves Lean proof states with prose. | CONFIRMED: `leanprover/LeanInk` is **archived** (last push 2024-07-18). `cpitclaudel/alectryon` is active (2026-06-02) but Rocq-focused; its Lean 4 path was LeanInk. | **Dead end for Lean 4.35.** |
| **LeanTeX** `kmill/LeanTeX` | Lean 4 library that pretty-prints `Expr` as LaTeX (`#latex 1 + 2/3` → `\frac{…}{…}`), with extensible `latex_pp_rules`. | CONFIRMED: 40★, last push 2025-03-05, toolchain `v4.18.0-rc1`, needs ProofWidgets. | Right idea, stale toolchain. **I wrote a minimal equivalent** (≈120 lines inside `MathView.lean`) that works on 4.35. MEASURED on all 26 theorems (§2.3). |
| **Delaborator / `ppSignature` / `collectAxioms` / `findDocString?` / `getUnfoldEqnFor?`** | Core metaprogramming APIs: pretty-printed signature, axioms used (so `sorryAx` is visible), docstring, a definition's `f.eq_def` equation. | CONFIRMED and MEASURED: the prototype uses all five on 4.35.0. | **The base of the pipeline.** |
| **LLM informalization + back-translation** | An LLM writes the English/math for a Lean statement; a second pass translates back, or a judge compares. | INFERRED from literature. [Herald, arXiv 2410.10878](https://arxiv.org/pdf/2410.10878v2) uses LLM back-translation checks to validate statements. [Beyond Compilation, arXiv 2606.31002](https://www.alphaxiv.org/abs/2606.31002) reports 89.5 % compile-pass but only 60.5 % faithful statements for a tool-augmented agent (a 29-point gap) and recommends round-trip judging plus a clause-by-clause checklist under two-judge consensus. [Numerical-analysis formalization audit, arXiv 2606.14000](https://arxiv.org/pdf/2606.14000) makes the same "kernel acceptance is not enough" point. | Use it as the **review step**, never as the source of truth. The mechanical LaTeX is the fixed point the review is anchored to. |

---

## 2. Recommended pipeline for this repo

### 2.1 Convention (one place for the math)

```lean
/-- A frame is at least 5 ticks long exactly when it lasts at least 37.5 ms.

$$\forall\, dt \in \mathbb{N}:\quad 5 \le \operatorname{tick}(dt) \iff dt \ge 37\,500$$
-/
theorem tick_ge5_iff (dt : Nat) : 5 ≤ tick dt ↔ 37500 ≤ dt := …
```

Rules:
- The first paragraph is one English sentence; the first `$$…$$` block is the statement. Edge
  cases go in a second `$$` block, or on an "Edge:" line.
- Every `theorem`, `def`, `structure` and `inductive` under `Fw.Spec` needs this. Helpers can opt
  out with `@[mathview_skip]` (to add).
- Symbols must come from the notation table (§3), which becomes a `mathview` macro prelude. Then
  `\operatorname{tick}` etc. are not re-invented per entry.
- Do not hand-write "uses"/dependency lists. The exporter computes them from the term's constants
  (`Expr.getUsedConstants`, transitively through `Fw.*` defs).

### 2.2 Generated artefacts (all rebuilt by `lake build` + one command, so nothing is edited by hand)

| artefact | made by | content |
|---|---|---|
| `_out/mathview.json` | `lake exe mathview` (Lean, runs on the compiled `.olean`s) | per declaration: `name, kind, module, line, doc, math[], signature, autoTex, stmtHash, axioms[], sorryFree` (prototype fields, MEASURED). Add `uses[]`. |
| `docs/math/index.html` | a ~150-line Node script over the JSON (KaTeX `renderToString`, `throwOnError: true`) | one static page grouped by module. Per entry: curated math, English line, status chips, Lean signature (collapsed), mechanical math (collapsed), uses-chips, link to `file:line`. The v2 console can embed or link it. Shape: `math-view-sample.html`. |
| `math.lock.json` (committed) | `lake exe mathview accept <decl…>` | `{decl: {stmtHash, mathHash, reviewed: {role, date, method}}}`. `mathHash` = hash of the docstring's English + `$$` text. |

### 2.3 Checks (CI and pre-commit; fail = red build, no human reminder needed)

| check | fails when |
|---|---|
| `missing-math` | a theorem/def/structure has no `$$` block (prototype `--lint`, MEASURED: on today's sketch it reports `70 entries, 26 failing`, i.e. all 26 theorems; defs not yet enforced) |
| `sorry` | `axioms` contains `sorryAx` (MEASURED: a test theorem `:= sorry` shows `['sorryAx'] False`) and the declaration is not on a `planned` allowlist |
| `stale-statement` | the current `stmtHash` ≠ the lock: the Lean statement **or any `Fw.*` definition it reaches** changed since the math was reviewed |
| `stale-math` | the current `mathHash` ≠ the lock: someone edited the math or English without a review |
| `katex` | KaTeX cannot parse a `$$` block |
| `orphan` | the lock names a declaration that no longer exists |
| `axioms` | anything beyond `propext`, `Classical.choice`, `Quot.sound` (replaces `scripts/Axioms.lean`'s hand-kept list, which today covers 10 names, with "every declaration") |

The page shows the same states as chips: **proved** / **sorry**, **reviewed** / **unreviewed** /
**stale**. A stale entry stays visible but is struck through in the console. The user never reads
outdated math as current.

### 2.4 Why a *deep* hash (MEASURED)

A theorem's meaning depends on the definitions it names. `stmtHash` therefore folds the
`Expr.hash` of the theorem type with `(type, value)` hashes of every `Fw.*` constant it reaches,
transitively (`deepConsts` in `MathView.lean`). Experiment, in
`lean-scratch/04-mathview` (my copy of the sketch):

```
lake exe mathview > out.json                 # baseline
sed -i '' 's/def minRuns : Nat := 3/def minRuns : Nat := 4/' Fw/Spec/Verdict.lean
lake build Fw && lake exe mathview > out3.json
```

| theorem | signature text | stmtHash before → after |
|---|---|---|
| `better_needs_runs` | identical | `1230331855713331017` → `15282557627323986904` |
| `better_sound` | identical | `9064569543793763486` → `3138665797608781551` |
| `tick_ge5_iff` | identical | unchanged (does not reach `minRuns`) |

So a signature-only hash would have missed a real meaning change ("3 runs" becomes "4 runs").
Reverting restores the original hashes, and two runs give byte-identical JSON (MEASURED with
`cmp`). Caveat (INFERRED): `Expr.hash` is not guaranteed stable across toolchain bumps, so a bump
may mark everything stale. That fails in the safe direction. Add
`mathview accept --toolchain-bump`, which re-accepts only entries whose signature text and
mechanical LaTeX are unchanged.

### 2.5 The review loop (automated roles, no manual status upkeep)

1. A spec author (agent) changes Lean. CI goes red with `stale-statement: Fw.X.y`.
2. The author updates the docstring math. CI is still red (`stale-math`), as designed.
3. A **math-reviewer** agent (separate context, sees only the signature, mechanical LaTeX and
   definitions, **not** the docstring) writes its own math. A judge step compares it with the
   docstring clause by clause, using this checklist: quantifier set and domains (ℕ vs ℤ); every
   hypothesis present; `≤` vs `<`; ⌊⌋ / truncated `-`; empty-list behaviour; ties; duplicates in
   lists; `= true` for Bool; override/fold order; which direction of ⇔/⇒ is proved.
4. They agree → the reviewer runs `mathview accept Fw.X.y`, CI goes green and the page updates.
   They disagree → the item goes to the human queue with both versions side by side. This is the
   only time the user is asked.
5. For a non-Lean reader, the trust order is **mechanical math (exact, generated)** →
   **curated math (readable, review-gated)** → English line (gist only).

### 2.6 What the prototype shows (MEASURED, `lean-scratch/04-mathview/`)

Reproduce:
`cd research/kickoff/10-automation-and-proof/lean-scratch/04-mathview && ~/.elan/bin/lake build Fw mathview && ~/.elan/bin/lake exe mathview > out.json && ~/.elan/bin/lake exe mathview --lint`

- **Coverage:** 70 user-written declarations (26 theorems, 25 defs, 19 structures/inductives).
  Auto-generated ones are filtered out (`mk.inj`, derived `instRepr…`, matchers): no source
  range, an instance, a projection, or an `inst*` component. All 26 theorems are sorry-free.
- **Mechanical LaTeX is readable for all 26 theorems.** Example (`tick_ge5_iff`):
  `\forall \mathrm{dt} \in \mathbb{N},\ (5 \le \mathrm{tick}(\mathrm{dt})) \iff (37500 \le \mathrm{dt})`.
  For defs it renders the unfold equation `f.eq_def`:
  - `tick` → `\mathrm{tick}(dt) = \left\lfloor \frac{(dt \cdot 240) + 1000000}{2000000} \right\rfloor`
    (Nat `/` is rendered as ⌊⌋ on purpose).
  - `mainUs`, `override`, `advance`, `verdict` render as readable if/then/else.
- **Limit:** the 9 defs built on `match` (`step`, `promote`, `gateOk`, `Stage.idx/next`,
  `Rule.holds`, `resolve`, `verdict`'s inner match, `advance`'s inner match) render as
  `match_1(…)` and Bool helpers as `bne`/`and`/`all`. Next step: render those from the per-arm
  equation lemmas (`getEqnsFor?` gives `f.eq_1 … f.eq_n`) as a `cases` block, and map
  `bne/&&/||/!/List.all/List.contains` to `≠ ∧ ∨ ¬ ∀ ∈`. Until then, curated math carries these.
- Run time: 2.8 s wall-clock for `lake exe mathview` after the build, including Lake start-up (MEASURED with `/usr/bin/time -p`; one `importModules` of `Fw`). The `line` field is the start of the declaration range, so it points at the first line of the docstring, not at the `theorem` keyword.

### 2.7 Rejected alternatives

- **Math-first (write LaTeX, generate Lean):** this is autoformalization. The research above shows
  a 29-point gap between "compiles" and "faithful". Lean stays the source of truth.
- **LLM translation at render time:** it is not reproducible, and it is unreviewed exactly when
  the user reads it.
- **Separate `.tex` blueprint (leanblueprint):** a second file to keep in sync by hand, the very
  thing the user asked to get rid of.

---

## 3. Notation (defined once; used in §4 and on the page)

| symbol | meaning | Lean |
|---|---|---|
| $\mathbb{N}=\{0,1,2,\dots\}$, $\mathbb{Z}$ | naturals, integers (no floats anywhere in `Fw.Spec`) | `Nat`, `Int` |
| µs, s | all frame times are integer **microseconds**; lease times are integer **seconds** | comments in source |
| $X^{*}$ | finite lists over $X$, order and repeats matter | `List X` |
| $[\,]$, $[x_1,\dots,x_n]$, $x :: xs$, $xs \mathbin{+\!\!+} ys$ | empty list, list literal, prepend, append | `[]`, `[a,b]`, `x :: xs`, `xs ++ ys` |
| $\lvert xs\rvert$ | length, **counting repeats** | `xs.length` |
| $x \in xs$ | membership | `x ∈ xs` |
| $\#\{i : P(x_i)\} = \sum_{i=1}^{n} [P(x_i)]$ | count of positions satisfying $P$ (repeats counted) | `(xs.filter P).length` |
| $[P]$ | Iverson bracket: 1 if $P$, else 0 | `decide P` |
| $\lfloor a/b \rfloor$ | natural-number division rounds **down** | `a / b` on `Nat` |
| $-xs$ | negate every element: $[-x_1,\dots,-x_n]$ | `xs.map (- ·)` |
| $f[p \mapsto v]$ | function update: $f[p\mapsto v](q) = v$ if $q=p$, else $f(q)$ | `override f p v` |
| $X_\bot = X \cup \{\bot\}$ | optional value; $\bot$ = "none" | `Option X`, `none` / `some x` |
| $s.\mathit{field}$ | record field | `s.field` |
| Bool-valued $f$ | in the math, a Bool function is used as a predicate: "$f(x)$" means $f(x)=\mathrm{true}$ | `f x = true` |
| $(s', r) = \mathrm{step}(s,c)$; $\mathrm{step}(s,c)_1$ | a pair and its first component | `(step s c).1` / `.fst` |
| $\mathrm{ok}(x)$, $\mathrm{error}(m)$ | success or failure result | `Except.ok`, `.error` |
| $\Rightarrow$, $\iff$, $\forall$, $\exists$, $\land$, $\lor$, $\neg$ | as usual; an arrow chain $A \Rightarrow B \Rightarrow C$ reads "if A and B then C" | `→`, `↔`, `∀`, `∃`, `∧`, `∨`, `¬` |

"$\forall$ variables" are left implicit when they are just the declaration's parameters: every
free symbol in a theorem below is universally quantified over its type.

---

## 4. Translation of every declaration in `Fw/Spec/*.lean`

Format per entry: **Lean name** (`file:line`) · Lean (verbatim, shortened only where marked `…`) ·
math · plain English · relies on. Edge cases are part of the math, not footnotes.

### 4.1 Frames (`Fw/Spec/Frames.lean`)

**D1 · `Fw.Frames.tick`** (`:13`) · Lean: `def tick (dt : Nat) : Nat := (dt * 240 + 1000000) / 2000000`

$$\operatorname{tick}(dt) \;=\; \left\lfloor \frac{240\,dt + 10^{6}}{2\cdot 10^{6}} \right\rfloor \;=\; \left\lfloor \frac{dt}{8333.\overline{3}} + \frac12 \right\rfloor \qquad (dt \in \mathbb{N}\ \mu\text{s})$$

English: the number of 120 Hz ticks in a frame of $dt$ µs, rounded to the nearest tick, halves
rounded up. Edge (MEASURED, `EdgeCases.lean`): $\operatorname{tick}(0..4166)=0$,
$\operatorname{tick}(4167)=1$, $\operatorname{tick}(37499)=4$, $\operatorname{tick}(37500)=5$,
$\operatorname{tick}(54166)=6$, $\operatorname{tick}(54167)=7$. Relies on: —.

**T1 · `tick_ge5_iff`** (`:16`) · Lean: `theorem tick_ge5_iff (dt : Nat) : 5 ≤ tick dt ↔ 37500 ≤ dt`

$$\forall dt \in \mathbb{N}:\quad \operatorname{tick}(dt) \ge 5 \iff dt \ge 37\,500$$

English: a frame counts as "≥ 5 ticks" exactly when it is at least 37.5 ms long. Relies on: D1.

**T2 · `tick_ge7_iff`** (`:20`) · Lean: `theorem tick_ge7_iff (dt : Nat) : 7 ≤ tick dt ↔ 54167 ≤ dt`

$$\forall dt \in \mathbb{N}:\quad \operatorname{tick}(dt) \ge 7 \iff dt \ge 54\,167$$

English: "≥ 7 ticks" is exactly "at least 54.167 ms" (54 166.67 rounded up to whole µs). Relies on: D1.

**T3 · `tick_mono`** (`:24`) · Lean: `theorem tick_mono {a b : Nat} (h : a ≤ b) : tick a ≤ tick b`

$$\forall a,b \in \mathbb{N}:\quad a \le b \;\Rightarrow\; \operatorname{tick}(a) \le \operatorname{tick}(b)$$

English: a longer frame never gets fewer ticks. Relies on: D1.

**D2 · `countAbove`** (`:28`) · Lean: `def countAbove (t : Nat) (xs : List Nat) : Nat := (xs.filter (fun x => decide (t < x))).length`

$$\operatorname{countAbove}(t, [x_1,\dots,x_n]) \;=\; \#\{\, i : x_i > t \,\} \;=\; \sum_{i=1}^{n} [\,x_i > t\,]$$

English: how many frames are **strictly** longer than $t$ µs, repeats counted. Edge:
$\operatorname{countAbove}(t,[\,])=0$; $\operatorname{countAbove}(10,[11,11,10,5])=2$ (MEASURED;
the frame equal to $t$ is not counted). Relies on: —.

**T4 · `countAbove_antitone`** (`:31`) · Lean: `theorem countAbove_antitone {t t' : Nat} (h : t ≤ t') (xs : List Nat) : countAbove t' xs ≤ countAbove t xs`

$$\forall t,t' \in \mathbb{N},\ \forall xs \in \mathbb{N}^{*}:\quad t \le t' \;\Rightarrow\; \operatorname{countAbove}(t', xs) \le \operatorname{countAbove}(t, xs)$$

English: raising the threshold never raises the count. Example, with the ms thresholds converted
to µs: $\operatorname{countAbove}(54000, xs) \le \operatorname{countAbove}(50000, xs) \le \operatorname{countAbove}(46000, xs)$
on every run. Relies on: D2.

**T5 · `tick5_eq_countAbove`** (`:46`) · Lean: `theorem tick5_eq_countAbove (xs : List Nat) : (xs.filter (fun x => decide (5 ≤ tick x))).length = countAbove 37499 xs`

$$\forall xs \in \mathbb{N}^{*}:\quad \#\{\, i : \operatorname{tick}(x_i) \ge 5 \,\} \;=\; \operatorname{countAbove}(37\,499, xs) \;=\; \#\{\, i : x_i \ge 37\,500 \,\}$$

English: counting frames of ≥ 5 ticks is the same as counting frames of ≥ 37.5 ms.
Relies on: D1, D2, T1. **Exactness note:** the docstring says the legacy ">34 ms" count and the
tick count "differ exactly on the frames in (34, 37.5) ms". That follows from T5 by a partition
argument, $\operatorname{countAbove}(34000,xs) - \#\{\text{tick}\ge5\} = \#\{i : 34000 < x_i \le 37499\}$.
The subtraction here is ordinary minus, while Lean's `Nat` minus truncates at 0; the two agree
because the subtraction never truncates: tick ≥ 5 implies $x \ge 37500 > 34000$ (T1), so
$\#\{\text{tick}\ge5\} \le \operatorname{countAbove}(34000,xs)$ (T5 and T4). In the sketch this
equation is **not** a theorem yet; the checked proof is in §5, gap G1.

### 4.2 Verdict (`Fw/Spec/Verdict.lean`)

**D3 · types** (`:10-17`) · `inductive Dir | lower | higher` · `inductive Verdict | better | worse | noise | tooFew`

$$\mathrm{Dir} = \{\mathrm{lower}, \mathrm{higher}\}, \qquad \mathrm{Verdict} = \{\mathrm{better}, \mathrm{worse}, \mathrm{noise}, \mathrm{tooFew}\}$$

English: "lower is better" (frame counts, dt) or "higher is better" (fps); four possible outcomes.

**D4 · `below`** (`:20`) · Lean: `def below (b a : List Int) : Bool := b.all fun y => a.all fun x => decide (y < x)`

$$\operatorname{below}(B, A) \iff \forall y \in B,\ \forall x \in A:\ y < x \qquad\Big(\text{for } A,B \ne [\,]:\ \iff \max B < \min A\Big)$$

English: every value of $B$ is strictly below every value of $A$. Edge: **if either list is
empty, `below` is true** (vacuous; MEASURED `below [] [1,2] = true`, `below [1] [] = true`). A
single tie $y = x$ makes it false. Relies on: —.

**D5 · `minRuns`** (`:22`) · `def minRuns : Nat := 3`  $$\mathrm{minRuns} = 3$$

**D6 · `verdict`** (`:24`) · Lean:
`def verdict (d : Dir) (ctl var : List Int) : Verdict := if ctl.length < minRuns ∨ var.length < minRuns then .tooFew else match d with | .lower => if below var ctl then .better else if below ctl var then .worse else .noise | .higher => if below ctl var then .better else if below var ctl then .worse else .noise`

With control runs $C$ and variant runs $V$, first-match-wins:

$$\operatorname{verdict}(\mathrm{lower}, C, V) = \begin{cases} \mathrm{tooFew} & \text{if } |C| < 3 \ \lor\ |V| < 3 \\ \mathrm{better} & \text{else if } \operatorname{below}(V, C) \quad (\max V < \min C)\\ \mathrm{worse} & \text{else if } \operatorname{below}(C, V) \quad (\max C < \min V)\\ \mathrm{noise} & \text{otherwise (the ranges overlap or touch)} \end{cases}$$

$$\operatorname{verdict}(\mathrm{higher}, C, V) = \text{the same with } \operatorname{below}(C,V) \text{ for better and } \operatorname{below}(V,C) \text{ for worse.}$$

English: with at least 3 runs per side, the variant is better only if *every* variant run beats
*every* control run. Edge: lengths count repeats, so `[5,5,5]` is 3 runs. Ties give `noise`
(MEASURED: `verdict lower [10,11,12] [9,10,8] = noise`). When both sides have ≥ 3 runs, both
lists are non-empty, so by T9 at most one of the two `below` tests holds and the order of the
cases does not matter. Relies on: D3–D5.

**T6 · `below_spec`** (`:30`) · Lean: `theorem below_spec (b a : List Int) : below b a = true ↔ ∀ y ∈ b, ∀ x ∈ a, y < x`

$$\forall A, B \in \mathbb{Z}^{*}:\quad \operatorname{below}(B, A) = \mathrm{true} \iff \forall y \in B,\ \forall x \in A:\ y < x$$

English: the Bool test means exactly what it says. Relies on: D4.

**T7 · `better_sound`** (`:34`) · Lean: `theorem better_sound {ctl var : List Int} (h : verdict .lower ctl var = .better) : ∀ y ∈ var, ∀ x ∈ ctl, y < x`

$$\operatorname{verdict}(\mathrm{lower}, C, V) = \mathrm{better} \;\Rightarrow\; \forall y \in V,\ \forall x \in C:\ y < x$$

English: when lower is better, "better" means every variant run was strictly lower than every
control run (Mann–Whitney $U = 0$). Scope: proved for `lower` only; `higher` follows from T12
but is not stated. Relies on: D6, T6.

**T8 · `better_needs_runs`** (`:45`) · Lean: `theorem better_needs_runs {d : Dir} {ctl var : List Int} (h : verdict d ctl var = .better) : minRuns ≤ ctl.length ∧ minRuns ≤ var.length`

$$\forall d:\quad \operatorname{verdict}(d, C, V) = \mathrm{better} \;\Rightarrow\; |C| \ge 3 \ \land\ |V| \ge 3$$

English: no "better" without at least 3 runs on each side. Relies on: D5, D6.

**T9 · `below_antisymm`** (`:53`) · Lean: `theorem below_antisymm {a b : List Int} (ha : a ≠ []) (hb : b ≠ []) (h1 : below b a = true) (h2 : below a b = true) : False`

$$A \ne [\,] \ \land\ B \ne [\,] \;\Rightarrow\; \neg\big(\operatorname{below}(B, A) \land \operatorname{below}(A, B)\big)$$

English: two non-empty lists cannot each be strictly below the other. (With an empty list both
are true, see D4, which is why the hypotheses are needed.) Relies on: D4, T6.

**T10 · `swap_better`** (`:63`) · Lean: `theorem swap_better {d : Dir} {ctl var : List Int} (h : verdict d ctl var = .better) : verdict d var ctl = .worse`

$$\forall d:\quad \operatorname{verdict}(d, C, V) = \mathrm{better} \;\Rightarrow\; \operatorname{verdict}(d, V, C) = \mathrm{worse}$$

English: swapping control and variant turns "better" into "worse". Scope: one direction only;
"worse → swap gives better" and "noise ↔ noise" are not stated (gap G2). Relies on: D6, T8, T9.

**T11 · `below_neg`** (`:96`) · Lean: `theorem below_neg (a b : List Int) : below (a.map (- ·)) (b.map (- ·)) = below b a`

$$\forall A, B \in \mathbb{Z}^{*}:\quad \operatorname{below}(-A, -B) = \operatorname{below}(B, A)$$

English: negating both lists flips which one is below. Relies on: D4, T6.

**T12 · `verdict_higher_eq_lower_neg`** (`:108`) · Lean: `theorem verdict_higher_eq_lower_neg (ctl var : List Int) : verdict .higher ctl var = verdict .lower (ctl.map (- ·)) (var.map (- ·))`

$$\forall C, V \in \mathbb{Z}^{*}:\quad \operatorname{verdict}(\mathrm{higher}, C, V) = \operatorname{verdict}(\mathrm{lower}, -C, -V)$$

English: "higher is better" on $x$ is exactly "lower is better" on $-x$. One rule, two directions.
Relies on: D6, T11.

### 4.3 Flags (`Fw/Spec/Flags.lean`)

**D7 · `Part`, `Part.all`** (`:11-15`) · `inductive Part | nav | hero | categories | carousel | countdown | footer` · `def Part.all : List Part := [.nav, .hero, .categories, .carousel, .countdown, .footer]`

$$\mathrm{Part} = \{\mathrm{nav}, \mathrm{hero}, \mathrm{categories}, \mathrm{carousel}, \mathrm{countdown}, \mathrm{footer}\},\qquad \mathrm{Part.all} = [\mathrm{nav}, \mathrm{hero}, \mathrm{categories}, \mathrm{carousel}, \mathrm{countdown}, \mathrm{footer}]$$

**T13 · `Part.mem_all`** (`:16`) · Lean: `theorem Part.mem_all (p : Part) : p ∈ Part.all`

$$\forall p \in \mathrm{Part}:\quad p \in \mathrm{Part.all}$$

English: the list of parts is complete. Relies on: D7.

**D8 · `Variant`, `Config`** (`:18-19`) · `abbrev Variant := String` · `abbrev Config := Part → Variant`

$$\mathrm{Variant} = \text{strings}, \qquad \mathrm{Config} = \mathrm{Variant}^{\mathrm{Part}} \ \ (\text{total functions } c : \mathrm{Part} \to \mathrm{Variant})$$

English: a configuration picks exactly one variant for every part. This holds by its type, so no
theorem is needed.

**D9 · `Rule`, `Rule.holds`** (`:21-28`) · Lean: `| .requires p v q w => c p != v || c q == w` · `| .conflicts p v q w => !(c p == v && c q == w)`

$$\operatorname{holds}_c\big(\mathrm{requires}(p,v,q,w)\big) \iff \big(c(p) = v \Rightarrow c(q) = w\big), \qquad \operatorname{holds}_c\big(\mathrm{conflicts}(p,v,q,w)\big) \iff \neg\big(c(p) = v \land c(q) = w\big)$$

English: "if part $p$ uses $v$ then part $q$ must use $w$" / "$p{=}v$ and $q{=}w$ never together".

**D10 · `Registry`, `Config.ok`** (`:30-35`) · Lean: `def Config.ok (r : Registry) (c : Config) : Bool := Part.all.all (fun p => (r.variants p).contains (c p)) && r.rules.all (·.holds c)`

A registry is a pair

$$r = (\mathit{variants} : \mathrm{Part} \to \mathrm{Variant}^{*},\ \ \mathit{rules} : \mathrm{Rule}^{*}), \qquad \text{the head of } \mathit{variants}(p) \text{ is the default for } p.$$

$$\operatorname{ok}_r(c) \iff \big(\forall p \in \mathrm{Part.all}:\ c(p) \in r.\mathit{variants}(p)\big) \ \land\ \big(\forall \rho \in r.\mathit{rules}:\ \operatorname{holds}_c(\rho)\big) \qquad (\mathrm{Part.all} = \mathrm{Part} \text{ by T13})$$

English: every chosen variant is registered for its part, and every rule holds. Note: Lean loops
over the **list** `Part.all`, not over the type. The two agree only because of T13; if a new `Part`
constructor were added without updating `Part.all`, T13 would stop compiling, which is what keeps
this check from silently skipping the new part. Edge: if $r.\mathit{variants}(p) = [\,]$ for some
$p$, **no** configuration is ok. Relies on: D7, D9, T13.

**D11 · `defaults`** (`:37`) · Lean: `def defaults (r : Registry) : Config := fun p => (r.variants p).headD "orig"`

$$\operatorname{defaults}_r(p) = \begin{cases} v_1 & \text{if } r.\mathit{variants}(p) = [v_1, \dots] \\ \texttt{"orig"} & \text{if } r.\mathit{variants}(p) = [\,] \end{cases}$$

English: the first registered variant is the default; with none registered, the default is
`"orig"`, which then fails D10 (MEASURED `defaults {variants := fun _ => []} nav = "orig"`).

**D12 · `override`** (`:39`) · Lean: `def override (c : Config) (p : Part) (v : Variant) : Config := fun q => if q = p then v else c q`

$$\operatorname{override}(c, p, v) = c[p \mapsto v]$$

**D13 · `resolve`** (`:42-46`) · Lean: `def resolve (r : Registry) (req : List (Part × Variant)) : Except String Config := check r (req.foldl (fun c (p, v) => override c p v) (defaults r))` with `check r c := if c.ok r then .ok c else .error "invalid configuration"`

$$c^{\star} = \operatorname{defaults}_r[p_1 \mapsto v_1][p_2 \mapsto v_2]\cdots[p_n \mapsto v_n], \qquad \operatorname{resolve}(r, [(p_1,v_1),\dots,(p_n,v_n)]) = \begin{cases} \mathrm{ok}(c^{\star}) & \text{if } \operatorname{ok}_r(c^{\star}) \\ \mathrm{error}(\texttt{"invalid configuration"}) & \text{otherwise} \end{cases}$$

English: start from the defaults, apply the requested overrides left to right, and accept the
result only if it is valid. Edge: **for a part requested twice, the last request wins** (MEASURED:
`[(hero,"orig"),(hero,"v2")]` gives `"v2"`); an empty request gives the defaults. An unknown
variant gives the error **only if it is the last request for its part**: an earlier unknown
request that a later one overwrites is accepted (MEASURED in verification: with `reg` as in
`EdgeCases.lean`, `resolve reg [(hero,"v3"),(hero,"v2")] = ok` with hero ↦ `"v2"`). An empty
variant list for any part also gives the error (D11), and so does any failing rule.

**T14 · `resolve_sound`** (`:48`) · Lean: `theorem resolve_sound {r : Registry} {req : List (Part × Variant)} {c : Config} (h : resolve r req = .ok c) : c.ok r = true`

$$\operatorname{resolve}(r, \mathit{req}) = \mathrm{ok}(c) \;\Rightarrow\; \operatorname{ok}_r(c)$$

English: whatever `resolve` returns is a valid configuration. Relies on: D10, D13.

**D14 · `diff`** (`:56`) · Lean: `def diff (a b : Config) : List Part := Part.all.filter (fun p => a p != b p)`

$$\operatorname{diff}(a, b) = [\, p \in \mathrm{Part.all} \mid a(p) \ne b(p) \,] \quad (\text{in the order of } \mathrm{Part.all});\qquad \text{as a set: } \{p : a(p) \ne b(p)\}$$

**T15 · `override_diff`** (`:60`) · Lean: `theorem override_diff (c : Config) (p : Part) (v : Variant) (h : c p ≠ v) : diff c (override c p v) = [p]`

$$c(p) \ne v \;\Rightarrow\; \operatorname{diff}\big(c,\ c[p \mapsto v]\big) = [p]$$

English: overriding one part to a new value gives a pair of configurations that differ in exactly
that part (A/B isolation by construction). Edge: if $c(p)=v$ the hypothesis fails; the diff is
then $[\,]$, which is true but not stated. Relies on: D7, D12, D14.

### 4.4 Cost (`Fw/Spec/Cost.lean`)

**D15 · `Work`, `CompWork`, `UnitCost`, `Frame`** (`:11-48`)

$$w = (s, e, \ell, k) \in \mathbb{N}^4 \ \ (\text{script }\mu\text{s},\ \text{style elements},\ \text{layout objects},\ \text{paint kpx}), \qquad \kappa = (m, r) \in \mathbb{N}^2 \ \ (\text{layers moved},\ \text{raster kpx})$$
$$u = (u_{\mathrm{style}}, u_{\mathrm{layout}}, u_{\mathrm{paint}}) \in \mathbb{N}^3 \ \ (\mu\text{s per unit, whole numbers}), \qquad \text{frame } f = (f.\mathit{main} \in \mathbb{N}^4,\ f.\mathit{comp} \in \mathbb{N}^2)$$

Edge: unit costs are **whole µs**, so they are $\ge 0$ automatically, but sub-µs costs (e.g. 0.3
µs per style element) cannot be expressed (gap G5).

**D16 · `Work.le`** (`:30`) · Lean: `a.scriptUs ≤ b.scriptUs ∧ a.styleElems ≤ b.styleElems ∧ a.layoutObjs ≤ b.layoutObjs ∧ a.paintKpx ≤ b.paintKpx`

$$a \preceq b \iff s_a \le s_b \ \land\ e_a \le e_b \ \land\ \ell_a \le \ell_b \ \land\ k_a \le k_b$$

English: $a$ does no more of each kind of main-thread work than $b$ (componentwise order; some
pairs are incomparable).

**D17 · `mainUs`** (`:33`) · Lean: `w.scriptUs + u.style * w.styleElems + u.layout * w.layoutObjs + u.paint * w.paintKpx`

$$\operatorname{mainUs}(u, w) = s + u_{\mathrm{style}}\, e + u_{\mathrm{layout}}\, \ell + u_{\mathrm{paint}}\, k \;=\; \sum_{j=1}^{4} c_j\, w_j,\quad c = (1, u_{\mathrm{style}}, u_{\mathrm{layout}}, u_{\mathrm{paint}}) \ge 0$$

English: main-thread time is a weighted sum of the work counts. Compositor work does not appear.

**T16 · `mainUs_mono`** (`:37`) · Lean: `theorem mainUs_mono (u : UnitCost) {a b : Work} (h : a.le b) : mainUs u a ≤ mainUs u b`

$$\forall u \in \mathbb{N}^3:\quad a \preceq b \;\Rightarrow\; \operatorname{mainUs}(u, a) \le \operatorname{mainUs}(u, b)$$

English: more work never costs less, whatever the (non-negative) unit costs. Relies on: D16, D17.

**T17 · `compositorOnly_same_main`** (`:51`) · Lean: `theorem compositorOnly_same_main (u : UnitCost) (base : Frame) (c : CompWork) : mainUs u { base with comp := c }.main = mainUs u base.main := rfl`

$$\forall u, \mathit{base}, \kappa:\quad \operatorname{mainUs}\big(u,\ (\mathit{base}.\mathit{main}, \kappa).\mathit{main}\big) = \operatorname{mainUs}(u, \mathit{base}.\mathit{main})$$

English: changing only compositor work leaves main-thread cost unchanged. It is true by
definition (`rfl`): the model keeps compositor work out of `mainUs`. Whether a CSS change *is*
compositor-only in an engine is an empirical claim, not proved here. Relies on: D15, D17.

**D18 · `onTime`** (`:55`) · Lean: `def onTime (u : UnitCost) (budgetUs : Nat) (w : Work) : Bool := decide (mainUs u w ≤ budgetUs)`

$$\operatorname{onTime}(u, B, w) \iff \operatorname{mainUs}(u, w) \le B$$

English: a frame is on time when its main-thread cost fits the budget $B$ µs (e.g. 16 667 at 60 Hz).
Edge: equality counts as on time.

**T18 · `onTime_of_le`** (`:58`) · Lean: `theorem onTime_of_le (u : UnitCost) (budgetUs : Nat) {a b : Work} (h : a.le b) (hb : onTime u budgetUs b = true) : onTime u budgetUs a = true`

$$a \preceq b \ \land\ \operatorname{onTime}(u, B, b) \;\Rightarrow\; \operatorname{onTime}(u, B, a)$$

English: if one frame's work $a$ is componentwise at most another frame's work $b$, and $b$ fits
the budget, then $a$ fits the budget. Scope: the theorem is about one pair of work vectors.
Matching a variant's frames to a base's frames (so as to say "every base frame on time stays on
time") is outside the theorem and outside the model. Relies on: D16–D18, T16.

### 4.5 Lease (`Fw/Spec/Lease.lean`)

**D19 · types** (`:12-33`)

$$\mathrm{Owner} = \text{strings}\ \ (\text{Lean: } \texttt{abbrev Owner := String}),$$
$$\mathrm{Lease} = \mathrm{Owner} \times \mathbb{N}\ \ (\mathit{owner}, \mathit{expires}\ \text{in s}), \qquad \mathrm{State} = \mathrm{Lease}_\bot \times \mathrm{Owner}^{*}\ \ (h = \mathit{holder},\ Q = \mathit{queue}), \qquad s_0 = (\bot, [\,])$$
$$\mathrm{Cmd} = \mathrm{acquire}(o,\mathit{now},\mathit{ttl}) \mid \mathrm{renew}(o,\mathit{now},\mathit{ttl}) \mid \mathrm{release}(o,\mathit{now},\mathit{ttl}) \mid \mathrm{tick}(\mathit{now},\mathit{ttl})$$
$$\mathrm{Reply} = \mathrm{granted}(l) \mid \mathrm{queued}(\mathit{pos}) \mid \mathrm{renewed}(l) \mid \mathrm{released} \mid \mathrm{refused}(\mathit{why}) \mid \mathrm{ok}$$

English: at most one holder **by type** ($h$ is a single optional lease), plus a FIFO queue of
waiting owners. This is the mutual-exclusion guarantee: there is no state with two holders.

**D20 · `promote`** (`:36`) · Lean: `| [] => { holder := none, queue := [] } | o :: q => { holder := some ⟨o, now + ttl⟩, queue := q }`

$$\operatorname{promote}(\mathit{now},\mathit{ttl},[\,]) = (\bot, [\,]), \qquad \operatorname{promote}(\mathit{now},\mathit{ttl}, o :: q) = \big((o,\ \mathit{now}+\mathit{ttl}),\ q\big)$$

English: give the device to the head of the queue for $\mathit{ttl}$ seconds; with nobody waiting,
the device becomes free.

**D21 · `step`** (`:40-64`) · Lean: `def step : State → Cmd → State × Reply` (25 lines; full text at the source). With $s = (h, Q)$
and first-match-wins:

$$\mathrm{step}\big(s, \mathrm{acquire}(o,\mathit{now},\mathit{ttl})\big) = \begin{cases} \big(((o, \mathit{now}+\mathit{ttl}), [\,]),\ \mathrm{granted}(o, \mathit{now}+\mathit{ttl})\big) & h = \bot,\ Q = [\,] \\ (s,\ \mathrm{refused}(\texttt{"not normalized"})) & h = \bot,\ Q \ne [\,] \\ (s,\ \mathrm{granted}(l)) & h = l,\ l.\mathit{owner} = o \\ (s,\ \mathrm{queued}(\operatorname{idx}_Q(o))) & h = l,\ l.\mathit{owner} \ne o,\ o \in Q \\ \big((l,\ Q \mathbin{+\!\!+} [o]),\ \mathrm{queued}(|Q|)\big) & h = l,\ l.\mathit{owner} \ne o,\ o \notin Q \end{cases}$$

$$\mathrm{step}\big(s, \mathrm{renew}(o,\mathit{now},\mathit{ttl})\big) = \begin{cases} \big((l',\ Q),\ \mathrm{renewed}(l')\big) \ \text{ where } l' = (o,\ \max(l.\mathit{expires},\ \mathit{now}+\mathit{ttl})) & h = l,\ l.\mathit{owner} = o \\ (s,\ \mathrm{refused}(\texttt{"not the holder"})) & \text{otherwise} \end{cases}$$

The reply carries the same new lease $l'$ that is stored (`Lease.lean:52-53`).

$$\mathrm{step}\big(s, \mathrm{release}(o,\mathit{now},\mathit{ttl})\big) = \begin{cases} (\operatorname{promote}(\mathit{now},\mathit{ttl},Q),\ \mathrm{released}) & h = l,\ l.\mathit{owner} = o \\ \big((l,\ Q \ominus o),\ \mathrm{ok}\big) & h = l,\ l.\mathit{owner} \ne o \\ (s,\ \mathrm{ok}) & h = \bot \end{cases}$$

$$\mathrm{step}\big(s, \mathrm{tick}(\mathit{now},\mathit{ttl})\big) = \begin{cases} (\operatorname{promote}(\mathit{now},\mathit{ttl},Q),\ \mathrm{ok}) & h = l,\ l.\mathit{expires} \le \mathit{now} \\ (s,\ \mathrm{ok}) & \text{otherwise} \end{cases}$$

Here $\operatorname{idx}_Q(o)$ is the **0-based** position of $o$ in $Q$, and $Q \ominus o$ removes
the **first** occurrence of $o$ (no change if $o \notin Q$).
Edge cases (all MEASURED in `lean-scratch/04-mathview/EdgeCases.lean`):
- `acquire` never checks expiry. An expired holder keeps the device until a `tick`.
- A re-entrant `acquire` by the holder does **not** extend the lease ($\mathit{expires}$ stays 10
  when re-acquired at $t=5$ with $\mathit{ttl}=100$).
- A lease expiring exactly at $\mathit{now}$ counts as expired ($\le$).
- `release` by a stranger who is not queued replies `ok` and changes nothing.
- The new holder's lease after `release`/`tick` uses the $\mathit{ttl}$ carried by that command.

**D22 · `Inv`** (`:67-70`) · Lean: `idle_empty : s.holder = none → s.queue = []`, `nodup : s.queue.Nodup`, `not_both : ∀ l, s.holder = some l → l.owner ∉ s.queue`

$$\operatorname{Inv}(h, Q) \iff \big(h = \bot \Rightarrow Q = [\,]\big) \ \land\ \big(Q \text{ has no repeated owner}\big) \ \land\ \big(\forall l:\ h = l \Rightarrow l.\mathit{owner} \notin Q\big)$$

English: nobody waits for a free device, nobody is in the queue twice, and the holder is not also
waiting.

**T19 · `inv_init`** (`:72`) · Lean: `theorem inv_init : Inv {}`  $$\operatorname{Inv}(s_0)$$
English: the empty state satisfies the invariant. Relies on: D19, D22.

**T20 · `promote_inv`** (`:74`) · Lean: `theorem promote_inv {now ttl : Nat} {q : List Owner} (h : q.Nodup) : Inv (promote now ttl q)`

$$Q \text{ has no repeats} \;\Rightarrow\; \operatorname{Inv}\big(\operatorname{promote}(\mathit{now}, \mathit{ttl}, Q)\big)$$

English: promoting from a duplicate-free queue gives a valid state. Relies on: D20, D22.

**T21 · `step_inv`** (`:85`) · Lean: `theorem step_inv {s : State} (c : Cmd) (h : Inv s) : Inv (step s c).1`

$$\forall s, c:\quad \operatorname{Inv}(s) \;\Rightarrow\; \operatorname{Inv}\big(\mathrm{step}(s, c)_1\big)$$

English: every command keeps the invariant. Corollary (by induction, **not yet a Lean theorem**,
gap G3): for every command sequence $c_1,\dots,c_n$, with $s_i = \mathrm{step}(s_{i-1}, c_i)_1$,
$\operatorname{Inv}(s_n)$ holds. Relies on: D21, D22, T20.

**T22 · `requeue_keeps_place`** (`:146`) · Lean: `theorem requeue_keeps_place (s : State) (l : Lease) (o : Owner) (now ttl : Nat) (hl : s.holder = some l) (hne : l.owner ≠ o) (hq : o ∈ s.queue) : (step s (.acquire o now ttl)).1 = s`

$$h = l \ \land\ l.\mathit{owner} \ne o \ \land\ o \in Q \;\Rightarrow\; \mathrm{step}\big(s, \mathrm{acquire}(o, \mathit{now}, \mathit{ttl})\big)_1 = s$$

English: a waiter who asks again keeps its place; the state does not change (v1 incident I-113).
Relies on: D21.

**T23 · `renew_never_shortens`** (`:152`) · Lean: `theorem renew_never_shortens (s : State) (l : Lease) (now ttl : Nat) (hl : s.holder = some l) : ∃ l', (step s (.renew l.owner now ttl)).1.holder = some l' ∧ l.expires ≤ l'.expires`

$$h = l \;\Rightarrow\; \exists l':\ \mathrm{step}\big(s, \mathrm{renew}(l.\mathit{owner}, \mathit{now}, \mathit{ttl})\big)_1.\mathit{holder} = l' \ \land\ l.\mathit{expires} \le l'.\mathit{expires}$$

English: the holder's renew never moves its expiry earlier (v1 incident I-091). Relies on: D21.

**T24 · `release_fifo`** (`:158`) · Lean: `theorem release_fifo (s : State) (l : Lease) (o : Owner) (q : List Owner) (now ttl : Nat) (hl : s.holder = some l) (hq : s.queue = o :: q) : (step s (.release l.owner now ttl)).1 = { holder := some ⟨o, now + ttl⟩, queue := q }`

$$h = l \ \land\ Q = o :: q \;\Rightarrow\; \mathrm{step}\big(s, \mathrm{release}(l.\mathit{owner}, \mathit{now}, \mathit{ttl})\big)_1 = \big((o,\ \mathit{now}+\mathit{ttl}),\ q\big)$$

English: when the holder releases, the first waiter gets the device and everyone else moves up one
place. Scope: one step only; the docstring's "no starvation" is **not** proved and is false
without a fairness assumption (gap G4). Relies on: D20, D21.

### 4.6 Stage (`Fw/Spec/Stage.lean`)

**D23 · `Stage`, `idx`, `next`** (`:7-15`)

$$\mathrm{Stage} = \{R, I, D, F, V, L\},\quad \operatorname{idx}: R,I,D,F,V,L \mapsto 0,1,2,3,4,5,\quad \operatorname{next}(x) = \begin{cases} \operatorname{idx}^{-1}(\operatorname{idx}(x)+1) & x \ne L \\ \bot & x = L \end{cases}$$

**D24 · `Attribution`, `Role`, `Card`, `Topic`** (`:17-43`)

$$\mathrm{Attribution} = \{\mathrm{named}, \mathrm{located}, \mathrm{unexplained}\},\quad \mathrm{Role} = \{\mathrm{owner}, \mathrm{lead}, \mathrm{reviewer}\}$$
$$\mathrm{Card} = \mathrm{Stage} \times \mathrm{Role} \times \mathrm{Attribution}_\bot\ (\mathit{closes}, \mathit{signedBy}, \mathit{attribution}{=}\bot \text{ by default}),\qquad \mathrm{Topic} = \mathrm{Stage} \times \mathrm{Card}^{*},\ t_0 = (R, [\,])$$

**D25 · `gateOk`** (`:33`) · Lean: `match c.closes with | .D => c.signedBy == .lead && c.attribution == some .named | .V => c.signedBy == .reviewer | .L => c.signedBy == .lead | _ => c.signedBy == .owner`

$$\operatorname{gateOk}(c) \iff \begin{cases} c.\mathit{signedBy} = \mathrm{lead} \ \land\ c.\mathit{attribution} = \mathrm{named} & c.\mathit{closes} = D \\ c.\mathit{signedBy} = \mathrm{reviewer} & c.\mathit{closes} = V \\ c.\mathit{signedBy} = \mathrm{lead} & c.\mathit{closes} = L \\ c.\mathit{signedBy} = \mathrm{owner} & c.\mathit{closes} \in \{R, I, F\} \end{cases}$$

**D26 · `advance`** (`:45`) · Lean: `if c.closes ≠ t.stage then .error … else if !gateOk c then .error … else match t.stage.next with | some s => .ok { stage := s, cards := c :: t.cards } | none => .error "already landed"`

First match wins, and each condition is also written out in full, so no case can be read on its
own as applying more widely:

$$\operatorname{advance}(t, c) = \begin{cases} \mathrm{error}(\texttt{"card closes another stage"}) & \text{if } c.\mathit{closes} \ne t.\mathit{stage} \\ \mathrm{error}(\texttt{"gate not met"}) & \text{if } c.\mathit{closes} = t.\mathit{stage} \ \land\ \neg\operatorname{gateOk}(c) \\ \mathrm{ok}\big((s',\ c :: t.\mathit{cards})\big) & \text{if } c.\mathit{closes} = t.\mathit{stage} \ \land\ \operatorname{gateOk}(c) \ \land\ \operatorname{next}(t.\mathit{stage}) = s' \ \ (s' \in \mathrm{Stage}) \\ \mathrm{error}(\texttt{"already landed"}) & \text{if } c.\mathit{closes} = t.\mathit{stage} = L \ \land\ \operatorname{gateOk}(c)\ \ (\text{that is, } c.\mathit{signedBy} = \mathrm{lead}) \end{cases}$$

The four conditions are mutually exclusive and cover every $(t, c)$: the third needs
$\operatorname{next}(t.\mathit{stage}) \ne \bot$, i.e. $t.\mathit{stage} \ne L$, and the fourth is
exactly the case $t.\mathit{stage} = L$. In particular "already landed" needs a card that closes $L$
**and** is signed by the lead; any other card at $L$ gets one of the first two errors.

English: a card may close only the current stage, must pass that stage's gate, and moves the topic
one stage on. $L$ is terminal (MEASURED: closing $L$ with a lead card gives "already landed"; a
$D$ card with attribution `located` gives "gate not met"). The card list is recorded but never
read by `advance`.

**T25 · `advance_one`** (`:53`) · Lean: `theorem advance_one {t t' : Topic} {c : Card} (h : advance t c = .ok t') : t'.stage.idx = t.stage.idx + 1`

$$\operatorname{advance}(t, c) = \mathrm{ok}(t') \;\Rightarrow\; \operatorname{idx}(t'.\mathit{stage}) = \operatorname{idx}(t.\mathit{stage}) + 1$$

English: every successful advance moves exactly one stage, so no stage is skipped. Relies on: D23, D26.

**T26 · `enter_F`** (`:61`) · Lean: `theorem enter_F {t t' : Topic} {c : Card} (h : advance t c = .ok t') (hF : t'.stage = .F) : c.closes = .D ∧ c.signedBy = .lead ∧ c.attribution = some .named`

$$\operatorname{advance}(t, c) = \mathrm{ok}(t') \ \land\ t'.\mathit{stage} = F \;\Rightarrow\; c.\mathit{closes} = D \ \land\ c.\mathit{signedBy} = \mathrm{lead} \ \land\ c.\mathit{attribution} = \mathrm{named}$$

English: the only way into the fix stage F is a lead-signed card that closes D with a NAMED cause.
Scope: about the single step into F; "every topic at F has such a card in its history" is a
reachability statement that is not yet proved (gap G6). Relies on: D25, D26.

`Fw/Wire.lean` has no theorems (a JSON boundary); it is out of scope for this list.

---

## 5. Gaps found while translating (comment claims vs. what Lean proves)

| id | where | claim in comment | what is proved | suggested Lean (T1 = first wave) |
|---|---|---|---|---|
| G1 | `tick5_eq_countAbove` | legacy >34 ms and tick ≥ 5 "differ exactly on frames in (34, 37.5) ms" | only #tick≥5 = #>37 499 | MEASURED: statement and proof below type-check on Lean 4.35.0 (`lean-scratch/04-mathview/GapProofs.lean`, axioms propext, Classical.choice, Quot.sound). It needs an induction, not one `omega` call. Math: $\operatorname{countAbove}(34000,xs) - \#\{\operatorname{tick}\ge5\} = \#\{i : 34000 < x_i \le 37499\}$; Nat minus never truncates here (tick ≥ 5 ⇒ x ≥ 37500 > 34000). |
| G2 | `swap_better` | "symmetry" | better→worse only | `swap_verdict : verdict d var ctl = (verdict d ctl var).swap` with `swap better = worse`, `worse = better`, others fixed |
| G3 | `step_inv` | "invariant every reachable state keeps" | one step | `reachable_inv : Inv (cs.foldl (fun s c => (step s c).1) {})` (induction on `cs`, 5 lines) |
| G4 | `release_fifo` | "the ranking function for no starvation" | one release step | **Not true as written.** MEASURED: `a` acquires at 0 (ttl 10), `b` queues, `a` renews at 9 and 18, ticks at 15 and 25 → `a` still holds (expires 28) and `b` still waits. Needs a renew cap (e.g. max total hold, or no renew while $Q \ne [\,]$) and then a theorem: under that cap, the waiter's position strictly decreases within a bounded time. |
| G5 | `Cost.UnitCost` | "µs per element" | whole-µs costs | switch units to ns, or use `Rat`, before calibration; monotonicity proofs carry over |
| G6 | `enter_F` | "a topic can only reach F through …" | the single step into F | `reach_F_has_named_D` over `foldl advance` histories (the card list is already kept) |
| G7 | `better_sound` | soundness of the verdict | `lower` only | `better_sound_higher`, from T7 and T12 in 4 lines. MEASURED: checked on Lean 4.35.0 (`GapProofs.lean`, axioms propext, Quot.sound). Math: $\operatorname{verdict}(\mathrm{higher},C,V) = \mathrm{better} \Rightarrow \forall y\in V,\ \forall x\in C:\ x < y$. |

Checked proofs for G1 and G7 (copy into `Fw/Spec/Frames.lean` and `Fw/Spec/Verdict.lean`):

```lean
theorem G1 (xs : List Nat) :
    Frames.countAbove 34000 xs - (xs.filter (5 ≤ Frames.tick ·)).length
      = (xs.filter (fun x => 34000 < x ∧ x ≤ 37499)).length := by
  induction xs with
  | nil => simp [Frames.countAbove]
  | cons x xs ih =>
    have hk := Frames.tick_ge5_iff x
    have hle : (xs.filter (5 ≤ Frames.tick ·)).length ≤ Frames.countAbove 34000 xs := by
      rw [Frames.tick5_eq_countAbove]; exact Frames.countAbove_antitone (by omega) xs
    simp only [Frames.countAbove] at hle ih ⊢
    rw [List.filter_cons, List.filter_cons, List.filter_cons]
    split <;> split <;> split <;> simp_all [List.length_cons] <;> omega

theorem better_sound_higher {ctl var : List Int} (h : verdict .higher ctl var = .better) :
    ∀ y ∈ var, ∀ x ∈ ctl, x < y := by
  rw [verdict_higher_eq_lower_neg] at h
  intro y hy x hx
  have := better_sound h (-y) (List.mem_map.mpr ⟨y, hy, rfl⟩) (-x) (List.mem_map.mpr ⟨x, hx, rfl⟩)
  omega
```

None of these is a bug in the proofs. They are places where the English said more than the
theorem. Translating into exact math is what surfaced them, which is a good argument for the
review loop in §2.5.

---

## 6. Files

- This note: `research/kickoff/10-automation-and-proof/04-lean-to-math.md`
- Sample page: `research/kickoff/10-automation-and-proof/math-view-sample.html` (5 entries,
  KaTeX 0.16.11 from cdnjs; cdnjs's latest is 0.19.0 per `api.cdnjs.com/libraries/KaTeX`. The pin
  is deliberate.) MEASURED in headless Chrome (first version, with the KaTeX stylesheet): all 19
  formulas render with no TeX fallback, and nothing scrolls sideways at 390 px or 1280 px, in dark
  and light themes.
- **Stylesheet decision (after verification):** the page no longer loads `katex.min.css`. The
  Artifact page contract allows external stylesheets only from Google Fonts, so a published copy
  of this page, or of the generated `docs/math/index.html`, would have lost the KaTeX CSS and
  fonts and shown unstyled formulas (INFERRED from the contract; not tested on a published
  artifact). The page now calls `katex.render(…, {output: 'mathml'})`: KaTeX emits MathML only, and
  the browser renders it natively (MathML Core: Chrome 109+, Safari, Firefox), with no CSS or font
  files. **The generator (`docs/math/index.html`) uses the same choice:** `renderToString(tex,
  {output: 'mathml', throwOnError: true})` at build time, so the page needs no script at all. The
  alternative, inlining `katex.min.css` with its fonts as `data:` URIs (about 300 KB), is kept as a
  fallback if MathML spacing turns out too plain. MEASURED after the change: all 19 `data-tex`
  formulas still parse with `throwOnError: true` (`node check.cjs`); not yet re-screenshotted.
- KaTeX check of this note (MEASURED, re-run after the verification fixes with `check2.cjs`, which
  also blanks double-backtick code spans): 62 display and 112 inline formulas, 0 parse failures. The
  check runs `katex@0.16.11` `renderToString(…, {throwOnError: true})` over every `$…$` / `$$…$$`
  outside code spans, which is the same check the `katex` lint in §2.3 would run.
- Prototype: `research/kickoff/10-automation-and-proof/lean-scratch/04-mathview/`. It holds
  `MathView.lean` (exporter + Expr→LaTeX + deep hash), `MathViewMain.lean` (`lake exe mathview
  [--lint]`), `EdgeCases.lean` (the MEASURED `#eval`s above), `out.json` (current export) and a
  verbatim copy of the sketch's `Fw/` (identical by `diff -r`).
  The parent `lean-scratch/` is shared with other notes, so mine is isolated in `04-mathview/`.
