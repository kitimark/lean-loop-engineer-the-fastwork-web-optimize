Scripts behind the v1 numbers in 01-v1-console-manual-work.md. They read local, read-only data and print counts only;
they write nothing except scan.py's intermediate calls.jsonl (keep it local; it holds per-turn token counts and role
names, no message text). Run each with `python3 -I`.

  V1=../fastwork-com-web-optimize   M=$V1/.git/fastwork-mirror   D=.local/v1-chat-digest/out
  RAW=<v1 transcripts dir>

  scan.py   $RAW $D/agents.json calls.jsonl   -> calls.jsonl (one line per assistant message with tool calls)
  agg.py                                       -> tool calls by category and role (§3.1); reads ./calls.jsonl
  agg2.py                                      -> upkeep turns, class A/B, by role (§3.2); reads ./calls.jsonl
  agg3.py   calls.jsonl                        -> the same totals with blocking waits (class W) split out (§3.2)
  status_hist.py $M                            -> status history: actions, writers, key sets, classification (§3.3)
  holdcheck.py   $M                            -> the loose ±30 min / 6 h hold cross-checks (575/701, 344/422)
  holds_control.py $M                          -> the same ±30 min test on a judgement-class control, with ±2 h shifts
  holds_strict.py  $M                          -> the strict test: write inside [acquiredAt, at] (131/701 vs 20/537)
  lag.py    $M                                 -> decision -> next board write lag (§1.2)
  stores.py / stores2.py $M                    -> findings, incidents, steps, proposals, threads (§3.4)
