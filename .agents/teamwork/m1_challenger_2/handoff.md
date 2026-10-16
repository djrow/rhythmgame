# Milestone 1: Grand Staff Highway & Scoring — Adversarial Stress Test Report

**Author**: `m1_challenger_2` (Teamwork Adversarial Challenger)  
**Date**: 2026-10-16  
**Milestone**: Milestone 1 (M1) — Grand Staff Highway & Scoring  
**Verdict**: **REQUEST_CHANGES**  
**Project Root**: `c:\Users\david\Documents\micgame-3`  

---

## 1. Observation

Adversarial stress testing was conducted against the implementation delivered by `m1_worker_1`. Tests were executed via Godot 4.7.2 headless test harness `tests/test_adversarial_m1.gd`.

### 1.1 Test Execution Command & Verbatim Output

```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_adversarial_m1.gd"
```

Verbatim Output:
```
Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org

================================================================================
          ADVERSARIAL STRESS TEST HARNESS — MILESTONE 1 (M1)
================================================================================

--- Suite 1: Extreme Pitch Geometry & Ledger Lines ---
  [PASS] C4 MIDI pitch is 60 (expected 60, got 60)
  [PASS] C4 pitch name is C4 (expected C4, got C4)
  [PASS] C4 diatonic step is 28 (expected 28, got 28)
  [PASS] C4 Y position is exactly Y=360.0 (expected ~360.000000, got 360.000000)
  [PASS] C4 has exactly 1 ledger line (expected 1, got 1)
  [PASS] C4 ledger line is at Y=360.0 (expected ~360.000000, got 360.000000)
  [PASS] C2 MIDI pitch is 36 (expected 36, got 36)
  [PASS] C2 pitch name is C2 (expected C2, got C2)
  [PASS] C2 diatonic step is 14 (expected 14, got 14)
  [PASS] C2 Y position is Y=486.0 (expected ~486.000000, got 486.000000)
  [PASS] C2 has 2 ledger lines below Bass staff (expected 2, got 2)
  [PASS] C2 1st ledger is E2 at Y=468.0 (expected ~468.000000, got 468.000000)
  [PASS] C2 2nd ledger is C2 at Y=486.0 (expected ~486.000000, got 486.000000)
  [PASS] C6 MIDI pitch is 84 (expected 84, got 84)
  [PASS] C6 pitch name is C6 (expected C6, got C6)
  [PASS] C6 diatonic step is 42 (expected 42, got 42)
  [PASS] C6 Y position is Y=234.0 (expected ~234.000000, got 234.000000)
  [PASS] C6 has 2 ledger lines above Treble staff (expected 2, got 2)
  [PASS] C6 1st ledger is A5 at Y=252.0 (expected ~252.000000, got 252.000000)
  [PASS] C6 2nd ledger is C6 at Y=234.0 (expected ~234.000000, got 234.000000)
  [PASS] C8 MIDI pitch is 108 (expected 108, got 108)
  [PASS] C8 pitch name is C8 (expected C8, got C8)
  [PASS] C8 diatonic step is 56 (expected 56, got 56)
  [PASS] C8 Y position is Y=108.0 (expected ~108.000000, got 108.000000)
  [PASS] C8 has 9 ledger lines (expected 9, got 9)
  [PASS] C8 first ledger is at Y=252.0 (expected ~252.000000, got 252.000000)
  [PASS] C8 highest ledger is at Y=108.0 (expected ~108.000000, got 108.000000)
  [FAIL] NoteData supports C0 (MIDI 12) without clamping to A0 (MIDI 21)
  [PASS] midi_to_step(12) returns diatonic step 0 (expected 0, got 0)
  [PASS] midi_to_y(12) returns Y=612.0 (expected ~612.000000, got 612.000000)
  [PASS] C0 (step 0) has 9 ledger lines (expected 9, got 9)

--- Suite 2: Out-of-Range MIDI Numbers ---
  [PASS] Negative MIDI -1 clamped safely to valid range (got 21)
  [PASS] Negative MIDI -1 produced finite Y position (567.000000)
  [PASS] midi_to_y(-1) produces finite Y (684.000000)
  [PASS] Negative MIDI -12 clamped safely to valid range (got 21)
  [PASS] Negative MIDI -12 produced finite Y position (567.000000)
  [PASS] midi_to_y(-12) produces finite Y (738.000000)
  [PASS] Negative MIDI -24 clamped safely to valid range (got 21)
  [PASS] Negative MIDI -24 produced finite Y position (567.000000)
  [PASS] midi_to_y(-24) produces finite Y (801.000000)
  [PASS] Negative MIDI -100 clamped safely to valid range (got 21)
  [PASS] Negative MIDI -100 produced finite Y position (567.000000)
  [PASS] midi_to_y(-100) produces finite Y (1206.000000)
  [PASS] Excessive MIDI 128 clamped to valid range (got 108)
  [PASS] Excessive MIDI 128 produced finite Y position (108.000000)
  [PASS] Excessive MIDI 150 clamped to valid range (got 108)
  [PASS] Excessive MIDI 150 produced finite Y position (108.000000)
  [PASS] Excessive MIDI 255 clamped to valid range (got 108)
  [PASS] Excessive MIDI 255 produced finite Y position (108.000000)
  [PASS] Excessive MIDI 1000 clamped to valid range (got 108)
  [PASS] Excessive MIDI 1000 produced finite Y position (108.000000)
  [PASS] set_live_pitch(-10) resets indicator to -1.0 (expected -1.0, got -1.0)
  [PASS] set_live_pitch(150) resets indicator to -1.0 (expected -1.0, got -1.0)
  [INFO] Highway.set_live_pitch(12) ignored C0 because guard is [21..108]

--- Suite 3: Dense Chord Stacking & Collision Handling ---
  [PASS] Fifth C4 has 0.0 horizontal offset (expected 0.0, got 0.0)
  [PASS] Fifth G4 has 0.0 horizontal offset (expected 0.0, got 0.0)
  [PASS] Fifth vertical distance (36.000000 px) exceeds note diameter 17px
  [PASS] Octave note C3 has 0.0 horizontal offset (expected 0.0, got 0.0)
  [PASS] Octave note C4 has 0.0 horizontal offset (expected 0.0, got 0.0)
  [PASS] Octave note C5 has 0.0 horizontal offset (expected 0.0, got 0.0)
  [PASS] Second pair separated horizontally by >= 15px (got 16.000000 px)
  [PASS] Second pair 2D distance (18.357560 px) clears notehead collision (17px)
  Cluster offsets: C4=0.0, D4=16.0, E4=16.0, F4=16.0
  [COLLISION DETECTED] D4 and E4 in 4-note second cluster: dx=0.0, dy=9.0, dist=9.00 < 17.0px
  [COLLISION DETECTED] E4 and F4 in 4-note second cluster: dx=0.0, dy=9.0, dist=9.00 < 17.0px
  [FAIL] Dense cluster of 4 seconds has NO notehead collisions (< 17px center-to-center)

--- Suite 4: Scrolling Pooling & Memory Stability (5,000 Notes Chart) ---
  Generated 5,000 notes chart. Measuring load_notes performance...
  load_notes(5000 notes) completed in 1869.31 ms
  [PASS] Highway loaded exactly 5000 notes (expected 5000, got 5000)
  [PASS] load_notes for 5,000 notes completed in reasonable time (< 5000ms, took 1869.31 ms)
  Max active pooled notes on screen during playback: 193 (out of 5,000)
  Memory difference after 600 frames: 4.95 KB
  [PASS] Active notes pool is strictly bounded (< 400, observed peak 193)
  [PASS] Spawn index advanced through chart (648 / 5000)
  [PASS] Culling properly removes expired notes behind despawn threshold

--- Suite 5: Extreme Scroll Speeds ---
  [PASS] Highway progressed normally at scroll_speed=100.0
  [PASS] Active notes pool stable at scroll_speed=100.0
  [PASS] Highway progressed normally at scroll_speed=400.0
  [PASS] Active notes pool stable at scroll_speed=400.0
  [PASS] Highway progressed normally at scroll_speed=1500.0
  [PASS] Active notes pool stable at scroll_speed=1500.0
  [PASS] Highway progressed normally at scroll_speed=5000.0
  [PASS] Active notes pool stable at scroll_speed=5000.0
  Scroll speed 0.0 lookahead evaluated to: inf

--- Suite 6: NoteRenderer Structural Safety & Data Mapping ---
  [PASS] NoteRenderer handles empty note array (expected 0, got 0)
  [PASS] NoteRenderer updates 500 simultaneous notes without state corruption (expected 500, got 500)
  [PASS] NoteRenderer handles extreme duration notes cleanly (expected 3, got 3)

================================================================================
 ADVERSARIAL TEST RESULTS: 76 Passed, 2 Failed
================================================================================
```

