# Comprehensive Survey & Architectural Analysis Report: micgame-3

**Author**: `survey_explorer_1` (Teamwork Explorer)  
**Date**: 2026-10-16  
**Target Project**: `c:\Users\david\Documents\micgame-3`  
**Specification Reference**: `c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md`

---

## 1. Executive Summary

This report delivers a comprehensive investigation of the `micgame-3` workspace, Godot 4.7 engine runtime environment, Android (Pixel 7a) and Windows export configurations, and architectural specifications for the **Grand Staff Right-to-Left Note Highway**, real-time **Spotify Basic Pitch ONNX inference**, and **On-Device Optical Music Recognition (OMR)** rhythm game.

### Core Discoveries
1. **Engine & Runtime**: The active Godot engine binary is **Godot v4.7.2.stable.official.ed1daf0bf** located at `C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe`. Both headless execution (`--headless`) and headless export pipelines are fully operational.
2. **Current Project State**: The root directory contains project configuration files (`project.godot`, `export_presets.cfg`, `default_bus_layout.tres`, `icon.svg`) and two pre-built binaries (`micgame3.apk`, `micgame3.exe`). The scene files (`res://scenes/main.tscn`) and scripts referenced in `project.godot` are missing from the filesystem, as the pre-built binaries were exported from an earlier vertical 4-lane receptor prototype. Furthermore, `project.godot` contains references to an orphaned AI addon (`res://addons/godot_ai/runtime/game_helper.gd`) which causes headless execution to fail with exit code 1 until cleaned up.
3. **Export Validation**:
   - **Android Export (Google Pixel 7a)**: Verified and fully working. The export template (`4.7.2.stable/android_debug.apk`), Android SDK (`C:\Users\david\AppData\Local\Android\Sdk`), build-tools 36.0.0, Java JDK 17 (`C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot`), and `debug.keystore` are fully installed. Godot's headless CLI export command successfully builds, packages, aligns, and signs an ARM64-v8a debug APK with `RECORD_AUDIO` and `MODIFY_AUDIO_SETTINGS` permissions.
   - **Windows Desktop Export**: Verified and working. Successfully exports an embedded PCK x86_64 binary.
4. **Python & ML Tooling**: Python 3.12.10 is installed with `onnxruntime` (1.31.0), `basic-pitch` (0.4.0), `torch` (2.13.0), `opencv-python-headless` (5.0.0.93), `pillow` (12.3.0), `music21` (10.5.0), and `numpy` (2.3.5). The official Spotify Basic Pitch ONNX weights file (`nmp.onnx`) is physically verified on disk.
5. **Grand Staff Right-to-Left Highway Architecture**: A complete mathematical model for mapping pitches C2 (MIDI 36) through C6+ (MIDI 84+) to diatonic staff steps, dual Treble and Bass staves, symmetrical Middle C ledger spacing, dynamic ledger lines, right-to-left continuous highway scrolling, hit line target zone, and visual timing/accuracy feedback has been developed and specified below.

---

## 2. Existing Codebase & Environment Inventory

### 2.1 File System Audit of Project Root (`c:\Users\david\Documents\micgame-3`)

| File / Folder | Size / Type | Status & Purpose |
| :--- | :--- | :--- |
| `project.godot` | 1,066 bytes | Godot 4.7 configuration file. Enables audio input, references `default_bus_layout.tres`, specifies window size 1280x720. **Defect**: References nonexistent autoload `res://addons/godot_ai/runtime/game_helper.gd` and main scene `res://scenes/main.tscn`. |
| `export_presets.cfg` | 9,218 bytes | Configures preset 0 (`Android`, ARM64-v8a, `RECORD_AUDIO=true`) and preset 1 (`Windows Desktop`, x86_64, `embed_pck=true`). Both presets tested and valid. |
| `default_bus_layout.tres` | 414 bytes | Godot AudioBusLayout with master bus (index 0) and `Record` bus (index 1) equipped with `AudioEffectCapture` (buffer_length 1.0s). Ready for live microphone streaming. |
| `icon.svg` & `.import` | ~1 KB | Default Godot project icon. |
| `micgame3.apk` | 58.5 MB | Compiled Android APK from a prior vertical 4-lane button prototype. Contains compiled `.gdc` bytecode and `.scn` binary scenes. |
| `micgame3.exe` | 110.5 MB | Compiled Windows x86_64 executable containing embedded PCK of the prior vertical 4-lane prototype. |
| `.agents/` | Directory | Teamwork metadata and agent memory directories. |

