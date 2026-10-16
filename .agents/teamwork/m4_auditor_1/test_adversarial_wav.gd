extends SceneTree

const LevelLoaderScript = preload("res://scripts/level_loader.gd")

func _init() -> void:
	print("--- Running Adversarial Verification on LevelLoader RIFF WAV Decoder ---")
	var loader = LevelLoaderScript.new()

	# 1. Test synthetic RIFF WAV header (22050 Hz, 8-bit mono, 100 bytes data)
	var buf = PackedByteArray()
	buf.resize(44 + 100)
	# RIFF
	buf[0] = 82; buf[1] = 73; buf[2] = 70; buf[3] = 70 # "RIFF"
	buf.encode_u32(4, 36 + 100) # file size - 8
	buf[8] = 87; buf[9] = 65; buf[10] = 86; buf[11] = 69 # "WAVE"
	# fmt chunk
	buf[12] = 102; buf[13] = 109; buf[14] = 116; buf[15] = 32 # "fmt "
	buf.encode_u32(16, 16) # subchunk1 size
	buf.encode_u16(20, 1) # PCM
	buf.encode_u16(22, 1) # mono (1 channel)
	buf.encode_u32(24, 22050) # mix rate 22050 Hz
	buf.encode_u32(28, 22050) # byte rate
	buf.encode_u16(32, 1) # block align
	buf.encode_u16(34, 8) # bits per sample (8-bit)
	# data chunk
	buf[36] = 100; buf[37] = 97; buf[38] = 116; buf[39] = 97 # "data"
	buf.encode_u32(40, 100) # data length 100 bytes
	for i in range(100):
		buf[44 + i] = (i * 2) % 256

	var wav: AudioStreamWAV = loader._load_wav_from_bytes(buf)
	if wav == null:
		printerr("Failed to decode synthetic WAV")
		quit(1)
		return

	if wav.mix_rate != 22050:
		printerr("Expected mix_rate 22050, got %d" % wav.mix_rate)
		quit(1)
		return

	if wav.format != AudioStreamWAV.FORMAT_8_BITS:
		printerr("Expected FORMAT_8_BITS, got %d" % wav.format)
		quit(1)
		return

	if wav.stereo != false:
		printerr("Expected stereo=false, got true")
		quit(1)
		return

	if wav.data.size() != 100:
		printerr("Expected 100 bytes data, got %d" % wav.data.size())
		quit(1)
		return

	print("Synthetic WAV decoded successfully: mix_rate=%d, format=%d, stereo=%s, data_size=%d" % [wav.mix_rate, wav.format, wav.stereo, wav.data.size()])

	# 2. Test invalid buffer handling
	var bad_buf = PackedByteArray([1, 2, 3, 4, 5])
	var bad_wav = loader._load_wav_from_bytes(bad_buf)
	if bad_wav != null:
		printerr("Expected null for invalid WAV header")
		quit(1)
		return

	print("Invalid buffer properly rejected: null returned")

	loader.free()
	print("LevelLoader RIFF WAV decoder adversarial verification PASSED cleanly!")
	quit(0)
