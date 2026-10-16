# Project Orchestrator Soft Handoff (Generation 1 -> Generation 2)

**From**: Project Orchestrator Gen 1 (`7da07436-85a8-464d-9f3c-d174d6d86ee2`)  
**To**: Project Orchestrator Gen 2 (Successor)  
**Parent Conversation ID**: `e11d3dc9-435b-45b8-bb14-b793abd526b3`  
**Date**: 2026-10-16T19:20:00Z  
**Type**: Soft Handoff (Context Succession at 16 Spawns)

---

## 1. Milestone State
- [x] **Survey Phase (Phase 0)**: Complete. 3 Explorers analyzed the codebase, Godot engine 4.7.2, audio inference, and OMR.
- [x] **E2E Testing Track**: Complete. `TEST_INFRA.md` created, 230 tests implemented in `tests/e2e/` (Tiers 1-4), 100% pass rate achieved, and `TEST_READY.md` published.
- [x] **Milestone 1 (Grand Staff Highway & Scoring)**: Complete & Gate Passed.
  - `project.godot` cleaned up (orphaned autoloads/plugins removed).
  - Grand Staff visual highway implemented (`scripts/highway.gd`, `scenes/highway.tscn`, `scripts/note_data.gd`, `scripts/note_renderer.gd`). Diatonic coordinates centered at Middle C ($Y=360$px, $S=18$px) covering C2 to C6+.
  - Scoring engine implemented (`scripts/scoring_engine.gd`) with timing windows (Perfect $\pm 50$ms, Good $\pm 100$ms, Miss $> 100$ms), combo streaks, multipliers (1x-4x), and polyphonic pitch matching.
  - HUD feedback popups implemented (`scripts/hud.gd`, `scenes/hud.tscn`).
  - Adversarial remediations applied: float comparison epsilon, `is_missed` checks, $O(N)$ chord loop, dense cluster alternating offsets, and MIDI 0..127 range.
  - Verified with 91 baseline unit tests + 111 adversarial scoring tests + 78 adversarial highway tests.
- [x] **Milestone 2 (Bundled Test Pieces & Assets)**: Complete & Gate Passed.
  - Official Spotify Basic Pitch ONNX model `nmp.onnx` (230,444 bytes) bundled into `assets/models/nmp.onnx`.
  - Generator script `tools/generate_test_assets.py` implemented.
  - All 12 test assets across 3 pieces (monophonic, 2-part harmony, polyphonic chords) generated in `assets/test_pieces/` and mirrored to `assets/audio/`, `assets/scores/`, and `assets/charts/`.
  - Forensic audit verified: CLEAN.
- [ ] **Milestone 3 (Basic Pitch ONNX & Audio Inference)**: PLANNED (Ready for immediate dispatch).
  - Scope: Pluggable `IAudioPitchModel` interface, Godot microphone capture via `AudioEffectCapture` on Record bus, streaming NumPy + ONNX inference server/driver, polyphonic pitch cluster scoring.
- [ ] **Milestone 4 (On-Device OMR & Level Alignment)**: PLANNED.
  - Scope: Sheet music OMR pipeline (Python & native GDScript `omr_processor.gd`), structured chart exporter, audio-chart alignment engine, playable level loader.
- [ ] **Milestone 5 (E2E Test Pass, Platform Export & Hardening)**: PLANNED.
  - Scope: Automated CLI test harnesses (`test_omr_harness.py`, `test_transcription_harness.py`, `test_scoring_harness.py`), Android Pixel 7a ARM64-v8a signed APK export, Windows x86_64 export, headless validation, and Tier 5 adversarial coverage hardening.

---

## 2. Active Subagents
- None. All 16 spawned subagents have delivered their handoffs and are retired.

---

## 3. Pending Decisions & Key Technical Findings
1. **Basic Pitch ONNX Architecture for Milestone 3**:
   - Pretrained model: `assets/models/nmp.onnx` (input shape `[batch, 43844, 1]` at 22,050 Hz).
   - Inference latency: benchmarked at ~10.2 ms on CPU.
   - Decoupled interface: `res://scripts/inference/audio_pitch_model.gd` base interface with `WebSocketInferenceDriver` (streaming to local Python runner `python/inference_server.py`) and `MockFileInferenceDriver` (for offline / automated testing).
2. **OMR Architecture for Milestone 4**:
   - Python engine: `python/omr_engine.py` using OpenCV + NumPy projection profiling.
   - Native Godot GDScript engine: `scripts/omr_processor.gd` using Godot's `Image` class and row projection histogram for on-device mobile execution.
3. **Android Export Tooling**:
   - Godot 4.7.2 console binary: `C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe`.
   - Android SDK at `C:\Users\david\AppData\Local\Android\Sdk` (build-tools 36.0.0, apksigner, JDK 17).
   - Android export preset in `export_presets.cfg` is already verified for ARM64-v8a and `RECORD_AUDIO`.

---

## 4. Remaining Work & Immediate Next Steps for Successor
1. Re-establish heartbeat cron: `schedule(CronExpression="*/10 * * * *", Prompt="Heartbeat: check subagent progress and update progress.md", IsDaemon=false)`.
2. Dispatch Milestone 3 (Basic Pitch ONNX & Audio Inference):
   - Step 2A/2B: Run iteration loop for M3:
     - 3 Explorers (or use technical designs from `survey_explorer_2/report.md`)
     - 1 Worker to implement `python/inference_server.py`, `scripts/inference/audio_pitch_model.gd`, `scripts/inference/websocket_driver.gd`, `scripts/inference/mock_driver.gd`, and mic capture integration in `scripts/audio_capture.gd`.
     - 2 Reviewers, 2 Challengers, 1 Forensic Auditor.
3. Dispatch Milestone 4 (On-Device OMR & Level Alignment).
4. Dispatch Milestone 5 (E2E Test Pass, Platform Export & Hardening).
5. Deliver victory report back to parent `e11d3dc9-435b-45b8-bb14-b793abd526b3`.

---

## 5. Key Artifacts
- `c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md`: Authoritative User Specification
- `c:\Users\david\Documents\micgame-3\PROJECT.md`: Global architecture, feature inventory, milestones, and interface contracts
- `c:\Users\david\Documents\micgame-3\TEST_INFRA.md`: E2E test suite architecture & thresholds
- `c:\Users\david\Documents\micgame-3\TEST_READY.md`: 230 passing E2E tests report
- `c:\Users\david\Documents\micgame-3\.agents\teamwork\orchestrator_1\GATE_STATUS.md`: Gate status records
- `c:\Users\david\Documents\micgame-3\.agents\teamwork\orchestrator_1\BRIEFING.md`: Working memory state
- `c:\Users\david\Documents\micgame-3\.agents\teamwork\orchestrator_1\progress.md`: Liveness progress record
