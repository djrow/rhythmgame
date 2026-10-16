# Milestone 1: Scoring Engine & Timing Evaluation - Adversarial Challenger Handoff Report

**Author**: `m1_challenger_1` (Empirical Challenger / Adversarial Critic)  
**Date**: 2026-10-16  
**Milestone**: Milestone 1 (M1) — Grand Staff Highway & Scoring  
**Project Root**: `c:\Users\david\Documents\micgame-3`  
**Verdict**: **REQUEST_CHANGES**

---

## 1. Observation

### 1.1 Codebase Defects Identified in `scripts/scoring_engine.gd`

#### Defect 1: `process_input` Ignores `is_missed` Flag (High Severity)
In `scripts/scoring_engine.gd` (lines 121–134):
```gdscript
121: 		if note is Dictionary:
122: 			is_hit = bool(note.get("is_hit", false))
123: 			note_pitch = int(note.get("pitch_midi", 0))
124: 			note_time = float(note.get("time_sec", 0.0))
125: 		elif note is RefCounted and "is_hit" in note and "pitch_midi" in note and "time_sec" in note:
126: 			is_hit = note.is_hit
127: 			note_pitch = note.pitch_midi
128: 			note_time = note.time_sec
129: 		else:
130: 			continue
131: 		
132: 		if is_hit:
133: 			continue
```
In `scripts/highway.gd` (lines 136–140):
```gdscript
136: 		if not note.is_hit and not note.is_missed and current_song_time > note.time_sec + miss_window_sec:
137: 			note.is_missed = true
138: 			note.hit_rating = "MISS"
139: 			note_missed.emit(note)
```
`highway.gd` marks missed notes with `note.is_missed = true`, but preserves `note.is_hit = false`. Because `scoring_engine.process_input()` only checks `if is_hit: continue` and never checks `is_missed`, any note that was missed remains matchable by late or asynchronous audio/keyboard inputs while the note is still in the active array before off-screen despawn.

#### Defect 2: `check_expired_notes` Inappropriately Corrupts `is_hit = true` on Missed Notes (High Severity)
In `scripts/scoring_engine.gd` (lines 189–190 and 199–200):
```gdscript
189: 				note["is_missed"] = true
190: 				note["is_hit"] = true # Mark processed so it won't be evaluated again
...
199: 				note.is_missed = true
200: 				note.is_hit = true
```
To prevent `process_input` from re-matching expired notes, `check_expired_notes` sets `is_hit = true` on expired (missed) notes. This breaks the domain contract (`PROJECT.md` line 68 & `NoteData.is_hit`), making it impossible for downstream consumers (stats, UI, replay, highway) to distinguish between a hit note and a missed note.

#### Defect 3: `register_hit` Increments `total_notes` Before Validating Judgment (Medium Severity)
In `scripts/scoring_engine.gd` (lines 62–81):
```gdscript
62: func register_hit(judgment: String, note_data: Dictionary = {}) -> Dictionary:
63: 	total_notes += 1
64: 	var base_pts: int = 0
65: 	
66: 	if judgment == "PERFECT":
...
78: 	else:
79: 		push_warning("Unknown judgment: " + judgment)
80: 		return {}
```
`total_notes += 1` executes unconditionally at line 63 before verifying if `judgment` is `"PERFECT"`, `"GOOD"`, or `"MISS"`. An invalid judgment causes `total_notes` to increment while `count_perfect`, `count_good`, and `count_miss` remain unchanged. This desynchronizes `total_notes` from the sum of judgments and permanently depresses the performance accuracy returned by `get_accuracy()`.

#### Defect 4: Floating-Point Subtraction Drops Nominal +100ms Hits as `OUT_OF_WINDOW` (Medium Severity)
In `scripts/scoring_engine.gd` (lines 53–60 & 142):
```gdscript
53: func evaluate_timing(time_diff_sec: float) -> String:
54: 	var abs_diff: float = abs(time_diff_sec)
55: 	if abs_diff <= WINDOW_PERFECT_SEC:
56: 		return "PERFECT"
57: 	elif abs_diff <= WINDOW_GOOD_SEC:
58: 		return "GOOD"
59: 	else:
60: 		return "MISS"
...
142: 		if abs_diff <= WINDOW_GOOD_SEC and abs_diff < min_abs_diff:
```
In IEEE 754 64-bit floating point arithmetic, `(t + 0.100) - t` often evaluates to `0.10000000000000009` (e.g. at `t = 1.0, 30.0, 60.0, 300.0, 600.0`). Because line 142 tests `abs_diff <= WINDOW_GOOD_SEC` (0.100) with zero epsilon tolerance, nominal boundary hits at exactly +100ms are completely rejected by `process_input` (returning `{}` as `OUT_OF_WINDOW`) instead of being evaluated as `GOOD`. Similarly, `(t + 0.050) - t` can evaluate to `0.050000000000000044`, causing an exact nominal 50ms hit to demote to `GOOD` rather than `PERFECT`.

