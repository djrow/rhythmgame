# Comprehensive Technical Report: Modular Audio Inference Architecture in Godot 4

**Agent**: `m3_explorer_1`  
**Milestone**: Milestone 3 — Basic Pitch ONNX & Audio Inference  
**Date**: 2026-10-16  
**Project**: MicGame-3 Grand Staff Rhythm Game  
**Target Files**:
- `res://scripts/inference/audio_pitch_model.gd`
- `res://scripts/inference/websocket_driver.gd`
- `res://scripts/inference/mock_driver.gd`

---

## 1. Executive Summary

Milestone 3 requires a modular, pluggable audio inference architecture decoupling the Godot 4 game loop from machine learning model execution. This report specifies the exact GDScript architecture and verified implementations for:
1. **Base Interface (`res://scripts/inference/audio_pitch_model.gd`)**: An abstract `RefCounted` interface defining signals (`pitches_detected`, `onsets_detected`, `model_ready`, `model_error`) and polymorphic methods (`push_audio_samples`, `get_detected_pitches`, `get_recent_onsets`, `pop_recent_onsets`, `is_model_ready`, `reset`, `poll`).
2. **Streaming WebSocket Driver (`res://scripts/inference/websocket_driver.gd`)**: A high-performance real-time driver using Godot 4's built-in `WebSocketPeer`. Streams mono audio chunks as native little-endian IEEE float32 (`PackedFloat32Array.to_byte_array()`) to `ws://127.0.0.1:8765`, and parses both text JSON and compact binary responses into typed `Array[int]` MIDI pitches and onsets.
3. **Mock / Offline Driver (`res://scripts/inference/mock_driver.gd`)**: A deterministic model runner for headless CI and playtesting. Supports programmatic note/onset feeds (`set_detected_pitches`, `set_recent_onsets`) and automated chart-driven playback (`load_chart_from_file`, `update_playback_time`) that synchronizes detected notes to playhead time without requiring a microphone or external server.

All classes and edge cases were verified with a 17-test headless verification suite (`test_inference_architecture.gd`), achieving 100% pass under Godot 4.7.2.

---

## 2. Requirements & Interface Contracts

### 2.1 Authoritative Specifications Mapping
| Requirement | Specification Source | Architecture Fulfillment |
|---|---|---|
| **Modular Neural Net Interface** | `ORIGINAL_REQUEST.md §R2` | `AudioPitchModel` base class allows hot-swapping between `WebSocketDriver`, `MockDriver`, and future pretrained instrument / stem separation models. |
| **Streaming WebSocket Audio Driver** | Dispatch & `PROJECT.md §F9` | `WebSocketDriver` connects to `ws://127.0.0.1:8765`, streams binary PCM chunks, drains packets on `poll()`. |
| **Polyphonic Pitch & Onset Extraction** | `PROJECT.md §F10` | Outputs active sustained pitches `[21..108]` and instantaneous onset attacks. |
| **Deterministic Headless Testing** | `ORIGINAL_REQUEST.md §R4` | `MockDriver` simulates live pitch feeds programmatically or driven by ground truth charts. |
| **E2E Contract Compliance** | `tests/e2e/test_tier1_features.py §F09`, `test_tier2_boundaries.py` | Strictly adheres to method signatures, empty buffer handling, type safety, and error resilience. |

### 2.2 Base Interface Method Signatures (`AudioPitchModel`)
```gdscript
class_name AudioPitchModel
extends RefCounted

signal pitches_detected(pitches: Array[int])
signal onsets_detected(pitches: Array[int])
signal model_ready()
signal model_error(error_message: String)

func push_audio_samples(samples: PackedFloat32Array) -> void: pass
func get_detected_pitches() -> Array[int]: return []
func get_recent_onsets(clear: bool = false) -> Array[int]: return []
func pop_recent_onsets() -> Array[int]: return get_recent_onsets(true)
func is_model_ready() -> bool: return false
func reset() -> void: pass
func poll() -> void: pass
```

---

## 3. WebSocket Streaming Protocol Specification

The protocol between `WebSocketDriver` (`websocket_driver.gd`) and `InferenceServer` (`python/inference_server.py`) operates over standard WebSocket full-duplex framing on `ws://127.0.0.1:8765`:

```
+---------------------------------------------------------------------------------+
|                                GODOT 4 CLIENT                                   |
|                                                                                 |
|  [AudioCapture] ---> mono float32 ---> [WebSocketDriver]                        |
|                                             |                                   |
|                                    (ws.put_packet)                              |
|                                             |                                   |
|                                    Binary Float32 PCM                           |
|                                   [4 bytes per sample]                          |
|                                             v                                   |
|                               ws://127.0.0.1:8765                               |
|                                             |                                   |
|                                             v                                   |
|                             +-------------------------------+                   |
|                             |   PYTHON INFERENCE SERVER     |                   |
|                             | - np.frombuffer(dtype=float32)|                   |
|                             | - np.interp (resample 22050)  |                   |
|                             | - Basic Pitch nmp.onnx        |                   |
|                             | - Peak picking & thresholds   |                   |
|                             +---------------+---------------+                   |
|                                             |                                   |
|                                    JSON / Binary Payload                        |
|                                             |                                   |
|                                             v                                   |
|  [ScoringEngine / Highway] <--- Array[int] -+                                   |
+---------------------------------------------------------------------------------+
```

### 3.1 Upstream Audio Streaming (Godot $\to$ Python)
1. **Sample Encoding**:
   - `PackedFloat32Array.to_byte_array()` produces native IEEE 754 32-bit floating point little-endian bytes.
   - 1024 mono samples = 4,096 bytes.
   - Optional 16-bit PCM integer mode (`send_int16 = true`): 2 bytes per sample via `encode_s16`.
2. **Transmission**:
   - Sent via `ws.put_packet(raw_bytes)`.
   - Polled every frame in `_process(delta)` or on push.

### 3.2 Downstream Inference Results (Python $\to$ Godot)
`WebSocketDriver` supports both text JSON and compact binary:

#### Mode A: JSON Format (Default & Human-Readable)
```json
{
  "type": "pitches",
  "pitches": [48, 55, 60, 64],
  "onsets": [48, 60],
  "timestamp": 1.250,
  "confidence": {
    "48": 0.731,
    "55": 0.735,
    "60": 0.755,
    "64": 0.684
  },
  "latency_ms": 10.2
}
```

#### Mode B: Compact Binary Format (Ultra Low-Bandwidth)
- **Byte 0**: $N$ (number of active sustained pitches, $0 \le N \le 88$)
- **Bytes $1 \dots N$**: MIDI note numbers $[21 \dots 108]$
- **Byte $N+1$**: $M$ (number of recent onsets, $0 \le M \le 88$)
- **Bytes $N+2 \dots N+1+M$**: MIDI note numbers for onsets

---

## 4. Key Architectural Discoveries & Engine Nuances

During our hands-on investigation with Godot 4.7.2, several critical platform behaviors were uncovered and addressed:

1. **Godot Class Cache in Headless Mode**:
   - Godot indexes project scripts into `.godot/global_script_class_cache.cfg`.
   - In automated test runners or fresh checkouts where the Godot editor has not been launched to rebuild the cache, referencing `extends AudioPitchModel` can fail with `Could not find base class "AudioPitchModel"`.
   - **Solution**: In `websocket_driver.gd` and `mock_driver.gd`, using:
     ```gdscript
     class_name WebSocketDriver
     extends "res://scripts/inference/audio_pitch_model.gd"
     ```
     guarantees that inheritance always succeeds across all environments, regardless of class cache state.

2. **GDScript Lambda Closure Value Capture**:
   - In GDScript, lambdas capture outer scalar/array references by value. Reassigning `signal_array = p` inside a lambda only affects the closure copy.
   - For signal testing or event capture, mutating the existing array via `signal_array.clear(); signal_array.append_array(p)` is required.

3. **Onset Atomic Consumption (`pop_recent_onsets`)**:
   - Unlike sustained active pitches (which remain active as long as energy is sustained), note onsets represent discrete attack impulses.
   - If `get_recent_onsets()` is read without clearing, subsequent frames could trigger false duplicate hits.
   - Providing `pop_recent_onsets()` and `get_recent_onsets(clear: bool = false)` allows atomic consumption by the rhythm game scoring loop while maintaining idempotent inspection for debug HUDs.

