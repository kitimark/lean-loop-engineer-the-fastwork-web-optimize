import Fw.Obs.Health
import Lean.Data.Json

/-!
# Golden vectors of the resource baseline

`packages/contracts/golden/obs/sup-health.jsonl`: one line per case, `{"name", "request", "response"}`. The kind classifier (a process list with ancestry, arguments and the Simulator devices) and
the sample verdict (`Fw.Obs.Health.Res`) are the Lean side; `apps/runner/src/watch-collect.ts` is checked against these lines.
Run from `lean/`: `lake env lean --run scripts/SupHealthGolden.lean [--check]`.
-/
open Lean
open Fw.Obs.Health.Res

abbrev RProc := Fw.Obs.Health.Res.Proc
abbrev RDevice := Fw.Obs.Health.Res.Device

def kindJson (k : ProcKind) : Json := .str k.name

def obsJson (o : Obs) : Json :=
  Json.mkObj [("procs", .arr (o.procs.map kindJson).toArray), ("loadCenti", o.loadCenti), ("swapUsedMB", o.swapUsedMB),
    ("swapTotalMB", o.swapTotalMB), ("compressorMB", o.compressorMB), ("ramMB", o.ramMB), ("freePct", o.freePct)]

def paramsJson (p : Params) : Json :=
  Json.mkObj [("swapPct", p.swapPct), ("cmprsPct", p.cmprsPct), ("freePct", p.freePct), ("quietCenti", p.quietCenti)]

def verdictName : Verdict → String
  | .quiet => "quiet" | .busy => "busy" | .pressured => "pressured"

def line (name : String) (req resp : Json) : String :=
  (Json.mkObj [("name", .str name), ("request", req), ("response", resp)]).compress ++ "\n"

def kindsLine : String :=
  line "kinds" (Json.mkObj [("op", "sup.kinds")])
    (Json.mkObj [("kinds", .arr (ProcKind.all.map kindJson).toArray),
      ("heavy", .arr ((ProcKind.all.filter ProcKind.heavy).map kindJson).toArray)])

