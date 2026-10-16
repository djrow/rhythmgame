extends SceneTree

# Prototype testing AudioCapture, Polyphonic Cluster Matcher, and Headless Runner mechanics

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
	print(" TESTING AUDIOCAPTURE & CLUSTER MATCHER MECHANICS ")
	print("==================================================")
	
	test_audio_capture_rms_and_gating()
	test_stereo_to_mono_normalization()
	test_cluster_matcher_monophonic()
	test_cluster_matcher_polyphonic_chord()
	test_cluster_matcher_partial_chord()
	test_cluster_matcher_sustain_retrigger_prevention()
	
	print("==================================================")
	print(" RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("==================================================")
	if tests_failed == 0:
		print("ALL PROTOTYPE TESTS PASSED [OK]")
		quit(0)
	else:
		printerr("PROTOTYPE TESTS FAILED")
		quit(1)

# Mock IAudioPitchModel for testing
class MockModel extends RefCounted:
	var pushed_samples: PackedFloat32Array = PackedFloat32Array()
	var detected_pitches: Array[int] = []
	var recent_onsets: Array[int] = []
	var ready: bool = true
	
	func push_audio_samples(samples: PackedFloat32Array) -> void:
		pushed_samples.append_array(samples)
	
	func get_detected_pitches() -> Array[int]:
		return detected_pitches
	
	func get_recent_onsets() -> Array[int]:
		var copy = recent_onsets.duplicate()
		recent_onsets.clear() # clear after polling
		return copy
	
	func is_model_ready() -> bool:
		return ready
	
	func poll() -> void:
		pass
	
	func reset() -> void:
		pushed_samples.clear()
		detected_pitches.clear()
		recent_onsets.clear()

# Mock AudioCapture logic for testing
class MockAudioCapture extends RefCounted:
	var rms_threshold: float = 0.005 # ~ -46 dB
	var push_silence_when_gated: bool = true
	var pitch_model: MockModel = null
	var last_rms: float = 0.0
	var last_is_gated: bool = false
	
	func calculate_rms(samples: PackedFloat32Array) -> float:
		if samples.is_empty():
			return 0.0
		var sum_sq: float = 0.0
		for i in range(samples.size()):
			var s: float = samples[i]
			sum_sq += s * s
		return sqrt(sum_sq / float(samples.size()))
	
	func process_stereo_buffer(stereo_buffer: PackedVector2Array) -> PackedFloat32Array:
		var n: int = stereo_buffer.size()
		var mono: PackedFloat32Array = PackedFloat32Array()
		mono.resize(n)
		for i in range(n):
			mono[i] = (stereo_buffer[i].x + stereo_buffer[i].y) * 0.5
		
		var rms: float = calculate_rms(mono)
		last_rms = rms
		last_is_gated = (rms < rms_threshold)
		
		if last_is_gated:
			if push_silence_when_gated:
				mono.fill(0.0)
				if pitch_model:
					pitch_model.push_audio_samples(mono)
		else:
			if pitch_model:
				pitch_model.push_audio_samples(mono)
		
		return mono

func test_audio_capture_rms_and_gating() -> void:
	print("\n--- Test Suite 1: AudioCapture RMS & Noise Gate ---")
	var cap = MockAudioCapture.new()
	var model = MockModel.new()
	cap.pitch_model = model
	
	# Silence buffer (1024 zeroes)
	var silence_stereo = PackedVector2Array()
	silence_stereo.resize(512)
	silence_stereo.fill(Vector2.ZERO)
	
	cap.process_stereo_buffer(silence_stereo)
	assert_eq(cap.last_rms, 0.0, "Silence RMS is 0.0")
	assert_true(cap.last_is_gated, "Silence is gated")
	assert_eq(model.pushed_samples.size(), 512, "Silence pushed as zeroed buffer")
	assert_eq(model.pushed_samples[0], 0.0, "Pushed sample is 0.0")
	
	# Low room noise (amplitude 0.002, below 0.005 threshold)
	model.reset()
	var noise_stereo = PackedVector2Array()
	noise_stereo.resize(512)
	noise_stereo.fill(Vector2(0.002, 0.002))
	
	cap.process_stereo_buffer(noise_stereo)
	assert_true(cap.last_rms < 0.005, "Low noise RMS is below 0.005 threshold")
	assert_true(cap.last_is_gated, "Low room noise is gated")
	assert_eq(model.pushed_samples[0], 0.0, "Low noise zeroed out when pushed")
	
	# Clear musical tone (amplitude 0.25, well above threshold)
	model.reset()
	var tone_stereo = PackedVector2Array()
	tone_stereo.resize(512)
	for i in range(512):
		var val = 0.25 * sin(float(i) * 0.2)
		tone_stereo[i] = Vector2(val, val)
	
	cap.process_stereo_buffer(tone_stereo)
	assert_true(cap.last_rms > 0.05, "Tone RMS is above noise threshold")
	assert_true(not cap.last_is_gated, "Tone is NOT gated")
	assert_true(abs(model.pushed_samples[10]) > 0.01, "Active audio samples pushed to model")

func test_stereo_to_mono_normalization() -> void:
	print("\n--- Test Suite 2: Stereo to Mono Normalization ---")
	var cap = MockAudioCapture.new()
	var stereo = PackedVector2Array([
		Vector2(1.0, 1.0),
		Vector2(-0.8, -0.4),
		Vector2(0.6, -0.6)
	])
	var mono = cap.process_stereo_buffer(stereo)
	assert_eq(mono[0], 1.0, "Stereo (1.0, 1.0) -> Mono 1.0")
	assert_true(abs(mono[1] - (-0.6)) < 0.0001, "Stereo (-0.8, -0.4) -> Mono -0.6")
	assert_eq(mono[2], 0.0, "Stereo (0.6, -0.6) -> Mono 0.0 (phase cancellation average)")

func test_cluster_matcher_monophonic() -> void:
	print("\n--- Test Suite 3: Monophonic Pitch Matching ---")
	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var scoring = ScoringEngineScript.new()
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5, "is_hit": false}
	]
	
	var res = scoring.process_input(1.02, 60, active_notes, 0)
	assert_eq(res.get("judgment"), "PERFECT", "Single C4 at +20ms is PERFECT")
	assert_eq(active_notes[0]["is_hit"], true, "Note marked hit")
	assert_eq(scoring.score, 100, "Score is 100")
	assert_eq(scoring.combo, 1, "Combo is 1")

