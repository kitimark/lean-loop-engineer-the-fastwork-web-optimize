/-!
# CircleCI pilot: pair verdict, credits, stop rule and routing rule (task `circleci-pilot`)
Decides a GitHub job against its CircleCI twin on the same commit, what a CircleCI job costs, when the pilot stops and which provider a lane goes to.
-/
namespace Fw.Ci.Provider

/-- The CI provider a job ran on. -/
inductive Provider where
  | github
  | circleci
deriving DecidableEq, Repr

/-- The machine family of a lane or a resource class. -/
inductive Platform where
  | linuxArm
  | macos
deriving DecidableEq, Repr

/-- The credit pool a resource class draws from. -/
inductive Pool where
  | oss
  | base
deriving DecidableEq, Repr

/-- One resource class with its price and the page it was read from. -/
structure Rate where
  cls : String
  platform : Platform
  pool : Pool
  creditsPerMin : Nat
  free : Bool
  source : String
deriving DecidableEq, Repr

/-- The price list the pilot meets: rates CONFIRMED (`research/notes/2026/10-20-circleci-free-tier.md`, capacity table); the class names `arm.*.gen2` CONFIRMED (accepted by pipelines 15 and 16, the job API reports `arm-medium-gen2` and `arm-large-gen2`; `research/notes/2026/10-20-circleci-pilot.md`), `arm.medium` and `arm.large` are the fallback. -/
def rates : List Rate := [
  ⟨"arm.medium", .linuxArm, .oss, 10, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"arm.large", .linuxArm, .oss, 20, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"arm.medium.gen2", .linuxArm, .oss, 6, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"arm.large.gen2", .linuxArm, .oss, 12, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"m4pro.medium", .macos, .base, 200, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"m4pro.large", .macos, .base, 400, false, "https://circleci.com/pricing/price-list/"⟩]

/-- The rate row of a class name. -/
def rateOf (c : String) : Option Rate := rates.find? (·.cls == c)

/-- The class name as the config writes it, from the name the job API reports (`executor.resource_class`): the API writes dashes (`arm-medium-gen2`, MEASURED on a real job), the config and the price list write dots. -/
def classOfApi (s : String) : String := String.ofList (s.toList.map fun c => if c == '-' then '.' else c)

/-- The API name of every class the pilot runs maps to a price-list row. -/
theorem api_names_priced :
    (["arm-medium-gen2", "arm-large-gen2", "arm-medium", "arm-large"].map fun a => (rateOf (classOfApi a)).isSome) =
      [true, true, true, true] := by decide

/-- A name that is already a config name stays. -/
theorem class_of_api_config_name : classOfApi "arm.medium.gen2" = "arm.medium.gen2" := by decide

/-- The free pool of a pool kind, in credits a month. -/
def poolCredits : Pool → Nat
  | .oss => 400000
  | .base => 30000

/-- Credits of a job: price times duration, rounded up to a whole credit; none for a class not in the price list. -/
def credits (c : String) (durMs : Nat) : Option Nat :=
  (rateOf c).map fun r => (durMs * r.creditsPerMin + 59999) / 60000

/-- The class is in the price list and on the Free plan. -/
def freeClass (c : String) : Bool := (rateOf c).any (·.free)

/-- How a job ended. -/
inductive Conclusion where
  | pass
  | fail
  | notRun
deriving DecidableEq, Repr

/-- A CircleCI job or workflow status as a conclusion: only `success` passes; a job that was cancelled or never ran reached no verdict. -/
def ofCircleStatus (s : String) : Conclusion :=
  if s == "success" then .pass
  else if ["failed", "infrastructure_fail", "timedout", "error", "failing", "unauthorized"].contains s then .fail
  else .notRun

/-- A GitHub job conclusion as a conclusion: only `success` passes; cancelled, skipped and not yet known reached no verdict. -/
def ofGithubConclusion (s : String) : Conclusion :=
  if s == "success" then .pass
  else if ["failure", "timed_out", "startup_failure", "action_required"].contains s then .fail
  else .notRun

/-- The workflow status is final. -/
def circleTerminal (s : String) : Bool :=
  ["success", "failed", "error", "canceled", "not_run", "unauthorized", "infrastructure_fail", "timedout", "terminated-unknown"].contains s

/-- The exit code of a wait over final workflow statuses: 0 all passed, 1 one failed, 4 none failed but not all passed (cancelled, not run). -/
def endCode (sts : List String) : Nat :=
  if sts.all (· == "success") then 0
  else if sts.any (fun s => ["failed", "error", "infrastructure_fail", "timedout", "unauthorized"].contains s) then 1
  else 4

/-- What one poll of `wait` reads: the workflow statuses and the seconds waited against the two limits. -/
structure WaitInput where
  statuses : List String
  waitedS : Nat
  noWorkflowS : Nat
  timeoutS : Nat
deriving DecidableEq, Repr

/-- The exit code of a wait at one poll, none while it goes on: final workflows decide, no workflow after the grace time is 4, a timeout is 3. -/
def waitStep (i : WaitInput) : Option Nat :=
  if i.statuses.isEmpty then
    (if i.noWorkflowS ≤ i.waitedS then some 4 else if i.timeoutS ≤ i.waitedS then some 3 else none)
  else if i.statuses.all circleTerminal then some (endCode i.statuses)
  else if i.timeoutS ≤ i.waitedS then some 3 else none

/-- How a GitHub job name is matched to a pilot job: the whole name, or a matrix name that starts with `pre` and ends with `, <vm>)`. -/
inductive GhName where
  | exact (name : String)
  | matrix (pre vm : String)
deriving DecidableEq, Repr

/-- The name closing a matrix job name of the VM `vm`. -/
def vmSuffix (vm : String) : String := ", " ++ vm ++ ")"

/-- A GitHub job name fits a rule; a matrix rule needs prefix and suffix not to overlap. -/
def ghMatches : GhName → String → Bool
  | .exact n, s => n == s
  | .matrix p vm, s => p.toList.isPrefixOf s.toList && (vmSuffix vm).toList.isSuffixOf s.toList
      && decide (p.length + (vmSuffix vm).length ≤ s.length)

/-- One pilot job: the lane, how its GitHub twin is named, its CircleCI name, whether its verdict is the premise digest, and
whether the job has a `save_cache` step (the ledger reads the job steps of these jobs only). -/
structure JobRow where
  lane : String
  gh : GhName
  circleci : String
  digest : Bool
  savesCache : Bool
deriving DecidableEq, Repr

/-- The GitHub job of the pilot lane against its CircleCI twin. The engine jobs end `exit 0` on both sides, so their verdict is the digest of the premise results. -/
def jobMap : List JobRow := [
  ⟨"premise-tests", .exact "engine (chromium)", "engine-chromium", true, true⟩,
  ⟨"premise-tests", .exact "engine (playwright-webkit)", "engine-playwright-webkit", true, true⟩,
  ⟨"premise-tests", .exact "verdict", "verdict", false, false⟩,
  ⟨"webkit-sim", .matrix "sim (original," "v1", "webkit-sim", false, false⟩]

