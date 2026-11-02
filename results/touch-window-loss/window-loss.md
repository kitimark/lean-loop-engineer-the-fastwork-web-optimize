# Lost touch-lock windows by class

Planned windows per job: 24 (6 reps x 4 arms); 12 job slots per run.

| run | planned | ok | noOpen | tooShort | pageLost | beginLate | swipeLate | driverNotReady | restartFailed | inspectorDead | evaluateTimeout | walkDeadline | jobCut | planShort | noArtifact |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 41391781282 | 288 | 71 | 31 | 11 | 2 | 0 | 3 | 0 | 113 | 0 | 0 | 33 | 0 | 0 | 24 |
| 41402584809 | 288 | 46 | 39 | 8 | 1 | 0 | 0 | 24 | 52 | 21 | 15 | 18 | 0 | 16 | 48 |
| 41422536168 | 288 | 66 | 37 | 8 | 3 | 0 | 0 | 0 | 56 | 45 | 17 | 6 | 22 | 28 | 0 |
| 41436626306 | 288 | 105 | 38 | 14 | 2 | 0 | 0 | 0 | 37 | 28 | 0 | 0 | 0 | 16 | 48 |
| 41460411752 | 288 | 80 | 35 | 8 | 0 | 0 | 3 | 48 | 42 | 0 | 0 | 22 | 6 | 20 | 24 |
| 41475879793 | 288 | 94 | 32 | 13 | 2 | 1 | 1 | 24 | 55 | 16 | 21 | 11 | 10 | 8 | 0 |
| 41503168296 | 288 | 96 | 36 | 13 | 3 | 0 | 1 | 0 | 53 | 23 | 20 | 31 | 0 | 12 | 0 |
| all | 2016 | 558 | 248 | 75 | 13 | 1 | 8 | 96 | 408 | 133 | 73 | 121 | 38 | 100 | 144 |

## Ranked lost classes

| class | windows | share of planned |
|---|---|---|
| restartFailed | 408 | 20.2% |
| noOpen | 248 | 12.3% |
| noArtifact | 144 | 7.1% |
| inspectorDead | 133 | 6.6% |
| walkDeadline | 121 | 6.0% |
| planShort | 100 | 5.0% |
| driverNotReady | 96 | 4.8% |
| tooShort | 75 | 3.7% |
| evaluateTimeout | 73 | 3.6% |
| jobCut | 38 | 1.9% |
| pageLost | 13 | 0.6% |
| swipeLate | 8 | 0.4% |
| beginLate | 1 | 0.0% |

Sides: ok 558, harness 726, simulator 732 of 2016.

## Per job and arm

Each cell is the class counts of that arm (6 planned windows) as `class:n`, ok first.

### Run 41391781282

| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6 | 2 | 742 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | ok:1 restartFailed:5 | pageLost:1 restartFailed:5 | restartFailed:6 | no |
| 2 | 6 | 15 | 1919 | fault lost-mid-walk: restart failed: push server: no ready file after  | ok:2 noOpen:1 restartFailed:3 | ok:4 restartFailed:2 | ok:1 noOpen:2 tooShort:1 restartFailed:2 | ok:2 noOpen:2 restartFailed:2 | no |
| 3 | 6 | 24 | 831 | complete | ok:6 | ok:6 | ok:3 noOpen:1 tooShort:2 | ok:5 tooShort:1 | no |
| 4 | 6 | 16 | 2107 | walk deadline: abandoned a window in flight after 16 windows | ok:3 noOpen:1 walkDeadline:2 | ok:1 noOpen:3 walkDeadline:2 | ok:1 noOpen:3 walkDeadline:2 | ok:2 noOpen:1 tooShort:1 walkDeadline:2 | no |
| 5 | 6 | 5 | 1130 | fault lost-mid-walk: restart failed: push server: no ready file after  | noOpen:1 restartFailed:5 | ok:1 restartFailed:5 | noOpen:1 restartFailed:5 | ok:1 pageLost:1 restartFailed:4 | no |
| 6 | 6 | 13 | 1931 | walk deadline: abandoned a window in flight after 13 windows | ok:2 tooShort:1 walkDeadline:3 | ok:1 noOpen:2 walkDeadline:3 | ok:3 walkDeadline:3 | ok:2 noOpen:2 walkDeadline:2 | no |
| 7 | 6 | 6 | 1344 | fault lost-mid-walk: restart failed: push server: no ready file after  | ok:1 restartFailed:5 | ok:1 restartFailed:5 | ok:1 swipeLate:1 restartFailed:4 | ok:1 noOpen:1 restartFailed:4 | no |
| 8 | 6 | 1 | 1069 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | swipeLate:1 restartFailed:5 | restartFailed:6 | restartFailed:6 | no |
| 9 | 6 | 2 | 1061 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | ok:1 restartFailed:5 | swipeLate:1 restartFailed:5 | restartFailed:6 | no |
| 10 | 0 | 0 | - | no artifact | noArtifact:6 | noArtifact:6 | noArtifact:6 | noArtifact:6 | no |
| 11 | 6 | 24 | 1670 | complete | ok:6 | ok:2 noOpen:2 tooShort:2 | ok:3 noOpen:2 tooShort:1 | ok:3 noOpen:2 tooShort:1 | no |
| 12 | 6 | 10 | 1698 | walk deadline: abandoned a window in flight after 10 windows | ok:2 walkDeadline:4 | ok:2 tooShort:1 walkDeadline:3 | ok:1 noOpen:2 walkDeadline:3 | noOpen:2 walkDeadline:4 | no |

