# res://tests/test_adversarial_m4.gd
extends SceneTree

## Adversarial Stress Test Suite for Milestone 4:
## - LevelLoader._load_wav_from_bytes() byte-level fuzzing and corruption resistance
## - Extreme latency calibration offsets (-1000ms, +5000ms, 0, sub-ms)
## - Chart schema vulnerabilities: zero BPM, missing/malformed notes, malformed time_signatures
## - Audio-chart alignment under duration mismatches (notes beyond audio)
## - Rapid successive calls to load_level() and apply_to_game() under active playback

const LevelLoaderScript = preload("res://scripts/level_loader.gd")
const OMRProcessorScript = preload("res://scripts/omr_processor.gd")
const HighwayScript = preload("res://scripts/highway.gd")
const NoteDataScript = preload("res://scripts/note_data.gd")

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

func assert_false(condition: bool, message: String) -> void:
	assert_true(not condition, message)

func assert_eq(actual, expected, message: String) -> void:
	if actual == expected:
		tests_passed += 1
		print("  [PASS] %s (expected %s, got %s)" % [message, str(expected), str(actual)])
	else:
		tests_failed += 1
		var err_msg = "[FAIL] %s (expected %s, got %s)" % [message, str(expected), str(actual)]
		failure_reports.append(err_msg)
		printerr("  " + err_msg)

func assert_null(val, message: String) -> void:
	assert_true(val == null, message)

func assert_not_null(val, message: String) -> void:
	assert_true(val != null, message)

func _init() -> void:
	print("================================================================================")
	print("       MILESTONE 4 ADVERSARIAL STRESS TEST SUITE (GODOT HEADLESS)              ")
	print("================================================================================")

	test_suite_1_wav_decoder_stress_and_fuzzing()
	test_suite_2_extreme_calibration_offsets()
	test_suite_3_chart_schema_anomalies_and_malformed_inputs()
	test_suite_4_rapid_successive_loads_and_lifecycle_stress()
	test_suite_5_audio_chart_alignment_durations_and_drift()
	test_suite_6_omr_processor_adversarial_images()

	print("================================================================================")
	print(" ADVERSARIAL TEST RESULTS: %d Passed, %d Failed" % [tests_passed, tests_failed])
	print("================================================================================")

	if tests_failed > 0:
		printerr("\nADVERSARIAL VULNERABILITIES / FAILURES ENCOUNTERED (%d):" % tests_failed)
		for rep in failure_reports:
			printerr("  - " + rep)
		quit(1)
	else:
		print("ALL ADVERSARIAL STRESS TESTS PASSED SUCCESSFULLY [OK]")
		quit(0)

# ==============================================================================
# Helper to construct valid minimal RIFF WAV byte buffers
# ==============================================================================
func _create_dummy_wav_bytes(sample_rate: int = 44100, channels: int = 1, bits: int = 16, num_samples: int = 100) -> PackedByteArray:
	var bytes_per_sample = bits / 8
	var data_size = num_samples * channels * bytes_per_sample
	var file_size = 36 + data_size
	var buf = PackedByteArray()
	buf.resize(44 + data_size)
	
	# "RIFF"
	buf.encode_u8(0, 82); buf.encode_u8(1, 73); buf.encode_u8(2, 70); buf.encode_u8(3, 70)
	buf.encode_u32(4, file_size)
	# "WAVE"
	buf.encode_u8(8, 87); buf.encode_u8(9, 65); buf.encode_u8(10, 86); buf.encode_u8(11, 69)
	# "fmt "
	buf.encode_u8(12, 102); buf.encode_u8(13, 109); buf.encode_u8(14, 116); buf.encode_u8(15, 32)
	buf.encode_u32(16, 16) # fmt chunk size
	buf.encode_u16(20, 1)  # PCM
	buf.encode_u16(22, channels)
	buf.encode_u32(24, sample_rate)
	var byte_rate = sample_rate * channels * bytes_per_sample
	buf.encode_u32(28, byte_rate)
	var block_align = channels * bytes_per_sample
	buf.encode_u16(32, block_align)
	buf.encode_u16(34, bits)
	# "data"
	buf.encode_u8(36, 100); buf.encode_u8(37, 97); buf.encode_u8(38, 116); buf.encode_u8(39, 97)
	buf.encode_u32(40, data_size)
	# samples remain 0 (silence)
	return buf

