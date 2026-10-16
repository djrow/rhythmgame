# BRIEFING — 2026-10-16T19:42:30Z

## Mission
Implement Milestone 3: Basic Pitch ONNX & Audio Inference, including Python ONNX runner, WebSocket server, Godot drivers, AudioCapture, main.gd integration, and test harnesses.

## 🔒 My Identity
- Archetype: implementer
- Roles: implementer, qa, specialist
- Working directory: c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_worker_1
- Original parent: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Milestone: Milestone 3: Basic Pitch ONNX & Audio Inference

## 🔒 Key Constraints
- Pure NumPy + ONNX Runtime execution for basic_pitch_onnx.py (no torch/librosa dependency)
- Resample to 22,050 Hz via np.interp
- WebSocket server on ws://127.0.0.1:8765 using websockets
- AudioPitchModel RefCounted base class in Godot
- WebSocketDriver and MockDriver implementations
- AudioCapture node with AudioEffectCapture, RMS noise gate (-45 dB / 0.005 threshold)
- Main integration with active notes and concurrent chord pitch clusters
- Tests: test_transcription_harness.py (F1 >= 0.80), test_inference_scoring_runner.gd (exit code 0), run_all_e2e_tests.py
- Minimal change principle, DO NOT cheat, genuine implementation

## Current Parent
- Conversation ID: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Updated: 2026-10-16T19:42:30Z

## Task Summary
- **What to build**: Complete Milestone 3 implementation: Python Basic Pitch ONNX runtime, WebSocket inference server, Godot inference model interface & drivers (WebSocket + Mock), Godot audio capture with noise gate, main.gd integration with ScoringEngine, and transcription & headless integration test runners.
- **Success criteria**: All Python and Godot test suites pass with exit code 0; transcription harness >= 80% F1.
- **Interface contracts**: PROJECT.md & explorer reports
- **Code layout**: python/, scripts/inference/, scripts/, tests/

## Key Decisions Made
- `python/basic_pitch_onnx.py`: Implemented `BasicPitchOnnxRunner` with pure NumPy + ONNX Runtime. Linear resampling using `np.interp`, local maxima peak picking via boolean masking (`argrelmax_axis0`), and overlap-add window unwrapping.
- `python/inference_server.py`: Async WebSocket server on `ws://127.0.0.1:8765` handling sliding circular buffer (43,844 samples), JSON/binary response framing, and 120ms debounce.
- `scripts/inference/audio_pitch_model.gd`: RefCounted base interface declaring `push_audio_samples`, `get_detected_pitches`, `get_recent_onsets`, `pop_recent_onsets`, `is_model_ready`, `reset`, `poll`.
- `scripts/inference/websocket_driver.gd` & `mock_driver.gd`: Modular drivers implementing streaming WebSocket and offline deterministic testing.
- `scripts/audio_capture.gd`: AudioEffectCapture node on Record bus with RMS noise gate (-45 dB / 0.005 threshold) and downmixing.
- `scripts/main.gd`: Coordinator integrating audio capture and polyphonic cluster matching against active highway notes.
- `tests/test_transcription_harness.py`: Evaluates test pieces against ground truth chart notes, confirming >= 80% F1.
- `tests/test_inference_scoring_runner.gd`: Headless Godot runner verifying full pipeline (7 test suites, 63 assertions).

## Change Tracker
- **Files modified**:
  - `python/basic_pitch_onnx.py`: pure NumPy ONNX model runner
  - `python/inference_server.py`: async WebSocket inference server
  - `scripts/inference/audio_pitch_model.gd`: base interface
  - `scripts/inference/websocket_driver.gd`: WebSocket audio streaming driver
  - `scripts/inference/mock_driver.gd`: offline/mock driver
  - `scripts/audio_capture.gd`: microphone capture with noise gate
  - `scripts/main.gd`: audio inference & polyphonic scoring integration
  - `tests/test_transcription_harness.py`: CLI transcription verification harness
  - `tests/test_inference_scoring_runner.gd`: headless Godot integration test suite
- **Build status**: PASS (all suites pass with exit code 0)
- **Pending issues**: none

## Quality Status
- **Build/test result**: PASS
  - `python tests/test_transcription_harness.py --min-f1 0.80`: 100% pass (Ode: 93.3%, Bach: 82.4%, Cadence: 80.0%)
  - `Godot test_inference_scoring_runner.gd`: 63/63 assertions passed
  - `python tests/e2e/run_all_e2e_tests.py`: 230/230 tests passed
- **Lint status**: clean
- **Tests added/modified**: `tests/test_transcription_harness.py`, `tests/test_inference_scoring_runner.gd`

## Loaded Skills
- none

## Artifact Index
- DISPATCH.md — dispatch message
- progress.md — progress log
- handoff.md — 5-component handoff report
