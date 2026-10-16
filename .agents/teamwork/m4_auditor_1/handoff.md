# Forensic Audit Report: Milestone 4 (On-Device OMR & Level Alignment)

**Work Product**: Milestone 4 Implementation (`python/omr_engine.py`, `tests/test_omr_harness.py`, `scripts/omr_processor.gd`, `scripts/level_loader.gd`, `tests/test_omr_runner.gd`, `scripts/main.gd`, `scenes/main.tscn`)  
**Profile**: General Project  
**Integrity Mode**: Development (per `ORIGINAL_REQUEST.md` line 8)  
**Auditor**: `m4_auditor_1`  
**Verdict**: **CLEAN**

---

### Phase Results
- **Hardcoded test results check**: PASS — Source code inspection and adversarial perturbation confirm no lookup tables bypassing pixels or hardcoded piece notes.
- **Facade implementation check**: PASS — Full OpenCV CV pipeline in Python (`omr_engine.py`) and native 2D Summed Area Table integral image in GDScript (`omr_processor.gd`) perform genuine pixel processing.
- **Fabricated verification outputs check**: PASS — No pre-existing `.log` files or fabricated verification artifacts exist; all tests executed live with zero errors.
- **Self-certifying tests check**: PASS — Accuracy calculated via bipartite matching against ground truth annotations generated in M2.
- **Execution delegation check**: PASS — GDScript OMR operates natively inside Godot without delegating to external processes or Python runtimes.

---

## 1. Observation

Direct forensic observations of code, test runs, and adversarial experiments:

### 1.1 Source Code Architecture Analysis
1. **`python/omr_engine.py`**:
   - Implements authentic computer vision algorithms:
     - Grayscale conversion and Otsu binarization (`cv2.threshold(..., cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)`).
     - Horizontal projection profiling (`np.sum(binary == 255, axis=1)`) to detect 10 grand staff lines and calculate inter-line spacing $S_s$.
     - Vertical morphology opening with a $1 \times 100\text{px}$ rectangular structuring element to detect 200px-spanning barlines while excluding 70px note stems.
     - Enclosed hole contour detection (`cv2.findContours(inv, cv2.RETR_LIST)`) to isolate hollow white holes of whole and half notes, followed by filling via `cv2.drawContours`.
     - Staff line run-length erasure preserving vertical stems and notehead cores.
     - Elliptical morphological opening ($7 \times 7$) and contour moment centroid calculation ($cx = M_{10}/M_{00}, cy = M_{01}/M_{00}$) to isolate noteheads.
     - Stem slice pixel sum and flag box evaluation for duration classification (whole, half, quarter, eighth, dotted).
     - Polyphonic chord clustering ($\Delta x \le 0.6 \cdot S_s$) and 16th-note metric grid quantization ($0.25$ beat subdivisions).
   - Zero occurrences of song titles (`piece_`, `Ode`, `Bach`, `Beethoven`) in detection logic.

2. **`scripts/omr_processor.gd`**:
   - Implements native Godot 4 computer vision on `Image` byte buffers:
     - Horizontal projection profiling on `FORMAT_L8` grayscale data.
     - Vertical column projection for barlines spanning non-staff vertical extents.
     - 2D Summed Area Table (Integral Image) over $(W+1) \times (H+1)$ size, providing $O(1)$ box sum evaluations:
       $$\text{box\_sum}(x_1, y_1, x_2, y_2) = \text{SAT}(r_2, c_2) - \text{SAT}(r_1, c_2) - \text{SAT}(r_2, c_1) + \text{SAT}(r_1, c_1)$$
     - Discrete diatonic step scanning across $Y$-levels (`STEP_TO_MIDI` mapping C2 through C6+) with box density thresholding ($\ge 110$).
     - Vertical Non-Maximum Suppression (NMS) to eliminate staff-line bridges between chord notes.
     - Proportional metric beat placement within measures and duration classification based on inner hole box sums, stem presence, flag patches, and dot patches.
   - Zero hardcoded song titles or pre-canned note tables.

3. **`scripts/level_loader.gd`**:
   - Polymorphic level ingestion supporting Dictionaries, JSON files, score images (via `OMRProcessor`), and bundled piece IDs.
   - Pure GDScript RIFF WAV parser (`_load_wav_from_bytes`):
     - Parses 44-byte RIFF header, validates `"RIFF"` and `"WAVE"` magic strings.
     - Traverses `"fmt "` and `"data"` subchunks, extracting sample rate, bit depth, channel count, and slicing PCM data into an `AudioStreamWAV`.
   - Audio-chart alignment: verifies musical duration against audio stream length, converts calibration offsets (ms to sec), and applies levels to `Highway` and `AudioStreamPlayer`.

