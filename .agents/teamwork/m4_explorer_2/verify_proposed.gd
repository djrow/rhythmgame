@tool
extends SceneTree

func _init() -> void:
	print("Validating proposed_omr_processor.gd...")
	var OMRProc = load("res://.agents/teamwork/m4_explorer_2/proposed_omr_processor.gd")
	if OMRProc == null:
		print("FAILED to load proposed_omr_processor.gd")
		quit(1)
		return
	
	var pieces = [
		{"path": "res://assets/scores/piece_1_monophonic.png", "bpm": 120.0, "ts": [4, 4], "expected": 15},
		{"path": "res://assets/scores/piece_2_harmony.png", "bpm": 100.0, "ts": [3, 4], "expected": 16},
		{"path": "res://assets/scores/piece_3_polyphonic.png", "bpm": 80.0, "ts": [4, 4], "expected": 20}
	]
	
	for p in pieces:
		var chart: Dictionary = OMRProc.process_image(p.path, {
			"bpm": p.bpm,
			"time_signature": p.ts
		})
		var notes: Array = chart.get("notes", [])
		print("Score: ", p.path.get_file(), " -> Detected notes: ", notes.size(), " (expected: ", p.expected, ")")
		assert(notes.size() == p.expected)
		
		# Test NoteData loading
		for n in notes:
			var nd = NoteData.from_dict(n)
			assert(nd != null)
	
	print("SUCCESS: proposed_omr_processor.gd passed all validations!")
	quit(0)
