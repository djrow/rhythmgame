class_name WebSocketDriver
extends "res://scripts/inference/audio_pitch_model.gd"

## Real-time streaming WebSocket driver for Basic Pitch ONNX inference server.
## Streams audio PCM buffers from Godot to localhost (ws://127.0.0.1:8765)
## and receives detected polyphonic MIDI pitches and onsets.
## Also supports an optional built-in NativePitchDetector fallback when offline or on Android.

const NativePitchDetectorScript = preload("res://scripts/inference/native_pitch_detector.gd")
const OnnxNativeDriverScript = preload("res://scripts/inference/onnx_native_driver.gd")

@export var server_url: String = "ws://127.0.0.1:8765"
@export var auto_reconnect: bool = true
@export var reconnect_interval_sec: float = 2.0
@export var send_int16: bool = false # False = raw IEEE float32 mono, True = int16 PCM
@export var enable_dsp_fallback: bool = false # Enabled by Main for live gameplay fallback
@export var min_send_samples: int = 0 # If > 0, batches samples before sending over WebSocket

var ws: WebSocketPeer = null
var is_connected: bool = false
var reconnect_timer: float = 0.0
var _reconnect_timer: float = 0.0
var _last_poll_msec: int = 0
var _config_sent: bool = false

var detected_pitches: Array[int] = []
var recent_onsets: Array[int] = []
var last_timestamp: float = 0.0
var confidence_map: Dictionary = {}
var last_latency_ms: float = 0.0
var inference_count: int = 0
var samples_sent: int = 0

var _tx_buffer: PackedFloat32Array = PackedFloat32Array()
var _dsp_fallback: RefCounted = null
var _onnx_native: RefCounted = null
var _onnx_ring_22k: PackedFloat32Array = PackedFloat32Array()
var _onnx_write_pos: int = 0
var _onnx_samples_since_eval: int = 0
var _onnx_worker_task_id: int = -1
var _onnx_pending_result: Dictionary = {}
var _onnx_mutex: Mutex = Mutex.new()

func _init(url: String = "ws://127.0.0.1:8765") -> void:
	server_url = url
	var sr: float = float(AudioServer.get_mix_rate())
	if sr <= 0.0:
		sr = 48000.0
	_dsp_fallback = NativePitchDetectorScript.new(sr)
	_onnx_ring_22k.resize(43844)
	_onnx_ring_22k.fill(0.0)
	var candidate_onnx = OnnxNativeDriverScript.new()
	if candidate_onnx.is_available() and candidate_onnx.initialize():
		_onnx_native = candidate_onnx
	connect_to_server()

func _append_resampled_22k(samples: PackedFloat32Array, sr: float) -> int:
	if samples.is_empty():
		return 0
	var ratio: float = sr / 22050.0
	if ratio <= 0.0:
		ratio = 48000.0 / 22050.0
	var out_count: int = int(floor(float(samples.size()) / ratio))
	if out_count <= 0:
		return 0
	var ring_size: int = _onnx_ring_22k.size()
	for i in range(out_count):
		var a: int = int(float(i) * ratio)
		var b: int = mini(maxi(int(float(i + 1) * ratio), a + 1), samples.size())
		var acc: float = 0.0
		for k in range(a, b):
			acc += samples[k]
		_onnx_ring_22k[_onnx_write_pos] = acc / float(b - a)
		_onnx_write_pos = (_onnx_write_pos + 1) % ring_size
	return out_count

func _get_ordered_22k_window() -> PackedFloat32Array:
	var ring_size: int = _onnx_ring_22k.size()
	var ordered := PackedFloat32Array()
	ordered.resize(ring_size)
	var idx: int = _onnx_write_pos
	for i in range(ring_size):
		ordered[i] = _onnx_ring_22k[idx]
		idx += 1
		if idx >= ring_size:
			idx = 0
	return ordered

func _run_onnx_worker(window_22k: PackedFloat32Array) -> void:
	if _onnx_native == null:
		return
	var t0: int = Time.get_ticks_usec()
	var res: Dictionary = _onnx_native.transcribe_live_window(window_22k, 0.35, false)
	var elapsed_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
	res["latency_ms"] = elapsed_ms
	_onnx_mutex.lock()
	_onnx_pending_result = res
	_onnx_mutex.unlock()

