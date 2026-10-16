extends SceneTree

const MIDI_TO_Y = {
	81: 300, 79: 310, 77: 320, 76: 330, 74: 340, 72: 350, 71: 360, 69: 370, 67: 380, 65: 390, 64: 400,
	62: 410, 60: 420, 59: 430, 57: 440, 55: 450, 53: 460, 52: 470, 50: 480, 48: 490, 47: 500, 45: 510,
	43: 520, 41: 530, 40: 540, 38: 550, 36: 560
}

func _init() -> void:
	print("Checking Piece 3 (Polyphonic) with dynamic barlines...")
	test_piece("res://assets/test_pieces/piece_3_polyphonic/score.png", "res://assets/test_pieces/piece_3_polyphonic/ground_truth.json")
	quit(0)

func test_piece(img_path: String, gt_path: String) -> void:
	var img = Image.load_from_file(ProjectSettings.globalize_path(img_path))
	img.convert(Image.FORMAT_L8)
	var w = img.get_width()
	var h = img.get_height()
	var raw = img.get_data()
	
	var y_to_midi = {}
	for midi in MIDI_TO_Y:
		y_to_midi[MIDI_TO_Y[midi]] = midi
	
	var staff_set = {320: true, 340: true, 360: true, 380: true, 400: true, 440: true, 460: true, 480: true, 500: true, 520: true}
	var non_staff_ys = []
	for y in range(320, 521):
		if not staff_set.has(y):
			non_staff_ys.append(y)
	
	# Dynamic barlines
	var barlines = []
	for x in range(200, w - 50):
		var count = 0
		for y in non_staff_ys:
			if raw[y * w + x] < 128:
				count += 1
		if count >= non_staff_ys.size() - 5:
			if barlines.is_empty() or x - barlines[-1] > 20:
				barlines.append(x)
	
	var staff_ys = [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]
	var ink = PackedByteArray()
	ink.resize(w * h)
	for i in range(w * h):
		ink[i] = 1 if raw[i] < 128 else 0
	
	for sy in staff_ys:
		for x in range(w):
			if ink[sy * w + x] == 1:
				var v_run = 0
				for dy in range(-2, 3):
					var cy = sy + dy
					if cy >= 0 and cy < h and raw[cy * w + x] < 128:
						v_run += 1
				if v_run <= 2:
					ink[sy * w + x] = 0
	
	for bx in barlines:
		for dx in range(-4, 5):
			var cx = bx + dx
			if cx >= 0 and cx < w:
				for y in range(300, 540):
					ink[y * w + cx] = 0
	for y in range(h):
		for x in range(230):
			ink[y * w + x] = 0
	
	var visited = PackedByteArray()
	visited.resize(w * h)
	var detected_notes = []
	
	for y in range(280, 580):
		for x in range(230, 1520):
			if ink[y * w + x] == 1 and visited[y * w + x] == 0:
				var q = [Vector2i(x, y)]
				visited[y * w + x] = 1
				var pts = [Vector2i(x, y)]
				var head = 0
				var min_x = x; var max_x = x; var min_y = y; var max_y = y
				while head < q.size():
					var pt = q[head]
					head += 1
					var px = pt.x; var py = pt.y
					if px < min_x: min_x = px
					if px > max_x: max_x = px
					if py < min_y: min_y = py
					if py > max_y: max_y = py
					for n_pt in [Vector2i(px+1, py), Vector2i(px-1, py), Vector2i(px, py+1), Vector2i(px, py-1)]:
						if n_pt.x >= 230 and n_pt.x < 1520 and n_pt.y >= 280 and n_pt.y < 580:
							var n_idx = n_pt.y * w + n_pt.x
							if ink[n_idx] == 1 and visited[n_idx] == 0:
								visited[n_idx] = 1
								q.append(n_pt)
								pts.append(n_pt)
				
				var bw = max_x - min_x + 1
				if bw >= 12 and pts.size() >= 40:
					var row_pixels = {}
					for pt in pts:
						if not row_pixels.has(pt.y):
							row_pixels[pt.y] = []
						row_pixels[pt.y].append(pt.x)
					
					var sorted_ys = row_pixels.keys()
					sorted_ys.sort()
					var r_widths = {}
					for ry in sorted_ys:
						var xs = row_pixels[ry]
						xs.sort()
						r_widths[ry] = xs[-1] - xs[0] + 1
					
					var peak_regions = []
					var in_peak = false
					var cur_peak_ys = []
					for ry in sorted_ys:
						var rw = r_widths[ry]
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
						var yc = preg[preg.size() / 2]
						var xs_at_yc = row_pixels[yc]
						xs_at_yc.sort()
						var xc = (xs_at_yc[0] + xs_at_yc[-1]) / 2.0
						var round_yc = round((yc - 300) / 10.0) * 10.0 + 300
						var pitch_midi = y_to_midi.get(int(round_yc), -1)
						detected_notes.append({"xc": xc, "yc": yc, "round_yc": round_yc, "pitch_midi": pitch_midi})
	
	print("Extracted candidate noteheads: ", detected_notes.size())
	var f = FileAccess.open(gt_path, FileAccess.READ)
	var gt_json = JSON.parse_string(f.get_as_text())
	var gt_notes = gt_json["notes"]
	print("Ground truth note count: ", gt_notes.size())
	
	var matched_gt = {}
	var tp = 0
	for det in detected_notes:
		var best_idx = -1
		var min_dx = 9999.0
		for gi in range(gt_notes.size()):
			if matched_gt.has(gi): continue
			var gn = gt_notes[gi]
			if gn.pitch_midi == det.pitch_midi:
				var m = gn["measure"]
				var b = gn["beat"]
				var bleft = barlines[m - 1]
				var wcur = barlines[m] - bleft
				var num_beats = gt_json.get("time_signature", [4, 4])[0]
				var expected_x = bleft + 15.0 + (b / float(num_beats)) * (wcur - 30.0)
				var dx = abs(det.xc - expected_x)
				if dx < 40.0 and dx < min_dx:
					min_dx = dx
					best_idx = gi
		if best_idx >= 0:
			matched_gt[best_idx] = true
			tp += 1
	
	var accuracy = float(tp) / gt_notes.size() * 100.0
	print("  Matched (TP): ", tp, " / ", gt_notes.size(), " (", accuracy, "%)")
