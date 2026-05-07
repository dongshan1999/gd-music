extends RefCounted

enum PopupId {
	COMMON_DIALOG,
}

const POPUP_SCENES := {
	PopupId.COMMON_DIALOG: preload("res://scenes/popup/common_dialog_popup.tscn"),
}

static func has_popup(popup_id: int) -> bool:
	return POPUP_SCENES.has(popup_id)

static func get_scene(popup_id: int) -> PackedScene:
	if not POPUP_SCENES.has(popup_id):
		return null
	return POPUP_SCENES[popup_id] as PackedScene
