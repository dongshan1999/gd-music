extends Node

var _failures := PackedStringArray()

func _ready() -> void:
	# Redirect the autoload too: this test must never change the user's library.
	DX.save.save_path = OS.get_cache_dir().path_join("gdmusic-focus-save-test/autoload.json")
	DX.save.data = DX_SaveData.new()
	call_deferred("_run")

func _run() -> void:
	if OS.has_feature("mobile"):
		print("Desktop focus save test skipped on mobile.")
		get_tree().quit()
		return
	var manager := DX_SaveManager.new()
	manager.save_path = OS.get_cache_dir().path_join("gdmusic-focus-save-test/data.json")
	var track := TrackData.new()
	track.id = "background-playback-test"
	track.title = "Before focus loss"
	track.duration = 10
	manager.data.music.tracks.append(track)
	var state: MusicAppPlaybackStateData = manager.data.music.playback_state
	state.track_ids.append(track.id)
	state.selected_track_id = track.id
	state.is_playing = true
	state.elapsed_seconds = 1
	_check(manager.save(), "Initial save succeeds")
	var saved_bytes := FileAccess.get_file_as_bytes(manager.save_path)
	track.title = "After focus loss"
	manager.save(false)
	var deadline: int = manager._next_save_at_msec
	for i in 5:
		manager.in_focus(false)
		manager.in_focus(true)

	_check(FileAccess.get_file_as_bytes(manager.save_path) == saved_bytes, "Desktop focus changes do not rewrite the save")
	_check(manager._is_dirty and manager._next_save_at_msec == deadline, "Focus changes preserve pending autosave and its deadline")
	_check(state.is_playing and state.elapsed_seconds == 1, "Focus changes preserve app playback state")
	manager._next_save_at_msec = Time.get_ticks_msec()
	manager.in_process(0.0)
	var reloaded := DX_SaveManager.new()
	reloaded.save_path = manager.save_path
	reloaded.load()
	_check(reloaded.data.music.tracks[0].title == track.title and not manager._is_dirty, "Scheduled autosave still persists edits")
	state.elapsed_seconds = 2
	manager.in_pause(true)
	reloaded.load()
	_check(reloaded.data.music.playback_state.elapsed_seconds == 2, "System pause still saves immediately")
	state.elapsed_seconds = 3
	manager.in_quit()
	reloaded.load()
	_check(reloaded.data.music.playback_state.elapsed_seconds == 3, "Quit still saves immediately")
	for failure in _failures:
		push_error(failure)
	print("Music app focus save tests: %s failures" % _failures.size())
	get_tree().quit(OK if _failures.is_empty() else FAILED)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
