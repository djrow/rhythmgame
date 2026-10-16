# Milestone 3 Independent Quality & Adversarial Review Report

**Agent**: `m3_reviewer_1` (Roles: Reviewer, Adversarial Critic)  
**Parent Agent**: `7da07436-85a8-464d-9f3c-d174d6d86ee2`  
**Milestone**: Milestone 3 — Basic Pitch ONNX & Audio Inference  
**Verdict**: **APPROVE**  
**Date**: 2026-10-16  

---

## 1. Observation

### 1.1 Direct Inspection of Implemented Targets

1. **`assets/models/nmp.onnx`**:
   - Model file size: 230,444 bytes.
   - Inputs: `serving_default_input_2:0`, shape `[batch, 43844, 1]`, type `float32`.
   - Outputs: `StatefulPartitionedCall:2` (onsets: `[batch, 172, 88]`), `StatefulPartitionedCall:1` (notes: `[batch, 172, 88]`), `StatefulPartitionedCall:0` (contours: `[batch, 172, 264]`).
   - Model SHA256: `2c3c1d144bfa61ad236e92e169c13535c880469a12a047d4e73451f2c059a0ec`.
   - Verified verbatim against official Spotify `basic_pitch` package (`basic_pitch/saved_models/icassp_2022/nmp.onnx`): identical SHA256 hash.

2. **`python/basic_pitch_onnx.py`**:
   - Zero `scipy`, `librosa`, or `resampy` dependencies. Only imports: `os`, `wave`, `typing`, `numpy`, `onnxruntime`.
   - Linear interpolation resampling implemented via `np.interp` (`resample_to_22050`).
   - Pure NumPy 1D peak detection implemented via neighbor comparison `(mat[1:-1] > mat[:-2]) & (mat[1:-1] >= mat[2:])` (`argrelmax_axis0`).
   - Frame difference onset inference implemented via `infer_onsets_numpy`.
   - Receptive field boundary filtering: frames 158..167 inspected to eliminate output edge padding distortion.
   - 120ms per-pitch onset debounce implemented in `process_streaming_chunk`.
   - Overlap-add unwrapping with 30-frame padding implemented in `transcribe_file`.

3. **`python/inference_server.py`**:
   - Asynchronous WebSocket server running on `ws://127.0.0.1:8765`.
   - Supports text control commands (`config`, `reset`, `ping`) and binary PCM streaming.
   - Dual protocol support: JSON payload schema and compact binary encoding (`[N_pitches, ...pitches, N_onsets, ...onsets]`).

4. **`scripts/inference/audio_pitch_model.gd`, `websocket_driver.gd`, `mock_driver.gd`**:
   - Clean polymorphic inheritance from `AudioPitchModel extends RefCounted`.
   - Base signals: `pitches_detected`, `onsets_detected`, `model_ready`, `model_error`.
   - Polling methods: `push_audio_samples()`, `get_detected_pitches()`, `get_recent_onsets()`, `pop_recent_onsets()`, `is_model_ready()`, `reset()`, `poll()`.
   - `MockDriver` supports both programmatic injection and chart-driven simulation.
   - `WebSocketDriver` supports automated reconnection and packet draining.

5. **`scripts/audio_capture.gd` & `scripts/main.gd`**:
   - `AudioCapture` attaches `AudioEffectCapture` to dedicated `Record` bus (configured with `send = &""` to prevent feedback loops).
   - Stereo to mono downmixing with root-mean-square amplitude calculation.
   - Noise gate at 0.005 RMS ($\approx -46$ dB); advances model temporal clock with zeroed buffers during silence.
   - `Main` polls pitch model, distinguishes attack onsets from sustained hold notes (`_last_detected_pitches`), and matches polyphonic pitch clusters concurrently in `ScoringEngine.process_input()`.

### 1.2 Independent Execution of Required Verification Commands

