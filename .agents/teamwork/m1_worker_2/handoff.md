# Milestone 1 Remediation: Adversarial Defect Fixes — Handoff Report

**Author**: `m1_worker_2` (Implementation Worker)  
**Date**: 2026-10-16  
**Milestone**: Milestone 1 (M1) — Grand Staff Highway & Scoring Remediation  
**Project Root**: `c:\Users\david\Documents\micgame-3`  
**Verdict**: **REMEDIATION_COMPLETE** (100% Pass Across All Suites)

---

## 1. Observation

### 1.1 Initial Failures Identified by Challengers
Adversarial stress testing by `m1_challenger_1` and `m1_challenger_2` highlighted the following baseline failures:

1. **`test_scoring_adversarial.gd`**: Fails with 9 failed assertions across Suites 2, 7, 8, 9 (exit code 1):
   - Suite 2: Nominal +100ms hits dropped as `OUT_OF_WINDOW` at `t = 1.0, 30.0, 60.0, 300.0, 600.0` due to IEEE 754 float subtraction inaccuracy (`(t + 0.100) - t = 0.10000000000000009 > 0.100`).
   - Suite 7: `check_expired_notes()` set `note.is_hit = true` on expired notes, corrupting the `NoteData` contract.
   - Suite 8: `process_input()` only checked `is_hit` and ignored `is_missed`, allowing double-matching of already-missed notes.
   - Suite 9: `register_hit()` incremented `total_notes += 1` before validating if `judgment` was one of `"PERFECT"`, `"GOOD"`, or `"MISS"`, permanently degrading accuracy calculations.
2. **`test_adversarial_m1.gd`**: Fails with 2 failed assertions and 3 empirical findings:
   - Suite 1: `NoteData` clamped `p_midi` to `[21, 108]`, mutating C0 (MIDI 12) into A0 (MIDI 21).
   - Suite 3: Dense chord clusters of 3+ seconds (e.g. C4, D4, E4, F4) displaced all upper notes to `chord_offset_x = 16.0`, causing noteheads between adjacent seconds (D4 and E4, E4 and F4) to collide with only 9.0px center distance (< 17px collision threshold).
   - Suite 4: `load_notes()` chord detection performed an unconstrained $O(N^2)$ inner loop, taking ~1,869 ms for a 5,000-note chart.
   - Suite 5: When `scroll_speed <= 0.0`, `spawn_lookahead` evaluated to `INF`.

### 1.2 Remediations Implemented

#### File: `scripts/scoring_engine.gd`
- **Fix 1 (`process_input` Missed Flag Check)**:
  Lines 117-133:
  Extracted `is_missed` from Dictionary (`bool(note.get("is_missed", false))`) and RefCounted (`note.is_missed if "is_missed" in note else false`).
  Checked `if is_hit or is_missed: continue`.
- **Fix 2 (`check_expired_notes` Missed Flag without `is_hit`)**:
  Lines 180-207:
  Removed `note["is_hit"] = true` and `note.is_hit = true`. Only set `is_missed = true` (and `hit_rating = "MISS"`).
- **Fix 3 (`register_hit` Judgment Validation)**:
  Lines 63-66:
  Validated `judgment != "PERFECT" and judgment != "GOOD" and judgment != "MISS"` and returned `{}` BEFORE executing `total_notes += 1`.
- **Fix 4 (`TIMING_EPSILON` Float Tolerance)**:
  Line 9: Defined `const TIMING_EPSILON: float = 0.000005` (5 microseconds).
  Lines 55-58: Checked `abs_diff <= WINDOW_PERFECT_SEC + TIMING_EPSILON` and `abs_diff <= WINDOW_GOOD_SEC + TIMING_EPSILON`.
  Line 144: In `process_input()`, checked `abs_diff <= (WINDOW_GOOD_SEC + TIMING_EPSILON)`.

#### File: `scripts/highway.gd`
- **Fix 5 (`load_notes` $O(N)$ Optimization)**:
  Lines 85-98:
  Sorted `chart_notes` chronologically with secondary sort on `diatonic_step`.
  Grouped simultaneous notes using a window-bounded sliding pointer (`absf(chart_notes[j].time_sec - chart_notes[idx].time_sec) < 0.005`), reducing 5,000-note load time from 1,869 ms to 34.7 ms.
- **Fix 6 (Dense Cluster Alternating Offsets)**:
  Lines 100-125:
  For each chord, sorted notes by `diatonic_step` ascending and detected contiguous runs of adjacent diatonic steps (`step[r+1] - step[r] == 1`).
  Assigned alternating offsets: `(r - k) % 2 == 1 ? 16.0 : 0.0`, ensuring Euclidean center distance $\sqrt{16.0^2 + 9.0^2} = 18.36\text{ px} \ge 17.0\text{ px}$.
- **Fix 7 (`spawn_lookahead` Guard & `scroll_speed` Setter)**:
  Lines 24-26: Added setter to `scroll_speed` using `maxf(value, 1.0)`.
  Lines 150 & 222: Guarded `spawn_lookahead` using `(SCREEN_WIDTH - x_hit + SPAWN_MARGIN_PX) / maxf(scroll_speed, 1.0)`.
  Lines 242-246: Expanded `set_live_pitch` guard to `midi >= 0 and midi <= 127`.

