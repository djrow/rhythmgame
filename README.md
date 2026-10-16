# MicGame-3: Grand Staff Rhythm Game

**MicGame-3** is a cross-platform (**Windows Desktop x86_64** & **Android ARM64-v8a**, validated for stock **Google Pixel 7a**) musical rhythm game built on **Godot 4.7.2**. It adapts the Guitar Hero formula into a continuous **right-to-left horizontal Grand Staff (Treble + Bass)** highway with real-time polyphonic microphone pitch and chord scoring powered by **Spotify's Basic Pitch ONNX** model (`nmp.onnx`), plus an integrated **on-device Optical Music Recognition (OMR)** pipeline that pairs digitized sheet music images with user audio accompaniment.

---

## 1. System Architecture

1. **Grand Staff Right-to-Left Highway (`scripts/highway.gd`, `scripts/note_renderer.gd`)**:
   - **Diatonic Coordinate Model**: Centered at Middle C ($C4$, MIDI 60, diatonic step 28) at $Y = 360\text{ px}$ with $18\text{ px}$ staff line spacing ($9\text{ px}$ per diatonic step).
   - **Dual Staves**: Simultaneous 5-line Treble Clef ($E4\text{–}F5$, $Y = 270\text{–}342\text{ px}$) and 5-line Bass Clef ($G2\text{–}A3$, $Y = 378\text{–}450\text{ px}$) scrolling horizontally right-to-left into the receptor hit line at $X = 160\text{ px}$.
   - **Full Pitch Range & Ledgers**: Supports $C2$ (MIDI 36) through $C6+$ (MIDI 84+) with automatic Middle C and outer ledger line rendering, sharp/flat accidentals, and polyphonic chord stacking.
   - **Sub-Frame Playhead Sync**: Synchronizes note visual coordinates with `AudioStreamPlayer.get_playback_position() + AudioServer.get_time_since_last_mix()`.

2. **Modular Polyphonic Audio Inference (`scripts/inference/`, `python/basic_pitch_onnx.py`, `python/inference_server.py`)**:
   - **Pluggable Model Interface (`IAudioPitchModel`)**: Decouples Godot audio capture and gameplay scoring from the underlying neural network via `scripts/inference/audio_pitch_model.gd`, allowing drop-in replacement of future instrument-specific models, source separation networks, or fine-tuned weights.
   - **Drivers**:
     - `WebSocketInferenceDriver` (`scripts/inference/websocket_driver.gd`): Streams raw mono PCM chunks to the local/companion Python ONNX inference server (`ws://127.0.0.1:8765`).
     - `MockDriver` (`scripts/inference/mock_driver.gd`): Deterministic chart-driven pitch/onset provider for headless testing and offline verification.
   - **Spotify Basic Pitch ONNX Engine**: Bundled `assets/models/nmp.onnx` (ICARSP 2022 weights) executed via `onnxruntime` and pure `numpy` linear resampling ($48\text{ kHz}/44.1\text{ kHz} \to 22,050\text{ Hz}$), consuming `[1, 43844, 1]` audio windows and extracting 88-key note/onset activations (`[1, 172, 88]`) and 264-bin pitch contours (`[1, 172, 264]`).
   - **Low-Latency Microphone Capture (`scripts/audio_capture.gd`)**: Captures stereo input from Godot's dedicated `Record` bus (`default_bus_layout.tres`) via `AudioEffectCapture`, downmixes to mono, and applies an RMS noise gate ($-45\text{ dB}$ / $0.005\text{ RMS}$).

3. **Hit Detection & Polyphonic Scoring Engine (`scripts/scoring_engine.gd`)**:
   - **Timing Windows**: `PERFECT` ($\le \pm 50\text{ ms}$, $100\text{ pts}$), `GOOD` ($\le \pm 100\text{ ms}$, $50\text{ pts}$), `MISS` ($> \pm 100\text{ ms}$, $0\text{ pts}$, resets combo).
   - **Combo Multipliers**: $1\times$ ($0\text{–}9$ combo), $2\times$ ($10\text{–}19$), $3\times$ ($20\text{–}29$), and $4\times$ cap ($\ge 30$ combo).
   - **Polyphonic Cluster Matcher**: Evaluates simultaneous multi-note chords and 2-part harmony across Treble and Bass staves with sustain-retrigger filtering.

