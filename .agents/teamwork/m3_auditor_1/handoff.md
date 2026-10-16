# Forensic Audit Report: Milestone 3 Audio Inference & Pitch Tracking Subsystem

**Auditor**: `m3_auditor_1`  
**Target**: Milestone 3 — Basic Pitch ONNX & Audio Inference  
**Date**: 2026-10-16  
**Integrity Mode**: Development (from `ORIGINAL_REQUEST.md`, line 8)  
**Definitive Verdict**: **CLEAN**

---

## Forensic Audit Summary

**Work Product**: Milestone 3 ML Audio Pipeline & Pitch Tracking Model  
**Profile**: General Project  
**Verdict**: **CLEAN**

### Phase Results
- **Hardcoded Test Results Check**: **PASS** — Zero hardcoded scores, predictions, or PASS strings detected across all files.
- **Facade Implementation Check**: **PASS** — Pure NumPy resampling, peak-picking, circular buffer streaming, and Godot drivers contain complete, non-dummy logic.
- **Pre-populated Artifact Check**: **PASS** — No pre-existing logs, result caches, or certification artifacts.
- **Self-Certifying Tests Check**: **PASS** — Ground truth note events from test pieces are matched against real ONNX model outputs using MIR standard tolerances.
- **Empirical Model Validation**: **PASS** — Spotify Basic Pitch ONNX model inspected: inputs `serving_default_input_2:0` `[?, 43844, 1]`, outputs onsets `[?, 172, 88]`, notes `[?, 172, 88]`, contours `[?, 172, 264]`. Synthesized 440 Hz sine wave correctly yielded MIDI pitch 69 ($A_4$, probability 0.760); synthesized C major triad correctly yielded pitches 60, 64, 67.
- **WebSocket Streaming Test**: **PASS** — Live asynchronous client connected to `ws://127.0.0.1:8765`, streamed float32 PCM audio, and received verified MIDI pitch detections with 10.2ms latency.
- **Godot Headless Runner Execution**: **PASS** — 63 of 63 assertions passed across all 7 test suites (AudioCapture, RMS noise gate, mock/WS drivers, polyphonic chord matching, miss expiration, debounce filtering, end-to-end chain).
- **Transcription Accuracy Verification**: **PASS** — F1 scores achieved: Monophonic (93.3%), 2-Part Harmony (82.4%), Polyphonic Chordal (80.0%), exceeding the $\ge 80\%$ acceptance threshold.
- **Full E2E Regression Pass**: **PASS** — 230 of 230 tests passed across Tiers 1–4 with exit code 0.

---

## 1. Observation

### 1.1 Inspected File Paths and Scope
- `python/basic_pitch_onnx.py` (342 lines): Pure NumPy audio preprocessing (WAV reading, linear interpolation resampling to 22.05 kHz via `np.interp`, peak-picking via boolean neighbor mask `argrelmax_axis0`, onset inference, circular buffer sliding, overlap-add transcription unwrapping).
- `python/inference_server.py` (294 lines): Asynchronous WebSocket server using `websockets` on `ws://127.0.0.1:8765` handling PCM decoding (float32/int16), receptive field analysis (frames 158..167), 120ms onset debounce, and binary/JSON serialization.
- `scripts/inference/audio_pitch_model.gd` (52 lines): Abstract base interface (`RefCounted`) with signals (`pitches_detected`, `onsets_detected`, `model_ready`, `model_error`) and polymorphic methods.
- `scripts/inference/websocket_driver.gd` (182 lines): Concrete driver using Godot 4 `WebSocketPeer` streaming raw PCM float32 buffers and parsing responses.
- `scripts/inference/mock_driver.gd` (126 lines): Offline / deterministic mock driver supporting programmatic note injection and chart-driven automated playback.
- `scripts/audio_capture.gd` (154 lines): Low-latency microphone input management with `AudioEffectCapture` on `Record` bus, mono downmix, RMS root-mean-square calculation, dB conversion, and silence injection during noise gating.
- `scripts/main.gd` (241 lines): Central coordinator linking `Highway`, `HUD`, `ScoringEngine`, `AudioCapture`, and `AudioPitchModel`, evaluating concurrent chord clusters against active highway notes.
- `tests/test_transcription_harness.py` (200 lines): Automated CLI transcription verification harness evaluating notes against ground-truth JSON charts.
- `tests/test_inference_scoring_runner.gd` (341 lines): Headless Godot runner covering 7 test suites and 63 assertions.

