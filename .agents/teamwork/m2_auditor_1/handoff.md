# Forensic Audit Report & Handoff: Milestone 2 — Bundled Test Pieces & Assets

**Auditor**: `m2_auditor_1` (Forensic Integrity Auditor)  
**Parent Orchestrator**: `7da07436-85a8-464d-9f3c-d174d6d86ee2`  
**Target Work Product**: Milestone 2 Deliverables (`assets/models/nmp.onnx`, `tools/generate_test_assets.py`, `assets/test_pieces/`, mirrored assets in `assets/audio/`, `assets/scores/`, `assets/charts/`)  
**Profile**: General Project  
**Integrity Mode**: Development (per `ORIGINAL_REQUEST.md`)  
**Verdict**: **CLEAN**

---

## 1. Observation

### 1.1 Spotify Basic Pitch ONNX Model Verification (`assets/models/nmp.onnx`)
- **File Existence & Exact Size**:
  `assets/models/nmp.onnx` exists with exactly **230,444 bytes** (matches official Spotify Basic Pitch ICASSP 2022 pre-trained weights).
- **Cryptographic Hash (SHA-256)**:
  `2c3c1d144bfa61ad236e92e169c13535c880469a12a047d4e73451f2c059a0ec`
  Bit-for-bit identical to the official installed `basic_pitch` package model at:
  `C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages\basic_pitch\saved_models\icassp_2022\nmp.onnx`
- **ONNX Runtime Session Loading & Tensor Signature**:
  - Input: `serving_default_input_2:0`, shape `['unk__749', 43844, 1]`, dtype `tensor(float)`
  - Output 0: `StatefulPartitionedCall:2`, shape `['unk__750', 172, 88]`, dtype `tensor(float)` (onset activations across 88 MIDI pitches)
  - Output 1: `StatefulPartitionedCall:1`, shape `['unk__751', 172, 88]`, dtype `tensor(float)` (note frame activations across 88 MIDI pitches)
  - Output 2: `StatefulPartitionedCall:0`, shape `['unk__752', 172, 264]`, dtype `tensor(float)` (pitch bend / contour activations across 264 bins)
- **Empirical Inference Execution**:
  - Test 1 (440 Hz Sine wave input): Predicted peak activation at bin 48 (MIDI 69 = A4 = 440 Hz) with 100% precision.
  - Test 2 (Audio chunk of Piece 1 "Ode to Joy"): Top detected MIDI pitches were `[64, 67, 65]` (E4, G4, F4), matching Beethoven's first measure.

### 1.2 Asset Generator Script Verification (`tools/generate_test_assets.py`)
- **Audio Synthesis**:
  Pure mathematical additive synthesis: fundamental frequency $f_0 = 440 \times 2^{(p - 69)/12}$ plus 2nd (35%), 3rd (15%), and 4th (8%) harmonics. Shaped with linear 15 ms attack and 30 ms release ADSR envelopes. Normalized to 80% maximum amplitude ($\pm 26,213$ on 16-bit PCM scale). Written directly to uncompressed mono WAV via Python's standard `wave` library. No mock facades, dummy constants, or pre-recorded clips.
- **Score Image Rendering**:
  1600x900 8-bit grayscale PNG rendered dynamically using Pillow (`PIL.Image`, `PIL.ImageDraw`). Draws dual 5-line Treble (Y=320..400) and Bass (Y=440..520) staves, clefs, time signatures, barlines, noteheads (solid for quarter/eighth, hollow for half/whole), stems (directional based on middle line), eighth-note flags, dotted-note dots, and dynamic ledger lines for Middle C (Y=420), A5 (Y=300), E2 (Y=540), and C2 (Y=560).
- **JSON Chart Generation**:
  Structured charts conforming strictly to Section 4.5 schema and `tests/e2e/e2e_test_utils.py` `ChartValidator`. Full root metadata, measure timing partitions, and per-note event records.
- **MIDI File Generation**:
  Standard Type 1 MIDI files generated via `music21` with distinct Treble and Bass parts, tempos, time signatures, notes, durations, and velocities.

### 1.3 Deep Inspection of All 12 Bundled Assets (`assets/test_pieces/`)
Executed independent audit script (`.agents/teamwork/m2_auditor_1/audit_assets.py`):
1. **Piece 1: Monophonic Melody ("Ode to Joy")**:
   - `audio.wav`: 22,050 Hz, 1 channel, 16-bit PCM, 187,425 frames (8.50s), peak=26,213 (0.80 full scale), RMS=16,104.69. Real audio.
   - `score.png`: Format=PNG, Mode=L, Size=(1600, 900), 30,150 black pixels, 1,406,039 white pixels. Real rendered score.
   - `ground_truth.json`: 4 measures, 15 notes, 120.0 BPM, pitches C4 to G4 on Treble staff.
   - `ground_truth.mid`: Size 199 bytes, 2 tracks, 15 notes parsed, 5 unique pitches matching chart exactly.
2. **Piece 2: 2-Part Harmony ("Bach Minuet / 2-Part Counterpoint")**:
   - `audio.wav`: 22,050 Hz, 1 channel, 16-bit PCM, 171,990 frames (7.80s), peak=26,213, RMS=11,466.98. Real audio.
   - `score.png`: Format=PNG, Mode=L, Size=(1600, 900), 31,986 black pixels, 1,403,434 white pixels. Real rendered score.
   - `ground_truth.json`: 4 measures, 16 notes, 100.0 BPM, dual Treble and Bass staves.
   - `ground_truth.mid`: Size 250 bytes, 3 tracks, 16 notes parsed, 8 unique pitches matching chart exactly.
