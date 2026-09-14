extends RefCounted

## Convert downloaded AAC locally; no URL or credentials are passed to a process.
const TIMEOUT_MSEC := 30000
var last_error := ""

func decode(buffer: PackedByteArray, is_cancelled: Callable) -> AudioStream:
	last_error = ""
	var executable := _find_converter()
	if executable.is_empty():
		last_error = "当前设备缺少 AAC/M4A 解码支持。桌面版可安装 FFmpeg 后重试。"
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or buffer.is_empty() or is_cancelled.call():
		return null
	var directory := OS.get_cache_dir().path_join("gdmusic-audio")
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		last_error = "无法创建音频转换缓存。"
		return null
	var input := directory.path_join("%s-%s.m4a" % [OS.get_process_id(), Time.get_ticks_usec()])
	var output := input + ".wav"
	var file := FileAccess.open(input, FileAccess.WRITE)
	if file == null:
		last_error = "无法写入音频转换缓存。"
		return null
	file.store_buffer(buffer)
	file.close()
	var args := PackedStringArray(["-f", "WAVE", "-d", "LEI16", input, output])
	if executable.get_file() != "afconvert":
		args = PackedStringArray(["-nostdin", "-v", "error", "-y", "-i", input, "-vn", "-ac", "2", "-ar", "44100", "-c:a", "pcm_s16le", output])
	var pid := OS.create_process(executable, args)
	var started := Time.get_ticks_msec()
	var cancelled := false
	var timed_out := false
	if pid > 0:
		while OS.is_process_running(pid):
			cancelled = bool(is_cancelled.call())
			timed_out = Time.get_ticks_msec() - started > TIMEOUT_MSEC
			if cancelled or timed_out:
				OS.kill(pid)
				break
			await tree.create_timer(0.05).timeout
	var stream: AudioStream = null
	if not cancelled and not timed_out and not is_cancelled.call() and FileAccess.file_exists(output):
		stream = _load_pcm_wave(FileAccess.get_file_as_bytes(output))
	DirAccess.remove_absolute(input)
	if FileAccess.file_exists(output):
		DirAccess.remove_absolute(output)
	if stream == null and not cancelled:
		last_error = "AAC/M4A 音频转换失败或超时。"
	return stream

func _load_pcm_wave(bytes: PackedByteArray) -> AudioStream:
	# afconvert writes WAVE_FORMAT_EXTENSIBLE even for 16-bit PCM. Godot's
	# WAV loader accepts the same samples with the ordinary PCM format tag.
	var offset := 12
	while offset + 8 <= bytes.size():
		var size := bytes.decode_u32(offset + 4)
		if size > bytes.size() - offset - 8:
			return null
		if bytes.slice(offset, offset + 4).get_string_from_ascii() == "fmt " and size >= 40:
			var format := offset + 8
			var pcm_guid := PackedByteArray([1, 0, 0, 0, 0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113])
			if bytes.decode_u16(format) == 0xfffe and bytes.slice(format + 24, format + 40) == pcm_guid:
				bytes.encode_u16(format, 1)
			break
		offset += 8 + size + (size % 2)
	return AudioStreamWAV.load_from_buffer(bytes)

func _find_converter() -> String:
	if OS.get_name() == "macOS" and FileAccess.file_exists("/usr/bin/afconvert"):
		return "/usr/bin/afconvert"
	if OS.get_name() not in ["macOS", "Windows", "Linux"]:
		return ""
	var name := "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	var paths := OS.get_environment("PATH").split(";" if OS.get_name() == "Windows" else ":")
	for path in paths:
		if path.is_absolute_path() and FileAccess.file_exists(path.path_join(name)):
			return path.path_join(name)
	return ""
