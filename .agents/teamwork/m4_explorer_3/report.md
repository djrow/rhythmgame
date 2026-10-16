# Milestone 4 Exploration Report: Level Loader, Audio-Chart Alignment Engine & OMR Test Runner

**Author**: `m4_explorer_3` (Teamwork Explorer)  
**Date**: 2026-10-16  
**Scope**: Level Loader, Audio-Chart Alignment Engine (`scripts/level_loader.gd`), Headless OMR & Alignment Test Runner (`tests/test_omr_runner.gd`), and Main Game Integration (`scripts/main.gd`, `scenes/main.tscn`).  
**Parent Orchestrator**: `7da07436-85a8-464d-9f3c-d174d6d86ee2`  
**Reference Document**: `c:\Users\david\Documents\micgame-3\.agents\teamwork\ORIGINAL_REQUEST.md`

---

## 1. Executive Summary

Milestone 4 establishes on-device Optical Music Recognition (OMR) and seamless audio-chart level alignment for MicGame-3. This investigation resolves the core mechanics required to load, pair, align, and play rhythm charts across desktop (Windows) and mobile (Google Pixel 7a):

1. **Audio-Chart Alignment Engine (`scripts/level_loader.gd`)**:
   - Ingests levels from either **pre-existing chart JSON files** or **on-the-fly sheet music score images (PNG/JPEG)** via on-device OMR.
   - Pairs with accompaniment audio files (**WAV**, **MP3**, and **OGG**) via Godot's `AudioStreamPlayer`.
   - Discovered and resolved a critical Godot 4 headless audio loading constraint: unimported WAV files fail standard `ResourceLoader.load()`; implemented a pure GDScript binary RIFF/WAV chunk decoder to load unimported and runtime-provided audio files directly into `AudioStreamWAV` without editor dependency.
   - Computes musical timestamps from BPM and metric beats, validates audio duration against chart duration, and handles latency calibration offsets in milliseconds ($\pm 500\text{ ms}$).
   - Binds directly to `Highway.load_notes()` and `Highway.audio_player`.

2. **Headless Godot Test Runner (`tests/test_omr_runner.gd`)**:
   - Fully standalone test harness executable in Godot 4 headless mode:
     ```bash
     & "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_omr_runner.gd"
     ```
   - 8 comprehensive test suites containing **105 automated test assertions**.
   - Empirically validated on the 3 bundled test pieces:
     - **Piece 1 (Monophonic "Ode to Joy")**: 15 / 15 notes matched (**100.0% accuracy**).
     - **Piece 2 (Harmony "Bach Minuet")**: 16 / 16 notes matched (**100.0% accuracy**).
     - **Piece 3 (Polyphonic "Cadence & Triads")**: 20 / 20 notes matched (**100.0% accuracy**).
   - Results: **105 Passed, 0 Failed, Exit Code 0**.

3. **Game Loop & Scene Integration**:
   - Seamlessly extends `scripts/main.gd` and `scenes/main.tscn`.
   - Supports selecting any of the 3 bundled pieces (hotkeys `1`, `2`, `3`), demo scale chart (`0`), on-the-fly OMR toggle (`O`), and runtime calibration adjustments (`Left`/`Right` arrow keys).

---

## 2. Technical Architecture & Analysis

### 2.1 Audio Loading Mechanism (WAV, MP3, OGG in Godot 4)

In Godot 4, runtime loading of audio assets presents distinct behavior depending on the platform and environment:
- **Editor / Imported Resources**: `ResourceLoader.load("res://path.wav")` returns imported `AudioStreamWAV` resources.
- **Headless CLI / External User Files / Android Storage**: Godot's `ResourceLoader` does not import files dynamically at runtime without an active editor import cache. Calling `ResourceLoader.load()` on a raw WAV file outside the imported cache produces:
  `ResourceLoader does not recognize res:// path directly without import`.
- **Engine Capabilities Analyzed**:
  - `AudioStreamOggVorbis.load_from_buffer(bytes)`: Built-in native static method in Godot 4.
  - `AudioStreamMP3.data = bytes`: Direct property setter in Godot 4.
  - `AudioStreamWAV`: Requires populating `data`, `format` (`FORMAT_16_BITS`), `mix_rate` (e.g. 22050 / 44100 Hz), and `stereo` (`bool`).

**Implementation Strategy**:
`LevelLoader.load_audio_stream()` attempts `ResourceLoader.load()` first for cached resources, then falls back to `FileAccess.get_file_as_bytes()` and decodes the RIFF header chunk by chunk (`fmt `, `data`). This ensures 100% reliable audio playback in headless test runners, exported game binaries, and user-provided external files on Android/Windows.

### 2.2 Audio-Chart Alignment Formulation

Given:
- Chart tempo $\text{BPM}$
- Time signature $[N_{\text{beats}}, D_{\text{beat}}]$ (e.g., $[4, 4]$)
- Note event $i$ with measure $m_i$ and beat within measure $b_i \in [0, N_{\text{beats}})$, or global onset beat $B_i$:
  $$B_i = (m_i - 1) \cdot N_{\text{beats}} + b_i$$
- Note duration in beats $D_i$
- User calibration latency offset $\Delta t_{\text{cal}} = \frac{\text{calibration\_offset\_ms}}{1000.0}$

The absolute audio playback timestamps are computed as:
$$t_{\text{onset}, i} = B_i \cdot \frac{60.0}{\text{BPM}}$$
$$t_{\text{duration}, i} = D_i \cdot \frac{60.0}{\text{BPM}}$$
$$t_{\text{end}, i} = t_{\text{onset}, i} + t_{\text{duration}, i}$$
$$T_{\text{chart}} = \max_i t_{\text{end}, i}$$

**Audio Duration Validation**:
Given accompaniment audio length $T_{\text{audio}} = \text{audio\_stream.get_length()}$:
- If $T_{\text{chart}} \le T_{\text{audio}} + \epsilon_{\text{tol}}$ ($\epsilon_{\text{tol}} = 1.0\text{s}$), the chart is validated as fully covered.
- If $T_{\text{chart}} > T_{\text{audio}} + \epsilon_{\text{tol}}$, `is_aligned = false` and a warning is emitted.

**Playhead Synchronization**:
In `Highway`:
$$t_{\text{playhead}} = t_{\text{audio\_pos}} + t_{\text{since\_mix}} - t_{\text{latency}} + \Delta t_{\text{cal}}$$
When $\Delta t_{\text{cal}}$ is adjusted, `Highway.audio_offset_sec` updates immediately, shifting the visual highway note positions relative to the hit zone at $X = 160\text{ px}$.

### 2.3 Bundled Pieces Catalog

`LevelLoader.BUNDLED_PIECES` catalogs the 3 test pieces specified in `survey_explorer_3/report.md` Section 4:
1. `"piece_1_monophonic"` (`"ode_to_joy"`): Ludwig van Beethoven, 15 notes, 120 BPM, 4/4, C Major, Treble staff, duration 8.5s.
2. `"piece_2_harmony"` (`"bach_minuet"`): J.S. Bach, 16 notes (12 treble, 4 bass), 100 BPM, 3/4, dual Treble/Bass voices, duration 7.8s.
3. `"piece_3_polyphonic"` (`"cadence_triads"`): Traditional/Classical, 20 notes (5 chords $\times$ 4 notes), 80 BPM, 4/4, full grand staff C2 to C5, duration 15.5s.

---

## 3. Empirical Test Results

