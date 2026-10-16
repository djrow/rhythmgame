# res://scripts/inference/websocket_driver.gd
class_name WebSocketDriver
extends "res://scripts/inference/audio_pitch_model.gd"

## Real-time streaming WebSocket driver for Basic Pitch ONNX inference server.
## Streams audio PCM buffers from Godot to localhost (ws://127.0.0.1:8765)
## and receives detected polyphonic MIDI pitches and onsets.

@export var server_url: String = "ws://127.0.0.1:8765"
@export var auto_reconnect: bool = true
@export var reconnect_interval_sec: float = 2.0
@export var send_int16: bool = false # False = raw IEEE float32 mono, True = int16 PCM

var ws: WebSocketPeer = null
var is_connected: bool = false
var reconnect_timer: float = 0.0

var detected_pitches: Array[int] = []
var recent_onsets: Array[int] = []
var last_timestamp: float = 0.0
var confidence_map: Dictionary = {}

func _init(url: String = "ws://127.0.0.1:8765") -> void:
	server_url = url
	connect_to_server()

## Connects or reconnects to the WebSocket inference server.
func connect_to_server() -> Error:
	if ws == null:
		ws = WebSocketPeer.new()
	is_connected = false
	var err: Error = ws.connect_to_url(server_url)
	if err != OK:
		model_error.emit("Failed to initiate connection to %s (Error code: %d)" % [server_url, err])
	return err

## Disconnects from the WebSocket server cleanly.
func disconnect_from_server() -> void:
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.close(1000, "Clean client disconnect")
	is_connected = false

## Streams audio samples to the server.
func push_audio_samples(samples: PackedFloat32Array) -> void:
	poll()
	if samples.is_empty():
		return
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return

	if send_int16:
		var int16_bytes = PackedByteArray()
		int16_bytes.resize(samples.size() * 2)
		for i in range(samples.size()):
			var clamped: float = clampf(samples[i], -1.0, 1.0)
			var s16: int = int(round(clamped * 32767.0))
			int16_bytes.encode_s16(i * 2, s16)
		ws.put_packet(int16_bytes)
	else:
		# Native float32 binary packing
		var raw_bytes: PackedByteArray = samples.to_byte_array()
		ws.put_packet(raw_bytes)

## Polls the WebSocket connection, advances state, and processes incoming packets.
func poll() -> void:
	if ws == null:
		if auto_reconnect:
			connect_to_server()
		return

	ws.poll()
	var state = ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			if not is_connected:
				is_connected = true
				reconnect_timer = 0.0
				model_ready.emit()

			# Drain all available packets
			while ws.get_available_packet_count() > 0:
				var pkt: PackedByteArray = ws.get_packet()
				if ws.was_string_packet():
					_parse_json_response(pkt.get_string_from_utf8())
				else:
					_parse_binary_response(pkt)

		WebSocketPeer.STATE_CONNECTING:
			pass

		WebSocketPeer.STATE_CLOSING:
			pass

		WebSocketPeer.STATE_CLOSED:
			var was_active = is_connected
			is_connected = false
			if was_active:
				model_error.emit("WebSocket closed (Code: %d, Reason: %s)" % [ws.get_close_code(), ws.get_close_reason()])

## Parses JSON response from inference server.
## Expected schema: {"type":"pitches","pitches":[60,64,67],"onsets":[60],"timestamp":1.25,"confidence":{...}}
func _parse_json_response(json_text: String) -> void:
	var json = JSON.new()
	var err: Error = json.parse(json_text)
	if err != OK:
		model_error.emit("Failed to parse JSON response: %d" % err)
		return

	var data = json.data
	if not (data is Dictionary):
		return

	var msg_type: String = String(data.get("type", "pitches"))
	if msg_type == "pitches" or data.has("pitches"):
		var raw_pitches: Array = data.get("pitches", [])
		var new_pitches: Array[int] = []
		for p in raw_pitches:
			new_pitches.append(int(p))
		detected_pitches = new_pitches

		var raw_onsets: Array = data.get("onsets", [])
		var new_onsets: Array[int] = []
		for o in raw_onsets:
			new_onsets.append(int(o))
		recent_onsets = new_onsets

		last_timestamp = float(data.get("timestamp", 0.0))
		confidence_map = data.get("confidence", {})

		if not detected_pitches.is_empty():
			pitches_detected.emit(detected_pitches)
		if not recent_onsets.is_empty():
			onsets_detected.emit(recent_onsets)

## Parses compact binary response packet from inference server.
## Byte 0: count_pitches (N)
## Bytes 1..N: pitch numbers
## Byte N+1: count_onsets (M)
## Bytes N+2..N+1+M: onset numbers
func _parse_binary_response(pkt: PackedByteArray) -> void:
	if pkt.size() < 2:
		return

	var n_pitches: int = pkt[0]
	if pkt.size() < 1 + n_pitches + 1:
		return

	var new_pitches: Array[int] = []
	for i in range(n_pitches):
		new_pitches.append(int(pkt[1 + i]))
	detected_pitches = new_pitches

	var onset_offset: int = 1 + n_pitches
	var n_onsets: int = pkt[onset_offset]
	var new_onsets: Array[int] = []
	for j in range(n_onsets):
		if onset_offset + 1 + j < pkt.size():
			new_onsets.append(int(pkt[onset_offset + 1 + j]))
	recent_onsets = new_onsets

	if not detected_pitches.is_empty():
		pitches_detected.emit(detected_pitches)
	if not recent_onsets.is_empty():
		onsets_detected.emit(recent_onsets)

func get_detected_pitches() -> Array[int]:
	return detected_pitches

func get_recent_onsets(clear: bool = false) -> Array[int]:
	var copy: Array[int] = recent_onsets.duplicate()
	if clear:
		recent_onsets.clear()
	return copy

func pop_recent_onsets() -> Array[int]:
	return get_recent_onsets(true)

func is_model_ready() -> bool:
	return is_connected and ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func reset() -> void:
	detected_pitches.clear()
	recent_onsets.clear()
	confidence_map.clear()
