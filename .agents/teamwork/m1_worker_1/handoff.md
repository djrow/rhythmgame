# Milestone 1: Grand Staff Highway & Scoring - Hard Handoff Report

**Author**: `m1_worker_1` (Teamwork Implementer & QA)  
**Date**: 2026-10-16  
**Milestone**: Milestone 1 (M1) — Grand Staff Highway & Scoring  
**Project Root**: `c:\Users\david\Documents\micgame-3`  

---

## 1. Observation

### 1.1 Pre-Modification State & Errors
Direct inspection of `project.godot` revealed orphaned references to missing plugins:
- Lines 23-26: `[autoload]` referencing `*res://addons/godot_ai/runtime/game_helper.gd`.
- Lines 34-37: `[editor_plugins]` referencing `res://addons/godot_ai/plugin.cfg`.
Prior to remediation, launching Godot headlessly failed with:
```
ERROR: Attempt to open script 'res://addons/godot_ai/runtime/game_helper.gd' resulted in error 'File not found'.
ERROR: Failed to instantiate an autoload, can't load from path: res://addons/godot_ai/runtime/game_helper.gd.
```
Exit code: `1`.

### 1.2 Implemented Artifacts
The following files were authored and placed in their designated directories:
- `project.godot`: Cleaned orphaned autoloads and editor plugins; configured viewport 1280x720, `gl_compatibility` renderer, audio input enabled, and `run/main_scene="res://scenes/main.tscn"`.
- `scripts/note_data.gd`: Diatonic step precomputation ($D(M) = O \times 7 + \text{DiatonicOffset}[P]$), vertical staff coordinate positioning ($Y = 360 - (D - 28) \times 9$), Middle C ledger line symmetry ($Y=360$, step 28), and dynamic ledger line generation for high Treble ($\ge 40$, up to C6+ at $Y=234$) and low Bass ($\le 16$, down to C2 at $Y=486$).
- `scripts/note_renderer.gd`: 2D CanvasItem vector rendering note heads, diatonic pitch labels, sharps, sustain trails with rounded endcaps, vertical chord stems, and ledger lines.
- `scripts/highway.gd` & `scenes/highway.tscn`: Dual Grand Staff (Treble lines at $Y \in [270, 288, 306, 324, 342]$, Bass lines at $Y \in [378, 396, 414, 432, 450]$, Middle C at $Y=360$), continuous right-to-left scrolling towards hit line at $X=160$ ($V_{\text{scroll}}=400$ px/s), zero-allocation sliding window pooling and culling (despawn threshold $X < -60$), sub-frame audio playhead sync with monotonic clamp, and live hit ripple effects.
- `scripts/scoring_engine.gd`: Pure logic scoring engine with strict timing windows (Perfect $\le 50$ms, Good $\le 100$ms, Miss $> 100$ms), combo streaks, dynamic multipliers (1x for 0-9, 2x for 10-19, 3x for 20-29, 4x for 30+), polyphonic chord pitch matching, and note expiration checks. Supports both `NoteData` objects and dictionary representations.
- `scripts/hud.gd` & `scenes/hud.tscn`: UI CanvasLayer displaying tweened score ticks (`%06d`), bouncing combo counter, multiplier badge with tiered colors, and floating upward-drifting judgment popups.
- `scripts/main.gd` & `scenes/main.tscn`: Root game scene orchestrating Highway, HUD, ScoringEngine, and AudioStreamPlayer, featuring demo chart playback spanning C2 to C6+ with chord progression, keyboard strumming for manual testing, and Android audio permission request.
- `tests/test_scoring_runner.gd`: Self-contained headless test runner executing 6 comprehensive test suites.

### 1.3 Execution Commands & Verbatim Outputs

#### Command 1: Godot Headless Project Startup Check
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit
```
Output:
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
```
Exit Code: `0` (clean startup and termination, 0 errors, 0 warnings).