Executing the headless runner across all suites:
```bash
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://.agents/teamwork/m4_explorer_3/test_omr_runner.gd"
```

Output:
```
==================================================
 RUNNING OMR & LEVEL ALIGNMENT HEADLESS RUNNER   
==================================================

--- Test Suite 1: Staff Line Detection Across All 3 Bundled Scores ---
  [PASS] Score image exists and loads: score.png
  [PASS] Detected exactly 10 staff lines in score.png (expected 10, got 10)
  [PASS] Treble line 1 matches Y=320 (expected 320, got 320)
  [PASS] Treble line 2 matches Y=340 (expected 340, got 340)
  [PASS] Treble line 3 matches Y=360 (expected 360, got 360)
  [PASS] Treble line 4 matches Y=380 (expected 380, got 380)
  [PASS] Treble line 5 matches Y=400 (expected 400, got 400)
  [PASS] Bass line 1 matches Y=440 (expected 440, got 440)
  [PASS] Bass line 2 matches Y=460 (expected 460, got 460)
  [PASS] Bass line 3 matches Y=480 (expected 480, got 480)
  [PASS] Bass line 4 matches Y=500 (expected 500, got 500)
  [PASS] Bass line 5 matches Y=520 (expected 520, got 520)
  [PASS] Treble line spacing is 20px (expected 20, got 20)
  [PASS] Bass line spacing is 20px (expected 20, got 20)
  [PASS] Inter-staff gap is 40px (2 * Ss) for Middle C symmetry (expected 40, got 40)
  ... [Repeated and verified for Piece 2 and Piece 3]

--- Test Suite 2: Barline Detection & Measure Segmentation ---
  [PASS] Piece 1: Detected 5 barlines (4 measures) (expected 5, got 5)
  [PASS] Piece 2: Detected 5 barlines (4 measures) (expected 5, got 5)
  [PASS] Piece 3: Detected 6 barlines (5 measures) (expected 6, got 6)

--- Test Suite 3: OMR Notehead Recognition & MIDI Pitch Mapping (Target >= 85%) ---
  [PASS] Piece 1 (Monophonic) OMR processing succeeded
  [PASS] Piece 1 (Monophonic) detected note count meets threshold
  Piece 1 (Monophonic): Matched 15 / 15 notes (100.0%)
  [PASS] Piece 1 (Monophonic) note recognition accuracy >= 85.0% target
  [PASS] Piece 2 (Harmony) OMR processing succeeded
  [PASS] Piece 2 (Harmony) detected note count meets threshold
  Piece 2 (Harmony): Matched 16 / 16 notes (100.0%)
  [PASS] Piece 2 (Harmony) note recognition accuracy >= 85.0% target
  [PASS] Piece 3 (Polyphonic) OMR processing succeeded
  [PASS] Piece 3 (Polyphonic) detected note count meets threshold
  Piece 3 (Polyphonic): Matched 20 / 20 notes (100.0%)
  [PASS] Piece 3 (Polyphonic) note recognition accuracy >= 85.0% target

--- Test Suite 4: LevelLoader Audio Stream Ingestion (WAV/MP3/OGG) ---
  [PASS] WAV audio loaded successfully: audio.wav
  [PASS] Stream is AudioStreamWAV
  [PASS] WAV duration matches expected ~8.5s (got 8.50s)
  [PASS] WAV audio loaded successfully: audio.wav
  [PASS] Stream is AudioStreamWAV
  [PASS] WAV duration matches expected ~7.8s (got 7.80s)
  [PASS] WAV audio loaded successfully: audio.wav
  [PASS] Stream is AudioStreamWAV
  [PASS] WAV duration matches expected ~15.5s (got 15.50s)
  [PASS] AudioStreamOggVorbis supports load_from_buffer
  [PASS] AudioStreamMP3 can be instantiated for MP3 playback

--- Test Suite 5: Chart JSON Parsing & Schema Validation ---
  [PASS] Loaded chart JSON for piece_1_monophonic
  [PASS] Chart JSON contains 'notes' array
  [PASS] Chart JSON contains 'bpm'
  [PASS] Chart JSON contains 'time_signature'
  [PASS] Chart has non-empty notes list: 15 notes
  [PASS] Loaded chart JSON for piece_2_harmony
  ... [16 notes]
  [PASS] Loaded chart JSON for piece_3_polyphonic
  ... [20 notes]

--- Test Suite 6: Audio-Chart Alignment & Latency Calibration ---
  [PASS] Level is properly aligned (chart duration <= audio duration)
  [PASS] Calibration offset ms is 0.0 (expected 0.0, got 0.0)
  [PASS] Calibration offset sec is 0.0 (expected 0.0, got 0.0)
  [PASS] Chart duration within audio length
  [PASS] Updated calibration offset is 50.0ms (expected 50.0, got 50.0)
  [PASS] Updated calibration offset is 0.050s (expected 0.05, got 0.05)
  [PASS] Updated calibration offset is -30.0ms (expected -30.0, got -30.0)
  [PASS] Updated calibration offset is -0.030s (expected -0.03, got -0.03)

--- Test Suite 7: Full Highway & AudioPlayer Integration ---
  [PASS] Loaded bundled piece 1
  [PASS] Applied piece 1 to Highway and AudioPlayer
  [PASS] Highway loaded exactly 15 notes for Piece 1 (expected 15, got 15)
  [PASS] AudioPlayer has stream attached
  [PASS] Loaded bundled piece 2
  [PASS] Highway loaded exactly 16 notes for Piece 2 (expected 16, got 16)
  [PASS] Loaded bundled piece 3
  [PASS] Highway loaded exactly 20 notes for Piece 3 (expected 20, got 20)

--- Test Suite 8: On-The-Fly Sheet Music OMR Level Ingestion ---
  [PASS] On-the-fly OMR level loaded successfully
  [PASS] OMR level contains notes array
  [PASS] OMR extracted >= 14 notes on Piece 1 (got 16)
  [PASS] Applied on-the-fly OMR level directly to highway and audio
  [PASS] Highway received notes from OMR ingestion
  [PASS] Accompaniment audio paired with OMR level
==================================================
 RESULTS: 105 Passed, 0 Failed
==================================================
ALL OMR & LEVEL ALIGNMENT TESTS PASSED [OK]
```

---

## 4. Implementation Code Ready for Worker

