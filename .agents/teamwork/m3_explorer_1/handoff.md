# Handoff Report: Modular Inference Architecture (GDScript)

**Agent**: `m3_explorer_1`  
**Milestone**: Milestone 3 — Basic Pitch ONNX & Audio Inference  
**Date**: 2026-10-16  
**Type**: Hard Handoff (Task Complete)  

---

## 1. Observation

1. **Pretrained Model & Environment**:
   - `assets/models/nmp.onnx` is present with size 230,444 bytes (`Length: 230444`).
   - Godot console binary is located at `C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe`.
   - Python 3.12 environment has `onnxruntime` 1.31.0 and `websockets` 17.0.1 installed and operational.
2. **Godot WebSocketPeer**:
   - Tested in Godot 4.7.2: `var ws = WebSocketPeer.new()` instantiates cleanly with ready state `STATE_CLOSED` (3), `STATE_CONNECTING` (0), `STATE_OPEN` (1), `STATE_CLOSING` (2).
   - `PackedFloat32Array.to_byte_array()` directly serializes float32 audio samples into little-endian IEEE 754 binary bytes (1 sample = 4 bytes; 4 samples = 16 bytes).
   - In Python, `np.frombuffer(raw_bytes, dtype=np.float32)` decodes the buffer with zero transformation overhead.
3. **GDScript Class Indexing & Headless Inheritance**:
   - In Godot headless mode, `.godot/global_script_class_cache.cfg` stores the indexed class names. When files are created in new subdirectories or prior to editor cache re-indexing, declaring `class_name Foo` and using `extends Foo` in another file without editor cache rebuild produces:
     `SCRIPT ERROR: Parse Error: Could not find base class "AudioPitchModel".`
   - Using string path inheritance:
     ```gdscript
     class_name MockDriver
     extends "res://scripts/inference/audio_pitch_model.gd"
     ```
     is 100% immune to missing class cache and compiles with status `0` (`Reload with string path: 0`).
4. **GDScript Lambda Closure Semantics**:
   - Reassigning a captured local variable inside a GDScript lambda (e.g. `captured = p.duplicate()`) mutates only the closure-local copy, leaving the outer array empty.
   - Mutating via array methods (`captured.clear(); captured.append_array(p)`) correctly modifies the outer instance.
5. **Peer Implementations Cross-Checked**:
   - `m3_explorer_2/proposed_inference_server.py`: Listens on `ws://127.0.0.1:8765`. Accepts raw binary float32 PCM chunks via WebSocket, processes via sliding ring buffer of 43,844 samples with `np.interp` resampling to 22,050 Hz, and sends JSON response `{"type":"pitches", "pitches":[...], "onsets":[...], "timestamp":..., "confidence":{...}}` or compact binary `[N, p1..pN, M, o1..oM]`.
   - `m3_explorer_3/proposed_audio_capture.gd`: Line 138-139 checks `if pitch_model != null and pitch_model.has_method("push_audio_samples"): pitch_model.push_audio_samples(forward_samples)`.
6. **Existing Test Pass**:
   - `python tests\e2e\run_all_e2e_tests.py` ran all 230 E2E tests (Tiers 1-4) in 0.481s with exit code 0 (100% pass rate).
   - Standalone GDScript test suite `test_inference_architecture.gd` ran 17 test cases with exit code 0 (17 Passed, 0 Failed).

---

## 2. Logic Chain

1. **Decoupling ML from Game Loop** (Obs 1, Obs 5):
   - Rhythm game scoring requires low-latency, deterministic note matching at 60+ FPS. Running ML models directly on the main thread would cause frame stalls.
   - Creating `AudioPitchModel` extending `RefCounted` abstracts the inference backend behind clean contracts: `push_audio_samples(samples)`, `get_detected_pitches()`, `get_recent_onsets()`.
2. **Real-Time Streaming Driver** (Obs 2, Obs 5):
   - For live microphone play, `WebSocketDriver` connects to `ws://127.0.0.1:8765`.
   - Audio is converted via native `samples.to_byte_array()` and pushed as binary WebSocket packets.
   - `poll()` drains incoming packets and parses JSON (`{"type":"pitches", "pitches":[...], "onsets":[...]}`) or compact binary packets into typed `Array[int]`.
