class_name MusicAppIcons
extends RefCounted

const ARROW_LEFT := preload("res://textures/arrow-left.svg")
const SHARE := preload("res://textures/share.svg")
const SEARCH := preload("res://textures/magnifying-glass.svg")
const MENU := preload("res://textures/bars-3.svg")
const MORE := preload("res://textures/ellipsis-vertical.svg")
const PLUS := preload("res://textures/plus.svg")
const DOWNLOAD := preload("res://textures/arrow-down-tray.svg")
const PLAY := preload("res://textures/play.svg")
const PAUSE := preload("res://textures/pause.svg")
const SHUFFLE := preload("res://textures/shuffle.svg")
const LOOP_ALL := preload("res://textures/arrow-path.svg")
const REPEAT_ONE := preload("res://textures/repeat-song.svg")
const SKIP_LEFT := preload("res://textures/skip-left.svg")
const SKIP_RIGHT := preload("res://textures/skip-right.svg")
const PLAYLIST := preload("res://textures/playlist.svg")
const MUSICAL_NOTE := preload("res://textures/musical-note.svg")
const HEART_OUTLINE := preload("res://textures/heart-outline.svg")
const HEART_FILLED := preload("res://textures/heart.svg")
const COMMENT := preload("res://textures/chat-bubble-oval-left-ellipsis.svg")
const TONE := preload("res://textures/cog-8-tooth.svg")
const FOLDER := preload("res://textures/folder-outline.svg")
const FOLDER_MUSIC := preload("res://textures/folder-music-outline.svg")
const CHECKED := preload("res://textures/check-circle.svg")
const UNCHECKED := preload("res://textures/check-circle-outline.svg")
const FIRE := preload("res://textures/fire-outline.svg")
const TROPHY := preload("res://textures/trophy.svg")
const CLOCK := preload("res://textures/clock-outline.svg")
const EDIT := preload("res://textures/pencil-square.svg")
const ALBUM := preload("res://textures/album-outline.svg")
const TRASH := preload("res://textures/trash-outline.svg")
const X_MARK := preload("res://textures/x-mark.svg")

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

static func apply_texture_icon(texture_rect: TextureRect, icon: Texture2D) -> void:
	if texture_rect == null:
		return
	texture_rect.texture = icon