#### Command 1: Standalone Transcription Verification Harness
Command:
```powershell
python tests/test_transcription_harness.py --min-f1 0.80
```
Verbatim Terminal Output:
```
======================================================================
MICGAME-3 BASIC PITCH ONNX TRANSCRIPTION HARNESS
======================================================================
Model Path : C:\Users\david\Documents\micgame-3\assets\models\nmp.onnx
Audio Dir  : C:\Users\david\Documents\micgame-3\assets\audio
Charts Dir : C:\Users\david\Documents\micgame-3\assets\charts
Min F1 Req : 80.0%

Piece: Monophonic Melody ('Ode to Joy')
  Audio File       : ode_to_joy.wav
  Inference Time   : 0.097 s
  Ground Truth     : 15 notes
  Detected Notes   : 15 notes
  TP / FP / FN     : 14 / 1 / 1
  Precision        : 93.3%
  Recall           : 93.3%
  F1-Score         : 93.3% (Required: >=80.0%)
  Status           : PASSED [OK]

Piece: 2-Part Harmony ('Bach Minuet')
  Audio File       : bach_minuet.wav
  Inference Time   : 0.084 s
  Ground Truth     : 16 notes
  Detected Notes   : 18 notes
  TP / FP / FN     : 14 / 4 / 2
  Precision        : 77.8%
  Recall           : 87.5%
  F1-Score         : 82.4% (Required: >=80.0%)
  Status           : PASSED [OK]

Piece: Polyphonic Chordal ('Cadence Triads')
  Audio File       : cadence_triads.wav
  Inference Time   : 0.136 s
  Ground Truth     : 20 notes
  Detected Notes   : 20 notes
  TP / FP / FN     : 16 / 4 / 4
  Precision        : 80.0%
  Recall           : 80.0%
  F1-Score         : 80.0% (Required: >=80.0%)
  Polyphonic Chords: PASS (Concurrent notes verified)
  Status           : PASSED [OK]

======================================================================
OVERALL HARNESS RESULT: ALL PASS [OK]
======================================================================
```
Exit code: `0`.

#### Command 2: Headless Godot Inference & Scoring Runner
Command:
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"
```
Verbatim Terminal Output:
```
==================================================
 RUNNING FULL INFERENCE & SCORING VERIFICATION    
==================================================

--- Test Suite 1: AudioCapture Record Bus & Lifecycle ---
  [PASS] AudioCapture script loads cleanly
  [PASS] Initial capturing state is false (expected false, got false)
  [PASS] Record bus index resolved successfully
  [PASS] AudioEffectCapture attached to Record bus
  [PASS] Capture started successfully (expected true, got true)
  [PASS] Capture stopped successfully (expected false, got false)

--- Test Suite 2: Stereo Downmix & RMS Noise Gating (-45 dB) ---
  [PASS] Stereo (1.0, 1.0) -> Mono 1.0 (expected 1.0, got 1.0)
  [PASS] Stereo (-0.8, -0.2) -> Mono -0.5
  [PASS] Stereo (0.5, -0.5) -> Mono 0.0 (expected 0.0, got 0.0)
  [PASS] Silence RMS is 0.0 (expected 0.0, got 0.0)
  [PASS] Silence dB is -100 dB (expected -100.0, got -100.0)
  [PASS] Silence is gated
  [PASS] Zeroes pushed during silence to preserve clock (expected 256, got 256)
  [PASS] Noise RMS < 0.005 threshold
  [PASS] Room noise suppressed by noise gate
  [PASS] Musical tone RMS is > 0.05
  [PASS] Musical tone passes noise gate
  [PASS] Active audio samples received by model runner (expected 256, got 256)

--- Test Suite 3: MockDriver & AudioPitchModel Protocol ---
  [PASS] MockDriver is immediately ready
  [PASS] Initial detected pitches is empty (expected 0, got 0)
  [PASS] Initial recent onsets is empty (expected 0, got 0)
  [PASS] Detected pitches updated to [60, 64, 67] (expected [60, 64, 67], got [60, 64, 67])
  [PASS] Recent onsets updated to [60] (expected [60], got [60])
  [PASS] WebSocketDriver script loads cleanly
  [PASS] WebSocket driver initial readiness is false until connected (expected false, got false)

--- Test Suite 4: Polyphonic Chord Matching (C Major Triad) ---
  [PASS] All 3 chord tones matched and scored concurrently (expected 3, got 3)
  [PASS] C4 is_hit = true (expected true, got true)
  [PASS] E4 is_hit = true (expected true, got true)
  [PASS] G4 is_hit = true (expected true, got true)
  [PASS] Combo incremented to 3 for triad (expected 3, got 3)
  [PASS] Score awarded 300 points (3 x 100 Perfect) (expected 300, got 300)
  [PASS] 3 Perfect counts recorded (expected 3, got 3)

