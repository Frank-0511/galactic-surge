# boss_damage.gd
# Damage intake of the Boss: the Núcleo Blindado armor phase (exterior, subcore, exposed core) with
# its exposed-core multiplier, the enrage switch at half health, defeat, and the filter that turns
# player projectiles into damage. Owned by Boss through _boss; health, phase and signals stay on Boss.

extends RefCounted

var _boss: Area2D


func _init(boss: Area2D) -> void:
	_boss = boss


## Returns the Núcleo Blindado phase. Without multi-phase mode the boss stays in the exterior phase.
func get_armor_phase() -> int:
	if not _boss.multi_phase_enabled:
		return _boss.ArmorPhase.EXTERIOR_ARMOR
	return _phase_for_health(_boss.health)


func _phase_for_health(current: int) -> int:
	# Integer comparison avoids float rounding at the exact thresholds.
	if current * 100 <= _boss.max_health * _boss.EXPOSED_CORE_THRESHOLD_PERCENT:
		return _boss.ArmorPhase.EXPOSED_CORE
	if current * 100 <= _boss.max_health * _boss.SUBCORE_THRESHOLD_PERCENT:
		return _boss.ArmorPhase.SUBCORE
	return _boss.ArmorPhase.EXTERIOR_ARMOR


## Applies damage to the boss: exposed-core multiplier, armor phase change, enrage and defeat.
func take_damage(amount: int = 1) -> void:
	if _boss._is_defeated or _boss.replica:
		return
	var applied: int = amount
	if get_armor_phase() == _boss.ArmorPhase.EXPOSED_CORE:
		applied = int(round(float(amount) * _boss.EXPOSED_CORE_DAMAGE_MULTIPLIER))
	_boss.health = maxi(0, _boss.health - applied)
	_boss.current_health = _boss.health
	_boss._hit_flash_time = 0.12

	var new_phase: int = get_armor_phase()
	if new_phase != _boss._armor_phase:
		_boss._armor_phase = new_phase
		_boss.armor_phase_changed.emit(new_phase)

	if _boss.health <= (_boss.max_health / 2) and not _boss.is_enraged:
		_boss.is_enraged = true
		if _boss._shoot_timer != null:
			_boss._shoot_timer.wait_time = 0.5
		_boss._dive_cooldown = minf(_boss._dive_cooldown, 3.0)

	_boss.health_changed.emit(_boss.health, _boss.max_health)
	_boss.queue_redraw()

	if _boss.health == 0:
		_boss._is_defeated = true
		if _boss._shoot_timer != null:
			_boss._shoot_timer.stop()
		_boss.boss_defeated.emit(_boss)
		_boss.queue_free()


## Area contact: player projectiles that are not beams and have not hit yet deal their damage once.
func on_area_entered(area: Area2D) -> void:
	if _boss._is_defeated or _boss.replica:
		return
	if area.has_method(&"is_beam") and area.call(&"is_beam"):
		return
	# Player bullet layer is 2
	if (area.collision_layer & 2) != 0 or area.is_in_group(&"player_bullets"):
		if area.get("damage_applied") == true:
			return
		if "damage_applied" in area:
			area.set("damage_applied", true)
		var damage_amount: int = 1
		if "damage" in area and area.damage != null:
			damage_amount = int(area.damage)
		elif area.get("damage") != null:
			damage_amount = int(area.get("damage"))
		elif area.has_meta(&"damage"):
			damage_amount = int(area.get_meta(&"damage"))
		take_damage(damage_amount)