### 1.2 Direct Code Observations

1. **`scripts/highway.gd` lines 87-96**:
   ```gdscript
   # Detect chords and offset adjacent diatonic steps
   for i in range(chart_notes.size()):
       for j in range(i + 1, chart_notes.size()):
           var n1: NoteData = chart_notes[i]
           var n2: NoteData = chart_notes[j]
           if absf(n1.time_sec - n2.time_sec) < 0.005:
               if abs(n1.diatonic_step - n2.diatonic_step) == 1:
                   if n1.diatonic_step < n2.diatonic_step:
                       n2.chord_offset_x = 16.0
                   else:
                       n1.chord_offset_x = 16.0
   ```
   - For an isolated pair of seconds (C4 and D4), C4 has `offset = 0.0`, D4 has `offset = 16.0`. 2D distance is $\sqrt{16.0^2 + 9.0^2} = 18.36\text{ px} > 17.0\text{ px}$.
   - For clusters of 3+ seconds (e.g., C4 step 28, D4 step 29, E4 step 30, F4 step 31), D4, E4, and F4 are ALL assigned `chord_offset_x = 16.0`. Center-to-center distance between D4 and E4 is only $9.0\text{ px}$, causing direct visual collision ($9.0\text{ px} < 17.0\text{ px}$ diameter).
   - In addition, because there is no `if n2.time_sec - n1.time_sec >= 0.005: break`, the inner loop runs all $j$ from $i+1$ to $N-1$ unconditionally for every note, executing $\frac{N(N-1)}{2} = 12,497,500$ iterations for $N=5,000$ notes and taking 1.87 seconds on desktop CPU.