4. **On-Device Optical Music Recognition & Audio Alignment (`scripts/omr_processor.gd`, `python/omr_engine.py`, `scripts/level_loader.gd`)**:
   - **Dual Implementation**: Native GDScript `OMRProcessor` (`Image` pixel operations for standalone Android/Windows execution) and standalone Python `OMREngine` (`opencv-python-headless` + `numpy`).
   - **Pipeline**: Grayscale binarization $\to$ horizontal projection profiling for Treble/Bass staff line detection $\to$ vertical projection for barlines/measures $\to$ connected-component notehead isolation $\to$ diatonic pitch & beat duration quantization $\to$ audio accompaniment pairing (`WAV`/`MP3`/`OGG`) into playable `chart.json`.

---

## 2. Dependencies & Environment Requirements

| Component | Version / Package | Purpose |
| :--- | :--- | :--- |
| **Godot Engine** | Godot `4.7.2.stable` (Console / Standard) | Game runtime, GDScript headless test runners, Android/Windows export |
| **Python** | Python `3.12+` | CLI verification harnesses, ONNX inference service, asset generation |
| **ONNX Runtime** | `onnxruntime >= 1.18` | CPU execution of `assets/models/nmp.onnx` |
| **NumPy** | `numpy >= 1.26` | Audio resampling, projection profiles, tensor post-processing |
| **OpenCV & Pillow** | `opencv-python-headless`, `Pillow` | Sheet music image ingestion, OMR morphological processing, score synthesis |
| **WebSockets** | `websockets` (optional) | Real-time streaming IPC for `python/inference_server.py` |
| **Music21** | `music21` (optional) | Reference `.mid` generation in `tools/generate_test_assets.py` |

To regenerate all 3 bundled test pieces (`ode_to_joy`, `bach_minuet`, `cadence_triads`) and verify `assets/models/nmp.onnx`:
```bash
python tools/generate_test_assets.py
```

---

## 3. Running Verification Harnesses & E2E Test Suite

All verification harnesses run deterministically from the project root without requiring live microphone hardware or a graphical display:

### 3.1 Standalone CLI Test Harnesses
1. **OMR Verification Harness** (Target: $\ge 85.0\%$ note pitch & onset accuracy across all 3 bundled scores):
   ```bash
   python tests/test_omr_harness.py
   ```
2. **Basic Pitch ONNX Transcription Harness** (Target: $\ge 80.0\%$ F1-score & polyphonic chord simultaneity on bundled WAV audio):
   ```bash
   python tests/test_transcription_harness.py
   ```
3. **Scoring & Alignment Verification Harness** (Simulates Perfect/Good/Miss playthroughs across all 3 test pieces and runs Godot headless scoring & inference suites):
   ```bash
   python tests/test_scoring_harness.py
   ```

### 3.2 Full 5-Tier E2E Test Suite (250 Tests)
Executes Tier 1 (Feature Coverage, 100 tests), Tier 2 (Boundary & Corner Cases, 100 tests), Tier 3 (Cross-Feature Combinations, 20 tests), Tier 4 (Real-World Scenarios, 10 tests), and Tier 5 (Adversarial & Hardening, 20 tests):
```bash
python tests/e2e/run_all_e2e_tests.py
```
For machine-readable JSON output:
```bash
python tests/e2e/run_all_e2e_tests.py --json
```

---

## 4. Building & Deploying for Windows and Google Pixel 7a

### 4.1 Automated Build, Export & Validation CLI
Run `tools/build_and_export.py` to validate `project.godot`, `export_presets.cfg`, run Godot headless project verification, and inspect `micgame3.apk` and `micgame3.exe`:
```bash
python tools/build_and_export.py
```
To force a fresh headless export of both `micgame3.apk` (Android ARM64-v8a) and `micgame3.exe` (Windows Desktop x86_64):
```bash
python tools/build_and_export.py --export
```

### 4.2 Stock Google Pixel 7a Deployment (`micgame3.apk`)
- **Hardware Target**: Google Tensor G2 (`arm64-v8a`), Mali-G710 MP7 GPU (`gl_compatibility` / OpenGL ES 3.0 renderer with ASTC texture compression enabled).
- **Audio Permissions**: Configured with `android.permission.RECORD_AUDIO` and `android.permission.MODIFY_AUDIO_SETTINGS` in `export_presets.cfg`, plus runtime permission request on startup in `scripts/audio_capture.gd`.
- **Install via ADB**:
  ```bash
  adb install -r micgame3.apk
  ```

### 4.3 Windows Desktop Execution (`micgame3.exe`)
- **Target**: Windows `x86_64` standalone executable with embedded PCK (`binary_format/embed_pck=true`) and D3D12/GL Compatibility rendering.
- **Run Locally**:
  ```bash
  ./micgame3.exe
  ```
  *(Optional)* Start the companion Basic Pitch ONNX WebSocket server before launching for live neural polyphonic transcription:
  ```bash
  python python/inference_server.py --host 127.0.0.1 --port 8765
  ```
