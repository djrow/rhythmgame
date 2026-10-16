# Milestone 3 Challenger Adversarial Report

**Agent**: `m3_challenger_1`  
**Milestone**: Milestone 3 — Basic Pitch ONNX & Audio Inference  
**Date**: 2026-10-16  
**Verdict**: **REQUEST_CHANGES**  
**Assigned Artifacts Under Stress**: `python/basic_pitch_onnx.py`, `tests/test_transcription_harness.py`  

---

## 1. Observation

### 1.1 Baseline Harness & Test Execution
The baseline harnesses reported in the worker handoff were verified:
1. `python tests/test_transcription_harness.py --min-f1 0.80`: Exited with code `0`, reporting Ode to Joy F1 93.3%, Bach Minuet F1 82.4%, Cadence Triads F1 80.0%.
2. Godot headless test runner `tests/test_inference_scoring_runner.gd`: Exited with code `0`, 63 passed, 0 failed.
3. E2E test runner `tests/e2e/run_all_e2e_tests.py`: Exited with code `0`, 230 passed.

### 1.2 Extreme Signal Fuzzing & Polyphony Stress (New Suite: `tests/test_adversarial_m3.py`)
An adversarial stress harness was created at `tests/test_adversarial_m3.py` comprising 21 rigorous tests across four test classes:
- **Digital silence (0.0 amplitude)**: Both streaming chunk processing and offline transcription return 0 active pitches and 0 onsets (`test_pure_digital_silence`: PASSED).
- **0 dBFS clipped square wave**: Tested across 110 Hz, 440 Hz, 1000 Hz, and 4000 Hz. Confirmed finite output values in `[0.0, 1.0]`, no NaNs, no Infs (`test_clipped_square_wave_0dbfs`: PASSED).
- **Nyquist limit alternating sequence**: $+1, -1$ alternating at $f_s/2 = 11,025$ Hz produced valid outputs without arithmetic overflow (`test_nyquist_alternating_signal`: PASSED).
- **Gaussian white noise**: White noise at $-20$ dBFS ($0.1$ standard deviation) triggered $<5$ spurious notes. Loud noise ($0.5$ standard deviation clipped to $[-1, 1]$) yielded finite confidences without crashing (`test_gaussian_white_noise_rejection`: PASSED).
- **Infrasonic & Ultrasonic rejection**: $10$ Hz sine wave produced 0 notes. $10,500$ Hz near-Nyquist tone produced 0 notes within the $A0..C8$ piano pitch range (`test_infrasonic_and_ultrasonic_rejection`: PASSED).
- **Transient clicks & Dirac impulses**: 5 single-sample impulses spaced across 2 seconds were successfully rejected by the $6$-frame minimum note length filter (`test_micro_burst_transient_clicks`: PASSED).
- **Harmonic suppression**: Pure A4 (440 Hz, MIDI 69) detected pitch 69 and suppressed octave harmonics 81, 88, 93 (`test_monophonic_pure_sine_harmonic_suppression`: PASSED). Complex tone with fundamental C4 (60) + 2nd harmonic C5 (72) + 3rd harmonic G5 (79) correctly identified C4 and suppressed harmonics 72 and 79 (`test_harmonic_complex_tone_suppression`: PASSED).
- **Real-time streaming polyphonic triad**: Sliding ring buffer receiving C Major triad chunks (60, 64, 67) concurrently detected all three active pitches and onsets (`test_streaming_polyphonic_triad_detection`: PASSED).

### 1.3 Discovered Vulnerability 1: Sub-Hop Buffer Crash in `infer_onsets_numpy`
**Target File**: `python/basic_pitch_onnx.py`, lines 73 and 283–289.  
When an audio array shorter than 256 samples (less than 1 FFT hop size = 11.6ms at 22,050 Hz, including empty array `len(audio) == 0`) is supplied to `transcribe_file`:
```python
283: n_output_frames = int(np.floor(audio_len * (FPS / AUDIO_SAMPLE_RATE)))
284: unwrapped_onsets = unwrapped_onsets[:n_output_frames, :]
285: unwrapped_notes = unwrapped_notes[:n_output_frames, :]
...
289: onsets = infer_onsets_numpy(unwrapped_onsets, frames)
```
Since `audio_len < 256`, `n_output_frames` evaluates to `0`. `frames` and `unwrapped_onsets` have shape `(0, 88)`.
In `infer_onsets_numpy` at line 73:
```python
73: max_diff = np.max(frame_diff)
```
`frame_diff` is an empty matrix of shape `(0, 88)`.
**Verbatim Crash Output**:
```
ValueError: zero-size array to reduction operation maximum which has no identity
```
Empirically tested for lengths `[0, 1, 2, 10, 50, 100, 255]`: all 7 crashed with `ValueError`. Only lengths $\ge 256$ survived.