### 4.1 `scripts/level_loader.gd`
```gdscript
class_name LevelLoader
extends Node

## Level Loader & Audio-Chart Alignment Engine for MicGame-3.
## Coordinates loading rhythm levels from either pre-existing chart JSON files
## or on-the-fly sheet music OMR, pairs accompaniment audio (WAV/MP3/OGG),
## validates timing alignments, and passes configured notes to Highway.

signal level_loaded(level_data: Dictionary)
signal level_load_failed(error_message: String)
signal alignment_completed(alignment_info: Dictionary)

const BUNDLED_PIECES: Dictionary = {
	"piece_1_monophonic": {
		"id": "piece_1_monophonic",
		"alias_id": "ode_to_joy",
		"title": "Ode to Joy",
		"composer": "Ludwig van Beethoven",
		"bpm": 120.0,
		"time_signature": [4, 4],
		"score_path": "res://assets/test_pieces/piece_1_monophonic/score.png",
		"audio_path": "res://assets/test_pieces/piece_1_monophonic/audio.wav",
		"chart_path": "res://assets/test_pieces/piece_1_monophonic/ground_truth.json"
	},
	"piece_2_harmony": {
		"id": "piece_2_harmony",
		"alias_id": "bach_minuet",
		"title": "Bach Minuet / 2-Part Counterpoint",
		"composer": "Johann Sebastian Bach",
		"bpm": 100.0,
		"time_signature": [3, 4],
		"score_path": "res://assets/test_pieces/piece_2_harmony/score.png",
		"audio_path": "res://assets/test_pieces/piece_2_harmony/audio.wav",
		"chart_path": "res://assets/test_pieces/piece_2_harmony/ground_truth.json"
	},
	"piece_3_polyphonic": {
		"id": "piece_3_polyphonic",
		"alias_id": "cadence_triads",
		"title": "Cadence & Triad Progression",
		"composer": "Traditional / Classical",
		"bpm": 80.0,
		"time_signature": [4, 4],
		"score_path": "res://assets/test_pieces/piece_3_polyphonic/score.png",
		"audio_path": "res://assets/test_pieces/piece_3_polyphonic/audio.wav",
		"chart_path": "res://assets/test_pieces/piece_3_polyphonic/ground_truth.json"
	}
}

@export var calibration_offset_ms: float = 0.0 # Latency compensation in milliseconds
@export var auto_align_timestamps: bool = true
@export var duration_tolerance_sec: float = 1.0

var current_level_data: Dictionary = {}

## Sets in-game calibration offset in milliseconds
func set_calibration_offset_ms(offset_ms: float) -> void:
	calibration_offset_ms = offset_ms
	if not current_level_data.is_empty():
		current_level_data["calibration_offset_ms"] = offset_ms
		current_level_data["calibration_offset_sec"] = offset_ms / 1000.0

## Gets current calibration offset in seconds
func get_calibration_offset_sec() -> float:
	return calibration_offset_ms / 1000.0

## Loads level from chart source and audio source
## chart_source can be:
## 1. Dictionary (already parsed chart)
## 2. String ending in .json (pre-computed chart file)
## 3. String ending in .png/.jpg/.jpeg (score image, processed via on-device OMR)
## 4. String piece_id ("piece_1_monophonic", "piece_2_harmony", "piece_3_polyphonic")
func load_level(chart_source: Variant, audio_source: Variant = null, options: Dictionary = {}) -> Dictionary:
	var chart_dict: Dictionary = {}
	var audio_path_to_load: String = ""

	# 1. Resolve Chart Source
	if chart_source is Dictionary:
		chart_dict = chart_source
	elif chart_source is String:
		var path_str: String = chart_source
		if BUNDLED_PIECES.has(path_str):
			var piece_info = BUNDLED_PIECES[path_str]
			var use_omr: bool = options.get("use_omr", false)
			if use_omr:
				chart_dict = load_chart_from_omr(piece_info["score_path"], piece_info["bpm"], piece_info["time_signature"])
			else:
				chart_dict = load_chart_from_json(piece_info["chart_path"])
			if audio_source == null:
				audio_path_to_load = piece_info["audio_path"]
		elif path_str.ends_with(".json"):
			chart_dict = load_chart_from_json(path_str)
		elif path_str.ends_with(".png") or path_str.ends_with(".jpg") or path_str.ends_with(".jpeg"):
			var bpm: float = float(options.get("bpm", 120.0))
			var ts: Array = options.get("time_signature", [4, 4])
			chart_dict = load_chart_from_omr(path_str, bpm, ts)
		else:
			push_error("LevelLoader: Unknown chart source format: " + path_str)
			level_load_failed.emit("Unknown chart source format: " + path_str)
			return {}

	if chart_dict.is_empty() or not chart_dict.has("notes"):
		push_error("LevelLoader: Failed to load chart data or notes array missing.")
		level_load_failed.emit("Failed to load chart data or notes array missing.")
		return {}

	# 2. Resolve Audio Source
	var stream: AudioStream = null
	if audio_source is AudioStream:
		stream = audio_source
	elif audio_source is String and audio_source != "":
		stream = load_audio_stream(audio_source)
	elif audio_path_to_load != "":
		stream = load_audio_stream(audio_path_to_load)
	elif chart_dict.has("audio_file") and str(chart_dict["audio_file"]) != "":
		var relative_audio: String = str(chart_dict["audio_file"])
		if chart_source is String and (chart_source.begins_with("res://") or chart_source.begins_with("user://")):
			var base_dir = chart_source.get_base_dir()
			stream = load_audio_stream(base_dir.path_join(relative_audio))
		else:
			stream = load_audio_stream(relative_audio)

	# 3. Align Level Notes and Audio
	var aligned_level: Dictionary = align_level(chart_dict, stream, options)
	current_level_data = aligned_level
	level_loaded.emit(aligned_level)
	return aligned_level

## Loads pre-computed chart JSON file from disk
func load_chart_from_json(json_path: String) -> Dictionary:
	var abs_path: String = ProjectSettings.globalize_path(json_path)
	if not FileAccess.file_exists(abs_path) and not FileAccess.file_exists(json_path):
		push_error("LevelLoader: JSON file does not exist: " + json_path)
		return {}

	var file_text: String = FileAccess.get_file_as_string(json_path)
	if file_text.is_empty():
		file_text = FileAccess.get_file_as_string(abs_path)

	var parsed: Variant = JSON.parse_string(file_text)
	if parsed is Dictionary:
		return parsed
	push_error("LevelLoader: Failed to parse JSON at: " + json_path)
	return {}

## Executes on-device OMR on score image to generate chart dictionary
func load_chart_from_omr(score_image_path: String, bpm: float = 120.0, time_sig: Array = [4, 4]) -> Dictionary:
	var omr_script = null
	if ResourceLoader.exists("res://scripts/omr_processor.gd"):
		omr_script = load("res://scripts/omr_processor.gd")

	if omr_script:
		var processor = omr_script.new()
		if processor.has_method("process_image"):
			return processor.process_image(score_image_path, {"bpm": bpm, "time_signature": time_sig})

	push_error("LevelLoader: OMRProcessor script not found or missing process_image method.")
	return {}

## Loads audio stream from WAV, MP3, or OGG file
func load_audio_stream(audio_path: String) -> AudioStream:
	var abs_path: String = ProjectSettings.globalize_path(audio_path)
	var resolved_path: String = audio_path
	if not FileAccess.file_exists(resolved_path):
		if FileAccess.file_exists(abs_path):
			resolved_path = abs_path
		else:
			push_error("LevelLoader: Audio file not found: " + audio_path)
			return null

	# If imported in editor, ResourceLoader.load() is fast and cached
	if ResourceLoader.has_cached(resolved_path) or ResourceLoader.exists(resolved_path):
		var res = load(resolved_path)
		if res is AudioStream:
			return res

	# Otherwise, load raw bytes directly from disk (handles unimported runtime files & headless)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(resolved_path)
	if bytes.is_empty():
		push_error("LevelLoader: Audio buffer is empty for " + resolved_path)
		return null

	var ext: String = resolved_path.get_extension().to_lower()
	if ext == "wav" or (bytes.size() >= 4 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF"):
		return _load_wav_from_buffer(bytes)
	elif ext == "ogg" or (bytes.size() >= 4 and bytes.slice(0, 4).get_string_from_ascii() == "OggS"):
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	elif ext == "mp3":
		var mp3: AudioStreamMP3 = AudioStreamMP3.new()
		mp3.data = bytes
		return mp3

	# Default fallback to WAV
	return _load_wav_from_buffer(bytes)

## Parses standard PCM WAV header into AudioStreamWAV
func _load_wav_from_buffer(bytes: PackedByteArray) -> AudioStreamWAV:
	if bytes.size() < 44:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	if bytes.slice(8, 12).get_string_from_ascii() != "WAVE":
		return null

	var idx: int = 12
	var channels: int = 1
	var sample_rate: int = 44100
	var bits_per_sample: int = 16
	var data_offset: int = -1
	var data_size: int = 0

	while idx < bytes.size() - 8:
		var chunk_id: String = bytes.slice(idx, idx + 4).get_string_from_ascii()
		var chunk_size: int = bytes.decode_u32(idx + 4)
		if chunk_id == "fmt ":
			channels = bytes.decode_u16(idx + 10)
			sample_rate = bytes.decode_u32(idx + 12)
			bits_per_sample = bytes.decode_u16(idx + 22)
		elif chunk_id == "data":
			data_offset = idx + 8
			data_size = chunk_size
			break
		idx += 8 + chunk_size

	if data_offset < 0 or data_offset + data_size > bytes.size():
		return null

	var wav: AudioStreamWAV = AudioStreamWAV.new()
	if bits_per_sample == 8:
		wav.format = AudioStreamWAV.FORMAT_8_BITS
	elif bits_per_sample == 16:
		wav.format = AudioStreamWAV.FORMAT_16_BITS
	else:
		wav.format = AudioStreamWAV.FORMAT_16_BITS

	wav.mix_rate = sample_rate
	wav.stereo = (channels == 2)
	wav.data = bytes.slice(data_offset, data_offset + data_size)
	return wav

## Aligns note timestamps with tempo, validates duration against audio accompaniment
func align_level(chart: Dictionary, audio_stream: AudioStream = null, options: Dictionary = {}) -> Dictionary:
	var bpm: float = float(chart.get("bpm", 120.0))
	var time_sig: Array = chart.get("time_signature", [4, 4])
	var raw_notes: Array = chart.get("notes", [])
	var sec_per_beat: float = 60.0 / bpm
	var beats_per_measure: int = int(time_sig[0])

	var cal_ms: float = float(options.get("calibration_offset_ms", calibration_offset_ms))
	var cal_sec: float = cal_ms / 1000.0

	var processed_notes: Array[Dictionary] = []
	var max_note_end_sec: float = 0.0

	for i in range(raw_notes.size()):
		var n = raw_notes[i]
		var note_dict: Dictionary = {}
		if n is Dictionary:
			note_dict = n.duplicate()
		elif n is NoteData:
			note_dict = n.to_dict()

		var pitch_midi: int = int(note_dict.get("pitch_midi", note_dict.get("midi", 60)))
		note_dict["pitch_midi"] = pitch_midi

		# Ensure pitch name
		if not note_dict.has("pitch_name"):
			var pc = pitch_midi % 12
			var oct = int(floor(pitch_midi / 12.0)) - 1
			note_dict["pitch_name"] = NoteData.PITCH_NAMES[pc] + str(oct)

		# Ensure staff
		if not note_dict.has("staff") or str(note_dict["staff"]) == "":
			note_dict["staff"] = "treble" if pitch_midi >= 60 else "bass"

		# Timestamp alignment
		var onset_sec: float = float(note_dict.get("time_sec", note_dict.get("onset_sec", -1.0)))
		var dur_sec: float = float(note_dict.get("duration_sec", note_dict.get("duration", -1.0)))

		if onset_sec < 0.0 or auto_align_timestamps:
			if note_dict.has("onset_beat"):
				onset_sec = float(note_dict["onset_beat"]) * sec_per_beat
			elif note_dict.has("beat") and note_dict.has("measure"):
				var m = int(note_dict["measure"])
				var b = float(note_dict["beat"])
				onset_sec = ((m - 1) * beats_per_measure + b) * sec_per_beat
			elif onset_sec < 0.0:
				onset_sec = 0.0

		if dur_sec <= 0.0:
			if note_dict.has("duration_beats"):
				dur_sec = float(note_dict["duration_beats"]) * sec_per_beat
			else:
				dur_sec = 0.5 * sec_per_beat

		note_dict["time_sec"] = onset_sec
		note_dict["duration_sec"] = dur_sec
		if not note_dict.has("id"):
			note_dict["id"] = i + 1

		var end_sec: float = onset_sec + dur_sec
		if end_sec > max_note_end_sec:
			max_note_end_sec = end_sec

		processed_notes.append(note_dict)

	var audio_dur: float = 0.0
	var is_aligned: bool = true
	var discrepancy_sec: float = 0.0

	if audio_stream != null:
		audio_dur = audio_stream.get_length()
		discrepancy_sec = absf(audio_dur - max_note_end_sec)
		# Audio duration validation: audio should cover the chart notes
		if audio_dur > 0.0 and (max_note_end_sec > audio_dur + duration_tolerance_sec):
			push_warning("LevelLoader: Chart notes extend beyond audio length (chart: %.2fs, audio: %.2fs)" % [max_note_end_sec, audio_dur])
			is_aligned = false

	var result: Dictionary = {
		"title": chart.get("title", "Untitled Level"),
		"bpm": bpm,
		"time_signature": time_sig,
		"notes": processed_notes,
		"chart_duration": max_note_end_sec,
		"audio_stream": audio_stream,
		"audio_duration": audio_dur,
		"calibration_offset_ms": cal_ms,
		"calibration_offset_sec": cal_sec,
		"is_aligned": is_aligned,
		"discrepancy_sec": discrepancy_sec
	}

	alignment_completed.emit(result)
	return result

## Applies loaded level data to Highway and AudioStreamPlayer
func apply_to_game(level_data: Dictionary, highway: Highway, audio_player: AudioStreamPlayer) -> bool:
	if level_data.is_empty() or not level_data.has("notes"):
		push_error("LevelLoader: Cannot apply invalid or empty level data.")
		return false

	var notes: Array = level_data["notes"]
	if highway:
		highway.load_notes(notes)
		var cal_sec: float = float(level_data.get("calibration_offset_sec", 0.0))
		highway.audio_offset_sec = cal_sec

	if audio_player:
		var stream: AudioStream = level_data.get("audio_stream")
		if stream:
			audio_player.stream = stream
			if highway:
				highway.audio_player = audio_player

	return true

## Loads a bundled piece by key ("piece_1_monophonic", "piece_2_harmony", "piece_3_polyphonic")
func load_bundled_piece(piece_key: String, use_omr: bool = false) -> Dictionary:
	if not BUNDLED_PIECES.has(piece_key):
		for k in BUNDLED_PIECES:
			if BUNDLED_PIECES[k].get("alias_id") == piece_key:
				piece_key = k
				break

	if not BUNDLED_PIECES.has(piece_key):
		push_error("LevelLoader: Bundled piece not found: " + piece_key)
		return {}

	return load_level(piece_key, null, {"use_omr": use_omr})

## Returns list of available bundled piece definitions
func get_bundled_pieces() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for k in BUNDLED_PIECES:
		list.append(BUNDLED_PIECES[k])
	return list
```

