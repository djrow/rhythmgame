extends SceneTree

const OnnxNativeDriverScript = preload("res://scripts/inference/onnx_native_driver.gd")

func _synth_chord(midis: Array, n: int, sr: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t: float = float(i) / sr
		var v: float = 0.0
		for m in midis:
			var f: float = 440.0 * pow(2.0, (float(m) - 69.0) / 12.0)
			v += sin(TAU * f * t) + 0.4 * sin(TAU * 2.0 * f * t) + 0.2 * sin(TAU * 3.0 * f * t)
		out[i] = 0.25 * v / float(midis.size())
	return out

func _init() -> void:
	print("== NATIVE ONNX (nmp.onnx) GDExtension TEST ==")
	var fails: int = 0
	var drv = OnnxNativeDriverScript.new()
	if not drv.is_available():
		printerr("[FAIL] Engine meta 'onnx_pitch_native' missing - GDExtension not loaded")
		quit(1)
		return
	print("[PASS] GDExtension registered native callable")
	if not drv.initialize():
		printerr("[FAIL] ONNX session init failed")
		quit(1)
		return
	print("[PASS] ONNX Runtime session created from in-memory nmp.onnx")

	var win := _synth_chord([60, 64, 67], 43844, 22050.0)
	var t0 := Time.get_ticks_usec()
	var res: Dictionary = drv.transcribe_live_window(win, 0.35, true)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("inference %.1f ms -> ok=%s pitches=%s" % [ms, str(res.get("ok")), str(res.get("active_pitches"))])
	var got: Array = res.get("active_pitches", [])
	for p in [60, 64, 67]:
		if got.has(p):
			print("[PASS] detected MIDI %d" % p)
		else:
			printerr("[FAIL] missing MIDI %d" % p)
			fails += 1

	var silence := PackedFloat32Array()
	silence.resize(43844)
	var res2: Dictionary = drv.transcribe_live_window(silence, 0.35, true)
	if (res2.get("active_pitches", []) as Array).is_empty():
		print("[PASS] silence -> no pitches")
	else:
		printerr("[FAIL] silence produced pitches %s" % str(res2.get("active_pitches")))
		fails += 1

	print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(0 if fails == 0 else 1)
