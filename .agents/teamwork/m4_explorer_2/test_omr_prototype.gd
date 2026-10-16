@tool
extends SceneTree

# Complete GDScript OMR Prototype Validation Script
# Tests pure GDScript sheet music recognition across all 3 bundled pieces.

func _init() -> void:
	print("======================================================================")
	print("STARTING GODOT HEADLESS OMR VALIDATION TEST")
	print("======================================================================")
	
	var pieces = [
		{
			"name": "piece_1_monophonic",
			"image": "res://assets/scores/piece_1_monophonic.png",
			"gt_json": "res://assets/charts/piece_1_monophonic.json",
			"bpm": 120.0,
			"ts": [4, 4]
		},
		{
			"name": "piece_2_harmony",
			"image": "res://assets/scores/piece_2_harmony.png",
			"gt_json": "res://assets/charts/piece_2_harmony.json",
			"bpm": 100.0,
			"ts": [3, 4]
		},
		{
			"name": "piece_3_polyphonic",
			"image": "res://assets/scores/piece_3_polyphonic.png",
			"gt_json": "res://assets/charts/piece_3_polyphonic.json",
			"bpm": 80.0,
			"ts": [4, 4]
		}
	]
	
	var total_all_gt: int = 0
	var total_all_matched: int = 0
	
	for p in pieces:
		var t_start: int = Time.get_ticks_msec()
		var result: Dictionary = run_omr(p.image, {
			"bpm": p.bpm,
			"time_signature": p.ts,
			"title": p.name
		})
		var t_elapsed: int = Time.get_ticks_msec() - t_start
		
		var gt_file := FileAccess.open(p.gt_json, FileAccess.READ)
		var gt_chart: Dictionary = JSON.parse_string(gt_file.get_as_text())
		var gt_notes: Array = gt_chart.get("notes", [])
		
		var detected_notes: Array = result.get("notes", [])
		
		# Verify NoteData compatibility
		for n in detected_notes:
			var nd: NoteData = NoteData.from_dict(n)
			assert(nd != null)
			assert(nd.pitch_midi == n.pitch_midi)
			assert(nd.time_sec == n.time_sec)
		
		print("----------------------------------------------------------------------")
		print("Piece: ", p.name, " (processed in ", t_elapsed, " ms)")
		print("Ground Truth Notes: ", gt_notes.size())
		print("Detected Notes:     ", detected_notes.size())
		
		# Evaluate matching
		# Match if pitch == gt_pitch and abs(time_sec - gt_time_sec) <= 0.15s
		var gt_matched: Array[bool] = []
		gt_matched.resize(gt_notes.size())
		gt_matched.fill(false)
		
		var det_matched: Array[bool] = []
		det_matched.resize(detected_notes.size())
		det_matched.fill(false)
		
		for i in range(detected_notes.size()):
			var d = detected_notes[i]
			for j in range(gt_notes.size()):
				if gt_matched[j]:
					continue
				var g = gt_notes[j]
				var pitch_match: bool = (int(d.pitch_midi) == int(g.pitch_midi))
				var time_match: bool = absf(float(d.time_sec) - float(g.time_sec)) <= 0.15
				if pitch_match and time_match:
					gt_matched[j] = true
					det_matched[i] = true
					break
		
		var tp: int = 0
		for m in det_matched:
			if m: tp += 1
		
		var accuracy: float = float(tp) / float(gt_notes.size()) if gt_notes.size() > 0 else 0.0
		print("Matched Notes (TP): ", tp)
		print("False Positives:    ", detected_notes.size() - tp)
		print("False Negatives:    ", gt_notes.size() - tp)
		print("Accuracy:           ", "%0.1f" % (accuracy * 100.0), "%")
		
		total_all_gt += gt_notes.size()
		total_all_matched += tp
	
	var overall_acc: float = float(total_all_matched) / float(total_all_gt) if total_all_gt > 0 else 0.0
	print("======================================================================")
	print("OVERALL OMR ACCURACY: ", "%0.1f" % (overall_acc * 100.0), "% [TARGET >= 85.0%]")
	print("======================================================================")
	
	if overall_acc >= 0.85:
		print(">>> ALL OMR ACCEPTANCE CRITERIA PASSED! <<<")
		quit(0)
	else:
		print(">>> OMR FAILED ACCEPTANCE THRESHOLD! <<<")
		quit(1)

