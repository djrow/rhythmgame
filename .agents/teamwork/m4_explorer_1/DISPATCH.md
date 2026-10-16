## 2026-10-16T20:13:29Z

You are m4_explorer_1, an exploration agent for Milestone 4: On-Device OMR & Level Alignment.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\m4_explorer_1\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
The project index is at: c:\Users\david\Documents\micgame-3\PROJECT.md
Prior survey report: c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_3\report.md
Asset generator code: c:\Users\david\Documents\micgame-3\tools\generate_test_assets.py
Project root is: c:\Users\david\Documents\micgame-3

Your task:
1. Read ORIGINAL_REQUEST.md, PROJECT.md, survey_explorer_3/report.md (Sections 1 & 5), and inspect tools/generate_test_assets.py and the 3 score images in assets/scores/ (piece_1_monophonic.png, piece_2_harmony.png, piece_3_polyphonic.png).
2. Investigate and design the standalone Python OMR engine `python/omr_engine.py`:
   - Image loading & binarization via OpenCV & NumPy (Otsu threshold, grayscale).
   - Horizontal projection profile to detect staff lines, group into Treble and Bass 5-line staves, estimate staff spacing Ss (~20px).
   - Staff line removal via vertical morphology / run-length erasure to isolate noteheads and stems.
   - Measure barline detection via vertical morphology across staves.
   - Notehead detection via contour/connected components analysis with aspect ratio and area filters.
   - Solid vs hollow classification (fill ratio).
   - Diatonic pitch mapping from vertical centroid relative to staff lines:
     * Treble staff: F5 (line 1, top), D5 (line 2), B4 (line 3), G4 (line 4), E4 (line 5, bottom). Middle C (C4, ledger line).
     * Bass staff: A3 (line 1, top), F3 (line 2), D3 (line 3), B2 (line 4), G2 (line 5, bottom).
     * Full range C2 to C6+ with ledger line support matching MIDI_TO_Y in generate_test_assets.py.
   - Note duration determination: stem presence and flags/beams.
   - Polyphonic chord clustering: group noteheads within delta_x <= 0.6 * Ss into simultaneous chords sharing the same onset.
   - Output structured chart dictionary conforming to `chart.json` schema.
   - CLI execution: `python python/omr_engine.py --score <path> --output <path> --audio <path>`.
3. Investigate and design the automated CLI test harness `tests/test_omr_harness.py`:
   - CLI flags: `--score <path>`, `--ground-truth <path>`, `--min-accuracy 0.85` (default 0.85).
   - If no specific score is passed, evaluate across all 3 bundled test pieces in assets/test_pieces/.
   - Exact matching criteria: pitch_det == pitch_gt and abs(onset_beat_det - onset_beat_gt) <= 0.25 beats.
   - Print structured console report and exit with 0 on >=85% accuracy, 1 on failure.
4. Formulate the exact Python implementation code ready for the Worker.
5. Write your report and `handoff.md` in your working directory and notify the orchestrator via send_message.