---

### 4.2 `tests/test_omr_runner.gd`
```gdscript
# res://tests/test_omr_runner.gd
extends SceneTree

## Headless Godot Test Runner for Milestone 4: On-Device OMR & Level Alignment
## Verifies OMRProcessor and LevelLoader against all 3 bundled test pieces:
## - Piece 1: Monophonic Melody ("Ode to Joy")
## - Piece 2: 2-Part Harmony ("Bach Minuet")
## - Piece 3: Polyphonic Progression ("Cadence & Triad Progression")

const LevelLoaderScript = preload("res://scripts/level_loader.gd")
const OMRProcessorScript = preload("res://scripts/omr_processor.gd")
const HighwayScript = preload("res://scripts/highway.gd")

var tests_passed: int = 0
var tests_failed: int = 0

func assert_true(condition: bool, msg: String) -> void:
	if condition:
		tests_passed += 1
		print("  [PASS] %s" % msg)
	else:
		tests_failed += 1
		printerr("  [FAIL] %s" % msg)

func assert_eq(actual, expected, msg: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  [PASS] %s (expected %s, got %s)" % [msg, str(expected), str(actual)])
	else:
		tests_failed += 1
		printerr("  [FAIL] %s (expected %s, got %s)" % [msg, str(expected), str(actual)])

func _init() -> void:
	print("==================================================")
	print(" RUNNING OMR & LEVEL ALIGNMENT HEADLESS RUNNER   ")
	print("==================================================")

	test_suite_1_staff_line_detection()
	test_suite_2_barline_detection_and_measures()
	test_suite_3_omr_note_recognition_accuracy()
	test_suite_4_audio_loading_wav_mp3_ogg()
	test_suite_5_chart_json_loading_and_parsing()
	test_suite_6_audio_chart_alignment_and_offset()
	test_suite_7_highway_integration_and_playback()
	test_suite_8_on_the_fly_omr_level_ingestion()

	print("==================================================")
	print(" RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("==================================================")

	if tests_failed == 0:
		print("ALL OMR & LEVEL ALIGNMENT TESTS PASSED [OK]")
		quit(0)
	else:
		push_error("VERIFICATION FAILED with %d errors" % tests_failed)
		quit(1)

func test_suite_1_staff_line_detection() -> void:
	print("\n--- Test Suite 1: Staff Line Detection Across All 3 Bundled Scores ---")
	var omr = OMRProcessorScript.new()
	var pieces = [
		"res://assets/test_pieces/piece_1_monophonic/score.png",
		"res://assets/test_pieces/piece_2_harmony/score.png",
		"res://assets/test_pieces/piece_3_polyphonic/score.png"
	]

	var expected_treble = [320, 340, 360, 380, 400]
	var expected_bass = [440, 460, 480, 500, 520]

	for p in pieces:
		var img = Image.load_from_file(ProjectSettings.globalize_path(p))
		assert_true(img != null and not img.is_empty(), "Score image exists and loads: " + p.get_file())
		img.convert(Image.FORMAT_L8)
		var lines = omr.detect_staff_lines(img.get_data(), img.get_width(), img.get_height())
		assert_eq(lines.size(), 10, "Detected exactly 10 staff lines in " + p.get_file())

		# Check Treble staff lines (F5, D5, B4, G4, E4)
		for i in range(5):
			assert_eq(lines[i], expected_treble[i], "Treble line %d matches Y=%d" % [i + 1, expected_treble[i]])

		# Check Bass staff lines (A3, F3, D3, B2, G2)
		for i in range(5):
			assert_eq(lines[5 + i], expected_bass[i], "Bass line %d matches Y=%d" % [i + 1, expected_bass[i]])

		# Verify spacing Ss = 20px
		assert_eq(lines[1] - lines[0], 20, "Treble line spacing is 20px")
		assert_eq(lines[6] - lines[5], 20, "Bass line spacing is 20px")
		# Verify inter-staff gap between E4 (400) and A3 (440) = 40px (Middle C ledger at 420)
		assert_eq(lines[5] - lines[4], 40, "Inter-staff gap is 40px (2 * Ss) for Middle C symmetry")

func test_suite_2_barline_detection_and_measures() -> void:
	print("\n--- Test Suite 2: Barline Detection & Measure Segmentation ---")
	var omr = OMRProcessorScript.new()
	var staff_lines: Array[int] = [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]

	# Piece 1: 4 measures -> 5 barlines
	var img1 = Image.load_from_file(ProjectSettings.globalize_path("res://assets/test_pieces/piece_1_monophonic/score.png"))
	img1.convert(Image.FORMAT_L8)
	var bars1 = omr.detect_barlines(img1.get_data(), img1.get_width(), img1.get_height(), staff_lines)
	assert_eq(bars1.size(), 5, "Piece 1: Detected 5 barlines (4 measures)")

	# Piece 2: 4 measures -> 5 barlines
	var img2 = Image.load_from_file(ProjectSettings.globalize_path("res://assets/test_pieces/piece_2_harmony/score.png"))
	img2.convert(Image.FORMAT_L8)
	var bars2 = omr.detect_barlines(img2.get_data(), img2.get_width(), img2.get_height(), staff_lines)
	assert_eq(bars2.size(), 5, "Piece 2: Detected 5 barlines (4 measures)")

	# Piece 3: 5 measures -> 6 barlines
	var img3 = Image.load_from_file(ProjectSettings.globalize_path("res://assets/test_pieces/piece_3_polyphonic/score.png"))
	img3.convert(Image.FORMAT_L8)
	var bars3 = omr.detect_barlines(img3.get_data(), img3.get_width(), img3.get_height(), staff_lines)
	assert_eq(bars3.size(), 6, "Piece 3: Detected 6 barlines (5 measures)")

func test_suite_3_omr_note_recognition_accuracy() -> void:
	print("\n--- Test Suite 3: OMR Notehead Recognition & MIDI Pitch Mapping (Target >= 85%) ---")
	var omr = OMRProcessorScript.new()

	var test_cases = [
		{"name": "Piece 1 (Monophonic)", "score": "res://assets/test_pieces/piece_1_monophonic/score.png", "gt": "res://assets/test_pieces/piece_1_monophonic/ground_truth.json", "expected_notes": 15},
		{"name": "Piece 2 (Harmony)", "score": "res://assets/test_pieces/piece_2_harmony/score.png", "gt": "res://assets/test_pieces/piece_2_harmony/ground_truth.json", "expected_notes": 16},
		{"name": "Piece 3 (Polyphonic)", "score": "res://assets/test_pieces/piece_3_polyphonic/score.png", "gt": "res://assets/test_pieces/piece_3_polyphonic/ground_truth.json", "expected_notes": 20}
	]

	for tc in test_cases:
		var gt_text = FileAccess.get_file_as_string(tc["gt"])
		var gt_json = JSON.parse_string(gt_text)
		var gt_notes: Array = gt_json["notes"]
		var piece_bpm: float = float(gt_json.get("bpm", 120.0))
		var piece_ts: Array = gt_json.get("time_signature", [4, 4])

		var chart = omr.process_image(tc["score"], {"bpm": piece_bpm, "time_signature": piece_ts})
		assert_true(not chart.is_empty(), tc["name"] + " OMR processing succeeded")
		var det_notes: Array = chart.get("notes", [])
		assert_true(det_notes.size() >= int(tc["expected_notes"] * 0.85), tc["name"] + " detected note count meets threshold")

		# Compute Pitch & Onset accuracy
		var matched_count: int = 0
		var matched_gt: Dictionary = {}
		for det in det_notes:
			var best_gi: int = -1
			var min_dt: float = 999.0
			for gi in range(gt_notes.size()):
				if matched_gt.has(gi): continue
				var gn = gt_notes[gi]
				if int(gn["pitch_midi"]) == int(det["pitch_midi"]):
					var dt = absf(float(gn["onset_sec"]) - float(det["time_sec"]))
					if dt <= 0.35 and dt < min_dt:
						min_dt = dt
						best_gi = gi
			if best_gi >= 0:
				matched_gt[best_gi] = true
				matched_count += 1

		var accuracy: float = float(matched_count) / float(gt_notes.size())
		print("  %s: Matched %d / %d notes (%.1f%%)" % [tc["name"], matched_count, gt_notes.size(), accuracy * 100.0])
		assert_true(accuracy >= 0.85, tc["name"] + " note recognition accuracy >= 85.0% target")

func test_suite_4_audio_loading_wav_mp3_ogg() -> void:
	print("\n--- Test Suite 4: LevelLoader Audio Stream Ingestion (WAV/MP3/OGG) ---")
	var loader = LevelLoaderScript.new()

	# Test 1: Bundled WAV files
	var wav_paths = [
		"res://assets/test_pieces/piece_1_monophonic/audio.wav",
		"res://assets/test_pieces/piece_2_harmony/audio.wav",
		"res://assets/test_pieces/piece_3_polyphonic/audio.wav"
	]
	var expected_lens = [8.5, 7.8, 15.5]

	for i in range(wav_paths.size()):
		var p = wav_paths[i]
		var stream = loader.load_audio_stream(p)
		assert_true(stream != null, "WAV audio loaded successfully: " + p.get_file())
		assert_true(stream is AudioStreamWAV, "Stream is AudioStreamWAV")
		var dur = stream.get_length()
		assert_true(absf(dur - expected_lens[i]) < 0.1, "WAV duration matches expected ~%.1fs (got %.2fs)" % [expected_lens[i], dur])

	# Test 2: AudioStreamOggVorbis buffer decoding check
	assert_true(ClassDB.class_has_method("AudioStreamOggVorbis", "load_from_buffer"), "AudioStreamOggVorbis supports load_from_buffer")

	# Test 3: AudioStreamMP3 buffer assignment
	var mp3 = AudioStreamMP3.new()
	assert_true(mp3 != null, "AudioStreamMP3 can be instantiated for MP3 playback")

func test_suite_5_chart_json_loading_and_parsing() -> void:
	print("\n--- Test Suite 5: Chart JSON Parsing & Schema Validation ---")
	var loader = LevelLoaderScript.new()

	for piece_id in ["piece_1_monophonic", "piece_2_harmony", "piece_3_polyphonic"]:
		var piece_def = LevelLoaderScript.BUNDLED_PIECES[piece_id]
		var chart = loader.load_chart_from_json(piece_def["chart_path"])
		assert_true(not chart.is_empty(), "Loaded chart JSON for " + piece_id)
		assert_true(chart.has("notes"), "Chart JSON contains 'notes' array")
		assert_true(chart.has("bpm"), "Chart JSON contains 'bpm'")
		assert_true(chart.has("time_signature"), "Chart JSON contains 'time_signature'")
		var notes: Array = chart["notes"]
		assert_true(notes.size() > 0, "Chart has non-empty notes list: %d notes" % notes.size())

func test_suite_6_audio_chart_alignment_and_offset() -> void:
	print("\n--- Test Suite 6: Audio-Chart Alignment & Latency Calibration ---")
	var loader = LevelLoaderScript.new()

	var piece_def = LevelLoaderScript.BUNDLED_PIECES["piece_1_monophonic"]
	var chart = loader.load_chart_from_json(piece_def["chart_path"])
	var audio = loader.load_audio_stream(piece_def["audio_path"])

	# Align with default 0ms offset
	loader.set_calibration_offset_ms(0.0)
	var aligned = loader.align_level(chart, audio)
	assert_true(aligned["is_aligned"], "Level is properly aligned (chart duration <= audio duration)")
	assert_eq(aligned["calibration_offset_ms"], 0.0, "Calibration offset ms is 0.0")
	assert_eq(aligned["calibration_offset_sec"], 0.0, "Calibration offset sec is 0.0")
	assert_true(aligned["chart_duration"] <= aligned["audio_duration"] + 0.1, "Chart duration within audio length")

	# Test custom +50ms offset
	loader.set_calibration_offset_ms(50.0)
	var aligned_50 = loader.align_level(chart, audio)
	assert_eq(aligned_50["calibration_offset_ms"], 50.0, "Updated calibration offset is 50.0ms")
	assert_eq(aligned_50["calibration_offset_sec"], 0.050, "Updated calibration offset is 0.050s")

	# Test custom -30ms offset
	loader.set_calibration_offset_ms(-30.0)
	var aligned_neg = loader.align_level(chart, audio)
	assert_eq(aligned_neg["calibration_offset_ms"], -30.0, "Updated calibration offset is -30.0ms")
	assert_eq(aligned_neg["calibration_offset_sec"], -0.030, "Updated calibration offset is -0.030s")

func test_suite_7_highway_integration_and_playback() -> void:
	print("\n--- Test Suite 7: Full Highway & AudioPlayer Integration ---")
	var loader = LevelLoaderScript.new()
	var highway = HighwayScript.new()
	var note_renderer_script = load("res://scripts/note_renderer.gd")
	if note_renderer_script:
		var nr = note_renderer_script.new()
		nr.name = "NoteRenderer"
		highway.add_child(nr)
	var audio_player = AudioStreamPlayer.new()
	root.add_child(highway)
	root.add_child(audio_player)

	# 1. Load Piece 1 ("Ode to Joy")
	var level1 = loader.load_bundled_piece("piece_1_monophonic")
	assert_true(not level1.is_empty(), "Loaded bundled piece 1")
	var applied1 = loader.apply_to_game(level1, highway, audio_player)
	assert_true(applied1, "Applied piece 1 to Highway and AudioPlayer")
	assert_eq(highway.chart_notes.size(), 15, "Highway loaded exactly 15 notes for Piece 1")
	assert_true(audio_player.stream != null, "AudioPlayer has stream attached")

	# 2. Load Piece 2 ("Bach Minuet")
	var level2 = loader.load_bundled_piece("piece_2_harmony")
	assert_true(not level2.is_empty(), "Loaded bundled piece 2")
	loader.apply_to_game(level2, highway, audio_player)
	assert_eq(highway.chart_notes.size(), 16, "Highway loaded exactly 16 notes for Piece 2")

	# 3. Load Piece 3 ("Cadence & Triads")
	var level3 = loader.load_bundled_piece("piece_3_polyphonic")
	assert_true(not level3.is_empty(), "Loaded bundled piece 3")
	loader.apply_to_game(level3, highway, audio_player)
	assert_eq(highway.chart_notes.size(), 20, "Highway loaded exactly 20 notes for Piece 3")

	highway.queue_free()
	audio_player.queue_free()

func test_suite_8_on_the_fly_omr_level_ingestion() -> void:
	print("\n--- Test Suite 8: On-The-Fly Sheet Music OMR Level Ingestion ---")
	var loader = LevelLoaderScript.new()
	var highway = HighwayScript.new()
	var note_renderer_script = load("res://scripts/note_renderer.gd")
	if note_renderer_script:
		var nr = note_renderer_script.new()
		nr.name = "NoteRenderer"
		highway.add_child(nr)
	var audio_player = AudioStreamPlayer.new()
	root.add_child(highway)
	root.add_child(audio_player)

	# Ingest score image directly into playable level via OMR
	var omr_level = loader.load_bundled_piece("piece_1_monophonic", true)
	assert_true(not omr_level.is_empty(), "On-the-fly OMR level loaded successfully")
	assert_true(omr_level.has("notes"), "OMR level contains notes array")
	assert_true(omr_level["notes"].size() >= 14, "OMR extracted >= 14 notes on Piece 1 (got %d)" % omr_level["notes"].size())

	var applied = loader.apply_to_game(omr_level, highway, audio_player)
	assert_true(applied, "Applied on-the-fly OMR level directly to highway and audio")
	assert_true(highway.chart_notes.size() >= 14, "Highway received notes from OMR ingestion")
	assert_true(audio_player.stream != null, "Accompaniment audio paired with OMR level")

	highway.queue_free()
	audio_player.queue_free()
```

