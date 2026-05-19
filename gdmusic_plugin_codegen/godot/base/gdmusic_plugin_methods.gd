class_name GDMusicPluginMethods
extends GDMusicPluginBase

func search(query: String, page: int, media_type: String) -> Dictionary:
	push_warning("%s.search() is not implemented." % get_platform())
	return {"isEnd": true, "data": []}

func get_media_source(music_item: Dictionary, quality: String) -> Dictionary:
	push_warning("%s.get_media_source() is not implemented." % get_platform())
	return {}

func get_music_info(media_base: Dictionary) -> Dictionary:
	push_warning("%s.get_music_info() is not implemented." % get_platform())
	return {}

func get_lyric(music_item: Dictionary) -> Dictionary:
	push_warning("%s.get_lyric() is not implemented." % get_platform())
	return {}

func get_album_info(album_item: Dictionary, page: int) -> Dictionary:
	push_warning("%s.get_album_info() is not implemented." % get_platform())
	return {}

func get_artist_works(artist_item: Dictionary, page: int, media_type: String) -> Dictionary:
	push_warning("%s.get_artist_works() is not implemented." % get_platform())
	return {"isEnd": true, "data": []}

func import_music_sheet(url_like: String) -> Array:
	push_warning("%s.import_music_sheet() is not implemented." % get_platform())
	return []

func import_music_item(url_like: String) -> Dictionary:
	push_warning("%s.import_music_item() is not implemented." % get_platform())
	return {}

func get_toplists() -> Array:
	push_warning("%s.get_toplists() is not implemented." % get_platform())
	return []

func get_toplist_detail(toplist_item: Dictionary) -> Dictionary:
	push_warning("%s.get_toplist_detail() is not implemented." % get_platform())
	return {}