#### Command 2: Headless Scoring Runner Verification
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
```
Output:
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

==================================================
 RUNNING SCORING ENGINE HEADLESS VERIFICATION
==================================================

--- Test Suite 1: Timing Windows (Perfect <= 50ms, Good <= 100ms, Miss > 100ms) ---
  [PASS] 0ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] +25ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] -45ms diff should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] Exact +50ms boundary should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] Exact -50ms boundary should be PERFECT (expected PERFECT, got PERFECT)
  [PASS] +51ms should be GOOD (expected GOOD, got GOOD)
  [PASS] -75ms should be GOOD (expected GOOD, got GOOD)
  [PASS] Exact +100ms boundary should be GOOD (expected GOOD, got GOOD)
  [PASS] Exact -100ms boundary should be GOOD (expected GOOD, got GOOD)
  [PASS] +101ms should be MISS (expected MISS, got MISS)
  [PASS] -150ms should be MISS (expected MISS, got MISS)
  [PASS] +500ms should be MISS (expected MISS, got MISS)

--- Test Suite 2: Scoring Formulas & Multiplier Progression ---
  [PASS] Hit 1 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 2 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 3 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 4 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 5 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 6 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 7 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 8 multiplier should be 1x (expected 1, got 1)
  [PASS] Hit 9 multiplier should be 1x (expected 1, got 1)
  [PASS] Score after 9 Perfects at 1x should be 900 (expected 900, got 900)
  [PASS] Combo should be 9 (expected 9, got 9)
  [PASS] 10th hit triggers 2x multiplier (expected 2, got 2)
  [PASS] 10th hit awards 100 * 2 = 200 pts (expected 200, got 200)
  [PASS] Total score after 10th hit should be 900 + 200 = 1100 (expected 1100, got 1100)
  [PASS] Combo should be 10 (expected 10, got 10)
  [PASS] Combo 11 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 12 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 13 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 14 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 15 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 16 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 17 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 18 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo 19 multiplier should be 2x (expected 2, got 2)
  [PASS] Combo should be 19 (expected 19, got 19)
  [PASS] Score after 19 hits should be 2900 (expected 2900, got 2900)
  [PASS] 20th hit triggers 3x multiplier (expected 3, got 3)
  [PASS] 20th hit awards 100 * 3 = 300 pts (expected 300, got 300)
  [PASS] Total score after 20th hit should be 2900 + 300 = 3200 (expected 3200, got 3200)
  [PASS] Combo should be 20 (expected 20, got 20)
  [PASS] Combo 21 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 22 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 23 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 24 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 25 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 26 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 27 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 28 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo 29 multiplier should be 3x (expected 3, got 3)
  [PASS] Combo should be 29 (expected 29, got 29)
  [PASS] Score after 29 hits should be 5900 (expected 5900, got 5900)
  [PASS] 30th hit triggers 4x multiplier (expected 4, got 4)
  [PASS] 30th hit awards 100 * 4 = 400 pts (expected 400, got 400)
  [PASS] Total score after 30th hit should be 5900 + 400 = 6300 (expected 6300, got 6300)
  [PASS] Combo should be 30 (expected 30, got 30)
  [PASS] 31st hit multiplier should remain capped at 4x (expected 4, got 4)
  [PASS] Good at 4x awards 50 * 4 = 200 pts (expected 200, got 200)
  [PASS] Total score after 31st hit should be 6300 + 200 = 6500 (expected 6500, got 6500)
  [PASS] Combo should be 31 (expected 31, got 31)

--- Test Suite 3: Miss & Streak Reset ---
  [PASS] Combo should be 15 (expected 15, got 15)
  [PASS] Multiplier should be 2x (expected 2, got 2)
  [PASS] Judgment is MISS (expected MISS, got MISS)
  [PASS] Miss awards 0 pts (expected 0, got 0)
  [PASS] Score does not increase on miss (expected 2100, got 2100)
  [PASS] Combo immediately resets to 0 on miss (expected 0, got 0)
  [PASS] Multiplier drops back to 1x (expected 1, got 1)
  [PASS] Max combo remains preserved at 15 (expected 15, got 15)
  [PASS] Next hit after miss is at 1x (expected 1, got 1)
  [PASS] Next hit awards 100 pts (expected 100, got 100)
  [PASS] Combo restarts at 1 (expected 1, got 1)

--- Test Suite 4: Polyphonic Pitch Matching & Timing Offset ---
  [PASS] C4 at +20ms should be judged PERFECT (expected PERFECT, got PERFECT)
  [PASS] Note C4 marked as is_hit (expected true, got true)
  [PASS] Note E4 should remain unhit (expected false, got false)
  [PASS] Wrong pitch MIDI 62 should match nothing
  [PASS] E4 at +70ms should be judged GOOD (expected GOOD, got GOOD)
  [PASS] Note E4 marked as is_hit (expected true, got true)
  [PASS] G4 at +150ms is outside hit window, returns empty
  [PASS] G4 remains unhit (expected false, got false)

--- Test Suite 5: Note Expiration (Miss on Passing Hit Window) ---
  [PASS] Combo is 5 (expected 5, got 5)
  [PASS] No notes expired at 2.05s (expected 0, got 0)
  [PASS] Combo remains 5 (expected 5, got 5)
  [PASS] 1 note expired at 2.12s (expected 1, got 1)
  [PASS] Expired note awarded MISS (expected MISS, got MISS)
  [PASS] Combo reset to 0 by expired note (expected 0, got 0)
  [PASS] Note 60 marked is_missed (expected true, got true)
  [PASS] Note 64 at 2.50s remains untouched (expected false, got false)
  [PASS] No duplicate expiration (expected 0, got 0)

--- Test Suite 6: Performance Accuracy Percentage ---
  [PASS] Accuracy for 2 Perfect + 2 Good out of 4 should be 75.0% (expected 75.0, got 75.0)
  [PASS] Accuracy with 1 added Miss should be 60.0% (expected 60.0, got 60.0)
==================================================
 RESULTS: 91 Passed, 0 Failed
==================================================
ALL SCORING MECHANICS VERIFIED SUCCESSFULLY [OK]
```
Exit Code: `0`.

