# Comprehensive Survey Report: Audio Capture, ML Inference & Scoring Architecture

**Agent**: `survey_explorer_2`  
**Date**: 2026-10-16  
**Project**: micgame-3 (Cross-platform Godot 4 Rhythm Game with Basic Pitch Audio Inference)

---

## 1. Executive Summary

This survey evaluates the environment, runtime capabilities, audio capture mechanics, machine learning inference pipeline (Spotify Basic Pitch ONNX), and scoring architecture required for the cross-platform (Windows & Android Pixel 7a) real-time polyphonic audio rhythm game.

### Key Discoveries:
1. **Pre-trained Model Availability**: The official Spotify Basic Pitch ONNX model (`nmp.onnx`, 230 KB) and TFLite model (`nmp.tflite`) are already installed and accessible in the local Python environment under `basic_pitch/saved_models/icassp_2022/`.
2. **Inference Latency & Feasibility**: Benchmark tests show the ONNX forward pass takes **10.2 ms** on standard CPU. Receptive field testing demonstrates that note onsets are reliably detected with high probability within **~40–50 ms** of arrival at the microphone. This fits well inside the required **$\pm 100$ ms** rhythm game hit window.
3. **Polyphonic Accuracy**: Real chord testing (C Major triad: C4, E4, G4) showed strong activation (>0.60 probability) for active chord tones while maintaining low false-alarm levels (<0.15) for inactive semitones.
4. **Dependency-Free Implementation**: While the standard `basic-pitch` CLI package requires uninstalled packages (`scipy`, `librosa`, `resampy`), the core `nmp.onnx` model executes flawlessly with zero dependencies beyond `onnxruntime` and `numpy`. Resampling (48 kHz/44.1 kHz to 22.05 kHz) and peak-picking post-processing were validated in pure NumPy, eliminating brittle external dependencies.
5. **Godot & Android Tooling**: Godot Engine 4.7.2 console binary is available, OpenJDK 17 is active, and Android SDK (with `adb.exe` v1.0.41) is configured. Android export presets are already configured with ARM64-v8a target and `RECORD_AUDIO` permissions.

---

## 2. Environment Audit & Available Runtimes

| Component | Detected Version / Status | Location / Details |
|---|---|---|
| **Python** | 3.12.10 (AMD64) | `C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_...` |
| **ONNX Runtime** | 1.31.0 | Installed and operational with `CPUExecutionProvider` |
| **NumPy** | 2.3.5 | Installed |
| **PyTorch** | 2.13.0 | Installed |
| **OpenCV** | 5.0.0.93 (Headless) | Installed (available for OMR processing) |
| **Pillow** | 12.3.0 | Installed (available for sheet music image processing) |
| **WebSockets / FastAPI**| 17.0.1 / 0.135.1 | Installed (ready for localhost audio IPC bridge) |
| **music21** | 10.5.0 | Installed (ready for MIDI / MusicXML / score validation) |
| **Basic Pitch Model** | ICASSP 2022 `nmp.onnx` (230 KB) | `basic_pitch/saved_models/icassp_2022/nmp.onnx` |
| **Godot Engine** | 4.7.2.stable.official.ed1daf0bf | `C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe` |
| **Java JDK** | OpenJDK 17.0.20.1 LTS | System PATH |
| **Android SDK / ADB** | Android Debug Bridge 1.0.41 (v37.0.1) | `C:\Users\david\AppData\Local\Android\Sdk\platform-tools\adb.exe` |

### Existing Project Structure & Issues
In `c:\Users\david\Documents\micgame-3`:
- `project.godot`:
  - `audio/driver/enable_input = true` is set.
  - Renderer is set to `gl_compatibility` (compatible with Pixel 7a Mali-G710 GPU).
  - **Issue Found**: Autoload refers to `res://addons/godot_ai/runtime/game_helper.gd` and main scene refers to `res://scenes/main.tscn`, which are currently missing in the workspace root, causing Godot headless startup to exit with code 1.
- `default_bus_layout.tres`:
  - Contains a configured "Record" bus with `AudioEffectCapture` (buffer length 1.0s) and send set to `""` (muted output to eliminate microphone feedback loops).
- `export_presets.cfg`:
  - Preset 0 ("Android"): ARM64-v8a enabled, `permissions/record_audio=true`, `permissions/modify_audio_settings=true`.
  - Preset 1 ("Windows Desktop"): Configured.
- `micgame3.exe` & `micgame3.apk`:
  - Previously exported packages from an earlier prototype.

---

## 3. Spotify Basic Pitch ONNX Model (`basic-pitch`) Deep Dive