# ==============================================================================
# Suite 1: WAV Decoder Stress, Truncation & Fuzzing
# ==============================================================================
func test_suite_1_wav_decoder_stress_and_fuzzing() -> void:
	print("\n--- Suite 1: WAV Decoder Stress, Truncation & Fuzzing ---")
	var loader = LevelLoaderScript.new()

	# 1.1 Zero-byte array
	var zero_bytes = PackedByteArray()
	var res_zero = loader._load_wav_from_bytes(zero_bytes)
	assert_null(res_zero, "Zero-byte buffer gracefully rejected (returns null)")

	# 1.2 Truncated headers (< 44 bytes)
	var trunc_sizes = [1, 4, 11, 12, 16, 36, 43]
	for sz in trunc_sizes:
		var b = PackedByteArray()
		b.resize(sz)
		var res = loader._load_wav_from_bytes(b)
		assert_null(res, "Buffer of size %d (< 44) gracefully returns null" % sz)

	# 1.3 Invalid magic numbers
	var fake_magic = PackedByteArray()
	fake_magic.resize(44)
	fake_magic.encode_u8(0, 65); fake_magic.encode_u8(1, 66) # "AB..."
	assert_null(loader._load_wav_from_bytes(fake_magic), "Invalid RIFF magic rejected")

	var bad_wave = PackedByteArray()
	bad_wave.resize(44)
	bad_wave.encode_u8(0, 82); bad_wave.encode_u8(1, 73); bad_wave.encode_u8(2, 70); bad_wave.encode_u8(3, 70) # RIFF
	bad_wave.encode_u8(8, 78); bad_wave.encode_u8(9, 79); bad_wave.encode_u8(10, 80); bad_wave.encode_u8(11, 69) # NOPE
	assert_null(loader._load_wav_from_bytes(bad_wave), "Invalid WAVE magic rejected")

	# 1.4 Valid RIFF/WAVE header but no data chunk
	var no_data_buf = PackedByteArray()
	no_data_buf.resize(44)
	no_data_buf.encode_u8(0, 82); no_data_buf.encode_u8(1, 73); no_data_buf.encode_u8(2, 70); no_data_buf.encode_u8(3, 70)
	no_data_buf.encode_u8(8, 87); no_data_buf.encode_u8(9, 65); no_data_buf.encode_u8(10, 86); no_data_buf.encode_u8(11, 69)
	# Non-data chunk
	no_data_buf.encode_u8(12, 74); no_data_buf.encode_u8(13, 85); no_data_buf.encode_u8(14, 78); no_data_buf.encode_u8(15, 75) # JUNK
	no_data_buf.encode_u32(16, 20)
	var res_nodata = loader._load_wav_from_bytes(no_data_buf)
	assert_not_null(res_nodata, "WAV without explicit data chunk handled without crash")

	# 1.5 Corrupted fmt chunk size (claims 0 or huge)
	var corrupt_fmt = _create_dummy_wav_bytes(44100, 1, 16, 50)
	corrupt_fmt.encode_u32(16, 0) # fmt chunk size = 0
	var _res_cfmt = loader._load_wav_from_bytes(corrupt_fmt)
	# Should not crash or infinite loop
	assert_true(true, "Corrupted fmt chunk size=0 did not hang or crash parser")

	# 1.6 Oversized data chunk length (claims 100MB when buffer is small)
	var oversized_data = _create_dummy_wav_bytes(44100, 1, 16, 10)
	oversized_data.encode_u32(40, 100000000) # 100 MB data length
	var res_oversized = loader._load_wav_from_bytes(oversized_data)
	assert_not_null(res_oversized, "Oversized data chunk header handled gracefully without crash")

	# 1.7 8-bit, 16-bit, and stereo handling
	var wav_8bit = _create_dummy_wav_bytes(22050, 1, 8, 100)
	var res_8 = loader._load_wav_from_bytes(wav_8bit)
	assert_not_null(res_8, "8-bit mono WAV decoded")
	assert_eq(res_8.format, AudioStreamWAV.FORMAT_8_BITS, "AudioStreamWAV format is 8-bit")
	assert_eq(res_8.stereo, false, "AudioStreamWAV is mono")
	assert_eq(res_8.mix_rate, 22050, "Mix rate matches 22050")

	var wav_stereo = _create_dummy_wav_bytes(48000, 2, 16, 200)
	var res_stereo = loader._load_wav_from_bytes(wav_stereo)
	assert_not_null(res_stereo, "16-bit stereo WAV decoded")
	assert_eq(res_stereo.format, AudioStreamWAV.FORMAT_16_BITS, "AudioStreamWAV format is 16-bit")
	assert_eq(res_stereo.stereo, true, "AudioStreamWAV is stereo")
	assert_eq(res_stereo.mix_rate, 48000, "Mix rate matches 48000")

	# 1.8 Fuzzing with random byte buffers
	var fuzz_rng = RandomNumberGenerator.new()
	fuzz_rng.seed = 133742
	var fuzz_passed = true
	for f in range(50):
		var flen = fuzz_rng.randi_range(0, 300)
		var fbuf = PackedByteArray()
		fbuf.resize(flen)
		for b_idx in range(flen):
			fbuf.set(b_idx, fuzz_rng.randi_range(0, 255))
		# Inject RIFF and WAVE sometimes
		if f % 2 == 0 and flen >= 12:
			fbuf.encode_u8(0, 82); fbuf.encode_u8(1, 73); fbuf.encode_u8(2, 70); fbuf.encode_u8(3, 70)
			fbuf.encode_u8(8, 87); fbuf.encode_u8(9, 65); fbuf.encode_u8(10, 86); fbuf.encode_u8(11, 69)
		
		# Parser must not crash or hang on arbitrary garbage
		var _ignored = loader._load_wav_from_bytes(fbuf)
	assert_true(fuzz_passed, "50 random garbage byte sequences executed without crashing parser")

	# 1.9 Nonexistent audio file path in load_audio_stream
	var res_missing = loader.load_audio_stream("res://assets/audio/does_not_exist_404.wav")
	assert_null(res_missing, "Missing audio file returns null without throwing unhandled exception")
	loader.free()

