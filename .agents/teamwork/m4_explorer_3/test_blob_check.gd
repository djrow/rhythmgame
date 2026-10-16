extends SceneTree

const MIDI_TO_Y = {
	81: 300, 79: 310, 77: 320, 76: 330, 74: 340, 72: 350, 71: 360, 69: 370, 67: 380, 65: 390, 64: 400,
	62: 410, 60: 420, 59: 430, 57: 440, 55: 450, 53: 460, 52: 470, 50: 480, 48: 490, 47: 500, 45: 510,
	43: 520, 41: 530, 40: 540, 38: 550, 36: 560
}

func _init() -> void:
	print("Checking notehead extraction on piece_1_monophonic...")
	var p = "res://assets/test_pieces/piece_1_monophonic/score.png"
	var img = Image.load_from_file(ProjectSettings.globalize_path(p))
	img.convert(Image.FORMAT_L8)
	var w = img.get_width()
	var h = img.get_height()
	var raw = img.get_data()
	
	# Invert Y map: Y to MIDI
	var y_to_midi = {}
	for midi in MIDI_TO_Y:
		var y = MIDI_TO_Y[midi]
		y_to_midi[y] = midi
	
	# Detect noteheads by looking at dense ink clusters (width 12-24, height 8-16)
	# Connected component labeling or window scanning:
	# Since noteheads have width ~20 and height ~14, in non-staff areas or when staff lines are subtracted.
	# Let's test a simple connected component / flood-fill or blob detector on ink pixels:
	# Erase pure staff lines:
	var ink = PackedByteArray()
	ink.resize(w * h)
	var staff_ys = [320, 340, 360, 380, 400, 440, 460, 480, 500, 520]
	var staff_set = {}
	for sy in staff_ys: staff_set[sy] = true
	
	# Mark ink: dark pixel
	for i in range(w * h):
		ink[i] = 1 if raw[i] < 128 else 0
	
	# For staff lines: a pure staff line pixel has no ink above (y-2) and no ink below (y+2)
	# If y in staff_ys, only keep if vertical run around y is > 3
	for sy in staff_ys:
		for x in range(w):
			if ink[sy * w + x] == 1:
				var v_run = 0
				for dy in range(-2, 3):
					var cy = sy + dy
					if cy >= 0 and cy < h and raw[cy * w + x] < 128:
						v_run += 1
				if v_run <= 2:
					ink[sy * w + x] = 0 # Erase isolated staff pixel
	
	# Also erase vertical barlines:
	var barlines = [230, 552, 875, 1197, 1516]
	for bx in barlines:
		for dx in range(-4, 5):
			var cx = bx + dx
			if cx >= 0 and cx < w:
				for y in range(300, 540):
					ink[y * w + cx] = 0
	
	# Also erase clef and time sig region: x < 230
	for y in range(h):
		for x in range(230):
			ink[y * w + x] = 0
	
	# Now find connected components of remaining ink (noteheads + stems)
	# Noteheads have high horizontal thickness (e.g. 10 to 22 pixels across)
	# Stems are only 2 pixels wide!
	# So a morphological horizontal filter or bounding box analysis:
	var visited = PackedByteArray()
	visited.resize(w * h)
	
	var blobs = []
	for y in range(280, 580):
		for x in range(230, 1520):
			if ink[y * w + x] == 1 and visited[y * w + x] == 0:
				# Flood fill BFS
				var q = [Vector2i(x, y)]
				visited[y * w + x] = 1
				var min_x = x; var max_x = x; var min_y = y; var max_y = y
				var sum_x = 0; var sum_y = 0; var count = 0
				var head = 0
				while head < q.size():
					var pt = q[head]
					head += 1
					var px = pt.x; var py = pt.y
					sum_x += px; sum_y += py; count += 1
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
				
				var bw = max_x - min_x + 1
				var bh = max_y - min_y + 1
				# Notehead + stem component typically has width ~18-25 and height ~70-90
				# Or just notehead if stem detached.
				if bw >= 12 and count >= 50:
					blobs.append({"min_x": min_x, "max_x": max_x, "min_y": min_y, "max_y": max_y, "bw": bw, "bh": bh, "count": count, "sum_x": sum_x, "sum_y": sum_y})
	
	print("Found candidate blobs: ", blobs.size())
	for b in blobs:
		print("  Blob: x=[", b.min_x, "..", b.max_x, "] y=[", b.min_y, "..", b.max_y, "] w=", b.bw, " h=", b.bh, " count=", b.count)
	
	quit(0)