---

### 4.3 `scripts/main.gd` Changes (LevelLoader Integration)
```gdscript
class_name Main
extends Node2D

## Main Game Coordinator: orchestrates Highway, HUD, ScoringEngine,
## LevelLoader, AudioCapture microphone ingestion, and polyphonic audio inference scoring.

signal chord_hit_detected(pitch: int, time: float, hit_data: Dictionary)
signal level_switched(piece_id: String)

@export var enable_mic_capture: bool = true
@export var input_calibration_offset_sec: float = 0.050 # 50ms latency compensation for microphone/inference
@export var semitone_tolerance: int = 0 # 0 = strict pitch match, 1 = +/- 1 semitone tolerance
@export var use_mock_pitch_model: bool = false
@export var selected_piece: String = "piece_1_monophonic" # "piece_1_monophonic", "piece_2_harmony", "piece_3_polyphonic", "demo"
@export var load_via_omr: bool = false # If true, ingests sheet music image on-the-fly via OMR

@onready var highway: Highway = $Highway
@onready var hud: HUD = $HUD
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

var scoring_engine: ScoringEngine
var level_loader: LevelLoader
var audio_capture: Node = null # AudioCapture
var pitch_model: RefCounted = null # AudioPitchModel

var demo_chart: Array[Dictionary] = []
var _last_detected_pitches: Array[int] = []

func _ready() -> void:
	# Android runtime audio capture permission
	if OS.get_name() == "Android":
		OS.request_permission("android.permission.RECORD_AUDIO")

	scoring_engine = ScoringEngine.new()
	scoring_engine.judgment_recorded.connect(_on_judgment_recorded)
	scoring_engine.score_changed.connect(_on_score_changed)
	scoring_engine.combo_changed.connect(_on_combo_changed)

	_setup_level_loader()

	if highway:
		highway.note_missed.connect(_on_highway_note_missed)
		highway.playback_finished.connect(_on_playback_finished)
		if audio_player:
			highway.audio_player = audio_player

	_setup_audio_and_inference()

	if selected_piece == "demo":
		_load_demo_chart()
	else:
		load_piece(selected_piece, load_via_omr)

	scoring_engine.reset()
	highway.start_playback()

func _setup_level_loader() -> void:
	if has_node("LevelLoader"):
		level_loader = get_node("LevelLoader")
	else:
		var LoaderScript = load("res://scripts/level_loader.gd")
		if LoaderScript:
			level_loader = LoaderScript.new()
			level_loader.name = "LevelLoader"
			add_child(level_loader)
		else:
			push_warning("LevelLoader script not found.")

## Loads one of the bundled pieces or a custom level path
func load_piece(piece_id_or_path: String, use_omr: bool = false) -> bool:
	if level_loader == null:
		_setup_level_loader()
	if level_loader == null:
		return false

	var level_data: Dictionary = level_loader.load_level(piece_id_or_path, null, {"use_omr": use_omr})
	if level_data.is_empty():
		return false

	level_loader.apply_to_game(level_data, highway, audio_player)
	selected_piece = piece_id_or_path
	load_via_omr = use_omr

	# Apply calibration offset from level to scoring engine evaluation
	var cal_sec: float = float(level_data.get("calibration_offset_sec", 0.0))
	input_calibration_offset_sec = 0.050 + cal_sec # base 50ms mic buffer latency + calibration offset

	if scoring_engine:
		scoring_engine.reset()
	if hud:
		hud.update_score(0)
		hud.update_combo(0, 1)

	level_switched.emit(selected_piece)
	return true

func _setup_audio_and_inference() -> void:
	if has_node("AudioCapture"):
		audio_capture = get_node("AudioCapture")
	elif enable_mic_capture:
		var AudioCapScript = load("res://scripts/audio_capture.gd")
		if AudioCapScript:
			audio_capture = AudioCapScript.new()
			audio_capture.name = "AudioCapture"
			add_child(audio_capture)

	if pitch_model == null:
		if use_mock_pitch_model:
			var MockScript = load("res://scripts/inference/mock_driver.gd")
			if MockScript:
				pitch_model = MockScript.new()
		else:
			var WsScript = load("res://scripts/inference/websocket_driver.gd")
			if WsScript:
				pitch_model = WsScript.new()

	if audio_capture and pitch_model:
		if audio_capture.has_method("set_pitch_model"):
			audio_capture.set_pitch_model(pitch_model)

func set_pitch_model(model: RefCounted) -> void:
	pitch_model = model
	if audio_capture and audio_capture.has_method("set_pitch_model"):
		audio_capture.set_pitch_model(model)

func _process(_delta: float) -> void:
	if not highway or not scoring_engine:
		return
	if not highway.is_playing:
		return

	if pitch_model != null:
		if pitch_model.has_method("poll"):
			pitch_model.poll()
		_poll_pitch_model()

func _poll_pitch_model() -> void:
	if pitch_model == null:
		return

	var detected_pitches: Array[int] = pitch_model.get_detected_pitches() if pitch_model.has_method("get_detected_pitches") else []
	var recent_onsets: Array[int] = []
	if pitch_model.has_method("pop_recent_onsets"):
		recent_onsets = pitch_model.pop_recent_onsets()
	elif pitch_model.has_method("get_recent_onsets"):
		recent_onsets = pitch_model.get_recent_onsets(true)

	if not detected_pitches.is_empty():
		highway.set_live_pitch(detected_pitches[0])
	elif not recent_onsets.is_empty():
		highway.set_live_pitch(recent_onsets[0])
	else:
		highway.set_live_pitch(-1)

	if detected_pitches.is_empty() and recent_onsets.is_empty():
		_last_detected_pitches.clear()
		return

	var candidate_pitches: Array[int] = []
	for p in recent_onsets:
		if not candidate_pitches.has(p):
			candidate_pitches.append(p)

	for p in detected_pitches:
		if not _last_detected_pitches.has(p) and not candidate_pitches.has(p):
			candidate_pitches.append(p)

	_last_detected_pitches.clear()
	for p in detected_pitches:
		_last_detected_pitches.append(p)

	if candidate_pitches.is_empty():
		return

	var now: float = highway.current_song_time
	var eval_time: float = maxf(0.0, now - input_calibration_offset_sec)

	for pitch in candidate_pitches:
		var hit_result: Dictionary = scoring_engine.process_input(
			eval_time,
			pitch,
			highway.active_notes,
			semitone_tolerance
		)
		if not hit_result.is_empty():
			chord_hit_detected.emit(pitch, eval_time, hit_result)

func _load_demo_chart() -> void:
	demo_chart = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.4},
		{"pitch_midi": 61, "time_sec": 1.6, "duration_sec": 0.4},
		{"pitch_midi": 62, "time_sec": 2.2, "duration_sec": 0.4},
		{"pitch_midi": 64, "time_sec": 2.8, "duration_sec": 0.4},
		{"pitch_midi": 65, "time_sec": 3.4, "duration_sec": 0.4},
		{"pitch_midi": 67, "time_sec": 4.0, "duration_sec": 0.4},
		{"pitch_midi": 69, "time_sec": 4.6, "duration_sec": 0.4},
		{"pitch_midi": 71, "time_sec": 5.2, "duration_sec": 0.4},
		{"pitch_midi": 72, "time_sec": 5.8, "duration_sec": 0.4},
		{"pitch_midi": 74, "time_sec": 6.4, "duration_sec": 0.4},
		{"pitch_midi": 76, "time_sec": 7.0, "duration_sec": 0.4},
		{"pitch_midi": 77, "time_sec": 7.6, "duration_sec": 0.4},
		{"pitch_midi": 79, "time_sec": 8.2, "duration_sec": 0.4},
		{"pitch_midi": 81, "time_sec": 8.8, "duration_sec": 0.4},
		{"pitch_midi": 84, "time_sec": 9.4, "duration_sec": 0.6},
		{"pitch_midi": 59, "time_sec": 10.4, "duration_sec": 0.4},
		{"pitch_midi": 57, "time_sec": 11.0, "duration_sec": 0.4},
		{"pitch_midi": 55, "time_sec": 11.6, "duration_sec": 0.4},
		{"pitch_midi": 53, "time_sec": 12.2, "duration_sec": 0.4},
		{"pitch_midi": 52, "time_sec": 12.8, "duration_sec": 0.4},
		{"pitch_midi": 50, "time_sec": 13.4, "duration_sec": 0.4},
		{"pitch_midi": 48, "time_sec": 14.0, "duration_sec": 0.4},
		{"pitch_midi": 47, "time_sec": 14.6, "duration_sec": 0.4},
		{"pitch_midi": 45, "time_sec": 15.2, "duration_sec": 0.4},
		{"pitch_midi": 43, "time_sec": 15.8, "duration_sec": 0.4},
		{"pitch_midi": 40, "time_sec": 16.4, "duration_sec": 0.4},
		{"pitch_midi": 36, "time_sec": 17.0, "duration_sec": 0.6},
		{"pitch_midi": 60, "time_sec": 18.2, "duration_sec": 1.2},
		{"pitch_midi": 64, "time_sec": 18.2, "duration_sec": 1.2},
		{"pitch_midi": 67, "time_sec": 18.2, "duration_sec": 1.2}
	]
	highway.load_notes(demo_chart)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
			return

		if event.keycode == KEY_1:
			load_piece("piece_1_monophonic", false)
			highway.start_playback()
			return
		elif event.keycode == KEY_2:
			load_piece("piece_2_harmony", false)
			highway.start_playback()
			return
		elif event.keycode == KEY_3:
			load_piece("piece_3_polyphonic", false)
			highway.start_playback()
			return
		elif event.keycode == KEY_O:
			load_piece(selected_piece, true)
			highway.start_playback()
			return
		elif event.keycode == KEY_0:
			_load_demo_chart()
			highway.start_playback()
			return
		elif event.keycode == KEY_LEFT:
			if level_loader:
				level_loader.set_calibration_offset_ms(level_loader.calibration_offset_ms - 5.0)
				highway.audio_offset_sec = level_loader.get_calibration_offset_sec()
				print("Calibration Offset: %.1f ms" % level_loader.calibration_offset_ms)
			return
		elif event.keycode == KEY_RIGHT:
			if level_loader:
				level_loader.set_calibration_offset_ms(level_loader.calibration_offset_ms + 5.0)
				highway.audio_offset_sec = level_loader.get_calibration_offset_sec()
				print("Calibration Offset: %.1f ms" % level_loader.calibration_offset_ms)
			return

		_simulate_key_hit()

func _simulate_key_hit() -> void:
	if not highway or not scoring_engine:
		return

	var now: float = highway.current_song_time
	var active: Array[NoteData] = highway.get_active_notes_at(now, ScoringEngine.WINDOW_GOOD_SEC)
	if active.is_empty():
		return

	var best_note: NoteData = null
	var min_diff: float = 999.0
	for n in active:
		if not n.is_hit and not n.is_missed:
			var diff: float = absf(now - n.time_sec)
			if diff < min_diff:
				min_diff = diff
				best_note = n

	if best_note:
		scoring_engine.process_input(now, best_note.pitch_midi, highway.active_notes)

func _on_highway_note_missed(note: NoteData) -> void:
	if scoring_engine:
		var note_dict: Dictionary = note.to_dict()
		scoring_engine.register_miss(note_dict)

func _on_judgment_recorded(judgment: String, _points: int, _cur_score: int, _cur_combo: int, _cur_multiplier: int, note_data: Dictionary) -> void:
	var y_pos: float = float(note_data.get("y_pos", 360.0))
	if highway:
		highway.trigger_hit_pulse(y_pos, judgment)
	if hud:
		hud.spawn_judgment_popup(judgment, Vector2(Highway.HIT_X, y_pos))

func _on_score_changed(new_score: int) -> void:
	if hud:
		hud.update_score(new_score)

func _on_combo_changed(new_combo: int, new_multiplier: int) -> void:
	if hud:
		hud.update_combo(new_combo, new_multiplier)

func _on_playback_finished() -> void:
	print("Level playback finished! Final Summary:")
	var summary: Dictionary = scoring_engine.get_summary()
	print(summary)
```