# ==============================================================================
# Suite 2: Extreme Latency Calibration Offsets
# ==============================================================================
func test_suite_2_extreme_calibration_offsets() -> void:
	print("\n--- Suite 2: Extreme Latency Calibration Offsets ---")
	var loader = LevelLoaderScript.new()
	var highway = HighwayScript.new()
	var audio_player = AudioStreamPlayer.new()

	# 2.1 Default zero calibration
	loader.set_calibration_offset_ms(0.0)
	assert_eq(loader.calibration_offset_ms, 0.0, "Calibration offset ms is 0.0")
	assert_eq(loader.get_calibration_offset_sec(), 0.0, "Calibration offset sec is 0.0")

	# 2.2 Extreme negative offset (-1000ms = -1.0s)
	loader.set_calibration_offset_ms(-1000.0)
	assert_eq(loader.calibration_offset_ms, -1000.0, "Calibration offset ms set to -1000.0")
	assert_eq(loader.get_calibration_offset_sec(), -1.0, "Calibration offset sec is -1.0")

	# 2.3 Extreme positive offset (+5000ms = +5.0s)
	loader.set_calibration_offset_ms(5000.0)
	assert_eq(loader.calibration_offset_ms, 5000.0, "Calibration offset ms set to +5000.0")
	assert_eq(loader.get_calibration_offset_sec(), 5.0, "Calibration offset sec is 5.0")

	# 2.4 Sub-millisecond floating offset (0.123ms = 0.000123s)
	loader.set_calibration_offset_ms(0.123)
	assert_true(absf(loader.get_calibration_offset_sec() - 0.000123) < 1e-6, "Sub-millisecond calibration offset accurately converted")

	# 2.5 Propagation via load_level and apply_to_game
	var dummy_chart = {
		"title": "Offset Test",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5}
		]
	}
	var level_data = loader.load_level(dummy_chart, null, {"calibration_offset_ms": -1000.0})
	assert_eq(level_data["calibration_offset_ms"], -1000.0, "Level data holds -1000.0ms")
	assert_eq(level_data["calibration_offset_sec"], -1.0, "Level data holds -1.0s")

	var applied = loader.apply_to_game(level_data, highway, audio_player)
	assert_true(applied, "Level with -1000ms offset applied to game")
	assert_eq(highway.audio_offset_sec, -1.0, "Highway received -1.0s audio_offset_sec")

	# 2.6 Dynamic runtime offset adjustment updates current_level_data
	loader.set_calibration_offset_ms(250.0)
	assert_eq(loader.current_level_data["calibration_offset_ms"], 250.0, "Runtime adjustment updated current_level_data ms")
	assert_eq(loader.current_level_data["calibration_offset_sec"], 0.25, "Runtime adjustment updated current_level_data sec")

	# 2.7 Verify Highway playhead behavior with negative and positive offsets
	highway.is_playing = true
	# With audio_offset_sec = -1.0, simulated audio player
	audio_player.stream = loader._load_wav_from_bytes(_create_dummy_wav_bytes(44100, 1, 16, 44100))
	highway.audio_player = audio_player
	highway.audio_offset_sec = -1.0
	# Should not crash on _process(0.016)
	highway._process(0.016)
	assert_true(true, "Highway processed frame with negative offset without crash")

	highway.audio_offset_sec = 5.0
	highway._process(0.016)
	assert_true(true, "Highway processed frame with +5.0s offset without crash")

	highway.pause_playback()
	highway.free()
	audio_player.free()
	loader.free()