### 2.2 Godot Binary Detection & Capabilities

- **Console Binary**: `C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe`
- **Standard Binary**: `C:\Users\david\Downloads\Godot_v4.7.2-stable_win64.exe`
- **Version Reported**: `Godot Engine v4.7.2.stable.official.ed1daf0bf`
- **Headless Execution Verification**:
  - Running `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --version` returns `4.7.2.stable.official.ed1daf0bf` (exit code 0).
  - Running `--headless --path "c:\Users\david\Documents\micgame-3" --quit` executes the engine headlessly, but fails with exit code 1 due to the missing autoload and scene.

### 2.3 Required `project.godot` Remediation

In `project.godot`, lines 23-25 and lines 34-36 currently contain:
```ini
[autoload]
_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"

[editor_plugins]
enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")
```
Because `res://addons/godot_ai/` does not exist on disk, Godot logs fatal initialization errors on startup.  
**Action Required**: Remove lines 23-26 and lines 34-37 from `project.godot` to permit clean zero-error headless execution.

---

## 3. Grand Staff Right-to-Left Highway Visual Architecture

The visual presentation requires a continuous horizontal note highway running from **right to left**, rendering standard musical **Grand Staff (Double Staff)** notation featuring both Treble (G clef) and Bass (F clef) staves simultaneously.

```
          HIGHWAY SCROLL DIRECTION: <==== [Notes scroll Right to Left] <====
========================================================================================
                      TREBLE CLEF STAFF (5 Lines, 4 Spaces)
-------------------------------------------------------------------------  F5 (Top line)
-------------------------------------------------------------------------  D5
-------------------------------------------------------------------------  B4
-------------------------------------------------------------------------  G4
-------------------------------------------------------------------------  E4 (Bottom line)
========================================================================================
                          MIDDLE C (C4) LEDGER LINE ZONE
 - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -   C4 (Middle C)
========================================================================================
                       BASS CLEF STAFF (5 Lines, 4 Spaces)
-------------------------------------------------------------------------  A3 (Top line)
-------------------------------------------------------------------------  F3
-------------------------------------------------------------------------  D3
-------------------------------------------------------------------------  B2
-------------------------------------------------------------------------  G2 (Bottom line)
========================================================================================
   [TARGET ZONE / HIT LINE]
           X = 160 px
```

### 3.1 Mathematical Pitch-to-Staff Coordinate Model

Musical notation is structured on **diatonic pitch steps** (A, B, C, D, E, F, G), not linear semitones. Accidentals ($\sharp$, $\flat$, $\natural$) alter the pitch chromatically without changing the vertical staff position of the note head.

#### Diatonic Step Calculation:
Let $M$ be the MIDI pitch number ($0 \le M \le 127$).
- Semitone pitch class $P = M \pmod{12}$, where $0 = \text{C}, 1 = \text{C}\sharp/\text{D}\flat, 2 = \text{D}, \dots, 11 = \text{B}$.
- Octave number $O = \lfloor M / 12 \rfloor - 1$.
- Pitch class diatonic step lookup:
  $$\text{DiatonicOffset}(P) = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6][P]$$
- Accidental flag:
  $$\text{IsAccidental}(P) = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0][P]$$
- Absolute Diatonic Step Index $D(M)$:
  $$D(M) = O \times 7 + \text{DiatonicOffset}(P)$$

#### Vertical Staff Layout & Symmetry
Let Middle C (C4, MIDI 60) serve as the vertical reference origin:
$$D(\text{C4}) = 4 \times 7 + 0 = 28$$
Let $S$ be the vertical distance between adjacent staff lines (e.g., $S = 18\text{ pixels}$).  
Each diatonic step (line to space or space to line) corresponds to half the line spacing:
$$\Delta y = \frac{S}{2} = 9\text{ pixels}$$

