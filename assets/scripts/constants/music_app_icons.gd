class_name MusicAppIcons
extends RefCounted

const ARROW_LEFT := preload("res://assets/textures/arrow-left.svg")
const SHARE := preload("res://assets/textures/share.svg")
const SEARCH := preload("res://assets/textures/magnifying-glass.svg")
const MENU := preload("res://assets/textures/bars-3.svg")
const MORE := preload("res://assets/textures/ellipsis-vertical.svg")
const PLUS := preload("res://assets/textures/plus.svg")
const DOWNLOAD := preload("res://assets/textures/arrow-down-tray.svg")
const PLAY := preload("res://assets/textures/play.svg")
const PAUSE := preload("res://assets/textures/pause.svg")
const SHUFFLE := preload("res://assets/textures/shuffle.svg")
const LOOP_ALL := preload("res://assets/textures/arrow-path.svg")
const REPEAT_ONE := preload("res://assets/textures/repeat-song-1.svg")
const SKIP_LEFT := preload("res://assets/textures/skip-left.svg")
const SKIP_RIGHT := preload("res://assets/textures/skip-right.svg")
const PLAYLIST := preload("res://assets/textures/playlist.svg")
const MUSICAL_NOTE := preload("res://assets/textures/musical-note.svg")
const HEART_OUTLINE := preload("res://assets/textures/heart-outline.svg")
const HEART_FILLED := preload("res://assets/textures/heart.svg")
const COMMENT := preload("res://assets/textures/chat-bubble-oval-left-ellipsis.svg")
const TONE := preload("res://assets/textures/cog-8-tooth.svg")
const FOLDER := preload("res://assets/textures/folder-outline.svg")
const FOLDER_MUSIC := preload("res://assets/textures/folder-music-outline.svg")
const CHECKED := preload("res://assets/textures/check-circle.svg")
const UNCHECKED := preload("res://assets/textures/check-circle-outline.svg")
const FIRE := preload("res://assets/textures/fire-outline.svg")
const TROPHY := preload("res://assets/textures/trophy.svg")
const CLOCK := preload("res://assets/textures/clock-outline.svg")
const EDIT := preload("res://assets/textures/pencil-square.svg")
const ALBUM := preload("res://assets/textures/album-outline.svg")
const TRASH := preload("res://assets/textures/trash-outline.svg")
const X_MARK := preload("res://assets/textures/x-mark.svg")

static func apply_icon_button(
	button: Button,
	icon: Texture2D,
	keep_text: bool = false,
	expand_icon: bool = true
) -> void:
	if button == null:
		return
	button.icon = icon
	button.expand_icon = expand_icon
	if not keep_text:
		button.text = ""
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