### Run 41402584809

| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6 | 6 | 619 | walk deadline: abandoned a window in flight after 6 windows | tooShort:1 walkDeadline:5 | ok:1 walkDeadline:5 | ok:1 noOpen:1 walkDeadline:4 | noOpen:2 walkDeadline:4 | no |
| 2 | 0 | 0 | 721 | fault touch-driver-not-ready: push server: no ready file after 512 s;  | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | no |
| 3 | 6 | 6 | 929 | fault lost-mid-walk: restart failed: push server: no ready file after  | noOpen:1 restartFailed:5 | ok:1 restartFailed:5 | tooShort:1 pageLost:1 restartFailed:4 | ok:2 restartFailed:4 | no |
| 4 | 6 | 9 | 2065 | walk deadline: abandoned a window in flight after 9 windows | ok:1 noOpen:1 evaluateTimeout:4 | noOpen:3 evaluateTimeout:3 | noOpen:2 evaluateTimeout:4 | noOpen:2 evaluateTimeout:4 | no |
| 5 | 6 | 3 | 758 | the inspector is dead and rebooting the Simulator failed: simctl shutd | inspectorDead:6 | noOpen:1 inspectorDead:5 | noOpen:1 inspectorDead:5 | ok:1 inspectorDead:5 | no |
| 6 | 4 | 16 | 1983 | complete | ok:2 noOpen:2 planShort:2 | ok:1 noOpen:3 planShort:2 | ok:2 noOpen:2 planShort:2 | ok:4 planShort:2 | no |
| 7 | 0 | 0 | - | no artifact | noArtifact:6 | noArtifact:6 | noArtifact:6 | noArtifact:6 | no |
| 8 | 6 | 24 | 1346 | complete | ok:6 | ok:5 noOpen:1 | ok:4 noOpen:1 tooShort:1 | ok:5 tooShort:1 | no |
| 9 | 0 | 0 | - | no artifact | noArtifact:6 | noArtifact:6 | noArtifact:6 | noArtifact:6 | no |
| 10 | 4 | 14 | 2134 | walk deadline: abandoned a window in flight after 14 windows | ok:2 tooShort:1 restartFailed:1 planShort:2 | ok:2 noOpen:1 restartFailed:1 planShort:2 | ok:1 noOpen:2 tooShort:1 planShort:2 | ok:2 noOpen:2 planShort:2 | no |
| 11 | 6 | 5 | 1981 | walk deadline: abandoned a window in flight after 5 windows | noOpen:1 restartFailed:5 | ok:1 restartFailed:5 | tooShort:1 restartFailed:5 | noOpen:2 restartFailed:4 | no |
| 12 | 6 | 11 | 1397 | fault lost-mid-walk: restart failed: push server: no ready file after  | noOpen:2 restartFailed:4 | ok:1 noOpen:2 restartFailed:3 | ok:1 noOpen:1 tooShort:1 restartFailed:3 | noOpen:3 restartFailed:3 | no |

### Run 41422536168

| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 4 | 6 | 1969 | walk deadline: abandoned a window in flight after 6 windows | noOpen:1 evaluateTimeout:3 planShort:2 | noOpen:1 evaluateTimeout:3 planShort:2 | ok:1 noOpen:1 evaluateTimeout:2 planShort:2 | ok:1 noOpen:1 evaluateTimeout:2 planShort:2 | no |
| 2 | 6 | 0 | 630 | the inspector is dead and rebooting the Simulator failed: simctl shutd | inspectorDead:6 | inspectorDead:6 | inspectorDead:6 | inspectorDead:6 | no |
| 3 | 6 | 3 | 1007 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | ok:1 restartFailed:5 | ok:1 restartFailed:5 | pageLost:1 restartFailed:5 | no |
| 4 | 6 | 3 | 876 | the inspector is dead and rebooting the Simulator failed: simctl shutd | inspectorDead:6 | tooShort:1 inspectorDead:5 | noOpen:1 inspectorDead:5 | noOpen:1 inspectorDead:5 | no |
| 5 | 6 | 16 | 1422 | walk not finished: written after a window | ok:2 noOpen:2 jobCut:2 | ok:1 noOpen:1 tooShort:2 jobCut:2 | ok:4 jobCut:2 | ok:3 noOpen:1 jobCut:2 | no |
| 6 | 6 | 24 | 1053 | complete | ok:6 | ok:5 noOpen:1 | ok:4 noOpen:2 | ok:5 noOpen:1 | no |
| 7 | 6 | 18 | 1614 | walk deadline: abandoned a window in flight after 18 windows | ok:3 noOpen:1 walkDeadline:2 | ok:3 noOpen:2 walkDeadline:1 | ok:3 noOpen:2 walkDeadline:1 | ok:2 noOpen:2 walkDeadline:2 | no |
| 8 | 6 | 7 | 1084 | fault lost-mid-walk: restart failed: push server: no ready file after  | ok:1 restartFailed:5 | ok:1 pageLost:1 restartFailed:4 | noOpen:2 restartFailed:4 | ok:2 restartFailed:4 | no |
| 9 | 6 | 6 | 1921 | fault lost-mid-walk: restart failed: push server: no ready file after  | tooShort:1 restartFailed:5 | ok:1 restartFailed:5 | noOpen:1 pageLost:1 restartFailed:4 | ok:1 tooShort:1 restartFailed:4 | no |
| 10 | 4 | 2 | 731 | walk not finished: written after a window | jobCut:4 planShort:2 | noOpen:1 jobCut:3 planShort:2 | ok:1 jobCut:3 planShort:2 | jobCut:4 planShort:2 | no |
| 11 | 4 | 16 | 1037 | complete | ok:3 tooShort:1 planShort:2 | ok:3 noOpen:1 planShort:2 | ok:4 planShort:2 | ok:3 noOpen:1 planShort:2 | no |
| 12 | 5 | 13 | 1937 | walk deadline: abandoned a window in flight after 13 windows | noOpen:3 evaluateTimeout:2 planShort:1 | noOpen:3 evaluateTimeout:2 planShort:1 | noOpen:2 tooShort:1 evaluateTimeout:2 planShort:1 | ok:1 noOpen:2 tooShort:1 evaluateTimeout:1 planShort:1 | no |

### Run 41436626306

| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 0 | 0 | - | no artifact | noArtifact:6 | noArtifact:6 | noArtifact:6 | noArtifact:6 | no |
| 2 | 0 | 0 | - | no artifact | noArtifact:6 | noArtifact:6 | noArtifact:6 | noArtifact:6 | no |
| 3 | 6 | 20 | 2139 | walk deadline: abandoned a window in flight after 20 windows | ok:4 pageLost:1 restartFailed:1 | ok:4 noOpen:1 restartFailed:1 | ok:3 noOpen:2 restartFailed:1 | ok:2 noOpen:2 tooShort:1 restartFailed:1 | no |
| 4 | 6 | 24 | 1426 | complete | ok:2 noOpen:4 | ok:1 noOpen:3 tooShort:2 | ok:4 noOpen:1 tooShort:1 | ok:4 noOpen:1 tooShort:1 | no |
| 5 | 6 | 24 | 1832 | complete | ok:4 noOpen:2 | ok:2 noOpen:4 | ok:5 noOpen:1 | ok:5 noOpen:1 | no |
| 6 | 6 | 24 | 749 | complete | ok:5 tooShort:1 | ok:4 tooShort:2 | ok:6 | ok:6 | no |
| 7 | 4 | 6 | 2154 | walk deadline: abandoned a window in flight after 6 windows | noOpen:1 restartFailed:3 planShort:2 | noOpen:1 restartFailed:3 planShort:2 | ok:1 noOpen:1 restartFailed:2 planShort:2 | ok:1 noOpen:1 restartFailed:2 planShort:2 | no |
| 8 | 5 | 20 | 1296 | complete | ok:3 noOpen:1 tooShort:1 planShort:1 | ok:3 noOpen:2 planShort:1 | ok:3 tooShort:2 planShort:1 | ok:5 planShort:1 | no |
| 9 | 6 | 24 | 1032 | complete | ok:5 tooShort:1 | ok:5 tooShort:1 | ok:4 noOpen:2 | ok:5 noOpen:1 | no |
| 10 | 6 | 14 | 1420 | the inspector is dead and rebooting the Simulator failed: no Safari ta | ok:1 noOpen:2 inspectorDead:3 | ok:2 tooShort:1 inspectorDead:3 | ok:2 noOpen:2 inspectorDead:2 | ok:3 noOpen:1 inspectorDead:2 | no |
| 11 | 6 | 1 | 1224 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | pageLost:1 restartFailed:5 | restartFailed:6 | restartFailed:6 | no |
| 12 | 5 | 2 | 1609 | the inspector is dead and rebooting the Simulator failed: simctl shutd | inspectorDead:5 planShort:1 | noOpen:1 inspectorDead:4 planShort:1 | ok:1 inspectorDead:4 planShort:1 | inspectorDead:5 planShort:1 | no |

### Run 41460411752

| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6 | 15 | 1957 | walk deadline: abandoned a window in flight after 14 windows | ok:1 noOpen:1 tooShort:1 walkDeadline:3 | ok:1 noOpen:2 tooShort:1 walkDeadline:2 | ok:1 noOpen:3 walkDeadline:2 | ok:1 noOpen:3 walkDeadline:2 | no |
| 2 | 6 | 18 | 2083 | walk not finished: written after a window | ok:3 noOpen:1 jobCut:2 | ok:2 noOpen:3 jobCut:1 | ok:3 noOpen:2 jobCut:1 | ok:1 noOpen:3 jobCut:2 | no |
| 3 | 0 | 0 | - | no artifact | noArtifact:6 | noArtifact:6 | noArtifact:6 | noArtifact:6 | no |
| 4 | 6 | 5 | 809 | fault lost-mid-walk: restart failed: push server: no ready file after  | ok:1 restartFailed:5 | tooShort:1 restartFailed:5 | ok:1 restartFailed:5 | ok:1 swipeLate:1 restartFailed:4 | no |
| 5 | 5 | 7 | 1671 | walk deadline: abandoned a window in flight after 7 windows | noOpen:1 walkDeadline:4 planShort:1 | ok:1 noOpen:1 walkDeadline:3 planShort:1 | noOpen:2 walkDeadline:3 planShort:1 | noOpen:2 walkDeadline:3 planShort:1 | no |
| 6 | 6 | 24 | 919 | complete | ok:5 noOpen:1 | ok:5 tooShort:1 | ok:5 noOpen:1 | ok:4 noOpen:1 tooShort:1 | no |
| 7 | 4 | 16 | 1539 | complete | ok:4 planShort:2 | ok:3 noOpen:1 planShort:2 | ok:2 noOpen:2 planShort:2 | ok:1 noOpen:3 planShort:2 | no |
| 8 | 6 | 23 | 2058 | fault lost-mid-walk: restart failed: push server: no ready file after  | ok:4 tooShort:1 restartFailed:1 | ok:3 noOpen:1 tooShort:1 swipeLate:1 | ok:4 noOpen:1 tooShort:1 | ok:6 | no |
| 9 | 0 | 0 | 592 | fault touch-driver-not-ready: push server: no ready file after 511 s;  | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | no |
| 10 | 4 | 16 | 945 | complete | ok:4 planShort:2 | ok:4 planShort:2 | ok:4 planShort:2 | ok:4 planShort:2 | no |
| 11 | 6 | 2 | 1056 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | ok:1 restartFailed:5 | swipeLate:1 restartFailed:5 | restartFailed:6 | no |
| 12 | 0 | 0 | 684 | fault touch-driver-not-ready: push server: no ready file after 508 s;  | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | no |

### Run 41475879793

| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6 | 18 | 1938 | walk deadline: abandoned a window in flight after 18 windows | ok:2 noOpen:1 tooShort:1 evaluateTimeout:2 | ok:5 evaluateTimeout:1 | ok:3 noOpen:1 tooShort:1 evaluateTimeout:1 | ok:4 evaluateTimeout:2 | no |
| 2 | 6 | 9 | 2038 | walk deadline: no time left to start lock rep 2 | noOpen:1 tooShort:1 evaluateTimeout:4 | ok:2 noOpen:1 evaluateTimeout:3 | noOpen:2 evaluateTimeout:4 | ok:1 tooShort:1 evaluateTimeout:4 | no |
| 3 | 0 | 0 | 639 | fault touch-driver-not-ready: push server: no ready file after 505 s;  | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | driverNotReady:6 | no |
| 4 | 6 | 13 | 1977 | walk deadline: abandoned a window in flight after 13 windows | ok:2 tooShort:1 walkDeadline:3 | ok:1 noOpen:1 tooShort:1 walkDeadline:3 | noOpen:3 walkDeadline:3 | ok:2 noOpen:2 walkDeadline:2 | no |
| 5 | 5 | 9 | 1990 | walk deadline: abandoned a window in flight after 9 windows | ok:1 noOpen:1 restartFailed:3 planShort:1 | ok:2 noOpen:1 restartFailed:2 planShort:1 | ok:1 noOpen:1 restartFailed:3 planShort:1 | noOpen:2 restartFailed:3 planShort:1 | no |
| 6 | 6 | 15 | 1829 | fault lost-mid-walk: restart failed: push server: no ready file after  | ok:2 tooShort:1 restartFailed:3 | ok:3 noOpen:1 restartFailed:2 | ok:4 restartFailed:2 | ok:3 noOpen:1 restartFailed:2 | no |
| 7 | 6 | 14 | 2120 | walk not finished: written after a window | noOpen:1 tooShort:1 pageLost:1 jobCut:3 | ok:1 noOpen:1 tooShort:1 jobCut:3 | ok:2 noOpen:2 jobCut:2 | ok:4 jobCut:2 | no |
| 8 | 6 | 24 | 1504 | complete | ok:5 pageLost:1 | ok:5 noOpen:1 | ok:5 noOpen:1 | ok:5 tooShort:1 | yes |
| 9 | 6 | 13 | 2009 | walk not finished: written after a window | ok:1 noOpen:1 tooShort:1 restartFailed:3 | ok:2 noOpen:1 restartFailed:3 | ok:2 noOpen:1 restartFailed:3 | ok:3 noOpen:1 restartFailed:2 | no |
| 10 | 6 | 8 | 2005 | the inspector is dead and rebooting the Simulator failed: simctl shutd | ok:2 inspectorDead:4 | ok:2 inspectorDead:4 | ok:1 swipeLate:1 inspectorDead:4 | ok:2 inspectorDead:4 | no |
| 11 | 6 | 2 | 1670 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | ok:1 restartFailed:5 | beginLate:1 restartFailed:5 | restartFailed:6 | no |
| 12 | 5 | 18 | 1970 | walk deadline: abandoned a window in flight after 18 windows | ok:3 tooShort:1 restartFailed:1 planShort:1 | ok:3 noOpen:1 tooShort:1 planShort:1 | ok:3 noOpen:2 planShort:1 | ok:4 restartFailed:1 planShort:1 | no |

### Run 41503168296

