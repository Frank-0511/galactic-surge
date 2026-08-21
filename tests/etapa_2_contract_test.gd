extends SceneTree

func _init() -> void:
	var passed: bool = true
	passed = _assert_scene("res://scenes/entities/enemy/enemy.tscn") and passed
	passed = _assert_scene("res://scenes/entities/enemy/enemy_bullet.tscn") and passed
	passed = _assert_scene("res://scenes/systems/enemy_spawner.tscn") and passed
	passed = _assert_scene("res://scenes/ui/game_over.tscn") and passed
	quit(0 if passed else 1)

func _assert_scene(path: String) -> bool:
	if load(path) == null:
		push_error("Missing scene: %s" % path)
		return false
	return true
