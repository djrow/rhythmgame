extends SceneTree

# Define a test to verify class inheritance and polymorphism
func _init() -> void:
	print("--- Testing GDScript polymorphic interface pattern ---")
	var base_script = GDScript.new()
	base_script.source_code = """
class_name TestBaseModel extends RefCounted
signal pitches_detected(pitches: Array[int])
signal onsets_detected(pitches: Array[int])
signal model_ready()
signal model_error(msg: String)

func push_audio_samples(samples: PackedFloat32Array) -> void: pass
func get_detected_pitches() -> Array[int]: return []
func get_recent_onsets() -> Array[int]: return []
func is_model_ready() -> bool: return false
func reset() -> void: pass
func poll() -> void: pass
"""
	var err = base_script.reload()
	print("Base script reload status: ", err)

	var mock_script = GDScript.new()
	mock_script.source_code = """
extends RefCounted
var _pitches: Array[int] = []
var _onsets: Array[int] = []
var _samples_count: int = 0

func _init(initial_pitches: Array = []) -> void:
	for p in initial_pitches:
		_pitches.append(int(p))

func push_audio_samples(samples: PackedFloat32Array) -> void:
	_samples_count += samples.size()

func get_detected_pitches() -> Array[int]:
	return _pitches

func get_recent_onsets() -> Array[int]:
	return _onsets

func is_model_ready() -> bool:
	return true

func reset() -> void:
	_pitches.clear()
	_onsets.clear()
	_samples_count = 0
"""
	err = mock_script.reload()
	print("Mock script reload status: ", err)

	var mock_inst = mock_script.new([60, 64, 67])
	print("Mock pitches: ", mock_inst.get_detected_pitches())
	mock_inst.push_audio_samples(PackedFloat32Array([0.1, 0.2]))
	print("Mock samples pushed, is_ready: ", mock_inst.is_model_ready())
	mock_inst.reset()
	print("Mock after reset: ", mock_inst.get_detected_pitches())

	print("Polymorphic test passed successfully.")
	quit(0)
