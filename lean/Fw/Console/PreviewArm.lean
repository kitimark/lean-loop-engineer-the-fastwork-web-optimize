import Fw.Console.PreviewOwner

/-!
# One origin per preview arm (task preview-proxy-direct)

A preview has two arms, the task version (`r`) and the original snapshot (`o`). Each arm is served on its own port, hence
its own origin: a page of an arm asks for `/_app/x.js` and the browser sends that to the same origin, so no request is
redirected, no `Referer` is read and no HTML or CSS is rewritten. The arm's public port is the port the table already
allocates (`Pv.rp`, `Pv.op`: pairwise distinct, freed with the preview, `ports_distinct`). The preview server process
listens on a private loopback port, the arm's backend port (`backendOf`: the public port plus `backendOff`).

What is decided here: which arm a connection belongs to (`route`: by the port it arrived on, never by the path), that
no request reaches another arm or another preview (`route_no_leak`, `spec_port_inj`), that the path goes to the backend
unchanged (`route_identity`), and the gate (`armServe`: the same decision as the preview port gives a preview path today,
`arm_gate_eq_preview_path`). What is not: the sockets, the cookie header and the HTTP proxy itself are I/O.
-/

namespace Fw.Console.Preview.Arm

open Fw.Console.Preview

/-- The two arms of a preview. -/
inductive Arm where
  | r | o
deriving Repr, DecidableEq

/-- Its wire name. -/
def Arm.name : Arm → String
  | .r => "r" | .o => "o"

/-- The public port of an arm of a preview. -/
def Arm.port (p : Pv) : Arm → Nat
  | .r => p.rp | .o => p.op

-- `backendOff` (how far the private backend port lies above the public one) is defined with the table in `Preview`: at
-- least the width of the range, so a backend port is never a public port (`backend_ne_port`), and `admit` refuses a base
-- whose backend ports would leave the port space.

/-- The private loopback port of the preview server of the arm whose public port is `q`. -/
def backendOf (q : Nat) : Nat := q + backendOff

/-- One listening arm: the preview it belongs to, which arm, its public port and its backend port. -/
structure Spec where
  id : String
  arm : Arm
  port : Nat
  backend : Nat
deriving Repr, DecidableEq

/-- The two arms of a preview. -/
def specsOf (p : Pv) : List Spec :=
  [⟨p.id, .r, p.rp, backendOf p.rp⟩, ⟨p.id, .o, p.op, backendOf p.op⟩]

/-- The arms of every live preview. -/
def specs (s : List Pv) : List Spec := s.flatMap specsOf

/-- What the arm server does with a request. -/
inductive Act where
  /-- Send it to the backend of arm `arm` of preview `id`, with this path and query, unchanged. -/
  | proxy (id : String) (arm : Arm) (backend : Nat) (path : String)
  /-- No arm listens on this port. -/
  | refuse
deriving Repr, DecidableEq

/-- Where a request goes: decided by the local port it arrived on. The path is passed through, not inspected. -/
def route (s : List Pv) (port : Nat) (path : String) : Act :=
  match (specs s).find? (fun x => x.port == port) with
  | some x => .proxy x.id x.arm x.backend path
  | none => .refuse

/-- Which arm of which preview a verdict names, without the path. -/
def Act.target : Act → Option (String × Arm × Nat)
  | .proxy i a b _ => some (i, a, b)
  | .refuse => none

/-- The arms' public ports are the table's ports. -/
theorem specs_ports (s : List Pv) : (specs s).map (·.port) = ports s := by
  induction s with
  | nil => simp [specs, ports]
  | cons p t ih =>
    simp only [specs, ports, List.flatMap_cons, List.map_append] at ih ⊢
    simp [specsOf, ih]

