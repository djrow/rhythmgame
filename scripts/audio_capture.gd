class_name AudioCapture
extends Node

## AudioCapture manages real-time microphone input via Godot's AudioEffectCapture,
## supports enumerating and switching hardware microphone input devices,
## maintains a 512-sample rolling oscilloscope waveform buffer,
## calculates RMS amplitude, applies a configurable noise gate (-46 dB / 0.005 RMS),
## downmixes stereo to mono normalized [-1.0, 1.0] samples, and forwards them
## to an AudioPitchModel instance.

signal audio_chunk_captured(mono_samples: PackedFloat32Array, rms: float, is_gated: bool)
signal raw_waveform_updated(raw_samples: PackedFloat32Array, rms: float, rms_db: float, is_gated: bool)
signal rms_level_updated(rms_linear: float, rms_db: float)
signal input_device_changed(device_name: String)
signal capture_started()
signal capture_stopped()

const OSCILLOSCOPE_BUFFER_SIZE: int = 512

@export var record_bus_name: String = "Record"
@export var min_chunk_frames: int = 256 # Minimum frames to read per process tick
@export var rms_threshold: float = 0.005 # ~ -46 dB noise gate threshold
@export var push_silence_when_gated: bool = true # Advance model clock with zeros during silence
@export var auto_start: bool = true

var pitch_model: RefCounted = null # AudioPitchModel
var is_capturing: bool = false
var capture_effect: AudioEffectCapture = null
var record_bus_idx: int = -1

var current_rms: float = 0.0
var current_rms_db: float = -100.0
var is_currently_gated: bool = false
var total_frames_captured: int = 0

var latest_raw_samples: PackedFloat32Array = PackedFloat32Array()
var oscilloscope_ring_buffer: PackedFloat32Array = PackedFloat32Array()

var _mic_player: AudioStreamPlayer = null
var _synth_phase: float = 0.0

func _init() -> void:
	oscilloscope_ring_buffer.resize(OSCILLOSCOPE_BUFFER_SIZE)
	oscilloscope_ring_buffer.fill(0.0)
	_setup_bus_and_capture()

func _ready() -> void:
	if auto_start:
		start_capture()

func _setup_bus_and_capture() -> void:
	record_bus_idx = AudioServer.get_bus_index(record_bus_name)
	if record_bus_idx == -1:
		# Dynamically create Record bus if missing (e.g. in test harness)
		record_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(record_bus_idx)
		AudioServer.set_bus_name(record_bus_idx, record_bus_name)
		AudioServer.set_bus_send(record_bus_idx, &"") # Prevent feedback loop

	# Mute Record bus output so mic doesn't echo out of speakers (AudioEffectCapture runs pre-mute)
	# Never mute bus 0 (Master)
	if record_bus_idx > 0:
		AudioServer.set_bus_mute(record_bus_idx, true)

	# Locate or attach AudioEffectCapture
	var effect_count: int = AudioServer.get_bus_effect_count(record_bus_idx)
	for i in range(effect_count):
		var eff = AudioServer.get_bus_effect(record_bus_idx, i)
		if eff is AudioEffectCapture:
			capture_effect = eff
			break

	if capture_effect == null:
		capture_effect = AudioEffectCapture.new()
		capture_effect.buffer_length = 1.0
		AudioServer.add_bus_effect(record_bus_idx, capture_effect)

	# Ensure internal AudioStreamPlayer exists to drive microphone input
	if _mic_player == null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.name = "InternalMicPlayer"
		_mic_player.bus = record_bus_name
		var mic_stream := AudioStreamMicrophone.new()
		_mic_player.stream = mic_stream
		add_child(_mic_player)

## Returns the list of available hardware microphone input devices from AudioServer.
func get_input_devices() -> PackedStringArray:
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	if devices.is_empty():
		return PackedStringArray(["Default"])
	return devices

## Returns the currently active microphone input device name.
func get_current_input_device() -> String:
	var dev: String = AudioServer.input_device
	return dev if not dev.is_empty() else "Default"

## Switches the active hardware microphone input device and restarts the AudioStreamMicrophone stream.
func set_input_device(device_name: String) -> bool:
	if device_name.is_empty():
		return false
	var devices: PackedStringArray = AudioServer.get_input_device_list()
	if not devices.is_empty() and not devices.has(device_name) and device_name != "Default":
		return false

	AudioServer.input_device = device_name
	if _mic_player != null:
		var should_play: bool = _mic_player.playing or is_capturing
		if _mic_player.playing:
			_mic_player.stop()
		_mic_player.stream = AudioStreamMicrophone.new()
		if should_play and is_inside_tree():
			_mic_player.play()
	if capture_effect != null:
		capture_effect.clear_buffer()

	input_device_changed.emit(device_name)
	return true

func start_capture() -> void:
	if is_capturing:
		if is_inside_tree() and _mic_player and not _mic_player.playing:
			_mic_player.play()
		return
	if OS.get_name() == "Android":
		OS.request_permission("android.permission.RECORD_AUDIO")
	if is_inside_tree() and _mic_player and not _mic_player.playing:
		_mic_player.play()
	if capture_effect:
		capture_effect.clear_buffer()
	is_capturing = true
	capture_started.emit()

func stop_capture() -> void:
	if not is_capturing:
		return
	if _mic_player and _mic_player.playing:
		_mic_player.stop()
	is_capturing = false
	capture_stopped.emit()

