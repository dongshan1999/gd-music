extends SceneTree

const LyricParserScript := preload("res://scripts/ui/music_app/player/music_app_lyric_parser.gd")

var _failures := PackedStringArray()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var timed_lines := LyricParserScript.parse(
		"[ti:Metadata]\n[00:01.20]First line\n[00:02.00][00:03.50]Repeated line\n"
	)
	_check(timed_lines.size() == 3, "timestamped lyrics should expand repeated timestamps")
	_check(int(timed_lines[0].get("time", -1)) == 1, "fractional timestamps should resolve to seconds")
	_check(str(timed_lines[1].get("text", "")) == "Repeated line", "lyric text should exclude timestamps")
	_check(int(timed_lines[2].get("time", -1)) == 3, "later repeated timestamp should be retained")

	var plain_lines := LyricParserScript.parse("First plain line\n\nSecond plain line")
	_check(plain_lines.size() == 2, "plain text lyrics should preserve non-empty lines")
	_check(int(plain_lines[0].get("time", 0)) == -1, "plain text lyrics should not expose a seek time")

	for failure in _failures:
		push_error(failure)
	print("Music app lyric parser tests: %s failures" % _failures.size())
	quit(OK if _failures.is_empty() else FAILED)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