--- Test Suite 5: Partial Chord Match & Note Expiration ---
  [PASS] C4 struck (expected true, got true)
  [PASS] E4 struck (expected true, got true)
  [PASS] G4 remains unhit (expected false, got false)
  [PASS] Combo is 2 (expected 2, got 2)
  [PASS] 1 note expired (G4) (expected 1, got 1)
  [PASS] G4 judged MISS (expected MISS, got MISS)
  [PASS] G4 marked missed (expected true, got true)
  [PASS] Combo reset to 0 by missed chord note (expected 0, got 0)

--- Test Suite 6: Sustain vs Onset Edge Retrigger Filtering ---
  [PASS] Note 1 hit at 1.0s (expected true, got true)
  [PASS] Combo is 1 (expected 1, got 1)
  [PASS] No duplicate strike during sustained note (expected 0, got 0)
  [PASS] No duplicate strike during sustained note (expected 0, got 0)
  [PASS] No duplicate strike during sustained note (expected 0, got 0)
  [PASS] No duplicate strike during sustained note (expected 0, got 0)
  [PASS] No duplicate strike during sustained note (expected 0, got 0)
  [PASS] Combo preserved at 1 during sustain (expected 1, got 1)
  [PASS] Subsequent note 2 at 2.5s untouched (expected false, got false)
  [PASS] Note 2 hit on new onset (expected true, got true)
  [PASS] Combo reached 2 (expected 2, got 2)
  [PASS] Score reached 200 (expected 200, got 200)

--- Test Suite 7: Full End-to-End Chain (Capture -> Model -> Matcher -> Scoring) ---
  [PASS] Background noise gated
  [PASS] Musical audio passed noise gate
  [PASS] Note C4 scored from audio pipeline (expected true, got true)
  [PASS] Combo is 1 (expected 1, got 1)
  [PASS] Chord note E4 scored (expected true, got true)
  [PASS] Chord note G4 scored (expected true, got true)
  [PASS] Combo reached 3 (expected 3, got 3)
  [PASS] 3 total notes scored (expected 3, got 3)
  [PASS] All 3 scored PERFECT (expected 3, got 3)
  [PASS] 0 misses (expected 0, got 0)
  [PASS] 100.0% accuracy (expected 100.0, got 100.0)
==================================================
 RESULTS: 63 Passed, 0 Failed
==================================================
ALL INFERENCE & SCORING SUITES PASSED [OK]
```
Exit code: `0`.

#### Command 3: Full Project E2E Regression Suite
Command:
```powershell
python tests/e2e/run_all_e2e_tests.py
```
Verbatim Terminal Output:
```
================================================================================
           MICGAME-3 E2E TEST RUNNER - AUTOMATED QUALITY REPORT
================================================================================
Tier Name                              | Total  | Passed | Fail  | Err   | Time (s)
--------------------------------------------------------------------------------
Tier 1: Feature Coverage               | 100    | 100    | 0     | 0     | 0.305   
Tier 2: Boundary & Corner Cases        | 100    | 100    | 0     | 0     | 0.095   
Tier 3: Cross-Feature Combinations     | 20     | 20     | 0     | 0     | 0.076   
Tier 4: Real-World Scenarios           | 10     | 10     | 0     | 0     | 0.001   
--------------------------------------------------------------------------------
TOTAL                                  | 230    | 230    | 0     | 0     | 0.478   
================================================================================

FINAL ASSESSMENT:
 [PASS] All 230 E2E tests executed and passed successfully in 0.478 seconds.
 Coverage: Tier 1 (100), Tier 2 (100), Tier 3 (20), Tier 4 (10).
 100% Pass Rate requirement fulfilled. Exit code: 0
```
Exit code: `0`.

### 1.3 Adversarial Stress-Test Experiments

1. **Synthetic Frequency Discrimination**:
   - Synthesized a pure 440.0 Hz sine wave ($A_4$). Runner detected MIDI 69 ($A_4$) at onset 0.023s with 0.638 confidence.
   - Synthesized a simultaneous C Major triad ($C_4 = 261.63$ Hz, $E_4 = 329.63$ Hz, $G_4 = 392.00$ Hz). Runner detected all 3 pitches: `[67, 64, 60]`.
2. **WebSocket Real-Time Server Communication**:
   - Spun up `inference_server.py` on test port 8769 and verified:
     - JSON Ping/Pong: latency < 1ms.
     - Dynamic configuration handshake: `config_ack` OK.
     - Streaming float32 PCM: detected pitch 69 with 12.8ms inference latency.
     - Compact binary protocol: received `pitches=[69], onsets=[]` in raw byte packet.
3. **Headless Scene Execution**:
   - Ran `res://scenes/main.tscn` directly in Godot headless mode for 60 frames: exited cleanly with exit code 0.
