# Contract harness for Etapa 20: LaserBeam enemy_hit emission per damage tick.
# Verifies that apply_damage_tick() emits enemy_hit once with the target while firing,
# routes damage through take_damage, and stays silent when the beam is not firing.
extends SceneTree

const LASER_BEAM_PATH := "res://features/bullet/laser_beam.tscn"

const FAKE_TARGET_SOURCE := "extends Area2D
var hits := 0
var last := 0.0
func supports_fractional_damage() -> void: pass
func take_damage(a) -> void: hits += 1; last = a
"


func _init() -> void:
	call_deferred("_run_contracts")


func _run_contracts() -> void:
	var passed: bool = _assert_laser_hit_emission_contract()

	if passed:
		print("ETAPA 20 LASER HIT CONTRACT TESTS: ALL PASSED")
	else:
		push_error("ETAPA 20 LASER HIT CONTRACT TESTS: FAILURES DETECTED")
	quit(0 if passed else 1)


# ---------------------------------------------------------------------------
# LaserBeam enemy_hit emission contract
# ---------------------------------------------------------------------------

func _assert_laser_hit_emission_contract() -> bool:
	if not ResourceLoader.exists(LASER_BEAM_PATH):
		push_error("Missing scene: %s" % LASER_BEAM_PATH)
		return false

	var packed: PackedScene = load(LASER_BEAM_PATH) as PackedScene
	var laser = packed.instantiate()
	if laser == null:
		push_error("LaserBeam root must be Area2D")
		return false
	root.add_child(laser)
	laser.is_firing = true

	var script := GDScript.new()
	script.source_code = FAKE_TARGET_SOURCE
	script.reload()
	var target = script.new()
	if target == null or not (target is Area2D):
		push_error("Fake target script must instantiate as Area2D")
		_free_node(laser)
		return false
	root.add_child(target)

	var passed: bool = true

	var emitted: Array[Area2D] = []
	laser.enemy_hit.connect(func(enemy: Area2D) -> void: emitted.append(enemy))

	laser._current_target_enemy = target
	laser._damage.apply_damage_tick()

	if emitted.size() != 1:
		push_error("apply_damage_tick() while firing must emit enemy_hit exactly once, got %d" % emitted.size())
		passed = false
	elif emitted[0] != target:
		push_error("enemy_hit must carry the current target as argument")
		passed = false

	if int(target.hits) != 1:
		push_error("Target take_damage must be called once, got %d" % int(target.hits))
		passed = false

	var expected_amount: float = laser.damage_per_second * laser.damage_tick_rate
	if absf(float(target.last) - expected_amount) > 0.0001:
		push_error("Target must receive damage_per_second * damage_tick_rate = %f, got %f" % [expected_amount, float(target.last)])
		passed = false

	# Not firing: the tick must not damage or emit.
	laser.is_firing = false
	laser._damage.apply_damage_tick()

	if emitted.size() != 1:
		push_error("apply_damage_tick() while not firing must not emit enemy_hit, emissions now %d" % emitted.size())
		passed = false

	_free_node(target)
	_free_node(laser)
	return passed


func _free_node(node: Object) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node and (node as Node).is_inside_tree():
		(node as Node).get_parent().remove_child(node as Node)
	node.free()
