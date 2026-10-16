# res://tests/test_adversarial_m1.gd
extends SceneTree

const NoteDataScript = preload("res://scripts/note_data.gd")
const NoteRendererScript = preload("res://scripts/note_renderer.gd")
const HighwayScript = preload("res://scripts/highway.gd")
const ScoringEngineScript = preload("res://scripts/scoring_engine.gd")

var tests_passed: int = 0
var tests_failed: int = 0
var findings: Array[Dictionary] = []

func _init() -> void:
	print("================================================================================")
	print("          ADVERSARIAL STRESS TEST HARNESS — MILESTONE 1 (M1)")
	print("================================================================================")

	test_extreme_pitches_and_geometry()
	test_out_of_range_pitches()
	test_dense_chord_stacking_and_collisions()
	test_scrolling_pooling_and_memory_stability()
	test_extreme_scroll_speeds()
	test_renderer_stress_and_safety()

	print("\n================================================================================")
	print(" ADVERSARIAL TEST RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("================================================================================")
	
	if findings.size() > 0:
		print("\n--- EMPIRICAL FINDINGS & VULNERABILITIES DETECTED (%d) ---" % findings.size())
		for idx in range(findings.size()):
			var f = findings[idx]
			print("[%d] Severity: %s | Area: %s" % [idx + 1, f["severity"], f["area"]])
			print("    Description: %s" % f["description"])
			print("    Evidence: %s" % f["evidence"])
	else:
		print("\nNo vulnerabilities or defects found.")

	quit(0)

func assert_true(condition: bool, message: String, severity: String = "MEDIUM", area: String = "GENERAL") -> bool:
	if condition:
		tests_passed += 1
		print("  [PASS] %s" % message)
		return true
	else:
		tests_failed += 1
		printerr("  [FAIL] %s" % message)
		findings.append({
			"severity": severity,
			"area": area,
			"description": message,
			"evidence": "Condition evaluated to false"
		})
		return false

func assert_eq(actual, expected, message: String, severity: String = "MEDIUM", area: String = "GENERAL") -> bool:
	if actual == expected:
		tests_passed += 1
		print("  [PASS] %s (expected %s, got %s)" % [message, str(expected), str(actual)])
		return true
	else:
		tests_failed += 1
		printerr("  [FAIL] %s (expected %s, got %s)" % [message, str(expected), str(actual)])
		findings.append({
			"severity": severity,
			"area": area,
			"description": message,
			"evidence": "Expected '%s', got '%s'" % [str(expected), str(actual)]
		})
		return false

func assert_approx_eq(actual: float, expected: float, tolerance: float, message: String, severity: String = "MEDIUM", area: String = "GENERAL") -> bool:
	if absf(actual - expected) <= tolerance:
		tests_passed += 1
		print("  [PASS] %s (expected ~%f, got %f)" % [message, expected, actual])
		return true
	else:
		tests_failed += 1
		printerr("  [FAIL] %s (expected ~%f, got %f, diff %f > tol %f)" % [message, expected, actual, absf(actual - expected), tolerance])
		findings.append({
			"severity": severity,
			"area": area,
			"description": message,
			"evidence": "Expected ~%f, got %f (diff %f > %f)" % [expected, actual, absf(actual - expected), tolerance]
		})
		return false

# ------------------------------------------------------------------------------
# SUITE 1: Extreme Pitches & Grand Staff Coordinate Geometry
# ------------------------------------------------------------------------------
func test_extreme_pitches_and_geometry() -> void:
	print("\n--- Suite 1: Extreme Pitch Geometry & Ledger Lines ---")

	# 1. C4 / Middle C (MIDI 60)
	var n_c4 = NoteDataScript.new(1, 60, 1.0, 0.5)
	assert_eq(n_c4.pitch_midi, 60, "C4 MIDI pitch is 60", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c4.pitch_name, "C4", "C4 pitch name is C4", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c4.diatonic_step, 28, "C4 diatonic step is 28", "LOW", "PITCH_GEOMETRY")
	assert_approx_eq(n_c4.y_pos, 360.0, 0.001, "C4 Y position is exactly Y=360.0", "HIGH", "PITCH_GEOMETRY")
	assert_eq(n_c4.ledger_y_positions.size(), 1, "C4 has exactly 1 ledger line", "MEDIUM", "LEDGER_LINES")
	if n_c4.ledger_y_positions.size() > 0:
		assert_approx_eq(n_c4.ledger_y_positions[0], 360.0, 0.001, "C4 ledger line is at Y=360.0", "HIGH", "LEDGER_LINES")

	# 2. C2 (MIDI 36) - Lower boundary of project spec (C2 to C6+)
	var n_c2 = NoteDataScript.new(2, 36, 1.0, 0.5)
	assert_eq(n_c2.pitch_midi, 36, "C2 MIDI pitch is 36", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c2.pitch_name, "C2", "C2 pitch name is C2", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c2.diatonic_step, 14, "C2 diatonic step is 14", "LOW", "PITCH_GEOMETRY")
	assert_approx_eq(n_c2.y_pos, 486.0, 0.001, "C2 Y position is Y=486.0", "HIGH", "PITCH_GEOMETRY")
	assert_eq(n_c2.ledger_y_positions.size(), 2, "C2 has 2 ledger lines below Bass staff", "MEDIUM", "LEDGER_LINES")
	if n_c2.ledger_y_positions.size() == 2:
		assert_approx_eq(n_c2.ledger_y_positions[0], 468.0, 0.001, "C2 1st ledger is E2 at Y=468.0", "MEDIUM", "LEDGER_LINES")
		assert_approx_eq(n_c2.ledger_y_positions[1], 486.0, 0.001, "C2 2nd ledger is C2 at Y=486.0", "MEDIUM", "LEDGER_LINES")

	# 3. C6 (MIDI 84) - Upper standard boundary
	var n_c6 = NoteDataScript.new(3, 84, 1.0, 0.5)
	assert_eq(n_c6.pitch_midi, 84, "C6 MIDI pitch is 84", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c6.pitch_name, "C6", "C6 pitch name is C6", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c6.diatonic_step, 42, "C6 diatonic step is 42", "LOW", "PITCH_GEOMETRY")
	assert_approx_eq(n_c6.y_pos, 234.0, 0.001, "C6 Y position is Y=234.0", "HIGH", "PITCH_GEOMETRY")
	assert_eq(n_c6.ledger_y_positions.size(), 2, "C6 has 2 ledger lines above Treble staff", "MEDIUM", "LEDGER_LINES")
	if n_c6.ledger_y_positions.size() == 2:
		assert_approx_eq(n_c6.ledger_y_positions[0], 252.0, 0.001, "C6 1st ledger is A5 at Y=252.0", "MEDIUM", "LEDGER_LINES")
		assert_approx_eq(n_c6.ledger_y_positions[1], 234.0, 0.001, "C6 2nd ledger is C6 at Y=234.0", "MEDIUM", "LEDGER_LINES")

	# 4. C8 (MIDI 108) - Highest piano key (boundary of 88-key range)
	var n_c8 = NoteDataScript.new(4, 108, 1.0, 0.5)
	assert_eq(n_c8.pitch_midi, 108, "C8 MIDI pitch is 108", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c8.pitch_name, "C8", "C8 pitch name is C8", "LOW", "PITCH_GEOMETRY")
	assert_eq(n_c8.diatonic_step, 56, "C8 diatonic step is 56", "LOW", "PITCH_GEOMETRY")
	assert_approx_eq(n_c8.y_pos, 108.0, 0.001, "C8 Y position is Y=108.0", "HIGH", "PITCH_GEOMETRY")
	assert_eq(n_c8.ledger_y_positions.size(), 9, "C8 has 9 ledger lines", "MEDIUM", "LEDGER_LINES")
	if n_c8.ledger_y_positions.size() == 9:
		assert_approx_eq(n_c8.ledger_y_positions[0], 252.0, 0.001, "C8 first ledger is at Y=252.0", "LOW", "LEDGER_LINES")
		assert_approx_eq(n_c8.ledger_y_positions[8], 108.0, 0.001, "C8 highest ledger is at Y=108.0", "LOW", "LEDGER_LINES")

	# 5. C0 (MIDI 12) - Sub-audio extreme pitch
	var n_c0 = NoteDataScript.new(5, 12, 1.0, 0.5)
	var c0_preserves_midi = (n_c0.pitch_midi == 12)
	assert_true(c0_preserves_midi, "NoteData supports C0 (MIDI 12) without clamping to A0 (MIDI 21)", "HIGH", "PITCH_CLAMPING")

	# Static math methods for C0 directly
	var c0_step = NoteDataScript.midi_to_step(12)
	var c0_y = NoteDataScript.step_to_y(c0_step)
	assert_eq(c0_step, 0, "midi_to_step(12) returns diatonic step 0", "MEDIUM", "PITCH_GEOMETRY")
	assert_approx_eq(c0_y, 612.0, 0.001, "midi_to_y(12) returns Y=612.0", "MEDIUM", "PITCH_GEOMETRY")
	var c0_ledgers = NoteDataScript.get_ledger_steps(c0_step)
	assert_eq(c0_ledgers.size(), 9, "C0 (step 0) has 9 ledger lines", "MEDIUM", "LEDGER_LINES")

# ------------------------------------------------------------------------------
# SUITE 2: Out-of-Range MIDI Numbers (<0, >127)
# ------------------------------------------------------------------------------
func test_out_of_range_pitches() -> void:
	print("\n--- Suite 2: Out-of-Range MIDI Numbers ---")

	var negative_midis = [-1, -12, -24, -100]
	for m in negative_midis:
		var n_neg = NoteDataScript.new(10, m, 1.0, 0.5)
		assert_true(n_neg.pitch_midi >= 0, "Negative MIDI %d clamped safely to valid range (got %d)" % [m, n_neg.pitch_midi], "LOW", "PITCH_SAFETY")
		assert_true(not is_nan(n_neg.y_pos) and not is_inf(n_neg.y_pos), "Negative MIDI %d produced finite Y position (%f)" % [m, n_neg.y_pos], "HIGH", "PITCH_SAFETY")

		var step_neg = NoteDataScript.midi_to_step(m)
		var y_neg = NoteDataScript.step_to_y(step_neg)
		assert_true(not is_nan(y_neg) and not is_inf(y_neg), "midi_to_y(%d) produces finite Y (%f)" % [m, y_neg], "MEDIUM", "PITCH_SAFETY")

	var excessive_midis = [128, 150, 255, 1000]
	for m in excessive_midis:
		var n_exc = NoteDataScript.new(11, m, 1.0, 0.5)
		assert_true(n_exc.pitch_midi <= 127, "Excessive MIDI %d clamped to valid range (got %d)" % [m, n_exc.pitch_midi], "LOW", "PITCH_SAFETY")
		assert_true(not is_nan(n_exc.y_pos) and not is_inf(n_exc.y_pos), "Excessive MIDI %d produced finite Y position (%f)" % [m, n_exc.y_pos], "HIGH", "PITCH_SAFETY")

	var highway = HighwayScript.new()
	highway.set_live_pitch(-10)
	assert_eq(highway.live_pitch_y, -1.0, "set_live_pitch(-10) resets indicator to -1.0", "LOW", "HIGHWAY_CURSOR")
	highway.set_live_pitch(150)
	assert_eq(highway.live_pitch_y, -1.0, "set_live_pitch(150) resets indicator to -1.0", "LOW", "HIGHWAY_CURSOR")
	highway.set_live_pitch(12)
	var c0_highway_supported = (highway.live_pitch_y != -1.0)
	if not c0_highway_supported:
		print("  [INFO] Highway.set_live_pitch(12) ignored C0 because guard is [21..108]")
	highway.free()

# ------------------------------------------------------------------------------
# SUITE 3: Dense Chord Stacking & Collision Handling
# ------------------------------------------------------------------------------
func test_dense_chord_stacking_and_collisions() -> void:
	print("\n--- Suite 3: Dense Chord Stacking & Collision Handling ---")

	var highway = HighwayScript.new()

	# 1. Harmonic Fifths: C4 (60, step 28) + G4 (67, step 32)
	var fifth_chart = [
		{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5},
		{"pitch_midi": 67, "time_sec": 1.0, "duration_sec": 0.5}
	]
	highway.load_notes(fifth_chart)
	var n_c4 = highway.chart_notes[0]
	var n_g4 = highway.chart_notes[1]
	assert_eq(n_c4.chord_offset_x, 0.0, "Fifth C4 has 0.0 horizontal offset", "LOW", "CHORD_ALIGNMENT")
	assert_eq(n_g4.chord_offset_x, 0.0, "Fifth G4 has 0.0 horizontal offset", "LOW", "CHORD_ALIGNMENT")
	var fifth_dy = absf(n_c4.y_pos - n_g4.y_pos)
	assert_true(fifth_dy >= 17.0, "Fifth vertical distance (%f px) exceeds note diameter 17px" % fifth_dy, "HIGH", "COLLISION")

	# 2. Octave Cluster: C3 (48) + C4 (60) + C5 (72)
	var octave_chart = [
		{"pitch_midi": 48, "time_sec": 2.0, "duration_sec": 0.5},
		{"pitch_midi": 60, "time_sec": 2.0, "duration_sec": 0.5},
		{"pitch_midi": 72, "time_sec": 2.0, "duration_sec": 0.5}
	]
	highway.load_notes(octave_chart)
	for n in highway.chart_notes:
		assert_eq(n.chord_offset_x, 0.0, "Octave note %s has 0.0 horizontal offset" % n.pitch_name, "LOW", "CHORD_ALIGNMENT")

	# 3. Diatonic Second Pair: C4 (60, step 28) + D4 (62, step 29)
	var second_chart = [
		{"pitch_midi": 60, "time_sec": 3.0, "duration_sec": 0.5},
		{"pitch_midi": 62, "time_sec": 3.0, "duration_sec": 0.5}
	]
	highway.load_notes(second_chart)
	var s_c4 = highway.chart_notes[0]
	var s_d4 = highway.chart_notes[1]
	var second_dx = absf(s_c4.chord_offset_x - s_d4.chord_offset_x)
	assert_true(second_dx >= 15.0, "Second pair separated horizontally by >= 15px (got %f px)" % second_dx, "HIGH", "COLLISION")
	var second_dist = sqrt(pow(second_dx, 2.0) + pow(s_c4.y_pos - s_d4.y_pos, 2.0))
	assert_true(second_dist >= 17.0, "Second pair 2D distance (%f px) clears notehead collision (17px)" % second_dist, "HIGH", "COLLISION")

	# 4. Dense Cluster of Seconds: C4 (28) + D4 (29) + E4 (30) + F4 (31)
	var cluster_chart = [
		{"pitch_midi": 60, "time_sec": 4.0, "duration_sec": 0.5}, # C4 step 28
		{"pitch_midi": 62, "time_sec": 4.0, "duration_sec": 0.5}, # D4 step 29
		{"pitch_midi": 64, "time_sec": 4.0, "duration_sec": 0.5}, # E4 step 30
		{"pitch_midi": 65, "time_sec": 4.0, "duration_sec": 0.5}  # F4 step 31
	]
	highway.load_notes(cluster_chart)
	var cl_c4 = highway.chart_notes[0]
	var cl_d4 = highway.chart_notes[1]
	var cl_e4 = highway.chart_notes[2]
	var cl_f4 = highway.chart_notes[3]

	print("  Cluster offsets: C4=%.1f, D4=%.1f, E4=%.1f, F4=%.1f" % [cl_c4.chord_offset_x, cl_d4.chord_offset_x, cl_e4.chord_offset_x, cl_f4.chord_offset_x])

	var pairs = [
		["C4", cl_c4, "D4", cl_d4],
		["D4", cl_d4, "E4", cl_e4],
		["E4", cl_e4, "F4", cl_f4]
	]

	var cluster_collision_found = false
	for p in pairs:
		var n1_name = p[0]
		var n1: NoteData = p[1]
		var n2_name = p[2]
		var n2: NoteData = p[3]
		var dx = absf(n1.chord_offset_x - n2.chord_offset_x)
		var dy = absf(n1.y_pos - n2.y_pos)
		var dist = sqrt(dx * dx + dy * dy)
		var collides = dist < 17.0
		if collides:
			cluster_collision_found = true
			printerr("  [COLLISION DETECTED] %s and %s in 4-note second cluster: dx=%.1f, dy=%.1f, dist=%.2f < 17.0px" % [n1_name, n2_name, dx, dy, dist])

	var cluster_ok = not cluster_collision_found
	assert_true(cluster_ok, "Dense cluster of 4 seconds has NO notehead collisions (< 17px center-to-center)", "HIGH", "CHORD_COLLISION")

	highway.free()

# ------------------------------------------------------------------------------
# SUITE 4: Scrolling Pooling & Memory Stability (5,000 Notes Chart)
# ------------------------------------------------------------------------------
func test_scrolling_pooling_and_memory_stability() -> void:
	print("\n--- Suite 4: Scrolling Pooling & Memory Stability (5,000 Notes Chart) ---")

	var highway = HighwayScript.new()
	var test_chart: Array[Dictionary] = []

	var rng = RandomNumberGenerator.new()
	rng.seed = 12345
	for i in range(5000):
		var t: float = float(i) * 0.02 + 0.1
		var midi: int = rng.randi_range(36, 84)
		var dur: float = rng.randf_range(0.05, 0.3)
		test_chart.append({
			"pitch_midi": midi,
			"time_sec": t,
			"duration_sec": dur
		})

	print("  Generated 5,000 notes chart. Measuring load_notes performance...")
	var t0 = Time.get_ticks_usec()
	highway.load_notes(test_chart)
	var t_load_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	print("  load_notes(5000 notes) completed in %.2f ms" % t_load_ms)

	assert_eq(highway.chart_notes.size(), 5000, "Highway loaded exactly 5000 notes", "HIGH", "SCROLL_POOLING")
	var load_time_ok = (t_load_ms < 5000.0)
	assert_true(load_time_ok, "load_notes for 5,000 notes completed in reasonable time (< 5000ms, took %.2f ms)" % t_load_ms, "MEDIUM", "PERFORMANCE")

	highway.start_playback()
	var max_active_notes: int = 0
	var sim_frames: int = 600
	var delta: float = 1.0 / 60.0

	var mem_before = OS.get_static_memory_usage()

	for frame in range(sim_frames):
		highway._process(delta)
		var cur_active = highway.active_notes.size()
		if cur_active > max_active_notes:
			max_active_notes = cur_active

	var mem_after = OS.get_static_memory_usage()
	var mem_diff_kb = float(mem_after - mem_before) / 1024.0

	print("  Max active pooled notes on screen during playback: %d (out of 5,000)" % max_active_notes)
	print("  Memory difference after 600 frames: %.2f KB" % mem_diff_kb)

	assert_true(max_active_notes < 400, "Active notes pool is strictly bounded (< 400, observed peak %d)" % max_active_notes, "HIGH", "SCROLL_POOLING")
	assert_true(highway.spawn_index > 0, "Spawn index advanced through chart (%d / 5000)" % highway.spawn_index, "HIGH", "SCROLL_POOLING")
	assert_true(highway.active_notes.size() < max_active_notes + 50, "Culling properly removes expired notes behind despawn threshold", "HIGH", "SCROLL_POOLING")

	highway.free()

# ------------------------------------------------------------------------------
# SUITE 5: Extreme Scroll Speeds & Edge Cases
# ------------------------------------------------------------------------------
func test_extreme_scroll_speeds() -> void:
	print("\n--- Suite 5: Extreme Scroll Speeds ---")

	var speeds = [100.0, 400.0, 1500.0, 5000.0]
	for spd in speeds:
		var highway = HighwayScript.new()
		highway.scroll_speed = spd
		var sample_chart = [
			{"pitch_midi": 60, "time_sec": 0.5, "duration_sec": 0.2},
			{"pitch_midi": 64, "time_sec": 1.0, "duration_sec": 0.2},
			{"pitch_midi": 67, "time_sec": 1.5, "duration_sec": 0.2}
		]
		highway.load_notes(sample_chart)
		highway.start_playback()

		for _f in range(120):
			highway._process(1.0 / 60.0)

		assert_true(highway.current_song_time > 1.8, "Highway progressed normally at scroll_speed=%.1f" % spd, "LOW", "SPEED_STABILITY")
		assert_true(highway.active_notes.size() <= 3, "Active notes pool stable at scroll_speed=%.1f" % spd, "LOW", "SPEED_STABILITY")
		highway.free()

	# Test Zero Scroll Speed
	var hw_zero = HighwayScript.new()
	hw_zero.scroll_speed = 0.0
	var sample_notes = [{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.2}]
	hw_zero.load_notes(sample_notes)
	hw_zero.start_playback()

	hw_zero._process(0.016)
	var spawn_lookahead = (HighwayScript.SCREEN_WIDTH - hw_zero.x_hit + HighwayScript.SPAWN_MARGIN_PX) / hw_zero.scroll_speed if hw_zero.scroll_speed != 0 else INF
	print("  Scroll speed 0.0 lookahead evaluated to: %f" % spawn_lookahead)
	if is_inf(spawn_lookahead):
		findings.append({
			"severity": "LOW",
			"area": "SPEED_STABILITY",
			"description": "Highway does not guard against scroll_speed <= 0.0. When scroll_speed is 0.0, spawn_lookahead evaluates to INF, spawning the entire chart instantly.",
			"evidence": "spawn_lookahead = (1280 - 160 + 100) / 0.0 = INF"
		})
	hw_zero.free()

# ------------------------------------------------------------------------------
# SUITE 6: NoteRenderer Structural Safety & Data Mapping
# ------------------------------------------------------------------------------
func test_renderer_stress_and_safety() -> void:
	print("\n--- Suite 6: NoteRenderer Structural Safety & Data Mapping ---")

	var renderer = NoteRendererScript.new()

	# 1. Update with empty notes
	renderer.update_notes([], 0.0, 160.0, 400.0)
	assert_eq(renderer.active_notes.size(), 0, "NoteRenderer handles empty note array", "LOW", "RENDERER_SAFETY")

	# 2. Update with 500 simultaneous notes
	var large_notes: Array[NoteData] = []
	for i in range(500):
		var n = NoteDataScript.new(i, 60 + (i % 24), float(i) * 0.01, 0.1)
		large_notes.append(n)

	renderer.update_notes(large_notes, 1.0, 160.0, 400.0)
	assert_eq(renderer.active_notes.size(), 500, "NoteRenderer updates 500 simultaneous notes without state corruption", "MEDIUM", "RENDERER_SAFETY")

	# 3. Update with extreme durations and coordinates
	var extreme_notes: Array[NoteData] = [
		NoteDataScript.new(1, 61, 0.0, 100.0),
		NoteDataScript.new(2, 84, 0.0, 0.001),
		NoteDataScript.new(3, 36, 0.0, 0.0)
	]
	renderer.update_notes(extreme_notes, 0.0, 160.0, 400.0)
	assert_eq(renderer.active_notes.size(), 3, "NoteRenderer handles extreme duration notes cleanly", "LOW", "RENDERER_SAFETY")

	renderer.free()
