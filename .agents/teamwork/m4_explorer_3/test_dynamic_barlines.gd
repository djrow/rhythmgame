extends SceneTree

func _init() -> void:
	print("Checking dynamic barline detection on all 3 pieces...")
	var paths = [
		"res://assets/test_pieces/piece_1_monophonic/score.png",
		"res://assets/test_pieces/piece_2_harmony/score.png",
		"res://assets/test_pieces/piece_3_polyphonic/score.png"
	]
	
	for p in paths:
		var img = Image.load_from_file(ProjectSettings.globalize_path(p))
		img.convert(Image.FORMAT_L8)
		var w = img.get_width()
		var h = img.get_height()
		var raw = img.get_data()
		
		var staff_set = {320: true, 340: true, 360: true, 380: true, 400: true, 440: true, 460: true, 480: true, 500: true, 520: true}
		var non_staff_ys = []
		for y in range(320, 521):
			if not staff_set.has(y):
				non_staff_ys.append(y)
		
		var barlines = []
		for x in range(200, w - 50):
			var count = 0
			for y in non_staff_ys:
				if raw[y * w + x] < 128:
					count += 1
			if count >= non_staff_ys.size() - 5:
				if barlines.is_empty() or x - barlines[-1] > 20:
					barlines.append(x)
		
		print(p, " -> Detected barlines (", barlines.size(), "): ", barlines, " -> Measures: ", barlines.size() - 1)
	
	quit(0)