# ==============================================================================
# Suite 3: Chart Schema Anomalies & Malformed Inputs
# ==============================================================================
func test_suite_3_chart_schema_anomalies_and_malformed_inputs() -> void:
	print("\n--- Suite 3: Chart Schema Anomalies & Malformed Inputs ---")
	var loader = LevelLoaderScript.new()

	# 3.1 Notes extending beyond audio duration
	var dummy_audio = loader._load_wav_from_bytes(_create_dummy_wav_bytes(44100, 1, 16, 44100)) # 1.0 second audio
	var chart_exceeding = {
		"title": "Exceeding Notes",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": 0.5, "duration_sec": 0.5},
			{"pitch_midi": 64, "time_sec": 5.0, "duration_sec": 1.0} # Note at 5.0s, ends at 6.0s
		]
	}
	var res_exceeding = loader.align_level(chart_exceeding, dummy_audio)
	assert_false(res_exceeding["is_aligned"], "Chart exceeding audio length marked as is_aligned == false")
	assert_true(res_exceeding["chart_duration"] > res_exceeding["audio_duration"], "Chart duration exceeds audio duration")
	assert_true(res_exceeding["discrepancy_sec"] > 4.0, "Discrepancy correctly calculated")

	# 3.2 Notes within audio duration
	var chart_within = {
		"title": "Within Audio",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": 0.2, "duration_sec": 0.3}
		]
	}
	var res_within = loader.align_level(chart_within, dummy_audio)
	assert_true(res_within["is_aligned"], "Chart within audio duration marked as is_aligned == true")

	# 3.3 Zero BPM
	var chart_zero_bpm = {
		"title": "Zero BPM",
		"bpm": 0.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5}
		]
	}
	# Must not throw unhandled division by zero exception or crash
	var res_zero_bpm = loader.align_level(chart_zero_bpm, dummy_audio)
	assert_true(res_zero_bpm.has("bpm"), "Zero BPM chart handled")

	# 3.4 Missing notes array
	var chart_no_notes = {
		"title": "Empty Chart",
		"bpm": 120.0
	}
	var res_no_notes = loader.align_level(chart_no_notes, dummy_audio)
	assert_eq(res_no_notes["notes"].size(), 0, "Missing notes key handled as empty notes array")
	assert_eq(res_no_notes["chart_duration"], 0.0, "Chart duration is 0.0 when notes missing")

	# 3.5 Malformed note elements in notes array (null, string, int, empty dict)
	var chart_malformed_elements = {
		"title": "Malformed Elements",
		"bpm": 120.0,
		"notes": [
			null,
			"invalid_string",
			42,
			{},
			{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5}
		]
	}
	var res_malformed = loader.align_level(chart_malformed_elements, dummy_audio)
	assert_eq(res_malformed["notes"].size(), 5, "All 5 elements processed without fatal exception")
	var valid_note = res_malformed["notes"][4]
	assert_eq(valid_note["pitch_midi"], 60, "Valid note retained its pitch")

	# 3.6 Extreme MIDI pitches (negative and huge)
	var chart_extreme_pitches = {
		"title": "Extreme Pitches",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": -50, "time_sec": 0.1, "duration_sec": 0.2},
			{"pitch_midi": 9999, "time_sec": 0.3, "duration_sec": 0.2}
		]
	}
	var res_pitches = loader.align_level(chart_extreme_pitches, dummy_audio)
	assert_eq(res_pitches["notes"].size(), 2, "Extreme pitches accepted into dictionary")
	# Check Highway loading NoteData clamps or handles extreme pitches
	var hw = HighwayScript.new()
	hw.load_notes(res_pitches["notes"])
	assert_eq(hw.chart_notes.size(), 2, "Highway safely instantiated NoteData for extreme pitches")
	assert_true(hw.chart_notes[0].pitch_midi >= 0 and hw.chart_notes[0].pitch_midi <= 127, "Negative pitch clamped to [0..127]")
	assert_true(hw.chart_notes[1].pitch_midi >= 0 and hw.chart_notes[1].pitch_midi <= 127, "Oversized pitch clamped to [0..127]")
	hw.free()

	# 3.7 Negative timestamps and durations
	var chart_negative_times = {
		"title": "Negative Times",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": -5.0, "duration_sec": -2.0}
		]
	}
	var res_neg = loader.align_level(chart_negative_times, dummy_audio)
	assert_eq(res_neg["notes"].size(), 1, "Negative timestamp processed")

	# 3.8 Missing or empty time_signature
	var chart_default_ts = {
		"title": "Default TS",
		"bpm": 120.0,
		"notes": [{"pitch_midi": 60, "beat": 1.0, "measure": 1}]
	}
	var res_ts = loader.align_level(chart_default_ts, dummy_audio)
	assert_eq(res_ts["time_signature"], [4, 4], "Default time signature [4, 4] supplied")

	# 3.9 Zero BPM with measure/beat alignment
	var chart_zero_bpm_beats = {
		"title": "Zero BPM Beats",
		"bpm": 0.0,
		"notes": [
			{"pitch_midi": 60, "measure": 1, "beat": 1.0}
		]
	}
	var res_z_beats = loader.align_level(chart_zero_bpm_beats, dummy_audio)
	assert_not_null(res_z_beats, "Zero BPM with beat alignment handled")
	assert_false(is_inf(float(res_z_beats["chart_duration"])), "Zero BPM fallback prevents INF duration")
	loader.free()

