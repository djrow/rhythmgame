# res://.agents/teamwork/m3_explorer_3/test_full_chain.gd
extends SceneTree

# Full end-to-end headless verification test for Milestone 3 AudioCapture & Polyphonic Scoring

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

# In-memory MockModel implementing IAudioPitchModel contract
class MockAudioPitchModel extends RefCounted:
	var pushed_samples: PackedFloat32Array = PackedFloat32Array()
	var detected_pitches: Array[int] = []
	var recent_onsets: Array[int] = []
	var is_ready: bool = true
	var poll_count: int = 0
	
	func push_audio_samples(samples: PackedFloat32Array) -> void:
		pushed_samples.append_array(samples)
	
	func get_detected_pitches() -> Array[int]:
		return detected_pitches
	
	func get_recent_onsets() -> Array[int]:
		var copy: Array[int] = []
		for p in recent_onsets:
			copy.append(p)
		recent_onsets.clear()
		return copy
	
	func is_model_ready() -> bool:
		return is_ready
	
	func poll() -> void:
		poll_count += 1
	
	func reset() -> void:
		pushed_samples.clear()
		detected_pitches.clear()
		recent_onsets.clear()
		poll_count = 0

# Concrete AudioCapture implementation for test
class AudioCaptureTestInstance extends Node:
	var record_bus_name: String = "Record"
	var min_chunk_frames: int = 256
	var rms_threshold: float = 0.005 # ~ -46 dB
	var push_silence_when_gated: bool = true
	var is_capturing: bool = false
	var pitch_model: MockAudioPitchModel = null
	
	var current_rms: float = 0.0
	var current_rms_db: float = -100.0
	var is_currently_gated: bool = false
	var chunks_processed: int = 0
	
	func set_pitch_model(model: MockAudioPitchModel) -> void:
		pitch_model = model
	
	func start_capture() -> void:
		is_capturing = true
	
	func stop_capture() -> void:
		is_capturing = false
	
	func calculate_rms(samples: PackedFloat32Array) -> float:
		if samples.is_empty():
			return 0.0
		var sum_sq: float = 0.0
		for i in range(samples.size()):
			var s: float = samples[i]
			sum_sq += s * s
		return sqrt(sum_sq / float(samples.size()))
	
	func process_stereo_buffer(stereo_buffer: PackedVector2Array) -> PackedFloat32Array:
		var n_frames: int = stereo_buffer.size()
		if n_frames == 0:
			return PackedFloat32Array()
		
		var mono: PackedFloat32Array = PackedFloat32Array()
		mono.resize(n_frames)
		var sum_squares: float = 0.0
		for i in range(n_frames):
			var s: float = (stereo_buffer[i].x + stereo_buffer[i].y) * 0.5
			mono[i] = s
			sum_squares += s * s
		
		var rms: float = sqrt(sum_squares / float(n_frames))
		current_rms = rms
		current_rms_db = 20.0 * log(rms) / log(10.0) if rms > 0.0000001 else -100.0
		is_currently_gated = (rms < rms_threshold)
		chunks_processed += 1
		
		var forward_samples: PackedFloat32Array = mono
		if is_currently_gated:
			if push_silence_when_gated:
				forward_samples = PackedFloat32Array()
				forward_samples.resize(n_frames)
				forward_samples.fill(0.0)
				if pitch_model:
					pitch_model.push_audio_samples(forward_samples)
		else:
			if pitch_model:
				pitch_model.push_audio_samples(forward_samples)
		
		return forward_samples

