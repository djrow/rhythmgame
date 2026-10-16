# res://tests/test_inference_scoring_runner.gd
extends SceneTree

# Comprehensive Headless Verification Test for Milestone 3 Audio Inference & Scoring Integration

const ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
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

func _create_mock_driver() -> RefCounted:
	if ResourceLoader.exists("res://scripts/inference/mock_driver.gd"):
		var S = load("res://scripts/inference/mock_driver.gd")
		if S:
			return S.new()
	var Fallback = load("res://scripts/inference/audio_pitch_model.gd")
	return Fallback.new()

func _init() -> void:
	print("==================================================")
	print(" RUNNING FULL INFERENCE & SCORING VERIFICATION    ")
	print("==================================================")

	test_suite_1_audio_capture_bus_and_lifecycle()
	test_suite_2_stereo_downmix_and_noise_gate()
	test_suite_3_mock_driver_integration()
	test_suite_4_polyphonic_cluster_matching()
	test_suite_5_partial_chords_and_miss_handling()
	test_suite_6_sustain_retrigger_filtering()
	test_suite_7_end_to_end_gameplay_chain()
	test_suite_8_oscilloscope_mic_dropdown_and_live_dsp()
	test_suite_9_native_onnx_driver_pipeline()
	test_suite_10_custom_song_import_and_ios_readiness()

	print("==================================================")
	print(" RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("==================================================")

	if tests_failed == 0:
		print("ALL INFERENCE & SCORING SUITES PASSED [OK]")
		quit(0)
	else:
		push_error("VERIFICATION FAILED with %d errors" % tests_failed)
		quit(1)

func test_suite_1_audio_capture_bus_and_lifecycle() -> void:
	print("\n--- Test Suite 1: AudioCapture Record Bus & Lifecycle ---")
	var AudioCaptureScript = load("res://scripts/audio_capture.gd")
	assert_true(AudioCaptureScript != null, "AudioCapture script loads cleanly")
	
	var cap = AudioCaptureScript.new()
	cap.auto_start = false
	root.add_child(cap)
	
	assert_eq(cap.is_capturing, false, "Initial capturing state is false")
	assert_true(cap.record_bus_idx >= 0, "Record bus index resolved successfully")
	assert_true(cap.capture_effect != null, "AudioEffectCapture attached to Record bus")
	
	cap.start_capture()
	assert_eq(cap.is_capturing, true, "Capture started successfully")
	
	cap.stop_capture()
	assert_eq(cap.is_capturing, false, "Capture stopped successfully")
	
	cap.free()

func test_suite_2_stereo_downmix_and_noise_gate() -> void:
	print("\n--- Test Suite 2: Stereo Downmix & RMS Noise Gating (-45 dB) ---")
	var AudioCaptureScript = load("res://scripts/audio_capture.gd")
	var cap = AudioCaptureScript.new()
	var mock = _create_mock_driver()
	cap.set_pitch_model(mock)
	
	# Test stereo to mono downmix
	var stereo_test = PackedVector2Array([
		Vector2(1.0, 1.0),
		Vector2(-0.8, -0.2),
		Vector2(0.5, -0.5)
	])
	var mono = cap.process_stereo_buffer(stereo_test)
	assert_eq(mono[0], 1.0, "Stereo (1.0, 1.0) -> Mono 1.0")
	assert_true(abs(mono[1] - (-0.5)) < 0.0001, "Stereo (-0.8, -0.2) -> Mono -0.5")
	assert_eq(mono[2], 0.0, "Stereo (0.5, -0.5) -> Mono 0.0")

	# Test silence gating
	mock.reset()
	var silence = PackedVector2Array()
	silence.resize(256)
	silence.fill(Vector2.ZERO)
	cap.process_stereo_buffer(silence)
	assert_eq(cap.current_rms, 0.0, "Silence RMS is 0.0")
	assert_eq(cap.current_rms_db, -100.0, "Silence dB is -100 dB")
	assert_true(cap.is_currently_gated, "Silence is gated")
	assert_eq(mock._samples_processed, 256, "Zeroes pushed during silence to preserve clock")

	# Test room noise suppression (< 0.005 RMS / -46 dB)
	mock.reset()
	var noise = PackedVector2Array()
	noise.resize(256)
	noise.fill(Vector2(0.003, 0.003)) # 0.003 < 0.005 threshold
	cap.process_stereo_buffer(noise)
	assert_true(cap.current_rms < 0.005, "Noise RMS < 0.005 threshold")
	assert_true(cap.is_currently_gated, "Room noise suppressed by noise gate")

	# Test musical signal passing (> 0.005 RMS)
	mock.reset()
	var tone = PackedVector2Array()
	tone.resize(256)
	for i in range(256):
		var v = 0.4 * sin(float(i) * 0.1)
		tone[i] = Vector2(v, v)
	cap.process_stereo_buffer(tone)
	assert_true(cap.current_rms > 0.05, "Musical tone RMS is > 0.05")
	assert_true(not cap.is_currently_gated, "Musical tone passes noise gate")
	assert_eq(mock._samples_processed, 256, "Active audio samples received by model runner")
	
	cap.free()

func test_suite_3_mock_driver_integration() -> void:
	print("\n--- Test Suite 3: MockDriver & AudioPitchModel Protocol ---")
	var mock = _create_mock_driver()
	
	assert_true(mock.is_model_ready(), "MockDriver is immediately ready")
	assert_eq(mock.get_detected_pitches().size(), 0, "Initial detected pitches is empty")
	assert_eq(mock.get_recent_onsets().size(), 0, "Initial recent onsets is empty")

	# Programmatic pitch and onset injection
	mock.set_detected_pitches([60, 64, 67])
	mock.set_recent_onsets([60])
	assert_eq(mock.get_detected_pitches(), [60, 64, 67], "Detected pitches updated to [60, 64, 67]")
	assert_eq(mock.get_recent_onsets(), [60], "Recent onsets updated to [60]")

	# Test WebSocketDriver structure
	var WsScript = load("res://scripts/inference/websocket_driver.gd")
	assert_true(WsScript != null, "WebSocketDriver script loads cleanly")
	var ws_driver = WsScript.new("ws://127.0.0.1:8765")
	assert_eq(ws_driver.is_model_ready(), false, "WebSocket driver initial readiness is false until connected")
	ws_driver.disconnect_from_server()

func test_suite_4_polyphonic_cluster_matching() -> void:
	print("\n--- Test Suite 4: Polyphonic Chord Matching (C Major Triad) ---")
	var scoring = ScoringEngineScript.new()
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false}, # C4
		{"pitch_midi": 64, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false}, # E4
		{"pitch_midi": 67, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false}  # G4
	]

	# All 3 chord tones arrive concurrently at time 1.02s (+20ms -> PERFECT)
	var chord_cluster = [60, 64, 67]
	var now: float = 1.02
	var hits: Array[Dictionary] = []

	for pitch in chord_cluster:
		var res = scoring.process_input(now, pitch, active_notes, 0)
		if not res.is_empty():
			hits.append(res)

	assert_eq(hits.size(), 3, "All 3 chord tones matched and scored concurrently")
	assert_eq(active_notes[0]["is_hit"], true, "C4 is_hit = true")
	assert_eq(active_notes[1]["is_hit"], true, "E4 is_hit = true")
	assert_eq(active_notes[2]["is_hit"], true, "G4 is_hit = true")
	assert_eq(scoring.combo, 3, "Combo incremented to 3 for triad")
	assert_eq(scoring.score, 300, "Score awarded 300 points (3 x 100 Perfect)")
	assert_eq(scoring.count_perfect, 3, "3 Perfect counts recorded")