3. **Headless Deterministic Driver** (Obs 1, Obs 6):
   - Headless test runners, CI pipelines, and mobile tests require deterministic pitch feeds without running Python or requiring microphone hardware.
   - `MockDriver` provides both programmatic note feeds (`set_detected_pitches`, `set_recent_onsets`) and automated chart-driven playback (`load_chart`, `load_chart_from_file`, `update_playback_time`).
4. **Inheritance Reliability** (Obs 3):
   - Because CI environments run `--headless` without an interactive editor session, relying strictly on global class names for internal module inheritance risks cache misses.
   - Specifying `extends "res://scripts/inference/audio_pitch_model.gd"` in both drivers ensures zero parser failures while still exposing `class_name WebSocketDriver` and `class_name MockDriver` globally.
5. **Onset Atomicity** (Obs 5, Obs 6):
   - Note onsets are discrete hit triggers. Adding `pop_recent_onsets()` provides atomic drain semantics so game scoring loops never trigger duplicate hits on subsequent frames, while `get_recent_onsets(clear=false)` remains safe and idempotent for debug overlays.

---

## 3. Caveats

1. **Android Deployment Mode**:
   - `WebSocketDriver` connects to `ws://127.0.0.1:8765`. When deployed standalone to Android (Google Pixel 7a), a localhost Python daemon cannot run unless bundled as a native shared library (`.so`) via GDExtension / ONNX Runtime mobile or running against a local network development PC. For standalone mobile play without an active PC server, the game gracefully uses `MockDriver` or chart-synchronized offline playback.
2. **Audio Sample Rate Resampling**:
   - Godot's audio mix rate is 44,100 Hz on Windows and 48,000 Hz on Pixel 7a (`AudioServer.get_mix_rate()`). `WebSocketDriver` streams raw samples directly; the Python `inference_server.py` performs fractional resampling via `np.interp` to 22,050 Hz. If a custom standalone C++ GDExtension runner is added in the future, it should implement internal linear resampling.
3. **No other caveats.**

---

## 4. Conclusion

The modular inference subsystem for Godot 4 is fully designed, documented, and validated:
- Base class: `res://scripts/inference/audio_pitch_model.gd`
- Real-time driver: `res://scripts/inference/websocket_driver.gd`
- Deterministic mock driver: `res://scripts/inference/mock_driver.gd`

The proposed implementation files are ready for immediate drop-in deployment by the Worker:
- `.agents/teamwork/m3_explorer_1/proposed_audio_pitch_model.gd` $\to$ `res://scripts/inference/audio_pitch_model.gd`
- `.agents/teamwork/m3_explorer_1/proposed_websocket_driver.gd` $\to$ `res://scripts/inference/websocket_driver.gd`
- `.agents/teamwork/m3_explorer_1/proposed_mock_driver.gd` $\to$ `res://scripts/inference/mock_driver.gd`

---

## 5. Verification Method

To independently verify the architecture and implementations:

1. **Run Inference Architecture Verification Suite**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless -s res://.agents/teamwork/m3_explorer_1/test_inference_architecture.gd
   ```
   **Expected Output**:
   ```
   RESULTS: 17 Passed, 0 Failed
   INFERENCE ARCHITECTURE VERIFICATION SUCCESSFUL [OK]
   Exit code: 0
   ```

2. **Run E2E Regression Suite**:
   ```powershell
   python tests\e2e\run_all_e2e_tests.py
   ```
   **Expected Output**:
   ```
   TOTAL: 230 Passed, 0 Failed, 0 Errors
   [PASS] All 230 E2E tests executed and passed successfully
   Exit code: 0
   ```

3. **Invalidation Conditions**:
   - Any failure or crash when pushing empty or non-empty `PackedFloat32Array` buffers to `AudioPitchModel`.
   - `get_detected_pitches()` or `get_recent_onsets()` returning `null` / `nil` instead of typed `Array[int]`.
   - `WebSocketDriver` failing to parse JSON `{"type":"pitches", "pitches":[60, 64], "onsets":[60]}`.
   - `MockDriver` failing to track chart notes or simulate polyphonic chords.
