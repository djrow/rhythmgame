# Milestone 1 Handoff Report

**Agent**: `m1_explorer_1`  
**Milestone**: Milestone 1: Grand Staff Highway & Scoring  
**Date**: 2026-10-16  
**Type**: Hard Handoff (Investigation & Architecture Design Complete)

---

## 1. Observation

1. **`project.godot` Configuration Defect**:
   - Inspected `c:\Users\david\Documents\micgame-3\project.godot`.
   - Lines 23–26 contain:
     ```ini
     [autoload]

     _mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"

     ```
   - Lines 34–37 contain:
     ```ini
     [editor_plugins]

     enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")

     ```
   - Running Godot 4.7.2 headlessly via `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit` output verbatim:
     ```
     ERROR: Attempt to open script 'res://addons/godot_ai/runtime/game_helper.gd' resulted in error 'File not found'.
        at: load_source_code (modules/gdscript/gdscript.cpp:1139)
     ERROR: Failed loading resource: res://addons/godot_ai/runtime/game_helper.gd.
        at: _load (core/io/resource_loader.cpp:317)
     ERROR: Failed to instantiate an autoload, can't load from path: res://addons/godot_ai/runtime/game_helper.gd.
        at: start (main/main.cpp:4533)
     ERROR: Cannot open file 'res://scenes/main.tscn'.
        at: load (scene/resources/resource_format_text.cpp:1442)
     ERROR: Failed loading resource: res://scenes/main.tscn.
        at: _load (core/io/resource_loader.cpp:317)
     ERROR: Failed loading scene: res://scenes/main.tscn.
        at: start (main/main.cpp:4767)
     ```
     Command returned exit code `1`.

2. **Absence of Source Scenes and Scripts**:
   - `find_by_name` across `c:\Users\david\Documents\micgame-3` returned 9 files (`project.godot`, `export_presets.cfg`, `default_bus_layout.tres`, `icon.svg`, `icon.svg.import`, `micgame3.apk`, `micgame3.apk.idsig`, `micgame3.exe`, `PROJECT.md`).
   - Directories `scenes/` and `scripts/` do not yet exist in project root.

3. **Mathematical Staff Verification**:
   - Python simulation verifying diatonic steps and Y-coordinates yielded:
     - Middle C (C4, MIDI 60): Step 28, $Y = 360\text{ px}$.
     - Treble lines (bottom to top): E4 (step 30, $Y=342$), G4 (step 32, $Y=324$), B4 (step 34, $Y=306$), D5 (step 36, $Y=288$), F5 (step 38, $Y=270$).
     - Bass lines (top to bottom): A3 (step 26, $Y=378$), F3 (step 24, $Y=396$), D3 (step 22, $Y=414$), B2 (step 20, $Y=432$), G2 (step 18, $Y=450$).
     - Range boundaries: C2 (step 14, $Y=486$), C6 (step 42, $Y=234$).
     - Ledger line rule output: C4 $\to [28]$; A5 $\to [40]$; C6 $\to [40, 42]$; E2 $\to [16]$; C2 $\to [16, 14]$.

---

## 2. Logic Chain

1. **Root Cause of Godot Startup Failure**:
   - Godot tries to load all autoloads declared in `project.godot` prior to loading the main scene.
   - Because `res://addons/godot_ai/runtime/game_helper.gd` does not exist on disk, Godot logs an error and exits with code 1.
   - Concurrently, `run/main_scene="res://scenes/main.tscn"` is declared at line 14, but `res://scenes/main.tscn` does not exist on disk.
   - Therefore, removing lines 23–26 and lines 34–37 from `project.godot` and creating `res://scenes/main.tscn` will allow Godot to boot cleanly with exit code 0.

2. **Diatonic Coordinate Symmetry**:
   - Middle C ($Y=360$) is exactly equidistant ($18\text{ px} = 1S$) between the Treble bottom line ($Y=342$) and Bass top line ($Y=378$).
   - The gap between the staves is $36\text{ px} = 2S$.
   - All 10 staff lines and all ledger lines fall on even step numbers ($2k$).
   - All spaces between lines fall on odd step numbers ($2k + 1$).
   - Pitch mapping with $Y = 360 - (D - 28) \times 9$ places every musical note at its standard diatonic staff position with zero distortion.

