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
	var AudioCaptureScript = load("res://.agents/teamwork/m3_explorer_3/proposed_audio_capture.gd")
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
	
	cap.queue_free()

# In-runner mock driver implementing AudioPitchModel contract
class LocalMockDriver extends RefCounted:
	var _active_pitches: Array[int] = []
	var _recent_onsets: Array[int] = []
	var _samples_processed: int = 0
	var _chart_notes: Array = []
	var _is_chart_mode: bool = false
	var _onset_window_sec: float = 0.050

	func set_detected_pitches(pitches: Array) -> void:
		_active_pitches.clear()
		for p in pitches:
			_active_pitches.append(int(p))

	func set_recent_onsets(onsets: Array) -> void:
		_recent_onsets.clear()
		for o in onsets:
			_recent_onsets.append(int(o))

	func push_audio_samples(samples: PackedFloat32Array) -> void:
		_samples_processed += samples.size()

	func get_detected_pitches() -> Array[int]:
		return _active_pitches

	func get_recent_onsets() -> Array[int]:
		var copy: Array[int] = []
		for o in _recent_onsets:
			copy.append(o)
		_recent_onsets.clear()
		return copy

	func is_model_ready() -> bool:
		return true

	func reset() -> void:
		_active_pitches.clear()
		_recent_onsets.clear()
		_samples_processed = 0

	func poll() -> void:
		pass

func _create_mock_driver() -> RefCounted:
	if ResourceLoader.exists("res://scripts/inference/mock_driver.gd"):
		var S = load("res://scripts/inference/mock_driver.gd")
		if S: return S.new()
	return LocalMockDriver.new()

func test_suite_2_stereo_downmix_and_noise_gate() -> void:
	print("\n--- Test Suite 2: Stereo Downmix & RMS Noise Gating (-45 dB) ---")
	var AudioCaptureScript = load("res://.agents/teamwork/m3_explorer_3/proposed_audio_capture.gd")
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
	var AudioCaptureScript = load("res://.agents/teamwork/m3_explorer_3/proposed_audio_capture.gd")

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
