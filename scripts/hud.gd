class_name HUD
extends CanvasLayer

## Heads-Up Display:
## - Score, Combo counter, Multiplier indicator, and Rating Popups
## - Microphone Selection Dropdown (OptionButton) & Refresh button
## - Real-Time Oscilloscope View & VU Level Meter
## - Polyphonic Inference Engine Status, Latency & Detected Notes Readout

const OscilloscopeViewScript = preload("res://scripts/oscilloscope_view.gd")
const NoteDataScript = preload("res://scripts/note_data.gd")

signal mic_device_selected(device_name: String)
signal refresh_mics_requested()
signal test_signal_requested()
signal piece_selected(piece_id: String, use_omr: bool)
signal custom_song_requested(sheet_path: String, audio_path: String, bpm: float)

@onready var score_value: Label = $ScoreContainer/ScoreValue
@onready var combo_container: VBoxContainer = $ComboContainer
@onready var combo_label: Label = $ComboContainer/ComboLabel
@onready var multiplier_label: Label = $ComboContainer/MultiplierLabel
@onready var judgment_layer: Control = $JudgmentLayer

# Audio & Inference Diagnostic UI nodes (created dynamically if not in scene)
var top_info_bar: PanelContainer = null
var diagnostic_dock: PanelContainer = null
var mic_dropdown: OptionButton = null
var refresh_mic_button: Button = null
var test_signal_button: Button = null
var mic_status_label: Label = null
var mic_level_label: Label = null
var oscilloscope_view: Control = null # OscilloscopeView
var inference_backend_label: Label = null
var inference_metrics_label: Label = null
var detected_notes_label: Label = null
var last_onset_label: Label = null
var piece_title_label: Label = null
var custom_song_button: Button = null
var custom_song_modal: PanelContainer = null
var custom_sheet_input: LineEdit = null
var custom_audio_input: LineEdit = null
var custom_bpm_spin: SpinBox = null
var sheet_file_dialog: FileDialog = null
var audio_file_dialog: FileDialog = null

const COLOR_PERFECT: Color = Color(1.0, 0.84, 0.0)     # Gold
const COLOR_GOOD: Color = Color(0.0, 0.9, 1.0)         # Cyan / Neon Blue
const COLOR_MISS: Color = Color(1.0, 0.2, 0.4)         # Crimson

const COLOR_MULT_1X: Color = Color(0.8, 0.8, 0.8)     # Silver
const COLOR_MULT_2X: Color = Color(0.0, 0.9, 1.0)     # Cyan
const COLOR_MULT_3X: Color = Color(1.0, 0.6, 0.0)     # Orange
const COLOR_MULT_4X: Color = Color(1.0, 0.84, 0.0)    # Gold

var displayed_score: int = 0
var score_tween: Tween
var _last_onset_text: String = "Last Onset: —"
var _onset_flash_timer: float = 0.0

func _ready() -> void:
	_build_diagnostic_ui()
	_apply_mobile_safe_area()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_apply_mobile_safe_area)
	update_score(0)
	update_combo(0, 1)
	refresh_microphone_dropdown()

func _process(delta: float) -> void:
	if _onset_flash_timer > 0.0:
		_onset_flash_timer = maxf(0.0, _onset_flash_timer - delta)
		if last_onset_label:
			var t: float = clampf(_onset_flash_timer / 0.6, 0.0, 1.0)
			last_onset_label.modulate = Color(0.7, 0.82, 0.95).lerp(Color(1.0, 0.92, 0.25), t)