4. **`tests/test_omr_runner.gd`**:
   - 8 test suites comprising 105 distinct assertions.
   - Each assertion tests real returned data:
     - 45 assertions verifying detected line coordinates against actual image pixel projections (15 assertions per score $\times$ 3 scores).
     - 3 assertions verifying detected barlines (5, 5, 6 barlines).
     - 9 assertions verifying OMR note extraction count and bipartite matching accuracy ($\ge 85\%$).
     - 11 assertions verifying RIFF WAV decoding and stream lengths.
     - 15 assertions verifying JSON schema validation across all 3 charts.
     - 10 assertions verifying calibration offsets and duration boundaries.
     - 6 assertions verifying Highway note loading and AudioPlayer binding.
     - 6 assertions verifying on-the-fly OMR level ingestion into live game nodes.
   - Zero tautological assertions (`assert(true)` or `assert(x == x)`).

5. **`tests/test_omr_harness.py`**:
   - Authentic bipartite matching algorithm (`evaluate_omr_metrics`) comparing detected notes against ground truth annotations:
     - Exact MIDI pitch matching: `pitch_det == pitch_gt`.
     - Temporal onset tolerance: $|t_{\text{det}} - t_{\text{gt}}| \le 0.25\text{ beats}$.
     - Standard information retrieval metrics: True Positives, False Positives, False Negatives, Precision, Recall, and Accuracy.

---

### 1.2 Verbatim Test Execution Outputs

1. **Python OMR CLI Verification Harness**:
   Command: `python tests/test_omr_harness.py --min-accuracy 0.85`
   ```
   ======================================================================
   OMR BUNDLED SUITE SUMMARY
   ----------------------------------------------------------------------
     Piece 1: Monophonic Melody ('Ode to Joy')          : 100.0% (15/15 notes) -> PASSED [OK]
     Piece 2: 2-Part Harmony ('Bach Minuet')            : 100.0% (16/16 notes) -> PASSED [OK]
     Piece 3: Polyphonic Progression ('Cadence Triads') : 100.0% (20/20 notes) -> PASSED [OK]
   ----------------------------------------------------------------------
   OVERALL OMR HARNESS RESULT: ALL PASS [OK]
   ======================================================================
   ```
   Exit code: `0`.

2. **Godot Headless OMR & Level Alignment Runner**:
   Command: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_omr_runner.gd"`
   ```
   ==================================================
    RESULTS: 105 Passed, 0 Failed
   ==================================================
   ALL OMR & LEVEL ALIGNMENT TESTS PASSED [OK]
   ```
   Exit code: `0`.

3. **Godot Headless Scoring Runner**:
   Command: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"`
   ```
   ==================================================
    RESULTS: 91 Passed, 0 Failed
   ==================================================
   ALL SCORING MECHANICS VERIFIED SUCCESSFULLY [OK]
   ```
   Exit code: `0`.

4. **Godot Headless Audio Inference Scoring Runner**:
   Command: `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"`
   ```
   ==================================================
    RESULTS: 63 Passed, 0 Failed
   ==================================================
   ALL INFERENCE & SCORING SUITES PASSED [OK]
   ```
   Exit code: `0`.

5. **Basic Pitch Transcription Harness**:
   Command: `python tests/test_transcription_harness.py --min-f1 0.80`
   ```
   Piece: Monophonic Melody ('Ode to Joy')          : F1-Score: 96.8% -> PASSED [OK]
   Piece: 2-Part Harmony ('Bach Minuet')            : F1-Score: 86.5% -> PASSED [OK]
   Piece: Polyphonic Chordal ('Cadence Triads')     : F1-Score: 88.9% -> PASSED [OK]
   OVERALL HARNESS RESULT: ALL PASS [OK]
   ```
   Exit code: `0`.

6. **End-to-End Test Suite**:
   Command: `python tests/e2e/run_all_e2e_tests.py`
   ```
   Tier 1: Feature Coverage               | 100    | 100    | 0     | 0     | 0.294   
   Tier 2: Boundary & Corner Cases        | 100    | 100    | 0     | 0     | 0.091   
   Tier 3: Cross-Feature Combinations     | 20     | 20     | 0     | 0     | 0.077   
   Tier 4: Real-World Scenarios           | 10     | 10     | 0     | 0     | 0.001   
   TOTAL                                  | 230    | 230    | 0     | 0     | 0.465   
   100% Pass Rate requirement fulfilled. Exit code: 0
   ```
   Exit code: `0`.

---

### 1.3 Adversarial Stress-Test Results

To empirically disprove any possibility of cheating or pre-baked outputs:

1. **Python OMR Image Perturbation**:
   - Synthetically injected a quarter notehead at $X=700, Y=360$ (B4, MIDI 71) with a 70px vertical stem on `piece_1_monophonic/score.png`.
   - Result: `OMREngine.process_score` dynamically detected 16 notes (original 15 + 1 new note).
   - The new note was correctly classified as:
     `{'id': 7, 'pitch_name': 'B4', 'pitch_midi': 71, 'staff': 'treble', 'measure': 2, 'beat': 1.75, 'onset_beat': 5.75, 'duration_beats': 1.0, 'duration_sec': 0.5, 'is_chord': False}`
   - Script: `.agents/teamwork/m4_auditor_1/test_adversarial_omr.py` -> PASSED.

2. **GDScript OMR Image Perturbation**:
   - Synthetically injected a quarter notehead at $X=700, Y=360$ with a 70px vertical stem on `piece_1_monophonic/score.png` in Godot memory.
   - Result: `OMRProcessor.process_image_data` dynamically detected 16 notes (original 15 + 1 new note).
   - The new note was correctly classified as:
     `{ "id": 7, "pitch_name": "B4", "pitch_midi": 71, "staff": "treble", "measure": 2, "beat": 1.75, "onset_beat": 5.75, "time_sec": 2.875, "duration_beats": 1.0, "is_chord": false }`
   - Script: `.agents/teamwork/m4_auditor_1/test_adversarial_gdscript_omr.gd` -> PASSED.

3. **LevelLoader WAV Byte Decoding Robustness**:
   - Synthesized a custom 22050 Hz 8-bit mono WAV buffer in memory and fed it to `LevelLoader._load_wav_from_bytes()`.
   - Result: `AudioStreamWAV` correctly populated with `mix_rate = 22050`, `format = 0 (FORMAT_8_BITS)`, `stereo = false`, `data_size = 100`.
   - Malformed byte buffers were cleanly rejected with `null`.
   - Script: `.agents/teamwork/m4_auditor_1/test_adversarial_wav.gd` -> PASSED.

---

## 2. Logic Chain

1. **Premise**: Under Development mode integrity forensics, a work product must not contain hardcoded test results, facade implementations, fabricated verification outputs, self-certifying tautological tests, or unauthorized execution delegation.
2. **Observation**: Inspection of `python/omr_engine.py` and `scripts/omr_processor.gd` shows pure mathematical and morphological computer vision algorithms operating on pixel buffers. Neither file contains test piece names or hardcoded note coordinates.
3. **Adversarial Verification**: Modifying score image pixels directly alters the detected note lists in both Python and GDScript engines, precisely extracting the newly drawn note's pitch and duration. This proves detection is governed by pixel geometry rather than lookup tables.
4. **Behavioral Integrity**: `scripts/level_loader.gd` accurately decodes raw RIFF WAV byte streams and performs real-time audio-chart temporal alignment.
5. **Test Authenticity**: All 105 assertions in `tests/test_omr_runner.gd` evaluate genuine functional components and dynamic data rather than tautological constants.
6. **Zero Regressions**: All 230 E2E tests, scoring tests (91/91), inference tests (63/63), transcription tests (F1 >= 86.5%), and OMR harness tests (100.0%) pass with exit code 0.
7. **Conclusion**: The Milestone 4 deliverables are genuine, robust, and clean of integrity violations.

---

## 3. Caveats

- **Digital Score Precision**: The OMR pipeline is calibrated for clean digital sheet music with standard line spacing ($S_s \approx 20\text{px}$) and upright orientation. Distorted or angled camera photos would require a pre-processing deskew filter.
- **Accidental Support**: Current bundled pieces are in C Major. Sheet music featuring non-zero key signatures or sharp/flat accidentals will require accidental glyph classification to shift the diatonic pitch mappings.

---

## 4. Conclusion

Milestone 4 (On-Device OMR & Level Alignment) satisfies all requirements and integrity constraints.
- Computer vision engines (Python & GDScript) are authentic, non-facade, and non-hardcoded.
- Audio decoding and temporal alignment operate with authentic mathematical precision.
- Test suites are authentic, non-tautological, and comprehensively pass.
- **Final Verdict: CLEAN.**

---

## 5. Verification Method

To independently re-verify the auditor's findings:

1. **Run Python OMR Verification Harness**:
   ```powershell
   python tests/test_omr_harness.py --min-accuracy 0.85
   ```
2. **Run Godot Headless OMR Runner**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_omr_runner.gd"
   ```
3. **Run Auditor Python Adversarial Test**:
   ```powershell
   python .agents/teamwork/m4_auditor_1/test_adversarial_omr.py
   ```
4. **Run Auditor GDScript Adversarial Test**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://.agents/teamwork/m4_auditor_1/test_adversarial_gdscript_omr.gd"
   ```
5. **Run Auditor WAV Decoder Adversarial Test**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://.agents/teamwork/m4_auditor_1/test_adversarial_wav.gd"
   ```
