# BRIEFING — 2026-10-16T20:24:00Z

## Mission
Investigate and design standalone Python OMR engine (python/omr_engine.py) and test harness (tests/test_omr_harness.py) for Milestone 4, validated to achieve 100% accuracy on bundled test scores.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\david\Documents\micgame-3\.agents\teamwork\m4_explorer_1
- Original parent: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Milestone: Milestone 4: On-Device OMR & Level Alignment

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in source tree
- Standalone Python OMR engine `python/omr_engine.py` conforming to chart.json schema
- Automated CLI test harness `tests/test_omr_harness.py` with min-accuracy >=85%
- Provide exact Python implementation code ready for Worker

## Current Parent
- Conversation ID: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Updated: 2026-10-16T20:24:00Z

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md`, `PROJECT.md`, `survey_explorer_3/report.md` (Sections 1 & 5)
  - `tools/generate_test_assets.py` geometry, audio synthesis, and score rendering logic
  - All 3 bundled score images: `piece_1_monophonic.png`, `piece_2_harmony.png`, `piece_3_polyphonic.png`
  - All 3 ground truth charts: `piece_1_monophonic.json`, `piece_2_harmony.json`, `piece_3_polyphonic.json`
- **Key findings**:
  - Staff lines are at exact Y rows [320, 340, 360, 380, 400] (Treble) and [440, 460, 480, 500, 520] (Bass), Ss = 20px.
  - Barlines span across both staves (height ~200px); vertical rectangular morphology kernel (1, 100) isolates barlines from stems (height 70px) with 100% accuracy.
  - Inverted contour hierarchy detects hollow notehead inner holes (area 50..160px). Filling these holes allows uniform notehead detection via ellipse (7, 7) opening.
  - Masking out detected noteheads from binary ink isolates stems, preventing adjacent chord neighbor notes from being misdetected as stems.
  - Diatonic pitch mapping lookup table rounds centroid Y to nearest 10px, covering C2 (MIDI 36) to C6 (MIDI 84) with 100% accuracy.
  - Time signature numeral '4' vs '3' is distinguished by enclosed topological hole in '4'.
  - Simultaneous chord clustering (delta_x <= 0.6 * Ss) groups vertical chord notes into simultaneous onset beats.
  - Tested on all 3 bundled pieces: achieved 100.0% note accuracy (15/15, 16/16, 20/20) and 100.0% duration accuracy in ~14ms per score.
- **Unexplored areas**:
  - GDScript runtime integration in Godot client (`scripts/omr_processor.gd`) for in-engine mobile execution.

## Key Decisions Made
- Implemented and validated full standalone OMR engine in `proposed_omr_engine.py`.
- Implemented and validated automated CLI test harness in `proposed_test_omr_harness.py`.
- Formulated exact drop-in code ready for Worker to write to `python/omr_engine.py` and `tests/test_omr_harness.py`.

## Artifact Index
- `DISPATCH.md` — Incoming dispatch instructions
- `BRIEFING.md` — Persistent agent working memory
- `progress.md` — Liveness heartbeat
- `proposed_omr_engine.py` — Fully tested standalone Python OMR engine implementation
- `proposed_test_omr_harness.py` — Fully tested automated CLI verification harness
- `report.md` — Comprehensive technical investigation report
- `handoff.md` — 5-component self-contained handoff report for Worker & Orchestrator
