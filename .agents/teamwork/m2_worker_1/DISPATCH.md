## 2026-10-16T19:00:21Z
You are m2_worker_1, an implementation worker for Milestone 2: Bundled Test Pieces & Assets.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\m2_worker_1\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
The project index is at: c:\Users\david\Documents\micgame-3\PROJECT.md
Survey explorer report: c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_3\report.md
Project root is: c:\Users\david\Documents\micgame-3

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Your write ownership (exclusive):
- `tools/generate_test_assets.py`
- `assets/models/`
- `assets/test_pieces/`
- `assets/audio/`
- `assets/scores/`
- `assets/charts/`

Your tasks:
1. Read ORIGINAL_REQUEST.md, PROJECT.md, and survey_explorer_3/report.md.
2. Bundle official Spotify Basic Pitch ONNX model:
   - Locate official `nmp.onnx` at:
     `C:\Users\david\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.12_qbz5n2kfra8p0\LocalCache\local-packages\Python312\site-packages\basic_pitch\saved_models\icassp_2022\nmp.onnx`
   - Copy it into `c:\Users\david\Documents\micgame-3\assets\models\nmp.onnx` (verify size is ~230,444 bytes).
3. Implement `tools/generate_test_assets.py`:
   - Follow the exact specification from Section 4 of `survey_explorer_3/report.md` for the 3 test pieces:
     * Piece 1: Monophonic melody ("Ode to Joy", 15 notes, 4/4, 120 BPM, C Major, Treble staff).
     * Piece 2: 2-Part harmony ("Bach Minuet / 2-Part Counterpoint", 16 notes, 3/4, 100 BPM, dual Treble/Bass voices).
     * Piece 3: Polyphonic chordal progression ("Cadence & Triad Progression", 20 notes across 5 four-note chords, 4/4, 80 BPM, C2-C5 range).
   - Use `Pillow` to draw clean, high-contrast score PNG images with staff lines, clefs, and note heads.
   - Use Python standard library `wave` and `numpy` to synthesize uncompressed 16-bit PCM mono 22,050 Hz WAV audio files using additive sine synthesis with attack/decay envelopes.
   - Use standard library `json` to write `ground_truth.json` files adhering to the schema in Section 4.5 of `survey_explorer_3/report.md`.
   - Use `music21` (already installed) or pure MIDI byte writer to generate standard `ground_truth.mid` files.
4. Execute `python tools/generate_test_assets.py` to generate all assets.
5. Also mirror or symlink the audio/score/chart files to `assets/audio/`, `assets/scores/`, and `assets/charts/` for convenient access by Godot scenes.
6. VERIFICATION: You MUST execute the verification commands yourself:
   - Verify all 12 test asset files exist and have non-zero size.
   - Run `python -c "import wave; f = wave.open('assets/test_pieces/piece_1_monophonic/audio.wav'); print(f.getframerate(), f.getnchannels(), f.getsampwidth())"` (must print `22050 1 2`).
   - Run `python tests/e2e/run_all_e2e_tests.py` (verify 230/230 pass).
7. Document your changes and verbatim command outputs in `handoff.md` and report back via send_message.
