class_name Main
extends Node2D

## Main Game Coordinator: orchestrates Highway, HUD (with Oscilloscope & Mic Dropdown),
## ScoringEngine, LevelLoader, AudioCapture microphone ingestion, and polyphonic audio inference scoring.

signal chord_hit_detected(pitch: int, time: float, hit_data: Dictionary)
signal level_switched(piece_id: String)

@export var enable_mic_capture: bool = true
@export var auto_start_onnx_server: bool = true
@export var auto_loop_playback: bool = true
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
var _onnx_server_pid: int = -1
var _test_tone_timer: float = 0.0
var _test_tone_pitches: Array = [60, 64, 67]
var _loop_restart_timer: float = -1.0

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
	_connect_hud_signals()

	if selected_piece == "demo":
		_load_demo_chart()
	else:
		load_piece(selected_piece, load_via_omr)

	scoring_engine.reset()
	highway.start_playback()

func _exit_tree() -> void:
	if pitch_model != null and pitch_model.has_method("disconnect_from_server"):
		pitch_model.disconnect_from_server()
	if _onnx_server_pid > 0 and OS.is_process_running(_onnx_server_pid):
		OS.kill(_onnx_server_pid)
		_onnx_server_pid = -1

func _connect_hud_signals() -> void:
	if hud == null:
		return
	if hud.has_signal("mic_device_selected") and not hud.mic_device_selected.is_connected(_on_hud_mic_device_selected):
		hud.mic_device_selected.connect(_on_hud_mic_device_selected)
	if hud.has_signal("refresh_mics_requested") and not hud.refresh_mics_requested.is_connected(_on_hud_refresh_mics_requested):
		hud.refresh_mics_requested.connect(_on_hud_refresh_mics_requested)
	if hud.has_signal("test_signal_requested") and not hud.test_signal_requested.is_connected(_on_hud_test_signal_requested):
		hud.test_signal_requested.connect(_on_hud_test_signal_requested)
	if hud.has_signal("piece_selected") and not hud.piece_selected.is_connected(_on_hud_piece_selected):
		hud.piece_selected.connect(_on_hud_piece_selected)
	if hud.has_signal("custom_song_requested") and not hud.custom_song_requested.is_connected(_on_hud_custom_song_requested):
		hud.custom_song_requested.connect(_on_hud_custom_song_requested)

	if audio_capture != null and hud.has_method("refresh_microphone_dropdown"):
		hud.refresh_microphone_dropdown(audio_capture.get_input_devices(), audio_capture.get_current_input_device())

func _on_hud_mic_device_selected(device_name: String) -> void:
	if audio_capture != null and audio_capture.has_method("set_input_device"):
		audio_capture.set_input_device(device_name)

func _on_hud_refresh_mics_requested() -> void:
	if hud != null and audio_capture != null and hud.has_method("refresh_microphone_dropdown"):
		hud.refresh_microphone_dropdown(audio_capture.get_input_devices(), audio_capture.get_current_input_device())

func _on_hud_test_signal_requested() -> void:
	# Choose currently active notes on highway if available, otherwise C Major Triad (60, 64, 67)
	_test_tone_pitches = [60, 64, 67]
	if highway != null and highway.is_playing:
		var active: Array[NoteData] = highway.get_active_notes_at(highway.current_song_time, 0.35)
		if not active.is_empty():
			var chord: Array = []
			for n in active:
				if not n.is_hit and not n.is_missed and not chord.has(n.pitch_midi):
					chord.append(n.pitch_midi)
			if not chord.is_empty():
				_test_tone_pitches = chord
	_test_tone_timer = 0.45

func _on_hud_piece_selected(piece_id: String, use_omr: bool) -> void:
	if piece_id == "__restart__":
		load_piece(selected_piece, load_via_omr)
		highway.start_playback()
		return
	var target: String = piece_id if not piece_id.is_empty() else selected_piece
	load_piece(target, use_omr)
	highway.start_playback()

func _on_hud_custom_song_requested(sheet_path: String, audio_path: String, bpm: float) -> void:
	if load_custom_song(sheet_path, audio_path, bpm):
		highway.start_playback()

