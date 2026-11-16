class_name PhysicsSafe
extends RefCounted
# Physics-safe node insertion. Inside an Area2D/Body collision handler (an asteroid was hit, the player died),
# adding a node with a CollisionShape2D to the tree fails with "Can't change this state while flushing queries".
# Handlers mark themselves with begin_callback()/end_callback(); insertions made inside them are queued.
# Outside handlers the call is immediate, so spawn timing in tests and elsewhere does not change.

static var _callback_depth: int = 0


static func begin_callback() -> void:
	_callback_depth += 1


static func end_callback() -> void:
	_callback_depth = maxi(_callback_depth - 1, 0)


static func add_child_safe(parent: Node, child: Node) -> void:
	if _callback_depth > 0:
		parent.add_child.call_deferred(child)
	else:
		parent.add_child(child)


static func set_global_position_safe(node: Node2D, position: Vector2) -> void:
	if _callback_depth > 0:
		node.set_deferred(&"global_position", position)
	else:
		node.global_position = position
