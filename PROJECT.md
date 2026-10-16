# Project: MicGame-3 Grand Staff Rhythm Game

## Architecture
MicGame-3 is a cross-platform (Windows & Android Pixel 7a) rhythm game built on Godot 4.7.2 featuring:
1. **Visual Highway Engine (Godot 4 GDScript)**:
   - Diatonic coordinate model centered at Y=360px with classical 18px line spacing.
   - Dual Treble and Bass staves scrolling horizontally from right to left toward a target hit zone at X=160px.
   - Pitch range covering C2 (MIDI 36) to C6+ (MIDI 84+) with dynamic ledger lines and clef indicators.
   - Sub-frame playhead synchronization (`AudioStreamPlayer` + `AudioServer.get_time_since_last_mix()`).
   - Timing window evaluation (Perfect ±50ms, Good ±100ms, Miss >100ms), combo multiplier (1x-4x), and animated rating popups.
2. **Modular Audio Inference Subsystem**:
   - Pluggable `IAudioPitchModel` interface enabling clean decoupling between Godot audio capture and ML inference.
   - `AudioEffectCapture` on dedicated `Record` bus in Godot capturing microphone input with RMS noise gate.
   - Spotify Basic Pitch ONNX model (`nmp.onnx`, 230 KB) running on CPU via ONNX Runtime (<11ms latency).
   - Pure NumPy resampling (48k/44.1k to 22.05k) and onset/note probability peak-picking.
   - Polyphonic pitch cluster matcher evaluating incoming chord pitches against active highway notes.
3. **Optical Music Recognition (OMR) Subsystem**:
   - Dual-mode OMR engine:
     - Standalone Python OMR (`omr/engine.py`) using projection profiling and morphological analysis.
     - Native Godot GDScript OMR (`scripts/omr_processor.gd`) using `Image` pixel operations for on-device mobile execution.
   - Detects staves, clefs, noteheads (pitches, onsets, durations), and polyphonic chords from PNG/JPEG sheet music.
   - Pairs digitized sheet music with audio accompaniment files (WAV, MP3, OGG) to generate playable rhythm charts (`chart.json`).
4. **Bundled Test Assets & CLI Verification Harnesses**:
   - 3 varied test pieces: Monophonic melody ("Ode to Joy"), 2-part harmony ("Bach Minuet"), and polyphonic chordal progression ("Cadence & Triad Progression").
   - 3 standalone CLI test harnesses: OMR harness (>=85% accuracy), ONNX transcription harness (>=80% F1-score), and headless scoring harness.
5. **Cross-Platform & Android (Pixel 7a) Packaging**:
   - Godot GL Compatibility (GLES3) renderer for maximum performance on Google Tensor G2 / Mali-G710.
   - Android export preset configured for ARM64-v8a target with `RECORD_AUDIO` and `MODIFY_AUDIO_SETTINGS` permissions.
   - Windows Desktop x86_64 export preset.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Godot Config Cleanup | Remove orphaned autoloads/plugins from project.godot to ensure clean headless execution | M1 | Survey (Explorer 1 & 2) |
| 2 | Grand Staff Highway | Dual Treble & Bass staves scrolling right-to-left towards hit line at X=160px | M1 | ORIGINAL_REQUEST §R1 |
| 3 | Diatonic Note Placement | Exact diatonic pitch mapping (C2 to C6+) with Middle C ledger line symmetry | M1 | ORIGINAL_REQUEST §R1 |
| 4 | Hit Detection & Scoring | Real-time hit detection (Perfect ±50ms, Good ±100ms, Miss), combo counter, multipliers | M1 | ORIGINAL_REQUEST §R1 |
| 5 | Audio Playhead Sync | Sub-frame synchronization of visual highway notes with audio playback position | M1 | ORIGINAL_REQUEST §R1 |
| 6 | Bundled Test Pieces | 3 varied test pieces (monophonic, 2-part harmony, polyphonic chordal) with sheet music, audio, charts, MIDIs | M2 | ORIGINAL_REQUEST §R4 |
| 7 | Asset Generation Pipeline | Script `tools/generate_test_assets.py` to synthesize all 12 asset files deterministically | M2 | Survey (Explorer 3) |
| 8 | Basic Pitch ONNX Model | Bundling Spotify Basic Pitch `nmp.onnx` into `assets/models/nmp.onnx` | M3 | ORIGINAL_REQUEST §R2 |
| 9 | Modular Inference Interface | Pluggable `IAudioPitchModel` interface decoupling game loop from neural net models | M3 | ORIGINAL_REQUEST §R2 |
| 10 | Real-Time Polyphonic Pitch Extraction | NumPy + ONNX inference service streaming audio chunks and detecting multi-pitch clusters | M3 | ORIGINAL_REQUEST §R2 |
| 11 | Microphone Audio Capture | Low-latency Godot `AudioEffectCapture` on Record bus with RMS noise gating | M3 | ORIGINAL_REQUEST §R2 |
| 12 | Polyphonic Scoring Matcher | Matching detected polyphonic pitch clusters against expected chart notes at playhead | M3 | ORIGINAL_REQUEST §R2 |
| 13 | Sheet Music Image Ingestion | Ingest user-submitted PNG/JPEG sheet music images into structured pixel buffers | M4 | ORIGINAL_REQUEST §R3 |
| 14 | Projection Profiling OMR | On-device OMR extracting staves, clefs, noteheads, and durations | M4 | ORIGINAL_REQUEST §R3 |
| 15 | Audio-Chart Alignment | Pairing digitized sheet music charts with audio accompaniment (WAV/MP3/OGG) | M4 | ORIGINAL_REQUEST §R3 |
| 16 | Standalone CLI Test Harnesses | 3 automated CLI test harnesses (OMR >=85%, ONNX transcription >=80% F1, scoring engine) | M5 | ORIGINAL_REQUEST §R4 |
| 17 | Android (Pixel 7a) Export | Verified Android ARM64-v8a signed APK export with audio recording permissions | M5 | ORIGINAL_REQUEST §R1, Acceptance Criteria |
| 18 | Windows Desktop Export | Verified Windows Desktop x86_64 runnable executable export | M5 | ORIGINAL_REQUEST §R1, Acceptance Criteria |
| 19 | Headless Project Validation | Automated script running Godot headless tests without crashes or errors | M5 | Acceptance Criteria |
| 20 | E2E Test Suite Validation | 100% pass of E2E opaque-box test suite (Tiers 1-4) and adversarial coverage hardening (Tier 5) | M5 | Project Pattern Mandate |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Grand Staff Highway & Scoring | Project cleanup, Grand Staff right-to-left highway visual architecture, note rendering (C2-C6+), hit detection & scoring feedback | none | DONE |
| M2 | Bundled Test Pieces & Assets | 3 test pieces (monophonic, 2-part harmony, polyphonic chordal progression) with matched sheet music, audio, charts, MIDIs, and generator | none | DONE |
| M3 | Basic Pitch ONNX & Audio Inference | Bundled ONNX model, modular inference runner interface, streaming polyphonic pitch detection, Godot mic capture, polyphonic scoring | M1, M2 | DONE |
| M4 | On-Device OMR & Level Alignment | Sheet music OMR pipeline (Python & GDScript), structured chart export, audio-chart alignment engine, playable level loader | M1, M2 | DONE |
| M5 | E2E Test Pass, Platform Export & Hardening | Automated CLI test harnesses, Android (Pixel 7a) & Windows exports, headless validation, 100% E2E test suite pass, Tier 5 adversarial hardening | M1, M2, M3, M4 | DONE |

