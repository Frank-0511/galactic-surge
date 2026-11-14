# settings.gd
# Local persistence for player settings (Etapa 19): audio levels in dB and
# display options. Static API, same pattern as high_score.gd; no autoload.
# Values are read/written under [audio] and [display] in user://settings.cfg.

extends RefCounted

const DEFAULT_PATH := "user://settings.cfg"


static func default_values() -> Dictionary:
	return {
		"master_db": 0.0,
		"music_db": 0.0,
		"sfx_db": 0.0,
		"fullscreen": false,
		"vsync": true,
	}


# Returns the saved values merged over the defaults. A missing or unreadable
# file yields the defaults and never creates a file.
static func load_settings(path: String = DEFAULT_PATH) -> Dictionary:
	var values: Dictionary = default_values()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return values
	for key: String in ["master_db", "music_db", "sfx_db"]:
		values[key] = float(config.get_value("audio", key, values[key]))
	for key: String in ["fullscreen", "vsync"]:
		values[key] = bool(config.get_value("display", key, values[key]))
	return values


static func save_settings(values: Dictionary, path: String = DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("audio", "master_db", values["master_db"])
	config.set_value("audio", "music_db", values["music_db"])
	config.set_value("audio", "sfx_db", values["sfx_db"])
	config.set_value("display", "fullscreen", values["fullscreen"])
	config.set_value("display", "vsync", values["vsync"])
	return config.save(path)
