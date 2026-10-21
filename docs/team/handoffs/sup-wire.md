# sup-wire handoff

State: branch `worktree-wf_ce9e5e9f-a2d-1`; see `git log` for the head commit. Core.lean unchanged.

Done
- `lean/Fw/Wire/Sup.lean`: JSON codecs for every type `Fw.Sup.Core` puts on the wire (Vec, Ident, Phase, Rsrc, Lease,
  Req, Ticket, Reap Row/Mcp/Input/Target, Sample, State, Ask, Target, Reply, Cmd, Event) and the message
  `Msg = event | cmd | snapshot`, written as `{v, t, body}`. Decoders are total (`Option`).
- Theorems: `decode_encode` (every message), built from `eventOf_eventJson`, `cmdOf_cmdJson`, `replyOf_replyJson`
  (every Why), `stateOf_stateJson` and one lemma per record; `decode_wrong_version` (any v ≠ `version` is refused);
  `decode_version` (anything accepted carries `version`); `whyOf_whyName`, `whyName_nodup`.
- Key lemma `fld_mkObj`: a field of `Json.mkObj l` with distinct keys is `l.lookup k`; record proofs are
  `simp [xOf, xJson, fld_mkObj, List.lookup, <part lemmas>]`, list-free records close by `rfl`.
- Golden `packages/contracts/golden/sup/wire.jsonl` (68 lines `{name, ok, wire}`: every event, every command incl.
  each Target × Sig and each Reply/Why, 3 snapshots, an `Ex.after` trace, 9 refused lines) from
  `lean/scripts/SupWireGolden.lean`; `--check` compares bytes and replays every line through `Json.parse`, `decode`
  and `encode`. Registered in `lean/scripts/check.sh` ("sup wire golden check").

Conventions
- Field names follow `ops.lspReap` for Reap rows, mcps, keep `{pid, at}` and targets.
- A new `Why` (sup-fairness-inv adds `.tooBig`): add a `whyName` row and a `whys` entry (`whyOf_whyName` fails until
  then), bump `version` to 2, regenerate the golden; v1 readers refuse v2 by `decode_wrong_version`.

Open (follow-ups, outside the unit)
- TS or Rust client of the wire checked against wire.jsonl; no runner test replays sup goldens yet.
- `Cfg` is not on the wire (it holds functions); the daemon reads it from its own config.
- Golden replay of `run_eq_fold` against a real fwcore op (sup-model open item).

Read first: `lean/Fw/Wire/Sup.lean` section "Round trips", then `lean/scripts/SupWireGolden.lean`.