def tableLine : String :=
  line "table" (Json.mkObj [("op", "sup.table")])
    (Json.mkObj [("table", .arr (kindTable.map fun (n, r) => Json.arr #[.str n, .str r.name]).toArray)])

def procJson (p : RProc) : Json :=
  Json.mkObj [("pid", p.pid), ("ppid", p.ppid), ("comm", .str p.comm), ("args", .str p.args)]

def deviceJson (d : RDevice) : Json := Json.mkObj [("udid", .str d.udid), ("name", .str d.name)]

def pr (pid ppid : Nat) (comm : String) (args : String := "") : RProc := ⟨pid, ppid, comm, args⟩
def dev (udid name : String) : RDevice := ⟨udid, name⟩

def classifyLine (name : String) (devs : List RDevice) (ps : List RProc) : String :=
  line name (Json.mkObj [("op", "sup.classify"), ("devices", .arr (devs.map deviceJson).toArray), ("procs", .arr (ps.map procJson).toArray)])
    (Json.mkObj [("kinds", .arr ((kindsOf devs ps).map kindJson).toArray)])

def tableLines : List String :=
  kindTable.map fun (n, _) => classifyLine s!"listed name {n}" [] [pr 100 1 s!"/opt/tool/bin/{n}"]

def udid : String := "aaaaaaaa-0000-4000-8000-000000000001"
def udid2 : String := "bbbbbbbb-0000-4000-8000-000000000002"
def simRoot (pid ppid : Nat) (u : String) : RProc :=
  pr pid ppid "/Volumes/RuntimeRoot/sbin/launchd_sim" s!"/Volumes/RuntimeRoot/sbin/launchd_sim /Users/x/Library/Developer/CoreSimulator/Devices/{u}/data/var/run/launchd_bootstrap.plist"
def lakeServe : RProc := pr 70547 92523 "/Users/x/.elan/bin/lake" "/Users/x/.elan/bin/lake serve -- -Dserver.reportDelayMs=0"
def coreSimSvc : RProc := pr 41639 1 "/L/CoreSimulator.framework/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc/Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService"
def sysWebContent : RProc := pr 4473 1 "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent"
def background : List RProc :=
  [pr 1 0 "/sbin/launchd", coreSimSvc, sysWebContent, pr 4477 1 "/S/WebKit.framework/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking",
    lakeServe, pr 70549 70547 "/Users/x/.elan/bin/lean" "/Users/x/.elan/bin/lean --server -Dserver.reportDelayMs=0",
    pr 35909 70549 "/Users/x/.elan/bin/lean" "/Users/x/.elan/bin/lean --worker -Dserver.reportDelayMs=0 file:///x",
    pr 92565 92531 "/Users/x/.elan/bin/lean" "/Users/x/.elan/bin/lean --server"]
def fwSim : List RProc :=
  [pr 1 0 "/sbin/launchd", simRoot 500 1 udid, pr 501 500 "/Volumes/RuntimeRoot/usr/libexec/backboardd", pr 502 500 "/Volumes/RuntimeRoot/usr/libexec/some-sim-daemon",
    pr 503 502 "/Volumes/RuntimeRoot/System/Library/WebKit/com.apple.WebKit.WebContent", pr 504 501 "/Volumes/RuntimeRoot/Applications/MobileSafari.app/MobileSafari"]

def extraLines : List String := [
  classifyLine "node with a long versioned path" [] [pr 100 1 "/Users/x/.nvm/versions/node/v24.22.0/bin/node"],
  classifyLine "a name with spaces inside an app path" []
    [pr 100 1 "/Applications/Chromium.app/Contents/Frameworks/Chromium Helper (Renderer).app/Contents/MacOS/Chromium Helper (Renderer)"],
  classifyLine "a retitled process keeps its first word" [] [pr 100 1 "node server.js"],
  classifyLine "a retitled process, other first word" [] [pr 100 1 "npm exec thing"],
  classifyLine "a directory named like a kind does not count" [] [pr 100 1 "/Users/x/node/not-node"],
  classifyLine "an unlisted tool is other" [] [pr 100 1 "/usr/bin/top"],
  classifyLine "case matters" [] [pr 100 1 "/usr/bin/Node"],
  classifyLine "the empty command" [] [pr 100 1 ""],
  classifyLine "the background of this Mac: the service and the system WebKit are system, the language server and its workers leanServe" []
    background,
  classifyLine "a build is leanBuild, with its lean children and a binary it runs" []
    [pr 1 0 "/sbin/launchd", pr 20 1 "/e/bin/lake" "/e/bin/lake build", pr 21 20 "/e/bin/lean" "/e/bin/lean -R x -o y",
      pr 22 20 "/e/bin/lake" "/e/bin/lake env .lake/build/bin/propslint", pr 23 22 "/x/.lake/build/bin/propslint" "/x/.lake/build/bin/propslint a"],
  classifyLine "a build started by a language-server process stays serve" []
    [pr 20 1 "/e/bin/lake" "/e/bin/lake serve", pr 21 20 "/e/bin/lake" "/e/bin/lake build", pr 22 21 "/e/bin/lean" "/e/bin/lean -R x"],
  classifyLine "a server verb after the first word is not a server" []
    [pr 20 1 "/e/bin/lake" "/e/bin/lake build serve", pr 21 1 "/e/bin/lean" "/e/bin/lean x.lean --server"],
  classifyLine "a booted device of ours: the whole launchd_sim subtree is simulator, a same-named process outside it is not" [dev udid "fw-sim 15 Pro Max"]
    (fwSim ++ [pr 600 1 "/Volumes/RuntimeRoot/usr/libexec/some-sim-daemon"]),
  classifyLine "a device not named fw- is not ours" [dev udid2 "iPhone 17"]
    [pr 500 1 "/Volumes/RuntimeRoot/sbin/launchd_sim" s!"/Volumes/RuntimeRoot/sbin/launchd_sim /D/Devices/{udid2}/data", pr 501 500 "/Volumes/RuntimeRoot/usr/libexec/backboardd"],
  classifyLine "a fw- device whose id is not in the command line is not ours" [dev udid "fw-sim 15 Pro Max"]
    [pr 500 1 "/Volumes/RuntimeRoot/sbin/launchd_sim" s!"/Volumes/RuntimeRoot/sbin/launchd_sim /D/Devices/{udid2}/data", pr 501 500 "/Volumes/RuntimeRoot/usr/libexec/backboardd"],
  classifyLine "an empty device id never matches" [dev "" "fw-x"] [pr 500 1 "/Volumes/RuntimeRoot/sbin/launchd_sim" "/Volumes/RuntimeRoot/sbin/launchd_sim"],
  classifyLine "a Safari under safaridriver and its WebKit services are webkit; the same without the driver are other and system" []
    [pr 1 0 "/sbin/launchd", pr 700 1 "/usr/bin/safaridriver", pr 701 700 "/Applications/Safari.app/Contents/MacOS/Safari",
      pr 702 701 "/S/com.apple.WebKit.WebContent", pr 703 701 "/S/com.apple.WebKit.GPU",
      pr 800 1 "/Applications/Safari.app/Contents/MacOS/Safari", pr 801 800 "/S/com.apple.WebKit.WebContent", pr 802 1 "/S/com.apple.WebKit.Networking"],
  classifyLine "a parent loop stops and gives the process own kind" [] [pr 5 6 "/usr/bin/node", pr 6 5 "/e/bin/lean" "/e/bin/lean x", pr 7 7 "/e/bin/lake" "/e/bin/lake serve"],
  classifyLine "a missing parent ends the chain" [] [pr 5 999 "/e/bin/lean" "/e/bin/lean --worker"]]

def sampleLine (name : String) (devs : List RDevice) (ps : List RProc) (o : Obs) (p : Params := {}) : String :=
  let ks := kindsOf devs ps
  line name (Json.mkObj [("op", "sup.sample"), ("params", paramsJson p), ("devices", .arr (devs.map deviceJson).toArray),
      ("procs", .arr (ps.map procJson).toArray), ("obs", obsJson o)])
    (Json.mkObj [("kinds", .arr (ks.map kindJson).toArray), ("verdict", .str (verdictName (verdict p { o with procs := ks })))])

def lowLoad : Obs := { loadCenti := 50, freePct := 50, swapUsedMB := 100, swapTotalMB := 1000, compressorMB := 100, ramMB := 1000 }

def sampleLines : List String := [
  sampleLine "CoreSimulatorService, system WebContent and lake serve at low load, no pressure, are quiet" [] background lowLoad,
  sampleLine "a booted fw- device subtree is busy" [dev udid "fw-sim 15 Pro Max"] fwSim lowLoad,
  sampleLine "the same subtree of a device not named fw- is quiet" [dev udid "iPhone 17"] fwSim lowLoad,
  sampleLine "a lake build on top of the background is busy" [] (background ++ [pr 20 1 "/e/bin/lake" "/e/bin/lake build"]) lowLoad,
  sampleLine "a Safari under safaridriver is busy" [] [pr 700 1 "/usr/bin/safaridriver", pr 701 700 "/Applications/Safari.app/Contents/MacOS/Safari"] lowLoad,
  sampleLine "a user's own Safari and its WebKit services are quiet" [] [pr 800 1 "/Applications/Safari.app/Contents/MacOS/Safari", pr 801 800 "/S/com.apple.WebKit.WebContent"] lowLoad,
  sampleLine "a quiet process list under memory pressure is pressured" [] background { lowLoad with freePct := 10 },
  sampleLine "a quiet process list at load 2.00 is busy" [] background { lowLoad with loadCenti := 200 }]

def trippedLine (name : String) (o : Obs) (p : Params := {}) : String :=
  line name (Json.mkObj [("op", "sup.tripped"), ("params", paramsJson p), ("obs", obsJson o)])
    (Json.mkObj [("swap", .bool (swapHigh p o)), ("cmprs", .bool (cmprsHigh p o)), ("free", .bool (freeLow p o))])

def trippedLines : List String := [
  trippedLine "nothing tripped" lowLoad,
  trippedLine "swap alone" { lowLoad with swapUsedMB := 900 },
  trippedLine "compressor alone" { lowLoad with compressorMB := 500 },
  trippedLine "free memory alone" { lowLoad with freePct := 15 },
  trippedLine "swap and free memory" { lowLoad with swapUsedMB := 900, freePct := 10 },
  trippedLine "no swap total never trips swap" { lowLoad with swapTotalMB := 0, swapUsedMB := 900 },
  trippedLine "a looser swap limit lets 90 percent pass" { lowLoad with swapUsedMB := 900 } { swapPct := 95 }]

def verdictLine (name : String) (o : Obs) (p : Params := {}) : String :=
  line name (Json.mkObj [("op", "sup.verdict"), ("params", paramsJson p), ("obs", obsJson o)])
    (Json.mkObj [("verdict", .str (verdictName (verdict p o)))])

def verdictLines : List String := [
  verdictLine "an idle machine is quiet" {},
    verdictLine "a lean build makes it busy" { procs := [.leanBuild] },
  verdictLine "the language server, system services and light tools do not" { procs := [.leanServe, .system, .node, .pnpm, .fwcore, .other] },
  verdictLine "a chromium process makes it busy" { procs := [.chromium] },
  verdictLine "a simulator process makes it busy" { procs := [.simulator] },
  verdictLine "a webkit process makes it busy" { procs := [.webkit] },
  verdictLine "load 2.00 is busy" { loadCenti := 200 },
  verdictLine "load 1.99 is quiet" { loadCenti := 199 },
  verdictLine "swap at 90 percent is pressured" { swapUsedMB := 900, swapTotalMB := 1000 },
  verdictLine "swap at 89.9 percent is quiet" { swapUsedMB := 899, swapTotalMB := 1000 },
  verdictLine "no swap total never trips the swap branch" { swapUsedMB := 900 },
  verdictLine "compressor at half of RAM is pressured" { compressorMB := 50, ramMB := 100 },
  verdictLine "compressor just below half is quiet" { compressorMB := 49, ramMB := 100 },
  verdictLine "no RAM size never trips the compressor branch" { compressorMB := 50 },
  verdictLine "free memory at 15 percent is pressured" { freePct := 15 },
  verdictLine "free memory at 16 percent is quiet" { freePct := 16 },
  verdictLine "pressure wins over a heavy process" { procs := [.leanBuild], freePct := 10 },
  verdictLine "pressure wins over load" { loadCenti := 4000, swapUsedMB := 95, swapTotalMB := 100 },
  verdictLine "a looser swap limit lets 90 percent pass" { swapUsedMB := 900, swapTotalMB := 1000 } { swapPct := 95 },
  verdictLine "a stricter load limit makes load 1.00 busy" { loadCenti := 100 } { quietCenti := 100 },
  verdictLine "a stricter free limit trips at 30 percent" { freePct := 30 } { freePct := 30 }]

def goldenText : String :=
  String.join ([kindsLine, tableLine] ++ tableLines ++ extraLines ++ sampleLines ++ trippedLines ++ verdictLines)

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "sup-health.jsonl"

def main (args : List String) : IO UInt32 := do
  if args.contains "--check" then
    let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
    if cur == goldenText then
      IO.eprintln s!"sup-health golden: {goldenPath} is up to date"
      return 0
    IO.eprintln s!"sup-health golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/SupHealthGolden.lean)"
    return 1
  IO.FS.writeFile goldenPath goldenText
  return 0