#### File: `scripts/note_data.gd`
- **Fix 8 (Full MIDI Range [0, 127])**:
  Line 39: Updated clamp from `clampi(p_midi, 21, 108)` to `clampi(p_midi, 0, 127)`.

---

## 2. Logic Chain

1. **Epsilon Tolerance Safety**:
   - `0.05001s` is $10\,\mu\text{s}$ above $50\,\text{ms}$, and `0.10001s` is $10\,\mu\text{s}$ above $100\,\text{ms}$.
   - Selecting `TIMING_EPSILON = 0.000005` ($5\,\mu\text{s}$) strictly accommodates IEEE 754 subtraction errors ($\approx 10^{-14}\text{ to } 10^{-16}$) while preserving sub-millisecond judgment boundaries (`0.05001s` > $0.050005\text{s} \rightarrow$ `GOOD`, `0.10001s` > $0.100005\text{s} \rightarrow$ `MISS`).
2. **Lifecycle Contract Coherence**:
   - Marking `is_missed = true` without setting `is_hit = true` satisfies both the `NoteData` contract (`is_hit == false` on miss) and the idempotency requirement (`process_input` and `check_expired_notes` both skip when `is_hit or is_missed` is true).
3. **Collision Avoidance via Alternating Parity**:
   - Any two adjacent diatonic steps have vertical separation $\Delta Y = 9.0\text{ px}$.
   - By alternating horizontal displacement between $0.0\text{ px}$ and $16.0\text{ px}$ for consecutive notes in a run of seconds, $\Delta X = 16.0\text{ px}$ for all adjacent pairs.
   - Euclidean center-to-center distance is $\sqrt{16^2 + 9^2} = 18.36\text{ px} \ge 17.0\text{ px}$ (circular notehead diameter is 17px). Thus no physical overlap occurs for clusters of arbitrary length (3, 4, or more adjacent seconds).
4. **Algorithmic Complexity Reduction**:
   - In `load_notes`, grouping notes within $\Delta t < 0.005\text{s}$ advances the outer index `idx` to the chord's upper bound `j`.
   - Each note in `chart_notes` is visited exactly once in the grouping loop.
   - Since chord sizes in standard musical charts are bounded by small constants ($K \le 10$), sorting each chord slice requires negligible operations ($O(K \log K) \le 33$ operations).
   - Overall execution time dropped by >98% (from 1,869 ms to 34.7 ms).

---

## 3. Caveats

- Live microphone hardware capture and Spotify Basic Pitch neural network inference are part of Milestone 3 (`IAudioPitchModel` and `basic-pitch`), as outlined in `PROJECT.md`.
- All tests here verify visual notation, diatonic geometry, chord collisions, timing windows, combo multipliers, and synthetic audio-playhead synchronization.
- No other caveats.

---

## 4. Conclusion

**VERDICT: REMEDIATION_COMPLETE**

All 8 remediation tasks were implemented cleanly without regressions or unnecessary refactoring. All baseline and adversarial test suites now pass with 100% assertions and zero findings.

---

## 5. Verification Method

### Test Commands and Verbatim Output

#### 1. Baseline Scoring Runner (`res://tests/test_scoring_runner.gd`)
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
```
**Result**: Exit code `0`
```
==================================================
 RESULTS: 91 Passed, 0 Failed
==================================================
ALL SCORING MECHANICS VERIFIED SUCCESSFULLY [OK]
```

#### 2. Adversarial Scoring Runner (`res://tests/test_scoring_adversarial.gd`)
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_adversarial.gd"
```
**Result**: Exit code `0`
```
================================================================================
 ADVERSARIAL RESULTS: 111 Passed, 0 Failed
================================================================================
ALL ADVERSARIAL STRESS TESTS COMPLETED SUCCESSFULLY [OK]
```

#### 3. Adversarial Milestone 1 Highway Runner (`res://tests/test_adversarial_m1.gd`)
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_adversarial_m1.gd"
```
**Result**: Exit code `0`
```
================================================================================
 ADVERSARIAL TEST RESULTS: 78 Passed, 0 Failed
================================================================================

No vulnerabilities or defects found.
```

#### 4. Full E2E Test Suite (`tests/e2e/run_all_e2e_tests.py`)
```powershell
python tests/e2e/run_all_e2e_tests.py
```
**Result**: Exit code `0`
```
================================================================================
           MICGAME-3 E2E TEST RUNNER - AUTOMATED QUALITY REPORT
================================================================================
Tier Name                              | Total  | Passed | Fail  | Err   | Time (s)
--------------------------------------------------------------------------------
Tier 1: Feature Coverage               | 100    | 100    | 0     | 0     | 0.307   
Tier 2: Boundary & Corner Cases        | 100    | 100    | 0     | 0     | 0.089   
Tier 3: Cross-Feature Combinations     | 20     | 20     | 0     | 0     | 0.072   
Tier 4: Real-World Scenarios           | 10     | 10     | 0     | 0     | 0.001   
--------------------------------------------------------------------------------
TOTAL                                  | 230    | 230    | 0     | 0     | 0.470   
================================================================================
FINAL ASSESSMENT:
 [PASS] All 230 E2E tests executed and passed successfully in 0.470 seconds.
 Coverage: Tier 1 (100), Tier 2 (100), Tier 3 (20), Tier 4 (10).
 100% Pass Rate requirement fulfilled. Exit code: 0
```
