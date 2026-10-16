# res://scripts/audio_capture.gd
class_name AudioCapture
extends Node

## AudioCapture manages real-time microphone input via Godot's AudioEffectCapture,
## calculates RMS amplitude, applies a configurable noise gate (-45 dB / 0.005 RMS),
## downmixes stereo to mono normalized [-1.0, 1.0] samples, and forwards them
## to an AudioPitchModel instance.

signal audio_chunk_captured(mono_samples: PackedFloat32Array, rms: float, is_gated: bool)
signal rms_level_updated(rms_linear: float, rms_db: float)
signal capture_started()
signal capture_stopped()

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

var _mic_player: AudioStreamPlayer = null

func _init() -> void:
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
		AudioServer.set_bus_send(record_bus_idx, &"") # Mute output to avoid feedback loop
	
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
		var mic_stream = AudioStreamMicrophone.new()
		_mic_player.stream = mic_stream
		add_child(_mic_player)

func start_capture() -> void:
	if is_capturing:
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
		
	var available: int = capture_effect.get_frames_available()
	if available < min_chunk_frames:
		return
		
	var stereo_buffer: PackedVector2Array = capture_effect.get_buffer(available)
	process_stereo_buffer(stereo_buffer)

## Processes stereo frames: downmixes to mono, computes RMS, applies noise gate, and forwards to pitch_model.
## Can also be called directly by headless tests to inject synthetic audio.
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
		
	var rms: float = sqrt(sum_squares / float(n_frames))
	current_rms = rms
	current_rms_db = 20.0 * log(rms) / log(10.0) if rms > 0.0000001 else -100.0
	is_currently_gated = (rms < rms_threshold)
	
	rms_level_updated.emit(current_rms, current_rms_db)
	
	var forward_samples: PackedFloat32Array = mono
	if is_currently_gated:
		if push_silence_when_gated:
			forward_samples = PackedFloat32Array()
			forward_samples.resize(n_frames)
			forward_samples.fill(0.0)
			if pitch_model != null and pitch_model.has_method("push_audio_samples"):
				pitch_model.push_audio_samples(forward_samples)
		else:
			forward_samples = PackedFloat32Array() # Gated without forwarding
	else:
		if pitch_model != null and pitch_model.has_method("push_audio_samples"):
			pitch_model.push_audio_samples(forward_samples)
			
	audio_chunk_captured.emit(forward_samples, current_rms, is_currently_gated)
	return forward_samples

## Directly inject mono samples (convenience method for tests)
func inject_mono_samples(mono_samples: PackedFloat32Array) -> PackedFloat32Array:
	var stereo = PackedVector2Array()
	stereo.resize(mono_samples.size())
	for i in range(mono_samples.size()):
		var v = mono_samples[i]
		stereo[i] = Vector2(v, v)
	return process_stereo_buffer(stereo)

func get_sample_rate() -> int:
	return int(AudioServer.get_mix_rate())