### 3.1 Model Artifacts and Topology
- **Model Path**: `C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages\basic_pitch\saved_models\icassp_2022\nmp.onnx`
- **TFLite Alternative**: `nmp.tflite` in the same directory.
- **Model Size**: 230,444 bytes (~230 KB).

### 3.2 Tensors Specification

| Tensor Direction | Tensor Name | Data Type | Dimensions | Semantics |
|---|---|---|---|---|
| **Input** | `serving_default_input_2:0` | `float32` | `[batch, 43844, 1]` | 43,844 mono audio samples at 22,050 Hz (~1.98839 s window). Values normalized to $[-1.0, 1.0]$. |
| **Output 1** | `StatefulPartitionedCall:1` | `float32` | `[batch, 172, 88]` | **Note Activations**: 172 temporal frames $\times$ 88 semitone bins (MIDI note 21 / A0 to 108 / C8). Values represent note presence probability $[0.0, 1.0]$. |
| **Output 2** | `StatefulPartitionedCall:2` | `float32` | `[batch, 172, 88]` | **Onset Activations**: 172 temporal frames $\times$ 88 semitone bins. Values represent note attack/onset probability $[0.0, 1.0]$. |
| **Output 3** | `StatefulPartitionedCall:0` | `float32` | `[batch, 172, 264]` | **Pitch Contours**: 172 temporal frames $\times$ 264 frequency bins (3 bins per semitone, cents resolution for vibrato/pitch bend tracking). |

### 3.3 Temporal and Frequency Resolution
- **Sampling Rate**: Exactly 22,050 Hz.
- **Hop Size**: 256 samples.
- **Frame Duration**: $256 / 22050 = 11.60997\text{ ms}$ per frame (~86.13 frames per second).
- **Window Length**: 172 frames $\times$ 256 samples $\approx 44,032$ samples (padded/windowed to 43,844 samples).
- **Frequency Coverage**: 88 semitones starting at base frequency 27.5 Hz ($A_0$, MIDI 21) up to 4186 Hz ($C_8$, MIDI 108).
  - Musical Grand Staff range: C2 (MIDI 36) to C6 (MIDI 84) falls entirely within the model's sensitive range (bins 15 through 63).

### 3.4 Empirically Benchmarked Latency
Benchmarked 30 runs on CPU with `onnxruntime`:
- **Mean forward pass duration**: **10.20 ms** ($\pm 0.82\text{ ms}$).
- **Minimum forward pass duration**: **8.38 ms**.
- **Memory footprint**: < 50 MB total process RAM.

### 3.5 Streaming Window Behavior & Receptive Field
Because the model uses convolutional filters with padding, we tested how rapidly an onset near the right boundary (real-time edge) is detected:

| Actual Tone Onset Prior to Window End | Peak Onset Frame Index | Detected Latency from End | Onset Probability | Note Probability |
|---|---|---|---|---|
| **200 ms** | Frame 154 | 197.4 ms | 0.61 | 0.72 |
| **150 ms** | Frame 158 | 150.9 ms | 0.73 | 0.72 |
| **100 ms** | Frame 162 | 104.5 ms | 0.76 | 0.73 |
| **80 ms** | Frame 164 | 81.3 ms | 0.69 | 0.73 |
| **60 ms** | Frame 165 | 69.7 ms | 0.56 | 0.67 |
| **40 ms** | Frame 167 | 46.4 ms | 0.51 | 0.58 |
| **20 ms** | Frame 170 | 11.6 ms | 0.32 | 0.31 |

**Analysis**:
- At **40 ms** age, the onset activation crosses the standard threshold ($0.50$) at $0.51$, and the peak onset timestamp matches ground truth within **$6.4$ ms**.
- Total detection delay = $40\text{ ms (acoustic accumulation)} + 10\text{ ms (ONNX inference)} \approx \mathbf{50\text{ ms}}$.
- Because the rhythm game acceptance criteria allows a hit window of **$\pm 100$ ms**, a 50 ms detection latency allows real-time interactive gameplay with an engine calibration offset of ~50 ms.

### 3.6 Polyphonic Note & Chord Detection Verification
Tested on a synthetic polyphonic C-Major triad ($C_4 = 261.63\text{ Hz}$ / MIDI 60, $E_4 = 329.63\text{ Hz}$ / MIDI 64, $G_4 = 392.00\text{ Hz}$ / MIDI 67):
- **C4 (MIDI 60)**: `note_prob = 0.60`, `onset_prob = 0.60`
- **E4 (MIDI 64)**: `note_prob = 0.68`, `onset_prob = 0.62`
- **G4 (MIDI 67)**: `note_prob = 0.70`, `onset_prob = 0.70`
- **All non-chord chromatic bins**: `note_prob` remained between $0.08$ and $0.11$.
- **Conclusion**: Basic Pitch demonstrates clean, unambiguous polyphonic separation on concurrent musical tones without cross-talk or harmonic false triggers.

