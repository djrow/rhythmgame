## 2026-10-16T18:35:49Z
You are m1_worker_1, an implementation worker for Milestone 1: Grand Staff Highway & Scoring.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\m1_worker_1\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
The project index is at: c:\Users\david\Documents\micgame-3\PROJECT.md
Project root is: c:\Users\david\Documents\micgame-3

Prior Explorer Reports:
- M1 Architecture & Cleanup: c:\Users\david\Documents\micgame-3\.agents\teamwork\m1_explorer_1\report.md
- M1 Note Scrolling & Playhead Sync: c:\Users\david\Documents\micgame-3\.agents\teamwork\m1_explorer_2\report.md
- M1 Scoring Engine & HUD Feedback: c:\Users\david\Documents\micgame-3\.agents\teamwork\m1_explorer_3\report.md

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your write ownership (exclusive):
- `project.godot`
- `scripts/note_data.gd`
- `scripts/note_renderer.gd`
- `scripts/highway.gd`
- `scripts/scoring_engine.gd`
- `scripts/hud.gd`
- `scripts/main.gd`
- `scenes/highway.tscn`
- `scenes/hud.tscn`
- `scenes/main.tscn`
- `tests/test_scoring_runner.gd`

Your tasks:
1. Read ORIGINAL_REQUEST.md, PROJECT.md, and all three explorer reports.
2. Clean up `project.godot`: Remove lines 23-26 (orphaned `_mcp_game_helper` autoload) and lines 34-37 (orphaned `godot_ai` plugin). Ensure `run/main_scene="res://scenes/main.tscn"`.
3. Implement `res://scripts/note_data.gd`: Precomputed diatonic steps, Y coordinate math ($Y_{\text{center}}=360$, $S=18$px, $\Delta y=9$px), Middle C (C4, step 28, Y=360px), ledger lines calculations for C2-E2 and A5-C6+, and note attributes.
4. Implement `res://scripts/note_renderer.gd`: CanvasItem 2D vector renderer drawing note heads, stems, accidentals, sustain trails, and dynamic ledger lines.
5. Implement `res://scripts/highway.gd` & `res://scenes/highway.tscn`: Dual Grand Staff (Treble lines at Y=270, 288, 306, 324, 342; Bass lines at Y=378, 396, 414, 432, 450; Middle C at Y=360), right-to-left scrolling toward target hit line at X=160px ($V_{\text{scroll}}=400$px/s), playhead sync with `AudioStreamPlayer`, sliding window pooling and culling.
6. Implement `res://scripts/scoring_engine.gd`: Full timing window logic (Perfect $\pm 50$ms, Good $\pm 100$ms, Miss $> 100$ms), combo streaks, multipliers (10 combo=2x, 20 combo=3x, 30+ combo=4x), chord pitch matching, and note expiration checks.
7. Implement `res://scripts/hud.gd` & `res://scenes/hud.tscn`: Score display, combo counter, multiplier indicator, and floating rating popups.
8. Implement `res://scripts/main.gd` & `res://scenes/main.tscn`: Root game scene orchestrating highway, HUD, demo chart playback, keyboard controls (e.g. keyboard strumming/chords for testing), and clean quit.
9. Implement `res://tests/test_scoring_runner.gd`: Headless test runner executing the 6 comprehensive test suites (timing windows, multipliers, streak reset, polyphony, note expiration, accuracy) with zero external dependencies.
10. VERIFICATION: You MUST execute the build and tests yourself:
    - Run: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --quit`
    - Run: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"`
    Verify that both exit with code 0 and all tests pass.
11. Document exact commands and output logs in your `handoff.md` and report back via send_message.