func test_suite_5_partial_chords_and_miss_handling() -> void:
	print("\n--- Test Suite 5: Partial Chord Match & Note Expiration ---")
	var scoring = ScoringEngineScript.new()
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 64, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 67, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false, "is_missed": false}
	]

	# User only plays C4 and E4, omitting G4
	var partial_cluster = [60, 64]
	var now: float = 2.01
	for p in partial_cluster:
		scoring.process_input(now, p, active_notes, 0)

	assert_eq(active_notes[0]["is_hit"], true, "C4 struck")
	assert_eq(active_notes[1]["is_hit"], true, "E4 struck")
	assert_eq(active_notes[2]["is_hit"], false, "G4 remains unhit")
	assert_eq(scoring.combo, 2, "Combo is 2")

	# Playhead passes beyond +100ms miss window (2.15s > 2.0s + 0.10s)
	var expired = scoring.check_expired_notes(2.15, active_notes)
	assert_eq(expired.size(), 1, "1 note expired (G4)")
	assert_eq(expired[0]["judgment"], "MISS", "G4 judged MISS")
	assert_eq(active_notes[2]["is_missed"], true, "G4 marked missed")
	assert_eq(scoring.combo, 0, "Combo reset to 0 by missed chord note")

func test_suite_6_sustain_retrigger_filtering() -> void:
	print("\n--- Test Suite 6: Sustain vs Onset Edge Retrigger Filtering ---")
	var scoring = ScoringEngineScript.new()
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 60, "time_sec": 2.5, "duration_sec": 1.0, "is_hit": false, "is_missed": false}
	]

	var last_detected_pitches: Array[int] = []

	# Frame 1: Note 1 attack
	var f1_onsets: Array[int] = [60]
	var f1_pitches: Array[int] = [60]
	var strikes: Array[int] = []
	for p in f1_onsets:
		strikes.append(p)
	for p in f1_pitches:
		if not last_detected_pitches.has(p) and not strikes.has(p):
			strikes.append(p)
	last_detected_pitches.clear()
	for p in f1_pitches:
		last_detected_pitches.append(p)

	for p in strikes:
		scoring.process_input(1.0, p, active_notes, 0)

	assert_eq(active_notes[0]["is_hit"], true, "Note 1 hit at 1.0s")
	assert_eq(scoring.combo, 1, "Combo is 1")

	# Frames 2..10: Holding sustain (detected_pitches has 60, onsets empty)
	for f in range(5):
		var fn_onsets: Array[int] = []
		var fn_pitches: Array[int] = [60]
		strikes.clear()
		for p in fn_onsets:
			strikes.append(p)
		for p in fn_pitches:
			if not last_detected_pitches.has(p) and not strikes.has(p):
				strikes.append(p)
		last_detected_pitches.clear()
		for p in fn_pitches:
			last_detected_pitches.append(p)

		assert_eq(strikes.size(), 0, "No duplicate strike during sustained note")
		for p in strikes:
			scoring.process_input(1.1 + float(f) * 0.1, p, active_notes, 0)

	assert_eq(scoring.combo, 1, "Combo preserved at 1 during sustain")
	assert_eq(active_notes[1]["is_hit"], false, "Subsequent note 2 at 2.5s untouched")

	# Frame 11: Release tone and re-attack Note 2 at 2.5s
	var f11_onsets: Array[int] = [60]
	var f11_pitches: Array[int] = [60]
	strikes.clear()
	for p in f11_onsets:
		strikes.append(p)
	for p in f11_pitches:
		if not last_detected_pitches.has(p) and not strikes.has(p):
			strikes.append(p)
	last_detected_pitches.clear()
	for p in f11_pitches:
		last_detected_pitches.append(p)

	for p in strikes:
		scoring.process_input(2.5, p, active_notes, 0)

	assert_eq(active_notes[1]["is_hit"], true, "Note 2 hit on new onset")
	assert_eq(scoring.combo, 2, "Combo reached 2")
	assert_eq(scoring.score, 200, "Score reached 200")

