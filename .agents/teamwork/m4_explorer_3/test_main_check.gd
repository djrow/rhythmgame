extends SceneTree

func _init() -> void:
	print("Checking Main integration with LevelLoader...")
	var main_scene = load("res://scenes/main.tscn")
	assert(main_scene != null, "scenes/main.tscn loads")
	var main = main_scene.instantiate()
	assert(main != null, "main.tscn instantiates")
	root.add_child(main)
	
	print("Main initialized with selected_piece: ", main.get("selected_piece"))
	print("Highway active notes count: ", main.highway.chart_notes.size())
	
	# Test switching to piece_2_harmony
	if main.has_method("load_piece"):
		main.load_piece("piece_2_harmony", false)
		print("Switched to piece_2_harmony, chart notes: ", main.highway.chart_notes.size())
	
	main.queue_free()
	print("Main integration check finished [OK]")
	quit(0)