4. **Integration with `AudioCapture` (`m3_explorer_3`)**:
   - `AudioCapture` feeds mono samples directly via `pitch_model.push_audio_samples(mono)`.
   - Noise gate attenuation in `AudioCapture` suppresses low ambient room noise ($< 0.005$ RMS / $-46$ dB) before reaching inference.

---

## 5. Verified Implementation Code

The complete proposed files have been created in `.agents/teamwork/m3_explorer_1/`:
- `proposed_audio_pitch_model.gd`
- `proposed_websocket_driver.gd`
- `proposed_mock_driver.gd`

### 5.1 `res://scripts/inference/audio_pitch_model.gd`
```gdscript
# res://scripts/inference/audio_pitch_model.gd
class_name AudioPitchModel
extends RefCounted

## Base class and interface for modular pitch detection models and drivers in MicGame-3.
## Decouples audio capture and game loop scoring from machine learning model runners.

## Emitted when active sustained pitches are detected or updated.
signal pitches_detected(pitches: Array[int])

## Emitted when new note onsets/attacks are detected.
signal onsets_detected(pitches: Array[int])

## Emitted when the inference backend is initialized, connected, and ready for audio.
signal model_ready()

## Emitted when a connection or inference backend error occurs.
signal model_error(error_message: String)

## Pushes mono audio samples normalized to [-1.0, 1.0].
## Concrete drivers queue or stream samples to the neural network or mock queue.
func push_audio_samples(_samples: PackedFloat32Array) -> void:
	pass

## Returns current active sustained MIDI note numbers in range [21..108].
## Must return an empty Array[int] if no pitches are detected (never null).
func get_detected_pitches() -> Array[int]:
	var empty: Array[int] = []
	return empty

## Returns recently triggered note onset/attack MIDI note numbers.
## If clear is true, clears internal onsets buffer after returning.
## Must return an empty Array[int] if no onsets are detected (never null).
func get_recent_onsets(_clear: bool = false) -> Array[int]:
	var empty: Array[int] = []
	return empty

## Convenience method to retrieve and consume recent onsets atomically.
func pop_recent_onsets() -> Array[int]:
	return get_recent_onsets(true)

## Returns whether the model runner is ready to accept audio input.
func is_model_ready() -> bool:
	return false

## Resets internal audio buffers, detected pitch states, and counters.
func reset() -> void:
	pass

## Periodic update method to service sockets, pump event loops, or update time.
func poll() -> void:
	pass
```

### 5.2 `res://scripts/inference/websocket_driver.gd`
```gdscript
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
```

