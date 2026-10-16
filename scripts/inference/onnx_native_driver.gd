class_name OnnxNativeDriver
extends RefCounted

const MODEL_PATH := "res://assets/models/nmp.onnx"
const MODEL_SAMPLE_RATE := 22050
const AUDIO_WINDOW_SAMPLES := 43844
const N_FRAMES := 172
const N_BINS := 88
const MIDI_OFFSET := 21
const FRAME_HOP_SEC := 256.0 / 22050.0 # ~0.01161s per frame
const SUMMARY_FLOATS := 352
const FULL_FLOATS := 352 + (N_FRAMES * N_BINS * 2) # 30,624 floats

var _native_callable: Callable
var _is_ready: bool = false
var _summary_template: PackedFloat32Array
var _full_template: PackedFloat32Array

func _init() -> void:
	_summary_template = PackedFloat32Array()
	_summary_template.resize(SUMMARY_FLOATS)
	_full_template = PackedFloat32Array()
	_full_template.resize(FULL_FLOATS)

func is_available() -> bool:
	return Engine.has_meta("onnx_pitch_native")

func is_ready() -> bool:
	return _is_ready

func initialize(model_path: String = MODEL_PATH) -> bool:
	if not Engine.has_meta("onnx_pitch_native"):
		return false
	var meta_val: Variant = Engine.get_meta("onnx_pitch_native")
	if typeof(meta_val) != TYPE_CALLABLE:
		return false
	_native_callable = meta_val

	var status_val: Variant = _native_callable.call(2)
	if typeof(status_val) == TYPE_INT and int(status_val) == 1:
		_is_ready = true
		return true

	if not FileAccess.file_exists(model_path):
		return false
	var model_bytes: PackedByteArray = FileAccess.get_file_as_bytes(model_path)
	if model_bytes.is_empty():
		return false

	var rc: Variant = _native_callable.call(0, model_bytes, model_bytes.size())
	_is_ready = (typeof(rc) == TYPE_INT and int(rc) == 1)
	return _is_ready

## Runs native ONNX Basic Pitch inference and returns live active pitches + 88-bin probabilities.
func transcribe_live_window(
	samples_22k: PackedFloat32Array,
	note_threshold: float = 0.45,
	use_full_window: bool = false
) -> Dictionary:
	if not _is_ready and not initialize():
		return {"ok": false, "active_pitches": [], "frame_probs": []}
	if samples_22k.is_empty():
		return {"ok": false, "active_pitches": [], "frame_probs": []}

	var res: Variant = _native_callable.call(
		1,
		samples_22k,
		samples_22k.size(),
		_summary_template,
		SUMMARY_FLOATS
	)
	if typeof(res) != TYPE_PACKED_FLOAT32_ARRAY:
		return {"ok": false, "active_pitches": [], "frame_probs": []}

	var out: PackedFloat32Array = res
	if out.size() < SUMMARY_FLOATS:
		return {"ok": false, "active_pitches": [], "frame_probs": []}

	var note_offset: int = 176 if use_full_window else 0
	var onset_offset: int = 264 if use_full_window else 88

	# If tail frames have very low energy (e.g. short test burst at start of buffer), fall back to full window
	if not use_full_window:
		var max_tail: float = 0.0
		var max_full: float = 0.0
		for b in range(N_BINS):
			if out[b] > max_tail:
				max_tail = out[b]
			if out[176 + b] > max_full:
				max_full = out[176 + b]
		if max_tail < note_threshold and max_full >= note_threshold:
			note_offset = 176
			onset_offset = 264

	var frame_probs: Array = []
	frame_probs.resize(N_BINS)
	var candidate_bins: Array[int] = []

	for b in range(N_BINS):
		var np: float = out[note_offset + b]
		var op: float = out[onset_offset + b]
		var combined: float = maxf(np, op * 0.85)
		frame_probs[b] = snappedf(np, 0.0001)
		var prev_np: float = out[note_offset + b - 1] if b > 0 else 0.0
		var next_np: float = out[note_offset + b + 1] if b + 1 < N_BINS else 0.0
		if combined >= note_threshold and np >= prev_np and np >= next_np:
			candidate_bins.append(b)

	# Sort candidates by descending note probability and keep top polyphonic voices
	candidate_bins.sort_custom(func(a: int, b: int) -> bool:
		return out[note_offset + a] > out[note_offset + b]
	)

	var active_pitches: Array[int] = []
	for b in candidate_bins:
		var midi_pitch: int = b + MIDI_OFFSET
		if midi_pitch < 36 or midi_pitch > 96:
			continue
		active_pitches.append(midi_pitch)
		if active_pitches.size() >= 6:
			break

	active_pitches.sort()
	return {
		"ok": true,
		"active_pitches": active_pitches,
		"frame_probs": frame_probs
	}