/-- A list whose images under `f` are pairwise distinct has `f` injective on its members. -/
theorem inj_of_nodup_map {α β : Type} {f : α → β} : ∀ {l : List α}, (l.map f).Nodup →
    ∀ x ∈ l, ∀ y ∈ l, f x = f y → x = y
  | [], _, x, hx, _, _, _ => by simp at hx
  | a :: t, hn, x, hx, y, hy, h => by
    rw [List.map_cons, List.nodup_cons] at hn
    rcases List.mem_cons.mp hx with rfl | hx' <;> rcases List.mem_cons.mp hy with rfl | hy'
    · rfl
    · exact absurd (h ▸ List.mem_map_of_mem hy') hn.1
    · exact absurd (h ▸ List.mem_map_of_mem hx') hn.1
    · exact inj_of_nodup_map hn.2 x hx' y hy' h

/-- **A port names one arm.** With pairwise distinct table ports, two arms with the same public port are the same arm. -/
theorem spec_port_inj {s : List Pv} (hn : (ports s).Nodup) {a b : Spec} (ha : a ∈ specs s) (hb : b ∈ specs s)
    (h : a.port = b.port) : a = b := by
  rw [← specs_ports] at hn
  exact inj_of_nodup_map hn a ha b hb h

/-- A verdict names an arm that exists: the request's port is that arm's public port and the verdict carries its
preview, arm and backend. -/
theorem route_sound {s : List Pv} {q : Nat} {path i : String} {a : Arm} {b : Nat} {p' : String}
    (h : route s q path = .proxy i a b p') : ∃ x ∈ specs s, x.port = q ∧ x.id = i ∧ x.arm = a ∧ x.backend = b := by
  unfold route at h
  cases hf : (specs s).find? (fun x => x.port == q) with
  | none => simp [hf] at h
  | some x =>
    simp only [hf, Act.proxy.injEq] at h
    obtain ⟨h1, h2, h3, _⟩ := h
    have hm := List.mem_of_find?_eq_some hf
    have hp := List.find?_some hf
    exact ⟨x, hm, by simpa using hp, h1, h2, h3⟩

/-- **The path goes to the backend unchanged**: no rewrite, no redirect (the only other verdict is a refusal). -/
theorem route_identity {s : List Pv} {q : Nat} {path i : String} {a : Arm} {b : Nat} {p' : String}
    (h : route s q path = .proxy i a b p') : p' = path := by
  unfold route at h
  cases hf : (specs s).find? (fun x => x.port == q) with
  | none => simp [hf] at h
  | some x => simp only [hf, Act.proxy.injEq] at h; exact h.2.2.2.symm

/-- **The path does not choose the arm**: two requests on one port, whatever their paths, go to the same arm. -/
theorem route_path_free (s : List Pv) (q : Nat) (p₁ p₂ : String) :
    (route s q p₁).target = (route s q p₂).target := by
  unfold route
  cases (specs s).find? (fun x => x.port == q) <;> rfl

/-- **No cross-preview leak.** A request that arrives on the public port of arm `a` of a live preview goes to arm `a` of
that preview and to nothing else, whatever its path. -/
theorem route_no_leak {s : List Pv} (hn : (ports s).Nodup) {pv : Pv} (hp : pv ∈ s) (a : Arm) (path : String) :
    route s (Arm.port pv a) path = .proxy pv.id a (backendOf (Arm.port pv a)) path := by
  have hmem : (⟨pv.id, a, Arm.port pv a, backendOf (Arm.port pv a)⟩ : Spec) ∈ specs s := by
    unfold specs
    refine List.mem_flatMap.mpr ⟨pv, hp, ?_⟩
    cases a <;> simp [specsOf, Arm.port]
  unfold route
  cases hf : (specs s).find? (fun x => x.port == Arm.port pv a) with
  | none =>
    have := List.find?_eq_none.mp hf _ hmem
    simp at this
  | some x =>
    have hxm := List.mem_of_find?_eq_some hf
    have hxp : x.port = Arm.port pv a := by simpa using List.find?_some hf
    have := spec_port_inj hn hxm hmem hxp
    subst this
    rfl

/-- **No arm, no answer**: a port that is no public port of the table is refused. -/
theorem route_refuse_iff (s : List Pv) (q : Nat) (path : String) : route s q path = .refuse ↔ q ∉ ports s := by
  rw [← specs_ports]
  unfold route
  cases hf : (specs s).find? (fun x => x.port == q) with
  | none =>
    have h := List.find?_eq_none.mp hf
    simp only [true_iff]
    intro hm
    obtain ⟨x, hx, hxq⟩ := List.mem_map.mp hm
    have := h x hx
    simp [hxq] at this
  | some x =>
    simp only [reduceCtorEq, false_iff, Classical.not_not]
    exact List.mem_map.mpr ⟨x, List.mem_of_find?_eq_some hf, by simpa using List.find?_some hf⟩

/-- **A backend port is never a public port**, so a connection to an arm's public port never reaches a preview server
without the gate. -/
theorem backend_ne_port {lo : Nat} {s : List Pv} (hr : ∀ q ∈ ports s, lo ≤ q ∧ q < lo + portN)
    {a b : Spec} (ha : a ∈ specs s) (hb : b ∈ specs s) : a.backend ≠ b.port := by
  have hpa : a.port ∈ ports s := by rw [← specs_ports]; exact List.mem_map.mpr ⟨a, ha, rfl⟩
  have hpb : b.port ∈ ports s := by rw [← specs_ports]; exact List.mem_map.mpr ⟨b, hb, rfl⟩
  have h1 := hr _ hpa
  have h2 := hr _ hpb
  have hb' : a.backend = a.port + backendOff := by
    unfold specs at ha
    obtain ⟨p, _, hp⟩ := List.mem_flatMap.mp ha
    simp only [specsOf, List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl <;> rfl
  have hw : portN ≤ backendOff := by decide
  omega

/-- **Backend ports follow public ports one to one**: two arms share a backend port only if they are the same arm. -/
theorem backend_inj {s : List Pv} (hn : (ports s).Nodup) {a b : Spec} (ha : a ∈ specs s) (hb : b ∈ specs s)
    (h : a.backend = b.backend) : a = b := by
  have hba : ∀ x ∈ specs s, x.backend = x.port + backendOff := by
    intro x hx
    unfold specs at hx
    obtain ⟨p, _, hp⟩ := List.mem_flatMap.mp hx
    simp only [specsOf, List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl <;> rfl
  rw [hba a ha, hba b hb] at h
  exact spec_port_inj hn ha hb (by omega)

/-- **A backend port is a port**: below 65536 when the range plus the offset is. -/
theorem backend_in_space {lo : Nat} {s : List Pv} (hr : ∀ q ∈ ports s, lo ≤ q ∧ q < lo + portN)
    (hs : lo + portN + backendOff ≤ 65536) {a : Spec} (ha : a ∈ specs s) : a.backend < 65536 := by
  have hpa : a.port ∈ ports s := by rw [← specs_ports]; exact List.mem_map.mpr ⟨a, ha, rfl⟩
  have h1 := hr _ hpa
  have hb' : a.backend = a.port + backendOff := by
    unfold specs at ha
    obtain ⟨p, _, hp⟩ := List.mem_flatMap.mp ha
    simp only [specsOf, List.mem_cons, List.not_mem_nil, or_false] at hp
    rcases hp with rfl | rfl <;> rfl
  omega

/-! ## The gate of an arm origin -/

open Fw.Console.Preview.Owner in
/-- Whether an arm origin serves a request. Every path of an arm origin belongs to the preview, so the gate is the
preview port's gate for a preview path (cookie of an owner session, or a live grant) and takes no path. -/
def armServe (lan session hostOk known : Bool) (started now : Nat) : Bool :=
  servePreview lan session hostOk known started now .preview

open Fw.Console.Preview.Owner in
/-- **The decision is the one the preview port gives a preview path today**, for any such path. -/
theorem arm_gate_eq_preview_path (lan session hostOk known : Bool) (started now : Nat) (x : String) :
    armServe lan session hostOk known started now = servePreview lan session hostOk known started now (classify ("/preview/" ++ x)) := by
  have : classify ("/preview/" ++ x) = .preview := by
    unfold classify
    have h1 : (("/preview/" ++ x) == "/owner/login") = false := by
      simp only [beq_eq_false_iff_ne, ne_eq]
      intro h
      have := congrArg (fun t => t.toList.take 4) h
      simp at this
    simp [h1]
  rw [this]; rfl

open Fw.Console.Preview.Owner in
/-- **Session branch**: an owner session's preview cookie, on the right Host, is served. -/
theorem arm_session_serves (lan hostOk known : Bool) (started now : Nat) (h : lan = false ∨ hostOk = true) :
    armServe lan true hostOk known started now = true := by
  simp only [armServe, servePreview, allowPreview]
  rcases h with rfl | rfl <;> simp

open Fw.Console.Preview.Owner in
/-- **Grant branch**: a live grant, on the right Host, is served. -/
theorem arm_grant_serves (lan : Bool) (started now : Nat) (h : now < started + grantCookieTtl) :
    armServe lan false true true started now = true := by
  simp [armServe, servePreview, allowPreview, allowGrant, h]

open Fw.Console.Preview.Owner in
/-- **Neither a cookie nor a grant: nothing is served.** -/
theorem arm_needs_credential (lan hostOk : Bool) (started now : Nat) :
    armServe lan false hostOk false started now = false := by
  simp [armServe, servePreview, allowPreview, allowGrant]

open Fw.Console.Preview.Owner in
/-- **A foreign Host is refused on the LAN** whatever the request carries. -/
theorem arm_wrong_host (session known : Bool) (started now : Nat) :
    armServe true session false known started now = false := by
  simp [armServe, servePreview, allowPreview, allowGrant]

end Fw.Console.Preview.Arm
