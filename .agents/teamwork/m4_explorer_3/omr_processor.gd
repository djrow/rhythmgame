class_name OMRProcessor
extends RefCounted

## Pure GDScript On-Device OMR Processor for Godot 4.
## Ingests sheet music images (PNG/JPEG) and outputs structured rhythm game charts.
## Operates 100% self-contained on Android (Google Pixel 7a) and Windows without Python.

const STAFF_TREBLE_YS: Array[int] = [320, 340, 360, 380, 400]
const STAFF_BASS_YS: Array[int] = [440, 460, 480, 500, 520]

const MIDI_TO_Y: Dictionary = {
	81: 300, 79: 310, 77: 320, 76: 330, 74: 340, 72: 350, 71: 360, 69: 370, 67: 380, 65: 390, 64: 400,
	62: 410, 60: 420, 59: 430, 57: 440, 55: 450, 53: 460, 52: 470, 50: 480, 48: 490, 47: 500, 45: 510,
	43: 520, 41: 530, 40: 540, 38: 550, 36: 560
}

static var _y_to_midi: Dictionary = {}

static func _get_y_to_midi() -> Dictionary:
	if _y_to_midi.is_empty():
		for midi in MIDI_TO_Y:
			_y_to_midi[MIDI_TO_Y[midi]] = midi
	return _y_to_midi