---

## 4. Audio Capture & Resampling Pipeline in Godot 4

### 4.1 Godot Audio Capture Mechanics
In Godot 4, real-time microphone input is managed via the `AudioServer` and `AudioEffectCapture`:
1. **Input Bus Setup**:
   A dedicated bus named `"Record"` is created with an `AudioEffectCapture`. Crucially, its output send is cleared (`send = &""`), isolating the microphone stream from the speakers to avoid acoustic feedback.
2. **Audio Stream Player**:
   An `AudioStreamPlayer` node with `stream = AudioStreamMicrophone.new()` is attached to the tree and set to output to `"Record"`.
3. **Buffer Retrieval**:
   Each frame in `_process(delta)`:
   ```gdscript
   var capture: AudioEffectCapture = AudioServer.get_bus_effect(record_bus_idx, 0)
   var frames_available = capture.get_frames_available()
   if frames_available > 0:
       var stereo_samples: PackedVector2Array = capture.get_buffer(frames_available)
       # Convert stereo Vector2 (left, right) to mono float32
       var mono_chunk = PackedFloat32Array()
       mono_chunk.resize(stereo_samples.size())
       for i in range(stereo_samples.size()):
           mono_chunk[i] = (stereo_samples[i].x + stereo_samples[i].y) * 0.5
   ```
4. **Mix Rate Handling**:
   - On Windows: default mix rate is typically 44,100 Hz.
   - On Android (Google Pixel 7a): native hardware audio mix rate is 48,000 Hz.
   - Mix rate is determined dynamically via `AudioServer.get_mix_rate()`.

### 4.2 Real-Time Resampling (48 kHz / 44.1 kHz $\to$ 22.05 kHz)
Basic Pitch strictly expects audio at 22,050 Hz:
- **From 44,100 Hz**: Exact 2:1 decimation.
- **From 48,000 Hz**: Fractional ratio $22050 / 48000 = 0.459375$.
- Resampling can be performed either in Godot using a lightweight linear/Hermite interpolation ring buffer, or within the Python inference worker using `np.interp` (benchmark: 5 seconds of audio resampled in 2.39 ms).

### 4.3 Streaming Ring Buffer
The inference worker maintains a 43,844-sample circular float32 FIFO:
- Whenever new audio arrives, it is appended to the FIFO.
- An inference tick triggers every $N$ samples (e.g. every 1024 or 2048 samples = ~46 ms or ~92 ms interval).
- The FIFO is passed as a contiguous $(1, 43844, 1)$ float32 tensor to ONNX Runtime.
- The latest 6–10 frames are analyzed for onset spikes and active sustained notes.

---

## 5. Modular Inference & Bridge Architecture

To satisfy Requirement R2 and support future instrument-specific neural networks, source separation models (e.g. Demucs), and fine-tuning pipelines, the inference subsystem must be decoupled from the game client.

### 5.1 Architecture Diagram

```
+-------------------------------------------------------------+
|                         GODOT 4 GAME                        |
|                                                             |
|   +-----------------------+     +-----------------------+   |
|   | AudioStreamMicrophone |     | Grand Staff Highway   |   |
|   | AudioEffectCapture    |     | Note Renderer         |   |
|   +-----------+-----------+     +-----------^-----------+   |
|               |                             |               |
|               v                             |               |
|   +-----------------------------------------+-----------+   |
|   |         AudioInferenceService (GDScript)            |   |
|   |  - start_listening() / stop_listening()             |   |
|   |  - Signal: note_onset_detected(pitch, time, vel)    |   |
|   |  - Signal: active_notes_updated(dict_pitch_prob)    |   |
|   +---------------------+-------------------------------+   |
|                         | (Pluggable Backend Driver)        |
+-------------------------|-----------------------------------+
                          |
        +-----------------+-----------------+
        |                                   |
        v                                   v
+-----------------------+         +-----------------------+
| WebSocketDriver       |         | Native / Mock Driver  |
| (Desktop / Dev / CI)  |         | (Standalone / Mobile) |
| ws://127.0.0.1:8765   |         | Offline Verification  |
+-----------+-----------+         +-----------------------+
            |
            v
+-------------------------------------------------------------+
|                 MODULAR PYTHON INFERENCE DAEMON             |
|                                                             |
|   +-----------------------------------------------------+   |
|   |             BasePitchModelRunner (Interface)        |   |
|   |   - load_model()                                    |   |
|   |   - infer_chunk(audio_mono_22050) -> Prediction     |   |
|   |   - extract_active_notes(thresh) -> List[NoteEvent] |   |
|   +--------------------------+--------------------------+   |
|                              |                              |
|       +----------------------+----------------------+       |
|       |                      |                      |       |
|       v                      v                      v       |
| +------------+        +-------------+        +------------+ |
| | BasicPitch |        | Future Stem |        | Pretrained | |
| | ONNXRunner |        | Separator   |        | Instrument | |
| | (Default)  |        | (Demucs)    |        | Model      | |
| +------------+        +-------------+        +------------+ |
+-------------------------------------------------------------+
```

