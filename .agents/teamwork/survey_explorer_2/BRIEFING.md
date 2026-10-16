# BRIEFING — 2026-10-16T18:22:00Z

## Mission
Investigate audio capture, ML inference (Basic Pitch / ONNX), Godot audio bridge, scoring engine architecture, and technical environment for the real-time polyphonic audio-to-game system.

## 🔒 My Identity
- Archetype: explorer
- Roles: Audio Capture & ML Inference Explorer
- Working directory: c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_2\
- Original parent: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Milestone: Project Survey & Architecture Exploration

## 🔒 Key Constraints
- Read-only investigation — do NOT implement application code
- Output report in `survey_explorer_2/report.md`
- Self-contained handoff in `survey_explorer_2/handoff.md`

## Current Parent
- Conversation ID: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Updated: 2026-10-16T18:22:00Z

## Investigation State
- **Explored paths**:
  - `basic_pitch` package, `saved_models/icassp_2022/nmp.onnx`, `nmp.tflite`
  - `project.godot`, `default_bus_layout.tres`, `export_presets.cfg`
  - Python runtime (Python 3.12, ONNX Runtime 1.31, NumPy 2.3, OpenCV, Pillow, music21)
  - Godot 4.7.2 headless console binary in Downloads
  - Android SDK and ADB 1.0.41 in AppData
  - APK and Windows build artifacts
- **Key findings**:
  - `nmp.onnx` is 230 KB, runs on CPU in ~10.2 ms with ONNX Runtime.
  - Streaming window tail onset detection latency is ~40-50 ms, well inside $\pm 100$ ms timing window.
  - Polyphonic chord detection achieved >0.60 activation on C-Major triad notes vs <0.12 on non-chord notes.
  - Pure NumPy implementation of audio resampling and peak-picking bypasses missing `scipy`/`librosa` dependencies.
  - Godot audio bus already has isolated "Record" bus with `AudioEffectCapture`.
- **Unexplored areas**: None for this survey milestone.

## Key Decisions Made
- Confirmed viability of real-time Basic Pitch ONNX transcription.
- Designed decoupled `AudioInferenceService` with swappable WebSocket, native, and mock harness drivers.
- Verified pure NumPy + ONNX Runtime execution strategy.

## Artifact Index
- DISPATCH.md — Dispatch log
- BRIEFING.md — Working memory
- progress.md — Liveness tracker
- report.md — Comprehensive survey report
- handoff.md — 5-component handoff report
