extends RefCounted

var tr_map := {
	"Anchors Only": {
		"zh": "仅锚点",
	},
	"Change Anchors, Grow Direction": {
		"zh": "更改锚点、增长方向",
	},
}

var translations := {}

func register():
	if translations.is_empty():
		for src in tr_map:
			for locale in tr_map[src]:
				if not translations.has(locale):
					translations[locale] = Translation.new()
					translations[locale].locale = locale
				translations[locale].add_message(src, tr_map[src][locale])

	var domain = Engine.get_singleton("TranslationServer").get_or_add_domain("godot.editor")
	for translation in translations.values():
		domain.add_translation(translation)

func unregister():
	var domain = Engine.get_singleton("TranslationServer").get_or_add_domain("godot.editor")
	for translation in translations.values():
		domain.remove_translation(translation)
	translations.clear()