### 1.4 Discovered Vulnerability 2: 100% Systematic Loss of Notes Starting at $t = 0.0$ in `transcribe_file`
**Target File**: `python/basic_pitch_onnx.py`, lines 55–62, 245–254, 279–285.  
When inspecting note-level errors across the bundled test pieces:
```powershell
python -c "
import json
from python.basic_pitch_onnx import BasicPitchOnnxRunner
from tests.test_transcription_harness import evaluate_note_metrics

runner = BasicPitchOnnxRunner('assets/models/nmp.onnx')
for piece, wav, chart_file in [
    ('Ode to Joy', 'ode_to_joy.wav', 'ode_to_joy.json'),
    ('Bach Minuet', 'bach_minuet.wav', 'bach_minuet.json'),
    ('Cadence Triads', 'cadence_triads.wav', 'cadence_triads.json')
]:
    with open('assets/charts/' + chart_file) as f:
        chart = json.load(f)
    gt = chart['notes']
    detected = runner.transcribe_file('assets/audio/' + wav)
    metrics = evaluate_note_metrics(detected, gt)
    f1_pct = metrics['f1'] * 100
    t0_notes = [g for g in gt if g['time_sec'] == 0.0]
    matched_t0 = [g for g in t0_notes if any(abs(d['pitch'] - g['pitch_midi']) == 0 and abs(d['onset_sec'] - g['time_sec']) <= 0.15 for d in detected)]
    t0_names = [n['pitch_name'] for n in t0_notes]
    print(piece + ':')
    print('  F1 Score       : ' + str(round(f1_pct, 1)) + '%')
    print('  Total GT Notes : ' + str(len(gt)))
    print('  t=0.0 GT Notes : ' + str(len(t0_notes)) + ' ' + str(t0_names))
    print('  t=0.0 Matched  : ' + str(len(matched_t0)))
    print('  False Negatives: ' + str(metrics['fn']))
"
```
**Verbatim Output**:
```
Ode to Joy:
  F1 Score       : 93.3%
  Total GT Notes : 15
  t=0.0 GT Notes : 1 ['E4']
  t=0.0 Matched  : 0
  False Negatives: 1
Bach Minuet:
  F1 Score       : 82.4%
  Total GT Notes : 16
  t=0.0 GT Notes : 2 ['G4', 'C3']
  t=0.0 Matched  : 0
  False Negatives: 2
Cadence Triads:
  F1 Score       : 80.0%
  Total GT Notes : 20
  t=0.0 GT Notes : 4 ['C3', 'G3', 'C4', 'E4']
  t=0.0 Matched  : 0
  False Negatives: 4
```
**100% of all False Negatives across all three pieces were exclusively notes starting at $t = 0.0$**:
- In `ode_to_joy.wav`: 1 GT note at $t=0.0$ (`E4`); 0 matched; 1 FN.
- In `bach_minuet.wav`: 2 GT notes at $t=0.0$ (`G4`, `C3`); 0 matched; 2 FN.
- In `cadence_triads.wav`: 4 GT notes at $t=0.0$ (`C3`, `G3`, `C4`, `E4`); 0 matched; 4 FN. The ENTIRE first chord was dropped.

---

## 2. Logic Chain

1. **Root Cause of Crash on Small Audio Arrays (Observation §1.3)**:
   - Line 283 computes `n_output_frames = int(np.floor(audio_len * (FPS / AUDIO_SAMPLE_RATE)))`.
   - Because `AUDIO_SAMPLE_RATE / FPS = 256` (the FFT hop size), any audio with fewer than 256 samples yields `n_output_frames = 0`.
   - The runner does not short-circuit when `audio_len < FFT_HOP`.
   - Slicing `unwrapped_onsets[:0, :]` creates an empty $(0, 88)$ array.
   - Calling `np.max(frame_diff)` in `infer_onsets_numpy` (line 73) on a 0-element array triggers a `ValueError`, crashing the caller ungracefully.

2. **Root Cause of $t = 0.0$ Onset Truncation (Observation §1.4)**:
   - In lines 247–248, `extra_pad_frames = 30` ($7,680$ samples) is prepended to the audio.
   - For an onset occurring at $t = 0.0$, the convolutional receptive field of Basic Pitch's harmonic dilated convolutions produces an onset activation peak centered at frame 28 or 29.
   - In lines 280–281, the unwrapped output is sliced via `unwrapped_onsets = unwrapped_onsets[extra_pad_frames:]` (skipping the first 30 frames).
   - This slice discards frame 29 (the true local maximum), leaving frame 30 (now frame 0) on a downward slope ($0.698 \rightarrow 0.494$).
   - In lines 55–61, `argrelmax_axis0` defines relative maxima strictly for interior frames:
     ```python
     peaks[1:-1] = (mat[1:-1] > mat[:-2]) & (mat[1:-1] >= mat[2:])
     ```
     Index 0 is never evaluated and is unconditionally set to `False`.
   - Because index 0 is not evaluated, and frame 29 was sliced off, no relative maximum is registered for the note onset.
   - Furthermore, the reference Spotify implementation includes a fallback `melodia_trick` in `basic_pitch.note_creation.output_to_notes_polyphonic` that recovers note events from sustained energy when onset peaks are absent. This was omitted from `basic_pitch_onnx.py`.
   - Consequently, **any audio note that starts at the downbeat ($t = 0.0$) is systematically invisible to `transcribe_file`**.

