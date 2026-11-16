# structure_contract_test.gd
# Contract test for the feature-based layout (core/, features/, tests/).
# Verifies: every .gd and .tscn lives under core/, features/, tests/ or addons/,
# and the legacy top-level scenes/ and scripts/ folders no longer exist.
extends SceneTree

const ALLOWED_PREFIXES: Array[String] = ["res://core/", "res://features/", "res://tests/", "res://addons/"]
const LEGACY_DIRS: Array[String] = ["res://scenes", "res://scripts"]


func _init() -> void:
	var files: Array[String] = []
	_collect("res://", files)
	var offenders: Array[String] = []
	for path in files:
		if not _is_allowed(path):
			offenders.append(path)
	var legacy: Array[String] = []
	for dir in LEGACY_DIRS:
		if DirAccess.dir_exists_absolute(dir):
			legacy.append(dir)
	var passed := offenders.is_empty() and legacy.is_empty()
	for path in offenders:
		push_error("archivo fuera de core/features/tests: %s" % path)
	for dir in legacy:
		push_error("carpeta legacy presente: %s" % dir)
	print("structure_contract: %s (%d archivos revisados)" % ["PASS" if passed else "FAIL", files.size()])
	quit(0 if passed else 1)


func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not name.begins_with("."):
			var path := dir.path_join(name)
			if d.current_is_dir():
				_collect(path, out)
			elif name.ends_with(".gd") or name.ends_with(".tscn"):
				out.append(path)
		name = d.get_next()
	d.list_dir_end()


func _is_allowed(path: String) -> bool:
	for prefix in ALLOWED_PREFIXES:
		if path.begins_with(prefix):
			return true
	return false