### 1.2 Empirical Model Inspection and Neural Network Output Verification
To prove the model is genuinely executing neural network inference and not returning mocked values, synthetic signals were injected directly into `BasicPitchOnnxRunner`:

**Test Command**:
```powershell
python -c "import onnxruntime as ort; session = ort.InferenceSession('assets/models/nmp.onnx'); print('Inputs:', [(i.name, i.shape, i.type) for i in session.get_inputs()]); print('Outputs:', [(o.name, o.shape, o.type) for o in session.get_outputs()])"
```
**Raw Output**:
```
Inputs: [('serving_default_input_2:0', ['unk__749', 43844, 1], 'tensor(float)')]
Outputs: [('StatefulPartitionedCall:2', ['unk__750', 172, 88], 'tensor(float)'), ('StatefulPartitionedCall:1', ['unk__751', 172, 88], 'tensor(float)'), ('StatefulPartitionedCall:0', ['unk__752', 172, 264], 'tensor(float)')]
```

**Single-Tone Inference (440 Hz Sine Wave vs Silence)**:
```powershell
python -c "import numpy as np; from python.basic_pitch_onnx import BasicPitchOnnxRunner, AUDIO_N_SAMPLES; runner = BasicPitchOnnxRunner('assets/models/nmp.onnx'); zero = np.zeros(AUDIO_N_SAMPLES, dtype=np.float32); notes, onsets, contours = runner.forward(zero); print('Zero input: max note prob =', np.max(notes), 'max onset prob =', np.max(onsets)); sr = 22050; t = np.arange(AUDIO_N_SAMPLES) / sr; a4 = 0.5 * np.sin(2 * np.pi * 440.0 * t).astype(np.float32); n_a4, o_a4, _ = runner.forward(a4); print('A4 input: max note prob =', np.max(n_a4), 'pitch index =', np.argmax(np.mean(n_a4, axis=0)) + 21)"
```
**Raw Output**:
```
Zero input: max note prob = 0.16070741 max onset prob = 0.31687897
A4 input: max note prob = 0.760113 pitch index = 69
```

**Polyphonic Triad Inference (C Major Chord: C4 261.63Hz, E4 329.63Hz, G4 392.00Hz)**:
```powershell
python -c "import numpy as np; from python.basic_pitch_onnx import BasicPitchOnnxRunner, AUDIO_N_SAMPLES; runner = BasicPitchOnnxRunner('assets/models/nmp.onnx'); sr = 22050; t = np.arange(AUDIO_N_SAMPLES) / sr; c_chord = (0.3 * np.sin(2 * np.pi * 261.63 * t) + 0.3 * np.sin(2 * np.pi * 329.63 * t) + 0.3 * np.sin(2 * np.pi * 392.0 * t)).astype(np.float32); notes, onsets, _ = runner.forward(c_chord); mean_probs = np.mean(notes, axis=0); top3_indices = np.argsort(mean_probs)[-3:][::-1]; print('Top 3 detected MIDI pitches for C major triad:', [i + 21 for i in top3_indices], 'probabilities:', [round(float(mean_probs[i]), 3) for i in top3_indices])"
```
**Raw Output**:
```
Top 3 detected MIDI pitches for C major triad: [67, 64, 60] probabilities: [0.657, 0.638, 0.521]
```
Observation: The top 3 detected pitches correspond exactly to $G_4$ (67), $E_4$ (64), and $C_4$ (60) with strong activation probabilities ($>0.50$).