func _init() -> void:
	print("==================================================")
	print(" RUNNING INTEGRATED INFERENCE & SCORING SUITE    ")
	print("==================================================")

	test_suite_1_audio_capture_mechanics()
	test_suite_2_stereo_downmix_and_rms_gating()
	test_suite_3_polyphonic_cluster_matcher()
	test_suite_4_sustain_and_onset_separation()
	test_suite_5_end_to_end_chain()

	print("==================================================")
	print(" RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("==================================================")

	if tests_failed == 0:
		print("ALL INFERENCE & SCORING TESTS PASSED [OK]")
		quit(0)
	else:
		push_error("FAILED WITH %d ERRORS" % tests_failed)
		quit(1)

func test_suite_1_audio_capture_mechanics() -> void:
	print("\n--- Test Suite 1: AudioCapture Initialization & State ---")
	var cap = AudioCaptureTestInstance.new()
	assert_eq(cap.is_capturing, false, "Capture inactive initially")
	cap.start_capture()
	assert_eq(cap.is_capturing, true, "Capture starts successfully")
	cap.stop_capture()
	assert_eq(cap.is_capturing, false, "Capture stops successfully")

func test_suite_2_stereo_downmix_and_rms_gating() -> void:
	print("\n--- Test Suite 2: Stereo-to-Mono & RMS Gating (-45 dB) ---")
	var cap = AudioCaptureTestInstance.new()
	var model = MockAudioPitchModel.new()
	cap.set_pitch_model(model)
	cap.start_capture()

	# Test 1: Stereo downmix calculation
	var stereo_test = PackedVector2Array([
		Vector2(0.5, 0.5),   # average 0.5
		Vector2(-0.4, -0.6), # average -0.5
		Vector2(0.8, -0.8)   # average 0.0
	])
	var mono = cap.process_stereo_buffer(stereo_test)
	assert_eq(mono[0], 0.5, "Stereo (0.5, 0.5) downmixes to 0.5")
	assert_eq(mono[1], -0.5, "Stereo (-0.4, -0.6) downmixes to -0.5")
	assert_eq(mono[2], 0.0, "Stereo (0.8, -0.8) downmixes to 0.0")

	# Test 2: Silence gating
	model.reset()
	var silence_stereo = PackedVector2Array()
	silence_stereo.resize(256)
	silence_stereo.fill(Vector2.ZERO)
	cap.process_stereo_buffer(silence_stereo)
	assert_eq(cap.current_rms, 0.0, "Silence RMS is 0.0")
	assert_eq(cap.current_rms_db, -100.0, "Silence dB is -100 dB")
	assert_true(cap.is_currently_gated, "Silence is gated")
	assert_eq(model.pushed_samples.size(), 256, "Zeroed buffer pushed to maintain timing")
	assert_eq(model.pushed_samples[0], 0.0, "Pushed sample is 0.0")

	# Test 3: Low room noise suppression (< 0.005 RMS)
	model.reset()
	var room_noise = PackedVector2Array()
	room_noise.resize(256)
	room_noise.fill(Vector2(0.003, 0.003)) # 0.003 < 0.005 threshold (~ -50 dB)
	cap.process_stereo_buffer(room_noise)
	assert_true(cap.is_currently_gated, "Room noise (0.003 RMS) suppressed by noise gate")
	assert_eq(model.pushed_samples[0], 0.0, "Room noise zeroed before pushing to model")

	# Test 4: Musical signal passing (> 0.005 RMS)
	model.reset()
	var tone = PackedVector2Array()
	tone.resize(256)
	for i in range(256):
		var v = 0.3 * sin(float(i) * 0.1)
		tone[i] = Vector2(v, v)
	cap.process_stereo_buffer(tone)
	assert_true(cap.current_rms > 0.1, "Tone RMS is > 0.1")
	assert_true(not cap.is_currently_gated, "Tone is NOT gated")
	assert_true(abs(model.pushed_samples[10]) > 0.01, "Tone audio forwarded intact to model")

func test_suite_3_polyphonic_cluster_matcher() -> void:
	print("\n--- Test Suite 3: Polyphonic Cluster Matcher in Game Loop ---")
	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var scoring = ScoringEngineScript.new()

	# Create active chord: C Major Triad (C4=60, E4=64, G4=67) at time 1.0s
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 64, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 67, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false}
	]

	# Case 1: Model detects full chord cluster [60, 64, 67] at time 1.01s (+10ms -> PERFECT)
	var chord_cluster = [60, 64, 67]
	var now = 1.01
	var hits: Array[Dictionary] = []

	for p in chord_cluster:
		var res = scoring.process_input(now, p, active_notes, 0)
		if not res.is_empty():
			hits.append(res)

	assert_eq(hits.size(), 3, "All 3 notes in chord hit simultaneously")
	assert_eq(active_notes[0]["is_hit"], true, "C4 is_hit = true")
	assert_eq(active_notes[1]["is_hit"], true, "E4 is_hit = true")
	assert_eq(active_notes[2]["is_hit"], true, "G4 is_hit = true")
	assert_eq(scoring.combo, 3, "Combo incremented to 3 for triad")
	assert_eq(scoring.score, 300, "Score is 300 (3 x 100 Perfect)")
	assert_eq(scoring.count_perfect, 3, "3 Perfect counts recorded")

	# Case 2: Spurious background noise (MIDI 50) while notes are already hit
	var bogus_hit = scoring.process_input(now, 50, active_notes, 0)
	assert_true(bogus_hit.is_empty(), "Spurious pitch 50 rejected")
	assert_eq(scoring.score, 300, "Score remains 300")