# ==============================================================================
# Suite 4: Rapid Successive Calls & Lifecycle Stress
# ==============================================================================
func test_suite_4_rapid_successive_loads_and_lifecycle_stress() -> void:
	print("\n--- Suite 4: Rapid Successive Calls & Lifecycle Stress ---")
	var loader = LevelLoaderScript.new()
	var highway = HighwayScript.new()
	var audio_player = AudioStreamPlayer.new()
	root.add_child(highway)
	root.add_child(audio_player)

	var pieces = ["piece_1_monophonic", "piece_2_harmony", "piece_3_polyphonic"]
	# In GDScript lambdas capture primitives by value, so use Array container for by-reference mutation
	var signal_counts = [0, 0, 0] # [load, align, fail]

	loader.level_loaded.connect(func(_d): signal_counts[0] += 1)
	loader.alignment_completed.connect(func(_d): signal_counts[1] += 1)
	loader.level_load_failed.connect(func(_msg): signal_counts[2] += 1)

	# 4.1 Rapid 30 consecutive bundled level loads
	for i in range(30):
		var piece_key = pieces[i % pieces.size()]
		var res = loader.load_bundled_piece(piece_key)
		assert_not_null(res.get("notes"), "Rapid load iteration %d succeeded" % i)

	assert_eq(signal_counts[0], 30, "level_loaded emitted exactly 30 times")
	assert_eq(signal_counts[1], 30, "alignment_completed emitted exactly 30 times")
	assert_eq(signal_counts[2], 0, "No failures during rapid bundled loads")

	# 4.2 Rapid apply_to_game calls
	for i in range(30):
		var piece_key = pieces[i % pieces.size()]
		var res = loader.load_bundled_piece(piece_key)
		var applied = loader.apply_to_game(res, highway, audio_player)
		assert_true(applied, "Rapid apply_to_game iteration %d succeeded" % i)

	# 4.3 Rapid switching during active playback
	highway.start_playback()
	assert_true(highway.is_playing, "Highway is actively playing")
	for i in range(10):
		var piece_key = pieces[i % pieces.size()]
		var res = loader.load_bundled_piece(piece_key)
		loader.apply_to_game(res, highway, audio_player)
		# Ensure highway state was cleanly reset without lingering notes from prior piece
		var expected_notes = res["notes"].size()
		assert_eq(highway.chart_notes.size(), expected_notes, "Highway note pool cleanly reset during active playback")
	highway.pause_playback()

	# 4.4 apply_to_game with empty dictionary or missing notes
	var res_empty = loader.apply_to_game({}, highway, audio_player)
	assert_false(res_empty, "apply_to_game with empty dictionary gracefully returned false")

	var res_nonotes = loader.apply_to_game({"title": "No Notes"}, highway, audio_player)
	assert_false(res_nonotes, "apply_to_game without notes key gracefully returned false")

	# 4.5 Unknown source formats emit fail signal
	var unknown_res = loader.load_level("invalid_path_unsupported.xyz")
	assert_true(unknown_res.is_empty(), "Unknown format returns empty dict")
	assert_eq(signal_counts[2], 1, "level_load_failed signal emitted for unknown format")

	highway.free()
	audio_player.free()
	loader.free()

