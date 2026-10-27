extends Node

const Reader := preload("res://assets/scripts/save/music/audio_artwork_reader.gd")

func _ready() -> void:
	var directory := OS.get_environment("ARTWORK_DIR")
	if directory.is_empty():
		directory = "/tmp/artwork_fixtures"
	var files: Array[String] = []
	var handle := DirAccess.open(directory)
	if handle != null:
		for name in handle.get_files():
			if name.begins_with("ft_"):
				files.append(directory.path_join(name))
	files.sort()
	for path in files:
		var artwork: Dictionary = Reader.read_embedded_artwork(path)
		if artwork.is_empty():
			print("FAIL %s -> no artwork" % path.get_file())
			continue
		var data: PackedByteArray = artwork["data"]
		var magic := ""
		if data.size() >= 3 and data[0] == 0xFF and data[1] == 0xD8:
			magic = "jpeg"
		elif data.size() >= 8 and data[0] == 0x89 and data[1] == 0x50:
			magic = "png"
		print("OK   %s -> mime=%s bytes=%d magic=%s" % [path.get_file(), artwork["mime"], data.size(), magic])
	# 没有封面的音频应当返回空
	var plain := directory.path_join("tone_src.mp3")
	print("PLAIN %s -> %s" % [plain.get_file(), "empty(ok)" if Reader.read_embedded_artwork(plain).is_empty() else "unexpected"])
	get_tree().quit()
