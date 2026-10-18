import Fw.Oracle.Core
import Fw.Oracle.Calibrate
import Fw.Oracle.Redact
import Fw.Oracle.Send
import Fw.Oracle.Triage
import Fw.Oracle.Wire
/-!
# Fw.Oracle: typed answers from an outside model, and what we do with them

An oracle question goes to an outside model (TypeSafe's Jev, `POST /v1/systemone`) when a decision cannot be scripted,
and comes back as a typed answer (choice, noul or score) with probabilities. Lean cannot prove an answer is right.
It proves what we do with any answer, and with any failure:

- `Core`: the answer spaces, validation (`validate_sound`, `validate_complete`), the gate value recomputed from the
  probabilities, and the policy: total (`policy_total`), every failure escalates (`failure_escalates`), no threshold
  escalates (`uncalibrated_escalates`), a gate below the threshold escalates (`escalate_below`), and the only effects
  are printing advice or asking a person (`never_irreversible`).
- `Calibrate`: the least observed threshold reaching a precision target on labeled rows (`calibrate_sound`,
  `calibrate_least`), else none, which escalates everything (`calibrate_none_escalates`).
- `Redact`: home paths, listed names, e-mails, addresses and key-shaped tokens out (`redact_idem`, `no_home_path`).
- `Send`: replay a logged answer, refuse an unredacted state or an exhausted budget, else send (`pre_send`).
- `Triage`: the registered questions and the CI-triage state; `Wire`: the `oracle.*` ops.

Accuracy is MEASURED on labeled replay rows (`Calibrate`), never proved.
-/
