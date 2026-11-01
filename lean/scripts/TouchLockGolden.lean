import Fw.Parts.EndPin

def main (args : List String) : IO UInt32 :=
  Fw.Measure.TouchLock.runText (Fw.Measure.TouchLock.goldenText ++ Fw.Parts.EndPin.goldenText)
    (Fw.Measure.TouchLock.goldenLines.length + Fw.Parts.EndPin.goldenLines.length) args
