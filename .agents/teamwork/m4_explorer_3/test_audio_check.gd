extends SceneTree

func _init() -> void:
	print("Checking AudioStreamOggVorbis and AudioStreamMP3 APIs...")
	
	# Check AudioStreamOggVorbis
	var ogg_has_load = ClassDB.class_has_method("AudioStreamOggVorbis", "load_from_buffer")
	print("AudioStreamOggVorbis has load_from_buffer: ", ogg_has_load)
	
	# Check AudioStreamMP3
	var mp3 = AudioStreamMP3.new()
	print("AudioStreamMP3 created: ", mp3 != null)
	mp3.data = PackedByteArray([0, 1, 2, 3])
	print("AudioStreamMP3 data assigned: ", mp3.data.size())
	
	quit(0)
