# res://.agents/teamwork/m3_explorer_1/test_proposed_drivers.gd
extends SceneTree

func _init() -> void:
	print("==================================================")
	print(" VERIFYING PROPOSED INFERENCE GDSCIRPT SCRIPTS")
	print("==================================================")

	var passed: int = 0
	var failed: int = 0

	# 1. Load AudioPitchModel
	var ModelScript = load("res://.agents/teamwork/m3_explorer_1/proposed_audio_pitch_model.gd")
	if ModelScript:
		var base_inst = ModelScript.new()
		if base_inst.get_detected_pitches() == [] and not base_inst.is_model_ready():
			print("  [PASS] proposed_audio_pitch_model.gd loaded and verified")
			passed += 1
		else:
			printerr("  [FAIL] proposed_audio_pitch_model.gd default values mismatch")
			failed += 1
	else:
		printerr("  [FAIL] Could not load proposed_audio_pitch_model.gd")
		failed += 1

	# 2. Load MockDriver
	var MockScript = load("res://.agents/teamwork/m3_explorer_1/proposed_mock_driver.gd")
	if MockScript:
		var mock = MockScript.new([60, 64, 67])
		if mock.get_detected_pitches() == [60, 64, 67] and mock.is_model_ready():
			print("  [PASS] proposed_mock_driver.gd initialization verified")
			passed += 1
		else:
			printerr("  [FAIL] proposed_mock_driver.gd initialization mismatch")
			failed += 1

		# Test chart loading from real chart file
		var err = mock.load_chart_from_file("res://assets/charts/piece_1_monophonic.json")
		if err == OK:
			print("  [PASS] proposed_mock_driver.gd loaded piece_1_monophonic.json")
			passed += 1
			# At 0.05s, first note E4 (64) should be active
			mock.update_playback_time(0.05)
			if mock.get_detected_pitches() == [64] and mock.get_recent_onsets() == [64]:
				print("  [PASS] proposed_mock_driver.gd chart playback verified at 0.05s")
				passed += 1
			else:
				printerr("  [FAIL] Chart playback mismatch: pitches=", mock.get_detected_pitches(), " onsets=", mock.get_recent_onsets())
				failed += 1
		else:
			printerr("  [FAIL] load_chart_from_file failed with error: ", err)
			failed += 1
	else:
		printerr("  [FAIL] Could not load proposed_mock_driver.gd")
		failed += 1

	# 3. Load WebSocketDriver
	var WsScript = load("res://.agents/teamwork/m3_explorer_1/proposed_websocket_driver.gd")
	if WsScript:
		var ws_driver = WsScript.new("ws://127.0.0.1:8765")
		if not ws_driver.is_model_ready() and ws_driver.get_detected_pitches().is_empty():
			print("  [PASS] proposed_websocket_driver.gd loaded and verified")
			passed += 1
		else:
			printerr("  [FAIL] proposed_websocket_driver.gd defaults mismatch")
			failed += 1

		# Test parsing simulated JSON payload
		var sim_json = '{"type":"pitches","pitches":[60,67],"onsets":[60],"timestamp":2.5}'
		ws_driver._parse_json_response(sim_json)
		if ws_driver.get_detected_pitches() == [60, 67] and ws_driver.get_recent_onsets() == [60]:
			print("  [PASS] proposed_websocket_driver.gd parsed JSON pitches and onsets")
			passed += 1
		else:
			printerr("  [FAIL] JSON parsing mismatch: ", ws_driver.get_detected_pitches())
			failed += 1

		# Test parsing binary payload: 2 pitches (60, 67), 1 onset (60)
		var sim_bin = PackedByteArray([2, 60, 67, 1, 60])
		ws_driver._parse_binary_response(sim_bin)
		if ws_driver.get_detected_pitches() == [60, 67] and ws_driver.get_recent_onsets() == [60]:
			print("  [PASS] proposed_websocket_driver.gd parsed binary response packet")
			passed += 1
		else:
			printerr("  [FAIL] Binary parsing mismatch: ", ws_driver.get_detected_pitches())
			failed += 1
	else:
		printerr("  [FAIL] Could not load proposed_websocket_driver.gd")
		failed += 1

	print("==================================================")
	print(" VERIFICATION: %d Passed, %d Failed" % [passed, failed])
	print("==================================================")
	if failed == 0:
		print("ALL PROPOSED SCRIPTS VALIDATED SUCCESSFULLY [OK]")
		quit(0)
	else:
		quit(1)
