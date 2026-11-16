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


static func window_mode_for(fullscreen: bool) -> DisplayServer.WindowMode:
	return DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED


static func vsync_mode_for(vsync: bool) -> DisplayServer.VSyncMode:
	return DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED


# Applies the dB levels to the Master, Music and SFX buses (buses come from default_bus_layout.tres).
static func apply_audio(values: Dictionary) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), values["master_db"])
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), values["music_db"])
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), values["sfx_db"])


# Applies display options to the running window. Called once at startup.
static func apply_display(values: Dictionary) -> void:
	DisplayServer.window_set_mode(window_mode_for(values["fullscreen"]))
	DisplayServer.window_set_vsync_mode(vsync_mode_for(values["vsync"]))


static func save_settings(values: Dictionary, path: String = DEFAULT_PATH) -> Error:
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("audio", "master_db", values["master_db"])
	config.set_value("audio", "music_db", values["music_db"])
	config.set_value("audio", "sfx_db", values["sfx_db"])
	config.set_value("display", "fullscreen", values["fullscreen"])
	config.set_value("display", "vsync", values["vsync"])
	return config.save(path)
