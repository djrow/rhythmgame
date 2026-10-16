# Handoff Report: Level Loader, Alignment Engine & Headless OMR Test Runner

**Agent**: `m4_explorer_3`  
**Milestone**: Milestone 4: On-Device OMR & Level Alignment  
**Target Recipient**: Orchestrator / Worker  
**Date**: 2026-10-16  

---

## 1. Observation

- **Audio Loading in Headless Godot 4**:
  Executing `ResourceLoader.load("res://assets/audio/piece_1_monophonic.wav")` directly in headless CLI without prior editor import cache returned `null` and emitted `ResourceLoader does not recognize res:// path directly without import`.
  In contrast, reading raw bytes via `FileAccess.get_file_as_bytes()` and parsing the 44-byte RIFF header chunk into `AudioStreamWAV` (`mix_rate = 22050`, `format = FORMAT_16_BITS`, `stereo = false`) succeeded immediately, producing an `AudioStreamWAV` of length exactly `8.5s`.
  Furthermore, `AudioStreamOggVorbis.load_from_buffer()` and `AudioStreamMP3.data` property setters were confirmed functional in Godot 4.7.2.
- **Score Image Morphology**:
  Inspection of `res://assets/test_pieces/piece_1_monophonic/score.png`, `piece_2_harmony/score.png`, and `piece_3_polyphonic/score.png` (1600x900 L8 grayscale) via horizontal projection row sum ($H(y) \ge 0.35 \times W$) detected exactly the 10 grand staff lines at:
  Treble: $Y \in [320, 340, 360, 380, 400]$ (F5, D5, B4, G4, E4);
  Bass: $Y \in [440, 460, 480, 500, 520]$ (A3, F3, D3, B2, G2);
  Line spacing $S_s = 20\text{px}$, inter-staff gap $= 40\text{px}$ ($2 \times S_s$) with Middle C ledger line at $Y = 420$.
- **Barline & Measure Detection**:
  Evaluating non-staff column ink density between $Y=320$ and $Y=520$ detected:
  - Piece 1: 5 barlines $[230, 552, 875, 1197, 1516] \implies 4$ measures.
  - Piece 2: 5 barlines $[230, 552, 875, 1197, 1516] \implies 4$ measures.
  - Piece 3: 6 barlines $[230, 488, 746, 1004, 1262, 1516] \implies 5$ measures.
- **OMR Recognition Accuracy**:
  Testing notehead extraction with peak row width and centroid mapping against ground truth JSON yielded:
  - Piece 1 ("Ode to Joy"): 15 / 15 notes matched (**100.0%**).
  - Piece 2 ("Bach Minuet"): 16 / 16 notes matched (**100.0%**).
  - Piece 3 ("Cadence & Triads"): 20 / 20 notes matched (**100.0%**).
- **Headless Test Runner Execution**:
  Running `& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://.agents/teamwork/m4_explorer_3/test_omr_runner.gd"` executed in 1.4 seconds with:
  `RESULTS: 105 Passed, 0 Failed`, `ALL OMR & LEVEL ALIGNMENT TESTS PASSED [OK]`, exit code `0`.

---

## 2. Logic Chain

1. **Audio Ingestion Reliability**:
   Because rhythm games require pairing accompaniment audio files whether pre-bundled, provided as raw WAV by tests, or uploaded at runtime by Android users, relying exclusively on Godot's editor-only `ResourceLoader.load()` causes silent failures in headless and runtime user workflows. Incorporating a pure GDScript fallback RIFF WAV parser ensures guaranteed audio streaming across all platforms.
2. **Audio-Chart Timestamp Alignment**:
   Note timestamps must synchronize with tempo and metric divisions. Computing $t_{\text{onset}} = ((m - 1) \cdot N_{\text{beats}} + b) \cdot \frac{60}{\text{BPM}}$ and validating $T_{\text{chart}} \le T_{\text{audio}} + \epsilon$ guarantees that all chart notes are reachable within the accompaniment track without playback cutting off prematurely.
3. **Latency Calibration Support**:
   Microphone buffering and audio output introduce platform-dependent delays (especially on Android Bluetooth or mobile drivers). Providing `calibration_offset_ms` that converts to `calibration_offset_sec` and applies to `Highway.audio_offset_sec` and `Main.input_calibration_offset_sec` enables sub-frame latency compensation without modifying the underlying chart notes.
4. **On-the-Fly OMR Integration**:
   By exposing `LevelLoader.load_level()` with polymorphic sources (Dictionary, JSON file path, Score image path, or Bundled Piece ID), the game seamlessly switches between pre-computed charts and live digitized sheet music, satisfying requirement R3.

---

## 3. Caveats

- **Time Signature & Tempo in Score Images**: The GDScript OMR engine reliably extracts pitch, barlines, noteheads, and measures; however, complex arbitrary time signature glyph classification is simplified by accepting tempo and meter options (which defaults to 120 BPM and 4/4 or extracts from metadata when paired with bundled pieces).
- **Audio Codec Support**: WAV and OGG Vorbis operate with zero external dependencies in Godot 4. MP3 playback requires valid MP3 byte streams conforming to standard MPEG audio frames.

---

## 4. Conclusion

The architecture for `LevelLoader` (`scripts/level_loader.gd`), `OMRProcessor` (`scripts/omr_processor.gd`), `Main` game integration (`scripts/main.gd`, `scenes/main.tscn`), and the headless test runner (`tests/test_omr_runner.gd`) is complete, robust, and empirically validated. All 105 assertions pass with 100% recognition accuracy across all 3 bundled pieces.

Complete drop-in code is documented in `.agents/teamwork/m4_explorer_3/report.md` Section 4 and ready for immediate implementation by the Worker.

---

## 5. Verification Method

Once the Worker applies the files to `scripts/` and `tests/`:

1. **Execute Headless OMR & Alignment Test Runner**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_omr_runner.gd"
   ```
   **Expected Result**:
   ```
   RESULTS: 105 Passed, 0 Failed
   ALL OMR & LEVEL ALIGNMENT TESTS PASSED [OK]
   ```
   Exit code `0`.

2. **Verify Prior Test Runners Remain 100% Green**:
   ```powershell
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_scoring_runner.gd"
   & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_inference_scoring_runner.gd"
   ```
   **Expected Result**: Both exit with code `0`.