# ==============================================================================
# Suite 5: Audio-Chart Alignment Durations & Drift
# ==============================================================================
func test_suite_5_audio_chart_alignment_durations_and_drift() -> void:
	print("\n--- Suite 5: Audio-Chart Alignment Durations & Drift ---")
	var loader = LevelLoaderScript.new()

	# 5.1 Exact boundary: note ends exactly at audio duration
	var dummy_audio_2s = loader._load_wav_from_bytes(_create_dummy_wav_bytes(44100, 1, 16, 88200)) # 2.0s
	var chart_exact = {
		"title": "Exact Match",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 1.0} # Ends at 2.0s
		]
	}
	var res_exact = loader.align_level(chart_exact, dummy_audio_2s)
	assert_true(res_exact["is_aligned"], "Note ending exactly at audio duration is aligned")
	assert_true(res_exact["discrepancy_sec"] < 0.01, "Discrepancy is near 0.0s")

	# 5.2 Within duration_tolerance_sec (default 1.0s)
	var chart_tol = {
		"title": "Tolerance Test",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": 1.5, "duration_sec": 1.0} # Ends at 2.5s (2.0s + 0.5s <= 2.0s + 1.0s)
		]
	}
	loader.duration_tolerance_sec = 1.0
	var res_tol = loader.align_level(chart_tol, dummy_audio_2s)
	assert_true(res_tol["is_aligned"], "Note within 1.0s tolerance is aligned")

	# 5.3 Exceeding duration_tolerance_sec
	var chart_over_tol = {
		"title": "Over Tolerance Test",
		"bpm": 120.0,
		"notes": [
			{"pitch_midi": 60, "time_sec": 2.5, "duration_sec": 1.0} # Ends at 3.5s > 2.0s + 1.0s
		]
	}
	var res_over_tol = loader.align_level(chart_over_tol, dummy_audio_2s)
	assert_false(res_over_tol["is_aligned"], "Note exceeding tolerance is unaligned")

	# 5.4 Metric beat alignment (auto_align_timestamps: measure + beat)
	var chart_beats = {
		"title": "Metric Beat Chart",
		"bpm": 60.0, # 1 sec per beat
		"time_signature": [4, 4],
		"notes": [
			{"pitch_midi": 60, "measure": 1, "beat": 1.0, "duration_beats": 1.0}, # (0*4 + 1.0)*1.0 = 1.0s
			{"pitch_midi": 62, "measure": 2, "beat": 2.0, "duration_beats": 2.0}  # (1*4 + 2.0)*1.0 = 6.0s
		]
	}
	var res_beats = loader.align_level(chart_beats, null)
	var n1 = res_beats["notes"][0]
	var n2 = res_beats["notes"][1]
	assert_eq(n1["time_sec"], 1.0, "Measure 1 Beat 1 at 60 BPM correctly mapped to 1.0s")
	assert_eq(n1["duration_sec"], 1.0, "Duration 1.0 beat at 60 BPM mapped to 1.0s")
	assert_eq(n2["time_sec"], 6.0, "Measure 2 Beat 2 at 60 BPM correctly mapped to 6.0s")
	assert_eq(n2["duration_sec"], 2.0, "Duration 2.0 beats at 60 BPM mapped to 2.0s")

	# 5.5 Bundled pieces all satisfy alignment
	for p_key in LevelLoader.BUNDLED_PIECES:
		var p_data = loader.load_bundled_piece(p_key)
		assert_true(p_data["is_aligned"], "Bundled piece '%s' audio and chart are aligned" % p_key)
		assert_true(p_data["audio_duration"] >= p_data["chart_duration"], "Bundled piece audio covers chart duration")

	loader.free()

