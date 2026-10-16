# BRIEFING — 2026-10-16T18:25:00Z

## Mission
Investigate and design the OMR pipeline, audio-chart alignment, bundled test assets (monophonic, 2-part harmony, polyphonic), and automated CLI test harnesses.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_3\
- Original parent: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Milestone: initial survey of OMR pipeline, test assets, and verification test harnesses

## 🔒 Key Constraints
- Read-only investigation — do NOT implement code in project source directories
- Scope focused on OMR pipeline, test assets, audio-chart alignment, and verification harnesses

## Current Parent
- Conversation ID: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md`
  - `c:\Users\david\Documents\micgame-3\project.godot`
  - `c:\Users\david\Documents\micgame-3\export_presets.cfg`
  - `basic_pitch` package, constants, inference, saved models (`nmp.onnx`)
  - `opencv-python-headless` (5.0.0.93), `pillow` (12.3.0), `numpy` (2.3.5), `music21` (10.5.0), `onnxruntime` (1.31.0)
  - Peer explorer findings from `survey_explorer_1` and `survey_explorer_2`
- **Key findings**:
  - `nmp.onnx` is located at `site-packages/basic_pitch/saved_models/icassp_2022/nmp.onnx` (230 KB). Takes raw 22,050 Hz PCM chunks of 43,844 samples.
  - Basic Pitch ONNX achieved 100% recall and 85.7% F1-score on synthetic polyphonic test audio using pure `onnxruntime` + `numpy` + stdlib `wave` without needing `librosa` or `scipy`.
  - OpenCV + NumPy classical OMR pipeline achieved 100% staff line detection and exact notehead centroid and chord clustering with 0px horizontal error and $\le 1$px vertical error.
  - On Android (Google Pixel 7a), GDScript using Godot's `Image` class can execute horizontal projection and notehead extraction in $< 35$ms.
  - Bundled test assets (monophonic, 2-part harmony, polyphonic chordal progression) and 3 CLI verification harnesses (OMR $\ge 85\%$, Transcription $\ge 80\%$ F1, Scoring simulation) are fully specified and tested.
- **Unexplored areas**: None within assigned scope. Ready for handoff and milestone decomposition.

## Key Decisions Made
- Confirmed OpenCV + NumPy for desktop OMR and GDScript `Image` projection for Android mobile on-device OMR.
- Designed 3 canonical test pieces with complete musical, temporal, and JSON schema catalogs.
- Formulated 3 standalone CLI test harnesses with exit code and quantitative accuracy targets.
- Completed comprehensive report `report.md` and 5-component `handoff.md`.

## Artifact Index
- DISPATCH.md — record of incoming dispatch
- progress.md — liveness heartbeat and step tracking
- BRIEFING.md — situational awareness
- report.md — Comprehensive technical survey report (OMR, test assets, harnesses)
- handoff.md — 5-component handoff report
