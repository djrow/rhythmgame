extends SceneTree

func _init() -> void:
	print("Checking barline and notehead detection on piece_1_monophonic...")
	var p = "res://assets/test_pieces/piece_1_monophonic/score.png"
	var img = Image.load_from_file(ProjectSettings.globalize_path(p))
	img.convert(Image.FORMAT_L8)
	var w = img.get_width()
	var h = img.get_height()
	var raw = img.get_data()
	
	# Vertical profile between Y=320 and Y=520 (excluding staff lines 320, 340, 360, 380, 400, 440, 460, 480, 500, 520)
	# A barline will have dark pixels at non-staff rows between 320 and 520!
	var non_staff_ys = []
	var staff_set = {320: true, 340: true, 360: true, 380: true, 400: true, 440: true, 460: true, 480: true, 500: true, 520: true}
	for y in range(320, 521):
		if not staff_set.has(y):
			non_staff_ys.append(y)
	
	# Detect columns where vertical continuity spans from 320 to 520
	var col_counts = PackedInt32Array()
	col_counts.resize(w)
	var barlines = []
	for x in range(200, w - 50):
		var count = 0
		for y in non_staff_ys:
			if raw[y * w + x] < 128:
				count += 1
		col_counts[x] = count
		if count >= non_staff_ys.size() - 5: # Nearly solid vertical barline
			if barlines.is_empty() or x - barlines[-1] > 20:
				barlines.append(x)
	
	print("Detected barlines: ", barlines)
	quit(0)