## Loads a user-selected custom sheet music image (via OMR) or chart JSON paired with an audio file.
func load_custom_song(sheet_path: String, audio_path: String = "", bpm: float = 120.0) -> bool:
	if level_loader == null:
		_setup_level_loader()
	if level_loader == null or sheet_path.is_empty():
		return false

	var ext: String = sheet_path.get_extension().to_lower()
	var is_image: bool = ext in ["png", "jpg", "jpeg"]
	var opts: Dictionary = {
		"use_omr": is_image,
		"bpm": bpm,
		"title": sheet_path.get_file().get_basename()
	}
	var audio_src: Variant = audio_path if not audio_path.is_empty() else null
	var level_data: Dictionary = level_loader.load_level(sheet_path, audio_src, opts)
	if level_data.is_empty():
		return false

	level_loader.apply_to_game(level_data, highway, audio_player)
	selected_piece = sheet_path
	load_via_omr = is_image
	_loop_restart_timer = -1.0

	var cal_sec: float = float(level_data.get("calibration_offset_sec", 0.0))
	input_calibration_offset_sec = 0.050 + cal_sec

	if scoring_engine:
		scoring_engine.reset()
	if hud:
		hud.update_score(0)
		hud.update_combo(0, 1)
		if hud.has_method("update_piece_title"):
			hud.update_piece_title(sheet_path.get_file().get_basename(), is_image)

	level_switched.emit(selected_piece)
	return true

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
	_loop_restart_timer = -1.0

	# Apply calibration offset from level to scoring engine evaluation
	var cal_sec: float = float(level_data.get("calibration_offset_sec", 0.0))
	input_calibration_offset_sec = 0.050 + cal_sec # base 50ms mic buffer latency + calibration offset

	if scoring_engine:
		scoring_engine.reset()
	if hud:
		hud.update_score(0)
		hud.update_combo(0, 1)
		if hud.has_method("update_piece_title"):
			hud.update_piece_title(selected_piece, load_via_omr)

	level_switched.emit(selected_piece)
	return true

func _setup_audio_and_inference() -> void:
	# 1. Auto-launch Python ONNX Inference Server on desktop when running interactively
	if auto_start_onnx_server and not use_mock_pitch_model and DisplayServer.get_name() != "headless":
		if OS.get_name() in ["Windows", "Linux", "macOS"]:
			_try_start_local_onnx_server()

	# 2. Setup AudioCapture node if not already present
	if has_node("AudioCapture"):
		audio_capture = get_node("AudioCapture")
	elif enable_mic_capture:
		var AudioCapScript = load("res://scripts/audio_capture.gd")
		if AudioCapScript:
			audio_capture = AudioCapScript.new()
			audio_capture.name = "AudioCapture"
			add_child(audio_capture)

	# 3. Setup AudioPitchModel if not injected
	if pitch_model == null:
		if use_mock_pitch_model:
			var MockScript = load("res://scripts/inference/mock_driver.gd")
			if MockScript:
				pitch_model = MockScript.new()
		else:
			var WsScript = load("res://scripts/inference/websocket_driver.gd")
			if WsScript:
				var ws_drv = WsScript.new()
				ws_drv.enable_dsp_fallback = true
				ws_drv.min_send_samples = 1024
				pitch_model = ws_drv

	if audio_capture and pitch_model:
		if audio_capture.has_method("set_pitch_model"):
			audio_capture.set_pitch_model(pitch_model)

func _try_start_local_onnx_server() -> void:
	if _onnx_server_pid > 0 and OS.is_process_running(_onnx_server_pid):
		return

	var candidate_scripts: Array[String] = [
		ProjectSettings.globalize_path("res://python/inference_server.py"),
		OS.get_executable_path().get_base_dir().path_join("python/inference_server.py")
	]
	var script_path: String = ""
	for path in candidate_scripts:
		if FileAccess.file_exists(path):
			script_path = path
			break
	if script_path.is_empty():
		return

	var sr: int = int(AudioServer.get_mix_rate())
	if sr <= 0:
		sr = 48000
	var args := PackedStringArray([script_path, "--sample-rate", str(sr)])
	_onnx_server_pid = OS.create_process("python", args, false)

## Allows external harnesses or tests to inject a pitch model runner
func set_pitch_model(model: RefCounted) -> void:
	pitch_model = model
	if audio_capture and audio_capture.has_method("set_pitch_model"):
		audio_capture.set_pitch_model(model)

