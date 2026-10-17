class_name OscilloscopeView
extends Control

## Real-Time Microphone Oscilloscope & VU Level Meter Control.
## Renders time-domain waveform with rising-edge zero-crossing trigger stabilization,
## graticule grid, noise-gate threshold guides, auto-gain scaling, and dB VU bar.

const DISPLAY_SAMPLES: int = 256

@export var rms_threshold: float = 0.005
@export var auto_gain: bool = true

var waveform_buffer: PackedFloat32Array = PackedFloat32Array()
var current_rms: float = 0.0
var current_rms_db: float = -100.0
var is_gated: bool = true
var sample_rate: int = 48000
var peak_amplitude: float = 0.0
var peak_db_hold: float = -100.0
var _peak_hold_timer: float = 0.0
var estimated_freq_hz: float = 0.0
var current_display_gain: float = 1.0

func _init() -> void:
	waveform_buffer.resize(512)
	waveform_buffer.fill(0.0)
	custom_minimum_size = Vector2(400, 110)

func update_waveform(samples: PackedFloat32Array, rms: float, rms_db: float, gated: bool, sr: int = 48000) -> void:
	if not samples.is_empty():
		waveform_buffer = samples.duplicate()
	current_rms = rms
	current_rms_db = rms_db
	is_gated = gated
	if sr > 0:
		sample_rate = sr

	# Compute peak amplitude and zero-crossing frequency estimate
	var pk: float = 0.0
	var zero_crossings: int = 0
	var n: int = waveform_buffer.size()
	for i in range(n):
		var a: float = absf(waveform_buffer[i])
		if a > pk:
			pk = a
		if i > 0 and waveform_buffer[i - 1] <= 0.0 and waveform_buffer[i] > 0.0:
			zero_crossings += 1
	peak_amplitude = pk

	if rms_db > peak_db_hold:
		peak_db_hold = rms_db
		_peak_hold_timer = 1.2

	if not is_gated and n > 0 and zero_crossings >= 2:
		var duration_sec: float = float(n) / float(maxi(1, sample_rate))
		estimated_freq_hz = float(zero_crossings) / duration_sec
	else:
		estimated_freq_hz = 0.0

	if auto_gain:
		var target_gain: float = 1.0
		if pk > 0.001 and pk < 0.45:
			target_gain = clampf(0.65 / pk, 1.0, 6.0)
		current_display_gain = lerpf(current_display_gain, target_gain, 0.25)
	else:
		current_display_gain = 1.0

	queue_redraw()

func _process(delta: float) -> void:
	if _peak_hold_timer > 0.0:
		_peak_hold_timer -= delta
	else:
		peak_db_hold = maxf(-100.0, peak_db_hold - delta * 25.0)
	queue_redraw()

