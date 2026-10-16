extends SceneTree

func _init() -> void:
	print("Inspecting score images with Godot Image class...")
	var paths = [
		"res://assets/test_pieces/piece_1_monophonic/score.png",
		"res://assets/test_pieces/piece_2_harmony/score.png",
		"res://assets/test_pieces/piece_3_polyphonic/score.png"
	]
	
	for p in paths:
		var img = Image.load_from_file(ProjectSettings.globalize_path(p))
		if img:
			print("Loaded: ", p, " Size: ", img.get_width(), "x", img.get_height(), " Format: ", img.get_format())
			img.convert(Image.FORMAT_L8)
			var w = img.get_width()
			var h = img.get_height()
			var raw = img.get_data()
			
			# Horizontal projection
			var h_proj = PackedInt32Array()
			h_proj.resize(h)
			for y in range(h):
				var dark_count = 0
				var row_off = y * w
				for x in range(w):
					if raw[row_off + x] < 128:
						dark_count += 1
				h_proj[y] = dark_count
			
			# Find lines with dark_count > 0.4 * w
			var lines = []
			for y in range(h):
				if h_proj[y] > 0.4 * w:
					lines.append(y)
			print("  Staff lines detected (row sum > 0.4*w): ", lines)
		else:
			print("Failed to load: ", p)
	
	quit(0)
