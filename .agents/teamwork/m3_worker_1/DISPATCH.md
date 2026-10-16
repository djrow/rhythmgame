## 2026-10-16T19:34:55Z
You are m3_worker_1, an implementation worker for Milestone 3: Basic Pitch ONNX & Audio Inference.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_worker_1\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
The project index is at: c:\Users\david\Documents\micgame-3\PROJECT.md
Project root is: c:\Users\david\Documents\micgame-3

Prior Explorer Reports & Code Artifacts:
- M3 Explorer 1 (Modular Architecture & Drivers): c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_explorer_1\report.md (and proposed_audio_pitch_model.gd, proposed_websocket_driver.gd, proposed_mock_driver.gd)
- M3 Explorer 2 (Python Server & Transcription Harness): c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_explorer_2\report.md (and proposed_basic_pitch_onnx.py, proposed_inference_server.py, proposed_test_transcription_harness.py)
- M3 Explorer 3 (Audio Capture, Main integration & Runner): c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_explorer_3\report.md (and proposed_audio_capture.gd, proposed_main.gd, proposed_test_inference_scoring_runner.gd)

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your write ownership (exclusive):
- `python/basic_pitch_onnx.py`
- `python/inference_server.py`
- `scripts/inference/audio_pitch_model.gd`
- `scripts/inference/websocket_driver.gd`
- `scripts/inference/mock_driver.gd`
- `scripts/audio_capture.gd`
- `scripts/main.gd`
- `tests/test_transcription_harness.py`
- `tests/test_inference_scoring_runner.gd`

Your tasks:
1. Read ORIGINAL_REQUEST.md, PROJECT.md, and all 3 explorer reports.
2. Implement `python/basic_pitch_onnx.py`:
   - Pure NumPy + ONNX Runtime execution loading `assets/models/nmp.onnx`.
   - Linear resampling to 22,050 Hz via `np.interp`.
   - Forward pass returning notes, onsets, and contours probabilities.
3. Implement `python/inference_server.py`:
   - Async WebSocket server on `ws://127.0.0.1:8765` using `websockets` package.
   - Sliding ring buffer of 43,844 samples.
   - Responds with JSON `{"type":"pitches", "pitches":[...], "onsets":[...], "timestamp":..., "confidence":{...}}`.
4. Implement `res://scripts/inference/audio_pitch_model.gd`:
   - Base `RefCounted` interface with methods: `push_audio_samples()`, `get_detected_pitches()`, `get_recent_onsets()`, `pop_recent_onsets()`, `is_model_ready()`, `poll()`, `reset()`.
5. Implement `res://scripts/inference/websocket_driver.gd`:
   - `WebSocketPeer` connecting to `ws://127.0.0.1:8765`.
   - Streams IEEE 754 float32 binary audio chunks via `to_byte_array()`.
   - Drains packets and parses detected notes and onsets.
6. Implement `res://scripts/inference/mock_driver.gd`:
   - Offline / mock driver supporting programmatic note feeds and automated chart-driven playback (`load_chart_from_file`, `update_playback_time`).
7. Implement `res://scripts/audio_capture.gd`:
   - Godot node capturing `AudioEffectCapture` on `Record` bus with RMS noise gate (-45 dB / 0.005 threshold) and pushing normalized float32 samples to `AudioPitchModel`.
8. Integrate in `res://scripts/main.gd`:
   - Instantiate `AudioCapture` and `AudioPitchModel` (defaulting to MockDriver or WebSocketDriver based on flag).
   - In `_process()`, poll model onsets and detected pitches, evaluate active notes at playhead, and process concurrent chord pitch clusters in `ScoringEngine`.
9. Implement automated CLI test harnesses:
   - `tests/test_transcription_harness.py`: Evaluates Basic Pitch ONNX against the 3 bundled audio test pieces and verifies >= 80% F1-score on polyphonic audio.
   - `res://tests/test_inference_scoring_runner.gd`: Headless Godot runner verifying the integrated audio capture -> inference -> scoring chain across all 7 test suites (61 assertions).
10. VERIFICATION: You MUST execute the build and tests yourself:
    - Run: `python tests/test_transcription_harness.py --min-f1 0.80`
    - Run: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"`
    - Run: `python tests/e2e/run_all_e2e_tests.py`
    Verify that all tests pass with exit code 0!
11. Document all executed commands, verbatim outputs, and file changes in `handoff.md` and report back via send_message.