func _find_trigger_offset() -> int:
	var n: int = waveform_buffer.size()
	var max_search: int = maxi(1, n - DISPLAY_SAMPLES - 1)
	# Search for rising zero-crossing with steepest positive slope
	for i in range(1, max_search):
		if waveform_buffer[i - 1] <= 0.0 and waveform_buffer[i] > 0.002:
			return i
	return 0

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if rect.size.x < 40.0 or rect.size.y < 30.0:
		return

	var vu_width: float = 22.0
	var scope_w: float = rect.size.x - vu_width - 6.0
	var scope_h: float = rect.size.y
	var scope_rect := Rect2(0.0, 0.0, scope_w, scope_h)

	# 1. Background CRT Panel
	draw_rect(scope_rect, Color(0.03, 0.05, 0.08, 0.94), true)

	# 2. Graticule Grid Lines
	var grid_col := Color(0.14, 0.22, 0.32, 0.55)
	var center_y: float = scope_h * 0.5
	var usable_half_h: float = (scope_h - 32.0) * 0.5

	# Horizontal division lines (+1.0, +0.5, 0.0, -0.5, -1.0)
	for frac in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var y: float = center_y - frac * usable_half_h
		var col: Color = Color(0.22, 0.35, 0.48, 0.8) if is_zero_approx(frac) else grid_col
		draw_line(Vector2(0.0, y), Vector2(scope_w, y), col, 1.0)

	# Vertical time division lines (8 divisions)
	for div_i in range(1, 8):
		var x: float = scope_w * (float(div_i) / 8.0)
		draw_line(Vector2(x, 0.0), Vector2(x, scope_h), grid_col, 1.0)

	# 3. Noise Gate Threshold Guides
	var gate_vis: float = clampf(rms_threshold * current_display_gain, 0.02, 0.95)
	var gate_y_top: float = center_y - gate_vis * usable_half_h
	var gate_y_bot: float = center_y + gate_vis * usable_half_h
	var gate_col := Color(1.0, 0.72, 0.15, 0.45)
	draw_dashed_line(Vector2(0.0, gate_y_top), Vector2(scope_w, gate_y_top), gate_col, 1.0, 5.0)
	draw_dashed_line(Vector2(0.0, gate_y_bot), Vector2(scope_w, gate_y_bot), gate_col, 1.0, 5.0)

	# 4. Triggered Time-Domain Waveform Trace
	var n_buf: int = waveform_buffer.size()
	if n_buf >= 2:
		var trig: int = _find_trigger_offset()
		var count: int = mini(DISPLAY_SAMPLES, n_buf - trig)
		if count >= 2:
			var pts := PackedVector2Array()
			pts.resize(count)
			for i in range(count):
				var px: float = (float(i) / float(count - 1)) * (scope_w - 4.0) + 2.0
				var sample: float = clampf(waveform_buffer[trig + i] * current_display_gain, -1.05, 1.05)
				var py: float = center_y - sample * usable_half_h
				pts[i] = Vector2(px, py)

			var trace_core: Color = Color(0.15, 1.0, 0.55, 0.98) if not is_gated else Color(0.25, 0.80, 1.0, 0.75)
			var trace_glow: Color = trace_core
			trace_glow.a = 0.25
			draw_polyline(pts, trace_glow, 5.0, true)
			draw_polyline(pts, trace_core, 2.0, true)

	# Outer border of scope
	var border_col: Color = Color(0.15, 0.95, 0.55, 0.85) if not is_gated else Color(0.25, 0.40, 0.58, 0.85)
	draw_rect(scope_rect, border_col, false, 1.5)

	# 5. Telemetry Overlay Labels inside Scope
	var font: Font = ThemeDB.fallback_font
	if font:
		draw_string(font, Vector2(8.0, 14.0), "OSCILLOSCOPE  [%d Hz]" % sample_rate, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.88, 1.0, 0.9))
		var gate_str: String = "GATE: OPEN" if not is_gated else "GATE: MUTED (< -46 dB)"
		var gate_text_col: Color = Color(0.2, 1.0, 0.5, 0.95) if not is_gated else Color(1.0, 0.72, 0.25, 0.85)
		draw_string(font, Vector2(scope_w - 145.0, 14.0), gate_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, gate_text_col)

		var db_display: String = "%.1f dB" % maxf(-60.0, current_rms_db) if current_rms_db > -90.0 else "-INF dB"
		var freq_display: String = "  |  ~%.1f Hz" % estimated_freq_hz if estimated_freq_hz >= 30.0 and estimated_freq_hz <= 2500.0 else ""
		draw_string(font, Vector2(8.0, scope_h - 6.0), "RMS: %s  |  Peak: %.3f%s" % [db_display, peak_amplitude, freq_display], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.9, 1.0, 0.88))
		draw_string(font, Vector2(scope_w - 72.0, scope_h - 6.0), "Gain: %.1fx" % current_display_gain, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.65, 0.78, 0.92, 0.8))

	# 6. Vertical VU Level Meter Bar on the Right
	var vu_rect := Rect2(scope_w + 6.0, 0.0, vu_width, scope_h)
	draw_rect(vu_rect, Color(0.04, 0.06, 0.10, 0.95), true)

	# Normalize dB from [-60..0] to [0..1]
	var db_norm: float = clampf((current_rms_db + 60.0) / 60.0, 0.0, 1.0)
	var fill_h: float = (scope_h - 4.0) * db_norm
	if fill_h > 1.0:
		var fill_rect := Rect2(vu_rect.position.x + 2.0, scope_h - 2.0 - fill_h, vu_width - 4.0, fill_h)
		var bar_col: Color = Color(0.15, 0.95, 0.50, 0.95)
		if current_rms_db > -6.0:
			bar_col = Color(1.0, 0.25, 0.30, 0.95)
		elif current_rms_db > -18.0:
			bar_col = Color(1.0, 0.84, 0.15, 0.95)
		elif is_gated:
			bar_col = Color(0.30, 0.65, 0.90, 0.70)
		draw_rect(fill_rect, bar_col, true)

	# Gate threshold tick on VU bar (-46 dB -> (60 - 46)/60 = 0.233)
	var gate_db_norm: float = clampf((20.0 * log(maxf(0.00001, rms_threshold)) / log(10.0) + 60.0) / 60.0, 0.0, 1.0)
	var gate_vu_y: float = scope_h - 2.0 - (scope_h - 4.0) * gate_db_norm
	draw_line(Vector2(vu_rect.position.x, gate_vu_y), Vector2(vu_rect.position.x + vu_width, gate_vu_y), Color(1.0, 0.72, 0.15, 0.9), 2.0)

	# Peak Hold Line on VU bar
	var peak_norm: float = clampf((peak_db_hold + 60.0) / 60.0, 0.0, 1.0)
	if peak_norm > 0.02:
		var pk_y: float = scope_h - 2.0 - (scope_h - 4.0) * peak_norm
		draw_line(Vector2(vu_rect.position.x + 1.0, pk_y), Vector2(vu_rect.position.x + vu_width - 1.0, pk_y), Color(1.0, 1.0, 1.0, 0.95), 2.0)

	draw_rect(vu_rect, Color(0.25, 0.40, 0.58, 0.85), false, 1.5)