func test_suite_4_sustain_and_onset_separation() -> void:
	print("\n--- Test Suite 4: Sustain & Onset Edge Separation ---")
	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var scoring = ScoringEngineScript.new()

	# Note 1 at 2.0s, Note 2 at 3.0s (both C4)
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 2.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 60, "time_sec": 3.0, "duration_sec": 1.0, "is_hit": false, "is_missed": false}
	]

	var last_detected: Array[int] = []

	# Frame 1: Attack on Note 1 at 2.0s
	var f1_onsets = [60]
	var f1_pitches = [60]
	var strikes: Array[int] = []
	for p in f1_onsets:
		strikes.append(p)
	for p in f1_pitches:
		if not last_detected.has(p) and not strikes.has(p):
			strikes.append(p)
	last_detected.clear()
	for p in f1_pitches:
		last_detected.append(p)

	for p in strikes:
		scoring.process_input(2.0, p, active_notes, 0)

	assert_eq(active_notes[0]["is_hit"], true, "Note 1 hit at 2.0s")
	assert_eq(scoring.combo, 1, "Combo is 1")

	# Frames 2..5: Player sustains C4 (pitch present, but onsets empty)
	for frame in range(4):
		var fn_onsets: Array[int] = []
		var fn_pitches: Array[int] = [60]
		strikes.clear()
		for p in fn_onsets:
			strikes.append(p)
		for p in fn_pitches:
			if not last_detected.has(p) and not strikes.has(p):
				strikes.append(p)
		last_detected.clear()
		for p in fn_pitches:
			last_detected.append(p)

		assert_eq(strikes.size(), 0, "No new strikes generated during sustained tone")
		for p in strikes:
			scoring.process_input(2.1 + float(frame) * 0.1, p, active_notes, 0)

	assert_eq(scoring.combo, 1, "Combo remained exactly 1 during sustain")
	assert_eq(active_notes[1]["is_hit"], false, "Note 2 at 3.0s untouched during Note 1 sustain")

	# Frame 6: Player releases tone, then re-attacks Note 2 at 3.0s
	var f6_onsets = [60]
	var f6_pitches = [60]
	strikes.clear()
	for p in f6_onsets:
		strikes.append(p)
	for p in f6_pitches:
		if not last_detected.has(p) and not strikes.has(p):
			strikes.append(p)
	last_detected.clear()
	for p in f6_pitches:
		last_detected.append(p)

	for p in strikes:
		scoring.process_input(3.0, p, active_notes, 0)

	assert_eq(active_notes[1]["is_hit"], true, "Note 2 hit cleanly on new onset")
	assert_eq(scoring.combo, 2, "Combo reached 2")
	assert_eq(scoring.score, 200, "Score reached 200")

func test_suite_5_end_to_end_chain() -> void:
	print("\n--- Test Suite 5: Complete Integrated Audio -> Model -> Scoring Chain ---")
	var cap = AudioCaptureTestInstance.new()
	var model = MockAudioPitchModel.new()
	cap.set_pitch_model(model)
	cap.start_capture()

	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var scoring = ScoringEngineScript.new()

	var chart = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5, "is_hit": false, "is_missed": false}, # C4
		{"pitch_midi": 64, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false, "is_missed": false}, # E4
		{"pitch_midi": 67, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false, "is_missed": false}  # G4 (chord with E4)
	]

	# Step 1: Push quiet room noise -> noise gate prevents audio propagation
	var noise = PackedVector2Array()
	noise.resize(256)
	noise.fill(Vector2(0.001, 0.001))
	cap.process_stereo_buffer(noise)
	assert_true(cap.is_currently_gated, "Ambient noise gated")

	# Step 2: Song time reaches 1.02s (+20ms). Audio tone arrives.
	var tone1 = PackedVector2Array()
	tone1.resize(256)
	for i in range(256):
		tone1[i] = Vector2(0.3, 0.3)
	cap.process_stereo_buffer(tone1)
	assert_true(not cap.is_currently_gated, "Tone 1 passed noise gate")
	
	# Model detects C4 onset
	var d1: Array[int] = [60]
	var o1: Array[int] = [60]
	model.detected_pitches = d1
	model.recent_onsets = o1
	
	# Matcher evaluates
	var onsets = model.get_recent_onsets()
	for p in onsets:
		scoring.process_input(1.02, p, chart, 0)

	assert_eq(chart[0]["is_hit"], true, "Note C4 hit from audio input")
	assert_eq(scoring.combo, 1, "Combo is 1")

	# Step 3: Song time reaches 2.04s (+40ms). Chord tone arrives.
	cap.process_stereo_buffer(tone1)
	var d2: Array[int] = [64, 67]
	var o2: Array[int] = [64, 67]
	model.detected_pitches = d2
	model.recent_onsets = o2

	var chord_onsets = model.get_recent_onsets()
	for p in chord_onsets:
		scoring.process_input(2.04, p, chart, 0)

	assert_eq(chart[1]["is_hit"], true, "Chord note E4 hit")
	assert_eq(chart[2]["is_hit"], true, "Chord note G4 hit")
	assert_eq(scoring.combo, 3, "Combo incremented by chord to 3")
	assert_eq(scoring.count_perfect, 3, "3 Perfect hits recorded")

	var summary = scoring.get_summary()
	assert_eq(summary["total_notes"], 3, "Total notes: 3")
	assert_eq(summary["count_miss"], 0, "Zero misses")
	assert_eq(summary["accuracy_pct"], 100.0, "100.0% accuracy")
