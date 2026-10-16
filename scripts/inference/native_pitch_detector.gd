class_name NativePitchDetector
extends RefCounted

## Real-time polyphonic spectral/harmonic pitch and onset detector in pure GDScript.
## Provides zero-latency in-engine polyphonic pitch detection on Android (Pixel 7a)
## and desktop whenever the external Python ONNX WebSocket server is offline or warming up.

const MIN_MIDI: int = 36 # C2 (~65.41 Hz)
const MAX_MIDI: int = 84 # C6 (~1046.50 Hz)
const WINDOW_SIZE: int = 2048

var sample_rate: float = 48000.0
var ring_buffer: PackedFloat32Array = PackedFloat32Array()
var _hann_window: PackedFloat32Array = PackedFloat32Array()
var _midi_freqs: PackedFloat32Array = PackedFloat32Array()
var _prev_energies: PackedFloat32Array = PackedFloat32Array()
var _last_onset_sec: Dictionary = {}

var detected_pitches: Array[int] = []
var recent_onsets: Array[int] = []
var confidence_map: Dictionary = {}
var last_latency_ms: float = 0.0
var inference_count: int = 0
var _samples_since_eval: int = 0
var eval_hop_samples: int = 1024 # ~21ms at 48kHz

func _init(sr: float = 48000.0) -> void:
	sample_rate = maxf(8000.0, sr)
	ring_buffer.resize(WINDOW_SIZE)
	ring_buffer.fill(0.0)
	_hann_window.resize(WINDOW_SIZE)
	for i in range(WINDOW_SIZE):
		_hann_window[i] = 0.5 * (1.0 - cos(TAU * float(i) / float(WINDOW_SIZE - 1)))

	var num_bins: int = MAX_MIDI - MIN_MIDI + 1
	_midi_freqs.resize(num_bins)
	_prev_energies.resize(num_bins)
	_prev_energies.fill(0.0)
	for b in range(num_bins):
		var midi: int = MIN_MIDI + b
		_midi_freqs[b] = 440.0 * pow(2.0, float(midi - 69) / 12.0)
		_last_onset_sec[midi] = -999.0

func reset() -> void:
	ring_buffer.fill(0.0)
	_prev_energies.fill(0.0)
	detected_pitches.clear()
	recent_onsets.clear()
	confidence_map.clear()
	_samples_since_eval = 0
	for k in _last_onset_sec.keys():
		_last_onset_sec[k] = -999.0

func push_audio_samples(samples: PackedFloat32Array, sr: float = -1.0) -> void:
	if sr > 0.0:
		sample_rate = sr
	var n: int = samples.size()
	if n == 0:
		return

	if n >= WINDOW_SIZE:
		for i in range(WINDOW_SIZE):
			var v: float = samples[n - WINDOW_SIZE + i]
			ring_buffer[i] = 0.0 if (is_nan(v) or is_inf(v)) else v
	else:
		var keep: int = WINDOW_SIZE - n
		for i in range(keep):
			ring_buffer[i] = ring_buffer[i + n]
		for i in range(n):
			var v: float = samples[i]
			ring_buffer[keep + i] = 0.0 if (is_nan(v) or is_inf(v)) else v

	_samples_since_eval += n
	if _samples_since_eval >= eval_hop_samples:
		_samples_since_eval = 0
		_evaluate_window()