---

### 1.2 Verbatim Test Execution Output

Adversarial test harness `tests/test_scoring_adversarial.gd` was executed via Godot 4.7.2 headless:

```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_adversarial.gd"
```

Verbatim execution log:
```
================================================================================
          ADVERSARIAL STRESS TEST SUITE: SCORING ENGINE & TIMING
================================================================================

--- Test Suite 1: Sub-Millisecond Precision Boundaries ---
  [PASS] +49.90ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] +49.99ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] +50.00ms exact boundary should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] +50.01ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] +50.10ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] +99.90ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] +99.99ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] +100.00ms exact boundary should be GOOD (expected GOOD, got GOOD)
  [PASS] +100.01ms diff should be MISS (expected MISS, got MISS)
  [PASS] +100.10ms diff should be MISS (expected MISS, got MISS)
  [PASS] -49.90ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] -49.99ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] -50.00ms exact boundary should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] -50.01ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] -50.10ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] -99.90ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] -99.99ms diff should be GOOD (expected GOOD, got GOOD)
  [PASS] -100.00ms exact boundary should be GOOD (expected GOOD, got GOOD)
  [PASS] -100.01ms diff should be MISS (expected MISS, got MISS)
  [PASS] -100.10ms diff should be MISS (expected MISS, got MISS)

--- Test Suite 2: Floating-Point Subtraction Precision Across Time ---
  [PASS] Nominal +50ms hit at t=0.0 should be PERFECT or GOOD, got PERFECT
  [PASS] Nominal +100ms hit at t=0.0 should be GOOD, got GOOD
  [PASS] Nominal +50ms hit at t=1.0 should be PERFECT or GOOD, got GOOD
  [FLOAT REJECTION BUG] Nominal +100ms hit dropped as OUT_OF_WINDOW at t=1.0 due to float subtraction!
  [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=1.0
  [PASS] Nominal +50ms hit at t=5.0 should be PERFECT or GOOD, got PERFECT
  [PASS] Nominal +100ms hit at t=5.0 should be GOOD, got GOOD
  [PASS] Nominal +50ms hit at t=10.0 should be PERFECT or GOOD, got GOOD
  [PASS] Nominal +100ms hit at t=10.0 should be GOOD, got GOOD
  [PASS] Nominal +50ms hit at t=30.0 should be PERFECT or GOOD, got GOOD
  [FLOAT REJECTION BUG] Nominal +100ms hit dropped as OUT_OF_WINDOW at t=30.0 due to float subtraction!
  [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=30.0
  [PASS] Nominal +50ms hit at t=60.0 should be PERFECT or GOOD, got PERFECT
  [FLOAT REJECTION BUG] Nominal +100ms hit dropped as OUT_OF_WINDOW at t=60.0 due to float subtraction!
  [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=60.0
  [PASS] Nominal +50ms hit at t=120.0 should be PERFECT or GOOD, got PERFECT
  [PASS] Nominal +100ms hit at t=120.0 should be GOOD, got GOOD
  [PASS] Nominal +50ms hit at t=300.0 should be PERFECT or GOOD, got GOOD
  [FLOAT REJECTION BUG] Nominal +100ms hit dropped as OUT_OF_WINDOW at t=300.0 due to float subtraction!
  [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=300.0
  [PASS] Nominal +50ms hit at t=600.0 should be PERFECT or GOOD, got PERFECT
  [FLOAT REJECTION BUG] Nominal +100ms hit dropped as OUT_OF_WINDOW at t=600.0 due to float subtraction!
  [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=600.0

--- Test Suite 3: Negative and Extreme Timestamps ---
  [PASS] Hit at -0.480s against note at -0.500s should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] Negative timestamp note 0 marked is_hit (expected true, got true)
  [PASS] Early hit at -0.280s against note at -0.200s should be GOOD (expected GOOD, got GOOD)
  [PASS] Extreme timestamp 36000.015s should evaluate PERFECT (expected PERFECT, got PERFECT)
  [PASS] INF timing diff evaluates to MISS without crash (expected MISS, got MISS)
  [PASS] -INF timing diff evaluates to MISS without crash (expected MISS, got MISS)
  [PASS] NAN timing diff evaluates to MISS without crash (expected MISS, got MISS)

--- Test Suite 4: Simultaneous Chords with Duplicate Pitches ---
  [PASS] First unison note hit should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] Combo should be 1 after first unison note (expected 1, got 1)
  [PASS] First unison note marked is_hit
  [PASS] Second unison note remains unhit
  [PASS] Second unison note hit should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] Combo should be 2 after second unison note (expected 2, got 2)
  [PASS] Second unison note now marked is_hit
  [PASS] Third hit on 2-note unison returns empty dictionary
  [PASS] Combo remains 2, not reset by surplus input (expected 2, got 2)
  [PASS] Reverse chord hit: G4 judged PERFECT (expected PERFECT, got PERFECT)
  [PASS] Reverse chord hit: E4 judged PERFECT (expected PERFECT, got PERFECT)
  [PASS] Reverse chord hit: C4 judged PERFECT (expected PERFECT, got PERFECT)
  [PASS] Triad hit in arbitrary order results in combo 3 (expected 3, got 3)
  [PASS] Triad score should be 300 (100 * 3) (expected 300, got 300)

--- Test Suite 5: Semitone Tolerance Behavior ---
  [PASS] Pitch 59 matches Note 60 under tolerance 1 (expected PERFECT, got PERFECT)
  [PASS] Note marked hit
  [PASS] Pitch 62 rejected under tolerance 1
  [PASS] Note remains unhit
  [INFO] Competing notes matching picked: Note with pitch 61 (timediff: 0.0)
  [PASS] Tolerance match matched a note

--- Test Suite 6: Massive Combo Progression (1500+ Notes) ---
  [PASS] Combo should reach exactly 1500 (expected 1500, got 1500)
  [PASS] Max combo should be 1500 (expected 1500, got 1500)
  [PASS] Count perfect should be 1500 (expected 1500, got 1500)
  [PASS] Total notes should be 1500 (expected 1500, got 1500)
  [PASS] Score after 1500 Perfects should be exactly 594,300 (expected 594300, got 594300)
  [PASS] Accuracy after 1500 Perfects should be 100.0% (expected 100.0, got 100.0)
  [PASS] Registered judgment is MISS (expected MISS, got MISS)
  [PASS] Combo immediately drops to 0 (expected 0, got 0)
  [PASS] Max combo preserved at 1500 (expected 1500, got 1500)
  [PASS] Multiplier drops to 1x (expected 1, got 1)
  [PASS] Total notes incremented to 1501 (expected 1501, got 1501)
  [PASS] Accuracy correctly drops to 99.933% after 1 miss
  [PASS] Combo re-ramped to 50 (expected 50, got 50)
  [PASS] Multiplier returned to 4x (expected 4, got 4)
  [PASS] Score correctly updated by 7150 points for 50 Goods (expected 601450, got 601450)

--- Test Suite 7: Expired Notes & Batch Expiration ---
  [PASS] Initial combo is 10 (expected 10, got 10)
  [PASS] No notes expired at 1.09s (expected 0, got 0)
  [PASS] Combo still 10 (expected 10, got 10)
  [PASS] Three notes expired together at 1.15s (expected 3, got 3)
  [PASS] Combo reset to 0 by batch expiration (expected 0, got 0)
  [PASS] Miss count increased by 3 (expected 3, got 3)
  [PASS] Note 65 remains unhit
  [PASS] Note 65 remains unmissed
  [CONTRACT CORRUPTION] Expired note had is_hit set to true!
  [FAIL] CONTRACT CORRUPTION: Expired note marked is_hit=true
  [PASS] Idempotent: no re-expiration at 1.16s (expected 0, got 0)

--- Test Suite 8: Missed Flag Vulnerability Stress Test ---
  [VULNERABILITY DETECTED] process_input matched a note that already had is_missed=true (Dictionary)!
  [FAIL] VULNERABILITY: process_input matched an already-missed Dictionary note
  [VULNERABILITY DETECTED] process_input matched a NoteData that already had is_missed=true!
  [FAIL] VULNERABILITY: process_input matched an already-missed NoteData object

--- Test Suite 9: Malformed and Dirty Inputs ---
  [PASS] Survived dirty notes array and matched valid note (expected PERFECT, got PERFECT)
  [PASS] check_expired_notes survived dirty array
WARNING: Unknown judgment: UNKNOWN_JUDGMENT
   at: push_warning (core/variant/variant_utility.cpp:1033)
  [PASS] Unknown judgment returns empty dictionary
  [FLAW DETECTED] total_notes was incremented from 4 to 5 on invalid judgment!
  [FAIL] total_notes should NOT increment on unknown judgment (expected 4, got 5)

--- Test Suite 10: Rapid Input Fuzzing & Throughput Benchmark ---
  [PASS] Spam inputs did not alter score (expected 0, got 0)
  [PASS] Spam inputs did not alter combo (expected 0, got 0)
  [PASS] Spam inputs did not alter total_notes (expected 0, got 0)
  [BENCHMARK] 10,000 process_input calls took 6.04 ms (1655903.3 calls/sec)
  [PASS] 10,000 queries completed in < 2000ms

--- Test Suite 11: Reset and State Reinitialization ---
  [PASS] Score > 0 before reset
  [PASS] Max combo > 0 before reset
  [PASS] Total notes > 0 before reset
  [PASS] Score reset to 0 (expected 0, got 0)
  [PASS] Combo reset to 0 (expected 0, got 0)
  [PASS] Max combo reset to 0 (expected 0, got 0)
  [PASS] count_perfect reset to 0 (expected 0, got 0)
  [PASS] count_good reset to 0 (expected 0, got 0)
  [PASS] count_miss reset to 0 (expected 0, got 0)
  [PASS] total_notes reset to 0 (expected 0, got 0)
  [PASS] Multiplier reset to 1x (expected 1, got 1)
  [PASS] Accuracy on 0 notes defaults to 100.0% (expected 100.0, got 100.0)

================================================================================
 ADVERSARIAL RESULTS: 102 Passed, 9 Failed
================================================================================

FAILURES ENCOUNTERED:
  - [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=1.0
  - [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=30.0
  - [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=60.0
  - [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=300.0
  - [FAIL] FLOAT REJECTION: Nominal +100ms hit dropped at t=600.0
  - [FAIL] CONTRACT CORRUPTION: Expired note marked is_hit=true
  - [FAIL] VULNERABILITY: process_input matched an already-missed Dictionary note
  - [FAIL] VULNERABILITY: process_input matched an already-missed NoteData object
  - [FAIL] total_notes should NOT increment on unknown judgment (expected 4, got 5)

ADVERSARIAL STRESS TEST COMPLETED WITH FAILURES
```

