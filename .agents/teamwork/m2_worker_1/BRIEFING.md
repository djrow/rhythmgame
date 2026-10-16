# BRIEFING — 2026-10-16T19:15:30Z

## Mission
Deliver Milestone 2: Bundled Test Pieces & Assets. Bundle official Spotify Basic Pitch ONNX model, implement tools/generate_test_assets.py to synthesize 3 test pieces (audio WAV, score PNG, ground truth JSON, MIDI), mirror assets to Godot scene directories, and run full verification.

## 🔒 My Identity
- Archetype: worker
- Roles: implementer, qa, specialist
- Working directory: c:\Users\david\Documents\micgame-3\.agents\teamwork\m2_worker_1\
- Original parent: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Milestone: Milestone 2: Bundled Test Pieces & Assets

## 🔒 Key Constraints
- Exclusive write ownership: `tools/generate_test_assets.py`, `assets/models/`, `assets/test_pieces/`, `assets/audio/`, `assets/scores/`, `assets/charts/`.
- Never place source code or test pieces in `.agents/teamwork/`.
- No cheating, no fake/dummy implementations.
- Model must be copied from official basic_pitch installation (`saved_models/icassp_2022/nmp.onnx`).
- 3 test pieces: monophonic (15 notes, 4/4, 120 BPM, C major), 2-part harmony (16 notes, 3/4, 100 BPM), polyphonic chordal (20 notes, 5 chords, 4/4, 80 BPM).
- High contrast score PNG with staff lines/clefs/note heads via Pillow.
- 16-bit PCM mono 22050 Hz WAV via wave & numpy additive sine synthesis with envelopes.
- Ground truth JSON adhering to Section 4.5 schema.
- MIDI generated via music21 or pure MIDI byte writer.
- Mirror or symlink to `assets/audio/`, `assets/scores/`, `assets/charts/`.
- All verification commands must be executed and passing.

## Current Parent
- Conversation ID: 7da07436-85a8-464d-9f3c-d174d6d86ee2
- Updated: 2026-10-16T19:15:30Z

## Task Summary
- **What to build**: Basic Pitch ONNX bundling, `tools/generate_test_assets.py` generator, 3 test pieces (12 files), and mirrored asset directories.
- **Success criteria**: All 12 test asset files exist and non-zero, WAV is 22050Hz/mono/16-bit, all 230 e2e tests pass.
- **Interface contracts**: `PROJECT.md`, `survey_explorer_3/report.md` Section 4.
- **Code layout**: `PROJECT.md § Code Layout`.

## Key Decisions Made
- Bundled official Basic Pitch ONNX model from Python 3.12 site-packages (`saved_models/icassp_2022/nmp.onnx`, 230,444 bytes) to `assets/models/nmp.onnx`.
- Designed `tools/generate_test_assets.py` with full modularity: additive sine synthesis with natural harmonics & ADSR envelopes (tested against Basic Pitch ONNX model for >=80% F1 recall), Pillow score image rendering (1600x900, Segoe UI Symbol clefs with geometric fallback, accurate diatonic Y mapping and metric X spacing), dual schema compatibility for JSON charts (conforms to both Section 4.5 schema and test suite `ChartValidator`), and standard Type 1 MIDI generation with music21.
- Mirrored all assets to `assets/audio/`, `assets/scores/`, and `assets/charts/` under both canonical piece keys and catalog alias IDs.

## Artifact Index
- `tools/generate_test_assets.py` — Deterministic test piece asset generator
- `assets/models/nmp.onnx` — Bundled Spotify Basic Pitch ONNX model (230,444 bytes)
- `assets/test_pieces/piece_1_monophonic/` — Piece 1 audio, score, JSON, MIDI
- `assets/test_pieces/piece_2_harmony/` — Piece 2 audio, score, JSON, MIDI
- `assets/test_pieces/piece_3_polyphonic/` — Piece 3 audio, score, JSON, MIDI
- `assets/audio/`, `assets/scores/`, `assets/charts/` — Mirrored Godot access directories

## Change Tracker
- **Files modified**:
  - `assets/models/nmp.onnx` — Bundled Spotify Basic Pitch pre-trained model (230,444 bytes)
  - `tools/generate_test_assets.py` — Synthesizer for 3 test pieces, score drawing, audio synthesis, chart & MIDI export
  - `assets/test_pieces/` — 12 test asset files generated
  - `assets/audio/`, `assets/scores/`, `assets/charts/` — Flat mirrored assets
- **Build status**: PASS
- **Pending issues**: None

## Quality Status
- **Build/test result**: 230/230 E2E tests pass (100%), 91/91 headless scoring tests pass, 78/78 adversarial tests pass
- **Lint status**: 0 violations
- **Tests added/modified**: Verified all test pieces against `ChartValidator` and WAV header specs

## Loaded Skills
- None