/-- The CircleCI jobs of the land lane, one per leg of `lean/land-legs.txt` (`.circleci/config.yml`, `land-<leg>`); each has a
`save_cache` step for the Lake cache (task `circleci-lean-cache`). `Fw.Ci.Overflow.landJobs_eq_legs` proves the list equals the legs. -/
def landJobs : List String := ["land-check-sh", "land-suites-a", "land-suites-b", "land-chromium", "land-playwright-webkit"]

/-- The CircleCI job has a `save_cache` step: a pilot job whose row says so, or a land job. A job outside both has none. -/
def savesCacheJob (job : String) : Bool := (jobMap.any fun r => r.circleci == job && r.savesCache) || landJobs.contains job

/-- The pilot job a GitHub job name belongs to. -/
def jobOfGithub (name : String) : Option JobRow := jobMap.find? (ghMatches ·.gh name)

/-- The pilot job (by CircleCI name) is judged by its premise digest. -/
def digestJob (job : String) : Bool := jobMap.any fun r => r.circleci == job && r.digest

/-- One job of one provider on one commit; the durations are milliseconds, the digest is the canonical result lines of the job. -/
structure Run where
  provider : Provider
  job : String
  sha : String
  conclusion : Conclusion
  digest : Option String
  cls : String
  queueMs : Nat
  durMs : Nat
deriving DecidableEq, Repr

/-- The two runs reached the same verdict: equal conclusions and, when both carry a digest, equal digests. -/
def verdictEq (g c : Run) : Bool :=
  g.conclusion == c.conclusion && (match g.digest, c.digest with | some a, some b => a == b | _, _ => true)

/-- The two runs of a digest job carry the same digest. -/
def verdictDigest (g c : Run) : Bool := g.digest.isSome && g.digest == c.digest

/-- The verdict of a pair: the digest for a digest job (its conclusion is `pass` on both sides by construction), else the conclusion. -/
def verdict (g c : Run) : Bool := if digestJob g.job then verdictDigest g c else verdictEq g c

/-- Why two runs are not a pair. -/
inductive Mismatch where
  | providers
  | job
  | sha
  | digest
deriving DecidableEq, Repr

/-- The first reason two runs are not a GitHub/CircleCI pair of the same job on the same commit; a job judged by its digest needs both digests. -/
def pairCheck (g c : Run) : Option Mismatch :=
  if g.provider != .github || c.provider != .circleci then some .providers
  else if g.job != c.job then some .job
  else if g.sha != c.sha then some .sha
  else if digestJob g.job && (g.digest.isNone || c.digest.isNone) then some .digest
  else none

/-- What the pilot records for one pair. -/
structure Comparison where
  finding : Bool
  ratioPermille : Option Nat
  queueGithubMs : Nat
  queueCircleMs : Nat
  credits : Option Nat
deriving DecidableEq, Repr

/-- CircleCI duration over GitHub duration in thousandths, rounded down; none when GitHub took no time. -/
def ratioPermille (g c : Run) : Option Nat :=
  if g.durMs = 0 then none else some (c.durMs * 1000 / g.durMs)

/-- Compare a pair: a verdict (`verdict`) that differs is a finding, with the duration ratio, both queue times and the CircleCI credits. -/
def compare (g c : Run) : Except Mismatch Comparison :=
  match pairCheck g c with
  | some m => .error m
  | none => .ok { finding := !verdict g c, ratioPermille := ratioPermille g c,
                  queueGithubMs := g.queueMs, queueCircleMs := c.queueMs, credits := credits c.cls c.durMs }

/-- The job-length cap of the Free plan, ms. -/
def capMs : Nat := 3600000

/-- The longest queue wait the pilot tolerates, ms. -/
def queueMaxMs : Nat := 600000

def storageAllowMilli : Nat := 2000

def storageStopMilli : Nat := 1000

def overageCreditsPerGbMonth : Nat := 420

def milliOfByteDays (byteDays : Nat) : Nat := (byteDays * 1000 + 30 * 1000000000 - 1) / (30 * 1000000000)

/-- Storage of a save in thousandths of a GB-month: bytes times retention days over 30 days, rounded up. -/
def storageMilli (bytes days : Nat) : Nat := milliOfByteDays (bytes * days)

/-- What the `save_cache` step of one job left in the CircleCI cache, as its job steps record it. `absent`: the job ran no
save step (it halted before it: the restored cache was current). `skipped`: the step found the key already stored and
uploaded nothing. `stored t`: the step uploaded an archive of `t` tenths of a MiB, the one decimal CircleCI prints. -/
inductive CacheSave where
  | absent
  | skipped
  | stored (tenthsMiB : Nat)
deriving DecidableEq, Repr

/-- Bytes a save added to the cache. The printed size is rounded to a tenth of a MiB, so one more tenth is added: the count is
an upper bound whichever way CircleCI rounds. -/
def cacheSavedBytes : CacheSave → Nat
  | .absent => 0
  | .skipped => 0
  | .stored t => ((t + 1) * 1048576 + 9) / 10

/-- Cache bytes a pipeline added: the sum over the saves of its jobs. -/
def cachePipelineBytes (saves : List CacheSave) : Nat := (saves.map cacheSavedBytes).sum

inductive StoreKind where
  | cache
  | workspace
  | artifact
deriving DecidableEq, Repr

def retentionDays : StoreKind → Nat
  | .cache => 15
  | .workspace => 15
  | .artifact => 30

def windowMs : Nat := 30 * 86400000

structure LedgerRow where
  atMs : Option Nat
  cache : Nat
  workspace : Nat
  artifacts : Nat
deriving DecidableEq, Repr

def LedgerRow.bytes (r : LedgerRow) : Nat := r.cache + r.workspace + r.artifacts

def LedgerRow.byteDays (r : LedgerRow) : Nat :=
  r.cache * retentionDays .cache + r.workspace * retentionDays .workspace + r.artifacts * retentionDays .artifact

def LedgerRow.inWindow (now : Nat) (r : LedgerRow) : Bool :=
  match r.atMs with
  | none => true
  | some t => decide (now ≤ t + windowMs)

def storageNow (rows : List LedgerRow) (now : Nat) : Nat :=
  milliOfByteDays (((rows.filter (LedgerRow.inWindow now)).map LedgerRow.byteDays).sum)

def storageCredits (milli : Nat) : Nat := ((milli - storageAllowMilli) * overageCreditsPerGbMonth + 999) / 1000

def ownSaveMilli : Nat := storageMilli (cacheSavedBytes (.stored 4481)) (retentionDays .cache)

def ledger20261021 : LedgerRow := ⟨none, 1294676789, 73728, 1668534⟩

inductive SavePolicy where
  | perSource
  | daily
deriving DecidableEq, Repr

def dayMs : Nat := 86400000

def lakeKeyTail : SavePolicy → String → Nat → String
  | .perSource, src, _ => src
  | .daily, _, now => "day-" ++ toString (now / dayMs)

def savesPerDay : SavePolicy → Nat
  | .perSource => 4
  | .daily => 1

def policyMilliPerDay (p : SavePolicy) : Nat := savesPerDay p * ownSaveMilli

