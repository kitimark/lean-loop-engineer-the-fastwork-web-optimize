import Fw.Oracle.Core
import Fw.Oracle.Calibrate
import Fw.Oracle.Redact
import Fw.Oracle.Send
import Fw.Oracle.Questions
import Fw.Oracle.Body
import Fw.Oracle.Wire
import Fw.Oracle.Replay
import Fw.Oracle.ReplayWire
/-!
# Fw.Oracle: typed answers from an outside model, and what we do with them

An oracle question goes to an outside model (TypeSafe's Jev, `POST /v1/systemone`) when a decision cannot be scripted,
and comes back as a typed answer (choice, noul or score) with probabilities. Lean cannot prove an answer is right.
It proves what we do with any answer, and with any failure:

- `Core`: the answer spaces, validation (`validate_sound`, `validate_complete`; a choice's pick must have the highest
  probability), the gate value recomputed from the probabilities, and the policy: total (`policy_total`), every
  failure escalates (`failure_escalates`), no threshold escalates (`uncalibrated_escalates`), a threshold outside
  (0, 1] escalates (`escalate_bad_threshold`), a gate below the threshold escalates (`escalate_below`), and the only
  effects are printing advice or asking a person (`never_irreversible`). It also holds the question record and the
  pinned model.
- `Calibrate`: per option, the least observed gate value at which at least `max 1 k` rows advised as that option
  are right and the precision reaches `q` (`calibrateOpt_sound`, `calibrateOpt_least`); the decision `decideOpt`
  advises an answer only under its own option's threshold (`per_option_sound`), and an option without one escalates
  (`decideOpt_missing`). An option with fewer than `max 1 k` labeled rows, or one the model never answers, gets none
  (`calibrate_none_of_sparse`, `never_answered_none`). `certify` chooses each threshold on the choose part of the
  replay rows and keeps it only when, on the holdout part split off by row id (`heldOut`), that option shows
  `max 1 k` hits and the Wilson score lower bound of its precision (one-sided, `z = 1.645`) is at least `q`
  (`holdout_certified`, `wilsonOk_sound`); holdout rows never move a threshold, they can only remove one
  (`choose_independent_of_holdout`). `evalBy` counts coverage and hits on the holdout part.
- `Redact`: home paths (`/Users/`, `/home/`, `\Users\`, `-Users-`), listed names (any letter case, bounded by
  non-alphanumerics), e-mails, addresses and key-shaped tokens out (`redact_idem`, `no_home_path`, `no_home_forms`);
  size caps on lines, states and stored replies (`redacted_caps`, `storedReply_size`).
- `Body`: the exact request bytes `bodyText q S`, built in Lean.
- `Send`: replay a logged answer; refuse a state with a field the question does not declare; refuse an oversized
  body or an exhausted budget; else send the body Lean built from the redacted state (`pre_send`, `body_from_lean`,
  `send_fields`, `send_no_home`, `send_caps`). A calibration run writes its table only when every labeled row was
  answered (`mayWrite_sound`, `unanswered_no_write`), and `--resume` is checked to fit the run cap
  (`resume_within_cap`). A replay run also stops at 60 sends or 400 000 estimated input tokens (`preRun_send`).
- `Questions`: the registered questions (`ciTriage`, `incidentClass`, `findingSeverity`), the registry and the
  seeded option shuffle (`shuffle_perm`); `Wire`: the `oracle.*` ops.
- `Replay`: the replay sets D1 and D2, the state of a row (`rowState_declared`, `scrubWf_clean`), the stratified
  sample (`sampleHeld_mem`, `d2_pick_le`) sized by the least held-out count that can certify an option
  (`certify_needs_holdout`, `minHoldout_least`), and the score of one arm (`right_le_chosen`, `right_le_labeled`,
  `armPrice`); `ReplayWire`: the ops `oracle.replay`, `oracle.preRun`, `oracle.score`.

Which texts are public enough to send is the caller's choice here; a provenance check per field is a later task.
Accuracy is MEASURED on labeled replay rows (`certify`, `oracle.eval` on the holdout part), never proved.
-/