func test_suite_7_end_to_end_gameplay_chain() -> void:
	print("\n--- Test Suite 7: Full End-to-End Chain (Capture -> Model -> Matcher -> Scoring) ---")
	var AudioCaptureScript = load("res://scripts/audio_capture.gd")

	var cap = AudioCaptureScript.new()
	var mock = _create_mock_driver()
	cap.set_pitch_model(mock)
	cap.start_capture()

	var scoring = ScoringEngineScript.new()
	var test_chart = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.4, "is_hit": false, "is_missed": false}, # C4
		{"pitch_midi": 64, "time_sec": 2.0, "duration_sec": 0.4, "is_hit": false, "is_missed": false}, # E4
		{"pitch_midi": 67, "time_sec": 2.0, "duration_sec": 0.4, "is_hit": false, "is_missed": false}  # G4
	]

	# 1. Background room noise is gated
	var noise = PackedVector2Array()
	noise.resize(256)
	noise.fill(Vector2(0.002, 0.002))
	cap.process_stereo_buffer(noise)
	assert_true(cap.is_currently_gated, "Background noise gated")

	# 2. Player sings C4 tone at 1.02s
	var tone = PackedVector2Array()
	tone.resize(256)
	for i in range(256):
		tone[i] = Vector2(0.3, 0.3)
	cap.process_stereo_buffer(tone)
	assert_true(not cap.is_currently_gated, "Musical audio passed noise gate")
	
	# Model detects C4
	mock.set_detected_pitches([60])
	mock.set_recent_onsets([60])

	# Polyphonic cluster matcher evaluates
	var onsets = mock.get_recent_onsets()
	for p in onsets:
		scoring.process_input(1.02, p, test_chart, 0)

	assert_eq(test_chart[0]["is_hit"], true, "Note C4 scored from audio pipeline")
	assert_eq(scoring.combo, 1, "Combo is 1")

	# 3. Player plays chord (E4, G4) at 2.03s
	cap.process_stereo_buffer(tone)
	mock.set_detected_pitches([64, 67])
	mock.set_recent_onsets([64, 67])

	var chord_onsets = mock.get_recent_onsets()
	for p in chord_onsets:
		scoring.process_input(2.03, p, test_chart, 0)

	assert_eq(test_chart[1]["is_hit"], true, "Chord note E4 scored")
	assert_eq(test_chart[2]["is_hit"], true, "Chord note G4 scored")
	assert_eq(scoring.combo, 3, "Combo reached 3")

	var summary = scoring.get_summary()
	assert_eq(summary["total_notes"], 3, "3 total notes scored")
	assert_eq(summary["count_perfect"], 3, "All 3 scored PERFECT")
	assert_eq(summary["count_miss"], 0, "0 misses")
	assert_eq(summary["accuracy_pct"], 100.0, "100.0% accuracy")

	cap.free()