Exit code: `1`.

---

## 2. Logic Chain

1. **Premise 1 (Missed Note Lifecycle)**: In `highway.gd:137`, when an active highway note scrolls past `current_song_time > note.time_sec + miss_window_sec`, `highway.gd` sets `note.is_missed = true` and leaves `note.is_hit = false` until despawn culling (`tail_x < -60`, approx 550ms later).
2. **Inference 1**: In `scripts/scoring_engine.gd:132`, `process_input` only executes `if is_hit: continue`. Because `is_missed` is never checked, any note marked missed by Highway is still accepted by `process_input` if an input event arrives with a matching timestamp. This was empirically confirmed in Suite 8: `process_input` successfully returned a hit for both Dictionary and `NoteData` objects that already had `is_missed = true`.
3. **Premise 2 (State Corruption in Expiration)**: To work around Premise 1, `check_expired_notes` sets `note.is_hit = true` on expired notes (lines 190 and 200).
4. **Inference 2**: Setting `is_hit = true` on a note that was missed corrupts the `NoteData` contract. In Suite 7, an expired note was inspected and found to have `is_hit == true`. Downstream systems cannot distinguish hit notes from missed notes.
5. **Premise 3 (Floating-Point Epsilon)**: Floating-point arithmetic on 64-bit IEEE 754 floats is not exact. For timestamps `t = 1.0, 30.0, 60.0, 300.0, 600.0`, `(t + 0.100) - t` yields values strictly greater than `0.100` (e.g. `0.10000000000000009`).
6. **Inference 3**: In `scoring_engine.gd:142`, `if abs_diff <= WINDOW_GOOD_SEC and abs_diff < min_abs_diff:` rejects `0.10000000000000009` as `OUT_OF_WINDOW`. In Suite 2, legitimate hits at exactly the +100ms Good boundary were discarded completely without judgment. Adding a microsecond epsilon (e.g. `const TIMING_EPSILON: float = 0.0001` or `1e-5`) is mathematically required for robust boundary checking.
7. **Premise 4 (Accuracy Calculation Invariant)**: The accuracy calculation formula `(count_perfect * 1.0 + count_good * 0.5) / total_notes * 100.0` assumes that `total_notes == count_perfect + count_good + count_miss`.
8. **Inference 4**: In `scoring_engine.gd:63`, `total_notes += 1` occurs before validating `judgment`. In Suite 9, passing an invalid judgment string incremented `total_notes` while returning `{}` and leaving judgment counts untouched, permanently distorting performance accuracy.