Let $Y_{\text{center}}$ be the screen Y-coordinate of Middle C (e.g., $Y_{\text{center}} = 360\text{ px}$ in a 720p viewport).  
Because Godot's 2D coordinate system has positive Y pointing downwards:
$$Y(M) = Y_{\text{center}} - \left( D(M) - 28 \right) \times \frac{S}{2}$$

#### Staff Anchor Points (Line Spacing $S = 18\text{ px}$, $\Delta y = 9\text{ px}$, $Y_{\text{center}} = 360\text{ px}$):
1. **Treble Staff Lines** (5 lines):
   - Line 1 (Bottom, E4, MIDI 64, Step 30): $Y = 360 - 2 \times 9 = 342\text{ px}$ (Offset $-S$)
   - Line 2 (G4, MIDI 67, Step 32): $Y = 360 - 4 \times 9 = 324\text{ px}$ (Offset $-2S$)
   - Line 3 (B4, MIDI 71, Step 34): $Y = 360 - 6 \times 9 = 306\text{ px}$ (Offset $-3S$)
   - Line 4 (D5, MIDI 74, Step 36): $Y = 360 - 8 \times 9 = 288\text{ px}$ (Offset $-4S$)
   - Line 5 (Top, F5, MIDI 77, Step 38): $Y = 360 - 10 \times 9 = 270\text{ px}$ (Offset $-5S$)
2. **Middle C Gap**:
   - The gap between Treble Bottom Line (E4, $Y=342$) and Bass Top Line (A3, $Y=378$) is exactly $2S = 36\text{ px}$. Middle C ($Y=360$) sits exactly in the center, equidistant ($1S = 18\text{ px}$) from both staves.
3. **Bass Staff Lines** (5 lines):
   - Line 5 (Top, A3, MIDI 57, Step 26): $Y = 360 + 2 \times 9 = 378\text{ px}$ (Offset $+S$)
   - Line 4 (F3, MIDI 53, Step 24): $Y = 360 + 4 \times 9 = 396\text{ px}$ (Offset $+2S$)
   - Line 3 (D3, MIDI 50, Step 22): $Y = 360 + 6 \times 9 = 414\text{ px}$ (Offset $+3S$)
   - Line 2 (B2, MIDI 47, Step 20): $Y = 360 + 8 \times 9 = 432\text{ px}$ (Offset $+4S$)
   - Line 1 (Bottom, G2, MIDI 43, Step 18): $Y = 360 + 10 \times 9 = 450\text{ px}$ (Offset $+5S$)

#### Pitch Boundary Range (C2 to C6+):
- **C2 (MIDI 36, Step 14)**: $Y = 360 - (14 - 28) \times 9 = 360 + 126 = 486\text{ px}$ (Requires 2 ledger lines below Bass staff: E2 at step 16, C2 at step 14).
- **C6 (MIDI 84, Step 42)**: $Y = 360 - (42 - 28) \times 9 = 360 - 126 = 234\text{ px}$ (Requires 2 ledger lines above Treble staff: A5 at step 40, C6 at step 42).
- **C7 (MIDI 96, Step 49)**: $Y = 360 - 21 \times 9 = 171\text{ px}$ (Extends gracefully with higher ledger lines).

### 3.2 Dynamic Ledger Line Rendering Rules

