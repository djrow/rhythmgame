# BRIEFING — 2026-10-16T20:24:00Z

## Mission
Design the pure GDScript on-device OMR processor `scripts/omr_processor.gd` for Godot 4 to run 100% self-contained without Python/external dependencies, producing a validated chart dictionary from sheet music images.

## 🔒 My Identity
- Archetype: explorer
- Roles: investigation, synthesis
- Working directory: c:\Users\david\Documents\micgame-3\.agents\teamwork\m4_explorer_2\
- Original parent: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Milestone: Milestone 4: On-Device OMR & Level Alignment

## 🔒 Key Constraints
- Read-only investigation — do NOT implement directly in project source code (scripts/omr_processor.gd directly), but formulate exact GDScript implementation code in reports/proposals for the worker.
- 100% self-contained inside Godot 4 (no Python, no external libraries; works on mobile Android Pixel 7a)
- Adhere to `chart.json` schema (`title`, `bpm`, `time_signature`, `notes`)
- Output structured findings, exact GDScript implementation code proposal, and 5-component handoff report

## Current Parent
- Conversation ID: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Updated: 2026-10-16T20:24:00Z

## Investigation State
- **Explored paths**:
  - `ORIGINAL_REQUEST.md`, `PROJECT.md`, `survey_explorer_3/report.md` (Section 2.2)
  - `tools/generate_test_assets.py` (exact rendering geometry, score dimensions 1600x900, staff line Ys, barlines, notehead parameters)
  - `scripts/note_data.gd` (diatonic step model, Middle C step 28 at Y=360, `step_dy=9.0` in highway vs image rendering geometry)
  - `scripts/highway.gd`, `scripts/main.gd` (chart loading contracts, chord clustering, playback sync)
  - `tests/e2e/e2e_test_utils.py` (`OMRUtils`, `ChartValidator`, `DiatonicMath`, `ScoringEngine`)
  - `tests/e2e/test_tier1_features.py`, `test_tier2_boundaries.py`, `test_tier3_combinations.py`, `test_tier4_scenarios.py`
  - Bundled score images: `assets/scores/piece_1_monophonic.png`, `piece_2_harmony.png`, `piece_3_polyphonic.png`
- **Key findings**:
  - Scores are 1600x900 grayscale images.
  - Grand Staff has Treble lines at Y=[320, 340, 360, 380, 400], Bass lines at Y=[440, 460, 480, 500, 520], staff spacing $S_s = 20$ px, Middle C at Y=420.
  - Horizontal projection histogram via `PackedByteArray` row access completes in ~30 ms in GDScript.
  - Vertical projection of columns across staff region (`y` in [320, 520]) accurately detects barlines and measure boundaries.
  - 2D Summed Area Table (Integral Image) built in GDScript takes ~68 ms, enabling $O(1)$ density queries per candidate box.
  - Testing discrete diatonic steps 14 to 42 (C2 to C6) combined with vertical non-maximum suppression achieves **100% note detection accuracy** (51/51 notes across all 3 test pieces, 0 false positives, 0 false negatives) in ~120 ms per image.
  - Generated chart Dictionary satisfies `ChartValidator.validate_chart_dict()` and is 100% compatible with `NoteData.from_dict()`.
- **Unexplored areas**:
  - None within Milestone 4 OMR processor scope.

## Key Decisions Made
- Chose pure GDScript 2D Summed Area Table (Integral Image) + discrete diatonic step scanning over complex morphological opening loops: achieves 100% accuracy, handles both solid and hollow noteheads (including stemless whole note chords), and executes in ~120 ms on CPU.
- Implemented vertical non-maximum suppression along diatonic steps at the same X coordinate to cleanly eliminate staff line bridges between vertically stacked chord notes.
- Included robust fallbacks for automatic time signature detection (numerator patch inspection) and tempo defaults when options are not provided.
- Created `proposed_omr_processor.gd` in worker-ready format.

## Artifact Index
- `.agents/teamwork/m4_explorer_2/proposed_omr_processor.gd` — Complete, tested GDScript OMR class ready for worker placement into `scripts/omr_processor.gd`.
- `.agents/teamwork/m4_explorer_2/test_omr_prototype.gd` — Headless Godot validation harness testing prototype across all 3 test pieces.
- `.agents/teamwork/m4_explorer_2/verify_proposed.gd` — Standalone Godot verification script for `proposed_omr_processor.gd`.
- `.agents/teamwork/m4_explorer_2/test_chart_validator.py` — Python verification script testing schema against `ChartValidator`.
- `.agents/teamwork/m4_explorer_2/report.md` — Comprehensive technical exploration and design report.
- `.agents/teamwork/m4_explorer_2/handoff.md` — 5-component handoff report.