3. **Ledger Line Sufficiency**:
   - Middle C (step 28) requires exactly 1 ledger line.
   - D4 (step 29) hangs directly below Treble Line 1 (E4) without a ledger line.
   - B3 (step 27) sits directly above Bass Line 5 (A3) without a ledger line.
   - Notes above Treble line 5 (F5, step 38): A5 (step 40) is the first ledger line above; B5 (step 41) sits on ledger line 40; C6 (step 42) has ledger lines 40 and 42.
   - Notes below Bass line 1 (G2, step 18): E2 (step 16) is the first ledger line below; D2 (step 15) hangs below ledger line 16; C2 (step 14) has ledger lines 16 and 14.
   - The formula `for s in range(40, max_step + 1, 2)` (and symmetrical for $\le 16$) covers every pitch up to C6+ and down to C2.

4. **Scoring Engine Decoupling**:
   - `ScoringEngine` computes rating (`PERFECT`, `GOOD`, `MISS`), points, and combo based on absolute time difference $\Delta t = |T_{\text{hit}} - t_{\text{note}}|$.
   - Emitting signals (`note_judged`, `score_updated`) allows `GrandStaffHighway` to trigger visual particle/ripple effects and `HUD` to animate popups without tight coupling.

---

## 3. Caveats

1. **Audio Latency on Hardware**: On physical mobile devices (Pixel 7a), `AudioServer.get_time_since_last_mix()` compensates for buffer latency, but hardware-specific audio output latency (typically 10–25ms on Android AAudio) may benefit from an in-game calibration slider in later milestones.
2. **Accidentals**: Currently sharps (♯) are modeled as the primary accidental offset. Flats (♭) share identical vertical diatonic positioning when represented by their enharmonic equivalent (e.g., B♭3 at step 27 with flat glyph vs A♯3 at step 26 with sharp glyph). A future enhancement can include an enharmonic flag in the chart format.
3. **Microphone Capture**: The `Record` bus in `default_bus_layout.tres` is primed with `AudioEffectCapture`. Connecting microphone pitch inference to `set_live_pitch` is scheduled for Milestone 3.

---

## 4. Conclusion

Milestone 1 architecture is fully resolved, mathematically verified, and documented.
The Worker implementation plan is:
1. Edit `project.godot`: Remove lines 23–26 (`[autoload]`) and lines 34–37 (`[editor_plugins]`).
2. Create `res://scripts/scoring_engine.gd`: Full timing window logic and combo multiplier calculations.
3. Create `res://scripts/highway.gd`: Full dual staff CanvasItem drawing, ledger lines, right-to-left scrolling, and hit effects.
4. Create `res://scripts/main.gd`: Game loop coordinator, demo chart loader, and Android permission request.
5. Create `res://scenes/main.tscn`: Root scene linking `Highway`, `ScoringEngine`, `AudioPlayer`, and `HUD`.

---

## 5. Verification Method

1. **Headless Execution Verification**:
   Execute Godot in headless mode from project root:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit-after 60
   ```
   **Expected Result**: Exit code `0`, zero error logs, clean initialization of `res://scenes/main.tscn`.

2. **Visual Inspection**:
   Run the project in a desktop window:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --path "c:\Users\david\Documents\micgame-3"
   ```
   **Expected Result**:
   - Dual Grand Staff renders centered at $Y=360\text{ px}$.
   - Treble clef and Bass clef labels visible on left.
   - Hit line receptor at $X=160\text{ px}$.
   - Demo chart notes scroll smoothly right-to-left.
   - Dynamic ledger lines visible on Middle C (C4), high notes (A5, C6), and low notes (E2, C2).
   - Pressing keys triggers hit judgment, popups, and HUD score updates.

3. **Android Export Verification**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --export-debug "Android" "micgame3_m1.apk"
   ```
   **Expected Result**: Exit code `0`, valid signed APK generated.