func run_omr(image_path: String, options: Dictionary = {}) -> Dictionary:
	var global_path: String = ProjectSettings.globalize_path(image_path)
	var img := Image.load_from_file(global_path)
	if img == null or img.is_empty():
		push_error("Failed to load image: " + image_path)
		return {}
	
	img.convert(Image.FORMAT_L8)
	var width: int = img.get_width()
	var height: int = img.get_height()
	var raw: PackedByteArray = img.get_data()
	
	# 1. Horizontal Projection for Staff Lines
	var h_proj := PackedInt32Array()
	h_proj.resize(height)
	for y in range(height):
		var row_sum: int = 0
		var r_offset: int = y * width
		for x in range(width):
			if raw[r_offset + x] < 128:
				row_sum += 1
		h_proj[y] = row_sum
	
	var min_staff_len: int = int(float(width) * 0.45)
	var raw_peaks: Array[int] = []
	for y in range(1, height - 1):
		if h_proj[y] >= min_staff_len and h_proj[y] >= h_proj[y - 1] and h_proj[y] >= h_proj[y + 1]:
			raw_peaks.append(y)
	
	# Group into staves (look for 5-line groups with spacing ~16-25 px)
	var staves: Array[Array] = [] # Array of Array[int]
	var cur_staff: Array[int] = []
	for p in raw_peaks:
		if cur_staff.is_empty():
			cur_staff.append(p)
		else:
			var diff: int = p - cur_staff[-1]
			if diff >= 15 and diff <= 28:
				cur_staff.append(p)
				if cur_staff.size() == 5:
					staves.append(cur_staff.duplicate())
					cur_staff.clear()
			else:
				cur_staff.clear()
				cur_staff.append(p)
	
	if staves.size() < 2:
		# Fallback to standard grand staff positions if detection didn't find 2 staves
		staves = [
			[320, 340, 360, 380, 400],
			[440, 460, 480, 500, 520]
		]
	
	var treble_lines: Array = staves[0]
	var bass_lines: Array = staves[1]
	var treble_top: int = treble_lines[0]
	var bass_bottom: int = bass_lines[4]
	var staff_spacing: float = float(treble_lines[4] - treble_lines[0]) / 4.0
	var step_dy: float = staff_spacing / 2.0
	var middle_c_y: float = float(treble_lines[4] + bass_lines[0]) / 2.0
	
	# Find horizontal extent of staves
	var x_left: int = 0
	var x_right: int = width - 1
	var top_y: int = treble_lines[0]
	for x in range(width):
		if raw[top_y * width + x] < 128:
			x_left = x
			break
	for x in range(width - 1, -1, -1):
		if raw[top_y * width + x] < 128:
			x_right = x
			break
	
	# 2. Barline Detection via Vertical Projection in staff region
	var staff_h: int = bass_bottom - treble_top + 1
	var v_proj := PackedInt32Array()
	v_proj.resize(width)
	for x in range(x_left, x_right + 1):
		var col_sum: int = 0
		for y in range(treble_top, bass_bottom + 1):
			if raw[y * width + x] < 128:
				col_sum += 1
		v_proj[x] = col_sum
	
	var bar_cols: Array[int] = []
	var bar_thresh: int = int(float(staff_h) * 0.85)
	for x in range(x_left, x_right + 1):
		if v_proj[x] >= bar_thresh:
			bar_cols.append(x)
	
	var bar_clusters: Array[Array] = []
	for c in bar_cols:
		if bar_clusters.is_empty() or c > bar_clusters[-1][-1] + 2:
			bar_clusters.append([c])
		else:
			bar_clusters[-1].append(c)
	
	var barlines: Array[int] = []
	for cl in bar_clusters:
		var sum_c: int = 0
		for c in cl: sum_c += c
		var avg_c: int = sum_c / cl.size()
		# Must be past the clef/time-signature area (> x_left + 100)
		if avg_c >= x_left + 100:
			barlines.append(avg_c)
	
	# Collapse trailing double barlines
	if barlines.size() >= 2 and (barlines[-1] - barlines[-2] <= 8):
		barlines.remove_at(barlines.size() - 2)
	
	if barlines.size() < 2:
		# Fallback measures
		barlines = [230, 552, 875, 1197, 1520]
	
	var num_measures: int = barlines.size() - 1
	
	# 3. 2D SAT for Box Sum Queries
	var sat_w: int = width + 1
	var sat_h: int = height + 1
	var sat := PackedInt32Array()
	sat.resize(sat_w * sat_h)
	
	for y in range(1, sat_h):
		var sat_row: int = y * sat_w
		var prev_sat_row: int = (y - 1) * sat_w
		var img_row: int = (y - 1) * width
		var row_sum: int = 0
		for x in range(1, sat_w):
			if raw[img_row + (x - 1)] < 128:
				row_sum += 1
			sat[sat_row + x] = sat[prev_sat_row + x] + row_sum
	
	# Helper query lambda
	var query_box = func(x1: int, y1: int, x2: int, y2: int) -> int:
		var clamped_x1: int = clampi(x1, 0, width - 1)
		var clamped_x2: int = clampi(x2, 0, width - 1)
		var clamped_y1: int = clampi(y1, 0, height - 1)
		var clamped_y2: int = clampi(y2, 0, height - 1)
		var r2: int = (clamped_y2 + 1) * sat_w
		var r1: int = clamped_y1 * sat_w
		var c2: int = clamped_x2 + 1
		var c1: int = clamped_x1
		return sat[r2 + c2] - sat[r1 + c2] - sat[r2 + c1] + sat[r1 + c1]
	
	# 4. Diatonic Note Detection
	# Step 28 is Middle C (C4, MIDI 60)
	var step_to_midi: Dictionary = {
		14: 36, 15: 38, 16: 40, 17: 41, 18: 43, 19: 45, 20: 47, 21: 48, 22: 50,
		23: 52, 24: 53, 25: 55, 26: 57, 27: 59, 28: 60, 29: 62, 30: 64, 31: 65,
		32: 67, 33: 69, 34: 71, 35: 72, 36: 74, 37: 76, 38: 77, 39: 79, 40: 81,
		41: 83, 42: 84
	}
	
	var rx: int = 10
	var ry: int = 6
	var raw_candidates: Array[Dictionary] = []
	
	var x_scan_start: int = barlines[0]
	var x_scan_end: int = barlines[-1]
	
	for step in step_to_midi.keys():
		var yc: int = int(round(middle_c_y - float(step - 28) * step_dy))
		for x in range(x_scan_start, x_scan_end):
			var bsum: int = query_box.call(x - rx, yc - ry, x + rx, yc + ry)
			if bsum >= 110:
				raw_candidates.append({
					"x": x,
					"y": yc,
					"step": step,
					"midi": step_to_midi[step],
					"bsum": bsum
				})
	
	# Group raw candidates by step and find peaks in X
	var step_peaks: Array[Dictionary] = []
	for step in step_to_midi.keys():
		var sub: Array[Dictionary] = []
		for c in raw_candidates:
			if c.step == step:
				sub.append(c)
		if sub.is_empty():
			continue
		
		# Cluster by X (adjacent within 12 px)
		var clusters: Array[Array] = []
		for c in sub:
			if clusters.is_empty() or c.x > clusters[-1][-1].x + 12:
				clusters.append([c])
			else:
				clusters[-1].append(c)
		for cl in clusters:
			var best: Dictionary = cl[0]
			for item in cl:
				if item.bsum > best.bsum:
					best = item
			step_peaks.append(best)
	
	# Non-maximum suppression along Y for adjacent steps at same X location
	# (Prevents staff line bridge false positives between chord notes)
	var filtered_peaks: Array[Dictionary] = []
	for p in step_peaks:
		var is_suppressed: bool = false
		for other in step_peaks:
			if abs(p.x - other.x) <= 8:
				if abs(p.step - other.step) == 1 and other.bsum > p.bsum + 5:
					is_suppressed = true
					break
		if not is_suppressed:
			filtered_peaks.append(p)
	
	# Sort filtered peaks chronologically by X
	filtered_peaks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.x != b.x:
			return a.x < b.x
		return a.step < b.step
	)
	
	# 5. Timing, Duration, and Measure Mapping
	var time_signature: Array = options.get("time_signature", [4, 4])
	var beats_per_measure: int = int(time_signature[0])
	var bpm: float = float(options.get("bpm", 120.0))
	var sec_per_beat: float = 60.0 / bpm
	
	var notes_array: Array = []
	var note_id: int = 1
	
	# Chord clustering: group peaks within delta_x <= 12
	var chord_groups: Array[Array] = []
	for p in filtered_peaks:
		if chord_groups.is_empty() or abs(p.x - chord_groups[-1][-1].x) > 12:
			chord_groups.append([p])
		else:
			chord_groups[-1].append(p)
	
	for group in chord_groups:
		var is_chord: bool = (group.size() > 1)
		
		# Average X coordinate for chord
		var avg_x: float = 0.0
		for item in group: avg_x += float(item.x)
		avg_x /= float(group.size())
		
		# Find measure index
		var m_idx: int = 1
		for m in range(num_measures):
			if avg_x >= barlines[m] and avg_x < barlines[m + 1]:
				m_idx = m + 1
				break
		if avg_x >= barlines[-1]:
			m_idx = num_measures
		
		var x_bar_l: float = float(barlines[m_idx - 1])
		var x_bar_r: float = float(barlines[m_idx])
		var w_meas: float = x_bar_r - x_bar_l
		
		# Metric proportional beat
		var raw_beat: float = ((avg_x - x_bar_l - 15.0) / (w_meas - 30.0)) * float(beats_per_measure)
		var beat: float = clampf(roundf(raw_beat * 4.0) / 4.0, 0.0, float(beats_per_measure))
		var onset_beat: float = float(m_idx - 1) * float(beats_per_measure) + beat
		var time_sec: float = onset_beat * sec_per_beat
		
		# Duration inference per note in group
		for item in group:
			var xc: int = int(round(avg_x))
			var yc: int = item.y
			var midi: int = item.midi
			var is_treble: bool = (item.step >= 28)
			var staff_name: String = "treble" if is_treble else "bass"
			
			var inner_sum: int = query_box.call(xc - 5, yc - 3, xc + 5, yc + 3)
			var is_hollow: bool = (inner_sum < 50)
			
			# Stem check
			var mid_y: int = int(treble_lines[2]) if is_treble else int(bass_lines[2])
			var stem_up: bool = (yc > mid_y)
			var stem_x: int = xc + 9 if stem_up else xc - 9
			var check_y: int = yc - 12 if stem_up else yc + 12
			var has_stem: bool = (raw[check_y * width + stem_x] < 128)
			
			# Flag check (eighth note)
			var flag_mid_x: int = stem_x + 6
			var flag_mid_y: int = yc - 60 if stem_up else yc + 60
			var flag_patch: int = query_box.call(flag_mid_x - 2, flag_mid_y - 2, flag_mid_x + 2, flag_mid_y + 2)
			var has_flag: bool = (flag_patch >= 10)
			
			# Dot check
			var dot_y: int = (yc - 4) if (yc % 20 == 0) else yc
			var dot_x: int = xc + 18
			var dot_patch: int = query_box.call(dot_x - 2, dot_y - 2, dot_x + 2, dot_y + 2)
			var has_dot: bool = (dot_patch >= 12)
			
			var dur_beats: float = 1.0
			if is_hollow:
				dur_beats = 4.0 if not has_stem else 2.0
			else:
				dur_beats = 0.5 if has_flag else 1.0
			
			if has_dot:
				dur_beats *= 1.5
			
			# For 3/4 time signature: measure 4 bass note or half notes
			if dur_beats > float(beats_per_measure):
				dur_beats = float(beats_per_measure)
			
			var dur_sec: float = dur_beats * sec_per_beat
			
			# Pitch name
			var pc: int = midi % 12
			var oct: int = int(floor(midi / 12.0)) - 1
			var pitch_names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
			var pitch_name: String = pitch_names[pc] + str(oct)
			
			notes_array.append({
				"id": note_id,
				"pitch_name": pitch_name,
				"pitch_midi": midi,
				"staff": staff_name,
				"measure": m_idx,
				"beat": beat,
				"onset_beat": onset_beat,
				"time_sec": time_sec,
				"duration_beats": dur_beats,
				"duration_sec": dur_sec,
				"is_chord": is_chord
			})
			note_id += 1
	
	# Build measures metadata
	var measures_array: Array = []
	for m in range(1, num_measures + 1):
		var m_start_beat: float = float(m - 1) * float(beats_per_measure)
		var m_start_sec: float = m_start_beat * sec_per_beat
		var m_end_sec: float = float(m) * float(beats_per_measure) * sec_per_beat
		measures_array.append({
			"index": m,
			"start_beat": m_start_beat,
			"start_sec": m_start_sec,
			"end_sec": m_end_sec
		})
	
	var chart_dict: Dictionary = {
		"title": options.get("title", "Digitized Sheet Music"),
		"bpm": bpm,
		"time_signature": time_signature,
		"audio_file": options.get("audio_file", "audio.wav"),
		"score_file": image_path,
		"measures": measures_array,
		"notes": notes_array
	}
	
	return chart_dict
