class_name MusicAppImmersive3DPlayer
extends Control

const PlaylistDataType := preload("res://scripts/save/music/playlist_data.gd")
const TrackDataType := preload("res://scripts/save/music/track_data.gd")

class DemoSpectrumController:
	extends RefCounted

	signal spectrum_changed(bass: float, mid: float, treble: float, volume: float)
	signal beat_detected(strength: float)
	signal detailed_spectrum_changed(
		kick: float,
		bass: float,
		vocal: float,
		instrument_mid: float,
		treble: float,
		treble_air: float,
		rms: float,
		energy_onset: float
	)

	func push(
		bass: float,
		mid: float,
		treble: float,
		volume: float,
		kick: float,
		vocal: float,
		instrument_mid: float,
		treble_air: float,
		rms: float,
		energy_onset: float
	) -> void:
		spectrum_changed.emit(bass, mid, treble, volume)
		detailed_spectrum_changed.emit(kick, bass, vocal, instrument_mid, treble, treble_air, rms, energy_onset)

	func push_beat(strength: float) -> void:
		beat_detected.emit(strength)

@onready var visualizer: Control = %MusicAppVisualizer
@onready var shelf_dock: Control = %ShelfDock
@onready var playlist_shelf_3d: Control = %PlaylistShelf3D
@onready var hero_title: Label = %HeroTitle
@onready var hero_meta: Label = %HeroMeta
@onready var now_playing_title: Label = %NowPlayingTitle
@onready var now_playing_meta: Label = %NowPlayingMeta
@onready var mode_button: Button = %ModeButton
@onready var shelf_button: Button = %ShelfButton
@onready var play_button: Button = %PlayButton

var _spectrum := DemoSpectrumController.new()
var _tracks: Array[TrackData] = []
var _playlists: Array[PlaylistData] = []
var _selected_playlist_index := 0
var _playing_playlist_index := -1
var _current_track_index := -1
var _elapsed := 0.0
var _beat_timer := 0.0
var _playing := true
var _shelf_open := false
var _mode := "mineradio"
var _quality := "high"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_demo_library()
	_bind()
	_setup_3d_content()
	_select_playlist(0)
	_play_selected_playlist()

