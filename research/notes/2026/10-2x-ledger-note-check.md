# A bad findings-ledger note is refused at the commit and in the dry land, not first at the remote suite

Task ledger-note-check, mistake class c-late-check (m219 hero-exit-gate-clear, m220 cols-probe; incident inc-ledger-note-late).

## Answer
- CONFIRMED (apps/runner/test/ledger-merge.test.ts:80-92): the rule "every note names a finding by its candidate, carries task, field and
  text, keys distinct" ran only in that test. hero-exit-gate-clear wrote field `gate` (no findings field); cols-probe wrote prose as the entry.
- CONFIRMED (before this task): `research/findings/ledger.json` was routed to the preset check by the commit checkmap
  (`lean/Fw/Ops/CheckMap.lean` `findingsLedger_routed`) and to `console-api:compose` by the dry land's local tier (`LandTier.selectLocal`).
  Neither ran the ledger test. The dry land's own `ledgerNoteKeyCheck` judged the (entry, task) key only.
- The commit checkmap already blocks: `scripts/hooks/pre-commit` runs `checkmap.mjs --staged` and exits 1 on any failed command
  (`checkmap.mjs` main: `v.ok ? 0 : 1`, Lean `runOk`). Only `git commit --no-verify` or a missing fwcore (skipped without `--strict`) bypass it.

## What was built
| piece | where | what it decides |
|---|---|---|
| Lean `Check.ledgerNotes`, `ledgerInput` | `lean/Fw/Ops/CheckMap.lean` | the findings ledger among the paths plans `checkmap file ledger <ledger>` |
| theorems | same | `ledgerInput_planned`, `ledgerInput_planStaged`, `findingsLedger_planned` (plan and staged plan, whatever else is staged or deleted), `ledgerInput_not` (other ledgers do not trigger), `plan_covers`/`plan_sound` extended |
| Lean `ledgerNotesReads`, `localTests` third entry | `lean/Fw/Console/LandTier.lean` | the dry land's local tier selects `runner:ledger-notes` (ledger-merge + land-notes tests); `ledger_selects_notes`, `ledgerNotes_reads_ledger`, no fwcore build (`ledgerNotes_no_core`) |
| golden | `packages/contracts/golden/ops/checkmap.jsonl` (3 cases), `golden/console/land-tier-local.jsonl` (5 cases) | TS replays them (`land-tier.test.ts`, `test-checkmap.mjs`) |
| the rule | `apps/runner/src/land-notes.ts` `noteShapeProblems` | TS stand-in (no Lean spec of the shape yet), one rule for the commit check, the dry land and the tests |
| dry land | `ledgerNoteKeyCheck` in `apps/runner/src/land.ts` | also refuses a bad shape, in every dry land |
| fixtures | `apps/runner/test/land-notes.test.ts`, `scripts/test-checkmap.mjs` section 3b | free-text entry, `gate` field, empty text, repeated key refused; real ledger untouched |

## Accepted limits
- `git commit --no-verify` bypasses the hook; the dry land still blocks. No CI runs. The remote suite stays the last line.
- The note rule is a TS stand-in; Lean decides when it runs, not what it judges.

## Found on the way (follow-ups)
- `node scripts/test-checkmap.mjs` is wired to no check.sh job or CI job. It fails today on "all 27 modules of Gen's import closure are inputs":
  `presetInputKey` lists 3 Lean modules, the closure of `Fw.Preset.Gen` is 27. Unrelated to this task, so left as it is.