### 5.3 `res://scripts/inference/mock_driver.gd`
```gdscript
# res://scripts/inference/mock_driver.gd
class_name MockDriver
extends "res://scripts/inference/audio_pitch_model.gd"

## Offline / Mock pitch model runner for deterministic headless testing,
## CI automation, and non-microphone playtesting.
## Supports both programmatic pitch feeds and automated chart-based playback.

var _active_pitches: Array[int] = []
var _recent_onsets: Array[int] = []
var _samples_processed: int = 0
var _chart_notes: Array = []
var _is_chart_mode: bool = false
var _onset_window_sec: float = 0.050

func _init(initial_pitches: Array = []) -> void:
	if not initial_pitches.is_empty():
		set_detected_pitches(initial_pitches)

## Programmatically feeds active sustained pitches.
func set_detected_pitches(pitches: Array) -> void:
	_active_pitches.clear()
	for p in pitches:
		_active_pitches.append(int(p))
	pitches_detected.emit(_active_pitches)

## Programmatically feeds recent note onsets.
func set_recent_onsets(onsets: Array) -> void:
	_recent_onsets.clear()
	for o in onsets:
		_recent_onsets.append(int(o))
	onsets_detected.emit(_recent_onsets)

## Loads chart notes to automatically simulate player input synchronized to playhead time.
func load_chart(notes: Array) -> void:
	_chart_notes = notes.duplicate(true)
	_is_chart_mode = true

## Loads chart notes directly from a JSON file path.
func load_chart_from_file(file_path: String) -> Error:
	if not FileAccess.file_exists(file_path):
		model_error.emit("Chart file not found: %s" % file_path)
		return ERR_FILE_NOT_FOUND
	var file = FileAccess.open(file_path, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.new()
	var err = json.parse(content)
	if err != OK:
		model_error.emit("Failed to parse chart JSON: %d" % err)
		return err
	var data = json.data
	if data is Dictionary and data.has("notes"):
		load_chart(data["notes"])
		return OK
	return ERR_INVALID_DATA

## Updates chart playback mode based on current song time.
## Populates _active_pitches with currently sustained notes and
## _recent_onsets with notes whose onset is within _onset_window_sec.
func update_playback_time(current_time: float) -> void:
	if not _is_chart_mode:
		return

	var active_set: Array[int] = []
	var onset_set: Array[int] = []

	for n in _chart_notes:
		var pitch: int = 0
		var time_sec: float = 0.0
		var dur: float = 0.2

		if n is Dictionary:
			pitch = int(n.get("pitch_midi", 0))
			time_sec = float(n.get("time_sec", 0.0))
			dur = float(n.get("duration_sec", 0.2))
		elif n is RefCounted and "pitch_midi" in n and "time_sec" in n:
			pitch = n.pitch_midi
			time_sec = n.time_sec
			dur = n.duration_sec if "duration_sec" in n else 0.2

		# Sustained note duration check
		if current_time >= time_sec and current_time <= (time_sec + dur):
			if not active_set.has(pitch):
				active_set.append(pitch)

		# Attack / onset window check
		if absf(current_time - time_sec) <= _onset_window_sec:
			if not onset_set.has(pitch):
				onset_set.append(pitch)

	_active_pitches = active_set
	_recent_onsets = onset_set

	if not _active_pitches.is_empty():
		pitches_detected.emit(_active_pitches)
	if not _recent_onsets.is_empty():
		onsets_detected.emit(_recent_onsets)

## Accepts audio samples and tracks throughput.
func push_audio_samples(samples: PackedFloat32Array) -> void:
	_samples_processed += samples.size()

func get_detected_pitches() -> Array[int]:
	return _active_pitches

func get_recent_onsets(clear: bool = false) -> Array[int]:
	var copy: Array[int] = _recent_onsets.duplicate()
	if clear:
		_recent_onsets.clear()
	return copy

func pop_recent_onsets() -> Array[int]:
	return get_recent_onsets(true)

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
```

---

## 6. Verification and Validation Results

The architecture was tested across 17 test cases in `test_inference_architecture.gd`:

```
==================================================
 RUNNING INFERENCE ARCHITECTURE VERIFICATION
==================================================

--- Test Suite 1: AudioPitchModel Base Class Contract ---
  [PASS] Base model defaults verified

--- Test Suite 2: MockDriver Contract and Dynamics ---
  [PASS] TC01: Mock initialized with chord [60, 64, 67]
  [PASS] TC02: Audio samples pushed and tracked
  [PASS] TC03: Empty audio push handled gracefully
  [PASS] TC04: pitches_detected signal emitted correctly
  [PASS] TC05: Chart playback active notes detected at 1.02s
  [PASS] TC06: Chart playback onsets detected at 1.02s
  [PASS] TC07: Playback time advancement updates active pitches
  [PASS] TC08: Mock reset cleared all state

--- Test Suite 3: WebSocketDriver Protocol & Response Parsing ---
  [PASS] TC09: WebSocket driver initial readiness is false
  [PASS] TC10: JSON pitch payload parsed to Array[int] correctly
  [PASS] TC11: JSON onsets parsed to Array[int] correctly
  [PASS] TC12: Compact binary response packet parsed correctly
  [PASS] TC13: PackedFloat32Array converts to 16 binary bytes
  [PASS] TC14: Reset clears pitch and onset arrays

--- Test Suite 4: Integrated MockDriver + ScoringEngine Polyphony ---
  [PASS] TC15: All 3 notes in chord evaluated and scored as PERFECT
  [PASS] TC16: Engine recorded combo 3 and score 300
==================================================
 VERIFICATION RESULTS: 17 Passed, 0 Failed
==================================================
INFERENCE ARCHITECTURE VERIFICATION SUCCESSFUL [OK]
```

Verification command:
```powershell
& "C:\Users\david\Downloads\Godot_v4.7.2-stable_win64_console.exe" --headless -s res://.agents/teamwork/m3_explorer_1/test_inference_architecture.gd
```
Exit code: `0`.