2. **`scripts/note_data.gd` lines 37-43**:
   ```gdscript
   func _init(p_id: int = 0, p_midi: int = 60, p_time: float = 0.0, p_dur: float = 0.0, p_staff: String = "") -> void:
       id = p_id
       pitch_midi = clampi(p_midi, 21, 108)
       time_sec = maxf(0.0, p_time)
       duration_sec = maxf(0.0, p_dur)
       staff = p_staff if p_staff != "" else ("treble" if pitch_midi >= 60 else "bass")
       _compute_notation_properties()
   ```
   - Standard MIDI allows note numbers 0 to 127. C0 is MIDI 12.
   - Instantiating C0 via `NoteData.new(1, 12)` results in `pitch_midi = 21` (A0), `pitch_name = "A0"` (instead of "C0"), and vertical position $Y = 567.0$ (instead of $Y = 612.0$).
   - Static methods `NoteData.midi_to_step(12)` and `NoteData.midi_to_y(12)` correctly calculate step 0, $Y=612.0$, and 9 ledger lines, showing the coordinate math already supports C0, but the hardcoded clamp `[21, 108]` truncates it.

3. **`scripts/highway.gd` line 121**:
   ```gdscript
   var spawn_lookahead: float = (SCREEN_WIDTH - x_hit + SPAWN_MARGIN_PX) / scroll_speed
   ```
   - When `scroll_speed <= 0.0`, `spawn_lookahead` evaluates to `INF`, causing all notes in the chart to spawn on frame 1 without despawning.

---

## 2. Logic Chain

1. **Staff Coordinate Geometry Correctness (C2, C4, C6, C8)**:
   - Middle C (C4, MIDI 60, step 28) is anchored at $Y=360.0$, equidistant (18px) between Treble Line 1 ($Y=342$) and Bass Line 5 ($Y=378$). It generates 1 ledger line at $Y=360.0$.
   - C2 (MIDI 36, step 14) positions at $Y=486.0$ with 2 ledger lines ($Y=468, 486$).
   - C6 (MIDI 84, step 42) positions at $Y=234.0$ with 2 ledger lines ($Y=252, 234$).
   - C8 (MIDI 108, step 56) positions at $Y=108.0$ with 9 ledger lines.
   - All standard octave anchor points match musical engraving requirements.

2. **C0 (MIDI 12) Truncation Defect**:
   - The user specification mandates testing extreme pitches including C0 (MIDI 12).
   - In `NoteData._init`, `pitch_midi` is clamped to `[21, 108]`.
   - Passing MIDI 12 causes the note to mutate into MIDI 21 (A0), distorting pitch name, vertical staff position, and ledger line calculations.
   - Because `clampi(p_midi, 0, 127)` or `clampi(p_midi, 12, 127)` would allow C0 to position cleanly at step 0 ($Y=612.0$, 9 ledgers), the current clamp is an unnecessary artificial restriction.