func _build_diagnostic_ui() -> void:
	if diagnostic_dock != null:
		return

	# Top-left Piece & Quick Controls Bar
	var top_bar := PanelContainer.new()
	top_bar.name = "TopInfoBar"
	top_bar.position = Vector2(20, 16)
	top_bar.size = Vector2(860, 48)
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = Color(0.06, 0.09, 0.14, 0.88)
	top_style.border_color = Color(0.22, 0.36, 0.54, 0.85)
	top_style.set_border_width_all(1)
	top_style.set_corner_radius_all(6)
	top_style.content_margin_left = 12
	top_style.content_margin_right = 12
	top_style.content_margin_top = 6
	top_style.content_margin_bottom = 6
	top_bar.add_theme_stylebox_override("panel", top_style)
	add_child(top_bar)
	top_info_bar = top_bar

	var top_hbox := HBoxContainer.new()
	top_hbox.add_theme_constant_override("separation", 8)
	top_bar.add_child(top_hbox)

	piece_title_label = Label.new()
	piece_title_label.text = "Piece: Ode to Joy (Monophonic)"
	piece_title_label.add_theme_font_size_override("font_size", 14)
	piece_title_label.add_theme_color_override("font_color", Color(0.95, 0.98, 1.0))
	piece_title_label.custom_minimum_size = Vector2(220, 0)
	top_hbox.add_child(piece_title_label)

	var btn_configs: Array[Dictionary] = [
		{"label": "[1] Ode to Joy", "piece": "piece_1_monophonic", "omr": false},
		{"label": "[2] Bach Minuet", "piece": "piece_2_harmony", "omr": false},
		{"label": "[3] Triads", "piece": "piece_3_polyphonic", "omr": false},
		{"label": "[O] OMR Scan", "piece": "", "omr": true},
		{"label": "[R] Restart", "piece": "__restart__", "omr": false}
	]
	for cfg in btn_configs:
		var b := Button.new()
		b.text = String(cfg["label"])
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		var p_id: String = String(cfg["piece"])
		var is_omr: bool = bool(cfg["omr"])
		b.pressed.connect(func(): piece_selected.emit(p_id, is_omr))
		top_hbox.add_child(b)

	custom_song_button = Button.new()
	custom_song_button.name = "CustomSongButton"
	custom_song_button.text = "[+] Custom Song"
	custom_song_button.focus_mode = Control.FOCUS_NONE
	custom_song_button.add_theme_font_size_override("font_size", 12)
	custom_song_button.pressed.connect(_on_custom_song_button_pressed)
	top_hbox.add_child(custom_song_button)

	# Bottom Audio, Oscilloscope & Inference Diagnostic Dock (Y = 542..688, compact 146px height)
	diagnostic_dock = PanelContainer.new()
	diagnostic_dock.name = "AudioInferenceDock"
	diagnostic_dock.position = Vector2(20, 542)
	diagnostic_dock.size = Vector2(1240, 146)

	var dock_style := StyleBoxFlat.new()
	dock_style.bg_color = Color(0.05, 0.07, 0.12, 0.94)
	dock_style.border_color = Color(0.20, 0.35, 0.55, 0.90)
	dock_style.set_border_width_all(2)
	dock_style.set_corner_radius_all(8)
	dock_style.content_margin_left = 12
	dock_style.content_margin_right = 12
	dock_style.content_margin_top = 8
	dock_style.content_margin_bottom = 8
	diagnostic_dock.add_theme_stylebox_override("panel", dock_style)
	add_child(diagnostic_dock)
	_build_custom_song_modal()

	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 14)
	diagnostic_dock.add_child(main_hbox)

	# --- Column 1: Microphone Selection & Input Status (Width: 350px) ---
	var mic_vbox := VBoxContainer.new()
	mic_vbox.custom_minimum_size = Vector2(350, 126)
	mic_vbox.add_theme_constant_override("separation", 4)
	main_hbox.add_child(mic_vbox)

	var mic_header_hbox := HBoxContainer.new()
	mic_header_hbox.add_theme_constant_override("separation", 8)
	mic_vbox.add_child(mic_header_hbox)

	var mic_title := Label.new()
	mic_title.text = "MICROPHONE INPUT"
	mic_title.add_theme_font_size_override("font_size", 14)
	mic_title.add_theme_color_override("font_color", Color(0.0, 0.92, 1.0))
	mic_header_hbox.add_child(mic_title)

	mic_status_label = Label.new()
	mic_status_label.name = "MicStatusLabel"
	mic_status_label.text = "● CAPTURING"
	mic_status_label.add_theme_font_size_override("font_size", 13)
	mic_status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	mic_header_hbox.add_child(mic_status_label)

	var dev_label := Label.new()
	dev_label.text = "Select Input Device:"
	dev_label.add_theme_font_size_override("font_size", 12)
	dev_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.90))
	mic_vbox.add_child(dev_label)

	var dropdown_hbox := HBoxContainer.new()
	dropdown_hbox.add_theme_constant_override("separation", 6)
	mic_vbox.add_child(dropdown_hbox)

	mic_dropdown = OptionButton.new()
	mic_dropdown.name = "MicDropdown"
	mic_dropdown.custom_minimum_size = Vector2(285, 30)
	mic_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_dropdown.focus_mode = Control.FOCUS_NONE
	mic_dropdown.clip_text = true
	mic_dropdown.add_theme_font_size_override("font_size", 13)
	mic_dropdown.item_selected.connect(_on_mic_dropdown_item_selected)
	dropdown_hbox.add_child(mic_dropdown)

	refresh_mic_button = Button.new()
	refresh_mic_button.name = "RefreshMicButton"
	refresh_mic_button.text = "↻"
	refresh_mic_button.tooltip_text = "Refresh Microphone Devices"
	refresh_mic_button.custom_minimum_size = Vector2(32, 30)
	refresh_mic_button.focus_mode = Control.FOCUS_NONE
	refresh_mic_button.pressed.connect(_on_refresh_mic_pressed)
	dropdown_hbox.add_child(refresh_mic_button)

	mic_level_label = Label.new()
	mic_level_label.name = "MicLevelLabel"
	mic_level_label.text = "Level: -100.0 dB  |  RMS: 0.0000  |  Frames: 0"
	mic_level_label.add_theme_font_size_override("font_size", 12)
	mic_level_label.add_theme_color_override("font_color", Color(0.85, 0.90, 0.96))
	mic_vbox.add_child(mic_level_label)

	var test_hbox := HBoxContainer.new()
	test_hbox.add_theme_constant_override("separation", 8)
	mic_vbox.add_child(test_hbox)

	test_signal_button = Button.new()
	test_signal_button.name = "TestSignalButton"
	test_signal_button.text = "🔊 Inject Test Chord (Verify Scope + Model)"
	test_signal_button.custom_minimum_size = Vector2(280, 26)
	test_signal_button.focus_mode = Control.FOCUS_NONE
	test_signal_button.add_theme_font_size_override("font_size", 11)
	test_signal_button.pressed.connect(func(): test_signal_requested.emit())
	test_hbox.add_child(test_signal_button)

	# --- Column 2: Real-Time Oscilloscope View (Width: 440px, Height: 126px) ---
	oscilloscope_view = OscilloscopeViewScript.new()
	oscilloscope_view.name = "OscilloscopeView"
	oscilloscope_view.custom_minimum_size = Vector2(440, 126)
	oscilloscope_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oscilloscope_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(oscilloscope_view)

	# --- Column 3: Inference Model Telemetry & Detected Pitches (Width: 350px) ---
	var inf_vbox := VBoxContainer.new()
	inf_vbox.custom_minimum_size = Vector2(350, 126)
	inf_vbox.add_theme_constant_override("separation", 4)
	main_hbox.add_child(inf_vbox)

	var inf_title := Label.new()
	inf_title.text = "POLYPHONIC INFERENCE MODEL"
	inf_title.add_theme_font_size_override("font_size", 14)
	inf_title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	inf_vbox.add_child(inf_title)

	inference_backend_label = Label.new()
	inference_backend_label.name = "InferenceBackendLabel"
	inference_backend_label.text = "● Engine: Initializing..."
	inference_backend_label.add_theme_font_size_override("font_size", 13)
	inference_backend_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.55))
	inf_vbox.add_child(inference_backend_label)

	inference_metrics_label = Label.new()
	inference_metrics_label.name = "InferenceMetricsLabel"
	inference_metrics_label.text = "Latency: 0.0 ms  |  Inferences: 0"
	inference_metrics_label.add_theme_font_size_override("font_size", 12)
	inference_metrics_label.add_theme_color_override("font_color", Color(0.78, 0.85, 0.94))
	inf_vbox.add_child(inference_metrics_label)

	var notes_box := PanelContainer.new()
	var notes_style := StyleBoxFlat.new()
	notes_style.bg_color = Color(0.03, 0.05, 0.09, 0.95)
	notes_style.border_color = Color(0.25, 0.45, 0.68, 0.85)
	notes_style.set_border_width_all(1)
	notes_style.set_corner_radius_all(5)
	notes_style.content_margin_left = 10
	notes_style.content_margin_right = 10
	notes_style.content_margin_top = 6
	notes_style.content_margin_bottom = 6
	notes_box.add_theme_stylebox_override("panel", notes_style)
	inf_vbox.add_child(notes_box)

	var notes_inner := VBoxContainer.new()
	notes_inner.add_theme_constant_override("separation", 4)
	notes_box.add_child(notes_inner)

	detected_notes_label = Label.new()
	detected_notes_label.name = "DetectedNotesLabel"
	detected_notes_label.text = "Active Notes: — (Sing or Play)"
	detected_notes_label.add_theme_font_size_override("font_size", 15)
	detected_notes_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
	detected_notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes_inner.add_child(detected_notes_label)

	last_onset_label = Label.new()
	last_onset_label.name = "LastOnsetLabel"
	last_onset_label.text = "Last Onset: —"
	last_onset_label.add_theme_font_size_override("font_size", 12)
	last_onset_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	notes_inner.add_child(last_onset_label)

	refresh_microphone_dropdown()