---

## 3. Caveats

- **No live microphone hardware stream**: As specified in the roadmap, live microphone capture and ONNX neural pitch inference are scheduled for Milestone 3 (`IAudioPitchModel` and Spotify Basic Pitch). All adversarial testing in Milestone 1 used programmatic timestamps, audio playhead simulations, and synthetic note clusters.
- **Robust areas verified**:
  - Unison chords with identical pitches at the exact same timestamp are handled cleanly (consecutive hits consume each note in sequence without re-triggering or combo reset).
  - Reverse-order polyphonic chord hits (C-Major triad) evaluate and award points correctly.
  - Massive combo scaling up to 1,500 consecutive notes executes with zero numerical overflow (score 594,300), preserves max combo on miss, drops multiplier to 1x, and recalculates weighted accuracy accurately.
  - Input spamming throughput exceeds 1,600,000 queries per second without side effects or leaks.
  - Negative and extreme timestamps (up to 36,000s, INF, -INF, NAN) are handled without crashing.

---

## 4. Conclusion

**VERDICT: REQUEST_CHANGES**

The scoring engine has 4 concrete, empirically reproducible defects that violate state integrity and timing evaluation:
1. `process_input` does not check `is_missed`, enabling double-scoring of missed notes.
2. `check_expired_notes` incorrectly sets `note.is_hit = true` on expired notes.
3. `register_hit` increments `total_notes` before validating `judgment`.
4. Strict float comparisons without epsilon cause nominal +100ms hits to be dropped as `OUT_OF_WINDOW`.

