# .agents/teamwork/m4_reviewer_1/test_edge_cases.gd
extends SceneTree

const LevelLoaderScript = preload("res://scripts/level_loader.gd")
const OMRProcessorScript = preload("res://scripts/omr_processor.gd")

func _init() -> void:
	print("--- Running Edge Case Tests for LevelLoader and OMRProcessor ---")
	var loader = LevelLoaderScript.new()

	var dummy_chart_long = {
		"bpm": 120.0,
		"time_signature": [4, 4],
		"notes": [
			{"pitch_midi": 60, "time_sec": 30.0, "duration_sec": 1.0}
		]
	}
	var real_audio = loader.load_audio_stream("res://assets/test_pieces/piece_1_monophonic/audio.wav")
	var align_res = loader.align_level(dummy_chart_long, real_audio)
	print("Real audio duration: ", real_audio.get_length())
	print("Chart duration: ", align_res["chart_duration"])
	print("Exceeding chart is_aligned == false: ", align_res["is_aligned"] == false)

	quit(0)
