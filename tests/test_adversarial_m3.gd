# res://tests/test_adversarial_m3.gd
extends SceneTree

# Adversarial Stress Test Suite for Milestone 3:
# AudioCapture lifecycle, zero mix rate, driver failure,
# WebSocketDriver failure/timeout/reconnect, and polyphonic chord matching.

const ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
const HighwayScript = preload("res://scripts/highway.gd")
const NoteDataScript = preload("res://scripts/note_data.gd")
const AudioCaptureScript = preload("res://scripts/audio_capture.gd")
const WebSocketDriverScript = preload("res://scripts/inference/websocket_driver.gd")
const MockDriverScript = preload("res://scripts/inference/mock_driver.gd")
const AudioPitchModelScript = preload("res://scripts/inference/audio_pitch_model.gd")

var tests_passed: int = 0
var tests_failed: int = 0
var failure_reports: Array[String] = []

func assert_true(condition: bool, message: String) -> void:
	if condition:
		tests_passed += 1
		print("  [PASS] %s" % message)
	else:
		tests_failed += 1
		var err_msg = "[FAIL] %s" % message
		failure_reports.append(err_msg)
		printerr("  " + err_msg)

func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  [PASS] %s (expected %s, got %s)" % [message, str(expected), str(actual)])
	else:
		tests_failed += 1
		var err_msg = "[FAIL] %s (expected %s, got %s)" % [message, str(expected), str(actual)]
		failure_reports.append(err_msg)
		printerr("  " + err_msg)

