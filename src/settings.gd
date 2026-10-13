class_name Settings
extends RefCounted
## Tiny persistent settings store (user://settings.cfg).

const PATH := "user://settings.cfg"


static func get_value(key: String, default: Variant = "") -> Variant:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return default
	return cf.get_value("apidya", key, default)


static func set_value(key: String, value: Variant) -> void:
	var cf := ConfigFile.new()
	cf.load(PATH)
	cf.set_value("apidya", key, value)
	cf.save(PATH)
