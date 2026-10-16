# Milestone 1: Grand Staff Highway & Scoring - Independent Review & Critic Handoff Report

**Reviewer / Critic**: `m1_reviewer_2`  
**Date**: 2026-10-16  
**Milestone**: Milestone 1 (M1) — Grand Staff Highway & Scoring  
**Project Root**: `c:\Users\david\Documents\micgame-3`  
**Verdict**: **APPROVE**  
**Integrity Status**: **CLEAN (0 integrity violations)**  

---

## 1. Observation

Direct examination and terminal execution of the codebase yielded the following observations:

### 1.1 Integrity & Source Code Inspection
- `project.godot`:
  - Verified lines 1-39: Clean configuration without orphaned autoloads or editor plugins (`res://addons/godot_ai/...` completely absent).
  - Configured with `run/main_scene="res://scenes/main.tscn"`, `driver/enable_input=true`, `renderer/rendering_method="gl_compatibility"`, viewport `1280x720`, canvas_items expand stretch.
  - Dedicated microphone bus layout configured in `default_bus_layout.tres` with `AudioEffectCapture` on unrouted `Record` bus.
- `scripts/highway.gd`:
  - Staff Line Positions (lines 15-18):
    - `TREBLE_LINES = [270.0, 288.0, 306.0, 324.0, 342.0]` (Spacing = $18.0$px)
    - `BASS_LINES = [378.0, 396.0, 414.0, 432.0, 450.0]` (Spacing = $18.0$px)
    - Center Y = $360.0$px. Distance from Treble Line 1 ($342$) to Center ($360$) is $18$px. Distance from Center ($360$) to Bass Line 5 ($378$) is $18$px.
  - Zero-Allocation Pooling & Culling (lines 124-144):
    - Notes are held in pre-allocated array `chart_notes: Array[NoteData]`.
    - Sliding window `active_notes` is populated via monotonic index `spawn_index` based on lookahead `spawn_threshold_time`.
    - Culling occurs at `tail_x < DESPAWN_X_THRESHOLD` ($-60.0$px), removing elements via `active_notes.remove_at(i)`.
    - Note rendering delegates to `NoteRenderer` in a single CanvasItem vector draw pass, avoiding dynamic Node2D instantiations or scene tree allocations per frame.
  - Sub-Frame Playhead Sync & Monotonic Clock (lines 170-189):
    - When `audio_player.playing`: calculates `calculated_time = pos + time_since_mix - latency + audio_offset_sec`.
    - Monotonically advances `current_song_time` only when `calculated_time >= current_song_time`.
    - Seek backwards detection (`pos < last_playback_pos - 0.5`) calls `_handle_seek()` to rebuild active notes and reset `spawn_index`.
    - Fallback accumulator `current_song_time += delta` handles headless execution and absent audio streams.
- `scripts/note_data.gd`:
  - Diatonic mapping (lines 46-54): `diatonic_step = oct * 7 + DIATONIC_OFFSETS[pc]`, `y_pos = 360.0 - float(diatonic_step - 28) * 9.0`.
  - Dynamic Ledger Generation (lines 72-89): Generates ledger lines for Middle C (step 28), high Treble ($\ge 40$, up to C6+ step 42), and low Bass ($\le 16$, down to C2 step 14).
- `scripts/scoring_engine.gd`:
  - Timing Windows (lines 6-8): `WINDOW_PERFECT_SEC = 0.050` ($\le \pm 50$ms), `WINDOW_GOOD_SEC = 0.100` ($\le \pm 100$ms), Miss $> 100$ms.
  - Combo Multiplier Thresholds (lines 15-18): 1x (0-9), 2x (10-19), 3x (20-29), 4x (30+).
  - Dynamic Hit & Expired Note Processing (lines 111-206): Matches input time and MIDI pitch against active unhit notes within semitone tolerance; sets `is_hit`; calculates points awarded as `base_pts * multiplier`.
- `scripts/hud.gd`:
  - Animated score rollups via `Tween.tween_method` with `TRANS_QUAD`.
  - Bouncing combo badge on increment (`scale 1.2 -> 1.0` with `TRANS_BACK`).
  - Tiered multiplier badge colors: 1x Silver, 2x Cyan, 3x Orange, 4x Gold.
  - Floating upward judgment popups (`spawn_judgment_popup`) with scale punch, upward drift, and self-cleaning `queue_free()`.
  - Comprehensive null checks guarding against early/headless execution.
- `scripts/main.gd`:
  - Coordinates Highway, HUD, and ScoringEngine.
  - Demo chart spanning C2 (MIDI 36) to C6 (MIDI 84) and a C Major triad chord.
  - Android permission check: `if OS.get_name() == "Android": OS.request_permission("android.permission.RECORD_AUDIO")`.
  - Keyboard strumming simulation for manual testing.

### 1.2 Independent Verification Tool Executions