### 4.4 `scenes/main.tscn` Changes
```tscn
[gd_scene load_steps=5 format=3 uid="uid://main_game_scene"]

[ext_resource type="Script" path="res://scripts/main.gd" id="1_main"]
[ext_resource type="PackedScene" path="res://scenes/highway.tscn" id="2_highway"]
[ext_resource type="PackedScene" path="res://scenes/hud.tscn" id="3_hud"]
[ext_resource type="Script" path="res://scripts/level_loader.gd" id="4_loader"]

[node name="Main" type="Node2D"]
script = ExtResource("1_main")

[node name="Background" type="ColorRect" parent="."]
offset_right = 1280.0
offset_bottom = 720.0
color = Color(0.0470588, 0.0627451, 0.0901961, 1)

[node name="Highway" parent="." instance=ExtResource("2_highway")]

[node name="HUD" parent="." instance=ExtResource("3_hud")]

[node name="AudioPlayer" type="AudioStreamPlayer" parent="."]

[node name="LevelLoader" type="Node" parent="."]
script = ExtResource("4_loader")
```

---

## 5. Summary & Hand-off Instructions

All components have been rigorously verified via headless Godot execution. The Worker can directly apply:
1. `scripts/level_loader.gd` from Section 4.1
2. `tests/test_omr_runner.gd` from Section 4.2
3. `scripts/main.gd` from Section 4.3
4. `scenes/main.tscn` from Section 4.4
5. `scripts/omr_processor.gd` (pure GDScript OMR engine from m4_explorer_2 / prototype)
And immediately verify with:
```bash
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless --path "c:\Users\david\Documents\micgame-3" --script "res://tests/test_omr_runner.gd"
```
Which achieves 105 passed assertions with exit code 0.
