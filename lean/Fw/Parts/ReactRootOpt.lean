import Lean.Data.Json

/-! `engine.events:quiet`: the React root skips the 7 animation and transition event types the page never handles; WebKit records one EventDispatch per listener phase (`EventTarget.cpp:313-357@862f17d`). -/
namespace Fw.Parts.ReactRootOpt

inductive Phase where
  | bubble | capture
  deriving DecidableEq, Repr

structure Reg where
  ty : String
  ph : Phase
  deriving DecidableEq, Repr

def Phase.tag : Phase → String
  | .bubble => "b" | .capture => "c"

/-- The types `listenToAllSupportedEvents` registers on a root (`allNativeEvents`, React 19.3.1), `selectionchange` aside. -/
def native : List String :=
  ["abort", "auxclick", "beforetoggle", "cancel", "canplay", "canplaythrough", "click", "close", "contextmenu", "copy", "cut",
   "drag", "dragend", "dragenter", "dragexit", "dragleave", "dragover", "dragstart", "drop", "durationchange", "emptied",
   "encrypted", "ended", "error", "fullscreenchange", "fullscreenerror", "gotpointercapture", "input", "invalid", "keydown",
   "keypress", "keyup", "load", "loadeddata", "loadedmetadata", "loadstart", "lostpointercapture", "mousedown", "mousemove",
   "mouseout", "mouseover", "mouseup", "paste", "pause", "play", "playing", "pointercancel", "pointerdown", "pointermove",
   "pointerout", "pointerover", "pointerup", "progress", "ratechange", "reset", "resize", "seeked", "seeking", "stalled",
   "submit", "suspend", "timeupdate", "touchcancel", "touchend", "touchstart", "volumechange", "scroll", "toggle", "touchmove",
   "waiting", "wheel", "scrollend", "animationend", "animationiteration", "animationstart", "dblclick", "focusin", "focusout",
   "transitionrun", "transitionstart", "transitioncancel", "transitionend", "change", "compositionend", "textInput",
   "compositionstart", "compositionupdate"]

/-- `nonDelegatedEvents` (`DOMPluginEventSystem.js:236-251@61aa00d`): a capture listener only. -/
def nonDelegated : List String :=
  ["beforetoggle", "cancel", "close", "invalid", "load", "scroll", "scrollend", "toggle",
   "abort", "canplay", "canplaythrough", "durationchange", "emptied", "encrypted", "ended", "error", "loadeddata",
   "loadedmetadata", "loadstart", "pause", "play", "playing", "progress", "ratechange", "resize", "seeked", "seeking",
   "stalled", "suspend", "timeupdate", "volumechange", "waiting"]

/-- The 7 types of the variant: the page has no React handler for any of them. -/
def quiet : List String :=
  ["animationend", "animationiteration", "animationstart", "transitioncancel", "transitionend", "transitionrun", "transitionstart"]

/-- What a root registers for one type (`DOMPluginEventSystem.js:432-445@61aa00d`). -/
def regsOf (e : String) : List Reg :=
  (if nonDelegated.contains e then [] else [⟨e, .bubble⟩]) ++ [⟨e, .capture⟩]

def regs : List Reg := native.flatMap regsOf

def admit (e : String) : Bool := !quiet.contains e

def quietRegs : List Reg := regs.filter fun r => admit r.ty

/-- EventDispatch records one dispatch of `e` costs on the root (`EventTarget.cpp:313-357@862f17d`: one per phase that has a listener). -/
def records (rs : List Reg) (e : String) : Nat := (rs.filter fun r => r.ty == e).length

#guard native.length == 87
#guard nonDelegated.length == 32
#guard regs.length == 142
#guard quietRegs.length == 128
#guard quiet.all native.contains

theorem quiet_none : ∀ r ∈ quietRegs, r.ty ∉ quiet := by
  intro r hr h
  have h2 := (List.mem_filter.1 hr).2
  simp [admit, h] at h2

theorem quiet_keeps : ∀ r ∈ regs, r.ty ∉ quiet → r ∈ quietRegs := by
  intro r hr h
  refine List.mem_filter.2 ⟨hr, ?_⟩
  simp [admit, h]

theorem quiet_sub : quietRegs ⊆ regs := fun _ h => (List.mem_filter.1 h).1

