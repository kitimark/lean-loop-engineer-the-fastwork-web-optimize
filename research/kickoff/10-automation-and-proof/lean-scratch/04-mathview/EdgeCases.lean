import Fw
open Fw
-- Verdict: ties, empty lists
#eval Verdict.verdict .lower [10,11,12] [9,10,8]        -- tie at 10
#eval Verdict.below [] [1,2]                              -- vacuous
#eval Verdict.below [1] []                                -- vacuous
#eval Verdict.verdict .lower [5,5,5] [4,4,4]
#eval Verdict.verdict .lower [5,5] [4,4,4]
-- Frames
#eval (Frames.tick 37499, Frames.tick 37500, Frames.tick 54166, Frames.tick 54167, Frames.tick 0, Frames.tick 4166, Frames.tick 4167)
#eval Frames.countAbove 0 []
#eval Frames.countAbove 10 [11, 11, 10, 5]
-- Flags: last override wins; empty variant list default
def reg : Flags.Registry := { variants := fun p => if p = .hero then ["v2","orig"] else ["orig"], rules := [] }
#eval match Flags.resolve reg [(.hero,"orig"),(.hero,"v2")] with | .ok c => c .hero | .error e => e
#eval match Flags.resolve reg [(.hero,"v3")] with | .ok c => c .hero | .error e => e
#eval Flags.defaults { variants := fun _ => [], rules := [] } .nav
-- Lease: renew-forever starves the queue; release by stranger; tick at exact expiry
open Lease in
#eval let s1 := (step {} (.acquire "a" 0 10)).1
      let s2 := (step s1 (.acquire "b" 1 10)).1
      let s3 := (step s2 (.renew "a" 9 10)).1
      let s4 := (step s3 (.tick 15 10)).1
      let s5 := (step s4 (.renew "a" 18 10)).1
      let s6 := (step s5 (.tick 25 10)).1
      (s6.holder, s6.queue)
open Lease in
#eval let s1 := (step {} (.acquire "a" 0 10)).1
      (step s1 (.tick 10 10)).1.holder    -- expires = 10, now = 10 -> expired
open Lease in
#eval let s1 := (step {} (.acquire "a" 0 10)).1
      let r := step s1 (.acquire "a" 5 100)
      (r.1.holder.map (·.expires), (match r.2 with | .granted l => l.expires | _ => 0))  -- re-entrant acquire does not extend
open Lease in
#eval let s1 := (step {} (.acquire "a" 0 10)).1
      let r := step s1 (.release "zed" 5 10)
      (r.1.queue, repr r.2)
-- Stage: closing L
open Stage in
#eval match advance { stage := .L } { closes := .L, signedBy := .lead } with | .ok _ => "ok" | .error e => e
open Stage in
#eval match advance { stage := .D } { closes := .D, signedBy := .lead, attribution := some .located } with | .ok _ => "ok" | .error e => e