## Populates the microphone OptionButton dropdown with AudioServer.get_input_device_list()
func refresh_microphone_dropdown(devices: PackedStringArray = PackedStringArray(), active_device: String = "") -> void:
	if mic_dropdown == null:
		return
	var dev_list: PackedStringArray = devices
	if dev_list.is_empty():
		dev_list = AudioServer.get_input_device_list()
	if dev_list.is_empty():
		dev_list = PackedStringArray(["Default"])

	var current_dev: String = active_device if not active_device.is_empty() else AudioServer.input_device
	if current_dev.is_empty():
		current_dev = dev_list[0]

	mic_dropdown.clear()
	var selected_idx: int = 0
	for i in range(dev_list.size()):
		var d_name: String = dev_list[i]
		mic_dropdown.add_item(d_name, i)
		if d_name == current_dev:
			selected_idx = i

	if mic_dropdown.item_count > 0:
		mic_dropdown.select(selected_idx)

func _on_mic_dropdown_item_selected(index: int) -> void:
	if mic_dropdown == null or index < 0 or index >= mic_dropdown.item_count:
		return
	var device_name: String = mic_dropdown.get_item_text(index)
	mic_device_selected.emit(device_name)

func _on_refresh_mic_pressed() -> void:
	refresh_microphone_dropdown()
	refresh_mics_requested.emit()