func set_pitch_model(model: RefCounted) -> void:
	pitch_model = model

func _process(_delta: float) -> void:
	if not is_capturing or capture_effect == null:
		return

	# Ensure mic stream player is active once inside tree
	if is_inside_tree() and _mic_player != null and not _mic_player.playing:
		_mic_player.play()

	var available: int = capture_effect.get_frames_available()
	if available < min_chunk_frames:
		return

	var stereo_buffer: PackedVector2Array = capture_effect.get_buffer(available)
	process_stereo_buffer(stereo_buffer)

## Processes stereo frames: downmixes to mono, updates oscilloscope buffer,
## computes RMS, applies noise gate, and forwards to pitch_model.
func process_stereo_buffer(stereo_buffer: PackedVector2Array) -> PackedFloat32Array:
	var n_frames: int = stereo_buffer.size()
	if n_frames == 0:
		return PackedFloat32Array()

	var mono: PackedFloat32Array = PackedFloat32Array()
	mono.resize(n_frames)
	var sum_squares: float = 0.0

	for i in range(n_frames):
		var s: float = (stereo_buffer[i].x + stereo_buffer[i].y) * 0.5
		mono[i] = s
		sum_squares += s * s

	total_frames_captured += n_frames
	latest_raw_samples = mono
	_update_oscilloscope_buffer(mono)

	var rms: float = sqrt(sum_squares / float(n_frames))
	current_rms = rms
	current_rms_db = 20.0 * log(rms) / log(10.0) if rms > 0.0000001 else -100.0
	is_currently_gated = (rms < rms_threshold)

	rms_level_updated.emit(current_rms, current_rms_db)
	raw_waveform_updated.emit(mono, current_rms, current_rms_db, is_currently_gated)

	var forward_samples: PackedFloat32Array = mono
	if is_currently_gated:
		if push_silence_when_gated:
			forward_samples = PackedFloat32Array()
			forward_samples.resize(n_frames)
			forward_samples.fill(0.0)
			if pitch_model != null and pitch_model.has_method("push_audio_samples"):
				pitch_model.push_audio_samples(forward_samples)
		else:
			forward_samples = PackedFloat32Array()
	else:
		if pitch_model != null and pitch_model.has_method("push_audio_samples"):
			pitch_model.push_audio_samples(forward_samples)

	audio_chunk_captured.emit(forward_samples, current_rms, is_currently_gated)
	return forward_samples

func _update_oscilloscope_buffer(mono: PackedFloat32Array) -> void:
	var n: int = mono.size()
	if n == 0:
		return
	if oscilloscope_ring_buffer.size() != OSCILLOSCOPE_BUFFER_SIZE:
		oscilloscope_ring_buffer.resize(OSCILLOSCOPE_BUFFER_SIZE)
		oscilloscope_ring_buffer.fill(0.0)

	if n >= OSCILLOSCOPE_BUFFER_SIZE:
		var start_idx: int = n - OSCILLOSCOPE_BUFFER_SIZE
		for i in range(OSCILLOSCOPE_BUFFER_SIZE):
			var v: float = mono[start_idx + i]
			oscilloscope_ring_buffer[i] = 0.0 if (is_nan(v) or is_inf(v)) else clampf(v, -1.5, 1.5)
	else:
		var keep: int = OSCILLOSCOPE_BUFFER_SIZE - n
		for i in range(keep):
			oscilloscope_ring_buffer[i] = oscilloscope_ring_buffer[i + n]
		for i in range(n):
			var v: float = mono[i]
			oscilloscope_ring_buffer[keep + i] = 0.0 if (is_nan(v) or is_inf(v)) else clampf(v, -1.5, 1.5)

## Directly inject mono samples (convenience method for tests)
func inject_mono_samples(mono_samples: PackedFloat32Array) -> PackedFloat32Array:
	var stereo := PackedVector2Array()
	stereo.resize(mono_samples.size())
	for i in range(mono_samples.size()):
		var v: float = mono_samples[i]
		stereo[i] = Vector2(v, v)
	return process_stereo_buffer(stereo)

## Synthesizes and injects a polyphonic harmonic test chord into the audio capture pipeline
## so users can visually verify the oscilloscope, RMS meter, and pitch inference model on demand.
func inject_test_chord(midi_pitches: Array = [60, 64, 67], duration_frames: int = 2048, amplitude: float = 0.28) -> PackedFloat32Array:
	var sr: float = float(get_sample_rate())
	if sr <= 0.0:
		sr = 48000.0
	var mono := PackedFloat32Array()
	mono.resize(duration_frames)
	var n_voices: int = maxi(1, midi_pitches.size())
	var voice_amp: float = amplitude / float(n_voices)

	for i in range(duration_frames):
		var t: float = (_synth_phase + float(i)) / sr
		var sample_val: float = 0.0
		for p in midi_pitches:
			var freq: float = 440.0 * pow(2.0, float(int(p) - 69) / 12.0)
			# Fundamental + light 2nd harmonic for realistic instrument timbre
			sample_val += voice_amp * (0.80 * sin(TAU * freq * t) + 0.20 * sin(TAU * freq * 2.0 * t))
		mono[i] = sample_val

	_synth_phase = fmod(_synth_phase + float(duration_frames), sr * 10.0)
	return inject_mono_samples(mono)

func get_sample_rate() -> int:
	return int(AudioServer.get_mix_rate())