#### Command 3: Full Simulation Frame Execution
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit-after 120
```
Output:
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
```
Exit Code: `0` (main scene runs and steps through 120 frames with full scene tree loaded).

---

## 2. Logic Chain

1. **Root Cause Resolution**: The inability to run Godot headlessly was directly caused by the missing files `res://addons/godot_ai/runtime/game_helper.gd` and `res://addons/godot_ai/plugin.cfg` listed in `project.godot`. Removing those orphaned blocks allowed the Godot engine parser to initialize without fatal errors.
2. **Diatonic Coordinate Symmetry**: Anchoring Middle C (C4, MIDI 60, diatonic step 28) at $Y=360$ px with vertical step height $\Delta y = 9$ px results in Treble Line 1 (E4, step 30) at $Y=342$ px and Bass Line 5 (A3, step 26) at $Y=378$ px. This forms an exact $36$ px gap with Middle C sitting at the exact midpoint ($18$ px equidistant from both staves).
3. **Dynamic Ledger Engine**: Ledger lines are restricted to even diatonic steps outside the 5-line staff bounds. Step 28 produces 1 ledger at $Y=360$; steps $\ge 40$ produce ledgers for even steps up to the pitch (e.g., C6 step 42 has ledgers at $Y=252$ and $Y=234$); steps $\le 16$ produce ledgers down to the pitch (e.g., C2 step 14 has ledgers at $Y=468$ and $Y=486$).
4. **Scrolling & Sub-Frame Synchronization**: Notes scroll right-to-left governed by $X(t_{\text{note}}, T) = 160 + (t_{\text{note}} - T) \times 400$. Playhead time $T$ incorporates hardware mix offset and output latency with monotonic clamping, ensuring jitter-free crossing at $X=160$ px when $T = t_{\text{note}}$, with a fallback delta accumulator for headless CI testing.
5. **Decoupled Scoring Engine**: By accepting both `NoteData` objects and dictionary representations, `ScoringEngine` supports headless unit testing and production scene interaction with identical real state machines (timing windows $\pm 50$ms / $\pm 100$ms, combo streaks, 1x-4x multipliers, expired note handling, and polyphonic pitch matching).

---

## 3. Caveats

- Microphone capture hardware input: While `driver/enable_input=true` and Android runtime permission request logic are present, live microphone streaming with ONNX inference is explicitly assigned to Milestone 3 (`IAudioPitchModel` and Spotify Basic Pitch). Milestone 1 implements keyboard chord/note emulation for real-time playtesting and programmatic pitch input.
- Audio accompaniment asset: The demo chart currently uses Godot's fallback internal clock since bundled song WAV/OGG files will be generated in Milestone 2. When an `AudioStream` is assigned to `AudioPlayer`, the playhead synchronizer automatically locks onto the audio mix position.

---

## 4. Conclusion

Milestone 1: Grand Staff Highway & Scoring is completely implemented, verified, and compliant with all acceptance criteria and integrity rules.
- `project.godot` loads cleanly.
- Visual highway renders dual Treble and Bass staves, Middle C, dynamic ledger lines, accidentals, and scrolling sustain trails.
- Real-time scoring engine validates timing windows, streaks, multipliers, chords, and expired note handling.
- All 91 automated unit and integration assertions pass headlessly with exit code 0.

---

## 5. Verification Method

To independently verify this milestone, execute:

1. **Verify Headless Load & Scene Initialization**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit
   ```
   *Expected outcome*: Exit code 0, no errors or warnings.

2. **Verify Scoring Engine & Timing Mechanics**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
   ```
   *Expected outcome*: Exit code 0, 91 passed assertions, 0 failures.

3. **Verify Runtime Game Loop**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit-after 120
   ```
   *Expected outcome*: Exit code 0, smooth 120-frame headless loop execution.