## Updates the oscilloscope and microphone telemetry readout.
func update_audio_telemetry(waveform: PackedFloat32Array, rms: float, rms_db: float, is_gated: bool, is_capturing: bool, total_frames: int, sample_rate: int = 48000) -> void:
	if oscilloscope_view != null and oscilloscope_view.has_method("update_waveform"):
		oscilloscope_view.update_waveform(waveform, rms, rms_db, is_gated, sample_rate)

	if mic_status_label != null:
		if not is_capturing:
			mic_status_label.text = "● STOPPED"
			mic_status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.35))
		elif is_gated:
			mic_status_label.text = "● CAPTURING (Idle / Gate Closed)"
			mic_status_label.add_theme_color_override("font_color", Color(0.45, 0.85, 1.0))
		else:
			mic_status_label.text = "● SIGNAL ACTIVE (Gate Open)"
			mic_status_label.add_theme_color_override("font_color", Color(0.15, 1.0, 0.50))

	if mic_level_label != null:
		var db_str: String = "%.1f dB" % maxf(-60.0, rms_db) if rms_db > -90.0 else "-INF dB"
		mic_level_label.text = "Level: %s  |  RMS: %.4f  |  Frames: %d" % [db_str, rms, total_frames]

## Updates the inference model telemetry panel.
func update_inference_telemetry(status: Dictionary, recent_onsets: Array[int] = []) -> void:
	var backend: String = String(status.get("backend", "Unknown"))
	var is_conn: bool = bool(status.get("is_connected", false))
	var is_ready: bool = bool(status.get("is_ready", false))
	var latency_ms: float = float(status.get("latency_ms", 0.0))
	var inf_count: int = int(status.get("inference_count", 0))
	var pitches: Array = status.get("pitches", [])
	var conf_map: Dictionary = status.get("confidence", {})

	if inference_backend_label != null:
		inference_backend_label.text = "● %s" % backend
		if is_conn:
			inference_backend_label.add_theme_color_override("font_color", Color(0.15, 1.0, 0.55))
		elif is_ready:
			inference_backend_label.add_theme_color_override("font_color", Color(0.25, 0.88, 1.0))
		else:
			inference_backend_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.2))

	if inference_metrics_label != null:
		inference_metrics_label.text = "Latency: %.1f ms  |  Inferences: %d" % [latency_ms, inf_count]

	if detected_notes_label != null:
		if pitches.is_empty():
			detected_notes_label.text = "Active Notes: — (Sing or Play into Mic)"
			detected_notes_label.add_theme_color_override("font_color", Color(0.55, 0.68, 0.82))
		else:
			var parts: PackedStringArray = PackedStringArray()
			for p in pitches:
				var midi: int = int(p)
				var p_name: String = NoteDataScript.midi_to_pitch_name(midi)
				var conf_val: float = float(conf_map.get(str(midi), 0.0))
				if conf_val > 0.0:
					parts.append("%s (%d) [%d%%]" % [p_name, midi, int(round(conf_val * 100.0))])
				else:
					parts.append("%s (%d)" % [p_name, midi])
			detected_notes_label.text = "Active Notes: " + "   ".join(parts)
			detected_notes_label.add_theme_color_override("font_color", Color(0.20, 1.0, 0.55))

	if not recent_onsets.is_empty() and last_onset_label != null:
		var onset_parts: PackedStringArray = PackedStringArray()
		for o in recent_onsets:
			var m: int = int(o)
			onset_parts.append("%s (%d)" % [NoteDataScript.midi_to_pitch_name(m), m])
		_last_onset_text = "Last Onset: " + ", ".join(onset_parts)
		last_onset_label.text = _last_onset_text
		_onset_flash_timer = 0.6