func _process(delta: float) -> void:
	# 1. Handle interactive test signal injection if active
	if _test_tone_timer > 0.0 and audio_capture != null:
		_test_tone_timer = maxf(0.0, _test_tone_timer - delta)
		if audio_capture.has_method("inject_test_chord"):
			var n_frames: int = maxi(256, int(round(float(audio_capture.get_sample_rate()) * minf(delta, 0.05))))
			audio_capture.inject_test_chord(_test_tone_pitches, n_frames, 0.28)

	# 2. Always poll pitch model and update HUD oscilloscope + telemetry (even between songs)
	if pitch_model != null:
		if pitch_model.has_method("poll"):
			pitch_model.poll(delta)
		_poll_pitch_model()

	_update_hud_diagnostics()

	# 3. Auto-loop restart timer after level completes
	if _loop_restart_timer > 0.0:
		_loop_restart_timer -= delta
		if _loop_restart_timer <= 0.0:
			_loop_restart_timer = -1.0
			if selected_piece == "demo":
				_load_demo_chart()
			else:
				load_piece(selected_piece, load_via_omr)
			highway.start_playback()

func _update_hud_diagnostics() -> void:
	if hud == null:
		return

	if audio_capture != null and hud.has_method("update_audio_telemetry"):
		hud.update_audio_telemetry(
			audio_capture.oscilloscope_ring_buffer,
			audio_capture.current_rms,
			audio_capture.current_rms_db,
			audio_capture.is_currently_gated,
			audio_capture.is_capturing,
			audio_capture.total_frames_captured,
			audio_capture.get_sample_rate()
		)

	if pitch_model != null and hud.has_method("update_inference_telemetry"):
		var status: Dictionary = {}
		if pitch_model.has_method("get_status_summary"):
			status = pitch_model.get_status_summary()
		else:
			status = {
				"backend": "Custom / Mock Driver",
				"is_connected": pitch_model.is_model_ready() if pitch_model.has_method("is_model_ready") else true,
				"is_ready": true,
				"latency_ms": 0.0,
				"inference_count": 0,
				"pitches": pitch_model.get_detected_pitches() if pitch_model.has_method("get_detected_pitches") else [],
				"confidence": {}
			}
		hud.update_inference_telemetry(status)

## Polls detected pitches and onsets from model runner, updates Grand Staff live cursors,
## and evaluates polyphonic clusters against active highway notes when playing.
func _poll_pitch_model() -> void:
	if pitch_model == null:
		return

	var detected_pitches: Array[int] = pitch_model.get_detected_pitches() if pitch_model.has_method("get_detected_pitches") else []
	var recent_onsets: Array[int] = []
	if pitch_model.has_method("pop_recent_onsets"):
		recent_onsets = pitch_model.pop_recent_onsets()
	elif pitch_model.has_method("get_recent_onsets"):
		recent_onsets = pitch_model.get_recent_onsets(true)

	# Update HUD onset flash if any new onsets arrived
	if hud != null and not recent_onsets.is_empty() and hud.has_method("update_inference_telemetry") and pitch_model.has_method("get_status_summary"):
		hud.update_inference_telemetry(pitch_model.get_status_summary(), recent_onsets)

	# Update live polyphonic pitch cursors on Grand Staff receptor line
	if highway != null:
		if not detected_pitches.is_empty():
			if highway.has_method("set_live_pitches"):
				highway.set_live_pitches(detected_pitches)
			else:
				highway.set_live_pitch(detected_pitches[0])
		elif not recent_onsets.is_empty():
			if highway.has_method("set_live_pitches"):
				highway.set_live_pitches(recent_onsets)
			else:
				highway.set_live_pitch(recent_onsets[0])
		else:
			highway.set_live_pitch(-1)

	if detected_pitches.is_empty() and recent_onsets.is_empty():
		_last_detected_pitches.clear()
		return

	# Candidate strike pitches:
	# 1. Any pitch explicitly triggered as an onset
	# 2. Any newly detected pitch (transitioned from silent to active)
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

	if highway == null or scoring_engine == null or not highway.is_playing:
		return

	# Evaluate candidates against highway active notes at current song time
	var now: float = highway.current_song_time
	var eval_time: float = maxf(0.0, now - input_calibration_offset_sec)

	# Evaluate all concurrent pitches in cluster (handles chords simultaneously)
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
	if hud and hud.has_method("update_piece_title"):
		hud.update_piece_title("demo", false)

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
		elif event.keycode == KEY_R:
			load_piece(selected_piece, load_via_omr)
			highway.start_playback()
			return
		elif event.keycode == KEY_T:
			_on_hud_test_signal_requested()
			return
		elif event.keycode == KEY_0:
			selected_piece = "demo"
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

		# Keyboard playtesting strum: hit nearest active note
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
	if highway:
		highway.is_playing = false
	print("Level playback finished! Final Summary:")
	var summary: Dictionary = scoring_engine.get_summary()
	print(summary)
	if auto_loop_playback and _loop_restart_timer < 0.0:
		_loop_restart_timer = 2.0