func _consume_onnx_worker_if_done() -> void:
	if _onnx_worker_task_id != -1 and WorkerThreadPool.is_task_completed(_onnx_worker_task_id):
		WorkerThreadPool.wait_for_task_completion(_onnx_worker_task_id)
		_onnx_worker_task_id = -1
		_onnx_mutex.lock()
		var res: Dictionary = _onnx_pending_result.duplicate(true)
		_onnx_pending_result.clear()
		_onnx_mutex.unlock()
		if bool(res.get("ok", false)):
			var onnx_pitches: Array = res.get("active_pitches", [])
			var frame_probs: Array = res.get("frame_probs", [])
			last_latency_ms = float(res.get("latency_ms", last_latency_ms))
			inference_count += 1
			if not onnx_pitches.is_empty():
				var merged: Array[int] = detected_pitches.duplicate()
				for p_var in onnx_pitches:
					var p: int = int(p_var)
					if not merged.has(p):
						merged.append(p)
					if not recent_onsets.has(p):
						recent_onsets.append(p)
					var bin_idx: int = p - 21
					if bin_idx >= 0 and bin_idx < frame_probs.size():
						confidence_map[str(p)] = float(frame_probs[bin_idx])
				merged.sort()
				detected_pitches = merged
				pitches_detected.emit(detected_pitches)
				if not recent_onsets.is_empty():
					onsets_detected.emit(recent_onsets)

## Connects or reconnects to the WebSocket inference server.
func connect_to_server() -> Error:
	ws = WebSocketPeer.new()
	is_connected = false
	_config_sent = false
	reconnect_timer = 0.0
	_reconnect_timer = 0.0
	var err: Error = ws.connect_to_url(server_url)
	if err != OK:
		model_error.emit("Failed to initiate connection to %s (Error code: %d)" % [server_url, err])
	return err

## Disconnects from the WebSocket server cleanly.
func disconnect_from_server() -> void:
	if _onnx_worker_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(_onnx_worker_task_id)
		_onnx_worker_task_id = -1
	if ws != null:
		if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			ws.close(1000, "Clean client disconnect")
	is_connected = false
	_config_sent = false

## Streams audio samples to the server (or built-in Native ONNX + DSP when standalone).
func push_audio_samples(samples: PackedFloat32Array) -> void:
	poll()
	if samples.is_empty():
		return

	samples_sent += samples.size()

	if ws != null and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not _config_sent:
			_send_handshake_config()
		if min_send_samples > 0:
			_tx_buffer.append_array(samples)
			if _tx_buffer.size() < min_send_samples:
				return
			_send_pcm_packet(_tx_buffer)
			_tx_buffer.clear()
		else:
			_send_pcm_packet(samples)
		return

	# Standalone on-device execution (Native ONNX Runtime nmp.onnx + low-latency DSP)
	if enable_dsp_fallback and _dsp_fallback != null:
		var sr: float = float(AudioServer.get_mix_rate())
		if sr <= 0.0:
			sr = 48000.0
		var prev_count: int = _dsp_fallback.inference_count
		_dsp_fallback.push_audio_samples(samples, sr)
		if _dsp_fallback.inference_count > prev_count:
			detected_pitches = _dsp_fallback.detected_pitches.duplicate()
			for o in _dsp_fallback.recent_onsets:
				if not recent_onsets.has(o):
					recent_onsets.append(o)
			_dsp_fallback.recent_onsets.clear()
			confidence_map = _dsp_fallback.confidence_map.duplicate()
			last_latency_ms = _dsp_fallback.last_latency_ms
			inference_count += 1
			if not detected_pitches.is_empty():
				pitches_detected.emit(detected_pitches)
			if not recent_onsets.is_empty():
				onsets_detected.emit(recent_onsets)

		if _onnx_native != null and _onnx_native.is_ready():
			_consume_onnx_worker_if_done()
			var added_22k: int = _append_resampled_22k(samples, sr)
			_onnx_samples_since_eval += added_22k
			if _onnx_worker_task_id == -1 and _onnx_samples_since_eval >= 4410:
				_onnx_samples_since_eval = 0
				var win_22k: PackedFloat32Array = _get_ordered_22k_window()
				_onnx_worker_task_id = WorkerThreadPool.add_task(_run_onnx_worker.bind(win_22k), false, "BasicPitchONNX")

