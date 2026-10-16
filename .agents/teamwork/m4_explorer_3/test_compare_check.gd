extends SceneTree

const MIDI_TO_Y = {
	81: 300, 79: 310, 77: 320, 76: 330, 74: 340, 72: 350, 71: 360, 69: 370, 67: 380, 65: 390, 64: 400,
	62: 410, 60: 420, 59: 430, 57: 440, 55: 450, 53: 460, 52: 470, 50: 480, 48: 490, 47: 500, 45: 510,
	43: 520, 41: 530, 40: 540, 38: 550, 36: 560
}

func _init() -> void:
	var p = "res://assets/test_pieces/piece_1_monophonic/score.png"
	var img = Image.load_from_file(ProjectSettings.globalize_path(p))
	img.convert(Image.FORMAT_L8)
	var w = img.get_width()
	var h = img.get_height()
	var raw = img.get_data()
	
	var y_to_midi = {}
	for midi in MIDI_TO_Y:
		y_to_midi[MIDI_TO_Y[midi]] = midi
	
	var ink = PackedByteArray()
	ink.resize(w * h)
	var staff_ys = [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]
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
	
	var barlines = [230, 552, 875, 1197, 1516]
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
				if bw >= 12 and pts.size() >= 50:
					var row_pixels = {}
					var max_rw = 0
					for pt in pts:
						if not row_pixels.has(pt.y):
							row_pixels[pt.y] = []
						row_pixels[pt.y].append(pt.x)
					
					for ry in row_pixels:
						var xs = row_pixels[ry]
						xs.sort()
						var rw = xs[-1] - xs[0] + 1
						if rw > max_rw:
							max_rw = rw
					
					# Find rows with width near max_rw (within 4px of max)
					var peak_ys = []
					for ry in row_pixels:
						var xs = row_pixels[ry]
						xs.sort()
						var rw = xs[-1] - xs[0] + 1
						if rw >= max_rw - 4 and rw >= 14:
							peak_ys.append(ry)
					
					if not peak_ys.is_empty():
						peak_ys.sort()
						var yc = peak_ys[peak_ys.size() / 2]
						var xs_at_yc = row_pixels[yc]
						xs_at_yc.sort()
						var xc = (xs_at_yc[0] + xs_at_yc[-1]) / 2.0
						var round_yc = round((yc - 300) / 10.0) * 10.0 + 300
						var pitch_midi = y_to_midi.get(int(round_yc), -1)
						detected_notes.append({"xc": xc, "yc": yc, "round_yc": round_yc, "pitch_midi": pitch_midi})
	
	detected_notes.sort_custom(func(a, b): return a.xc < b.xc)
	var gt_path = "res://assets/test_pieces/piece_1_monophonic/ground_truth.json"
	var f = FileAccess.open(gt_path, FileAccess.READ)
	var gt_json = JSON.parse_string(f.get_as_text())
	var gt_notes = gt_json["notes"]
	var matches = 0
	for i in range(mini(detected_notes.size(), gt_notes.size())):
		var det = detected_notes[i]
		var gt = gt_notes[i]
		var match_pitch = (det.pitch_midi == gt.pitch_midi)
		if match_pitch: matches += 1
		print("  Note ", i+1, " Det MIDI: ", det.pitch_midi, " GT MIDI: ", gt.pitch_midi, " MATCH: ", match_pitch)
	print("TOTAL MATCHES: ", matches, " / ", gt_notes.size(), " (", float(matches) / gt_notes.size() * 100.0, "%)")
	quit(0)