func update_piece_title(piece_id: String, via_omr: bool = false) -> void:
	if piece_title_label == null:
		return
	var pretty: String = piece_id
	match piece_id:
		"piece_1_monophonic", "ode_to_joy":
			pretty = "Ode to Joy (Monophonic)"
		"piece_2_harmony", "bach_minuet":
			pretty = "Bach Minuet (2-Part Harmony)"
		"piece_3_polyphonic", "cadence_triads":
			pretty = "Cadence & Triads (Polyphonic)"
		"demo":
			pretty = "Full Range Demo Chart"
	if via_omr:
		pretty += " [OMR Scanned]"
	piece_title_label.text = "Piece: " + pretty

func update_score(new_score: int) -> void:
	if score_value == null:
		return
	if score_tween:
		score_tween.kill()

	score_tween = create_tween()
	score_tween.tween_method(func(val: int):
		displayed_score = val
		score_value.text = "%06d" % val
	, displayed_score, new_score, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func update_combo(combo: int, multiplier: int) -> void:
	if combo_container == null:
		return

	if combo < 2:
		combo_container.modulate.a = 0.0
	else:
		combo_container.modulate.a = 1.0
		combo_label.text = "%d COMBO" % combo

		# Scale bounce on combo increment
		var t: Tween = create_tween()
		combo_container.scale = Vector2(1.2, 1.2)
		t.tween_property(combo_container, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	multiplier_label.text = "%dx" % multiplier
	match multiplier:
		1:
			multiplier_label.modulate = COLOR_MULT_1X
		2:
			multiplier_label.modulate = COLOR_MULT_2X
		3:
			multiplier_label.modulate = COLOR_MULT_3X
		4:
			multiplier_label.modulate = COLOR_MULT_4X

func spawn_judgment_popup(judgment: String, pos: Vector2) -> void:
	if judgment_layer == null:
		return

	var label: Label = Label.new()
	label.text = judgment + "!"
	label.position = pos - Vector2(50, 15)
	label.pivot_offset = Vector2(50, 15)

	match judgment:
		"PERFECT":
			label.modulate = COLOR_PERFECT
			label.add_theme_font_size_override("font_size", 30)
		"GOOD":
			label.modulate = COLOR_GOOD
			label.add_theme_font_size_override("font_size", 26)
		"MISS":
			label.text = "MISS"
			label.modulate = COLOR_MISS
			label.add_theme_font_size_override("font_size", 24)

	judgment_layer.add_child(label)

	var tween: Tween = create_tween().set_parallel(true)
	# Float upward
	tween.tween_property(label, "position:y", label.position.y - 35.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Scale punch
	label.scale = Vector2(1.3, 1.3)
	tween.tween_property(label, "scale", Vector2.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade out
	var alpha_tween: Tween = create_tween()
	alpha_tween.tween_interval(0.2)
	alpha_tween.tween_property(label, "modulate:a", 0.0, 0.25)
	alpha_tween.tween_callback(label.queue_free)

## Adapts HUD margins for iPhone Notch / Dynamic Island and mobile safe areas.
func _apply_mobile_safe_area() -> void:
	if not (OS.get_name() in ["iOS", "Android"]):
		return
	if DisplayServer.get_name() == "headless":
		return
	var safe_rect: Rect2i = DisplayServer.get_display_safe_area()
	var win_size: Vector2i = DisplayServer.window_get_size()
	if win_size.x <= 0 or win_size.y <= 0 or safe_rect.size.x <= 0:
		return
	var scale_x: float = 1280.0 / float(win_size.x)
	var scale_y: float = 720.0 / float(win_size.y)
	var left_inset: float = maxf(20.0, float(safe_rect.position.x) * scale_x + 8.0)
	var top_inset: float = maxf(16.0, float(safe_rect.position.y) * scale_y + 8.0)
	var right_inset: float = maxf(20.0, float(win_size.x - (safe_rect.position.x + safe_rect.size.x)) * scale_x + 8.0)
	var bottom_inset: float = maxf(8.0, float(win_size.y - (safe_rect.position.y + safe_rect.size.y)) * scale_y + 6.0)

	if top_info_bar != null:
		top_info_bar.position = Vector2(left_inset, top_inset)
	if diagnostic_dock != null:
		var dock_w: float = maxf(960.0, 1280.0 - left_inset - right_inset)
		var dock_h: float = 146.0
		var dock_y: float = clampf(720.0 - dock_h - bottom_inset, 510.0, 545.0)
		diagnostic_dock.position = Vector2(left_inset, dock_y)
		diagnostic_dock.size = Vector2(dock_w, dock_h)

func _build_custom_song_modal() -> void:
	if custom_song_modal != null:
		return

	custom_song_modal = PanelContainer.new()
	custom_song_modal.name = "CustomSongModal"
	custom_song_modal.visible = false
	custom_song_modal.position = Vector2(300, 130)
	custom_song_modal.size = Vector2(680, 340)

	var modal_style := StyleBoxFlat.new()
	modal_style.bg_color = Color(0.05, 0.08, 0.14, 0.98)
	modal_style.border_color = Color(0.25, 0.65, 1.0, 0.95)
	modal_style.set_border_width_all(2)
	modal_style.set_corner_radius_all(10)
	modal_style.content_margin_left = 20
	modal_style.content_margin_right = 20
	modal_style.content_margin_top = 16
	modal_style.content_margin_bottom = 16
	custom_song_modal.add_theme_stylebox_override("panel", modal_style)
	add_child(custom_song_modal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	custom_song_modal.add_child(vbox)

	var title := Label.new()
	title.text = "IMPORT CUSTOM SHEET MUSIC & BACKING TRACK"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Select a sheet music image (PNG/JPG) for on-device OMR digitization or a JSON chart, paired with an audio file (WAV/MP3/OGG)."
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(subtitle)

	# Row 1: Sheet music image / chart
	var sheet_row := HBoxContainer.new()
	sheet_row.add_theme_constant_override("separation", 8)
	vbox.add_child(sheet_row)

	var sheet_lbl := Label.new()
	sheet_lbl.text = "Sheet Music / Chart:"
	sheet_lbl.custom_minimum_size = Vector2(145, 0)
	sheet_lbl.add_theme_font_size_override("font_size", 13)
	sheet_row.add_child(sheet_lbl)

	custom_sheet_input = LineEdit.new()
	custom_sheet_input.name = "CustomSheetInput"
	custom_sheet_input.text = "res://assets/test_pieces/piece_1_monophonic/score.png"
	custom_sheet_input.placeholder_text = "Path to sheet music (.png, .jpg) or chart (.json)"
	custom_sheet_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_row.add_child(custom_sheet_input)

	var browse_sheet_btn := Button.new()
	browse_sheet_btn.text = "Browse..."
	browse_sheet_btn.pressed.connect(func():
		if sheet_file_dialog != null:
			sheet_file_dialog.popup_centered(Vector2i(720, 460))
	)
	sheet_row.add_child(browse_sheet_btn)

	# Row 2: Backing audio track
	var audio_row := HBoxContainer.new()
	audio_row.add_theme_constant_override("separation", 8)
	vbox.add_child(audio_row)

	var audio_lbl := Label.new()
	audio_lbl.text = "Audio File (WAV/MP3/OGG):"
	audio_lbl.custom_minimum_size = Vector2(145, 0)
	audio_lbl.add_theme_font_size_override("font_size", 13)
	audio_row.add_child(audio_lbl)

	custom_audio_input = LineEdit.new()
	custom_audio_input.name = "CustomAudioInput"
	custom_audio_input.text = "res://assets/test_pieces/piece_1_monophonic/audio.wav"
	custom_audio_input.placeholder_text = "Path to backing audio (.wav, .mp3, .ogg)"
	custom_audio_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	audio_row.add_child(custom_audio_input)

	var browse_audio_btn := Button.new()
	browse_audio_btn.text = "Browse..."
	browse_audio_btn.pressed.connect(func():
		if audio_file_dialog != null:
			audio_file_dialog.popup_centered(Vector2i(720, 460))
	)
	audio_row.add_child(browse_audio_btn)

	# Row 3: Tempo (BPM)
	var bpm_row := HBoxContainer.new()
	bpm_row.add_theme_constant_override("separation", 8)
	vbox.add_child(bpm_row)

	var bpm_lbl := Label.new()
	bpm_lbl.text = "Tempo (BPM):"
	bpm_lbl.custom_minimum_size = Vector2(145, 0)
	bpm_lbl.add_theme_font_size_override("font_size", 13)
	bpm_row.add_child(bpm_lbl)

	custom_bpm_spin = SpinBox.new()
	custom_bpm_spin.name = "CustomBpmSpin"
	custom_bpm_spin.min_value = 40.0
	custom_bpm_spin.max_value = 240.0
	custom_bpm_spin.step = 1.0
	custom_bpm_spin.value = 120.0
	bpm_row.add_child(custom_bpm_spin)

	# Action buttons
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 12)
	vbox.add_child(action_row)

	var load_btn := Button.new()
	load_btn.name = "ConfirmCustomSongButton"
	load_btn.text = "Digitize Sheet Music & Start Level"
	load_btn.custom_minimum_size = Vector2(240, 34)
	load_btn.pressed.connect(_on_confirm_custom_song_pressed)
	action_row.add_child(load_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(100, 34)
	cancel_btn.pressed.connect(func(): custom_song_modal.visible = false)
	action_row.add_child(cancel_btn)

	# Native/In-Engine FileDialogs for iOS / Android / Desktop
	sheet_file_dialog = FileDialog.new()
	sheet_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	sheet_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	sheet_file_dialog.use_native_dialog = true
	sheet_file_dialog.filters = PackedStringArray([
		"*.png, *.jpg, *.jpeg ; Sheet Music Images",
		"*.json ; Note Highway Charts"
	])
	sheet_file_dialog.file_selected.connect(func(path: String):
		if custom_sheet_input != null:
			custom_sheet_input.text = path
	)
	add_child(sheet_file_dialog)

	audio_file_dialog = FileDialog.new()
	audio_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	audio_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	audio_file_dialog.use_native_dialog = true
	audio_file_dialog.filters = PackedStringArray([
		"*.wav, *.mp3, *.ogg ; Audio Files"
	])
	audio_file_dialog.file_selected.connect(func(path: String):
		if custom_audio_input != null:
			custom_audio_input.text = path
	)
	add_child(audio_file_dialog)

func _on_custom_song_button_pressed() -> void:
	if custom_song_modal != null:
		custom_song_modal.visible = not custom_song_modal.visible

func _on_confirm_custom_song_pressed() -> void:
	var sheet_path: String = custom_sheet_input.text.strip_edges() if custom_sheet_input != null else ""
	var audio_path: String = custom_audio_input.text.strip_edges() if custom_audio_input != null else ""
	var bpm_val: float = float(custom_bpm_spin.value) if custom_bpm_spin != null else 120.0
	if custom_song_modal != null:
		custom_song_modal.visible = false
	if not sheet_path.is_empty():
		custom_song_requested.emit(sheet_path, audio_path, bpm_val)