## Interface Contracts
### Highway ↔ Audio Playhead
- Highway queries `AudioStreamPlayer.get_playback_position() + AudioServer.get_time_since_last_mix()`
- Active note lookup: `get_active_notes_at(time: float, tolerance: float = 0.1) -> Array[NoteData]`
- NoteData structure: `{ "pitch_midi": int, "time_sec": float, "duration_sec": float, "is_hit": bool }`

### Game Loop ↔ Audio Inference Engine (`IAudioPitchModel`)
- Abstract interface:
  ```gdscript
  class_name IAudioPitchModel extends RefCounted
  func push_audio_samples(samples: PackedFloat32Array) -> void: pass
  func get_detected_pitches() -> Array[int]: pass # Active MIDI pitches [21..108]
  func get_recent_onsets() -> Array[int]: pass # Recently triggered onset pitches
  ```
- Modular drivers:
  - `WebSocketInferenceDriver`: streams raw PCM to Python `onnxruntime` inference server (`ws://127.0.0.1:8765`).
  - `MockFileInferenceDriver`: reads pre-computed transcription from ground truth chart for deterministic testing without mic.

### OMR Engine ↔ Chart Format (`chart.json`)
- Output chart JSON schema:
  ```json
  {
    "title": "string",
    "bpm": 120.0,
    "time_signature": [4, 4],
    "audio_file": "audio.wav",
    "notes": [
      {
        "pitch_name": "C4",
        "pitch_midi": 60,
        "staff": "treble",
        "time_sec": 0.5,
        "duration_sec": 0.5,
        "measure": 1,
        "beat": 1.0
      }
    ]
  }
  ```

## Code Layout
```
c:\Users\david\Documents\micgame-3\
├── assets/
│   ├── audio/            # Bundled test audio (WAV)
│   ├── models/           # Bundled ONNX models (nmp.onnx)
│   ├── scores/           # Bundled sheet music images (PNG)
│   └── charts/           # Reference charts (JSON, MIDI)
├── scenes/
│   ├── main.tscn         # Main game scene
│   ├── highway.tscn      # Right-to-left grand staff highway
│   ├── hud.tscn          # Scoring, combo, multiplier, rating popups
│   └── menu.tscn         # Song selection & sheet music import UI
├── scripts/
│   ├── main.gd           # Main game coordinator
│   ├── highway.gd        # Highway drawing & note management
│   ├── note_renderer.gd  # Diatonic grand staff note & ledger line rendering
│   ├── scoring_engine.gd # Hit detection, timing windows, combo logic
│   ├── audio_capture.gd  # AudioEffectCapture microphone reader
│   ├── inference/        # Modular audio inference subsystem
│   │   ├── audio_pitch_model.gd     # IAudioPitchModel base interface
│   │   ├── websocket_driver.gd      # Streaming WebSocket model runner
│   │   └── mock_driver.gd           # Offline / mock model runner
│   └── omr_processor.gd  # On-device GDScript OMR image reader
├── python/
│   ├── inference_server.py # Basic Pitch ONNX NumPy inference server
│   ├── basic_pitch_onnx.py # Standalone pure ONNX Basic Pitch runner
│   └── omr_engine.py       # Standalone Python OMR processor
├── tools/
│   ├── generate_test_assets.py # Synthesize 3 test pieces
│   └── build_and_export.py     # Headless build & export validation
└── tests/
    ├── e2e/                     # E2E Testing Track test suite
    ├── test_omr_harness.py      # Automated CLI OMR harness
    ├── test_transcription_harness.py # Automated CLI ONNX harness
    ├── test_scoring_harness.py  # Automated CLI scoring harness
    └── test_scoring_runner.gd   # Headless Godot scoring runner
```
