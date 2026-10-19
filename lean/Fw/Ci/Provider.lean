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

/-- The price list the pilot meets (CONFIRMED rates, `research/notes/2026/10-20-circleci-free-tier.md`, capacity table). -/
def rates : List Rate := [
  ⟨"arm.medium", .linuxArm, .oss, 10, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"arm.large", .linuxArm, .oss, 20, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"arm.medium.gen2", .linuxArm, .oss, 6, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"arm.large.gen2", .linuxArm, .oss, 12, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"m4pro.medium", .macos, .base, 200, true, "https://circleci.com/pricing/price-list/"⟩,
  ⟨"m4pro.large", .macos, .base, 400, false, "https://circleci.com/pricing/price-list/"⟩]

/-- The rate row of a class name. -/
def rateOf (c : String) : Option Rate := rates.find? (·.cls == c)

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

/-- Why two runs are not a pair. -/
inductive Mismatch where
  | providers
  | job
  | sha
deriving DecidableEq, Repr

/-- The first reason two runs are not a GitHub/CircleCI pair of the same job on the same commit. -/
def pairCheck (g c : Run) : Option Mismatch :=
  if g.provider != .github || c.provider != .circleci then some .providers
  else if g.job != c.job then some .job
  else if g.sha != c.sha then some .sha
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

/-- Compare a pair: a verdict that differs is a finding, with the duration ratio, both queue times and the CircleCI credits. -/
def compare (g c : Run) : Except Mismatch Comparison :=
  match pairCheck g c with
  | some m => .error m
  | none => .ok { finding := !verdictEq g c, ratioPermille := ratioPermille g c,
                  queueGithubMs := g.queueMs, queueCircleMs := c.queueMs, credits := credits c.cls c.durMs }

/-- The job-length cap of the Free plan, ms. -/
def capMs : Nat := 3600000

/-- The longest queue wait the pilot tolerates, ms. -/
def queueMaxMs : Nat := 600000

/-- The storage allowance of the Free plan, in thousandths of a GB-month. -/
def storageMaxMilli : Nat := 1000

/-- Storage of a save in thousandths of a GB-month: bytes times retention days over 30 days, rounded up. -/
def storageMilli (bytes days : Nat) : Nat := (bytes * days * 1000 + 30 * 1000000000 - 1) / (30 * 1000000000)

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
    ++ (if storageMaxMilli < i.storageMilli then [Stop.storage] else [])

/-- The pilot stops. -/
def stop (i : StopInput) : Bool := !(stops i).isEmpty

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

/-- The GitHub job of the pilot lane against its CircleCI twin: (lane, GitHub job, CircleCI job). -/
def jobMap : List (String × String × String) := [
  ("premise-tests", "engine (chromium)", "engine-chromium"),
  ("premise-tests", "engine (playwright-webkit)", "engine-playwright-webkit"),
  ("premise-tests", "verdict", "verdict"),
  ("webkit-sim", "sim (original)", "webkit-sim")]

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

theorem pairCheck_none_iff (g c : Run) : pairCheck g c = none ↔
    g.provider = .github ∧ c.provider = .circleci ∧ g.job = c.job ∧ g.sha = c.sha := by
  unfold pairCheck
  by_cases h1 : g.provider = .github <;> by_cases h2 : c.provider = .circleci <;>
    by_cases h3 : g.job = c.job <;> by_cases h4 : g.sha = c.sha <;> simp [h1, h2, h3, h4]

theorem compare_ok_iff (g c : Run) : (∃ k, compare g c = .ok k) ↔ pairCheck g c = none := by
  unfold compare
  cases h : pairCheck g c <;> simp

theorem compare_error (g c : Run) (m : Mismatch) (h : pairCheck g c = some m) : compare g c = .error m := by
  simp [compare, h]

theorem finding_iff (g c : Run) (k : Comparison) (h : compare g c = .ok k) :
    k.finding = true ↔ verdictEq g c = false := by
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
  simp [storageMilli]

theorem mem_cap_iff (i : StopInput) : Stop.cap ∈ stops i ↔ capMs ≤ i.durMs := by
  unfold stops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;>
    by_cases h3 : storageMaxMilli < i.storageMilli <;> simp [h1, h2, h3]

theorem mem_queue_iff (i : StopInput) : Stop.queue ∈ stops i ↔ queueMaxMs < i.queueMs := by
  unfold stops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;>
    by_cases h3 : storageMaxMilli < i.storageMilli <;> simp [h1, h2, h3]

theorem mem_storage_iff (i : StopInput) : Stop.storage ∈ stops i ↔ storageMaxMilli < i.storageMilli := by
  unfold stops
  by_cases h1 : capMs ≤ i.durMs <;> by_cases h2 : queueMaxMs < i.queueMs <;>
    by_cases h3 : storageMaxMilli < i.storageMilli <;> simp [h1, h2, h3]

theorem stop_of_cap (i : StopInput) (h : capMs ≤ i.durMs) : stop i = true := by
  have := (mem_cap_iff i).mpr h
  unfold stop
  cases hs : stops i <;> simp_all

theorem stop_of_queue (i : StopInput) (h : queueMaxMs < i.queueMs) : stop i = true := by
  have := (mem_queue_iff i).mpr h
  unfold stop
  cases hs : stops i <;> simp_all

theorem stop_of_storage (i : StopInput) (h : storageMaxMilli < i.storageMilli) : stop i = true := by
  have := (mem_storage_iff i).mpr h
  unfold stop
  cases hs : stops i <;> simp_all

theorem stop_iff (i : StopInput) : stop i = true ↔
    capMs ≤ i.durMs ∨ queueMaxMs < i.queueMs ∨ storageMaxMilli < i.storageMilli := by
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

theorem no_stop_within_limits (i : StopInput) (h1 : i.durMs < capMs) (h2 : i.queueMs ≤ queueMaxMs)
    (h3 : i.storageMilli ≤ storageMaxMilli) : stop i = false := by
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

/-! ## Job map -/

theorem jobMap_github_nodup : (jobMap.map (fun x => (x.1, x.2.1))).Nodup := by decide

theorem jobMap_circle_nodup : (jobMap.map (fun x => (x.1, x.2.2))).Nodup := by decide

/-! ## Examples -/

#guard credits "arm.large.gen2" 90000 = some 18
#guard credits "arm.medium.gen2" 1 = some 1
#guard credits "m4pro.medium" 0 = some 0
#guard credits "arm.small" 1000 = none
#guard stops ⟨3600000, 0, 0⟩ == [.cap]
#guard stops ⟨3599999, 600000, 1000⟩ == []
#guard stops ⟨3600000, 600001, 1001⟩ == [.cap, .queue, .storage]
#guard route ⟨"premise-tests", .linuxArm, "arm.medium.gen2", ["premise-tests"], false, 600000, 100⟩ == .circleci
#guard route ⟨"premise-tests", .linuxArm, "arm.medium.gen2", [], false, 600000, 100⟩ == .github
#guard route ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], false, 600000, 30000⟩ == .github
#guard route ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], true, 600000, 30000⟩ == .circleci
#guard route ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], true, 600000, 1999⟩ == .github
#guard route ⟨"webkit-sim", .macos, "m4pro.large", ["webkit-sim"], true, 600000, 30000⟩ == .github

end Fw.Ci.Provider
