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
	elif ResourceLoader.exists("res://.agents/teamwork/m4_explorer_3/omr_processor.gd"):
		omr_script = load("res://.agents/teamwork/m4_explorer_3/omr_processor.gd")

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
		# Try looking up by alias
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