func test_cluster_matcher_polyphonic_chord() -> void:
	print("\n--- Test Suite 4: Polyphonic Chord Matching (C Major Triad) ---")
	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var scoring = ScoringEngineScript.new()
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 5.0, "duration_sec": 1.0, "is_hit": false},
		{"pitch_midi": 64, "time_sec": 5.0, "duration_sec": 1.0, "is_hit": false},
		{"pitch_midi": 67, "time_sec": 5.0, "duration_sec": 1.0, "is_hit": false}
	]
	
	# Model detects all 3 pitches simultaneously at time 5.01s (+10ms)
	var chord_onsets = [60, 64, 67]
	var now = 5.01
	
	var hits_recorded: Array[Dictionary] = []
	for p in chord_onsets:
		var hit = scoring.process_input(now, p, active_notes, 0)
		if not hit.is_empty():
			hits_recorded.append(hit)
	
	assert_eq(hits_recorded.size(), 3, "All 3 notes in triad recognized and hit")
	assert_eq(active_notes[0]["is_hit"], true, "C4 hit")
	assert_eq(active_notes[1]["is_hit"], true, "E4 hit")
	assert_eq(active_notes[2]["is_hit"], true, "G4 hit")
	assert_eq(scoring.combo, 3, "Combo incremented to 3 for triad")
	assert_eq(scoring.score, 300, "Score awarded 300 points (3 x 100 Perfect)")
	assert_eq(scoring.count_perfect, 3, "3 Perfect counts recorded")

func test_cluster_matcher_partial_chord() -> void:
	print("\n--- Test Suite 5: Partial Chord Match & Note Expiration ---")
	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var scoring = ScoringEngineScript.new()
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false},
		{"pitch_midi": 64, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false},
		{"pitch_midi": 67, "time_sec": 2.0, "duration_sec": 0.5, "is_hit": false}
	]
	
	# Player only sings/plays C4 and E4, missing G4
	var detected = [60, 64]
	var now = 2.02
	for p in detected:
		scoring.process_input(now, p, active_notes, 0)
	
	assert_eq(active_notes[0]["is_hit"], true, "C4 hit")
	assert_eq(active_notes[1]["is_hit"], true, "E4 hit")
	assert_eq(active_notes[2]["is_hit"], false, "G4 was not played, remains unhit")
	assert_eq(scoring.combo, 2, "Combo is 2")
	
	# Song time moves past hit window (2.15s > 2.0 + 0.10s)
	var expired = scoring.check_expired_notes(2.15, active_notes)
	assert_eq(expired.size(), 1, "1 note expired (G4)")
	assert_eq(expired[0]["judgment"], "MISS", "G4 expired as MISS")
	assert_eq(active_notes[2]["is_missed"], true, "G4 marked missed")
	assert_eq(scoring.combo, 0, "Combo reset to 0 upon missed chord tone")

func test_cluster_matcher_sustain_retrigger_prevention() -> void:
	print("\n--- Test Suite 6: Sustain vs Onset Retriggering Prevention ---")
	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var scoring = ScoringEngineScript.new()
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 1.0, "is_hit": false},
		{"pitch_midi": 60, "time_sec": 2.0, "duration_sec": 1.0, "is_hit": false} # Second note of same pitch later
	]
	
	# Simulating game loop sustain tracking
	var last_detected_pitches: Array[int] = []
	
	# Frame 1: Note 1 begins with onset [60]
	var frame1_onsets = [60]
	var frame1_detected = [60]
	var candidate_pitches: Array[int] = []
	for p in frame1_onsets:
		candidate_pitches.append(p)
	for p in frame1_detected:
		if not last_detected_pitches.has(p) and not candidate_pitches.has(p):
			candidate_pitches.append(p)
	last_detected_pitches.clear()
	for p in frame1_detected:
		last_detected_pitches.append(int(p))
	
	for p in candidate_pitches:
		scoring.process_input(1.0, p, active_notes, 0)
	
	assert_eq(active_notes[0]["is_hit"], true, "Note 1 hit")
	assert_eq(scoring.combo, 1, "Combo is 1")
	
	# Frame 2..10: User is sustaining C4. Detected pitches is [60], but onsets is []
	var frame2_onsets: Array[int] = []
	var frame2_detected = [60]
	candidate_pitches.clear()
	for p in frame2_onsets:
		candidate_pitches.append(p)
	for p in frame2_detected:
		if not last_detected_pitches.has(p) and not candidate_pitches.has(p):
			candidate_pitches.append(p)
	last_detected_pitches.clear()
	for p in frame2_detected:
		last_detected_pitches.append(int(p))
	
	assert_eq(candidate_pitches.size(), 0, "No new strike pitches during sustain")
	for p in candidate_pitches:
		scoring.process_input(1.05, p, active_notes, 0)
	
	assert_eq(scoring.combo, 1, "Combo did not retrigger during sustain")
	assert_eq(active_notes[1]["is_hit"], false, "Note 2 at 2.0s untouched")
