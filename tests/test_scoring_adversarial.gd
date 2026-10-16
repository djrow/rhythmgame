# res://tests/test_scoring_adversarial.gd
extends SceneTree

const ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
const NoteDataScript = preload("res://scripts/note_data.gd")

var tests_passed: int = 0
var tests_failed: int = 0
var failure_reports: Array[String] = []

func _init() -> void:
	print("================================================================================")
	print("          ADVERSARIAL STRESS TEST SUITE: SCORING ENGINE & TIMING")
	print("================================================================================")

	test_submillisecond_boundaries()
	test_floating_point_subtraction_fuzzing()
	test_negative_and_extreme_timestamps()
	test_chords_and_duplicate_pitches()
	test_semitone_tolerance_pitfalls()
	test_massive_combo_progression_1500()
	test_expired_notes_and_lifecycle_integrity()
	test_missed_flag_vulnerability_in_process_input()
	test_malformed_and_dirty_inputs()
	test_rapid_input_fuzzing_and_throughput()
	test_reset_and_state_reinitialization()

	print("================================================================================")
	print(" ADVERSARIAL RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("================================================================================")

	if tests_failed > 0:
		printerr("\nFAILURES ENCOUNTERED:")
		for report in failure_reports:
			printerr("  - " + report)
		print("\nADVERSARIAL STRESS TEST COMPLETED WITH FAILURES")
		quit(1)
	else:
		print("ALL ADVERSARIAL STRESS TESTS COMPLETED SUCCESSFULLY [OK]")
		quit(0)

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

# ==============================================================================
# 1. Sub-millisecond Boundaries
# ==============================================================================
func test_submillisecond_boundaries() -> void:
	print("\n--- Test Suite 1: Sub-Millisecond Precision Boundaries ---")
	var engine = ScoringEngineScript.new()

	# Positive window boundaries
	assert_eq(engine.evaluate_timing(0.04990), "PERFECT", "+49.90ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(0.04999), "PERFECT", "+49.99ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(0.05000), "PERFECT", "+50.00ms exact boundary should be PERFECT")
	assert_eq(engine.evaluate_timing(0.05001), "GOOD", "+50.01ms diff should be GOOD")
	assert_eq(engine.evaluate_timing(0.05010), "GOOD", "+50.10ms diff should be GOOD")

	assert_eq(engine.evaluate_timing(0.09990), "GOOD", "+99.90ms diff should be GOOD")
	assert_eq(engine.evaluate_timing(0.09999), "GOOD", "+99.99ms diff should be GOOD")
	assert_eq(engine.evaluate_timing(0.10000), "GOOD", "+100.00ms exact boundary should be GOOD")
	assert_eq(engine.evaluate_timing(0.10001), "MISS", "+100.01ms diff should be MISS")
	assert_eq(engine.evaluate_timing(0.10010), "MISS", "+100.10ms diff should be MISS")

	# Negative window boundaries (early hits)
	assert_eq(engine.evaluate_timing(-0.04990), "PERFECT", "-49.90ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(-0.04999), "PERFECT", "-49.99ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(-0.05000), "PERFECT", "-50.00ms exact boundary should be PERFECT")
	assert_eq(engine.evaluate_timing(-0.05001), "GOOD", "-50.01ms diff should be GOOD")
	assert_eq(engine.evaluate_timing(-0.05010), "GOOD", "-50.10ms diff should be GOOD")

	assert_eq(engine.evaluate_timing(-0.09990), "GOOD", "-99.90ms diff should be GOOD")
	assert_eq(engine.evaluate_timing(-0.09999), "GOOD", "-99.99ms diff should be GOOD")
	assert_eq(engine.evaluate_timing(-0.10000), "GOOD", "-100.00ms exact boundary should be GOOD")
	assert_eq(engine.evaluate_timing(-0.10001), "MISS", "-100.01ms diff should be MISS")
	assert_eq(engine.evaluate_timing(-0.10010), "MISS", "-100.10ms diff should be MISS")

# ==============================================================================
# 2. Floating-Point Subtraction Fuzzing
# ==============================================================================
func test_floating_point_subtraction_fuzzing() -> void:
	print("\n--- Test Suite 2: Floating-Point Subtraction Precision Across Time ---")
	var engine = ScoringEngineScript.new()

	# In IEEE 754, (t + 0.05) - t can have tiny epsilon inaccuracies (e.g. 0.050000000000000044)
	# Test if process_input handles exact +50ms and exact +100ms across multiple playhead offsets
	var base_times: Array[float] = [0.0, 1.0, 5.0, 10.0, 30.0, 60.0, 120.0, 300.0, 600.0]

	for t in base_times:
		var notes = [{ "pitch_midi": 60, "time_sec": t, "is_hit": false }]
		
		# Test exact nominal +50ms: input_time = t + 0.050
		var hit_50 = engine.process_input(t + 0.050, 60, notes)
		var rating_50 = hit_50.get("judgment", "")
		# Note: Due to float representation, t + 0.050 - t might be 0.050000000000000044
		# We check whether the engine rated it PERFECT or GOOD and document behavior
		assert_true(rating_50 == "PERFECT" or rating_50 == "GOOD",
			"Nominal +50ms hit at t=%.1f should be PERFECT or GOOD, got %s" % [t, rating_50])

		# Reset note for +100ms test
		notes = [{ "pitch_midi": 60, "time_sec": t, "is_hit": false }]
		var hit_100 = engine.process_input(t + 0.100, 60, notes)
		var rating_100 = hit_100.get("judgment", "")
		# If (t + 0.100) - t > 0.100 due to float representation, process_input drops the hit completely
		if hit_100.is_empty():
			printerr("  [FLOAT REJECTION BUG] Nominal +100ms hit dropped as OUT_OF_WINDOW at t=%.1f due to float subtraction!" % t)
			assert_true(false, "FLOAT REJECTION: Nominal +100ms hit dropped at t=%.1f" % t)
		else:
			assert_true(rating_100 == "GOOD", "Nominal +100ms hit at t=%.1f should be GOOD, got %s" % [t, rating_100])

# ==============================================================================
# 3. Negative and Extreme Timestamps
# ==============================================================================
func test_negative_and_extreme_timestamps() -> void:
	print("\n--- Test Suite 3: Negative and Extreme Timestamps ---")
	var engine = ScoringEngineScript.new()

	# Note at negative timestamp (e.g. song intro offset)
	var neg_notes = [
		{ "pitch_midi": 60, "time_sec": -0.500, "is_hit": false },
		{ "pitch_midi": 62, "time_sec": -0.200, "is_hit": false }
	]

	# Hit note at -0.480s (diff = -0.480 - (-0.500) = +0.020s -> PERFECT)
	var hit_neg = engine.process_input(-0.480, 60, neg_notes)
	assert_eq(hit_neg.get("judgment", ""), "PERFECT", "Hit at -0.480s against note at -0.500s should be PERFECT")
	assert_eq(neg_notes[0]["is_hit"], true, "Negative timestamp note 0 marked is_hit")

	# Hit note at -0.280s (diff = -0.280 - (-0.200) = -0.080s -> GOOD)
	var hit_neg2 = engine.process_input(-0.280, 62, neg_notes)
	assert_eq(hit_neg2.get("judgment", ""), "GOOD", "Early hit at -0.280s against note at -0.200s should be GOOD")

	# Extreme large timestamp (e.g. 10 hours = 36000 seconds)
	var far_notes = [{ "pitch_midi": 72, "time_sec": 36000.0, "is_hit": false }]
	var hit_far = engine.process_input(36000.015, 72, far_notes)
	assert_eq(hit_far.get("judgment", ""), "PERFECT", "Extreme timestamp 36000.015s should evaluate PERFECT")

	# NaN and INF robustness
	var inf_rating = engine.evaluate_timing(INF)
	assert_eq(inf_rating, "MISS", "INF timing diff evaluates to MISS without crash")
	var neg_inf_rating = engine.evaluate_timing(-INF)
	assert_eq(neg_inf_rating, "MISS", "-INF timing diff evaluates to MISS without crash")
	var nan_rating = engine.evaluate_timing(NAN)
	assert_eq(nan_rating, "MISS", "NAN timing diff evaluates to MISS without crash")

# ==============================================================================
# 4. Simultaneous Chords & Duplicate Pitches
# ==============================================================================
func test_chords_and_duplicate_pitches() -> void:
	print("\n--- Test Suite 4: Simultaneous Chords with Duplicate Pitches ---")
	var engine = ScoringEngineScript.new()

	# Scenario A: Unison chord with 2 notes of identical pitch at identical timestamp
	var unison_chord = [
		{ "pitch_midi": 60, "time_sec": 2.0, "is_hit": false, "id": 1 },
		{ "pitch_midi": 60, "time_sec": 2.0, "is_hit": false, "id": 2 }
	]

	# First hit with pitch 60 at time 2.0
	var hit1 = engine.process_input(2.0, 60, unison_chord)
	assert_eq(hit1.get("judgment", ""), "PERFECT", "First unison note hit should be PERFECT")
	assert_eq(engine.combo, 1, "Combo should be 1 after first unison note")
	assert_true(unison_chord[0]["is_hit"], "First unison note marked is_hit")
	assert_true(not unison_chord[1]["is_hit"], "Second unison note remains unhit")

	# Second hit with pitch 60 at time 2.0
	var hit2 = engine.process_input(2.0, 60, unison_chord)
	assert_eq(hit2.get("judgment", ""), "PERFECT", "Second unison note hit should be PERFECT")
	assert_eq(engine.combo, 2, "Combo should be 2 after second unison note")
	assert_true(unison_chord[1]["is_hit"], "Second unison note now marked is_hit")

	# Third hit with pitch 60 at time 2.0 (no remaining notes)
	var hit3 = engine.process_input(2.0, 60, unison_chord)
	assert_true(hit3.is_empty(), "Third hit on 2-note unison returns empty dictionary")
	assert_eq(engine.combo, 2, "Combo remains 2, not reset by surplus input")

	# Scenario B: Polyphonic C-major chord (C4=60, E4=64, G4=67) hit in reverse pitch order
	engine.reset()
	var triad = [
		{ "pitch_midi": 60, "time_sec": 5.0, "is_hit": false },
		{ "pitch_midi": 64, "time_sec": 5.0, "is_hit": false },
		{ "pitch_midi": 67, "time_sec": 5.0, "is_hit": false }
	]

	var hit_g = engine.process_input(5.01, 67, triad)
	assert_eq(hit_g.get("judgment", ""), "PERFECT", "Reverse chord hit: G4 judged PERFECT")
	var hit_e = engine.process_input(5.02, 64, triad)
	assert_eq(hit_e.get("judgment", ""), "PERFECT", "Reverse chord hit: E4 judged PERFECT")
	var hit_c = engine.process_input(4.98, 60, triad)
	assert_eq(hit_c.get("judgment", ""), "PERFECT", "Reverse chord hit: C4 judged PERFECT")
	assert_eq(engine.combo, 3, "Triad hit in arbitrary order results in combo 3")
	assert_eq(engine.score, 300, "Triad score should be 300 (100 * 3)")

# ==============================================================================
# 5. Semitone Tolerance Pitfalls
# ==============================================================================
func test_semitone_tolerance_pitfalls() -> void:
	print("\n--- Test Suite 5: Semitone Tolerance Behavior ---")
	var engine = ScoringEngineScript.new()

	# Note is C4 (MIDI 60). Tolerance = 1 semitone.
	var notes = [{ "pitch_midi": 60, "time_sec": 1.0, "is_hit": false }]

	# Pitch 59 (B3) -> within 1 semitone
	var hit_low = engine.process_input(1.0, 59, notes, 1)
	assert_eq(hit_low.get("judgment", ""), "PERFECT", "Pitch 59 matches Note 60 under tolerance 1")
	assert_true(notes[0]["is_hit"], "Note marked hit")

	# Reset note
	notes = [{ "pitch_midi": 60, "time_sec": 1.0, "is_hit": false }]
	# Pitch 62 (D4) -> 2 semitones off -> should fail with tolerance 1
	var hit_too_high = engine.process_input(1.0, 62, notes, 1)
	assert_true(hit_too_high.is_empty(), "Pitch 62 rejected under tolerance 1")
	assert_true(not notes[0]["is_hit"], "Note remains unhit")

	# Test competing notes: Note A (MIDI 61, time 1.000) vs Note B (MIDI 60, time 1.005)
	# User plays MIDI 60 at time 1.000 with tolerance 1
	var competing_notes = [
		{ "pitch_midi": 61, "time_sec": 1.000, "is_hit": false, "name": "A" },
		{ "pitch_midi": 60, "time_sec": 1.005, "is_hit": false, "name": "B" }
	]
	var matched = engine.process_input(1.000, 60, competing_notes, 1)
	# Process input picks the note with minimum abs(time_diff)
	# Note A has diff = 0.000, Note B has diff = -0.005
	# Under tolerance 1, Note A (off-pitch) was picked because its timing diff was smaller!
	print("  [INFO] Competing notes matching picked: Note with pitch %d (timediff: %s)" % [
		matched.get("note_data", {}).get("pitch_midi", -1),
		str(matched.get("time_diff", 0.0))
	])
	assert_true(not matched.is_empty(), "Tolerance match matched a note")

# ==============================================================================
# 6. Massive Combo Progression up to 1,500
# ==============================================================================
func test_massive_combo_progression_1500() -> void:
	print("\n--- Test Suite 6: Massive Combo Progression (1500+ Notes) ---")
	var engine = ScoringEngineScript.new()

	# Progressively register 1500 PERFECT hits
	for i in range(1500):
		var res = engine.register_hit("PERFECT")
		var expected_mult: int = 1
		if (i + 1) >= 30:
			expected_mult = 4
		elif (i + 1) >= 20:
			expected_mult = 3
		elif (i + 1) >= 10:
			expected_mult = 2
		else:
			expected_mult = 1

		if res["multiplier"] != expected_mult:
			assert_eq(res["multiplier"], expected_mult, "Multiplier mismatch at hit %d" % (i + 1))
			break

	assert_eq(engine.combo, 1500, "Combo should reach exactly 1500")
	assert_eq(engine.max_combo, 1500, "Max combo should be 1500")
	assert_eq(engine.count_perfect, 1500, "Count perfect should be 1500")
	assert_eq(engine.total_notes, 1500, "Total notes should be 1500")

	# Mathematical score check:
	# 1..9:   9 * 100 * 1 = 900
	# 10..19: 10 * 100 * 2 = 2000
	# 20..29: 10 * 100 * 3 = 3000
	# 30..1500: (1500 - 30 + 1) = 1471 notes * 100 * 4 = 588,400
	# Total = 900 + 2000 + 3000 + 588400 = 594,300
	assert_eq(engine.score, 594300, "Score after 1500 Perfects should be exactly 594,300")
	assert_eq(engine.get_accuracy(), 100.0, "Accuracy after 1500 Perfects should be 100.0%")

	# Break streak with a Miss
	var miss_res = engine.register_miss()
	assert_eq(miss_res["judgment"], "MISS", "Registered judgment is MISS")
	assert_eq(engine.combo, 0, "Combo immediately drops to 0")
	assert_eq(engine.max_combo, 1500, "Max combo preserved at 1500")
	assert_eq(engine.get_multiplier(), 1, "Multiplier drops to 1x")
	assert_eq(engine.total_notes, 1501, "Total notes incremented to 1501")

	# Accuracy check: 1500.0 / 1501.0 * 100.0 = 99.933377748...%
	var expected_acc: float = (1500.0 / 1501.0) * 100.0
	var diff_acc = absf(engine.get_accuracy() - expected_acc)
	assert_true(diff_acc < 0.0001, "Accuracy correctly drops to 99.933% after 1 miss")

	# Re-ramp multiplier with 50 GOOD hits
	# Hits 1..9: 9 * 50 * 1 = 450
	# Hits 10..19: 10 * 50 * 2 = 1000
	# Hits 20..29: 10 * 50 * 3 = 1500
	# Hits 30..50: 21 * 50 * 4 = 4200
	# Total added = 450 + 1000 + 1500 + 4200 = 7150
	var score_before_goods = engine.score
	for i in range(50):
		engine.register_hit("GOOD")
	assert_eq(engine.combo, 50, "Combo re-ramped to 50")
	assert_eq(engine.get_multiplier(), 4, "Multiplier returned to 4x")
	assert_eq(engine.score, score_before_goods + 7150, "Score correctly updated by 7150 points for 50 Goods")

# ==============================================================================
# 7. Expired Notes & Lifecycle Integrity
# ==============================================================================
func test_expired_notes_and_lifecycle_integrity() -> void:
	print("\n--- Test Suite 7: Expired Notes & Batch Expiration ---")
	var engine = ScoringEngineScript.new()

	# Staggered notes
	var notes = [
		{ "pitch_midi": 60, "time_sec": 1.00, "is_hit": false },
		{ "pitch_midi": 62, "time_sec": 1.02, "is_hit": false },
		{ "pitch_midi": 64, "time_sec": 1.04, "is_hit": false },
		{ "pitch_midi": 65, "time_sec": 1.50, "is_hit": false }
	]

	# Build initial combo of 10
	for i in range(10):
		engine.register_hit("PERFECT")
	assert_eq(engine.combo, 10, "Initial combo is 10")

	# At time 1.09s (None have exceeded note_time + 0.100s)
	# Note 60 expires at > 1.10s
	var exp0 = engine.check_expired_notes(1.09, notes)
	assert_eq(exp0.size(), 0, "No notes expired at 1.09s")
	assert_eq(engine.combo, 10, "Combo still 10")

	# At time 1.15s (Notes 60, 62, 64 expired: 1.00+0.1=1.10, 1.02+0.1=1.12, 1.04+0.1=1.14)
	var exp1 = engine.check_expired_notes(1.15, notes)
	assert_eq(exp1.size(), 3, "Three notes expired together at 1.15s")
	assert_eq(engine.combo, 0, "Combo reset to 0 by batch expiration")
	assert_eq(engine.count_miss, 3, "Miss count increased by 3")

	# Note 65 at 1.50s remains active
	assert_true(not notes[3].get("is_hit", false), "Note 65 remains unhit")
	assert_true(not notes[3].get("is_missed", false), "Note 65 remains unmissed")

	# Contract check: Expired notes must have is_missed == true and is_hit == false
	if notes[0].get("is_hit", false) == true:
		printerr("  [CONTRACT CORRUPTION] Expired note had is_hit set to true!")
		assert_true(false, "CONTRACT CORRUPTION: Expired note marked is_hit=true")
	else:
		assert_true(true, "Expired note correctly keeps is_hit=false")

	# Calling check_expired_notes again at 1.16s should return 0 new expirations
	var exp2 = engine.check_expired_notes(1.16, notes)
	assert_eq(exp2.size(), 0, "Idempotent: no re-expiration at 1.16s")

# ==============================================================================
# 8. Missed Flag Vulnerability in process_input
# ==============================================================================
func test_missed_flag_vulnerability_in_process_input() -> void:
	print("\n--- Test Suite 8: Missed Flag Vulnerability Stress Test ---")
	var engine = ScoringEngineScript.new()

	# Highway marks notes with is_missed = true when they pass miss_window_sec:
	# In highway.gd line 137:
	# note.is_missed = true; note.hit_rating = "MISS"
	# BUT note.is_hit is FALSE!
	
	# Test with Dictionary:
	var dict_missed_note = {
		"pitch_midi": 60,
		"time_sec": 1.00,
		"is_hit": false,
		"is_missed": true
	}
	var dict_notes = [dict_missed_note]

	# Attempt to hit the missed note within window (+80ms)
	var hit_result_dict = engine.process_input(1.08, 60, dict_notes)
	
	# If process_input only checks is_hit, it will hit this already-missed note!
	if not hit_result_dict.is_empty():
		printerr("  [VULNERABILITY DETECTED] process_input matched a note that already had is_missed=true (Dictionary)!")
		assert_true(false, "VULNERABILITY: process_input matched an already-missed Dictionary note")
	else:
		assert_true(true, "process_input correctly rejected already-missed Dictionary note")

	# Test with NoteData object:
	var note_obj = NoteDataScript.new(1, 60, 1.00, 0.4)
	note_obj.is_missed = true
	note_obj.is_hit = false
	var obj_notes = [note_obj]

	var hit_result_obj = engine.process_input(1.08, 60, obj_notes)
	if not hit_result_obj.is_empty():
		printerr("  [VULNERABILITY DETECTED] process_input matched a NoteData that already had is_missed=true!")
		assert_true(false, "VULNERABILITY: process_input matched an already-missed NoteData object")
	else:
		assert_true(true, "process_input correctly rejected already-missed NoteData object")

# ==============================================================================
# 9. Malformed and Dirty Inputs
# ==============================================================================
func test_malformed_and_dirty_inputs() -> void:
	print("\n--- Test Suite 9: Malformed and Dirty Inputs ---")
	var engine = ScoringEngineScript.new()

	# Notes array containing mixed garbage data
	var dirty_notes: Array = [
		null,
		12345,
		"corrupted_string",
		{}, # empty dictionary
		{ "unrelated_key": 999 },
		{ "pitch_midi": 60, "is_hit": true }, # missing time_sec
		{ "time_sec": 1.0, "is_hit": false }, # missing pitch_midi (defaults to 0)
		{ "pitch_midi": 60, "time_sec": 2.0, "is_hit": false } # legitimate note
	]

	# Should survive dirty array without crashing and hit the legitimate note
	var res = engine.process_input(2.02, 60, dirty_notes)
	assert_eq(res.get("judgment", ""), "PERFECT", "Survived dirty notes array and matched valid note")

	# Check expired notes with dirty array
	var exp_res = engine.check_expired_notes(3.0, dirty_notes)
	assert_true(exp_res.size() >= 1, "check_expired_notes survived dirty array")

	# Calling register_hit with unknown judgment
	var initial_total = engine.total_notes
	var bad_judgment_res = engine.register_hit("UNKNOWN_JUDGMENT")
	assert_true(bad_judgment_res.is_empty(), "Unknown judgment returns empty dictionary")
	
	# Check whether total_notes was incremented despite unknown judgment
	if engine.total_notes != initial_total:
		printerr("  [FLAW DETECTED] total_notes was incremented from %d to %d on invalid judgment!" % [initial_total, engine.total_notes])
		assert_eq(engine.total_notes, initial_total, "total_notes should NOT increment on unknown judgment")
	else:
		assert_eq(engine.total_notes, initial_total, "total_notes untouched on unknown judgment")

# ==============================================================================
# 10. Rapid Input Fuzzing and Throughput Benchmark
# ==============================================================================
func test_rapid_input_fuzzing_and_throughput() -> void:
	print("\n--- Test Suite 10: Rapid Input Fuzzing & Throughput Benchmark ---")
	var engine = ScoringEngineScript.new()

	var active_notes = [
		{ "pitch_midi": 60, "time_sec": 10.0, "is_hit": false }
	]

	# 10,000 rapid inputs when no note is in range
	var start_usec: int = Time.get_ticks_usec()
	for i in range(10000):
		var hit = engine.process_input(0.5, 60, active_notes)
		# Should return empty every time without side effects
	var elapsed_msec: float = float(Time.get_ticks_usec() - start_usec) / 1000.0

	assert_eq(engine.score, 0, "Spam inputs did not alter score")
	assert_eq(engine.combo, 0, "Spam inputs did not alter combo")
	assert_eq(engine.total_notes, 0, "Spam inputs did not alter total_notes")
	print("  [BENCHMARK] 10,000 process_input calls took %.2f ms (%.1f calls/sec)" % [
		elapsed_msec,
		(10000.0 / (elapsed_msec / 1000.0))
	])
	assert_true(elapsed_msec < 2000.0, "10,000 queries completed in < 2000ms")

# ==============================================================================
# 11. Reset and State Reinitialization
# ==============================================================================
func test_reset_and_state_reinitialization() -> void:
	print("\n--- Test Suite 11: Reset and State Reinitialization ---")
	var engine = ScoringEngineScript.new()

	# Build complex state
	for i in range(35):
		engine.register_hit("PERFECT")
	for i in range(10):
		engine.register_hit("GOOD")
	engine.register_miss()

	assert_true(engine.score > 0, "Score > 0 before reset")
	assert_true(engine.max_combo > 0, "Max combo > 0 before reset")
	assert_true(engine.total_notes > 0, "Total notes > 0 before reset")

	# Reset
	engine.reset()

	assert_eq(engine.score, 0, "Score reset to 0")
	assert_eq(engine.combo, 0, "Combo reset to 0")
	assert_eq(engine.max_combo, 0, "Max combo reset to 0")
	assert_eq(engine.count_perfect, 0, "count_perfect reset to 0")
	assert_eq(engine.count_good, 0, "count_good reset to 0")
	assert_eq(engine.count_miss, 0, "count_miss reset to 0")
	assert_eq(engine.total_notes, 0, "total_notes reset to 0")
	assert_eq(engine.get_multiplier(), 1, "Multiplier reset to 1x")
	assert_eq(engine.get_accuracy(), 100.0, "Accuracy on 0 notes defaults to 100.0%")
