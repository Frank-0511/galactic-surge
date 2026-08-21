# main.gd
# Main scene — entry point of the game. Sets up player and game systems.

extends Node2D

## Bullet scene to provide to the player.
var bullet_scene: PackedScene = preload("res://scenes/entities/bullet/bullet.tscn")

@onready var _player: CharacterBody2D = $Player


func _ready() -> void:
	if _player:
		_player.bullet_scene = bullet_scene