func test_suite_8_oscilloscope_mic_dropdown_and_live_dsp() -> void:
	print("\n--- Test Suite 8: OscilloscopeView, Mic Dropdown & Native Polyphonic DSP ---")
	var AudioCaptureScript = load("res://scripts/audio_capture.gd")
	var WsScript = load("res://scripts/inference/websocket_driver.gd")
	var HudScene = load("res://scenes/hud.tscn")

	var cap = AudioCaptureScript.new()
	cap.auto_start = false
	var ws_drv = WsScript.new("ws://127.0.0.1:28765")
	ws_drv.enable_dsp_fallback = true
	cap.set_pitch_model(ws_drv)

	var devices: PackedStringArray = cap.get_input_devices()
	assert_true(devices.size() >= 1, "AudioCapture enumerates at least 1 microphone device (%d found)" % devices.size())
	var switched: bool = cap.set_input_device(devices[0])
	assert_true(switched, "AudioCapture switches to microphone device '%s'" % devices[0])

	# Inject C Major Triad (60, 64, 67) into AudioCapture and verify Oscilloscope buffer + NativePitchDetector
	cap.inject_test_chord([60, 64, 67], 2048, 0.30)
	assert_eq(cap.oscilloscope_ring_buffer.size(), 512, "Oscilloscope ring buffer holds 512 samples")
	assert_true(cap.current_rms > 0.05, "Injected test chord produces positive RMS (%.3f)" % cap.current_rms)

	var detected: Array[int] = ws_drv.get_detected_pitches()
	assert_true(detected.has(60) and detected.has(64) and detected.has(67), "NativePitchDetector fallback detected C Major Triad [60, 64, 67]: got %s" % str(detected))

	var hud = HudScene.instantiate()
	root.add_child(hud)
	hud._build_diagnostic_ui()
	assert_true(hud.mic_dropdown != null and hud.mic_dropdown.item_count >= 1, "HUD MicDropdown OptionButton populated with input devices")
	assert_true(hud.oscilloscope_view != null, "HUD OscilloscopeView control instantiated")

	hud.update_audio_telemetry(cap.oscilloscope_ring_buffer, cap.current_rms, cap.current_rms_db, cap.is_currently_gated, true, cap.total_frames_captured, 48000)
	hud.update_inference_telemetry(ws_drv.get_status_summary(), ws_drv.pop_recent_onsets())
	assert_true(hud.detected_notes_label.text.find("C4 (60)") != -1, "HUD DetectedNotesLabel displays live detected note C4 (60): '%s'" % hud.detected_notes_label.text)
	assert_true(hud.oscilloscope_view.peak_amplitude > 0.05, "OscilloscopeView records non-zero waveform peak amplitude")

	hud.free()
	ws_drv.disconnect_from_server()
	cap.free()