def policyWindowCredits (p : SavePolicy) : Nat := storageCredits (31 * policyMilliPerDay p)

/-- Why the pilot stops. -/
inductive Stop where
  | cap
  | queue
  | storage
deriving DecidableEq, Repr

/-- What the stop rule reads. -/
structure StopInput where
  durMs : Nat
  queueMs : Nat
  storageMilli : Nat
deriving DecidableEq, Repr

/-- Every reason the pilot stops, in the order cap, queue, storage. -/
def stops (i : StopInput) : List Stop :=
  (if capMs ≤ i.durMs then [Stop.cap] else []) ++ (if queueMaxMs < i.queueMs then [Stop.queue] else [])
    ++ (if storageStopMilli < i.storageMilli then [Stop.storage] else [])

/-- The pilot stops. -/
def stop (i : StopInput) : Bool := !(stops i).isEmpty

def landStops (i : StopInput) : List Stop :=
  (if capMs ≤ i.durMs then [Stop.cap] else []) ++ (if queueMaxMs < i.queueMs then [Stop.queue] else [])

/-- What the routing rule reads for one lane. -/
structure RouteInput where
  lane : String
  platform : Platform
  cls : String
  allow : List String
  ghDegraded : Bool
  estMs : Nat
  creditsLeft : Nat
deriving DecidableEq, Repr

/-- The class is on the Free plan, on the lane's platform, and the estimated run fits the credits left. -/
def affordable (i : RouteInput) : Bool :=
  match rateOf i.cls with
  | none => false
  | some r => r.free && r.platform == i.platform && decide ((i.estMs * r.creditsPerMin + 59999) / 60000 ≤ i.creditsLeft)

/-- Where a lane runs: CircleCI only for an allowlisted lane on an affordable free class, and a macOS lane only while GitHub Actions is degraded. -/
def route (i : RouteInput) : Provider :=
  if i.allow.contains i.lane && affordable i && (i.platform != .macos || i.ghDegraded) then .circleci else .github

/-- A checkout-key kind the clone can use. -/
def usableKeyKind (k : String) : Bool := k == "deploy-key" || k == "github-user-key"

/-- A `Checkout code` step status as a clone result: `success` worked, `failed` did not, anything else says nothing. -/
def checkoutOfStatus (s : String) : Option Bool :=
  if s == "success" then some true else if s == "failed" then some false else none

/-- What the key check reads: the usable keys of the key list (none: the list answered 403) and the newest clone result. -/
structure KeyInput where
  keys : Option Nat
  checkout : Option Bool
deriving DecidableEq, Repr

/-- The checkout key is there, is not, or cannot be told. -/
inductive KeyVerdict where
  | ok
  | missing
  | unknown
deriving DecidableEq, Repr

/-- A readable key list decides; an unreadable one falls back to the newest clone result. -/
def keyVerdict (i : KeyInput) : KeyVerdict :=
  match i.keys with
  | some n => if 0 < n then .ok else .missing
  | none =>
    match i.checkout with
    | some true => .ok
    | some false => .missing
    | none => .unknown

/-- A pipeline may start only on `ok`. -/
def keyProceed (i : KeyInput) : Bool := keyVerdict i == .ok

/-! ## Rate table -/

theorem rates_cls_nodup : (rates.map (·.cls)).Nodup := by decide

theorem rate_arm_medium_gen2 : credits "arm.medium.gen2" 60000 = some 6 := by decide

theorem rate_arm_large_gen2 : credits "arm.large.gen2" 60000 = some 12 := by decide

theorem rate_m4pro_medium : credits "m4pro.medium" 60000 = some 200 := by decide

theorem unknown_class_no_credits (c : String) (h : rateOf c = none) (d : Nat) : credits c d = none := by
  simp [credits, h]

theorem no_such_class : rateOf "no.such.class" = none := by decide

theorem not_listed_not_free (c : String) (h : rateOf c = none) : freeClass c = false := by
  simp [freeClass, h]

theorem credits_exact_minute (c : String) (r : Rate) (h : rateOf c = some r) (m : Nat) :
    credits c (m * 60000) = some (m * r.creditsPerMin) := by
  simp only [credits, h, Option.map]
  congr 1
  have : m * 60000 * r.creditsPerMin = (m * r.creditsPerMin) * 60000 := by
    rw [Nat.mul_right_comm]
  rw [this]
  omega

theorem credits_cover (c : String) (r : Rate) (n : Nat) (h : rateOf c = some r) (d : Nat)
    (hc : credits c d = some n) : d * r.creditsPerMin ≤ n * 60000 := by
  simp only [credits, h, Option.map, Option.some.injEq] at hc
  omega

theorem credits_tight (c : String) (r : Rate) (n : Nat) (h : rateOf c = some r) (d : Nat)
    (hc : credits c d = some n) : n * 60000 < d * r.creditsPerMin + 60000 := by
  simp only [credits, h, Option.map, Option.some.injEq] at hc
  omega

theorem credits_zero_dur (c : String) (r : Rate) (h : rateOf c = some r) : credits c 0 = some 0 := by
  simp [credits, h]

theorem credits_mono (c : String) (r : Rate) (h : rateOf c = some r) (d e : Nat) (hde : d ≤ e) :
    ∃ n m, credits c d = some n ∧ credits c e = some m ∧ n ≤ m := by
  refine ⟨(d * r.creditsPerMin + 59999) / 60000, (e * r.creditsPerMin + 59999) / 60000,
    by simp [credits, h], by simp [credits, h], ?_⟩
  have : d * r.creditsPerMin ≤ e * r.creditsPerMin := Nat.mul_le_mul_right _ hde
  omega

/-! ## Pair verdict -/

theorem verdictEq_refl (r : Run) : verdictEq r r = true := by
  unfold verdictEq
  cases r.digest <;> simp

theorem finding_of_conclusion_ne (g c : Run) (h : g.conclusion ≠ c.conclusion) : verdictEq g c = false := by
  simp [verdictEq, h]

theorem finding_of_digest_ne (g c : Run) (a b : String) (hg : g.digest = some a) (hc : c.digest = some b)
    (h : a ≠ b) : verdictEq g c = false := by
  simp [verdictEq, hg, hc, h]

theorem verdictEq_of_agree (g c : Run) (h : g.conclusion = c.conclusion)
    (hd : ∀ a b, g.digest = some a → c.digest = some b → a = b) : verdictEq g c = true := by
  unfold verdictEq
  cases hg : g.digest <;> cases hc : c.digest <;> simp [h]
  exact hd _ _ hg hc

theorem verdictEq_iff (g c : Run) : verdictEq g c = true ↔
    g.conclusion = c.conclusion ∧ ∀ a b, g.digest = some a → c.digest = some b → a = b := by
  constructor
  · intro h
    unfold verdictEq at h
    simp only [Bool.and_eq_true, beq_iff_eq] at h
    refine ⟨h.1, fun a b ha hb => ?_⟩
    have := h.2
    simp [ha, hb] at this
    exact this
  · rintro ⟨h, hd⟩
    exact verdictEq_of_agree g c h hd