func _evaluate_window() -> void:
	var t0: int = Time.get_ticks_usec()
	inference_count += 1

	# Compute RMS and peak of current window
	var sum_sq: float = 0.0
	var peak: float = 0.0
	for i in range(WINDOW_SIZE):
		var s: float = ring_buffer[i]
		sum_sq += s * s
		var a: float = absf(s)
		if a > peak:
			peak = a
	var rms: float = sqrt(sum_sq / float(WINDOW_SIZE))
	if rms < 0.004 or peak < 0.006:
		detected_pitches.clear()
		confidence_map.clear()
		_prev_energies.fill(0.0)
		last_latency_ms = float(Time.get_ticks_usec() - t0) / 1000.0
		return

	# Normalize windowed signal
	var inv_peak: float = 1.0 / maxf(peak, 0.01)
	var windowed: PackedFloat32Array = PackedFloat32Array()
	windowed.resize(WINDOW_SIZE)
	for i in range(WINDOW_SIZE):
		windowed[i] = ring_buffer[i] * inv_peak * _hann_window[i]

	# Goertzel spectral magnitude across MIDI 36..84 (downsampled 2x to 1024 points for <1.5ms CPU speed)
	var step: int = 2
	var eff_sr: float = sample_rate / float(step)
	var n_pts: int = WINDOW_SIZE / step
	var num_bins: int = MAX_MIDI - MIN_MIDI + 1
	var raw_mag: PackedFloat32Array = PackedFloat32Array()
	raw_mag.resize(num_bins)

	for b in range(num_bins):
		var freq: float = _midi_freqs[b]
		var omega: float = TAU * freq / eff_sr
		var coeff: float = 2.0 * cos(omega)
		var s1: float = 0.0
		var s2: float = 0.0
		var idx: int = 0
		for _k in range(n_pts):
			var s0: float = windowed[idx] + coeff * s1 - s2
			s2 = s1
			s1 = s0
			idx += step
		var power: float = s1 * s1 + s2 * s2 - coeff * s1 * s2
		raw_mag[b] = sqrt(maxf(0.0, power)) / float(n_pts)

	# Local spectral peak picking & octave harmonic suppression
	var max_mag: float = 0.0001
	for b in range(num_bins):
		if raw_mag[b] > max_mag:
			max_mag = raw_mag[b]

	var norm_mag: PackedFloat32Array = PackedFloat32Array()
	norm_mag.resize(num_bins)
	for b in range(num_bins):
		norm_mag[b] = raw_mag[b] / max_mag

	# Suppress 2nd/3rd harmonics (+12 and +19 semitones) if fundamental is strong
	var suppressed: PackedFloat32Array = norm_mag.duplicate()
	for b in range(num_bins):
		if norm_mag[b] >= 0.45:
			if b + 12 < num_bins:
				suppressed[b + 12] = maxf(0.0, suppressed[b + 12] - norm_mag[b] * 0.55)
			if b + 19 < num_bins:
				suppressed[b + 19] = maxf(0.0, suppressed[b + 19] - norm_mag[b] * 0.40)
			if b + 24 < num_bins:
				suppressed[b + 24] = maxf(0.0, suppressed[b + 24] - norm_mag[b] * 0.45)

	var new_pitches: Array[int] = []
	var new_conf: Dictionary = {}
	var now_sec: float = float(Time.get_ticks_msec()) / 1000.0

	# Collect local peaks above threshold (up to 4 concurrent polyphonic notes)
	var candidates: Array[Dictionary] = []
	for b in range(num_bins):
		var val: float = suppressed[b]
		if val < 0.42:
			continue
		var is_local_max: bool = true
		if b > 0 and suppressed[b - 1] > val:
			is_local_max = false
		if b < num_bins - 1 and suppressed[b + 1] >= val:
			is_local_max = false
		if is_local_max:
			candidates.append({"bin": b, "midi": MIN_MIDI + b, "conf": clampf(val, 0.0, 1.0)})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["conf"]) > float(b["conf"])
	)

	var max_polyphony: int = mini(4, candidates.size())
	for i in range(max_polyphony):
		var c: Dictionary = candidates[i]
		var midi: int = int(c["midi"])
		var b: int = int(c["bin"])
		var conf: float = float(c["conf"])
		new_pitches.append(midi)
		new_conf[str(midi)] = snappedf(conf, 0.001)

		var prev_e: float = _prev_energies[b]
		var last_t: float = float(_last_onset_sec.get(midi, -999.0))
		if (conf - prev_e >= 0.25 or prev_e < 0.20) and (now_sec - last_t >= 0.120):
			if not recent_onsets.has(midi):
				recent_onsets.append(midi)
			_last_onset_sec[midi] = now_sec

	new_pitches.sort()
	for b in range(num_bins):
		_prev_energies[b] = suppressed[b]

	detected_pitches = new_pitches
	confidence_map = new_conf
	last_latency_ms = float(Time.get_ticks_usec() - t0) / 1000.0