3. **Dense Chord Seconds Collision Defect**:
   - Single pairs of seconds (e.g. C4 + D4) are properly offset by +16.0px, giving center distance $18.36\text{ px} \ge 17.0\text{ px}$.
   - However, for dense second clusters ($N \ge 3$ consecutive notes in seconds, e.g. C4, D4, E4), every note above C4 is assigned `offset = 16.0`.
   - Consequently, D4 ($Y=351$) and E4 ($Y=342$) have identical horizontal offset ($X=+16.0$).
   - Their vertical center distance is only $9.0\text{ px}$, causing an $8.0\text{ px}$ direct overlap between their circular noteheads.
   - This directly breaks Requirement R1 chord rendering visual fidelity.

4. **Large Chart Loading Latency**:
   - In `Highway.load_notes`, `chart_notes` is pre-sorted chronologically.
   - However, the inner chord detection loop tests all subsequent notes without checking if `n2.time_sec - n1.time_sec >= 0.005`.
   - For a 5,000-note chart, this executes $12.5$ million iterations, taking $1,869\text{ ms}$ on desktop and creating an unacceptable freeze / potential ANR risk on mobile (Pixel 7a).

5. **Memory & Scrolling Pool Stability**:
   - Active notes pool is strictly bounded: peak active notes during playback of 5,000 notes was 193 notes.
   - Notes crossing $X < -60.0$ are culled via `active_notes.remove_at(i)`.
   - Memory remained stable across 600 simulation frames ($+4.95\text{ KB}$ delta).
   - Scroll speed scaling (100 to 5,000 px/s) functions cleanly without pool runaway.

---

## 3. Caveats

- Live microphone audio capture and Spotify Basic Pitch ONNX inference were not evaluated in this report, as they are explicitly scheduled for Milestone 3 (`IAudioPitchModel` and `basic-pitch`).
- Real-time sheet music OMR was not evaluated, as it is scheduled for Milestone 4.

---

## 4. Conclusion

**Verdict: REQUEST_CHANGES**

While Grand Staff geometry, Middle C symmetry, single-second chord offsets, and scrolling pooling are solidly implemented and verified, the following changes are required before Milestone 1 can be formally approved:

1. **Fix Dense Second Cluster Collision in `scripts/highway.gd`**:
   - Update chord offset logic so that consecutive seconds alternate horizontal displacement (e.g. alternating left/right on even/odd diatonic steps or tracking assigned column slots) to prevent notehead overlap when 3 or more seconds occur simultaneously.
2. **Expand MIDI Clamping in `scripts/note_data.gd`**:
   - Adjust `clampi(p_midi, 21, 108)` in `NoteData._init` to `clampi(p_midi, 0, 127)` or `clampi(p_midi, 12, 127)` so C0 (MIDI 12) is rendered at diatonic step 0 ($Y=612.0$) with correct name and 9 ledger lines instead of mutating into A0.
   - Similarly update `Highway.set_live_pitch` guard to support pitches from 12 to 108.
3. **Optimize `load_notes` Chord Loop in `scripts/highway.gd`**:
   - Add `if n2.time_sec - n1.time_sec >= 0.005: break` inside the inner loop of `load_notes` to reduce large chart loading from $O(N^2)$ (12.5M iterations, 1.87s) to $O(N)$ (<5ms).
4. **Guard Zero Scroll Speed**:
   - Add `var speed = maxf(1.0, scroll_speed)` when calculating `spawn_lookahead` in `scripts/highway.gd` to avoid `INF` evaluation.

---

## 5. Verification Method

To independently verify these findings, run the newly authored adversarial test runner:

```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_adversarial_m1.gd"
```

Expected output confirms:
- `[FAIL] NoteData supports C0 (MIDI 12) without clamping to A0 (MIDI 21)` (clamped to MIDI 21, Y=567.0 instead of Y=612.0).
- `[COLLISION DETECTED] D4 and E4 in 4-note second cluster: dx=0.0, dy=9.0, dist=9.00 < 17.0px`
- `[FAIL] Dense cluster of 4 seconds has NO notehead collisions (< 17px center-to-center)`
- `load_notes(5000 notes) completed in ~1869 ms`