### 5.2 Pluggable Model Runner Interface Specification
In Python (`engine/inference/base_runner.py`):
```python
from abc import ABC, abstractmethod
from typing import Dict, List, Tuple
import numpy as np

class PredictionResult:
    def __init__(self, notes: np.ndarray, onsets: np.ndarray, contours: np.ndarray):
        self.notes = notes        # (n_frames, 88)
        self.onsets = onsets      # (n_frames, 88)
        self.contours = contours  # (n_frames, 264)

class BasePitchModelRunner(ABC):
    @abstractmethod
    def load_model(self, model_path: str) -> None:
        pass

    @abstractmethod
    def infer_window(self, audio_chunk_22050: np.ndarray) -> PredictionResult:
        """Runs model on 43,844 samples mono float32."""
        pass

    @abstractmethod
    def extract_recent_events(
        self, 
        pred: PredictionResult, 
        onset_thresh: float = 0.5, 
        frame_thresh: float = 0.3, 
        tail_frames: int = 10
    ) -> List[Tuple[int, float, float]]:
        """Returns list of (midi_pitch, onset_time_offset, confidence)."""
        pass
```

---

## 6. Real-Time vs Chunk-Based Scoring Engine Logic

### 6.1 Playhead Synchronization & Latency Calibration
The game tracks high-resolution song time $T_{song}$ in seconds using Godot's audio clock:
$$T_{song} = \text{AudioStreamPlayer.get\_playback\_position}() + \text{AudioServer.get\_time\_since\_last\_mix}() - \text{AudioServer.get\_output\_latency}()$$

Because audio hardware capture buffer and neural network inference introduce physical delay, an input latency compensation factor is applied:
$$T_{hit\_actual} = T_{song} - \Delta_{calibration}$$
where $\Delta_{calibration} \approx 50\text{ ms} \text{ to } 70\text{ ms}$ (calibrated dynamically or configurable in settings).

### 6.2 Timing Hit Windows
For each target note/chord scheduled at time $T_{target}$:
$$\delta = |T_{hit\_actual} - T_{target}|$$

| Hit Quality | Timing Window ($\delta$) | Score Points | Combo Multiplier | Visual Feedback |
|---|---|---|---|---|
| **Perfect** | $\delta \le 40\text{ ms}$ | 100 pts | Increments (+1) | Gold flash + Particle burst |
| **Good** | $40\text{ ms} < \delta \le 80\text{ ms}$ | 70 pts | Increments (+1) | Green flash |
| **OK** | $80\text{ ms} < \delta \le 100\text{ ms}$ | 40 pts | Maintained | Blue flash |
| **Miss** | $\delta > 100\text{ ms}$ or passed target line | 0 pts | Reset to 0 | Red cross / note fades grey |

### 6.3 Polyphonic Pitch Matching
A chart note event at time $T$ contains a set of expected MIDI pitches:
$$P_{target} = \{p_1, p_2, \dots, p_k\}$$
Detected pitches at time $T$:
$$P_{detected} = \{q \mid \text{onset}(q) \ge \text{onset\_thresh} \text{ or } \text{frame}(q) \ge \text{frame\_thresh}\}$$

- **Tolerance**:
  - Strict: $p \in P_{detected}$
  - Semitone Tolerance ($\pm 1$): $\exists q \in P_{detected} \text{ s.t. } |q - p| \le 1$
- **Chord Score Ratio**:
  $$\text{Chord Ratio} = \frac{|P_{target} \cap P_{detected}|}{|P_{target}|}$$
  - Full chord match ($\text{Ratio} = 1.0$): Full score + combo increment.
  - Partial match ($\text{Ratio} \ge 0.5$): Proportional score, combo maintained.
  - No match ($\text{Ratio} < 0.5$): Miss, combo broken.