| slot | reps | rows | wall s | end | orig | base | lock | pin | sufficient |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 6 | 16 | 2112 | walk deadline: abandoned a window in flight after 16 windows | ok:1 noOpen:2 tooShort:1 walkDeadline:2 | ok:2 noOpen:2 walkDeadline:2 | ok:1 noOpen:2 tooShort:1 walkDeadline:2 | ok:3 noOpen:1 walkDeadline:2 | no |
| 2 | 6 | 2 | 999 | fault lost-mid-walk: restart failed: push server: no ready file after  | restartFailed:6 | ok:1 restartFailed:5 | pageLost:1 restartFailed:5 | restartFailed:6 | no |
| 3 | 6 | 9 | 772 | walk not finished: written after a window | ok:1 noOpen:1 restartFailed:4 | ok:2 noOpen:1 restartFailed:3 | ok:2 restartFailed:4 | noOpen:2 restartFailed:4 | no |
| 4 | 6 | 24 | 864 | complete | ok:6 | ok:4 noOpen:1 tooShort:1 | ok:4 tooShort:2 | ok:5 noOpen:1 | no |
| 5 | 6 | 1 | 1352 | the inspector is dead and rebooting the Simulator failed: simctl shutd | inspectorDead:6 | ok:1 inspectorDead:5 | inspectorDead:6 | inspectorDead:6 | no |
| 6 | 6 | 17 | 2130 | walk deadline: abandoned a window in flight after 17 windows | ok:3 noOpen:1 walkDeadline:2 | ok:4 noOpen:1 walkDeadline:1 | ok:4 walkDeadline:2 | ok:3 swipeLate:1 walkDeadline:2 | no |
| 7 | 6 | 10 | 1506 | fault lost-mid-walk: restart failed: push server: no ready file after  | ok:2 restartFailed:4 | ok:2 noOpen:1 restartFailed:3 | ok:2 pageLost:1 restartFailed:3 | noOpen:2 restartFailed:4 | no |
| 8 | 6 | 22 | 2045 | walk deadline: abandoned a window in flight after 22 windows | ok:5 restartFailed:1 | ok:5 restartFailed:1 | ok:4 tooShort:1 pageLost:1 | ok:3 noOpen:3 | no |
| 9 | 4 | 14 | 1989 | walk deadline: no time left to start base rep 3 | ok:1 noOpen:2 walkDeadline:1 planShort:2 | ok:1 noOpen:2 walkDeadline:1 planShort:2 | ok:2 noOpen:1 tooShort:1 planShort:2 | noOpen:2 tooShort:2 planShort:2 | no |
| 10 | 5 | 6 | 1275 | walk deadline: abandoned a window in flight after 6 windows | ok:1 walkDeadline:4 planShort:1 | noOpen:1 walkDeadline:4 planShort:1 | noOpen:2 walkDeadline:3 planShort:1 | noOpen:2 walkDeadline:3 planShort:1 | no |
| 11 | 6 | 24 | 835 | complete | ok:6 | ok:5 tooShort:1 | ok:5 tooShort:1 | ok:5 tooShort:1 | yes |
| 12 | 6 | 4 | 2051 | walk deadline: abandoned a window in flight after 4 windows | noOpen:1 evaluateTimeout:5 | noOpen:1 evaluateTimeout:5 | noOpen:1 evaluateTimeout:5 | tooShort:1 evaluateTimeout:5 | no |

## Sufficiency and jobs implied

Jobs with every arm at minKept (5) accepted windows: 2 of 84; with status-ok windows: 15 of 84.
Jobs with every arm at minSamples (3) accepted windows: 16 of 84; WalkBudget.jobsFor at that rate: 22.
WalkBudget.jobsFor at the accepted rate 2/84: not within jobsCap; at the status-ok rate 15/84: 23.

| run | accepted | status ok | jobs at accepted rate (of 12) | jobs at status-ok rate (of 12) |
|---|---|---|---|---|
| 41391781282 | 0 | 2 | none | 25 |
| 41402584809 | 0 | 1 | none | none |
| 41422536168 | 0 | 1 | none | none |
| 41436626306 | 0 | 5 | none | 10 |
| 41460411752 | 0 | 2 | none | 25 |
| 41475879793 | 1 | 1 | none | none |
| 41503168296 | 1 | 3 | none | 16 |

Restarts started: 38; stalls {"pageLost":18,"ok":8,"swipeLate":10,"beginLate":2}; push server ready after a restart: 7, median 310 s, max 434 s.

## Counterfactual upper bounds (INFERRED, not measured)

Windows ok and jobs with every arm at minKept if (retryRefused) every refused window were rerun ok, (noStall) every window after the first stall ran ok, or both.

| lever | ok windows | sufficient jobs of 84 |
|---|---|---|
| base | 558 | 2 |
| retryRefused | 881 | 15 |
| noStall | 1059 | 18 |
| both | 1377 | 44 |

## First stall of a job and what followed

| first stall | jobs | lost windows after | ok windows after | push server ready after (s) |
|---|---|---|---|---|
| pageLost | 17 | 251 | 1 | 310, 266, 118 |
| ok | 7 | 70 | 3 | 434 |
| swipeLate | 10 | 149 | 9 | 243, 389 |
| beginLate | 2 | 31 | 0 | never |

## noOpen share of the windows that ran (status ok), by rep and by job

| rep | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| noOpen / ran | 94/257 | 71/205 | 43/165 | 29/132 | 7/72 | 4/50 |

Jobs with a stall: 83/312; jobs without: 165/569.