3. **Impact on Cadence Triads & Acceptance Threshold**:
   - `cadence_triads.json` contains 5 chords $\times$ 4 notes = 20 notes.
   - Because the first chord at $t=0.0$ was completely dropped (4 notes missed), and 4 octave harmonic false positives occurred, the piece achieved $TP=16, FP=4, FN=4 \rightarrow \text{F1} = 80.0\%$.
   - The test passed the $\ge 80.0\%$ bar by exactly $0.0\%$. Running `python tests/test_transcription_harness.py --min-f1 0.81` immediately fails.
   - Any user-imported sheet music or WAV file starting at beat 1 will drop the opening notes or chord.

---

## 3. Caveats

- **Streaming mode is unaffected by Bug 2**: As demonstrated in `test_streaming_polyphonic_triad_detection`, real-time sliding ring buffer streaming inspects frames 158..167 using `max(axis=0)` rather than `argrelmax_axis0`. Streaming microphone input successfully detects chords at any start time.
- **Audio delayed by $\ge 150$ms is unaffected by Bug 2**: When audio has lead silence $\ge 0.15$s, all notes (including C Major triad 60, 64, 67) are correctly detected with high precision.
- **No modification made to source code**: In accordance with the Challenger role constraints, no changes were applied to `python/basic_pitch_onnx.py` or `tests/test_transcription_harness.py`. All issues were demonstrated and verified strictly via external tests and scripts.

---

## 4. Conclusion

**Verdict: REQUEST_CHANGES**

While the pure NumPy + ONNX implementation demonstrates impressive DSP architecture, low latency (<11ms), and robust harmonic suppression against white noise, clipping, and out-of-band signals, it suffers from two critical defects that must be remediated:
1. **Critical Crash**: Unhandled `ValueError` when `transcribe_file` receives audio buffers under 256 samples.
2. **Critical Functional Defect**: Systematic 100% loss of notes starting at $t = 0.0$ in `transcribe_file`, which causes 100% of all false negatives across the bundled test pieces and leaves Cadence Triads scraping the acceptance threshold with 0.0% safety margin.

### Recommended Action Items for Worker:
1. In `python/basic_pitch_onnx.py::transcribe_file`:
   - Add an early return guard: `if len(audio) < FFT_HOP: return []`.
   - In `infer_onsets_numpy`: Guard `if frames.shape[0] == 0: return onsets` and `if frame_diff.size == 0 or max_diff == 0: return onsets`.
2. In `python/basic_pitch_onnx.py`:
   - Adjust pre-roll padding alignment and boundary peak picking so onsets occurring at $t=0.0$ are detected.
   - Allow `argrelmax_axis0` to evaluate boundary index 0 (e.g. `peaks[0] = (mat[0] >= mat[1])`), or retain pre-roll context so the onset peak at frame 28-29 is captured and mapped to $t \ge 0.0$.
   - Optionally implement the `melodia_trick` fallback from Spotify Basic Pitch to recover sustained notes at song boundaries.
3. Re-run `python tests/test_transcription_harness.py --min-f1 0.85` and `python tests/test_adversarial_m3.py` to confirm that all notes at $t=0.0$ are detected and Cadence Triads achieves $\ge 90\%$ F1-score.

---

## 5. Verification Method

To independently verify these findings, run the following commands from the project root `c:\Users\david\Documents\micgame-3`:

1. **Run the Full Adversarial Stress Test Suite**:
   ```powershell
   python tests/test_adversarial_m3.py -v
   ```
   *Expected outcome*: 21 tests pass, confirming extreme audio robustness and reproducing the bug conditions in dedicated tests `test_bug1_short_audio_buffer_crash_reproduction` and `test_bug2_t0_onset_truncation_reproduction`.

2. **Verify Bug 1 (Sub-Hop Array Crash)**:
   ```powershell
   python -c "import numpy as np; from python.basic_pitch_onnx import BasicPitchOnnxRunner; r = BasicPitchOnnxRunner('assets/models/nmp.onnx'); r.transcribe_file(np.array([], dtype=np.float32))"
   ```
   *Expected outcome*: Crashes with `ValueError: zero-size array to reduction operation maximum which has no identity`.

3. **Verify Bug 2 (Systematic 100% Loss of $t=0.0$ Notes Across Bundled Test Pieces)**:
   ```powershell
   python -c "import json; from python.basic_pitch_onnx import BasicPitchOnnxRunner; from tests.test_transcription_harness import evaluate_note_metrics; r = BasicPitchOnnxRunner('assets/models/nmp.onnx'); c = json.load(open('assets/charts/cadence_triads.json')); d = r.transcribe_file('assets/audio/cadence_triads.wav'); print('Notes at t=0 matched:', sum(any(abs(x['pitch']-g['pitch_midi'])==0 and abs(x['onset_sec']-g['time_sec'])<=0.15 for x in d) for g in c['notes'] if g['time_sec']==0.0))"
   ```
   *Expected outcome*: Prints `Notes at t=0 matched: 0` (0 out of 4 notes matched at $t=0.0$).