### 1.3 Live WebSocket Streaming Server Verification
An automated client connected to `ws://127.0.0.1:8765`, sent ping commands, and streamed 43,844 samples of a 440 Hz tone.

**Raw Server & Client Output**:
```
[InferenceServer] Loading Basic Pitch ONNX model from assets/models/nmp.onnx...
[InferenceServer] ONNX model loaded successfully.
[InferenceServer] Model warm-up completed in 16.55 ms.
[InferenceServer] WebSocket inference server listening on ws://127.0.0.1:8765
Client connected from ('127.0.0.1', 64544)
Ping response: {"type": "pong", "server_time": 1792179985.1866028}
Audio inference response type: pitches
Pitches detected: [69]
Onsets detected: []
Latency ms: 10.2
WebSocket Server Test PASSED!
```
Observation: The server processed raw binary PCM audio, ran the forward pass in 10.2 ms (< 15 ms target), detected MIDI pitch 69 ($A_4$), and transmitted the response over WebSocket.

### 1.4 Godot Headless Runner Verification
Command:
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"
```
Output:
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

### 1.5 Standalone Transcription Harness Execution
Command:
```powershell
python tests/test_transcription_harness.py --min-f1 0.80
```
Output:
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
  Inference Time   : 0.081 s
  Ground Truth     : 15 notes
  Detected Notes   : 15 notes
  TP / FP / FN     : 14 / 1 / 1
  Precision        : 93.3%
  Recall           : 93.3%
  F1-Score         : 93.3% (Required: >=80.0%)
  Status           : PASSED [OK]

Piece: 2-Part Harmony ('Bach Minuet')
  Audio File       : bach_minuet.wav
  Inference Time   : 0.081 s
  Ground Truth     : 16 notes
  Detected Notes   : 18 notes
  TP / FP / FN     : 14 / 4 / 2
  Precision        : 77.8%
  Recall           : 87.5%
  F1-Score         : 82.4% (Required: >=80.0%)
  Status           : PASSED [OK]

Piece: Polyphonic Chordal ('Cadence Triads')
  Audio File       : cadence_triads.wav
  Inference Time   : 0.124 s
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

### 1.6 E2E Test Suite Regression Verification
Command:
```powershell
python tests/e2e/run_all_e2e_tests.py
```
Output:
```
TOTAL: 230 tests, 230 Passed, 0 Failed, 0 Errors in 0.546 seconds.
Exit code: 0
```

---

## 2. Logic Chain

1. **Authentication of ONNX Model Execution**:
   - Observations 1.1 and 1.2 demonstrate that `nmp.onnx` is an authentic Spotify Basic Pitch model with expected input shapes `[1, 43844, 1]` and output shapes `[1, 172, 88]`.
   - Feeding synthetic silence, pure sine tones, and chord combinations yielded distinct, accurate probability arrays and pitch indices (silence $\to$ max 0.16; $A_4$ 440 Hz $\to$ pitch index 69 with 0.76 probability; C-major chord $\to$ pitches 60, 64, 67 with $>0.50$ probability).
   - Therefore, the model inference is genuine, dynamic, and non-fabricated.

2. **Decoupled Architecture & Driver Authenticity**:
   - Observation 1.1 reveals that `AudioPitchModel` defines an abstract contract with signals and virtual methods.
   - `WebSocketDriver` correctly instantiates Godot 4 `WebSocketPeer`, transmits binary float32 PCM packets, and parses incoming JSON or compact binary responses.
   - `MockDriver` provides offline, deterministic note feeds and chart playback for CI and headless testing without microphone dependencies.
   - Observation 1.3 proves that the Python server communicates bidirectionally over WebSocket with $<11$ ms forward pass latency.

3. **Audio Capture and Noise Floor Gating**:
   - In `scripts/audio_capture.gd`, stereo audio buffers from `AudioEffectCapture` on the `Record` bus are downmixed to mono, and RMS amplitude is computed.
   - When amplitude falls below 0.005 ($\approx -46$ dB), the noise gate activates, suppressing background room noise and feeding zeros to maintain neural network temporal clock synchronization.
   - Observation 1.4 (Test Suite 2) demonstrates empirical verification of stereo downmixing, silence gating, and musical tone transmission.

4. **Polyphonic Scoring and Debounce Integrity**:
   - `scripts/main.gd` polls the model runner and distinguishes fresh attacks (`recent_onsets` or transitions from inactive to active) from continuous sustains (`_last_detected_pitches`).
   - Multiple candidate pitches arriving concurrently at the playhead are evaluated against `highway.active_notes` in parallel, correctly scoring polyphonic chords.
   - Sustained notes update the visual pitch indicator on the highway receptor line without generating duplicate scoring hits.
   - Observation 1.4 (Test Suites 4, 5, 6, 7) verifies concurrent triad scoring (C4, E4, G4 awarded 300 points, combo 3), partial chord misses, and sustain re-trigger prevention.

5. **Transcription Metric Authenticity**:
   - In `tests/test_transcription_harness.py`, TP, FP, and FN are calculated note-by-note using standard bipartite matching with temporal ($\pm 150$ ms) and pitch ($\pm 0$ semitones) tolerances against ground truth.
   - Grep analysis confirmed zero hardcoded metric values in Python or GDScript source files.
   - Observation 1.5 confirmed F1-scores of 93.3% (Ode to Joy), 82.4% (Bach Minuet), and 80.0% (Cadence Triads), fulfilling acceptance criteria §R2.

---

## 3. Caveats

- **No Caveats**: All 9 assigned files were verified through empirical inspection, raw test output capture, and synthetic stress testing.
- The physical microphone capture was verified via Godot's audio server bus simulation and synthetic buffer injection (`inject_mono_samples`), which is standard for headless CI environments.

---

## 4. Conclusion

Milestone 3 (ML Audio Pipeline & Pitch Tracking Model) satisfies all requirements from `ORIGINAL_REQUEST.md` (§R2, §R4) and `PROJECT.md`:
1. The Spotify Basic Pitch ONNX runner is genuine, executes via ONNX Runtime on CPU with pure NumPy, and produces authentic transcription metrics $\ge 80\%$ F1-score across all 3 test pieces.
2. The WebSocket inference server handles streaming PCM audio with $<11$ ms latency.
3. The `IAudioPitchModel` interface, `WebSocketDriver`, and `MockDriver` provide clean modular decoupling.
4. The `AudioCapture` subsystem enforces a $-46$ dB RMS noise gate and maintains neural network temporal alignment.
5. The `Main` coordinator and `ScoringEngine` accurately match and score polyphonic chords while debouncing sustained notes.
6. All 63 Godot headless assertions, 3 transcription pieces, and 230 E2E tests pass with exit code `0`.

**Verdict**: **CLEAN** — APPROVED.

---

## 5. Verification Method

To independently reproduce and verify this audit verdict, execute the following commands in powershell from the project root `c:\Users\david\Documents\micgame-3`:

1. **Verify Basic Pitch ONNX Transcription F1-Scores**:
   ```powershell
   python tests/test_transcription_harness.py --min-f1 0.80
   ```
   *Expected*: Exit code 0, Ode to Joy 93.3%, Bach Minuet 82.4%, Cadence Triads 80.0%.

2. **Verify Godot Audio Capture, Drivers, and Scoring Integration (Headless)**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"
   ```
   *Expected*: Exit code 0, 63 Passed, 0 Failed, `ALL INFERENCE & SCORING SUITES PASSED [OK]`.

3. **Verify Full E2E Test Suite Regression (Tiers 1-4)**:
   ```powershell
   python tests/e2e/run_all_e2e_tests.py
   ```
   *Expected*: Exit code 0, 230 Passed, 0 Failed.