theorem verdictEq_comm (g c : Run) : verdictEq g c = verdictEq c g := by
  apply Bool.eq_iff_iff.mpr
  rw [verdictEq_iff, verdictEq_iff]
  constructor
  · rintro ⟨h, hd⟩
    exact ⟨h.symm, fun a b ha hb => (hd b a hb ha).symm⟩
  · rintro ⟨h, hd⟩
    exact ⟨h.symm, fun a b ha hb => (hd b a hb ha).symm⟩

theorem pairCheck_providers (g c : Run) (h : g.provider ≠ .github ∨ c.provider ≠ .circleci) :
    pairCheck g c = some .providers := by
  rcases h with h | h <;> simp [pairCheck, h]

theorem pairCheck_job (g c : Run) (hg : g.provider = .github) (hc : c.provider = .circleci) (h : g.job ≠ c.job) :
    pairCheck g c = some .job := by
  simp [pairCheck, hg, hc, h]

theorem pairCheck_sha (g c : Run) (hg : g.provider = .github) (hc : c.provider = .circleci) (hj : g.job = c.job)
    (h : g.sha ≠ c.sha) : pairCheck g c = some .sha := by
  simp [pairCheck, hg, hc, hj, h]

theorem pairCheck_digest (g c : Run) (hg : g.provider = .github) (hc : c.provider = .circleci) (hj : g.job = c.job)
    (hs : g.sha = c.sha) (hd : digestJob g.job = true) (h : g.digest = none ∨ c.digest = none) :
    pairCheck g c = some .digest := by
  rw [hj] at hd
  rcases h with h | h <;> simp [pairCheck, hg, hc, hj, hs, hd, h]

theorem pairCheck_none_iff (g c : Run) : pairCheck g c = none ↔
    g.provider = .github ∧ c.provider = .circleci ∧ g.job = c.job ∧ g.sha = c.sha ∧
      (digestJob g.job = true → g.digest.isSome = true ∧ c.digest.isSome = true) := by
  unfold pairCheck
  by_cases h1 : g.provider = .github <;> by_cases h2 : c.provider = .circleci <;>
    by_cases h3 : g.job = c.job <;> by_cases h4 : g.sha = c.sha <;> by_cases h5 : digestJob g.job = true <;>
    cases hg : g.digest <;> cases hc : c.digest <;> simp [h1, h2, h3, h4, h5]

theorem compare_ok_iff (g c : Run) : (∃ k, compare g c = .ok k) ↔ pairCheck g c = none := by
  unfold compare
  cases h : pairCheck g c <;> simp

theorem compare_error (g c : Run) (m : Mismatch) (h : pairCheck g c = some m) : compare g c = .error m := by
  simp [compare, h]

theorem finding_iff (g c : Run) (k : Comparison) (h : compare g c = .ok k) :
    k.finding = true ↔ verdict g c = false := by
  unfold compare at h
  cases hp : pairCheck g c <;> simp [hp] at h
  subst h
  simp

theorem compare_queues (g c : Run) (k : Comparison) (h : compare g c = .ok k) :
    k.queueGithubMs = g.queueMs ∧ k.queueCircleMs = c.queueMs := by
  unfold compare at h
  cases hp : pairCheck g c <;> simp [hp] at h
  subst h
  simp

theorem compare_credits (g c : Run) (k : Comparison) (h : compare g c = .ok k) :
    k.credits = credits c.cls c.durMs := by
  unfold compare at h
  cases hp : pairCheck g c <;> simp [hp] at h
  subst h
  rfl

theorem ratio_none_iff (g c : Run) : ratioPermille g c = none ↔ g.durMs = 0 := by
  unfold ratioPermille
  by_cases h : g.durMs = 0 <;> simp [h]

theorem ratio_spec (g c : Run) (r : Nat) (h : ratioPermille g c = some r) :
    r * g.durMs ≤ c.durMs * 1000 ∧ c.durMs * 1000 < (r + 1) * g.durMs := by
  unfold ratioPermille at h
  by_cases h0 : g.durMs = 0
  · simp [h0] at h
  · simp only [h0, ite_false, Option.some.injEq] at h
    subst h
    have hp : 0 < g.durMs := Nat.pos_of_ne_zero h0
    constructor
    · exact Nat.div_mul_le_self _ _
    · have := Nat.lt_mul_div_succ (c.durMs * 1000) hp
      rw [Nat.mul_comm (c.durMs * 1000 / g.durMs + 1)]
      exact this

theorem ratio_same_duration (g c : Run) (hp : 0 < g.durMs) (h : c.durMs = g.durMs) :
    ratioPermille g c = some 1000 := by
  have h0 : g.durMs ≠ 0 := Nat.pos_iff_ne_zero.mp hp
  simp [ratioPermille, h0, h, Nat.mul_div_cancel_left 1000 hp]

/-! ## Stop rule -/

theorem storageMilli_cache : storageMilli 1030000000 15 = 515 := by decide

theorem storageMilli_zero (d : Nat) : storageMilli 0 d = 0 := by
  simp [storageMilli, milliOfByteDays]

theorem storageStop_le_allow : storageStopMilli ≤ storageAllowMilli := by decide

theorem retention_le_30 (k : StoreKind) : retentionDays k ≤ 30 := by cases k <;> decide

theorem milliOfByteDays_mono {a b : Nat} (h : a ≤ b) : milliOfByteDays a ≤ milliOfByteDays b := by
  unfold milliOfByteDays
  exact Nat.div_le_div_right (by omega)

theorem byteDays_le (r : LedgerRow) : r.byteDays ≤ r.bytes * 30 := by
  simp only [LedgerRow.byteDays, LedgerRow.bytes, retentionDays]
  omega

theorem storageNow_le_hold30 (rows : List LedgerRow) (now : Nat) :
    storageNow rows now ≤ storageMilli ((rows.map LedgerRow.bytes).sum) 30 := by
  unfold storageNow storageMilli
  apply milliOfByteDays_mono
  induction rows with
  | nil => simp
  | cons r rs ih =>
    have := byteDays_le r
    rw [List.filter_cons]
    split <;> simp only [List.map_cons, List.sum_cons, Nat.add_mul] <;> omega

theorem storageNow_old_row (r : LedgerRow) (rows : List LedgerRow) (now t : Nat) (h : r.atMs = some t)
    (ho : t + windowMs < now) : storageNow (r :: rows) now = storageNow rows now := by
  have : ¬ now ≤ t + windowMs := by omega
  simp [storageNow, LedgerRow.inWindow, h, this]

theorem storageNow_untimed (r : LedgerRow) (rows : List LedgerRow) (now : Nat) (h : r.atMs = none) :
    storageNow (r :: rows) now = milliOfByteDays (r.byteDays + ((rows.filter (LedgerRow.inWindow now)).map LedgerRow.byteDays).sum) := by
  simp [storageNow, LedgerRow.inWindow, h]

theorem storageCredits_within_allow (m : Nat) (h : m ≤ storageAllowMilli) : storageCredits m = 0 := by
  simp only [storageCredits, overageCreditsPerGbMonth]
  rw [Nat.sub_eq_zero_of_le h]