func test_suite_9_native_onnx_driver_pipeline() -> void:
	print("\n--- Test Suite 9: Native ONNX (nmp.onnx) via WebSocketDriver worker pipeline ---")
	var WsScript = load("res://scripts/inference/websocket_driver.gd")
	var drv = WsScript.new("ws://127.0.0.1:28766")
	drv.enable_dsp_fallback = true
	drv.auto_reconnect = false
	if not drv.is_native_onnx_active():
		print("  [SKIP] native ONNX GDExtension not available on this platform")
		drv.disconnect_from_server()
		return
	assert_eq(drv.get_status_summary()["backend"], "ONNX Basic Pitch (Native On-Device)", "HUD backend reports native on-device ONNX")

	var sr: float = float(AudioServer.get_mix_rate())
	if sr <= 0.0:
		sr = 48000.0
	var n: int = int(sr * 2.5)
	var chord := PackedFloat32Array()
	chord.resize(n)
	for i in range(n):
		var t: float = float(i) / sr
		var v: float = 0.0
		for m in [60, 64, 67]:
			var f: float = 440.0 * pow(2.0, (float(m) - 69.0) / 12.0)
			v += sin(TAU * f * t) + 0.4 * sin(TAU * 2.0 * f * t)
		chord[i] = 0.08 * v

	var chunk: int = 1024
	var pos: int = 0
	var deadline: int = Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		if pos < n:
			drv.push_audio_samples(chord.slice(pos, mini(pos + chunk, n)))
			pos += chunk
		else:
			drv.poll()
		OS.delay_msec(8)
		var have: bool = drv.confidence_map.has("60") and drv.confidence_map.has("64") and drv.confidence_map.has("67")
		if have and pos >= n:
			break
	var det: Array[int] = drv.get_detected_pitches()
	assert_true(det.has(60) and det.has(64) and det.has(67), "Native ONNX pipeline detected C major triad from %d Hz audio: %s" % [int(sr), str(det)])
	assert_true(drv.confidence_map.has("60"), "ONNX confidence map populated (model output, not DSP)")
	assert_true(drv.last_latency_ms > 0.0, "ONNX inference latency recorded (%.1f ms)" % drv.last_latency_ms)
	drv.disconnect_from_server()

func test_suite_10_custom_song_import_and_ios_readiness() -> void:
	print("\n--- Test Suite 10: Custom Song Import Dialog & iOS Readiness ---")
	var main_scene_res = load("res://scenes/main.tscn")
	var main_node = main_scene_res.instantiate()
	main_node.enable_mic_capture = false
	main_node.auto_start_onnx_server = false
	root.add_child(main_node)

	var hud = main_node.get_node_or_null("HUD")
	var highway = main_node.get_node_or_null("Highway")
	var audio_player = main_node.get_node_or_null("AudioPlayer")
	main_node.hud = hud
	main_node.highway = highway
	main_node.audio_player = audio_player
	main_node.scoring_engine = ScoringEngineScript.new()
	main_node._setup_level_loader()
	hud._build_diagnostic_ui()
	hud._apply_mobile_safe_area()
	main_node._connect_hud_signals()

	assert_true(hud != null, "HUD node exists in Main scene")
	assert_true(hud.custom_song_button != null, "HUD Custom Song button initialized")
	assert_true(hud.custom_song_modal != null, "HUD CustomSongModal initialized")
	assert_true(hud.sheet_file_dialog != null, "HUD SheetFileDialog initialized")
	assert_true(hud.audio_file_dialog != null, "HUD AudioFileDialog initialized")

	# Simulate opening modal and submitting a custom song request via HUD
	hud._on_custom_song_button_pressed()
	assert_eq(hud.custom_song_modal.visible, true, "CustomSongModal opens when Custom Song button is pressed")

	hud.sheet_file_dialog.file_selected.emit("res://assets/test_pieces/piece_1_monophonic/score.png")
	hud.audio_file_dialog.file_selected.emit("res://assets/test_pieces/piece_1_monophonic/audio.wav")
	hud.custom_bpm_spin.value = 108.0
	hud._on_confirm_custom_song_pressed()

	assert_eq(hud.custom_song_modal.visible, false, "CustomSongModal closes after confirming load")
	assert_true(abs(float(main_node.level_loader.current_level_data.get("bpm", 0.0)) - 108.0) < 0.01, "Main.load_custom_song digitized score.png via OMR with custom BPM (108.0)")
	assert_true(main_node.highway.chart_notes.size() > 0, "Main.load_custom_song loaded notes into Highway (%d notes)" % main_node.highway.chart_notes.size())
	assert_true(main_node.audio_player.stream != null, "Main.load_custom_song paired custom audio.wav into AudioStreamPlayer")
	main_node.audio_player.stream = null

	main_node.free()


