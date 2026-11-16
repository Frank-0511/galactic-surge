# high_score.gd
# Persists the player's best score locally so it survives between sessions.

extends RefCounted

const _SAVE_PATH: String = "user://highscore.cfg"
const _SECTION: String = "score"
const _KEY: String = "best"


## Reads the stored best score, or 0 if none has been saved yet.
static func load_value() -> int:
	var config: ConfigFile = ConfigFile.new()
	if config.load(_SAVE_PATH) != OK:
		return 0
	return int(config.get_value(_SECTION, _KEY, 0))


## Persists a new best score to disk.
static func save_value(value: int) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(_SAVE_PATH) # Preserve any other keys already in the file.
	config.set_value(_SECTION, _KEY, value)
	config.save(_SAVE_PATH)
