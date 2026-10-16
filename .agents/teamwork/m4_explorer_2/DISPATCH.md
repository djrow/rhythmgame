## 2026-10-16T20:13:29Z
You are m4_explorer_2, an exploration agent for Milestone 4: On-Device OMR & Level Alignment.
Your working directory is: c:\Users\david\Documents\micgame-3\.agents\teamwork\m4_explorer_2\
The authoritative user specification is at: c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md
The project index is at: c:\Users\david\Documents\micgame-3\PROJECT.md
Prior survey report: c:\Users\david\Documents\micgame-3\.agents\teamwork\survey_explorer_3\report.md
Asset generator code: c:\Users\david\Documents\micgame-3\tools\generate_test_assets.py
Project root is: c:\Users\david\Documents\micgame-3

Your task:
1. Read ORIGINAL_REQUEST.md, PROJECT.md, survey_explorer_3/report.md (Section 2.2), and inspect tools/generate_test_assets.py and the score images in assets/scores/.
2. Investigate and design the pure GDScript on-device OMR processor `scripts/omr_processor.gd`:
   - Must run 100% self-contained inside Godot 4 without Python or external dependencies (critical for on-device mobile execution on Android Pixel 7a).
   - Uses `Image.load_from_file()` and `img.convert(Image.FORMAT_L8)` (grayscale).
   - Fast horizontal projection histogram using `PackedByteArray` row access (`raw_data[y * width + x] < 128` for dark ink).
   - Staff line detection and pairing into Grand Staff (Treble and Bass staves).
   - Barline detection to segment measures.
   - Notehead detection using horizontal and vertical density profiling or connected pixel clustering.
   - Diatonic pitch mapping from vertical Y position to MIDI pitch using diatonic step calculations matching `note_data.gd`.
   - Chord clustering for polyphonic notes occurring at the same horizontal beat location.
   - Generates structured chart Dictionary adhering to `chart.json` schema (`title`, `bpm`, `time_signature`, `notes`).
3. Formulate the exact GDScript implementation code ready for the Worker.
4. Write your report and `handoff.md` in your working directory and notify the orchestrator via send_message.
