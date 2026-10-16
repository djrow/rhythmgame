# res://scripts/main.gd
class_name Main
extends Node2D

## Main Game Coordinator: orchestrates Highway, HUD, ScoringEngine,
## AudioCapture microphone ingestion, and polyphonic audio inference scoring.

signal chord_hit_detected(pitch: int, time: float, hit_data: Dictionary)

@export var enable_mic_capture: bool = true
@export var input_calibration_offset_sec: float = 0.050 # 50ms latency compensation for microphone/inference
@export var semitone_tolerance: int = 0 # 0 = strict pitch match, 1 = +/- 1 semitone tolerance
@export var use_mock_pitch_model: bool = false

@onready var highway: Highway = $Highway
@onready var hud: HUD = $HUD
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

var scoring_engine: ScoringEngine
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

	if highway:
		highway.note_missed.connect(_on_highway_note_missed)
		highway.playback_finished.connect(_on_playback_finished)
		if audio_player:
			highway.audio_player = audio_player

	_setup_audio_and_inference()
	_load_demo_chart()
	scoring_engine.reset()
	highway.start_playback()

func _setup_audio_and_inference() -> void:
	# 1. Setup AudioCapture node if not already present
	if has_node("AudioCapture"):
		audio_capture = get_node("AudioCapture")
	elif enable_mic_capture:
		var AudioCapScript = load("res://scripts/audio_capture.gd")
		if AudioCapScript:
			audio_capture = AudioCapScript.new()
			audio_capture.name = "AudioCapture"
			add_child(audio_capture)

	# 2. Setup AudioPitchModel if not injected
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

## Allows external harnesses or tests to inject a pitch model runner
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

## Polls detected pitches and onsets from model runner, evaluates polyphonic clusters
## concurrently against active highway notes, and awards scoring judgments.
func _poll_pitch_model() -> void:
	if pitch_model == null:
		return

	var detected_pitches: Array[int] = pitch_model.get_detected_pitches() if pitch_model.has_method("get_detected_pitches") else []
	var recent_onsets: Array[int] = pitch_model.get_recent_onsets() if pitch_model.has_method("get_recent_onsets") else []

	# Update live pitch cursor on Grand Staff receptor line
	if not detected_pitches.is_empty():
		highway.set_live_pitch(detected_pitches[0])
	elif not recent_onsets.is_empty():
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
	# Build comprehensive test chart spanning C2 to C6+ with Middle C and polyphonic chord
	demo_chart = [
		# Middle C (Step 28, Y=360, 1 ledger)
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.4},
		# Accidental Middle C# (Step 28, Y=360, 1 ledger + sharp)
		{"pitch_midi": 61, "time_sec": 1.6, "duration_sec": 0.4},
		# Treble Staff Ascending
		{"pitch_midi": 62, "time_sec": 2.2, "duration_sec": 0.4}, # D4
		{"pitch_midi": 64, "time_sec": 2.8, "duration_sec": 0.4}, # E4 (Treble Line 1)
		{"pitch_midi": 65, "time_sec": 3.4, "duration_sec": 0.4}, # F4
		{"pitch_midi": 67, "time_sec": 4.0, "duration_sec": 0.4}, # G4 (Treble Line 2)
		{"pitch_midi": 69, "time_sec": 4.6, "duration_sec": 0.4}, # A4
		{"pitch_midi": 71, "time_sec": 5.2, "duration_sec": 0.4}, # B4 (Treble Line 3)
		{"pitch_midi": 72, "time_sec": 5.8, "duration_sec": 0.4}, # C5
		{"pitch_midi": 74, "time_sec": 6.4, "duration_sec": 0.4}, # D5 (Treble Line 4)
		{"pitch_midi": 76, "time_sec": 7.0, "duration_sec": 0.4}, # E5
		{"pitch_midi": 77, "time_sec": 7.6, "duration_sec": 0.4}, # F5 (Treble Line 5)
		{"pitch_midi": 79, "time_sec": 8.2, "duration_sec": 0.4}, # G5
		{"pitch_midi": 81, "time_sec": 8.8, "duration_sec": 0.4}, # A5 (1st Ledger Above)
		{"pitch_midi": 84, "time_sec": 9.4, "duration_sec": 0.6}, # C6 (2nd Ledger Above)
		# Bass Staff Descending
		{"pitch_midi": 59, "time_sec": 10.4, "duration_sec": 0.4}, # B3
		{"pitch_midi": 57, "time_sec": 11.0, "duration_sec": 0.4}, # A3 (Bass Line 5)
		{"pitch_midi": 55, "time_sec": 11.6, "duration_sec": 0.4}, # G3
		{"pitch_midi": 53, "time_sec": 12.2, "duration_sec": 0.4}, # F3 (Bass Line 4)
		{"pitch_midi": 52, "time_sec": 12.8, "duration_sec": 0.4}, # E3
		{"pitch_midi": 50, "time_sec": 13.4, "duration_sec": 0.4}, # D3 (Bass Line 3)
		{"pitch_midi": 48, "time_sec": 14.0, "duration_sec": 0.4}, # C3
		{"pitch_midi": 47, "time_sec": 14.6, "duration_sec": 0.4}, # B2 (Bass Line 2)
		{"pitch_midi": 45, "time_sec": 15.2, "duration_sec": 0.4}, # A2
		{"pitch_midi": 43, "time_sec": 15.8, "duration_sec": 0.4}, # G2 (Bass Line 1)
		{"pitch_midi": 40, "time_sec": 16.4, "duration_sec": 0.4}, # E2 (1st Ledger Below)
		{"pitch_midi": 36, "time_sec": 17.0, "duration_sec": 0.6}, # C2 (2nd Ledger Below)
		# Polyphonic Chord: C Major Triad (C4, E4, G4)
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

		# Keyboard playtesting strum: hit nearest active note
		_simulate_key_hit()

func _simulate_key_hit() -> void:
	if not highway or not scoring_engine:
		return

	var now: float = highway.current_song_time
	var active: Array[NoteData] = highway.get_active_notes_at(now, ScoringEngine.WINDOW_GOOD_SEC)
	if active.is_empty():
		return

	# Pick unhit note closest to hit line
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
	print("Demo chart playback finished! Final Summary:")
	var summary: Dictionary = scoring_engine.get_summary()
	print(summary)
