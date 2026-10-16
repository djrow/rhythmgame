extends SceneTree

const OMRProcessorScript = preload("res://scripts/omr_processor.gd")

func _init() -> void:
	print("--- Running Adversarial Test on GDScript OMRProcessor ---")
	var orig_path = "res://assets/test_pieces/piece_1_monophonic/score.png"
	var img = Image.load_from_file(ProjectSettings.globalize_path(orig_path))
	if img == null:
		printerr("Failed to load image")
		quit(1)
		return

	img.convert(Image.FORMAT_L8)
	var chart1 = OMRProcessorScript.process_image_data(img, orig_path, {"bpm": 120.0, "time_signature": [4, 4]})
	var count1 = chart1.get("notes", []).size()
	print("Original GDScript OMR detected note count: %d" % count1)
	if count1 != 15:
		printerr("Expected 15 original notes, got %d" % count1)
		quit(1)
		return

	# Draw an extra notehead at X=700, Y=360 (B4, MIDI 71)
	# Draw filled ellipse of black pixels (value 0)
	var rx = 10
	var ry = 7
	var cx = 700
	var cy = 360
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var dx = float(x - cx) / float(rx)
			var dy = float(y - cy) / float(ry)
			if (dx * dx + dy * dy) <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 1))

	# Draw stem: X = 709, from Y = 290 to Y = 360
	for y in range(290, 361):
		img.set_pixel(709, y, Color(0, 0, 0, 1))
		img.set_pixel(710, y, Color(0, 0, 0, 1))

	var chart2 = OMRProcessorScript.process_image_data(img, "perturbed_score.png", {"bpm": 120.0, "time_signature": [4, 4]})
	var notes2: Array = chart2.get("notes", [])
	var count2 = notes2.size()
	print("Perturbed GDScript OMR detected note count: %d" % count2)

	var b4_notes: Array = []
	for n in notes2:
		if n.get("pitch_midi") == 71:
			b4_notes.append(n)

	print("Detected B4 notes: %d" % b4_notes.size())
	if b4_notes.size() > 0:
		print("New B4 note details: %s" % str(b4_notes[0]))

	if count2 == 16 and b4_notes.size() == 1:
		print("GDScript OMRProcessor adversarial perturbation test PASSED cleanly!")
		quit(0)
	else:
		printerr("Adversarial test failed! Expected 16 notes and 1 B4 note, got count=%d, b4_count=%d" % [count2, b4_notes.size()])
		quit(1)
