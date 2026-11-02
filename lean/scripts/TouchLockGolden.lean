import Fw.Parts.EndPin

def main (args : List String) : IO UInt32 :=
  Fw.Measure.TouchLock.runText (Fw.Measure.TouchLock.goldenText ++ Fw.Parts.EndPin.goldenText)
    (Fw.Measure.TouchLock.goldenLines.length + Fw.Parts.EndPin.goldenLines.length) args

theorem quiet_link : Fw.Measure.TouchLock.quiet10 = 10 * Fw.Parts.EndPin.quietMs := by decide