#### Command 1: Godot Headless Project Startup
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit
```
- **Exit Code**: `0`
- **Output**:
  ```
  Godot Engine v4.7.2.stable.official.ed1daf0bf - https://godotengine.org
  ```
- **Result**: No errors, no missing script warnings, clean engine shutdown.

#### Command 2: Headless Scoring Runner
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
```
- **Exit Code**: `0`
- **Output**:
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
    ... (all 50 assertions passed) ...

  --- Test Suite 3: Miss & Streak Reset ---
    ... (all 11 assertions passed) ...

  --- Test Suite 4: Polyphonic Pitch Matching & Timing Offset ---
    ... (all 8 assertions passed) ...

  --- Test Suite 5: Note Expiration (Miss on Passing Hit Window) ---
    ... (all 8 assertions passed) ...

  --- Test Suite 6: Performance Accuracy Percentage ---
    ... (all 2 assertions passed) ...

  ==================================================
   RESULTS: 91 Passed, 0 Failed
  ==================================================
  ALL SCORING MECHANICS VERIFIED SUCCESSFULLY [OK]
  ```
- **Result**: 91 passed, 0 failed.

#### Command 3: Full E2E Test Suite Execution
```powershell
python tests/e2e/run_all_e2e_tests.py
```
- **Exit Code**: `0`
- **Output Summary**:
  ```
  ================================================================================
             MICGAME-3 E2E TEST RUNNER - AUTOMATED QUALITY REPORT
  ================================================================================
  Tier Name                              | Total  | Passed | Fail  | Err   | Time (s)
  --------------------------------------------------------------------------------
  Tier 1: Feature Coverage               | 100    | 100    | 0     | 0     | 0.300   
  Tier 2: Boundary & Corner Cases        | 100    | 100    | 0     | 0     | 0.089   
  Tier 3: Cross-Feature Combinations     | 20     | 20     | 0     | 0     | 0.073   
  Tier 4: Real-World Scenarios           | 10     | 10     | 0     | 0     | 0.001   
  --------------------------------------------------------------------------------
  TOTAL                                  | 230    | 230    | 0     | 0     | 0.465   
  ================================================================================
   [PASS] All 230 E2E tests executed and passed successfully in 0.465 seconds.
   100% Pass Rate requirement fulfilled. Exit code: 0
  ```
- **Result**: 230 passed, 0 failed.

#### Command 4: Extended Simulation Execution (180 Frames)
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit-after 180
```
- **Exit Code**: `0`
- **Result**: Full scene graph execution over 180 physics/render frames with zero runtime exceptions.

---

## 2. Logic Chain

1. **Staff Geometry & Diatonic Alignment**:
   - Anchoring Middle C (C4, step 28) at $Y=360$ with step size $\Delta y = 9$px produces Treble Line 1 (step 30) at $Y=342$ ($360 - 2 \times 9$) and Bass Line 5 (step 26) at $Y=378$ ($360 + 2 \times 9$).
   - Treble lines ($270, 288, 306, 324, 342$) and Bass lines ($378, 396, 414, 432, 450$) each have exact $18$px spacing, maintaining mathematical symmetry and standard grand staff proportions.
2. **Zero-Allocation Memory Discipline**:
   - Dynamic instantiation of Godot Nodes per note inside the game loop causes garbage collection stutter and heap fragmentation.
   - The implementation uses a sliding-window array of `NoteData` references into `chart_notes`, and `NoteRenderer` renders all active elements using CanvasItem vector primitives in `_draw()`. Nodes are neither spawned nor freed during scrolling.
3. **Culling Order of Operations**:
   - Miss evaluation occurs when $t_{\text{current}} > t_{\text{note}} + 0.100$s (at $X=120$px, 40px past the receptor line).
   - Note despawn occurs when $\text{tail\_x} < -60.0$px (over 500ms after passing the receptor line).
   - This strict ordering guarantees that notes cannot be culled prematurely before a miss is registered, and sustain tails remain fully visible until off-screen.
4. **Clock Synchronization & Jitter Rejection**:
   - Audio buffer mix timing often exhibits micro-jitter. By enforcing `calculated_time >= current_song_time`, notes never jitter backwards.
   - By detecting significant negative jumps (`pos < last_playback_pos - 0.5`), audio seeking is handled gracefully without stalling.
5. **Decoupled Scoring Engine**:
   - Pure logic `ScoringEngine` operates independently of visual scene trees, allowing comprehensive headless verification (Test Suites 1-6) while binding to UI signals at runtime.

---

## 3. Caveats

- **Bundled Song WAV Assets**: The demo chart uses Godot's delta clock for playback since bundled audio accompaniment WAV files are scheduled for synthesis in Milestone 2. The playhead synchronization logic is designed to automatically latch onto `AudioStreamPlayer.get_playback_position()` once audio streams are supplied.
- **Microphone ML Inference**: Live microphone streaming and Spotify Basic Pitch ONNX inference are explicitly assigned to Milestone 3. Milestone 1 includes keyboard strumming simulation for interactive testing and headless scoring runners.

---

## 4. Conclusion & Verdict

**Verdict**: **APPROVE**

All acceptance criteria for Milestone 1 (Grand Staff Highway & Scoring) have been verified:
- Clean project configuration without orphaned plugins.
- Symmetrical dual Treble/Bass Grand Staff notation with classical $S=18$px spacing and Middle C alignment.
- Zero-allocation note pooling and despawn culling.
- Robust hit detection, timing windows, combo multipliers, chord support, and responsive HUD feedback.
- Clean execution across all 91 unit tests and 230 E2E tests with 0 failures and 0 integrity violations.

---

## 5. Verification Method

To independently reproduce this verification:

1. **Verify Godot Project Initialization**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit
   ```
   *Expected outcome*: Exit code 0, 0 errors.

2. **Run Scoring Engine Headless Runner**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
   ```
   *Expected outcome*: Exit code 0, 91 passed assertions, 0 failures.

3. **Run Full E2E Test Suite**:
   ```powershell
   python tests/e2e/run_all_e2e_tests.py
   ```
   *Expected outcome*: Exit code 0, 230 passed assertions across all 4 tiers, 0 failures.

4. **Run Simulation Loop (180 Frames)**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit-after 180
   ```
   *Expected outcome*: Exit code 0.
