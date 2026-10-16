# res://tests/test_scoring_runner.gd / local probe
extends SceneTree

const ScoringEngineScript = preload("scoring_engine.gd")

var tests_passed: int = 0
var tests_failed: int = 0

func _init() -> void:
	print("==================================================")
	print(" RUNNING SCORING ENGINE HEADLESS VERIFICATION")
	print("==================================================")

	test_timing_windows()
	test_scoring_formulas_and_multipliers()
	test_combo_streak_reset()
	test_pitch_matching_and_polyphony()
	test_expired_notes()
	test_accuracy_calculation()

	print("==================================================")
	print(" RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("==================================================")

	if tests_failed == 0:
		print("ALL SCORING MECHANICS VERIFIED SUCCESSFULLY [OK]")
		quit(0)
	else:
		push_error("SCORING MECHANICS VERIFICATION FAILED with %d errors" % tests_failed)
		quit(1)

func assert_true(condition: bool, message: String) -> void:
	if condition:
		tests_passed += 1
		print("  [PASS] %s" % message)
	else:
		tests_failed += 1
		printerr("  [FAIL] %s" % message)

func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  [PASS] %s (expected %s, got %s)" % [message, str(expected), str(actual)])
	else:
		tests_failed += 1
		printerr("  [FAIL] %s (expected %s, got %s)" % [message, str(expected), str(actual)])

func test_timing_windows() -> void:
	print("\n--- Test Suite 1: Timing Windows (Perfect <= 50ms, Good <= 100ms, Miss > 100ms) ---")
	var engine = ScoringEngineScript.new()

	assert_eq(engine.evaluate_timing(0.0), "PERFECT", "0ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(0.025), "PERFECT", "+25ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(-0.045), "PERFECT", "-45ms diff should be PERFECT")
	assert_eq(engine.evaluate_timing(0.050), "PERFECT", "Exact +50ms boundary should be PERFECT")
	assert_eq(engine.evaluate_timing(-0.050), "PERFECT", "Exact -50ms boundary should be PERFECT")

	assert_eq(engine.evaluate_timing(0.051), "GOOD", "+51ms should be GOOD")
	assert_eq(engine.evaluate_timing(-0.075), "GOOD", "-75ms should be GOOD")
	assert_eq(engine.evaluate_timing(0.100), "GOOD", "Exact +100ms boundary should be GOOD")
	assert_eq(engine.evaluate_timing(-0.100), "GOOD", "Exact -100ms boundary should be GOOD")

	assert_eq(engine.evaluate_timing(0.101), "MISS", "+101ms should be MISS")
	assert_eq(engine.evaluate_timing(-0.150), "MISS", "-150ms should be MISS")
	assert_eq(engine.evaluate_timing(0.500), "MISS", "+500ms should be MISS")

func test_scoring_formulas_and_multipliers() -> void:
	print("\n--- Test Suite 2: Scoring Formulas & Multiplier Progression ---")
	var engine = ScoringEngineScript.new()

	# Hits 1 through 9 (Multiplier 1x)
	# 9 Perfect hits: 9 * (100 * 1) = 900 points
	for i in range(9):
		var res = engine.register_hit("PERFECT")
		assert_eq(res["multiplier"], 1, "Hit %d multiplier should be 1x" % (i + 1))
	assert_eq(engine.score, 900, "Score after 9 Perfects at 1x should be 900")
	assert_eq(engine.combo, 9, "Combo should be 9")

	# 10th Hit (Multiplier transitions to 2x: 10 combo = 2x)
	var res10 = engine.register_hit("PERFECT")
	assert_eq(res10["multiplier"], 2, "10th hit triggers 2x multiplier")
	assert_eq(res10["points_awarded"], 200, "10th hit awards 100 * 2 = 200 pts")
	assert_eq(engine.score, 1100, "Total score after 10th hit should be 900 + 200 = 1100")
	assert_eq(engine.combo, 10, "Combo should be 10")

	# Hits 11 through 19 (Combo 11..19, multiplier 2x)
	# 9 more hits: 9 * (100 * 2) = 1800 pts -> 1100 + 1800 = 2900
	for i in range(11, 20):
		var res = engine.register_hit("PERFECT")
		assert_eq(res["multiplier"], 2, "Combo %d multiplier should be 2x" % i)
	assert_eq(engine.combo, 19, "Combo should be 19")
	assert_eq(engine.score, 2900, "Score after 19 hits should be 2900")

	# 20th Hit (Multiplier transitions to 3x: 20 combo = 3x)
	var res20 = engine.register_hit("PERFECT")
	assert_eq(res20["multiplier"], 3, "20th hit triggers 3x multiplier")
	assert_eq(res20["points_awarded"], 300, "20th hit awards 100 * 3 = 300 pts")
	assert_eq(engine.score, 3200, "Total score after 20th hit should be 2900 + 300 = 3200")
	assert_eq(engine.combo, 20, "Combo should be 20")

	# Hits 21 through 29 (Combo 21..29, multiplier 3x)
	# 9 more hits: 9 * (100 * 3) = 2700 pts -> 3200 + 2700 = 5900
	for i in range(21, 30):
		var res = engine.register_hit("PERFECT")
		assert_eq(res["multiplier"], 3, "Combo %d multiplier should be 3x" % i)
	assert_eq(engine.combo, 29, "Combo should be 29")
	assert_eq(engine.score, 5900, "Score after 29 hits should be 5900")

	# 30th Hit (Multiplier transitions to 4x: 30+ combo = 4x)
	var res30 = engine.register_hit("PERFECT")
	assert_eq(res30["multiplier"], 4, "30th hit triggers 4x multiplier")
	assert_eq(res30["points_awarded"], 400, "30th hit awards 100 * 4 = 400 pts")
	assert_eq(engine.score, 6300, "Total score after 30th hit should be 5900 + 400 = 6300")
	assert_eq(engine.combo, 30, "Combo should be 30")

	# 31st Hit with GOOD (Good awards 50 * multiplier = 50 * 4 = 200 pts)
	var res31 = engine.register_hit("GOOD")
	assert_eq(res31["multiplier"], 4, "31st hit multiplier should remain capped at 4x")
	assert_eq(res31["points_awarded"], 200, "Good at 4x awards 50 * 4 = 200 pts")
	assert_eq(engine.score, 6500, "Total score after 31st hit should be 6300 + 200 = 6500")
	assert_eq(engine.combo, 31, "Combo should be 31")

func test_combo_streak_reset() -> void:
	print("\n--- Test Suite 3: Miss & Streak Reset ---")
	var engine = ScoringEngineScript.new()

	# Build up a 15-hit combo (Multiplier is 2x)
	for i in range(15):
		engine.register_hit("PERFECT")
	assert_eq(engine.combo, 15, "Combo should be 15")
	assert_eq(engine.get_multiplier(), 2, "Multiplier should be 2x")
	var score_before_miss = engine.score

	# Register a Miss
	var res_miss = engine.register_miss()
	assert_eq(res_miss["judgment"], "MISS", "Judgment is MISS")
	assert_eq(res_miss["points_awarded"], 0, "Miss awards 0 pts")
	assert_eq(engine.score, score_before_miss, "Score does not increase on miss")
	assert_eq(engine.combo, 0, "Combo immediately resets to 0 on miss")
	assert_eq(engine.get_multiplier(), 1, "Multiplier drops back to 1x")
	assert_eq(engine.max_combo, 15, "Max combo remains preserved at 15")

	# Next hit after miss should be at 1x multiplier
	var res_after = engine.register_hit("PERFECT")
	assert_eq(res_after["multiplier"], 1, "Next hit after miss is at 1x")
	assert_eq(res_after["points_awarded"], 100, "Next hit awards 100 pts")
	assert_eq(engine.combo, 1, "Combo restarts at 1")

func test_pitch_matching_and_polyphony() -> void:
	print("\n--- Test Suite 4: Polyphonic Pitch Matching & Timing Offset ---")
	var engine = ScoringEngineScript.new()

	# Polyphonic chord at time 1.00s: C4 (MIDI 60), E4 (MIDI 64), G4 (MIDI 67)
	var active_notes = [
		{ "pitch_midi": 60, "time_sec": 1.00, "is_hit": false },
		{ "pitch_midi": 64, "time_sec": 1.00, "is_hit": false },
		{ "pitch_midi": 67, "time_sec": 1.00, "is_hit": false }
	]

	# User plays C4 (MIDI 60) at time 1.02s (+20ms offset -> PERFECT)
	var hit1 = engine.process_input(1.02, 60, active_notes)
	assert_eq(hit1["judgment"], "PERFECT", "C4 at +20ms should be judged PERFECT")
	assert_eq(active_notes[0]["is_hit"], true, "Note C4 marked as is_hit")
	assert_eq(active_notes[1]["is_hit"], false, "Note E4 should remain unhit")

	# User plays wrong pitch D4 (MIDI 62) at time 1.03s -> no match
	var hit_wrong = engine.process_input(1.03, 62, active_notes)
	assert_true(hit_wrong.is_empty(), "Wrong pitch MIDI 62 should match nothing")

	# User plays E4 (MIDI 64) at time 1.07s (+70ms offset -> GOOD)
	var hit2 = engine.process_input(1.07, 64, active_notes)
	assert_eq(hit2["judgment"], "GOOD", "E4 at +70ms should be judged GOOD")
	assert_eq(active_notes[1]["is_hit"], true, "Note E4 marked as is_hit")

	# User plays G4 (MIDI 67) at time 1.15s (+150ms offset -> beyond 100ms window -> no match)
	var hit3 = engine.process_input(1.15, 67, active_notes)
	assert_true(hit3.is_empty(), "G4 at +150ms is outside hit window, returns empty")
	assert_eq(active_notes[2]["is_hit"], false, "G4 remains unhit")

func test_expired_notes() -> void:
	print("\n--- Test Suite 5: Note Expiration (Miss on Passing Hit Window) ---")
	var engine = ScoringEngineScript.new()

	var active_notes = [
		{ "pitch_midi": 60, "time_sec": 2.00, "is_hit": false },
		{ "pitch_midi": 64, "time_sec": 2.50, "is_hit": false }
	]

	# Build up 5-combo
	for i in range(5):
		engine.register_hit("PERFECT")
	assert_eq(engine.combo, 5, "Combo is 5")

	# Song time reaches 2.05s (Note 60 is only 50ms past, still within good window <= 100ms)
	var expired_early = engine.check_expired_notes(2.05, active_notes)
	assert_eq(expired_early.size(), 0, "No notes expired at 2.05s")
	assert_eq(engine.combo, 5, "Combo remains 5")

	# Song time reaches 2.12s (Note 60 is 120ms past -> > 100ms -> expired!)
	var expired_late = engine.check_expired_notes(2.12, active_notes)
	assert_eq(expired_late.size(), 1, "1 note expired at 2.12s")
	assert_eq(expired_late[0]["judgment"], "MISS", "Expired note awarded MISS")
	assert_eq(engine.combo, 0, "Combo reset to 0 by expired note")
	assert_eq(active_notes[0]["is_missed"], true, "Note 60 marked is_missed")
	assert_eq(active_notes[1]["is_hit"], false, "Note 64 at 2.50s remains untouched")

	# Second check at 2.15s does not re-expire Note 60
	var expired_again = engine.check_expired_notes(2.15, active_notes)
	assert_eq(expired_again.size(), 0, "No duplicate expiration")

func test_accuracy_calculation() -> void:
	print("\n--- Test Suite 6: Performance Accuracy Percentage ---")
	var engine = ScoringEngineScript.new()

	# 2 Perfect (100% weight each), 2 Good (50% weight each), 0 Miss -> (2*1 + 2*0.5)/4 = 3/4 = 75.0%
	engine.register_hit("PERFECT")
	engine.register_hit("PERFECT")
	engine.register_hit("GOOD")
	engine.register_hit("GOOD")
	assert_eq(engine.get_accuracy(), 75.0, "Accuracy for 2 Perfect + 2 Good out of 4 should be 75.0%")

	# Add 1 Miss -> total 5 notes: (2*1 + 2*0.5 + 0)/5 = 3/5 = 60.0%
	engine.register_miss()
	assert_eq(engine.get_accuracy(), 60.0, "Accuracy with 1 added Miss should be 60.0%")
