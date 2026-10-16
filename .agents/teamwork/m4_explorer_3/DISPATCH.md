## 2026-10-16T20:13:29Z
You are m4_explorer_3, an exploration agent for Milestone 4: On-Device OMR & Level Alignment.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\m4_explorer_3\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
The project index is at: c:\Users\david\Documents\micgame-3\PROJECT.md
Prior survey report: c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_3\report.md
Project root is: c:\Users\david\Documents\micgame-3

Your task:
1. Read ORIGINAL_REQUEST.md, PROJECT.md, and survey_explorer_3/report.md (Sections 3 & 5.3).
2. Investigate and design the level loader and audio-chart alignment engine `scripts/level_loader.gd`:
   - Loading levels from either pre-existing chart JSON files or on-the-fly via `omr_processor.gd` from score images.
   - Pairing with audio files (WAV/MP3/OGG) via Godot `AudioStreamPlayer`.
   - Audio alignment: validating audio duration against chart duration, calculating note timestamps from BPM and beats.
   - In-game calibration offset support: offset adjustment in ms applied to note evaluation and playhead synchronization.
   - Passing loaded notes to `highway.gd` (`highway.load_notes()`).
   - Integrating with `scripts/main.gd` and `scenes/main.tscn` to allow selecting any of the 3 bundled pieces or user files.
3. Design the headless Godot test runner `tests/test_omr_runner.gd`:
   - Runs in Godot headless: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_omr_runner.gd"`.
   - Tests `scripts/omr_processor.gd` and `scripts/level_loader.gd` against the bundled test pieces.
   - Verifies staff detection, notehead recognition, MIDI pitch mapping, and level loading.
   - Exits with code 0 on complete pass.
4. Formulate the exact implementation code ready for the Worker.
5. Write your report and `handoff.md` in your working directory and notify the orchestrator via send_message.