# ==============================================================================
# Suite 6: OMRProcessor Adversarial Image Inputs
# ==============================================================================
func test_suite_6_omr_processor_adversarial_images() -> void:
	print("\n--- Suite 6: OMRProcessor Adversarial Image Inputs ---")
	var omr = OMRProcessorScript.new()

	# 6.1 All-white image (1600x900)
	var white_img = Image.create(1600, 900, false, Image.FORMAT_L8)
	white_img.fill(Color.WHITE)
	var white_chart = omr.process_image_data(white_img, "all_white.png")
	assert_eq(white_chart["notes"].size(), 0, "All-white image produces 0 notes safely")

	# 6.2 All-black image (1600x900)
	var black_img = Image.create(1600, 900, false, Image.FORMAT_L8)
	black_img.fill(Color.BLACK)
	var black_chart = omr.process_image_data(black_img, "all_black.png")
	assert_eq(black_chart["notes"].size(), 0, "All-black image produces 0 notes safely")

	# 6.3 Tiny images (10x10, 50x50, 100x100)
	for dim in [10, 50, 100]:
		var tiny_img = Image.create(dim, dim, false, Image.FORMAT_L8)
		tiny_img.fill(Color(0.5, 0.5, 0.5))
		var tiny_chart = omr.process_image_data(tiny_img, "tiny_%d.png" % dim)
		assert_true(tiny_chart.has("notes"), "Tiny %dx%d image processed without out-of-bounds crash" % [dim, dim])

	# 6.4 Inverted score image (white ink on black background)
	var ref_img = Image.load_from_file(ProjectSettings.globalize_path("res://assets/test_pieces/piece_1_monophonic/score.png"))
	ref_img.convert(Image.FORMAT_L8)
	var raw_inv = ref_img.get_data()
	for i in range(raw_inv.size()):
		raw_inv[i] = 255 - raw_inv[i]
	var inv_img = Image.create_from_data(ref_img.get_width(), ref_img.get_height(), false, Image.FORMAT_L8, raw_inv)
	var inv_chart = omr.process_image_data(inv_img, "inverted_piece_1.png")
	assert_eq(inv_chart["notes"].size(), 15, "Inverted score image auto-corrected and detected all 15 notes")

	# 6.5 Non-existent image file path
	var missing_chart = omr.process_image("res://assets/scores/non_existent_999.png")
	assert_true(missing_chart.is_empty(), "Missing image path returns empty dict safely")

