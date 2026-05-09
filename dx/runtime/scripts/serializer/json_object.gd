class_name DX_JsonObject
extends RefCounted

## 重写此方法返回配置字典，格式：
## { "属性名": { "ignore"=bool, "json_name"=String } }
func _get_serialize_config() -> Dictionary:
	var config := {}
	if has_method("_get_save_ignored_fields"):
		for prop_name in call("_get_save_ignored_fields"):
			config[str(prop_name)] = {"ignore": true}
	return config
