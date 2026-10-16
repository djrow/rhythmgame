extends SceneTree

func _init() -> void:
	print("--- Testing Godot Audio Capture Headless ---")
	var bus_count: int = AudioServer.bus_count
	print("Bus count: ", bus_count)
	for i in range(bus_count):
		print("Bus %d: %s, effects: %d, send: %s" % [i, AudioServer.get_bus_name(i), AudioServer.get_bus_effect_count(i), AudioServer.get_bus_send(i)])
	
	var record_idx: int = AudioServer.get_bus_index("Record")
	print("Record bus index: ", record_idx)
	if record_idx != -1:
		var effect_count: int = AudioServer.get_bus_effect_count(record_idx)
		print("Record bus effect count: ", effect_count)
		if effect_count > 0:
			var effect = AudioServer.get_bus_effect(record_idx, 0)
			print("Effect 0 class: ", effect.get_class())
			if effect is AudioEffectCapture:
				print("Effect is AudioEffectCapture! Buffer length: ", effect.buffer_length)
				print("Frames available initially: ", effect.get_frames_available())
	
	var player = AudioStreamPlayer.new()
	var mic = AudioStreamMicrophone.new()
	player.stream = mic
	player.bus = "Record"
	root.add_child(player)
	player.play()
	print("Microphone player playing: ", player.playing)
	
	# Test RMS calculation formula
	var test_samples = PackedFloat32Array()
	# Silence
	test_samples.resize(1024)
	test_samples.fill(0.0)
	var rms_silence = calculate_rms(test_samples)
	print("RMS of silence: ", rms_silence)
	
	# Low noise (amplitude 0.002, below 0.005 threshold)
	for i in range(1024):
		test_samples[i] = 0.002
	var rms_low = calculate_rms(test_samples)
	print("RMS of low noise (0.002): ", rms_low)
	
	# Strong signal (sine wave amplitude 0.5)
	for i in range(1024):
		test_samples[i] = 0.5 * sin(float(i) * 0.1)
	var rms_signal = calculate_rms(test_samples)
	print("RMS of strong signal: ", rms_signal)
	
	quit(0)

func calculate_rms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sum_sq: float = 0.0
	for i in range(samples.size()):
		var s: float = samples[i]
		sum_sq += s * s
	return sqrt(sum_sq / float(samples.size()))
