# res://.agents/teamwork/m3_explorer_1/test_inference_architecture.gd
extends SceneTree

# Verification test script for AudioPitchModel, MockDriver, and WebSocketDriver

func _init() -> void:
	print("==================================================")
	print(" RUNNING INFERENCE ARCHITECTURE VERIFICATION")
	print("==================================================")

	var passed: int = 0
	var failed: int = 0

	# --- Test Suite 1: AudioPitchModel Base Interface ---
	print("\n--- Test Suite 1: AudioPitchModel Base Class Contract ---")
	var base_code = """
class_name TestAudioPitchModel extends RefCounted
signal pitches_detected(pitches: Array[int])
signal onsets_detected(pitches: Array[int])
signal model_ready()
signal model_error(error_message: String)

func push_audio_samples(_samples: PackedFloat32Array) -> void: pass
func get_detected_pitches() -> Array[int]: return []
func get_recent_onsets() -> Array[int]: return []
func is_model_ready() -> bool: return false
func reset() -> void: pass
func poll() -> void: pass
"""
	var base_script = GDScript.new()
	base_script.source_code = base_code
	var err = base_script.reload()
	if err == OK:
		var base_inst = base_script.new()
		if base_inst.get_detected_pitches() == [] and base_inst.is_model_ready() == false:
			print("  [PASS] Base model defaults verified")
			passed += 1
		else:
			printerr("  [FAIL] Base model defaults incorrect")
			failed += 1
	else:
		printerr("  [FAIL] Could not compile base_script: ", err)
		failed += 1

	# --- Test Suite 2: MockDriver Comprehensive Verification ---
	print("\n--- Test Suite 2: MockDriver Contract and Dynamics ---")
	var mock_code = """
extends RefCounted

signal pitches_detected(pitches: Array[int])
signal onsets_detected(pitches: Array[int])
signal model_ready()
signal model_error(error_message: String)

var _active_pitches: Array[int] = []
var _recent_onsets: Array[int] = []
var _samples_processed: int = 0
var _chart_notes: Array = []
var _is_chart_mode: bool = false
var _onset_window_sec: float = 0.050

func _init(initial_pitches: Array = []) -> void:
	if not initial_pitches.is_empty():
		set_detected_pitches(initial_pitches)

func set_detected_pitches(pitches: Array) -> void:
	_active_pitches.clear()
	for p in pitches:
		_active_pitches.append(int(p))
	pitches_detected.emit(_active_pitches)

func set_recent_onsets(onsets: Array) -> void:
	_recent_onsets.clear()
	for o in onsets:
		_recent_onsets.append(int(o))
	onsets_detected.emit(_recent_onsets)

func load_chart(notes: Array) -> void:
	_chart_notes = notes.duplicate(true)
	_is_chart_mode = true

func update_playback_time(current_time: float) -> void:
	if not _is_chart_mode:
		return
	
	var active_set: Array[int] = []
	var onset_set: Array[int] = []
	
	for n in _chart_notes:
		var pitch: int = int(n.get("pitch_midi", 0))
		var time_sec: float = float(n.get("time_sec", 0.0))
		var dur: float = float(n.get("duration_sec", 0.2))
		
		# Sustained note presence
		if current_time >= time_sec and current_time <= (time_sec + dur):
			if not active_set.has(pitch):
				active_set.append(pitch)
		
		# Onset window
		if absf(current_time - time_sec) <= _onset_window_sec:
			if not onset_set.has(pitch):
				onset_set.append(pitch)
				
	_active_pitches = active_set
	_recent_onsets = onset_set

func push_audio_samples(samples: PackedFloat32Array) -> void:
	_samples_processed += samples.size()

func get_detected_pitches() -> Array[int]:
	return _active_pitches

func get_recent_onsets() -> Array[int]:
	return _recent_onsets

func is_model_ready() -> bool:
	return true

func reset() -> void:
	_active_pitches.clear()
	_recent_onsets.clear()
	_samples_processed = 0
	_chart_notes.clear()
	_is_chart_mode = false

func poll() -> void:
	pass
"""
	var mock_script = GDScript.new()
	mock_script.source_code = mock_code
	err = mock_script.reload()
	if err == OK:
		# TC01: Initial pitches and queries
		var mock = mock_script.new([60, 64, 67])
		var pitches = mock.get_detected_pitches()
		if pitches == [60, 64, 67]:
			print("  [PASS] TC01: Mock initialized with chord [60, 64, 67]")
			passed += 1
		else:
			printerr("  [FAIL] TC01: Expected [60, 64, 67], got ", pitches)
			failed += 1

		# TC02: Push audio samples
		mock.push_audio_samples(PackedFloat32Array([0.1, -0.2, 0.5]))
		if mock._samples_processed == 3:
			print("  [PASS] TC02: Audio samples pushed and tracked")
			passed += 1
		else:
			printerr("  [FAIL] TC02: samples processed mismatch")
			failed += 1

		# TC03: Empty audio push (resilience)
		mock.push_audio_samples(PackedFloat32Array())
		if mock._samples_processed == 3:
			print("  [PASS] TC03: Empty audio push handled gracefully")
			passed += 1
		else:
			printerr("  [FAIL] TC03: Empty audio push failed")
			failed += 1

		# TC04: Signal emission on pitch update
		var signal_received: Array = []
		mock.pitches_detected.connect(func(p):
			signal_received.clear()
			signal_received.append_array(p)
		)
		mock.set_detected_pitches([72, 76])
		if signal_received == [72, 76] and mock.get_detected_pitches() == [72, 76]:
			print("  [PASS] TC04: pitches_detected signal emitted correctly")
			passed += 1
		else:
			printerr("  [FAIL] TC04: pitches_detected signal mismatch")
			failed += 1

		# TC05: Chart playback mode
		var test_chart = [
			{"pitch_midi": 60, "time_sec": 1.0, "duration_sec": 0.5},
			{"pitch_midi": 64, "time_sec": 1.0, "duration_sec": 0.5},
			{"pitch_midi": 67, "time_sec": 2.0, "duration_sec": 0.5}
		]
		mock.load_chart(test_chart)
		# At time 1.02s: chord [60, 64] should be active and onset
		mock.update_playback_time(1.02)
		var chart_pitches = mock.get_detected_pitches()
		var chart_onsets = mock.get_recent_onsets()
		if chart_pitches.has(60) and chart_pitches.has(64) and not chart_pitches.has(67):
			print("  [PASS] TC05: Chart playback active notes detected at 1.02s")
			passed += 1
		else:
			printerr("  [FAIL] TC05: Active notes mismatch: ", chart_pitches)
			failed += 1

		if chart_onsets.has(60) and chart_onsets.has(64):
			print("  [PASS] TC06: Chart playback onsets detected at 1.02s")
			passed += 1
		else:
			printerr("  [FAIL] TC06: Onset mismatch: ", chart_onsets)
			failed += 1

		# At time 2.0s: note 67 active, 60 & 64 gone
		mock.update_playback_time(2.0)
		if mock.get_detected_pitches() == [67]:
			print("  [PASS] TC07: Playback time advancement updates active pitches")
			passed += 1
		else:
			printerr("  [FAIL] TC07: Playback time advancement failed: ", mock.get_detected_pitches())
			failed += 1

		# TC08: Reset
		mock.reset()
		if mock.get_detected_pitches().is_empty() and mock._samples_processed == 0 and not mock._is_chart_mode:
			print("  [PASS] TC08: Mock reset cleared all state")
			passed += 1
		else:
			printerr("  [FAIL] TC08: Mock reset failed")
			failed += 1
	else:
		printerr("  [FAIL] Mock compilation failed: ", err)
		failed += 1

	# --- Test Suite 3: WebSocketDriver Protocol & Parsing ---
	print("\n--- Test Suite 3: WebSocketDriver Protocol & Response Parsing ---")
	var ws_driver_code = """
extends RefCounted

signal pitches_detected(pitches: Array[int])
signal onsets_detected(pitches: Array[int])
signal model_ready()
signal model_error(error_message: String)

var server_url: String = "ws://127.0.0.1:8765"
var auto_reconnect: bool = true
var is_connected: bool = false
var detected_pitches: Array[int] = []
var recent_onsets: Array[int] = []
var last_timestamp: float = 0.0
var confidence_map: Dictionary = {}

var ws: WebSocketPeer = null

func _init(url: String = "ws://127.0.0.1:8765") -> void:
	server_url = url
	ws = WebSocketPeer.new()

func connect_to_server() -> Error:
	if ws == null:
		ws = WebSocketPeer.new()
	return ws.connect_to_url(server_url)

func disconnect_from_server() -> void:
	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.close()
	is_connected = false

func push_audio_samples(samples: PackedFloat32Array) -> void:
	poll()
	if samples.is_empty():
		return
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var raw_bytes: PackedByteArray = samples.to_byte_array()
	ws.put_packet(raw_bytes)

func poll() -> void:
	if ws == null:
		return
	ws.poll()
	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			model_ready.emit()
		while ws.get_available_packet_count() > 0:
			var pkt: PackedByteArray = ws.get_packet()
			if ws.was_string_packet():
				_parse_json_response(pkt.get_string_from_utf8())
			else:
				_parse_binary_response(pkt)
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			model_error.emit("WebSocket closed")

func _parse_json_response(json_text: String) -> void:
	var json = JSON.new()
	var err = json.parse(json_text)
	if err != OK:
		model_error.emit("JSON parse error: %d" % err)
		return
	var data = json.data
	if not (data is Dictionary):
		return
	
	var msg_type = data.get("type", "pitches")
	if msg_type == "pitches" or data.has("pitches"):
		detected_pitches.clear()
		for p in data.get("pitches", []):
			detected_pitches.append(int(p))
		
		recent_onsets.clear()
		for o in data.get("onsets", []):
			recent_onsets.append(int(o))
			
		last_timestamp = float(data.get("timestamp", 0.0))
		
		if not detected_pitches.is_empty():
			pitches_detected.emit(detected_pitches)
		if not recent_onsets.is_empty():
			onsets_detected.emit(recent_onsets)

func _parse_binary_response(pkt: PackedByteArray) -> void:
	# Compact binary format:
	# Byte 0: count_pitches (N)
	# Bytes 1..N: pitches
	# Byte N+1: count_onsets (M)
	# Bytes N+2..N+1+M: onsets
	if pkt.size() < 2:
		return
	var n_pitches: int = pkt[0]
	if pkt.size() < 1 + n_pitches + 1:
		return
	detected_pitches.clear()
	for i in range(n_pitches):
		detected_pitches.append(pkt[1 + i])
		
	var onset_offset: int = 1 + n_pitches
	var n_onsets: int = pkt[onset_offset]
	recent_onsets.clear()
	for j in range(n_onsets):
		if onset_offset + 1 + j < pkt.size():
			recent_onsets.append(pkt[onset_offset + 1 + j])
			
	if not detected_pitches.is_empty():
		pitches_detected.emit(detected_pitches)
	if not recent_onsets.is_empty():
		onsets_detected.emit(recent_onsets)

func get_detected_pitches() -> Array[int]:
	return detected_pitches

func get_recent_onsets() -> Array[int]:
	return recent_onsets

func is_model_ready() -> bool:
	return is_connected and ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func reset() -> void:
	detected_pitches.clear()
	recent_onsets.clear()
	confidence_map.clear()
"""
	var ws_script = GDScript.new()
	ws_script.source_code = ws_driver_code
	err = ws_script.reload()
	if err == OK:
		var ws_driver = ws_script.new("ws://127.0.0.1:8765")
		# TC01: Initial ready state is false
		if not ws_driver.is_model_ready():
			print("  [PASS] TC09: WebSocket driver initial readiness is false")
			passed += 1
		else:
			printerr("  [FAIL] TC09: WebSocket ready state should be false")
			failed += 1

		# TC02: JSON response parsing simulation
		var simulated_json = '{"type":"pitches","pitches":[48,55,60,64],"onsets":[48,60],"timestamp":1.5}'
		var captured_pitches: Array = []
		var captured_onsets: Array = []
		ws_driver.pitches_detected.connect(func(p):
			captured_pitches.clear()
			captured_pitches.append_array(p)
		)
		ws_driver.onsets_detected.connect(func(o):
			captured_onsets.clear()
			captured_onsets.append_array(o)
		)
		ws_driver._parse_json_response(simulated_json)

		if ws_driver.get_detected_pitches() == [48, 55, 60, 64] and captured_pitches == [48, 55, 60, 64]:
			print("  [PASS] TC10: JSON pitch payload parsed to Array[int] correctly")
			passed += 1
		else:
			printerr("  [FAIL] TC10: JSON pitch parse failed: ", ws_driver.get_detected_pitches())
			failed += 1

		if ws_driver.get_recent_onsets() == [48, 60] and captured_onsets == [48, 60]:
			print("  [PASS] TC11: JSON onsets parsed to Array[int] correctly")
			passed += 1
		else:
			printerr("  [FAIL] TC11: JSON onset parse failed: ", ws_driver.get_recent_onsets())
			failed += 1

		# TC03: Binary response parsing simulation
		# 3 pitches (60, 64, 67), 1 onset (60)
		var bin_pkt = PackedByteArray([3, 60, 64, 67, 1, 60])
		ws_driver._parse_binary_response(bin_pkt)
		if ws_driver.get_detected_pitches() == [60, 64, 67] and ws_driver.get_recent_onsets() == [60]:
			print("  [PASS] TC12: Compact binary response packet parsed correctly")
			passed += 1
		else:
			printerr("  [FAIL] TC12: Binary parse failed: ", ws_driver.get_detected_pitches())
			failed += 1

		# TC04: Float32 conversion check
		var float_samples = PackedFloat32Array([0.5, -0.5, 0.25, -0.25])
		var bytes = float_samples.to_byte_array()
		if bytes.size() == 16:
			print("  [PASS] TC13: PackedFloat32Array converts to 16 binary bytes")
			passed += 1
		else:
			printerr("  [FAIL] TC13: Byte conversion size mismatch")
			failed += 1

		# TC05: Reset
		ws_driver.reset()
		if ws_driver.get_detected_pitches().is_empty() and ws_driver.get_recent_onsets().is_empty():
			print("  [PASS] TC14: Reset clears pitch and onset arrays")
			passed += 1
		else:
			printerr("  [FAIL] TC14: Reset failed")
			failed += 1
	else:
		printerr("  [FAIL] WebSocket script compilation failed: ", err)
		failed += 1

	# --- Test Suite 4: Integrated MockDriver + ScoringEngine Polyphonic Evaluation ---
	print("\n--- Test Suite 4: Integrated MockDriver + ScoringEngine Polyphony ---")
	var ScoringEngineScript = preload("res://scripts/scoring_engine.gd")
	var engine = ScoringEngineScript.new()
	var mock = mock_script.new()
	
	# Triad chord at 1.0s: C4(60), E4(64), G4(67)
	var active_notes = [
		{"pitch_midi": 60, "time_sec": 1.00, "is_hit": false},
		{"pitch_midi": 64, "time_sec": 1.00, "is_hit": false},
		{"pitch_midi": 67, "time_sec": 1.00, "is_hit": false}
	]
	
	# Driver detects chord
	mock.set_detected_pitches([60, 64, 67])
	mock.set_recent_onsets([60, 64, 67])
	
	var detected_onsets: Array[int] = mock.get_recent_onsets()
	var input_time: float = 1.015 # +15ms -> PERFECT
	var hit_count: int = 0
	for pitch in detected_onsets:
		var res = engine.process_input(input_time, pitch, active_notes)
		if not res.is_empty() and res.get("judgment") == "PERFECT":
			hit_count += 1
			
	if hit_count == 3 and active_notes[0]["is_hit"] and active_notes[1]["is_hit"] and active_notes[2]["is_hit"]:
		print("  [PASS] TC15: All 3 notes in chord evaluated and scored as PERFECT")
		passed += 1
	else:
		printerr("  [FAIL] TC15: Chord evaluation failed, hits: ", hit_count)
		failed += 1
		
	if engine.combo == 3 and engine.score == 300:
		print("  [PASS] TC16: Engine recorded combo 3 and score 300")
		passed += 1
	else:
		printerr("  [FAIL] TC16: Score/combo mismatch: score=%d, combo=%d" % [engine.score, engine.combo])
		failed += 1

	print("==================================================")
	print(" VERIFICATION RESULTS: %d Passed, %d Failed" % [passed, failed])
	print("==================================================")

	if failed == 0:
		print("INFERENCE ARCHITECTURE VERIFICATION SUCCESSFUL [OK]")
		quit(0)
	else:
		printerr("INFERENCE ARCHITECTURE VERIFICATION FAILED with %d errors" % failed)
		quit(1)