4. **Milestone 1 Regression Check**:
   - Ran `res://tests/test_scoring_runner.gd`: all 91 tests passed cleanly with 0 failures.

---

## 2. Logic Chain

1. **Integrity Verification**:
   - The model binary `assets/models/nmp.onnx` has SHA256 `2c3c1d144bfa61ad236e92e169c13535c880469a12a047d4e73451f2c059a0ec`, identically matching the official Spotify repository release.
   - There are zero hardcoded test outputs or dummy facades in `python/basic_pitch_onnx.py`. Running novel synthesized frequencies confirms the neural network evaluates genuine spectrogram activations.
   - Verification outputs produced by `m3_worker_1` were independently reproduced line-for-line with identical exit codes.
   - **Result**: Zero integrity violations found.
2. **Acceptance Criteria Verification**:
   - *F1-score $\ge 80\%$ on polyphonic test audio*: Verified on `cadence_triads.wav` (80.0%), `bach_minuet.wav` (82.4%), and `ode_to_joy.wav` (93.3%).
   - *Simultaneous chord pitches identified as concurrent notes*: Verified in `cadence_triads.wav` via `verify_polyphonic_simultaneity` and in `test_inference_scoring_runner.gd` Test Suite 4.
   - *Pluggable abstract interface decoupling model from game loop*: Verified in `scripts/inference/audio_pitch_model.gd`, `mock_driver.gd`, and `websocket_driver.gd`.
   - *Low-latency mic capture with noise gating*: Verified in `scripts/audio_capture.gd` (Record bus `send=""`, RMS threshold $0.005$, zero-fill during silence).
   - *Cross-platform / Android readiness*: Verified in `export_presets.cfg` (`RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`, ARM64-v8a target).
3. **Adversarial Hardening Findings**:
   - While all acceptance criteria are met, stress testing surfaced 4 minor edge cases for defensive hardening:
     - *Finding A1 (Minor)*: In `basic_pitch_onnx.py` line 289, passing zero-length audio `np.array([])` causes `frames.shape[0] == 0`, triggering a `ValueError: zero-size array` in `infer_onsets_numpy`.
     - *Finding A2 (Minor)*: In `websocket_driver.gd` line 116, if a fuzzed JSON packet contains a non-array value for `"pitches"`, assigning to `var raw_pitches: Array` triggers a GDScript type mismatch error.
     - *Finding A3 (Minor)*: In `websocket_driver.gd` line 142, if a truncated binary packet is received (e.g. claims 5 onsets but provides 0), `new_onsets` evaluates to empty and overwrites `recent_onsets`.
     - *Finding A4 (Minor)*: In `inference_server.py` line 85, receiving raw byte buffers with length not divisible by 4 triggers `ValueError` in `np.frombuffer`.
   - These findings do not impair normal gameplay or benchmark execution, but provide valuable input for Milestone 5 hardening.

---

## 3. Caveats

- **Physical Android Microphone Validation**: End-to-end microphone capture was validated via Godot's audio bus architecture, mock injections, and export preset configuration. Final acoustic validation on physical Google Pixel 7a hardware requires APK deployment.
- **Inference Server Port Configuration**: The default server port is `8765`. In multi-instance or restricted environments, the port can be adjusted via CLI argument `--port`.

---

## 4. Conclusion

Milestone 3 (Basic Pitch ONNX & Audio Inference) meets all requirements specified in `ORIGINAL_REQUEST.md` and `PROJECT.md`. The implementation is genuine, mathematically sound, decoupled, and achieves $\ge 80\%$ polyphonic note transcription accuracy with 100% pass rates across all verification test suites.

**Verdict**: **APPROVE**

---

## 5. Verification Method

To reproduce and verify this review independently, run the following commands from `c:\Users\david\Documents\micgame-3`:

1. **Basic Pitch ONNX Polyphonic Transcription Verification**:
   ```powershell
   python tests/test_transcription_harness.py --min-f1 0.80
   ```
   *Expected outcome*: Exit code 0, all 3 pieces $\ge 80\%$ F1-score.

2. **Headless Godot Inference & Scoring Runner**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"
   ```
   *Expected outcome*: Exit code 0, 63 Passed, 0 Failed.

3. **Full Project E2E Suite**:
   ```powershell
   python tests/e2e/run_all_e2e_tests.py
   ```
   *Expected outcome*: Exit code 0, 230 Passed, 0 Failed.