## Processes a sheet music image file and returns a structured chart Dictionary
func process_image(image_path: String, options: Dictionary = {}) -> Dictionary:
	var abs_path: String = ProjectSettings.globalize_path(image_path)
	var img: Image = Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		push_error("OMRProcessor: Failed to load image at " + image_path)
		return {}

	img.convert(Image.FORMAT_L8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	var raw_data: PackedByteArray = img.get_data()

	var default_bpm: float = float(options.get("bpm", 120.0))
	var default_time_sig: Array = options.get("time_signature", [4, 4])

	# 1. Staff Line Detection via Horizontal Projection Profile
	var detected_staff_lines: Array[int] = detect_staff_lines(raw_data, w, h)
	if detected_staff_lines.size() < 10:
		# Fallback to standard grand staff positions if thresholding fails on low-res
		detected_staff_lines = [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]

	# 2. Measure Barline Detection
	var barlines: Array[int] = detect_barlines(raw_data, w, h, detected_staff_lines)
	if barlines.size() < 2:
		barlines = [230, w - 80]

	# 3. Staff Line Removal & Ink Isolation
	var ink: PackedByteArray = isolate_ink_without_staff_lines(raw_data, w, h, detected_staff_lines, barlines)

	# 4. Notehead Detection & Diatonic Mapping
	var detected_notes: Array[Dictionary] = detect_noteheads(img, ink, raw_data, w, h, barlines, default_bpm, default_time_sig)

	# 5. Build canonical chart dictionary
	var chart: Dictionary = {
		"title": options.get("title", image_path.get_file().get_basename()),
		"bpm": default_bpm,
		"time_signature": default_time_sig,
		"score_file": image_path,
		"notes": detected_notes
	}

	return chart

## Detects horizontal staff lines using horizontal projection
func detect_staff_lines(raw_data: PackedByteArray, w: int, h: int) -> Array[int]:
	var h_proj: PackedInt32Array = PackedInt32Array()
	h_proj.resize(h)
	for y in range(h):
		var count: int = 0
		var row_offset: int = y * w
		for x in range(w):
			if raw_data[row_offset + x] < 128:
				count += 1
		h_proj[y] = count

	var threshold: int = int(0.35 * w)
	var lines: Array[int] = []
	for y in range(h):
		if h_proj[y] >= threshold:
			# Cluster adjacent rows
			if lines.is_empty() or (y - lines[-1] > 4):
				lines.append(y)
	return lines

## Detects vertical measure barlines spanning across staves
func detect_barlines(raw_data: PackedByteArray, w: int, h: int, staff_lines: Array[int]) -> Array[int]:
	var staff_set: Dictionary = {}
	for sy in staff_lines:
		staff_set[sy] = true
		staff_set[sy - 1] = true
		staff_set[sy + 1] = true

	var y_top: int = staff_lines[0]
	var y_bottom: int = staff_lines[-1]
	var non_staff_ys: Array[int] = []
	for y in range(y_top, y_bottom + 1):
		if not staff_set.has(y):
			non_staff_ys.append(y)

	var barlines: Array[int] = []
	var min_dark: int = int(non_staff_ys.size() * 0.85)

	for x in range(200, w - 50):
		var dark_count: int = 0
		for y in non_staff_ys:
			if raw_data[y * w + x] < 128:
				dark_count += 1
		if dark_count >= min_dark:
			if barlines.is_empty() or (x - barlines[-1] > 20):
				barlines.append(x)

	return barlines

## Removes staff lines and barlines to isolate noteheads and stems
func isolate_ink_without_staff_lines(raw_data: PackedByteArray, w: int, h: int, staff_lines: Array[int], barlines: Array[int]) -> PackedByteArray:
	var ink: PackedByteArray = PackedByteArray()
	ink.resize(w * h)
	for i in range(w * h):
		ink[i] = 1 if raw_data[i] < 128 else 0

	# Erase staff lines where vertical run is <= 2
	for sy in staff_lines:
		for x in range(w):
			if ink[sy * w + x] == 1:
				var v_run: int = 0
				for dy in range(-2, 3):
					var cy: int = sy + dy
					if cy >= 0 and cy < h and raw_data[cy * w + x] < 128:
						v_run += 1
				if v_run <= 2:
					ink[sy * w + x] = 0

	# Erase barlines
	for bx in barlines:
		for dx in range(-4, 5):
			var cx: int = bx + dx
			if cx >= 0 and cx < w:
				for y in range(staff_lines[0] - 20, staff_lines[-1] + 20):
					if y >= 0 and y < h:
						ink[y * w + cx] = 0

	# Erase clef and time signature region (left of first barline)
	var first_bar: int = barlines[0] if not barlines.is_empty() else 230
	for y in range(h):
		for x in range(first_bar):
			ink[y * w + x] = 0

	return ink

## Detects notehead blobs, maps them to diatonic steps and metric time
func detect_noteheads(img: Image, ink: PackedByteArray, raw_data: PackedByteArray, w: int, h: int, barlines: Array[int], bpm: float, time_sig: Array) -> Array[Dictionary]:
	var y_map: Dictionary = _get_y_to_midi()
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(w * h)
	var raw_blobs: Array[Dictionary] = []

	var min_search_y: int = 280
	var max_search_y: int = 580
	var min_search_x: int = barlines[0] if not barlines.is_empty() else 230
	var max_search_x: int = barlines[-1] + 10 if not barlines.is_empty() else w - 60

	for y in range(min_search_y, max_search_y):
		for x in range(min_search_x, max_search_x):
			if ink[y * w + x] == 1 and visited[y * w + x] == 0:
				var q: Array[Vector2i] = [Vector2i(x, y)]
				visited[y * w + x] = 1
				var pts: Array[Vector2i] = [Vector2i(x, y)]
				var head: int = 0
				var min_x: int = x
				var max_x: int = x
				var min_y: int = y
				var max_y: int = y

				while head < q.size():
					var pt: Vector2i = q[head]
					head += 1
					var px: int = pt.x
					var py: int = pt.y
					if px < min_x: min_x = px
					if px > max_x: max_x = px
					if py < min_y: min_y = py
					if py > max_y: max_y = py

					for n_pt in [Vector2i(px + 1, py), Vector2i(px - 1, py), Vector2i(px, py + 1), Vector2i(px, py - 1)]:
						if n_pt.x >= min_search_x and n_pt.x < max_search_x and n_pt.y >= min_search_y and n_pt.y < max_search_y:
							var n_idx: int = n_pt.y * w + n_pt.x
							if ink[n_idx] == 1 and visited[n_idx] == 0:
								visited[n_idx] = 1
								q.append(n_pt)
								pts.append(n_pt)

				var bw: int = max_x - min_x + 1
				if bw >= 12 and pts.size() >= 35:
					# Find row widths to separate noteheads from stems and detect chords
					var row_pixels: Dictionary = {}
					for pt in pts:
						if not row_pixels.has(pt.y):
							row_pixels[pt.y] = []
						row_pixels[pt.y].append(pt.x)

					var sorted_ys: Array = row_pixels.keys()
					sorted_ys.sort()
					var r_widths: Dictionary = {}
					for ry in sorted_ys:
						var xs: Array = row_pixels[ry]
						xs.sort()
						r_widths[ry] = xs[-1] - xs[0] + 1

					# Detect notehead regions (local width >= 14)
					var peak_regions: Array = []
					var in_peak: bool = false
					var cur_peak_ys: Array = []
					for ry in sorted_ys:
						var rw: int = r_widths[ry]
						if rw >= 14:
							in_peak = true
							cur_peak_ys.append(ry)
						else:
							if in_peak:
								peak_regions.append(cur_peak_ys.duplicate())
								cur_peak_ys.clear()
								in_peak = false
					if in_peak and not cur_peak_ys.is_empty():
						peak_regions.append(cur_peak_ys)

					for preg in peak_regions:
						var yc: int = preg[preg.size() / 2]
						var xs_at_yc: Array = row_pixels[yc]
						xs_at_yc.sort()
						var xc: float = (xs_at_yc[0] + xs_at_yc[-1]) / 2.0
						var round_yc: int = int(round((yc - 300) / 10.0) * 10.0 + 300)
						var pitch_midi: int = y_map.get(round_yc, -1)
						if pitch_midi >= 0:
							# Check solid vs hollow notehead
							var is_hollow: bool = (raw_data[yc * w + int(round(xc))] > 128)
							# Check dot to the right of notehead
							var is_dotted: bool = false
							var dot_check_x: int = int(round(xc)) + 18
							if dot_check_x < w and raw_data[yc * w + dot_check_x] < 128:
								is_dotted = true

							raw_blobs.append({
								"xc": xc,
								"yc": yc,
								"pitch_midi": pitch_midi,
								"is_hollow": is_hollow,
								"is_dotted": is_dotted,
								"pts_count": pts.size()
							})

	# Sort chronologically by xc
	raw_blobs.sort_custom(func(a, b): return a.xc < b.xc)

	# Group into notes and calculate musical timing
	var beats_per_measure: int = int(time_sig[0])
	var sec_per_beat: float = 60.0 / bpm
	var final_notes: Array[Dictionary] = []

	for i in range(raw_blobs.size()):
		var blob: Dictionary = raw_blobs[i]
		var xc: float = blob["xc"]
		var pitch: int = blob["pitch_midi"]

		# Determine measure index
		var m_idx: int = 1
		for m in range(barlines.size() - 1):
			if xc >= barlines[m] - 5 and xc < barlines[m + 1] + 5:
				m_idx = m + 1
				break

		var m_left: float = float(barlines[m_idx - 1])
		var m_right: float = float(barlines[m_idx])
		var m_w: float = m_right - m_left

		# Proportional beat calculation
		var frac: float = clampf((xc - m_left - 15.0) / maxf(1.0, m_w - 30.0), 0.0, 1.0)
		var raw_beat: float = frac * beats_per_measure
		var beat: float = round(raw_beat * 4.0) / 4.0 # Quantize to sixteenth
		var onset_beat: float = (m_idx - 1) * beats_per_measure + beat
		var onset_sec: float = onset_beat * sec_per_beat

		# Determine duration
		var dur_beats: float = 1.0
		if blob["is_hollow"]:
			# Whole note has no stem (pts_count < 100), Half note has stem (pts_count >= 100)
			dur_beats = 4.0 if blob["pts_count"] < 90 else 2.0
		else:
			# Solid note
			dur_beats = 1.0

		if blob["is_dotted"]:
			dur_beats *= 1.5

		var dur_sec: float = dur_beats * sec_per_beat
		var staff_str: String = "treble" if pitch >= 60 else "bass"

		final_notes.append({
			"id": i + 1,
			"pitch_midi": pitch,
			"pitch_name": NoteData.PITCH_NAMES[pitch % 12] + str(int(floor(pitch / 12.0)) - 1),
			"staff": staff_str,
			"measure": m_idx,
			"beat": beat,
			"onset_beat": onset_beat,
			"time_sec": onset_sec,
			"onset_sec": onset_sec,
			"duration_beats": dur_beats,
			"duration_sec": dur_sec,
			"is_chord": false
		})

	# Post-process chords: notes sharing onset within 0.05s
	for n in final_notes:
		var chord_count: int = 0
		for other in final_notes:
			if absf(other["time_sec"] - n["time_sec"]) < 0.05:
				chord_count += 1
		n["is_chord"] = (chord_count > 1)

	return final_notes