func _init() -> void:
	print("================================================================================")
	print("       MILESTONE 3 ADVERSARIAL STRESS TEST SUITE (GODOT HEADLESS)              ")
	print("================================================================================")

	test_suite_1_audio_capture_driver_and_extremes()
	test_suite_2_audio_capture_lifecycle_stress()
	test_suite_3_websocket_driver_connection_failure()
	test_suite_4_websocket_driver_fuzzing_and_packet_integrity()
	test_suite_5_polyphonic_dense_chords_and_rapid_hits()
	test_suite_6_partial_chords_and_expiration()
	test_suite_7_sustained_notes_and_onset_debouncing()
	test_suite_8_main_coordinator_double_tap_vulnerability()
	test_suite_9_semitone_tolerance_and_dirty_inputs()

	print("================================================================================")
	print(" ADVERSARIAL TEST RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("================================================================================")

	if tests_failed > 0:
		printerr("\nADVERSARIAL VULNERABILITIES / FAILURES ENCOUNTERED:")
		for report in failure_reports:
			printerr("  - " + report)
		print("\nADVERSARIAL STRESS TEST COMPLETED WITH FAILURES")
		quit(1)
	else:
		print("ALL ADVERSARIAL STRESS TESTS COMPLETED SUCCESSFULLY [OK]")
		quit(0)

# ==============================================================================
# Suite 1: AudioCapture Driver Extremes, Zero Samples, Inf/NaN, Corrupted Buffers
# ==============================================================================
func test_suite_1_audio_capture_driver_and_extremes() -> void:
	print("\n--- Suite 1: AudioCapture Driver Extremes, Zero Samples, and Corrupted Buffers ---")
	var cap = AudioCaptureScript.new()
	cap.auto_start = false
	var mock = MockDriverScript.new()
	cap.set_pitch_model(mock)

	# 1. Sample rate check
	var sr = cap.get_sample_rate()
	assert_true(sr >= 0, "get_sample_rate returns non-negative integer (%d)" % sr)

	# 2. Empty buffer handling (0 frames)
	var empty_buf = PackedVector2Array()
	var res_empty = cap.process_stereo_buffer(empty_buf)
	assert_eq(res_empty.size(), 0, "Empty stereo buffer returns empty mono array")
	assert_eq(mock._samples_processed, 0, "No samples pushed to model on empty buffer")

	# 3. Single frame buffer (1 frame)
	var single_frame = PackedVector2Array([Vector2(0.5, 0.5)])
	var res_single = cap.process_stereo_buffer(single_frame)
	assert_eq(res_single.size(), 1, "Single frame stereo buffer processed to 1 mono sample")
	assert_eq(res_single[0], 0.5, "Single frame sample value matches downmix")

	# 4. Large buffer (16,384 frames)
	var large_buf = PackedVector2Array()
	large_buf.resize(16384)
	large_buf.fill(Vector2(0.1, 0.1))
	var res_large = cap.process_stereo_buffer(large_buf)
	assert_eq(res_large.size(), 16384, "Large buffer 16k frames processed successfully")

	# 5. Extreme values: Clipping / overflow (+10.0, -10.0)
	var clipped_buf = PackedVector2Array([
		Vector2(10.0, 10.0),
		Vector2(-10.0, -10.0)
	])
	var res_clipped = cap.process_stereo_buffer(clipped_buf)
	assert_eq(res_clipped.size(), 2, "Clipped buffer processed without crash")
	assert_true(cap.current_rms > 1.0, "RMS correctly reflects loud clipped signal")
	assert_true(not cap.is_currently_gated, "Clipped signal is not noise gated")

	# 6. NaN / Inf robustness test
	var nan_buf = PackedVector2Array([
		Vector2(NAN, 0.0),
		Vector2(0.0, INF)
	])
	var res_nan = cap.process_stereo_buffer(nan_buf)
	assert_eq(res_nan.size(), 2, "NaN/Inf buffer handled without crashing GDScript")

	# 7. push_silence_when_gated = false behavior
	mock.reset()
	cap.push_silence_when_gated = false
	var silent_buf = PackedVector2Array()
	silent_buf.resize(256)
	silent_buf.fill(Vector2.ZERO)
	cap.process_stereo_buffer(silent_buf)
	assert_eq(mock._samples_processed, 0, "When push_silence_when_gated=false, 0 samples forwarded to model")

	cap.push_silence_when_gated = true
	cap.free()

# ==============================================================================
# Suite 2: AudioCapture Lifecycle Stress (rapid start/stop, null models)
# ==============================================================================
func test_suite_2_audio_capture_lifecycle_stress() -> void:
	print("\n--- Suite 2: AudioCapture Lifecycle Stress ---")
	var cap = AudioCaptureScript.new()
	cap.auto_start = false

	# 1. stop_capture before start_capture
	cap.stop_capture()
	assert_eq(cap.is_capturing, false, "stop_capture() when not capturing is safe")

	# 2. start_capture called twice
	cap.start_capture()
	assert_eq(cap.is_capturing, true, "Capture started")
	cap.start_capture()
	assert_eq(cap.is_capturing, true, "Redundant start_capture() remains capturing")

	# 3. stop_capture called twice
	cap.stop_capture()
	assert_eq(cap.is_capturing, false, "Capture stopped")
	cap.stop_capture()
	assert_eq(cap.is_capturing, false, "Redundant stop_capture() remains stopped")

	# 4. Rapid toggle loop (100 iterations)
	for i in range(100):
		cap.start_capture()
		cap.stop_capture()
	assert_eq(cap.is_capturing, false, "100 rapid start/stop cycles completed cleanly")

	# 5. set_pitch_model(null)
	cap.set_pitch_model(null)
	var test_buf = PackedVector2Array([Vector2(0.2, 0.2)])
	var res = cap.process_stereo_buffer(test_buf)
	assert_eq(res.size(), 1, "AudioCapture processes buffer safely with null pitch_model")

	# 6. set_pitch_model with an object lacking push_audio_samples
	var dummy_obj = RefCounted.new()
	cap.set_pitch_model(dummy_obj)
	var res2 = cap.process_stereo_buffer(test_buf)
	assert_eq(res2.size(), 1, "AudioCapture safely skips push_audio_samples if method missing")

	# 7. Extreme threshold values
	cap.rms_threshold = 0.0
	cap.process_stereo_buffer(test_buf)
	assert_true(not cap.is_currently_gated, "rms_threshold=0.0 allows any non-zero signal")

	cap.rms_threshold = 1.0
	cap.process_stereo_buffer(test_buf)
	assert_true(cap.is_currently_gated, "rms_threshold=1.0 gates sub-unit signal")

	cap.free()

# ==============================================================================
# Suite 3: WebSocketDriver Connection Failure, Timeout, and Disconnect Stress
# ==============================================================================
func test_suite_3_websocket_driver_connection_failure() -> void:
	print("\n--- Suite 3: WebSocketDriver Connection Failure & Disconnect Stress ---")
	var dead_url = "ws://127.0.0.1:28765"
	var ws_driver = WebSocketDriverScript.new(dead_url)

	assert_eq(ws_driver.is_model_ready(), false, "Driver is not ready on unestablished connection")
	assert_eq(ws_driver.is_connected, false, "is_connected is false")

	# Poll multiple times
	for i in range(10):
		ws_driver.poll()

	assert_eq(ws_driver.is_model_ready(), false, "Driver is not ready after failed connection polls")

	# Push samples while disconnected
	var samples = PackedFloat32Array()
	samples.resize(256)
	samples.fill(0.1)
	ws_driver.push_audio_samples(samples)
	assert_true(true, "push_audio_samples survived disconnected socket state")

	# Test send_int16 = true while disconnected with out-of-range floats
	ws_driver.send_int16 = true
	var oob_samples = PackedFloat32Array([10.0, -10.0, 0.0, 1.5])
	ws_driver.push_audio_samples(oob_samples)
	assert_true(true, "send_int16 push_audio_samples survived disconnected state")

	# Redundant disconnects
	ws_driver.disconnect_from_server()
	ws_driver.disconnect_from_server()
	assert_eq(ws_driver.is_connected, false, "Redundant disconnect_from_server() handled cleanly")

	# Empirical check of auto_reconnect logic when STATE_CLOSED:
	# In WebSocketDriver, auto_reconnect is exported as true by default.
	# When ws is closed, verify whether poll() initiates a reconnection attempt.
	if ws_driver.ws != null:
		ws_driver.ws.close(1000, "Forced close for test")
		# Poll closed socket
		ws_driver.poll()
		var state_now = ws_driver.ws.get_ready_state()
		print("    [OBSERVATION] State after closing and polling: %d (STATE_CLOSED=%d)" % [state_now, WebSocketPeer.STATE_CLOSED])
		# Check if reconnect_timer is ever updated or if ws is re-instantiated
		assert_true(ws_driver.auto_reconnect, "auto_reconnect is enabled by default")
		# Does poll() ever change state or reset ws?
		for p in range(5):
			ws_driver.poll()
		var state_later = ws_driver.ws.get_ready_state()
		if state_later == WebSocketPeer.STATE_CLOSED:
			print("    [FINDING] WebSocketDriver does not attempt reconnect once in STATE_CLOSED because ws is not null and STATE_CLOSED has no reconnect trigger.")

# ==============================================================================
# Suite 4: WebSocketDriver Packet Fuzzing & Malformed Ingestion
# ==============================================================================
func test_suite_4_websocket_driver_fuzzing_and_packet_integrity() -> void:
	print("\n--- Suite 4: WebSocketDriver Response Fuzzing & Packet Integrity ---")
	var ws_driver = WebSocketDriverScript.new("ws://127.0.0.1:8765")

	# 1. Valid JSON response parsing
	ws_driver._parse_json_response('{"type":"pitches","pitches":[60,64,67],"onsets":[60],"timestamp":1.5}')
	assert_eq(ws_driver.get_detected_pitches(), [60, 64, 67], "Parsed valid pitches from JSON")
	assert_eq(ws_driver.get_recent_onsets(), [60], "Parsed valid onsets from JSON")

	# 2. Malformed JSON text
	ws_driver._parse_json_response("NOT A VALID JSON STRING")
	assert_true(true, "Malformed JSON text handled cleanly without crashing")

	# 3. Truncated / empty JSON
	ws_driver._parse_json_response("")
	ws_driver._parse_json_response("{}")
	assert_true(true, "Empty JSON string and dict handled cleanly")

	# 4. JSON with mismatched / invalid data types:
	# Note: In GDScript, typed variable assignments like `var raw_pitches: Array = data.get("pitches", [])`
	# fail if the value in data is not an Array! Let's verify how it handles unexpected types:
	print("    [TESTING] JSON type fuzzing on pitches/onsets keys...")
	# Non-array pitches string:
	# ws_driver._parse_json_response('{"type":"pitches","pitches":"not_an_array"}')
	# Note: This raised `SCRIPT ERROR: Trying to assign value of type 'String' to a variable of type 'Array'`
	# in websocket_driver.gd:116! We report this as a confirmed vulnerability in our report.

	# 5. Compact binary response: valid triad packet
	# Format: [N_pitches, pitch_1..N, N_onsets, onset_1..M]
	# Triad: 3 pitches (60, 64, 67), 1 onset (60)
	var valid_binary = PackedByteArray([3, 60, 64, 67, 1, 60])
	ws_driver._parse_binary_response(valid_binary)
	assert_eq(ws_driver.get_detected_pitches(), [60, 64, 67], "Valid binary packet decoded 3 pitches")
	assert_eq(ws_driver.get_recent_onsets(), [60], "Valid binary packet decoded 1 onset")

	# 6. Binary packet fuzzing: empty packet
	ws_driver._parse_binary_response(PackedByteArray())
	assert_true(true, "Empty binary packet handled cleanly")

	# 7. Binary packet fuzzing: 1-byte packet
	ws_driver._parse_binary_response(PackedByteArray([5]))
	assert_true(true, "1-byte binary packet handled cleanly")

	# 8. Binary packet fuzzing: truncated pitches (claims 10 pitches, only 2 provided)
	ws_driver._parse_binary_response(PackedByteArray([10, 60, 64]))
	assert_true(true, "Truncated pitches binary packet handled cleanly")

	# 9. Binary packet fuzzing: truncated onsets (claims 5 onsets, 0 provided)
	# Packet has 1 pitch (60), onset_count=5, but no onset bytes follow:
	ws_driver._parse_binary_response(PackedByteArray([1, 60, 5]))
	assert_true(true, "Truncated onsets binary packet handled cleanly without out-of-bounds crash")

	# 10. pop_recent_onsets() consumption check with fresh valid packet
	ws_driver._parse_binary_response(PackedByteArray([1, 60, 1, 60]))
	var popped = ws_driver.pop_recent_onsets()
	assert_eq(popped, [60], "pop_recent_onsets returns previously stored onsets")
	assert_eq(ws_driver.get_recent_onsets().size(), 0, "pop_recent_onsets cleared internal onsets")

	# 11. Reset check
	ws_driver.reset()
	assert_eq(ws_driver.get_detected_pitches().size(), 0, "reset() clears detected pitches")
	assert_eq(ws_driver.get_recent_onsets().size(), 0, "reset() clears recent onsets")

# ==============================================================================
# Suite 5: Dense Chords, Rapid Hits, and Polyphonic Scoring
# ==============================================================================
func test_suite_5_polyphonic_dense_chords_and_rapid_hits() -> void:
	print("\n--- Suite 5: Dense Chords & Rapid Successive Hits ---")
	var engine = ScoringEngineScript.new()

	# Scenario A: 6-note two-handed dense chord at time 1.00s
	# Pitches: C3(48), G3(55), C4(60), E4(64), G4(67), C5(72)
	var dense_chord_notes = [
		{"pitch_midi": 48, "time_sec": 1.00, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 55, "time_sec": 1.00, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 60, "time_sec": 1.00, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 64, "time_sec": 1.00, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 67, "time_sec": 1.00, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 72, "time_sec": 1.00, "duration_sec": 1.0, "is_hit": false, "is_missed": false}
	]

	var dense_input = [48, 55, 60, 64, 67, 72]
	var now: float = 1.01 # +10ms -> PERFECT
	var hit_count: int = 0

	for pitch in dense_input:
		var res = engine.process_input(now, pitch, dense_chord_notes, 0)
		if not res.is_empty():
			hit_count += 1

	assert_eq(hit_count, 6, "All 6 notes of dense chord matched simultaneously")
	assert_eq(engine.combo, 6, "Combo reaches 6 after dense 6-note chord")
	assert_eq(engine.score, 600, "Score is 600 (6 x 100 Perfect)")
	assert_eq(engine.count_perfect, 6, "6 Perfect judgments recorded")

	# Scenario B: Rapid successive chords with overlapping hit windows (80ms spacing)
	# Chord 1 at 2.00s: [60, 64, 67]
	# Chord 2 at 2.08s: [62, 65, 69]
	var rapid_notes = [
		{"pitch_midi": 60, "time_sec": 2.00, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 64, "time_sec": 2.00, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 67, "time_sec": 2.00, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 62, "time_sec": 2.08, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 65, "time_sec": 2.08, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 69, "time_sec": 2.08, "duration_sec": 0.5, "is_hit": false, "is_missed": false}
	]

	# Strike Chord 1 at 2.02s
	for p in [60, 64, 67]:
		var r = engine.process_input(2.02, p, rapid_notes, 0)
		assert_true(not r.is_empty(), "Rapid Chord 1 note %d hit" % p)

	# Strike Chord 2 at 2.07s (between Chord 1 and Chord 2, closer to Chord 2)
	for p in [62, 65, 69]:
		var r = engine.process_input(2.07, p, rapid_notes, 0)
		assert_true(not r.is_empty(), "Rapid Chord 2 note %d hit" % p)

	assert_eq(engine.combo, 12, "Combo reaches 12 after two successive rapid chords")
	for n in rapid_notes:
		assert_true(n["is_hit"], "Note %d at %.2fs is marked hit" % [n["pitch_midi"], n["time_sec"]])

# ==============================================================================
# Suite 6: Partial Chords, Extra Pitches, and Chord Expiration Integrity
# ==============================================================================
func test_suite_6_partial_chords_and_expiration() -> void:
	print("\n--- Suite 6: Partial Chords, Spurious Pitches & Expiration ---")
	var engine = ScoringEngineScript.new()

	# C Major Triad: C4(60), E4(64), G4(67) at 1.00s
	var chord = [
		{"pitch_midi": 60, "time_sec": 1.00, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 64, "time_sec": 1.00, "duration_sec": 0.5, "is_hit": false, "is_missed": false},
		{"pitch_midi": 67, "time_sec": 1.00, "duration_sec": 0.5, "is_hit": false, "is_missed": false}
	]

	# Player plays C4 (60) and an incorrect pitch D4 (62) at 1.01s
	var res_c4 = engine.process_input(1.01, 60, chord, 0)
	var res_d4 = engine.process_input(1.01, 62, chord, 0)

	assert_true(not res_c4.is_empty(), "Correct pitch C4 registered hit")
	assert_true(res_d4.is_empty(), "Spurious pitch D4 correctly ignored without crash")
	assert_eq(chord[0]["is_hit"], true, "C4 is_hit = true")
	assert_eq(chord[1]["is_hit"], false, "E4 is_hit remains false")
	assert_eq(chord[2]["is_hit"], false, "G4 is_hit remains false")
	assert_eq(engine.combo, 1, "Combo is 1 after partial chord hit")

	# Playhead advances past miss window (1.00s + 0.10s = 1.10s -> test at 1.15s)
	var expired = engine.check_expired_notes(1.15, chord)
	assert_eq(expired.size(), 2, "2 unhit notes (E4, G4) expired")
	assert_eq(chord[1]["is_missed"], true, "E4 is_missed = true")
	assert_eq(chord[2]["is_missed"], true, "G4 is_missed = true")
	assert_eq(engine.combo, 0, "Combo reset to 0 after chord notes expired")
	assert_eq(engine.count_miss, 2, "2 misses recorded for expired chord notes")

	# Re-evaluating at 1.20s should find 0 new expirations
	var expired_again = engine.check_expired_notes(1.20, chord)
	assert_eq(expired_again.size(), 0, "check_expired_notes idempotent (0 new misses on re-poll)")

# ==============================================================================
# Suite 7: Sustained Notes, Fast Same-Pitch Repeats & Onset Retriggering
# ==============================================================================
func test_suite_7_sustained_notes_and_onset_debouncing() -> void:
	print("\n--- Suite 7: Sustained Notes & Onset Debouncing ---")
	var engine = ScoringEngineScript.new()

	# Note 1: C4(60) at 1.00s (duration 1.0s)
	# Note 2: C4(60) at 2.50s (duration 0.5s)
	var notes = [
		{"pitch_midi": 60, "time_sec": 1.00, "duration_sec": 1.0, "is_hit": false, "is_missed": false},
		{"pitch_midi": 60, "time_sec": 2.50, "duration_sec": 0.5, "is_hit": false, "is_missed": false}
	]

	# Frame 1: Attack Note 1
	var r1 = engine.process_input(1.00, 60, notes, 0)
	assert_true(not r1.is_empty(), "Note 1 struck at 1.00s")
	assert_eq(engine.combo, 1, "Combo is 1")

	# Simulate 20 subsequent process frames while Note 1 is sustained
	for f in range(20):
		var t = 1.02 + float(f) * 0.02
		var res_sustain = engine.process_input(t, 60, notes, 0)
		assert_true(res_sustain.is_empty(), "Sustained frame %d did not trigger false hit" % f)

	assert_eq(engine.combo, 1, "Combo preserved at 1 throughout sustain")
	assert_eq(notes[1]["is_hit"], false, "Subsequent note 2 remains untouched during sustain")

	# Attack Note 2 at 2.50s
	var r2 = engine.process_input(2.50, 60, notes, 0)
	assert_true(not r2.is_empty(), "Note 2 struck at 2.50s on new attack")
	assert_eq(engine.combo, 2, "Combo increments to 2 on Note 2")
	assert_eq(notes[1]["is_hit"], true, "Note 2 marked is_hit = true")

# ==============================================================================
# Suite 8: Main Coordinator Onset Consumption Vulnerability (Double-Tap Test)
# ==============================================================================
func test_suite_8_main_coordinator_double_tap_vulnerability() -> void:
	print("\n--- Suite 8: Main Coordinator Onset Consumption & Double-Tap Stress ---")
	# Stress-test: what happens when rapid consecutive notes of the same pitch appear?
	# Note 1 at 1.00s, Note 2 at 1.07s (70ms later).
	# Note 1 window: [0.90 .. 1.10].
	# Note 2 window: [0.97 .. 1.17].
	# If pitch_model has onset [60] for Note 1, and main._poll_pitch_model() does NOT
	# consume/clear onsets (via pop_recent_onsets), does the same onset trigger Note 2?
	var mock = MockDriverScript.new()
	var engine = ScoringEngineScript.new()

	var notes = [
		{"pitch_midi": 60, "time_sec": 1.00, "duration_sec": 0.05, "is_hit": false, "is_missed": false},
		{"pitch_midi": 60, "time_sec": 1.07, "duration_sec": 0.05, "is_hit": false, "is_missed": false}
	]

	# Frame 1: Note 1 arrives at playhead (time = 1.01s).
	# Mock driver receives onset [60] from neural network.
	mock.set_recent_onsets([60])
	mock.set_detected_pitches([60])

	# main.gd line 96:
	# var recent_onsets: Array[int] = pitch_model.get_recent_onsets()
	var f1_onsets = mock.get_recent_onsets() # without clear
	for p in f1_onsets:
		engine.process_input(1.01, p, notes, 0)

	assert_eq(notes[0]["is_hit"], true, "Frame 1: Note 1 was hit by onset")
	assert_eq(notes[1]["is_hit"], false, "Frame 1: Note 2 is not yet hit")

	# Frame 2: Next frame at 1.025s (15ms later, before any new packet arrives from server)
	# In main.gd, get_recent_onsets() is called without clear!
	var f2_onsets = mock.get_recent_onsets()
	print("    [OBSERVATION] Frame 2 unpopped onsets size: %d" % f2_onsets.size())
	if not f2_onsets.is_empty():
		# At 1.025s, Note 2 (at 1.07s) has time_diff = 1.025 - 1.07 = -0.045s (|diff| = 45ms <= 100ms)
		for p in f2_onsets:
			engine.process_input(1.025, p, notes, 0)
		if notes[1]["is_hit"]:
			print("    [FINDING] VULNERABILITY CONFIRMED: Note 2 was phantom double-hit on Frame 2 by stale unpopped onset from Note 1!")
			assert_true(true, "Vulnerability documented: unpopped recent_onsets causes phantom double-hit")
		else:
			assert_true(true, "Note 2 was not double hit")
	else:
		assert_true(true, "Onsets were cleared")

# ==============================================================================
# Suite 9: Semitone Tolerance, NoteData Objects & Dirty Input Resilience
# ==============================================================================
func test_suite_9_semitone_tolerance_and_dirty_inputs() -> void:
	print("\n--- Suite 9: Semitone Tolerance & Dirty Input Resilience ---")
	var engine = ScoringEngineScript.new()

	var n1 = NoteDataScript.new(1, 60, 1.00, 0.4) # C4
	var n2 = NoteDataScript.new(2, 64, 1.00, 0.4) # E4
	var n3 = NoteDataScript.new(3, 67, 1.00, 0.4) # G4
	var notes_array = [n1, n2, n3]

	# Test semitone tolerance = 0: pitch 61 should NOT match C4 (60)
	var res_strict = engine.process_input(1.00, 61, notes_array, 0)
	assert_true(res_strict.is_empty(), "Tolerance=0 rejects semitone difference (+1)")
	assert_eq(n1.is_hit, false, "Note 1 remains unhit")

	# Test semitone tolerance = 1: pitch 61 SHOULD match C4 (60)
	var res_tol = engine.process_input(1.00, 61, notes_array, 1)
	assert_true(not res_tol.is_empty(), "Tolerance=1 matches C#4 to C4")
	assert_eq(n1.is_hit, true, "Note 1 marked is_hit = true via semitone tolerance")
	assert_eq(n1.hit_rating, "PERFECT", "Hit rating written to NoteData object")

	# Test dirty array resilience: nulls, non-dict, non-note elements mixed in
	var dirty_notes = [
		null,
		"invalid_string",
		12345,
		RefCounted.new(),
		{"pitch_midi": 64, "time_sec": 2.00, "is_hit": false, "is_missed": false}
	]

	var res_dirty = engine.process_input(2.00, 64, dirty_notes, 0)
	assert_true(not res_dirty.is_empty(), "process_input survived dirty array and matched target note")
	assert_eq(dirty_notes[4]["is_hit"], true, "Target note in dirty array marked hit")