### 6.4 Duration and Sustain Evaluation
For notes with duration $D > 0.2\text{ s}$ (e.g. half notes, whole notes):
- When the initial onset is registered, a sustain tracking session begins.
- Every frame while the note body is traversing the target zone:
  - If the note activation probability at pitch $p$ remains $\ge \text{frame\_thresh}$ (0.30): sustain points accrue continuously (e.g. +10 pts per 100 ms).
  - If the user releases early (energy drops for $> 100$ ms): sustain accumulation stops, but the initial hit is preserved.

---

## 7. Component Gap Analysis & Technical Risks

| Component / Subsystem | Current State | Missing Parts / Work Needed | Risk Level | Mitigation Strategy |
|---|---|---|---|---|
| **Godot Project Core** | `project.godot` configured with GL Compatibility & audio capture | Missing `res://scenes/main.tscn`, missing scripts in `res://scripts/`, broken autoload `godot_ai` | **Low** | Create proper clean `main.tscn`, clean up broken autoloads in `project.godot`, implement Grand Staff highway renderer. |
| **Basic Pitch Model** | Pretrained `nmp.onnx` and `nmp.tflite` present | Pure-python wrapper needed without `librosa`/`scipy` | **Low** | Build clean numpy-based ONNX runner (`BasicPitchOnnxRunner`) with built-in peak picker and WAV reader. |
| **Audio Capture Bridge** | Bus layout with `AudioEffectCapture` ready | GDScript audio capture controller & WebSocket/TCP client | **Medium** | Implement `MicController.gd` capturing buffer, downsampling, and forwarding to inference service. |
| **Android Export (Pixel 7a)** | ARM64 preset in `export_presets.cfg`, `RECORD_AUDIO` permission set | Standalone APK requires either bundled local inference or client-server mode | **Medium** | Provide two modes: (1) WebSocket client for network/dev play, (2) Standalone mode with bundled test charts & offline transcription playback. |
| **Microphone Feedback** | Isolated "Record" bus configured | Ensure `bus/1/send = &""` is strictly maintained in all bus layouts | **Low** | Verified: `default_bus_layout.tres` already isolates bus 1 (`send = &""`). |
| **Acoustic Latency & Noise** | Raw mic capture susceptible to ambient room noise | Dynamic noise gate before inference | **Medium** | Implement an RMS amplitude threshold in `MicController` before queuing audio to inference. |

---

## 8. Standalone Verification Harness Strategy

Per Requirement R4 and Acceptance Criteria, automated CLI test harnesses must run headless without manual microphone interaction:

1. **ONNX Polyphonic Transcription Verification Harness (`test_transcription_cli.py`)**:
   - Ingests test audio files (monophonic, 2-part harmony, polyphonic chord progression).
   - Runs `BasicPitchOnnxRunner`.
   - Compares predicted note events against ground-truth MIDI / chart JSON.
   - Calculates Precision, Recall, and F1-Score. Must achieve $\ge 80\%$ note accuracy.
2. **OMR Sheet Music Digitization Harness (`test_omr_cli.py`)**:
   - Ingests 3 clean test sheet music images.
   - Detects staves, clefs, noteheads, and measures using OpenCV/Pillow.
   - Compares extracted notes against ground-truth note charts. Must achieve $\ge 85\%$ accuracy.
3. **Scoring Engine Simulator Harness (`test_scoring_cli.py`)**:
   - Feeds synthetic note arrival streams and simulated player onsets (with varying timing offsets: $-80$ ms, $0$ ms, $+35$ ms, $+120$ ms).
   - Evaluates Perfect/Good/OK/Miss grading, combo calculation, and chord matching logic.
   - Asserts correct scoring behavior deterministically.

---

## 9. Conclusion & Recommendations

1. **Feasibility**: All required core machine learning components, pretrained models, Godot runtimes, and build tools are present and functional on the host machine.
2. **Speed & Latency**: With ~10 ms ONNX inference latency and ~40 ms onset recognition, the real-time feedback loop easily fulfills the $\pm 100$ ms timing window.
3. **Implementation Plan**:
   - Clean up `project.godot` (remove broken `godot_ai` autoload and set up valid main scene).
   - Implement the modular inference pipeline in pure NumPy + ONNX Runtime.
   - Implement the Grand Staff highway rendering engine in Godot 4.
   - Implement the scoring engine with configurable latency calibration and chord matching.
   - Supply the 3 test pieces and CLI verification suites.
