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
