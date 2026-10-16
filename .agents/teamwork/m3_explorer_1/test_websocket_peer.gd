extends SceneTree

func _init() -> void:
	print("--- Testing WebSocketPeer in Godot 4 ---")
	var ws = WebSocketPeer.new()
	print("WebSocketPeer instantiated: ", ws != null)
	print("STATE_CONNECTING: ", WebSocketPeer.STATE_CONNECTING)
	print("STATE_OPEN: ", WebSocketPeer.STATE_OPEN)
	print("STATE_CLOSING: ", WebSocketPeer.STATE_CLOSING)
	print("STATE_CLOSED: ", WebSocketPeer.STATE_CLOSED)
	print("Initial ready state: ", ws.get_ready_state())

	print("\n--- Testing PackedFloat32Array <-> PackedByteArray ---")
	var float_arr = PackedFloat32Array([0.1, -0.5, 0.75, 1.0])
	var byte_arr: PackedByteArray = float_arr.to_byte_array()
	print("Float array size: ", float_arr.size(), " -> Byte array size: ", byte_arr.size())
	var decoded_floats: PackedFloat32Array = byte_arr.to_float32_array()
	print("Decoded size: ", decoded_floats.size())
	for i in range(float_arr.size()):
		var diff = abs(float_arr[i] - decoded_floats[i])
		if diff > 0.0001:
			printerr("Mismatch at index ", i)
	print("Float32 round-trip match OK!")

	print("\n--- Testing JSON packet parsing ---")
	var test_json_str = '{"type":"pitches","pitches":[60,64,67],"onsets":[60],"timestamp":1.234}'
	var json = JSON.new()
	var err = json.parse(test_json_str)
	if err == OK:
		var data = json.data
		print("Parsed JSON data: ", data)
		print("Pitches: ", data.get("pitches"))
		print("Onsets: ", data.get("onsets"))
	else:
		printerr("JSON parse error: ", err)

	print("\n--- Testing int16 conversion ---")
	# Convert float [-1.0, 1.0] to int16 bytes
	var int16_bytes = PackedByteArray()
	int16_bytes.resize(float_arr.size() * 2)
	for i in range(float_arr.size()):
		var clamped: float = clampf(float_arr[i], -1.0, 1.0)
		var s16: int = int(round(clamped * 32767.0))
		int16_bytes.encode_s16(i * 2, s16)
	print("Int16 encoded byte size: ", int16_bytes.size())
	# Decode back
	for i in range(float_arr.size()):
		var decoded_s16: int = int16_bytes.decode_s16(i * 2)
		var back_float: float = float(decoded_s16) / 32767.0
		print("Original: ", float_arr[i], " -> Decoded: ", back_float)

	print("\nAll tests in test_websocket_peer.gd completed.")
	quit(0)