theorem storageCredits_mono {a b : Nat} (h : a ≤ b) : storageCredits a ≤ storageCredits b := by
  unfold storageCredits
  exact Nat.div_le_div_right (by have := Nat.mul_le_mul_right overageCreditsPerGbMonth (Nat.sub_le_sub_right h storageAllowMilli); omega)

theorem storageCredits_one_gb_month : storageCredits (storageAllowMilli + 1000) = 420 := by decide

theorem ownSaveMilli_eq : ownSaveMilli = 235 := by decide

theorem storage_20261021 (now : Nat) : storageNow [ledger20261021] now = 650 := by
  rw [storageNow_untimed _ _ _ rfl, List.filter_nil]
  decide

theorem storage_20261021_under_stop (now : Nat) : storageNow [ledger20261021] now + ownSaveMilli < storageStopMilli := by
  rw [storage_20261021, ownSaveMilli_eq]
  decide

theorem hold30_20261021 : storageMilli ledger20261021.bytes 30 = 1297 ∧ storageStopMilli < 1297 := by decide

theorem daily_same_day (src src' : String) (t t' : Nat) (h : t / dayMs = t' / dayMs) :
    lakeKeyTail .daily src t = lakeKeyTail .daily src' t' := by
  simp [lakeKeyTail, h]

theorem daily_window_days (now t : Nat) (h1 : now ≤ t + windowMs) (h2 : t ≤ now) :
    t / dayMs ≤ now / dayMs ∧ now / dayMs ≤ t / dayMs + 30 := by
  unfold windowMs at h1
  unfold dayMs
  omega

theorem policyMilliPerDay_daily : policyMilliPerDay .daily = 235 := by decide

theorem policyMilliPerDay_perSource : policyMilliPerDay .perSource = 940 := by decide

theorem policyWindowCredits_daily : policyWindowCredits .daily = 2220 := by decide

theorem policyWindowCredits_perSource : policyWindowCredits .perSource = 11399 := by decide

theorem savesCacheJob_engine_chromium : savesCacheJob "engine-chromium" = true := by decide

theorem savesCacheJob_engine_webkit : savesCacheJob "engine-playwright-webkit" = true := by decide

theorem savesCacheJob_verdict : savesCacheJob "verdict" = false := by decide

theorem savesCacheJob_sim : savesCacheJob "webkit-sim" = false := by decide

theorem savesCacheJob_unknown : savesCacheJob "probe" = false := by decide

theorem savesCacheJob_land_check_sh : savesCacheJob "land-check-sh" = true := by decide

theorem savesCacheJob_land_suites_a : savesCacheJob "land-suites-a" = true := by decide

theorem savesCacheJob_land_suites_b : savesCacheJob "land-suites-b" = true := by decide

theorem savesCacheJob_land_chromium : savesCacheJob "land-chromium" = true := by decide

theorem savesCacheJob_land_playwright_webkit : savesCacheJob "land-playwright-webkit" = true := by decide

/-- The two branches of `savesCacheJob` do not overlap: no land job is a pilot job of the map, so a land job is counted by the land branch alone. -/
theorem landJobs_not_in_jobMap : ∀ j ∈ landJobs, ∀ r ∈ jobMap, r.circleci ≠ j := by decide

theorem cacheSavedBytes_absent : cacheSavedBytes .absent = 0 := rfl

theorem cacheSavedBytes_skipped : cacheSavedBytes .skipped = 0 := rfl

/-- A stored save counts at least the printed size. -/
theorem cacheSavedBytes_stored_ge (t : Nat) : t * 1048576 ≤ 10 * cacheSavedBytes (.stored t) := by
  simp only [cacheSavedBytes]
  omega

/-- A stored save counts at most the printed size plus two tenths of a MiB. -/
theorem cacheSavedBytes_stored_le (t : Nat) : 10 * cacheSavedBytes (.stored t) ≤ (t + 2) * 1048576 := by
  simp only [cacheSavedBytes]
  omega

/-- The 9.3 MiB archive of the first Arm pipeline counts 9856615 bytes: 10 thousandths of a GB-month. -/
theorem cacheSavedBytes_first : cacheSavedBytes (.stored 93) = 9856615 := by decide

theorem storageMilli_first_save : storageMilli (cacheSavedBytes (.stored 93)) 30 = 10 := by decide

/-- A pipeline whose jobs saved nothing adds no cache bytes, whatever the number of jobs. -/
theorem cachePipelineBytes_unsaved (saves : List CacheSave) (h : ∀ s ∈ saves, s = .absent ∨ s = .skipped) :
    cachePipelineBytes saves = 0 := by
  unfold cachePipelineBytes
  induction saves with
  | nil => rfl
  | cons s rest ih =>
    have hs := h s (List.mem_cons_self ..)
    have hr := ih (fun x hx => h x (List.mem_cons_of_mem _ hx))
    rcases hs with rfl | rfl <;> simp_all [cacheSavedBytes]

/-- The cost of the 108-thousandths pipeline: two jobs each counted the 53.6 MB store, saved or not. -/
theorem storageMilli_old_pipeline : storageMilli (2 * 53637120) 30 = 108 := by decide

theorem mem_cap_iff (i : StopInput) : Stop.cap ∈ stops i ↔ capMs ≤ i.durMs := by
  unfold stops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;>
    by_cases h3 : storageStopMilli < i.storageMilli <;> simp [h1, h2, h3]

theorem mem_queue_iff (i : StopInput) : Stop.queue ∈ stops i ↔ queueMaxMs < i.queueMs := by
  unfold stops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;>
    by_cases h3 : storageStopMilli < i.storageMilli <;> simp [h1, h2, h3]

theorem mem_storage_iff (i : StopInput) : Stop.storage ∈ stops i ↔ storageStopMilli < i.storageMilli := by
  unfold stops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;>
    by_cases h3 : storageStopMilli < i.storageMilli <;> simp [h1, h2, h3]

theorem stop_of_cap (i : StopInput) (h : capMs ≤ i.durMs) : stop i = true := by
  have := (mem_cap_iff i).mpr h
  unfold stop
  cases hs : stops i <;> simp_all

theorem stop_of_queue (i : StopInput) (h : queueMaxMs < i.queueMs) : stop i = true := by
  have := (mem_queue_iff i).mpr h
  unfold stop
  cases hs : stops i <;> simp_all

theorem stop_of_storage (i : StopInput) (h : storageStopMilli < i.storageMilli) : stop i = true := by
  have := (mem_storage_iff i).mpr h
  unfold stop
  cases hs : stops i <;> simp_all

theorem stop_iff (i : StopInput) : stop i = true ↔
    capMs ≤ i.durMs ∨ queueMaxMs < i.queueMs ∨ storageStopMilli < i.storageMilli := by
  constructor
  · intro h
    unfold stop at h
    cases hs : stops i with
    | nil => simp [hs] at h
    | cons s t =>
      cases s
      · exact Or.inl ((mem_cap_iff i).mp (by simp [hs]))
      · exact Or.inr (Or.inl ((mem_queue_iff i).mp (by simp [hs])))
      · exact Or.inr (Or.inr ((mem_storage_iff i).mp (by simp [hs])))
  · rintro (h | h | h)
    · exact stop_of_cap i h
    · exact stop_of_queue i h
    · exact stop_of_storage i h

theorem storage_not_mem_landStops (i : StopInput) : Stop.storage ∉ landStops i := by
  unfold landStops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;> simp [h1, h2]

theorem landStops_eq_filter (i : StopInput) : landStops i = (stops i).filter (· != Stop.storage) := by
  unfold landStops stops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;>
    by_cases h3 : storageStopMilli < i.storageMilli <;> simp [h1, h2, h3]

theorem landStops_storage_free (i : StopInput) (m : Nat) : landStops { i with storageMilli := m } = landStops i := rfl

theorem mem_landStops_cap_iff (i : StopInput) : Stop.cap ∈ landStops i ↔ capMs ≤ i.durMs := by
  unfold landStops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;> simp [h1, h2]

theorem mem_landStops_queue_iff (i : StopInput) : Stop.queue ∈ landStops i ↔ queueMaxMs < i.queueMs := by
  unfold landStops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;> simp [h1, h2]

theorem landStops_eq_stops (i : StopInput) (h : i.storageMilli ≤ storageStopMilli) : landStops i = stops i := by
  unfold landStops stops
  simp [Nat.not_lt.mpr h]

theorem no_stop_within_limits (i : StopInput) (h1 : i.durMs < capMs) (h2 : i.queueMs ≤ queueMaxMs)
    (h3 : i.storageMilli ≤ storageStopMilli) : stop i = false := by
  have : ¬ stop i = true := by
    rw [stop_iff]
    omega
  simpa using this

theorem stop_mono_dur (i : StopInput) (d : Nat) (h : i.durMs ≤ d) (hs : stop i = true) :
    stop { i with durMs := d } = true := by
  rw [stop_iff] at hs ⊢
  simp only
  omega

/-! ## Routing rule -/

theorem route_iff (i : RouteInput) : route i = .circleci ↔
    i.allow.contains i.lane = true ∧ affordable i = true ∧ (i.platform != .macos || i.ghDegraded) = true := by
  unfold route
  split <;> simp_all

theorem route_github_iff (i : RouteInput) : route i = .github ↔ ¬ route i = .circleci := by
  cases h : route i <;> simp

theorem route_circleci_allowlisted (i : RouteInput) (h : route i = .circleci) : i.lane ∈ i.allow := by
  have := ((route_iff i).mp h).1
  simpa using this

theorem route_circleci_affordable (i : RouteInput) (h : route i = .circleci) : affordable i = true :=
  ((route_iff i).mp h).2.1

theorem route_circleci_free_class (i : RouteInput) (h : route i = .circleci) : freeClass i.cls = true := by
  have ha := route_circleci_affordable i h
  unfold affordable at ha
  unfold freeClass
  cases hr : rateOf i.cls with
  | none => simp [hr] at ha
  | some r =>
    simp only [hr, Bool.and_eq_true] at ha
    simp [ha.1.1]

theorem route_circleci_platform (i : RouteInput) (h : route i = .circleci) :
    ∃ r, rateOf i.cls = some r ∧ r.platform = i.platform := by
  have ha := route_circleci_affordable i h
  unfold affordable at ha
  cases hr : rateOf i.cls with
  | none => simp [hr] at ha
  | some r =>
    simp only [hr, Bool.and_eq_true, beq_iff_eq] at ha
    exact ⟨r, rfl, ha.1.2⟩

theorem route_circleci_fits (i : RouteInput) (h : route i = .circleci) :
    ∃ n, credits i.cls i.estMs = some n ∧ n ≤ i.creditsLeft := by
  have ha := route_circleci_affordable i h
  unfold affordable at ha
  cases hr : rateOf i.cls with
  | none => simp [hr] at ha
  | some r =>
    simp only [hr, Bool.and_eq_true, decide_eq_true_eq] at ha
    exact ⟨_, by simp [credits, hr], ha.2⟩

theorem macos_needs_degraded (i : RouteInput) (hp : i.platform = .macos) (h : route i = .circleci) :
    i.ghDegraded = true := by
  have := ((route_iff i).mp h).2.2
  simpa [hp] using this

theorem macos_healthy_github (i : RouteInput) (hp : i.platform = .macos) (hg : i.ghDegraded = false) :
    route i = .github := by
  rw [route_github_iff]
  intro h
  have := macos_needs_degraded i hp h
  simp [hg] at this

theorem empty_allow_github (i : RouteInput) (h : i.allow = []) : route i = .github := by
  rw [route_github_iff]
  intro hc
  have := route_circleci_allowlisted i hc
  simp [h] at this

theorem not_allowlisted_github (i : RouteInput) (h : i.lane ∉ i.allow) : route i = .github := by
  rw [route_github_iff]
  intro hc
  exact h (route_circleci_allowlisted i hc)

theorem unaffordable_github (i : RouteInput) (h : affordable i = false) : route i = .github := by
  rw [route_github_iff]
  intro hc
  have := route_circleci_affordable i hc
  simp [h] at this

theorem route_linux_iff (i : RouteInput) (hp : i.platform = .linuxArm) :
    route i = .circleci ↔ i.lane ∈ i.allow ∧ affordable i = true := by
  rw [route_iff]
  simp [hp]

theorem route_macos_iff (i : RouteInput) (hp : i.platform = .macos) :
    route i = .circleci ↔ i.lane ∈ i.allow ∧ affordable i = true ∧ i.ghDegraded = true := by
  rw [route_iff]
  simp [hp]

theorem route_paid_class_github (i : RouteInput) (r : Rate) (h : rateOf i.cls = some r) (hf : r.free = false) :
    route i = .github := by
  apply unaffordable_github
  simp [affordable, h, hf]

theorem route_unknown_class_github (i : RouteInput) (h : rateOf i.cls = none) : route i = .github := by
  apply unaffordable_github
  simp [affordable, h]

theorem affordable_mono (i : RouteInput) (n : Nat) (h : affordable i = true) (hn : i.creditsLeft ≤ n) :
    affordable { i with creditsLeft := n } = true := by
  unfold affordable at h ⊢
  cases hr : rateOf i.cls with
  | none => simp [hr] at h
  | some r =>
    simp only [hr, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    exact ⟨h.1, Nat.le_trans h.2 hn⟩

theorem route_mono_credits (i : RouteInput) (n : Nat) (h : route i = .circleci) (hn : i.creditsLeft ≤ n) :
    route { i with creditsLeft := n } = .circleci := by
  have h' := (route_iff i).mp h
  rw [route_iff]
  exact ⟨h'.1, affordable_mono i n h'.2.1 hn, h'.2.2⟩

/-! ## Statuses and the wait rule -/

theorem ofCircleStatus_pass_iff (s : String) : ofCircleStatus s = .pass ↔ s = "success" := by
  unfold ofCircleStatus
  split
  · simp_all
  · split <;> simp_all

theorem ofGithubConclusion_pass_iff (s : String) : ofGithubConclusion s = .pass ↔ s = "success" := by
  unfold ofGithubConclusion
  split
  · simp_all
  · split <;> simp_all

theorem circle_canceled_not_pass : ofCircleStatus "canceled" = .notRun := by decide

theorem circle_not_run_not_pass : ofCircleStatus "not_run" = .notRun := by decide

theorem circle_queued_not_pass : ofCircleStatus "queued" = .notRun := by decide

theorem circle_running_not_pass : ofCircleStatus "running" = .notRun := by decide

theorem circle_failed_fails : ofCircleStatus "failed" = .fail := by decide

theorem circle_infra_fails : ofCircleStatus "infrastructure_fail" = .fail := by decide

theorem circle_timedout_fails : ofCircleStatus "timedout" = .fail := by decide

theorem github_cancelled_not_pass : ofGithubConclusion "cancelled" = .notRun := by decide

theorem github_skipped_not_pass : ofGithubConclusion "skipped" = .notRun := by decide

theorem github_unknown_not_pass : ofGithubConclusion "" = .notRun := by decide

theorem github_failure_fails : ofGithubConclusion "failure" = .fail := by decide

theorem github_timed_out_fails : ofGithubConclusion "timed_out" = .fail := by decide

theorem terminal_success : circleTerminal "success" = true := by decide

theorem running_not_terminal : circleTerminal "running" = false := by decide

theorem on_hold_not_terminal : circleTerminal "on_hold" = false := by decide

theorem endCode_zero_iff (sts : List String) : endCode sts = 0 ↔ sts.all (· == "success") = true := by
  unfold endCode
  by_cases h : sts.all (· == "success") = true <;> simp [h]
  split <;> simp

theorem endCode_canceled (sts : List String) (h : "canceled" ∈ sts) : endCode sts ≠ 0 := by
  rw [Ne, endCode_zero_iff]
  intro hall
  have := List.all_eq_true.mp hall "canceled" h
  simp at this

theorem endCode_failed (sts : List String) (h : "failed" ∈ sts) : endCode sts = 1 := by
  have hn : sts.all (· == "success") = false := by
    cases hc : sts.all (· == "success")
    · rfl
    · have := List.all_eq_true.mp hc "failed" h
      simp at this
  have hy : sts.any (fun s => ["failed", "error", "infrastructure_fail", "timedout", "unauthorized"].contains s) = true :=
    List.any_eq_true.mpr ⟨"failed", h, by decide⟩
  unfold endCode
  simp only [hn, hy]
  simp

theorem waitStep_pass (i : WaitInput) (hne : i.statuses ≠ []) (h : i.statuses.all (· == "success") = true) :
    waitStep i = some 0 := by
  have ht : i.statuses.all circleTerminal = true := by
    rw [List.all_eq_true] at h ⊢
    intro s hs
    have := h s hs
    simp at this
    subst this
    exact terminal_success
  cases hs : i.statuses with
  | nil => exact absurd hs hne
  | cons x t =>
    rw [hs] at ht h
    simp [waitStep, hs, ht, endCode, h]

theorem waitStep_canceled_not_pass (i : WaitInput) (h : "canceled" ∈ i.statuses) : waitStep i ≠ some 0 := by
  have hne := endCode_canceled i.statuses h
  unfold waitStep
  cases hs : i.statuses with
  | nil => rw [hs] at h; simp at h
  | cons x t =>
    rw [hs] at hne
    simp only [List.isEmpty_cons, Bool.false_eq_true, ↓reduceIte]
    split
    · simpa using hne
    · split <;> simp

theorem waitStep_failed (i : WaitInput) (h : "failed" ∈ i.statuses) (ht : i.statuses.all circleTerminal = true) :
    waitStep i = some 1 := by
  have := endCode_failed i.statuses h
  cases hs : i.statuses with
  | nil => rw [hs] at h; simp at h
  | cons x t =>
    rw [hs] at ht this
    simp only [waitStep, hs, List.isEmpty_cons, Bool.false_eq_true, ↓reduceIte, ht, this]

theorem waitStep_none_grace (i : WaitInput) (h : i.noWorkflowS ≤ i.waitedS) (he : i.statuses = []) :
    waitStep i = some 4 := by
  simp [waitStep, he, h]

theorem waitStep_timeout (i : WaitInput) (h : i.timeoutS ≤ i.waitedS) (hg : i.statuses = [] → i.waitedS < i.noWorkflowS)
    (hr : i.statuses.all circleTerminal = false) : waitStep i = some 3 := by
  cases hs : i.statuses with
  | nil =>
    have := hg hs
    simp [waitStep, hs, h, Nat.not_le.mpr this]
  | cons x t =>
    rw [hs] at hr
    simp only [waitStep, hs, List.isEmpty_cons, Bool.false_eq_true, ↓reduceIte, hr, h]

theorem waitStep_goes_on (i : WaitInput) (h1 : i.waitedS < i.timeoutS) (h2 : i.statuses = [] → i.waitedS < i.noWorkflowS)
    (h3 : i.statuses.all circleTerminal = false) : waitStep i = none := by
  cases hs : i.statuses with
  | nil =>
    have := h2 hs
    simp [waitStep, hs, Nat.not_le.mpr this, Nat.not_le.mpr h1]
  | cons x t =>
    rw [hs] at h3
    simp only [waitStep, hs, List.isEmpty_cons, Bool.false_eq_true, ↓reduceIte, h3, Nat.not_le.mpr h1]

/-! ## Job map -/

theorem jobMap_github_nodup : (jobMap.map (fun x => (x.lane, x.gh))).Nodup := by decide

theorem jobMap_gh_nodup : (jobMap.map (·.gh)).Nodup := by decide

theorem jobMap_circle_nodup : (jobMap.map (·.circleci)).Nodup := by decide

theorem exact_matches_iff (n s : String) : ghMatches (.exact n) s = true ↔ n = s := by
  simp [ghMatches]

/-- The real name of the sim matrix job of the original arm on the first VM (run 39123621097): `sim (original, 430, 1, <sha>, v1)`. -/
theorem sim_v1_row : jobOfGithub "sim (original, 430, 1, 40a8d4c1deadbeef, v1)" = some ⟨"webkit-sim", .matrix "sim (original," "v1", "webkit-sim", false, false⟩ := by
  decide

theorem sim_other_vm_no_row : jobOfGithub "sim (original, 430, 1, 40a8d4c1deadbeef, v2)" = none := by decide

theorem sim_rewrite_no_row : jobOfGithub "sim (rewrite, 430, 1, 40a8d4c1deadbeef, v1)" = none := by decide

theorem sim_overlap_no_row : jobOfGithub "sim (original, v1)" = none := by decide

theorem engine_chromium_row : (jobOfGithub "engine (chromium)").map (·.circleci) = some "engine-chromium" := by decide

theorem engine_name_is_whole : jobOfGithub "engine (chromium) again" = none := by decide

theorem verdict_row : (jobOfGithub "verdict").map (·.circleci) = some "verdict" := by decide

/-- No GitHub job name belongs to two rows: two rows of the map never match one name. -/
theorem jobMap_disjoint : ∀ r ∈ jobMap, ∀ r' ∈ jobMap, r ≠ r' → ∀ n, ghMatches r.gh n = true → ghMatches r'.gh n = false := by
  intro r hr r' hr' hne n hm
  simp only [jobMap, List.mem_cons, List.not_mem_nil, or_false] at hr hr'
  rcases hr with rfl | rfl | rfl | rfl <;> rcases hr' with rfl | rfl | rfl | rfl <;>
    first
    | exact absurd rfl hne
    | (simp only [ghMatches, beq_iff_eq] at hm; subst hm; decide)
    | (simp only [ghMatches, beq_eq_false_iff_ne, ne_eq]; rintro rfl; revert hm; decide)

theorem digest_jobs : digestJob "engine-chromium" = true ∧ digestJob "engine-playwright-webkit" = true ∧
    digestJob "verdict" = false ∧ digestJob "webkit-sim" = false := by decide

/-! ## Digest verdict -/

theorem verdict_digest_ignores_conclusion (g c : Run) (h : digestJob g.job = true) (a : String)
    (hg : g.digest = some a) (hc : c.digest = some a) : verdict g c = true := by
  simp [verdict, h, verdictDigest, hg, hc]

theorem verdict_digest_differs (g c : Run) (h : digestJob g.job = true) (a b : String)
    (hg : g.digest = some a) (hc : c.digest = some b) (hab : a ≠ b) : verdict g c = false := by
  simp [verdict, h, verdictDigest, hg, hc, hab]

theorem verdict_conclusion_job (g c : Run) (h : digestJob g.job = false) : verdict g c = verdictEq g c := by
  simp [verdict, h]

theorem verdict_digest_none (g c : Run) (h : digestJob g.job = true) (hg : g.digest = none) : verdict g c = false := by
  simp [verdict, h, verdictDigest, hg]

theorem digest_missing_not_comparable (g c : Run) (hg : g.provider = .github) (hc : c.provider = .circleci)
    (hj : g.job = c.job) (hs : g.sha = c.sha) (hd : digestJob g.job = true) (h : g.digest = none ∨ c.digest = none) :
    compare g c = .error .digest := by
  rw [compare_error g c _ (pairCheck_digest g c hg hc hj hs hd h)]

/-! ## Examples -/

#guard credits "arm.large.gen2" 90000 = some 18
#guard credits "arm.medium.gen2" 1 = some 1
#guard credits "m4pro.medium" 0 = some 0
#guard credits "arm.small" 1000 = none
#guard stops ⟨3600000, 0, 0⟩ == [.cap]
#guard stops ⟨3599999, 600000, 1000⟩ == []
#guard stops ⟨3600000, 600001, 1001⟩ == [.cap, .queue, .storage]
#guard landStops ⟨3600000, 600001, 1001⟩ == [.cap, .queue]
#guard landStops ⟨0, 0, 1297⟩ == []
#guard storageNow [⟨some 0, 1000000000, 0, 0⟩] windowMs == 500
#guard storageNow [⟨some 0, 1000000000, 0, 0⟩] (windowMs + 1) == 0
#guard storageNow [⟨none, 0, 0, 1000000000⟩] (windowMs + 1) == 1000
#guard storageNow [⟨some 0, 1, 0, 0⟩, ⟨some 0, 0, 1, 0⟩] 0 == 1
#guard storageNow [] 0 == 0
#guard storageCredits 2000 == 0 && storageCredits 2001 == 1 && storageCredits 3000 == 420 && storageCredits 0 == 0
#guard lakeKeyTail .perSource "abc" 0 == "abc"
#guard lakeKeyTail .daily "abc" (dayMs + 5) == "day-1" && lakeKeyTail .daily "xyz" (2 * dayMs - 1) == "day-1"
#guard ofCircleStatus "success" == .pass
#guard ofCircleStatus "canceled" == .notRun
#guard ofGithubConclusion "cancelled" == .notRun
#guard waitStep ⟨["success", "running"], 0, 300, 3600⟩ == none
#guard waitStep ⟨["success", "failed"], 0, 300, 3600⟩ == some 1
#guard waitStep ⟨[], 300, 300, 3600⟩ == some 4
#guard (jobOfGithub "sim (original, 430, 1, 40a8d4c1, v1)").map (·.circleci) == some "webkit-sim"
#guard route ⟨"premise-tests", .linuxArm, "arm.medium.gen2", ["premise-tests"], false, 600000, 100⟩ == .circleci
#guard route ⟨"premise-tests", .linuxArm, "arm.medium.gen2", [], false, 600000, 100⟩ == .github
#guard route ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], false, 600000, 30000⟩ == .github
#guard route ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], true, 600000, 30000⟩ == .circleci
#guard route ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], true, 600000, 1999⟩ == .github
#guard route ⟨"webkit-sim", .macos, "m4pro.large", ["webkit-sim"], true, 600000, 30000⟩ == .github


/-! ## Key check -/

theorem key_listed_ok (n : Nat) (c : Option Bool) (h : 0 < n) : keyVerdict ⟨some n, c⟩ = .ok := by
  simp [keyVerdict, h]

theorem key_list_empty_missing (c : Option Bool) : keyVerdict ⟨some 0, c⟩ = .missing := by
  simp [keyVerdict]

theorem key_unreadable_clone_ok : keyVerdict ⟨none, some true⟩ = .ok := by decide

theorem key_unreadable_clone_failed_missing : keyVerdict ⟨none, some false⟩ = .missing := by decide

theorem key_unreadable_no_evidence_unknown : keyVerdict ⟨none, none⟩ = .unknown := by decide

theorem key_list_beats_clone (n : Nat) (c d : Option Bool) : keyVerdict ⟨some n, c⟩ = keyVerdict ⟨some n, d⟩ := by
  simp [keyVerdict]

theorem key_proceed_iff (i : KeyInput) : keyProceed i = true ↔ keyVerdict i = .ok := by
  simp [keyProceed]

theorem key_not_ok_no_start (i : KeyInput) (h : keyVerdict i ≠ .ok) : keyProceed i = false := by
  simp [keyProceed, h]

theorem key_missing_never_starts (i : KeyInput) (h : keyVerdict i = .missing) : keyProceed i = false := by
  simp [keyProceed, h]

theorem key_unknown_never_starts (i : KeyInput) (h : keyVerdict i = .unknown) : keyProceed i = false := by
  simp [keyProceed, h]

theorem usable_deploy : usableKeyKind "deploy-key" = true := by decide

theorem usable_user : usableKeyKind "github-user-key" = true := by decide

theorem unusable_other : usableKeyKind "other" = false := by decide

theorem checkout_success : checkoutOfStatus "success" = some true := by decide

theorem checkout_failed : checkoutOfStatus "failed" = some false := by decide

theorem checkout_silent (s : String) (h1 : s ≠ "success") (h2 : s ≠ "failed") : checkoutOfStatus s = none := by
  simp [checkoutOfStatus, h1, h2]

end Fw.Ci.Provider