func _process(delta: float) -> void:
	_elapsed += delta
	_push_demo_spectrum(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_left"):
		_select_playlist(_selected_playlist_index - 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_select_playlist(_selected_playlist_index + 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_toggle_playback()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_M:
			_toggle_mode()
			get_viewport().set_input_as_handled()
		elif key_event.pressed and not key_event.echo and key_event.keycode == KEY_S:
			_toggle_shelf()
			get_viewport().set_input_as_handled()

func get_playlists() -> Array:
	return _playlists

func get_playlist_display_title(playlist) -> String:
	return playlist.title if playlist != null else ""

func get_playlist_display_mark(playlist) -> String:
	if playlist == null:
		return ""
	if not playlist.mark.is_empty():
		return playlist.mark
	return playlist.title.left(1) if not playlist.title.is_empty() else ""

func format_total_track_count(count: int) -> String:
	return "%d 首" % count

func get_track(track_index: int):
	if track_index < 0 or track_index >= _tracks.size():
		return null
	return _tracks[track_index]

func _bind() -> void:
	playlist_shelf_3d.previous_requested.connect(func(): _select_playlist(_selected_playlist_index - 1))
	playlist_shelf_3d.next_requested.connect(func(): _select_playlist(_selected_playlist_index + 1))
	playlist_shelf_3d.play_requested.connect(_play_selected_playlist)
	playlist_shelf_3d.playlist_selected.connect(_select_playlist)
	mode_button.pressed.connect(_toggle_mode)
	shelf_button.pressed.connect(_toggle_shelf)
	play_button.pressed.connect(_toggle_playback)

func _setup_3d_content() -> void:
	if visualizer.has_method("setup"):
		visualizer.setup(_spectrum)
	_apply_visual_settings()
	if visualizer.has_method("set_playback_active"):
		visualizer.set_playback_active(_playing)

func _apply_visual_settings() -> void:
	var settings := {
		"enabled": true,
		"mode": _mode,
		"quality": _quality,
		"particles": 1.15,
		"bloom": 0.92
	}
	if visualizer.has_method("apply_visualizer_settings"):
		visualizer.apply_visualizer_settings(settings)
	if playlist_shelf_3d.has_method("apply_visualizer_settings"):
		playlist_shelf_3d.apply_visualizer_settings(settings)
	mode_button.text = "City" if _mode == "mineradio" else "Mineradio"
	_apply_shelf_visibility()

func _build_demo_library() -> void:
	_tracks.clear()
	_playlists.clear()

	_add_track("Neon Drift", "Codex FM", "SYNTH", "immersive", 224)
	_add_track("Midnight Bloom", "Godot Stage", "BASS", "immersive", 208)
	_add_track("Glass Orbit", "Mineradio Study", "FLOW", "immersive", 252)
	_add_track("Signal City", "Voxel Club", "CITY", "city", 236)
	_add_track("Afterglow", "Particle Lab", "GLOW", "immersive", 218)
	_add_track("Deep Rail", "Night Shelf", "3D", "city", 241)

	_add_playlist("Mineradio Mix", "M", [0, 1, 2])
	_add_playlist("City Pulse", "C", [3, 5, 1])
	_add_playlist("Glass Shelf", "G", [2, 4, 0])
	_add_playlist("Late Night", "L", [4, 1, 5])
	_add_playlist("All Tracks", "A", [0, 1, 2, 3, 4, 5])

func _add_track(title: String, artist: String, mark: String, source: String, duration: int) -> void:
	var track: TrackData = TrackDataType.new()
	track.title = title
	track.artist = artist
	track.subtitle = "Immersive 3D Demo"
	track.mark = mark
	track.source = source
	track.platform = "immersive"
	track.remote_id = "%s-%d" % [title.to_lower().replace(" ", "_"), _tracks.size()]
	track.duration = duration
	_tracks.append(track)

func _add_playlist(title: String, mark: String, tracks: Array[int]) -> void:
	var playlist: PlaylistData = PlaylistDataType.new()
	playlist.title = title
	playlist.mark = mark
	playlist.tracks = tracks.duplicate()
	playlist.count = tracks.size()
	_playlists.append(playlist)

func _select_playlist(index: int) -> void:
	if _playlists.is_empty():
		return
	var next_index := clampi(index, 0, _playlists.size() - 1)
	if next_index == _selected_playlist_index and _current_track_index >= 0:
		_refresh_shelf()
		return
	_selected_playlist_index = next_index
	_refresh_shelf()
	if visualizer.has_method("trigger_favorite_feedback"):
		visualizer.trigger_favorite_feedback(true, _get_current_track())

func _play_selected_playlist() -> void:
	if _playlists.is_empty():
		return
	var playlist: PlaylistData = _playlists[_selected_playlist_index]
	if playlist.tracks.is_empty():
		return
	_playing_playlist_index = _selected_playlist_index
	_current_track_index = int(playlist.tracks[0])
	_playing = true
	_refresh_shelf()
	_refresh_now_playing()
	if visualizer.has_method("set_playback_active"):
		visualizer.set_playback_active(true)
	if visualizer.has_method("trigger_track_transition"):
		visualizer.trigger_track_transition(_get_current_track())

func _toggle_playback() -> void:
	_playing = not _playing
	play_button.text = "Pause" if _playing else "Play"
	if visualizer.has_method("set_playback_active"):
		visualizer.set_playback_active(_playing)

func _toggle_mode() -> void:
	_mode = "city" if _mode == "mineradio" else "mineradio"
	_apply_visual_settings()
	if visualizer.has_method("trigger_track_transition"):
		visualizer.trigger_track_transition(_get_current_track())

func _toggle_shelf() -> void:
	_shelf_open = not _shelf_open
	_apply_shelf_visibility()

func _apply_shelf_visibility() -> void:
	if shelf_dock == null:
		return
	shelf_dock.visible = _shelf_open
	shelf_button.text = "Close" if _shelf_open else "Shelf"

func _refresh_shelf() -> void:
	playlist_shelf_3d.configure(_playlists, _selected_playlist_index, self, _playing_playlist_index)

func _refresh_now_playing() -> void:
	var playlist: PlaylistData = _playlists[_selected_playlist_index]
	var track: TrackData = _get_current_track()
	var title := track.title if track != null else playlist.title
	var meta := "%s  /  %s" % [
		track.artist if track != null else "3D Stage",
		playlist.title
	]
	hero_title.text = title
	hero_meta.text = meta
	now_playing_title.text = title
	now_playing_meta.text = meta
	play_button.text = "Pause" if _playing else "Play"

func _get_current_track() -> TrackData:
	return get_track(_current_track_index)

func _push_demo_spectrum(delta: float) -> void:
	var activity := 1.0 if _playing else 0.22
	var beat_phase := fposmod(_elapsed * 1.82, 1.0)
	var beat_shape := pow(maxf(0.0, 1.0 - beat_phase * 5.4), 3.0)
	var bass := clampf((0.18 + sin(_elapsed * 3.1) * 0.12 + beat_shape * 0.68) * activity, 0.0, 1.0)
	var vocal := clampf((0.28 + sin(_elapsed * 1.7 + 0.8) * 0.16) * activity, 0.0, 1.0)
	var instrument_mid := clampf((0.24 + sin(_elapsed * 2.35 + 1.6) * 0.18) * activity, 0.0, 1.0)
	var treble := clampf((0.22 + sin(_elapsed * 8.0) * 0.12 + randf() * 0.08) * activity, 0.0, 1.0)
	var treble_air := clampf((0.18 + sin(_elapsed * 5.0 + 2.0) * 0.13 + randf() * 0.06) * activity, 0.0, 1.0)
	var mid := clampf(vocal * 0.55 + instrument_mid * 0.45, 0.0, 1.0)
	var rms := clampf(bass * 0.38 + mid * 0.36 + treble * 0.26, 0.0, 1.0)
	var onset := clampf(beat_shape * 0.95 + maxf(0.0, sin(_elapsed * 9.5)) * 0.08, 0.0, 1.0)
	_spectrum.push(bass, mid, treble, rms, bass, vocal, instrument_mid, treble_air, rms, onset)

	_beat_timer -= delta
	if _playing and _beat_timer <= 0.0:
		_beat_timer = lerpf(0.42, 0.64, randf())
		_spectrum.push_beat(clampf(0.58 + randf() * 0.34, 0.0, 1.0))