theorem handled_stays (H : List String) (hH : ∀ e ∈ H, e ∉ quiet) :
    ∀ e ∈ H, ∀ r ∈ regs, r.ty = e → r ∈ quietRegs := by
  intro e he r hr hre
  exact quiet_keeps r hr (hre ▸ hH e he)

set_option maxRecDepth 8000 in
theorem orig_registers : ∀ e ∈ quiet, (⟨e, .capture⟩ : Reg) ∈ regs ∧ (⟨e, .bubble⟩ : Reg) ∈ regs := by decide

set_option maxRecDepth 8000 in
theorem quiet_drops : ∀ e ∈ quiet, (⟨e, .capture⟩ : Reg) ∉ quietRegs ∧ (⟨e, .bubble⟩ : Reg) ∉ quietRegs := by decide

set_option maxRecDepth 8000 in
theorem dropped_count : regs.length - quietRegs.length = 14 := by decide

set_option maxRecDepth 8000 in
theorem records_orig : ∀ e ∈ quiet, records regs e = 2 := by decide

set_option maxRecDepth 8000 in
theorem records_quiet : ∀ e ∈ quiet, records quietRegs e = 0 := by decide

set_option maxRecDepth 8000 in
theorem records_other : ∀ e ∈ native, e ∉ quiet → records quietRegs e = records regs e := by decide

def line (fn : String) (inp : List (String × Lean.Json)) (out : Lean.Json) : String :=
  (Lean.Json.mkObj [("fn", .str fn), ("in", Lean.Json.mkObj inp), ("out", out)]).compress

def regJ (r : Reg) : Lean.Json := .str s!"{r.ty}:{r.ph.tag}"

def goldenLines (_ : Unit) : List String :=
  [line "quiet" [] (.arr (quiet.map Lean.Json.str).toArray),
   line "registered" [("variant", .str "faithful")] (.arr (regs.map regJ).toArray),
   line "registered" [("variant", .str "quiet")] (.arr (quietRegs.map regJ).toArray)] ++
  native.map (fun e => line "admit" [("type", .str e)] (.bool (admit e))) ++
  quiet.flatMap fun e =>
    [line "records" [("variant", .str "faithful"), ("type", .str e)] (.num ⟨(records regs e : Nat), 0⟩),
     line "records" [("variant", .str "quiet"), ("type", .str e)] (.num ⟨(records quietRegs e : Nat), 0⟩)]

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def shimText : String :=
  "const quiet: ReadonlySet<string> = new Set(quietTypes);\n\n" ++
  "export const QUIET_VARIANT = 'quiet';\n\n" ++
  "export const admit = (type: string): boolean => !quiet.has(type);\n\n" ++
  "export function quietContainer(el: EventTarget): void {\n" ++
  "  const add = el.addEventListener;\n" ++
  "  el.addEventListener = function (this: EventTarget, type: string, listener: EventListenerOrEventListenerObject | null, options?: boolean | AddEventListenerOptions) {\n" ++
  "    if (!admit(type)) return;\n" ++
  "    add.call(this, type, listener, options);\n" ++
  "  } as EventTarget['addEventListener'];\n" ++
  "}\n"

def tsText (_ : Unit) : String :=
  "// Generated by lean/Fw/Parts/ReactRootOpt.lean (Fw.Parts.ReactRootOpt). Do not edit.\n" ++
  "export const quietTypes: readonly string[] = " ++ (Lean.Json.arr (quiet.map Lean.Json.str).toArray).compress ++ ";\n\n" ++ shimText

#guard (goldenLines ()).length == 3 + 87 + 14

#guard goldenText () == include_str "../../../packages/contracts/golden/parts/react-root-quiet.jsonl"

def run (args : List String) : IO UInt32 := do
  match args with
  | ["--write", ts, g] =>
    IO.FS.writeFile ts (tsText ())
    IO.FS.writeFile g (goldenText ())
    return 0
  | ["--check", ts, g] =>
    let a ← IO.FS.readFile ts
    let b ← IO.FS.readFile g
    if a == tsText () && b == goldenText () then
      IO.eprintln "react-root-quiet: the site table and the golden are up to date"
      return 0
    IO.eprintln "react-root-quiet: the site table or the golden differs from the generated text"
    return 1
  | _ => IO.eprintln "usage: ReactRootOpt.run (--write | --check) <quiet.gen.ts> <react-root-quiet.jsonl>"; return 2

end Fw.Parts.ReactRootOpt
