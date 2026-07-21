class_name MusicAppLyricParser
extends RefCounted

const TIMESTAMP_PATTERN := "\\[(\\d+):(\\d+(?:\\.\\d+)?)\\]"

static func parse(text: String) -> Array[Dictionary]:
	var timestamp_regex := RegEx.new()
	if timestamp_regex.compile(TIMESTAMP_PATTERN) != OK:
		return []

	var lines: Array[Dictionary] = []
	for raw_line_value in text.replace("\r\n", "\n").replace("\r", "\n").split("\n", true):
		var raw_line := str(raw_line_value)
		var matches := timestamp_regex.search_all(raw_line)
		if matches.is_empty():
			var plain_text := raw_line.strip_edges()
			if _is_lrc_metadata(plain_text):
				continue
			if not plain_text.is_empty():
				lines.append({"time": -1, "text": plain_text})
			continue

		var lyric_text := raw_line.substr(matches[matches.size() - 1].get_end()).strip_edges()
		if lyric_text.is_empty():
			continue
		for timestamp_match in matches:
			var minutes := str(timestamp_match.get_string(1)).to_int()
			var seconds := str(timestamp_match.get_string(2)).to_float()
			lines.append({
				"time": maxi(0, int(float(minutes * 60) + seconds)),
				"text": lyric_text
			})
	return lines

static func _is_lrc_metadata(text: String) -> bool:
	if not text.begins_with("["):
		return false
	var closing_bracket := text.find("]")
	if closing_bracket <= 1:
		return false
	return text.substr(1, closing_bracket - 1).contains(":")
