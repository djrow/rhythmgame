extends SceneTree

func _init() -> void:
	print("--- Testing string path inheritance ---")
	var s = """
class_name TestDriverPreload
extends "res://.agents/teamwork/m3_explorer_1/proposed_audio_pitch_model.gd"

func is_model_ready() -> bool: return true
"""
	var g = GDScript.new()
	g.source_code = s
	var err = g.reload()
	print("Reload with string path: ", err)
	if err == OK:
		var inst = g.new()
		print("Instantiated: ", inst != null, " ready: ", inst.is_model_ready())
	quit(0)