3. **Piece 3: Polyphonic Progression ("Cadence & Triad Progression")**:
   - `audio.wav`: 22,050 Hz, 1 channel, 16-bit PCM, 341,775 frames (15.50s), peak=26,213, RMS=9,340.01. Real audio.
   - `score.png`: Format=PNG, Mode=L, Size=(1600, 900), 30,347 black pixels, 1,404,399 white pixels. Real rendered score.
   - `ground_truth.json`: 5 measures, 20 notes across 5 multi-voice chords, 80.0 BPM.
   - `ground_truth.mid`: Size 281 bytes, 3 tracks, 10 harmonic chord events with 20 distinct constituent notes parsed, 13 unique pitches matching chart exactly.

### 1.4 Mirrored Assets
- All 12 assets are mirrored into `assets/audio/`, `assets/scores/`, and `assets/charts/` under both canonical piece keys and readable aliases (e.g., `ode_to_joy.wav`, `bach_minuet.wav`, `cadence_triads.wav`).
- Bit-for-bit SHA256 equality was empirically verified across all mirrored pairs.

### 1.5 Test Suite Execution
- **Python E2E Test Suite** (`python tests/e2e/run_all_e2e_tests.py`):
  - Tier 1 (Feature Coverage): 100/100 passed (0 fail, 0 err)
  - Tier 2 (Boundary & Corner Cases): 100/100 passed (0 fail, 0 err)
  - Tier 3 (Cross-Feature Combinations): 20/20 passed (0 fail, 0 err)
  - Tier 4 (Real-World Scenarios): 10/10 passed (0 fail, 0 err)
  - **Total**: 230/230 passed (100% pass rate) in 0.473s.
- **Godot Headless Scoring Runner** (`res://tests/test_scoring_runner.gd`):
  - 91 passed, 0 failed.
- **Godot Adversarial Highway & Scoring Harness** (`res://tests/test_adversarial_m1.gd`):
  - 78 passed, 0 failed.
- **Godot Adversarial Scoring Precision Harness** (`res://tests/test_scoring_adversarial.gd`):
  - 111 passed, 0 failed.

---

## 2. Logic Chain

1. **Model Provenance and Functionality**:
   - The ONNX model size (230,444 bytes) and SHA256 match the official Spotify Basic Pitch ICASSP 2022 weights exactly.
   - ONNX Runtime initializes without warnings or errors.
   - Inference on pure sine (440 Hz) and generated piece audio yields real, mathematically expected pitch activation peaks (A4 = 69, E4 = 64, G4 = 67, F4 = 65).
   - Conclusion: The model is genuine, functional, uncorrupted, and un-mocked.
2. **Asset Authenticity and Non-Triviality**:
   - WAV files have true 22,050 Hz sampling rate, 1 channel, 16-bit PCM format, active non-zero waveform energy, and 80% peak normalization.
   - PNG files have genuine raster renderings with clean staves, clefs, and notes (>30,000 black pixels per score).
   - JSON charts have valid diatonic pitch assignments and full measure geometries conforming to `ChartValidator`.
   - MIDI files are valid Type 1 multitrack files with pitch collections identical to the JSON charts.
   - Conclusion: All 12 assets are genuine musical data generated via mathematical and vector synthesis, not dummy stubs.
3. **No Prohibited Patterns**:
   - No hardcoded test outputs or dummy return facades were found.
   - No pre-populated result logs exist in the repository.
   - In Development Mode, using Spotify's official pretrained ONNX weights fulfills requirement R2 directly.

---

## 3. Caveats

- Live microphone hardware capture and streaming WebSocket/in-engine inference runners are scheduled for Milestone 3 (`PROJECT.md` Feature 9-11).
- Optical Music Recognition (OMR) detection engines (`omr_processor.gd` and `omr_engine.py`) are scheduled for Milestone 4.
- No other caveats.

---

## 4. Conclusion

**FINAL VERDICT: CLEAN**

Milestone 2 deliverables satisfy all integrity, architectural, and quality standards:
- `assets/models/nmp.onnx` is genuine official Spotify Basic Pitch weights (230,444 bytes) and performs real neural pitch inference.
- `tools/generate_test_assets.py` synthesizes authentic audio waveforms, renders clean sheet music scores via Pillow, and exports valid JSON charts and MIDI files.
- All 12 test assets across monophonic, harmony, and polyphonic pieces exist, have non-zero size, and pass deep validation.
- 100% of the 230 E2E tests and all Godot headless tests pass cleanly without errors.

---

## 5. Verification Method

To independently reproduce the forensic verification:

1. **Verify Official Spotify Basic Pitch ONNX Model & Inference**:
   ```powershell
   python -c "import onnxruntime as ort, numpy as np; s = ort.InferenceSession('assets/models/nmp.onnx'); assert s.get_inputs()[0].shape[1] == 43844; print('Model Verified')"
   ```
2. **Verify All 12 Assets Deep Inspection**:
   ```powershell
   python .agents/teamwork/m2_auditor_1/audit_assets.py
   ```
3. **Run E2E Test Suite**:
   ```powershell
   python tests/e2e/run_all_e2e_tests.py
   ```
4. **Run Godot Headless Suites**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_adversarial_m1.gd"
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_adversarial.gd"
   ```