## Runs full [172, 88] matrix extraction identical to the Python Basic Pitch post-processor.
func transcribe_full_notes(
	samples_22k: PackedFloat32Array,
	note_threshold: float = 0.45,
	onset_threshold: float = 0.30,
	min_note_frames: int = 3
) -> Dictionary:
	if not _is_ready and not initialize():
		return {"ok": false, "notes": [], "active_pitches": [], "frame_probs": []}
	if samples_22k.is_empty():
		return {"ok": false, "notes": [], "active_pitches": [], "frame_probs": []}

	var res: Variant = _native_callable.call(
		1,
		samples_22k,
		samples_22k.size(),
		_full_template,
		FULL_FLOATS
	)
	if typeof(res) != TYPE_PACKED_FLOAT32_ARRAY:
		return {"ok": false, "notes": [], "active_pitches": [], "frame_probs": []}

	var out: PackedFloat32Array = res
	if out.size() < FULL_FLOATS:
		return transcribe_live_window(samples_22k, note_threshold, true)

	var notes_base: int = 352
	var onsets_base: int = 352 + (N_FRAMES * N_BINS)

	var notes_list: Array = []
	var active_set: Dictionary = {}

	for p in range(N_BINS):
		var midi_pitch: int = p + MIDI_OFFSET
		if midi_pitch < 36 or midi_pitch > 96:
			continue
		var in_note: bool = false
		var start_frame: int = 0
		var peak_conf: float = 0.0

		for f in range(N_FRAMES):
			var idx: int = f * N_BINS + p
			var n_prob: float = out[notes_base + idx]
			var o_prob: float = out[onsets_base + idx]
			var prev_p: float = out[notes_base + f * N_BINS + (p - 1)] if p > 0 else 0.0
			var next_p: float = out[notes_base + f * N_BINS + (p + 1)] if p + 1 < N_BINS else 0.0
			var is_spectral_peak: bool = (n_prob >= prev_p) and (n_prob >= next_p)

			if not in_note:
				if is_spectral_peak and (n_prob >= note_threshold or (o_prob >= onset_threshold and n_prob >= note_threshold * 0.7)):
					in_note = true
					start_frame = f
					peak_conf = n_prob
			else:
				if is_spectral_peak and n_prob >= note_threshold * 0.75:
					if o_prob >= onset_threshold and (f - start_frame) >= min_note_frames:
						notes_list.append({
							"pitch": midi_pitch,
							"onset_sec": snappedf(start_frame * FRAME_HOP_SEC, 0.0001),
							"duration_sec": snappedf((f - start_frame) * FRAME_HOP_SEC, 0.0001),
							"confidence": snappedf(peak_conf, 0.0001)
						})
						active_set[midi_pitch] = true
						start_frame = f
						peak_conf = n_prob
					else:
						peak_conf = maxf(peak_conf, n_prob)
				else:
					var dur_frames: int = f - start_frame
					if dur_frames >= min_note_frames:
						notes_list.append({
							"pitch": midi_pitch,
							"onset_sec": snappedf(start_frame * FRAME_HOP_SEC, 0.0001),
							"duration_sec": snappedf(dur_frames * FRAME_HOP_SEC, 0.0001),
							"confidence": snappedf(peak_conf, 0.0001)
						})
						active_set[midi_pitch] = true
					in_note = false

		if in_note and (N_FRAMES - start_frame) >= min_note_frames:
			notes_list.append({
				"pitch": midi_pitch,
				"onset_sec": snappedf(start_frame * FRAME_HOP_SEC, 0.0001),
				"duration_sec": snappedf((N_FRAMES - start_frame) * FRAME_HOP_SEC, 0.0001),
				"confidence": snappedf(peak_conf, 0.0001)
			})
			active_set[midi_pitch] = true

	var frame_probs: Array = []
	frame_probs.resize(N_BINS)
	for b in range(N_BINS):
		frame_probs[b] = snappedf(out[176 + b], 0.0001)

	var active_pitches: Array[int] = []
	for k in active_set.keys():
		active_pitches.append(int(k))
	active_pitches.sort()

	return {
		"ok": true,
		"notes": notes_list,
		"active_pitches": active_pitches,
		"frame_probs": frame_probs
	}