A ledger line is a short horizontal segment rendered through or behind a note head to extend the staff:
- **Ledger Line Geometry**: Width = $28\text{ px}$ (note head width $18\text{ px} + 10\text{ px}$ margin), thickness = $2\text{ px}$, color = `#6c7a89` or matching staff lines.
- **Rule 1 (Middle C Zone)**: When note step $D(M) == 28$ (C4 / C#4), draw a ledger line at $Y = Y_{\text{center}}$.
- **Rule 2 (Above Treble Staff, $D(M) \ge 40$)**: For even steps $k \in \{40, 42, \dots, 2 \times \lfloor D(M)/2 \rfloor\}$, draw ledger lines at $Y(k)$.
- **Rule 3 (Below Bass Staff, $D(M) \le 16$)**: For even steps $k \in \{16, 14, \dots, 2 \times \lceil D(M)/2 \rceil\}$, draw ledger lines at $Y(k)$.

### 3.3 Right-to-Left Highway Motion & Synchronization

1. **Target Zone / Hit Line**:
   - Fixed position on the left side of the viewport: $X_{\text{hit}} = 160\text{ px}$.
   - Renders as a vertical translucent luminescent bar across both staves ($Y \in [200, 520]$) with a dual-color neon core (`#00f0ff` cyan / `#ffd700` gold).
   - Clefs: Treble Clef icon rendered at $(X = 80, Y = 306)$ and Bass Clef icon rendered at $(X = 80, Y = 414)$.
2. **Note Highway Trajectory**:
   - Notes scroll strictly from **Right to Left**.
   - Note horizontal position equation at current song time $T$:
     $$X(t, T) = X_{\text{hit}} + (t_{\text{note}} - T) \times V_{\text{scroll}}$$
     where $V_{\text{scroll}}$ is configurable (default $320\text{ px/second}$).
   - A note scheduled at $t_{\text{note}}$ crosses the hit line at the exact moment $T = t_{\text{note}}$, where $X = X_{\text{hit}}$.
   - Visibility culling: Notes spawn when $X(t, T) \le 1280 + 100$ and are culled/evaluated as Misses when $X(t, T) < X_{\text{hit}} - 80$.
3. **Polyphonic Chord Stacking**:
   - Simultaneous notes sharing the same onset timestamp $t_{\text{note}}$ share the identical horizontal coordinate $X$. They render as vertically stacked note heads across the staves, connected by a vertical stem when appropriate.

### 3.4 Visual Hit Feedback & HUD Interface

1. **Hit Timing Windows & Judgment**:
   - **PERFECT**: $|T_{\text{hit}} - t_{\text{note}}| \le 50\text{ ms}$ (Color: `#ffd700` Gold, Scale Pulse: $1.4\times \to 1.0\times$, Score: $+1000 \times \text{Multiplier}$)
   - **GOOD**: $50\text{ ms} < |T_{\text{hit}} - t_{\text{note}}| \le 120\text{ ms}$ (Color: `#00ff88` Neon Green, Scale Pulse: $1.2\times \to 1.0\times$, Score: $+500 \times \text{Multiplier}$)
   - **MISS**: $|T_{\text{hit}} - t_{\text{note}}| > 120\text{ ms}$ or unplayed note passing $X_{\text{hit}} - 40\text{ px}$ (Color: `#ff3366` Crimson, Fade-out, Streak reset to 0)
2. **Hit Effect Animations**:
   - Floating rating labels spawned at $(X_{\text{hit}} + 40, Y_{\text{hit}})$ animating upwards with easing.
   - Ripple ring expansion at the receptor position on the staff.
3. **Combo & Scoring Display (HUD)**:
   - **Score Label**: Prominently displayed at top-center, animated with smooth numeric interpolation.
   - **Combo / Streak Counter**: Displays current streak; increments multiplier:
     - 1x: 0–9 combo
     - 2x: 10–19 combo
     - 3x: 20–29 combo
     - 4x: 30+ combo
   - **Pitch Indicator (Live Tuning Guide)**: An active vertical marker or glowing pip on the hit line indicating the player's current singing/playing pitch in real time, giving immediate visual feedback on whether they are sharp, flat, or on target.

---

## 4. Mobile & Desktop Export Architecture (Google Pixel 7a & Windows)

### 4.1 Stock Google Pixel 7a Target Hardware Profile

| Hardware Specification | Pixel 7a Property | Rhythm Game Architecture Implication |
| :--- | :--- | :--- |
| **SoC** | Google Tensor G2 (5 nm) | High single-thread and multicore performance. |
| **CPU Architecture** | 64-bit ARM (`ARM64-v8a`) | APK must package `lib/arm64-v8a/libgodot_android.so`. `arm64-v8a=true` verified in `export_presets.cfg`. |
| **GPU** | Mali-G710 MP7 | Supports Vulkan 1.3 & OpenGL ES 3.2. |
| **Display** | 1080 x 2400 pixels, 90Hz, 20:9 | Viewport stretch mode `canvas_items` with aspect `expand` adapts seamlessly from 16:9 (1280x720) to 20:9 without distorting staff spacing. 90Hz provides ultra-smooth 11.1ms frame delivery for note highway. |
| **Audio Subsystem** | AAudio / OpenSL ES, 48kHz native | Low-latency audio capture via AAudio. Requires buffer resampling from 48kHz to 22.05kHz for Basic Pitch inference. |
| **OS** | Android 13 / 14 / 15 | Strict runtime permission requirements: `android.permission.RECORD_AUDIO`. |

### 4.2 Renderer Selection: GL Compatibility vs Vulkan Mobile

In `project.godot`:
```ini
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true
```
**Architectural Verification**:
- **Why GL Compatibility (GLES3) is ideal for Pixel 7a**:
  1. GLES3 starts up instantly without Vulkan pipeline cache compilation stutter.
  2. A 2D musical staff and note highway relies on clean 2D vector primitives, line drawing, and UI canvas items. OpenGL ES 3.0 provides maximum frame-rate stability and minimum thermal overhead on the Mali-G710 GPU.
  3. ASTC texture compression (`import_etc2_astc=true`) is natively supported in hardware by Mali GPUs.

### 4.3 Android Permissions & Audio Recording Verification

1. **Manifest Permissions in `export_presets.cfg`**:
   - `permissions/record_audio = true` (Line 187) -> Adds `android.permission.RECORD_AUDIO`.
   - `permissions/modify_audio_settings = true` (Line 155) -> Adds `android.permission.MODIFY_AUDIO_SETTINGS`.
2. **Runtime Permission Request**:
   On Android 6.0+, permissions in the manifest are not enough; the app must request permission at runtime. GDScript initialization routine:
   ```gdscript
   func _ready() -> void:
       if OS.get_name() == "Android":
           if not OS.is_permission_granted("android.permission.RECORD_AUDIO"):
               OS.request_permission("android.permission.RECORD_AUDIO")
   ```
3. **Headless Android Export Test**:
   - Executed:
     ```powershell
     & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --export-debug "Android" "test_export.apk"
     ```
   - Result: **SUCCESS (Exit Code 0)**.
   - APK signed with `apksigner.bat` using Android SDK build-tools 36.0.0 and `debug.keystore`.
   - Verified APK contents: contains `lib/arm64-v8a/libgodot_android.so` and `AndroidManifest.xml` with `RECORD_AUDIO`.

### 4.4 Windows Desktop Export Verification

- **Preset**: `Windows Desktop` (`x86_64`, `embed_pck=true`).
- **Headless Export Test**:
  - Executed:
    ```powershell
    & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --export-debug "Windows Desktop" "test_export.exe"
    ```
  - Result: **SUCCESS (Exit Code 0)**.
  - Windows executable packages cleanly with embedded PCK and console wrapper.

---

## 5. Audio Pipeline & Spotify Basic Pitch ONNX Architecture

### 5.1 Environment ML Tooling Verification

| Dependency | Version Detected | Disk Path / Verification |
| :--- | :--- | :--- |
| **Python** | 3.12.10 | `C:\Users\david\AppData\Local\Microsoft\WindowsApps\python.exe` |
| **ONNX Runtime** | 1.31.0 | `onnxruntime` import validated in Python 3.12 |
| **Basic Pitch** | 0.4.0 | `site-packages\basic_pitch` validated |
| **Basic Pitch ONNX Weights** | `nmp.onnx` (ICARSP 2022) | `C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages\basic_pitch\saved_models\icassp_2022\nmp.onnx` |
| **PyTorch** | 2.13.0 | Installed |
| **OpenCV** | 5.0.0.93 (`opencv-python-headless`) | Installed |
| **Pillow** | 12.3.0 | Installed |
| **Music21** | 10.5.0 | Installed |

### 5.2 Basic Pitch ONNX Model Tensor Specifications

Verified by inspecting `nmp.onnx` with `onnxruntime.InferenceSession`:
- **Input Tensor**:
  - Name: `serving_default_input_2:0`
  - Shape: `[batch_size, 43844, 1]`
  - Type: `tensor(float)` (Float32)
  - Sample Rate: **22,050 Hz** (43,844 samples = exactly $1.988\text{ seconds}$).
- **Output Tensors**:
  1. `StatefulPartitionedCall:2`: Shape `[batch_size, 172, 88]` (Float32 Note activation probabilities for 88 MIDI pitches from A0 [MIDI 21] to C8 [MIDI 108]).
  2. `StatefulPartitionedCall:1`: Shape `[batch_size, 172, 88]` (Float32 Onset activation probabilities).
  3. `StatefulPartitionedCall:0`: Shape `[batch_size, 172, 264]` (Float32 Pitch bend contours with 3 sub-semitone bins per pitch: $88 \times 3 = 264$).

### 5.3 Modular Model Runner Architecture

To satisfy requirement R2 ("Design the audio inference subsystem with a modular model runner interface so future instrument-specific neural networks, source separation models, and fine-tuning pipelines can be cleanly plugged in"):

```
+-------------------------------------------------------------------------+
|                         AUDIO INFERENCE SYSTEM                          |
+-------------------------------------------------------------------------+
                                     |
              +----------------------+----------------------+
              |                                             |
   [Godot Client / Engine]                       [Modular Model Runner]
              |                                             |
   AudioEffectCapture (Record Bus)               IAudioPitchModel (Interface)
              |                                             |
   PCM Buffer Extraction                         +----------+----------+
              |                                  |                     |
   Resample 48k/44.1k -> 22.05k        [BasicPitchONNXRunner] [Future Model / Separator]
              |                                  |
   IPC / Native Bridge -----------------> infer_window(audio_samples)
                                                 |
                                         Note & Onset Events [MIDI, Onset, Time]
                                                 |
   Scoring Engine <------------------------------+
   (Pitch matching +/- semitone,
    Timing window +/- 100ms)
```

1. **Abstract Model Runner Interface (`IAudioPitchModel`)**:
   - `initialize(model_path: String, config: Dictionary) -> bool`
   - `get_expected_sample_rate() -> int` (returns 22050 for Basic Pitch)
   - `get_window_size() -> int` (returns 43844 for Basic Pitch)
   - `process_audio_chunk(pcm_data: PackedFloat32Array) -> Array[NoteEvent]`
   - `reset() -> void`
2. **Audio Streaming & Latency Budget**:
   - In live gameplay, a full 1.988s window creates latency if not windowed. Basic Pitch uses overlapping hops (e.g., hop size of 2,205 to 4,410 samples = 100ms–200ms update rate). The latest frames in the 172-frame output correspond to the immediate real-time notes.
   - For offline test harnesses, entire tracks or streaming chunks can be processed in batch.

---

## 6. Optical Music Recognition (OMR) Architecture & Test Assets

### 6.1 On-Device OMR Ingestion Pipeline

The OMR engine ingests clean sheet music images (PNG/JPEG) and outputs structured note charts:
1. **Binarization & Preprocessing**:
   - Input image converted to grayscale and thresholded using OpenCV/Pillow (`cv2.adaptiveThreshold` or Otsu).
2. **Staff Line Detection**:
   - Horizontal projection profiles locate staff line clusters.
   - Computes staff line thickness ($t$) and line spacing ($s$).
   - Segments the systems into dual staves: identifies Treble staff (top) and Bass staff (bottom) pairs.
3. **Bar Line / Measure Segmentation**:
   - Vertical projection profiles and morphological vertical kernels extract measure boundaries.
4. **Clef & Key Signature Recognition**:
   - Detects G-clef on top staff and F-clef on bottom staff.
5. **Note Head Detection & Pitch Mapping**:
   - Connected Component Analysis (CCA) and morphological black-hat transforms isolate note heads.
   - Vertical center of each note head is compared against the 5 staff line Y-coordinates to determine the exact diatonic step and pitch (C2–C6+).
6. **Chart Serialization**:
   - Emits standardized JSON chart format:
     ```json
     {
       "title": "Test Piece 1 - Monophonic Melody",
       "tempo_bpm": 120.0,
       "time_signature": [4, 4],
       "notes": [
         {"pitch_name": "C4", "midi": 60, "start_time": 0.0, "duration": 0.5, "staff": "treble"},
         {"pitch_name": "E4", "midi": 64, "start_time": 0.5, "duration": 0.5, "staff": "treble"},
         {"pitch_name": "G4", "midi": 67, "start_time": 1.0, "duration": 0.5, "staff": "treble"}
       ]
     }
     ```

### 6.2 Bundled Test Assets & CLI Test Harnesses

To satisfy R4 and Acceptance Criteria:
1. **Three Test Pieces Required**:
   - **Piece 1 (Monophonic Melody)**: Clean vocal or solo instrument line spanning C4 to C5.
   - **Piece 2 (2-Part Harmony)**: Simultaneous Treble melody and Bass counterpoint.
   - **Piece 3 (Polyphonic Chord Progression)**: 3-to-4 note chords across both Treble and Bass staves.
   - Each piece must include:
     - Rendered clean sheet music score (`score.png`)
     - Pre-recorded reference audio (`audio.wav` or `.ogg`)
     - Ground-truth chart (`chart.json`)
2. **Three CLI Test Harnesses Required**:
   - `test_omr.py`: Compares OMR output against ground-truth note charts (target $\ge 85\%$ accuracy).
   - `test_transcription.py`: Runs Basic Pitch ONNX on reference audio against ground truth (target $\ge 80\%$ F1-score).
   - `test_scoring.py`: Feeds simulated note hits with various timing offsets and pitches into the scoring engine to verify Perfect/Good/Miss logic without live mic input.

---

## 7. Gap Analysis & Downstream Implementation Roadmap

### 7.1 Detailed Gap Inventory

| Component / Subsystem | Current State | Required State | Actionable Fix / Implementation |
| :--- | :--- | :--- | :--- |
| `project.godot` | References missing `addons/godot_ai` autoload & missing `main.tscn` | Clean configuration loading default scene without errors | Remove `_mcp_game_helper` autoload and plugin lines; create `res://scenes/main.tscn`. |
| Grand Staff Note Highway | Only 4-lane receptor binary prototype exists | Full horizontal right-to-left Grand Staff highway | Create `scripts/grand_staff_highway.gd`, dual staves, Middle C ledger, dynamic ledger generator, hit line at $X=160$. |
| Note Rendering & Scrolling | Basic single-lane note blocks in compiled `.scn` | Diatonic note heads, accidentals (#/b), chords, smooth right-to-left motion | Implement `scripts/note_renderer.gd` supporting C2 to C6+ with chord stacking. |
| Hit Detection & Feedback | Simple RMS threshold strumming in compiled `.scn` | Timing windows (Perfect $\pm 50$ms, Good $\pm 120$ms, Miss), floating labels, particle pulse | Implement `scripts/hit_feedback.gd` and `scripts/scoring_manager.gd`. |
| HUD & Scoring Display | Simple prototype labels | High-polish HUD: Score, Streak, Multiplier (1x-4x), live pitch tuning guide | Create UI scenes/HUD with reactive score interpolation. |
| Microphone Capture | Bus `Record` configured with `AudioEffectCapture` | GDScript audio capture manager with Android permission request | Create `scripts/mic_capture.gd` querying `AudioEffectCaptureInstance.get_buffer()`. |
| Basic Pitch ONNX Runner | Python environment has package & weights; no Godot bridge | Decoupled inference runner with `IAudioPitchModel` interface | Create Python CLI transcription harness and Godot bridge / offline validator. |
| On-Device OMR Pipeline | Python OpenCV/Pillow available; no pipeline scripts in workspace | Automated image-to-chart OMR processor | Create `tools/omr/omr_processor.py` for staff/note recognition. |
| Bundled Test Pieces | None in project root | 3 varied test pieces (monophonic, 2-part harmony, polyphonic chords) | Generate/bundle sheet music images, audio, and ground truth charts. |
| CLI Verification Harnesses | None in project root | Standalone CLI scripts for OMR, ONNX transcription, and scoring | Implement `tests/test_omr.py`, `tests/test_transcription.py`, `tests/test_scoring.py`. |

---

## 8. Conclusion

The development environment is primed and fully capable of delivering all requirements:
- Godot 4.7 is operational with verified headless compilation and export for both **Windows Desktop (x86_64)** and **Android Google Pixel 7a (ARM64-v8a)**.
- Android permissions (`RECORD_AUDIO`, `MODIFY_AUDIO_SETTINGS`) and signing via `apksigner.bat` are fully verified.
- The machine learning runtime (`onnxruntime`, `basic-pitch`, `nmp.onnx`) is installed and functional.
- The mathematical coordinate system and visual architecture for the Grand Staff right-to-left note highway are fully specified.

This report serves as the authoritative blueprint for the implementation teams.
