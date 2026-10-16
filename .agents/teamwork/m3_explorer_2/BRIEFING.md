# BRIEFING — 2026-10-16T19:33:30Z

## Mission
Investigate standalone Python inference server (nmp.onnx Basic Pitch model), pure NumPy/ONNX Runtime execution, resampling, streaming buffer, post-processing, and WebSocket API for Milestone 3. Formulate concrete code and standalone verification script.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\david\Documents\micgame-3\.agents\teamwork\m3_explorer_2\
- Original parent: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Milestone: Milestone 3 - Basic Pitch ONNX & Audio Inference

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in project source code files (`python/inference_server.py`)
- Write proposals, analysis, and verification scripts into own folder (`.agents/teamwork/m3_explorer_2/`)
- Pretrained model at `assets/models/nmp.onnx`
- Pure NumPy + ONNX Runtime (zero scipy/librosa dependencies)
- WebSocket server using `websockets` package

## Current Parent
- Conversation ID: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Updated: 2026-10-16T19:33:30Z

## Investigation State
- **Explored paths**:
  - `assets/models/nmp.onnx`: 230,444 bytes. Inputs: `serving_default_input_2:0` [batch, 43844, 1]. Outputs: `StatefulPartitionedCall:2` (onsets [batch, 172, 88]), `StatefulPartitionedCall:1` (notes [batch, 172, 88]), `StatefulPartitionedCall:0` (contours [batch, 172, 264]).
  - `assets/audio/`: `ode_to_joy.wav`, `bach_minuet.wav`, `cadence_triads.wav` (22,050 Hz, 16-bit mono PCM).
  - `assets/charts/`: `ode_to_joy.json`, `bach_minuet.json`, `cadence_triads.json`.
  - `basic_pitch` package internals: `constants.py`, `inference.py`, `note_creation.py`.
  - Pure NumPy reimplementation of `scipy.signal.argrelmax`, window unwrapping (trimming 15 frames from each boundary), onset-driven note tracking, and linear resampling (`np.interp`).
  - `websockets` 17.0.1 integration and Godot packet format coordination.
- **Key findings**:
  - Zero external dependencies: The entire transcription and streaming pipeline executes with only `numpy` and `onnxruntime`. Resampling 2048 samples via `np.interp` takes 0.07 ms.
  - Forward pass latency: ~8.3 ms - 11.4 ms on CPU.
  - Optimal thresholds: `note_threshold = 0.40`, `onset_threshold = 0.45`, `min_note_len = 6` frames (~70ms).
  - Benchmark accuracy: Ode to Joy: 93.3% F1; Bach Minuet: 82.4% F1; Cadence Triads: 80.0% F1 (polyphonic concurrent chords verified).
  - Streaming receptive field: frames 158..167 provide clean onset & sustained note detection without window boundary padding artifacts.
- **Unexplored areas**:
  - Full Godot-to-Python network IPC in live game loop (handled by `m3_explorer_1` and `m3_explorer_3`).

## Key Decisions Made
- Implemented pure NumPy note creation (`BasicPitchOnnxRunner`) eliminating scipy, librosa, and resampy.
- Architected `proposed_basic_pitch_onnx.py` for both offline and real-time streaming.
- Architected `proposed_inference_server.py` supporting WebSocket JSON & compact binary protocols matching `m3_explorer_1/proposed_websocket_driver.gd`.
- Formulated and verified `proposed_test_transcription_harness.py` achieving >= 80% F1-score across all 3 test pieces.

## Artifact Index
- `proposed_basic_pitch_onnx.py` — Target: `python/basic_pitch_onnx.py`
- `proposed_inference_server.py` — Target: `python/inference_server.py`
- `proposed_test_transcription_harness.py` — Target: `tests/test_transcription_harness.py`
- `test_websocket_server.py` — E2E WebSocket test script
- `test_pure_numpy_basic_pitch.py` — Pure NumPy validation script
- `grid_search_thresholds.py` — Threshold optimization runner
- `report.md` — Detailed analysis report
- `handoff.md` — Structured 5-component handoff report