### Actionable Remediation Items for Worker:

1. In `scripts/scoring_engine.gd`:
   - Add `const TIMING_EPSILON: float = 0.0001` (0.1ms).
   - In `evaluate_timing(time_diff_sec: float)`:
     ```gdscript
     if abs_diff <= WINDOW_PERFECT_SEC + TIMING_EPSILON:
         return "PERFECT"
     elif abs_diff <= WINDOW_GOOD_SEC + TIMING_EPSILON:
         return "GOOD"
     else:
         return "MISS"
     ```
   - In `process_input()`:
     - Check `is_missed` alongside `is_hit`:
       ```gdscript
       var is_missed: bool = false
       if note is Dictionary:
           is_hit = bool(note.get("is_hit", false))
           is_missed = bool(note.get("is_missed", false))
           ...
       elif note is RefCounted ...:
           is_hit = note.is_hit
           is_missed = note.is_missed if "is_missed" in note else false
           ...
       if is_hit or is_missed:
           continue
       ```
     - Use `abs_diff <= WINDOW_GOOD_SEC + TIMING_EPSILON` for window checking.
   - In `check_expired_notes()`:
     - Remove `note["is_hit"] = true` and `note.is_hit = true` (only set `is_missed = true`). Because `process_input()` will now check `is_missed`, `is_hit` remains cleanly `false`.
   - In `register_hit(judgment: String, note_data: Dictionary = {})`:
     - Validate `judgment` before mutating state:
       ```gdscript
       if judgment != "PERFECT" and judgment != "GOOD" and judgment != "MISS":
           push_warning("Unknown judgment: " + judgment)
           return {}
       total_notes += 1
       ```

---

## 5. Verification Method

To independently reproduce the failures and verify remediation:

1. **Run the Adversarial Test Runner**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_adversarial.gd"
   ```
   - Current state: Fails with exit code 1, reporting 9 failures across Suites 2, 7, 8, and 9.
   - Fixed state: Must exit with code 0, reporting all passed.

2. **Run Baseline Unit Test Runner**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
   ```
   - Expected outcome: Exit code 0, 91 passed.

3. **Run Full E2E Test Suite**:
   ```powershell
   python tests/e2e/run_all_e2e_tests.py
   ```
   - Expected outcome: Exit code 0, 230 passed.