func _send_handshake_config() -> void:
	if ws == null or ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var sr: int = int(AudioServer.get_mix_rate())
	if sr <= 0:
		sr = 48000
	var cfg_json: String = JSON.stringify({
		"cmd": "config",
		"sample_rate": sr,
		"pcm_format": "int16" if send_int16 else "float32",
		"response_format": "json"
	})
	ws.send_text(cfg_json)
	_config_sent = true

func _send_pcm_packet(samples: PackedFloat32Array) -> void:
	if send_int16:
		var int16_bytes := PackedByteArray()
		int16_bytes.resize(samples.size() * 2)
		for i in range(samples.size()):
			var v: float = samples[i]
			if is_nan(v) or is_inf(v):
				v = 0.0
			var clamped: float = clampf(v, -1.0, 1.0)
			var s16: int = int(round(clamped * 32767.0))
			int16_bytes.encode_s16(i * 2, s16)
		ws.put_packet(int16_bytes)
	else:
		var raw_bytes: PackedByteArray = samples.to_byte_array()
		ws.put_packet(raw_bytes)

## Polls the WebSocket connection, advances state, and processes incoming packets.
func poll(delta: float = -1.0) -> void:
	if enable_dsp_fallback and _onnx_native != null and _onnx_native.is_ready():
		_consume_onnx_worker_if_done()

	var now_msec: int = Time.get_ticks_msec()
	var dt: float = delta
	if dt < 0.0:
		if _last_poll_msec > 0:
			dt = float(now_msec - _last_poll_msec) / 1000.0
		else:
			dt = 0.0
	_last_poll_msec = now_msec

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
				_reconnect_timer = 0.0
				_send_handshake_config()
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
			_config_sent = false
			if was_active:
				model_error.emit("WebSocket closed (Code: %d, Reason: %s)" % [ws.get_close_code(), ws.get_close_reason()])
			if auto_reconnect:
				_reconnect_timer += dt
				reconnect_timer = _reconnect_timer
				if _reconnect_timer >= reconnect_interval_sec:
					_reconnect_timer = 0.0
					reconnect_timer = 0.0
					connect_to_server()

## Parses JSON response from inference server.
## Expected schema: {"type":"pitches","pitches":[60,64,67],"onsets":[60],"timestamp":1.25,"confidence":{...},"latency_ms":9.5}
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
		var raw_pitches = data.get("pitches", [])
		var new_pitches: Array[int] = []
		if raw_pitches is Array:
			for p in raw_pitches:
				new_pitches.append(int(p))
		detected_pitches = new_pitches

		var raw_onsets = data.get("onsets", [])
		var new_onsets: Array[int] = []
		if raw_onsets is Array:
			for o in raw_onsets:
				new_onsets.append(int(o))
		recent_onsets = new_onsets

		last_timestamp = float(data.get("timestamp", 0.0))
		if data.has("latency_ms"):
			last_latency_ms = float(data.get("latency_ms", 0.0))
		var raw_conf = data.get("confidence", {})
		if raw_conf is Dictionary:
			confidence_map = raw_conf

		inference_count += 1

		if not detected_pitches.is_empty():
			pitches_detected.emit(detected_pitches)
		if not recent_onsets.is_empty():
			onsets_detected.emit(recent_onsets)

## Parses compact binary response packet from inference server.
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

	inference_count += 1

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

func is_native_onnx_active() -> bool:
	return _onnx_native != null and _onnx_native.is_ready()

func get_status_summary() -> Dictionary:
	var ws_open: bool = is_model_ready()
	var native_onnx: bool = is_native_onnx_active() and enable_dsp_fallback
	var backend: String = "Disconnected"
	if ws_open:
		backend = "ONNX Basic Pitch (nmp.onnx)"
	elif native_onnx:
		backend = "ONNX Basic Pitch (Native On-Device)"
	elif enable_dsp_fallback:
		backend = "Native Polyphonic DSP (ONNX Standby)"
	return {
		"backend": backend,
		"is_connected": ws_open or native_onnx,
		"is_ready": ws_open or native_onnx or enable_dsp_fallback,
		"latency_ms": last_latency_ms,
		"inference_count": inference_count,
		"samples_sent": samples_sent,
		"pitches": detected_pitches,
		"confidence": confidence_map
	}

func reset() -> void:
	detected_pitches.clear()
	recent_onsets.clear()
	confidence_map.clear()
	_tx_buffer.clear()
	if _dsp_fallback != null:
		_dsp_fallback.reset()
	reconnect_timer = 0.0
	_reconnect_timer = 0.0
