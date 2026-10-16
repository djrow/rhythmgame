# res://tests/test_omr_runner.gd
extends SceneTree

## Headless Godot Test Runner for Milestone 4: On-Device OMR & Level Alignment
## Verifies OMRProcessor and LevelLoader against all 3 bundled test pieces:
## - Piece 1: Monophonic Melody ("Ode to Joy")
## - Piece 2: 2-Part Harmony ("Bach Minuet")
## - Piece 3: Polyphonic Progression ("Cadence & Triad Progression")

const LevelLoaderScript = preload("res://scripts/level_loader.gd")
const OMRProcessorScript = preload("res://scripts/omr_processor.gd")
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
	print(" RUNNING OMR & LEVEL ALIGNMENT HEADLESS RUNNER   ")
	print("==================================================")

	test_suite_1_staff_line_detection()
	test_suite_2_barline_detection_and_measures()
	test_suite_3_omr_note_recognition_accuracy()
	test_suite_4_audio_loading_wav_mp3_ogg()
	test_suite_5_chart_json_loading_and_parsing()
	test_suite_6_audio_chart_alignment_and_offset()
	test_suite_7_highway_integration_and_playback()
	test_suite_8_on_the_fly_omr_level_ingestion()

	print("==================================================")
	print(" RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("==================================================")

	if tests_failed == 0:
		print("ALL OMR & LEVEL ALIGNMENT TESTS PASSED [OK]")
		quit(0)
	else:
		push_error("VERIFICATION FAILED with %d errors" % tests_failed)
		quit(1)

func test_suite_1_staff_line_detection() -> void:
	print("\n--- Test Suite 1: Staff Line Detection Across All 3 Bundled Scores ---")
	var omr = OMRProcessorScript.new()
	var pieces = [
		"res://assets/test_pieces/piece_1_monophonic/score.png",
		"res://assets/test_pieces/piece_2_harmony/score.png",
		"res://assets/test_pieces/piece_3_polyphonic/score.png"
	]

	var expected_treble = [320, 340, 360, 380, 400]
	var expected_bass = [440, 460, 480, 500, 520]

	for p in pieces:
		var img = Image.load_from_file(ProjectSettings.globalize_path(p))
		assert_true(img != null and not img.is_empty(), "Score image exists and loads: " + p.get_file())
		img.convert(Image.FORMAT_L8)
		var lines = omr.detect_staff_lines(img.get_data(), img.get_width(), img.get_height())
		assert_eq(lines.size(), 10, "Detected exactly 10 staff lines in " + p.get_file())

		# Check Treble staff lines (F5, D5, B4, G4, E4)
		for i in range(5):
			assert_eq(lines[i], expected_treble[i], "Treble line %d matches Y=%d" % [i + 1, expected_treble[i]])

		# Check Bass staff lines (A3, F3, D3, B2, G2)
		for i in range(5):
			assert_eq(lines[5 + i], expected_bass[i], "Bass line %d matches Y=%d" % [i + 1, expected_bass[i]])

		# Verify spacing Ss = 20px
		assert_eq(lines[1] - lines[0], 20, "Treble line spacing is 20px")
		assert_eq(lines[6] - lines[5], 20, "Bass line spacing is 20px")
		# Verify inter-staff gap between E4 (400) and A3 (440) = 40px (Middle C ledger at 420)
		assert_eq(lines[5] - lines[4], 40, "Inter-staff gap is 40px (2 * Ss) for Middle C symmetry")

func test_suite_2_barline_detection_and_measures() -> void:
	print("\n--- Test Suite 2: Barline Detection & Measure Segmentation ---")
	var omr = OMRProcessorScript.new()
	var staff_lines: Array[int] = [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]

	# Piece 1: 4 measures -> 5 barlines
	var img1 = Image.load_from_file(ProjectSettings.globalize_path("res://assets/test_pieces/piece_1_monophonic/score.png"))
	img1.convert(Image.FORMAT_L8)
	var bars1 = omr.detect_barlines(img1.get_data(), img1.get_width(), img1.get_height(), staff_lines)
	assert_eq(bars1.size(), 5, "Piece 1: Detected 5 barlines (4 measures)")

	# Piece 2: 4 measures -> 5 barlines
	var img2 = Image.load_from_file(ProjectSettings.globalize_path("res://assets/test_pieces/piece_2_harmony/score.png"))
	img2.convert(Image.FORMAT_L8)
	var bars2 = omr.detect_barlines(img2.get_data(), img2.get_width(), img2.get_height(), staff_lines)
	assert_eq(bars2.size(), 5, "Piece 2: Detected 5 barlines (4 measures)")

	# Piece 3: 5 measures -> 6 barlines
	var img3 = Image.load_from_file(ProjectSettings.globalize_path("res://assets/test_pieces/piece_3_polyphonic/score.png"))
	img3.convert(Image.FORMAT_L8)
	var bars3 = omr.detect_barlines(img3.get_data(), img3.get_width(), img3.get_height(), staff_lines)
	assert_eq(bars3.size(), 6, "Piece 3: Detected 6 barlines (5 measures)")

func test_suite_3_omr_note_recognition_accuracy() -> void:
	print("\n--- Test Suite 3: OMR Notehead Recognition & MIDI Pitch Mapping (Target >= 85%) ---")
	var omr = OMRProcessorScript.new()

	var test_cases = [
		{"name": "Piece 1 (Monophonic)", "score": "res://assets/test_pieces/piece_1_monophonic/score.png", "gt": "res://assets/test_pieces/piece_1_monophonic/ground_truth.json", "expected_notes": 15},
		{"name": "Piece 2 (Harmony)", "score": "res://assets/test_pieces/piece_2_harmony/score.png", "gt": "res://assets/test_pieces/piece_2_harmony/ground_truth.json", "expected_notes": 16},
		{"name": "Piece 3 (Polyphonic)", "score": "res://assets/test_pieces/piece_3_polyphonic/score.png", "gt": "res://assets/test_pieces/piece_3_polyphonic/ground_truth.json", "expected_notes": 20}
	]

	for tc in test_cases:
		var gt_text = FileAccess.get_file_as_string(tc["gt"])
		var gt_json = JSON.parse_string(gt_text)
		var gt_notes: Array = gt_json["notes"]
		var piece_bpm: float = float(gt_json.get("bpm", 120.0))
		var piece_ts: Array = gt_json.get("time_signature", [4, 4])

		var chart = omr.process_image(tc["score"], {"bpm": piece_bpm, "time_signature": piece_ts})
		assert_true(not chart.is_empty(), tc["name"] + " OMR processing succeeded")
		var det_notes: Array = chart.get("notes", [])
		assert_true(det_notes.size() >= int(tc["expected_notes"] * 0.85), tc["name"] + " detected note count meets threshold")

		# Compute Pitch & Onset accuracy
		var matched_count: int = 0
		var matched_gt: Dictionary = {}
		for det in det_notes:
			var best_gi: int = -1
			var min_dt: float = 999.0
			for gi in range(gt_notes.size()):
				if matched_gt.has(gi): continue
				var gn = gt_notes[gi]
				if int(gn["pitch_midi"]) == int(det["pitch_midi"]):
					var dt = absf(float(gn["onset_sec"]) - float(det["time_sec"]))
					if dt <= 0.35 and dt < min_dt:
						min_dt = dt
						best_gi = gi
			if best_gi >= 0:
				matched_gt[best_gi] = true
				matched_count += 1

		var accuracy: float = float(matched_count) / float(gt_notes.size())
		print("  %s: Matched %d / %d notes (%.1f%%)" % [tc["name"], matched_count, gt_notes.size(), accuracy * 100.0])
		assert_true(accuracy >= 0.85, tc["name"] + " note recognition accuracy >= 85.0% target")

func test_suite_4_audio_loading_wav_mp3_ogg() -> void:
	print("\n--- Test Suite 4: LevelLoader Audio Stream Ingestion (WAV/MP3/OGG) ---")
	var loader = LevelLoaderScript.new()

	# Test 1: Bundled WAV files
	var wav_paths = [
		"res://assets/test_pieces/piece_1_monophonic/audio.wav",
		"res://assets/test_pieces/piece_2_harmony/audio.wav",
		"res://assets/test_pieces/piece_3_polyphonic/audio.wav"
	]
	var expected_lens = [8.5, 7.8, 15.5]

	for i in range(wav_paths.size()):
		var p = wav_paths[i]
		var stream = loader.load_audio_stream(p)
		assert_true(stream != null, "WAV audio loaded successfully: " + p.get_file())
		assert_true(stream is AudioStreamWAV, "Stream is AudioStreamWAV")
		var dur = stream.get_length()
		assert_true(absf(dur - expected_lens[i]) < 0.1, "WAV duration matches expected ~%.1fs (got %.2fs)" % [expected_lens[i], dur])

	# Test 2: AudioStreamOggVorbis buffer decoding check
	assert_true(ClassDB.class_has_method("AudioStreamOggVorbis", "load_from_buffer"), "AudioStreamOggVorbis supports load_from_buffer")

	# Test 3: AudioStreamMP3 buffer assignment
	var mp3 = AudioStreamMP3.new()
	assert_true(mp3 != null, "AudioStreamMP3 can be instantiated for MP3 playback")

	loader.free()

func test_suite_5_chart_json_loading_and_parsing() -> void:
	print("\n--- Test Suite 5: Chart JSON Parsing & Schema Validation ---")
	var loader = LevelLoaderScript.new()

	for piece_id in ["piece_1_monophonic", "piece_2_harmony", "piece_3_polyphonic"]:
		var piece_def = LevelLoaderScript.BUNDLED_PIECES[piece_id]
		var chart = loader.load_chart_from_json(piece_def["chart_path"])
		assert_true(not chart.is_empty(), "Loaded chart JSON for " + piece_id)
		assert_true(chart.has("notes"), "Chart JSON contains 'notes' array")
		assert_true(chart.has("bpm"), "Chart JSON contains 'bpm'")
		assert_true(chart.has("time_signature"), "Chart JSON contains 'time_signature'")
		var notes: Array = chart["notes"]
		assert_true(notes.size() > 0, "Chart has non-empty notes list: %d notes" % notes.size())

	loader.free()

func test_suite_6_audio_chart_alignment_and_offset() -> void:
	print("\n--- Test Suite 6: Audio-Chart Alignment & Latency Calibration ---")
	var loader = LevelLoaderScript.new()

	var piece_def = LevelLoaderScript.BUNDLED_PIECES["piece_1_monophonic"]
	var chart = loader.load_chart_from_json(piece_def["chart_path"])
	var audio = loader.load_audio_stream(piece_def["audio_path"])

	# Align with default 0ms offset
	loader.set_calibration_offset_ms(0.0)
	var aligned = loader.align_level(chart, audio)
	assert_true(aligned["is_aligned"], "Level is properly aligned (chart duration <= audio duration)")
	assert_eq(aligned["calibration_offset_ms"], 0.0, "Calibration offset ms is 0.0")
	assert_eq(aligned["calibration_offset_sec"], 0.0, "Calibration offset sec is 0.0")
	assert_true(aligned["chart_duration"] <= aligned["audio_duration"] + 0.1, "Chart duration within audio length")

	# Test custom +50ms offset
	loader.set_calibration_offset_ms(50.0)
	var aligned_50 = loader.align_level(chart, audio)
	assert_eq(aligned_50["calibration_offset_ms"], 50.0, "Updated calibration offset is 50.0ms")
	assert_eq(aligned_50["calibration_offset_sec"], 0.050, "Updated calibration offset is 0.050s")

	# Test custom -30ms offset
	loader.set_calibration_offset_ms(-30.0)
	var aligned_neg = loader.align_level(chart, audio)
	assert_eq(aligned_neg["calibration_offset_ms"], -30.0, "Updated calibration offset is -30.0ms")
	assert_eq(aligned_neg["calibration_offset_sec"], -0.030, "Updated calibration offset is -0.030s")

	loader.free()

func test_suite_7_highway_integration_and_playback() -> void:
	print("\n--- Test Suite 7: Full Highway & AudioPlayer Integration ---")
	var loader = LevelLoaderScript.new()
	var highway = HighwayScript.new()
	var note_renderer_script = load("res://scripts/note_renderer.gd")
	if note_renderer_script:
		var nr = note_renderer_script.new()
		nr.name = "NoteRenderer"
		highway.add_child(nr)
	var audio_player = AudioStreamPlayer.new()
	root.add_child(highway)
	root.add_child(audio_player)

	# 1. Load Piece 1 ("Ode to Joy")
	var level1 = loader.load_bundled_piece("piece_1_monophonic")
	assert_true(not level1.is_empty(), "Loaded bundled piece 1")
	var applied1 = loader.apply_to_game(level1, highway, audio_player)
	assert_true(applied1, "Applied piece 1 to Highway and AudioPlayer")
	assert_eq(highway.chart_notes.size(), 15, "Highway loaded exactly 15 notes for Piece 1")
	assert_true(audio_player.stream != null, "AudioPlayer has stream attached")

	# 2. Load Piece 2 ("Bach Minuet")
	var level2 = loader.load_bundled_piece("piece_2_harmony")
	assert_true(not level2.is_empty(), "Loaded bundled piece 2")
	loader.apply_to_game(level2, highway, audio_player)
	assert_eq(highway.chart_notes.size(), 16, "Highway loaded exactly 16 notes for Piece 2")

	# 3. Load Piece 3 ("Cadence & Triads")
	var level3 = loader.load_bundled_piece("piece_3_polyphonic")
	assert_true(not level3.is_empty(), "Loaded bundled piece 3")
	loader.apply_to_game(level3, highway, audio_player)
	assert_eq(highway.chart_notes.size(), 20, "Highway loaded exactly 20 notes for Piece 3")

	highway.free()
	audio_player.free()
	loader.free()

func test_suite_8_on_the_fly_omr_level_ingestion() -> void:
	print("\n--- Test Suite 8: On-The-Fly Sheet Music OMR Level Ingestion ---")
	var loader = LevelLoaderScript.new()
	var highway = HighwayScript.new()
	var note_renderer_script = load("res://scripts/note_renderer.gd")
	if note_renderer_script:
		var nr = note_renderer_script.new()
		nr.name = "NoteRenderer"
		highway.add_child(nr)
	var audio_player = AudioStreamPlayer.new()
	root.add_child(highway)
	root.add_child(audio_player)

	# Ingest score image directly into playable level via OMR
	var omr_level = loader.load_bundled_piece("piece_1_monophonic", true)
	assert_true(not omr_level.is_empty(), "On-the-fly OMR level loaded successfully")
	assert_true(omr_level.has("notes"), "OMR level contains notes array")
	assert_true(omr_level["notes"].size() >= 14, "OMR extracted >= 14 notes on Piece 1 (got %d)" % omr_level["notes"].size())

	var applied = loader.apply_to_game(omr_level, highway, audio_player)
	assert_true(applied, "Applied on-the-fly OMR level directly to highway and audio")
	assert_true(highway.chart_notes.size() >= 14, "Highway received notes from OMR ingestion")
	assert_true(audio_player.stream != null, "Accompaniment audio paired with OMR level")

	highway.free()
	audio_player.free()
	loader.free()
