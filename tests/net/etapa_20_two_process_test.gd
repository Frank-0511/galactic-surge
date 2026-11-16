extends SceneTree
# Two-process check for Etapa 20 (gap item 6): starts a host probe and a client probe as two real Godot
# processes over ENet on localhost (PORT), waits for both with one shared hard deadline (TIMEOUT_MS), kills any
# probe that is still running, then reports every "PROBE" line the probes printed. Both probes start together
# because the host finishes only after the client connects. Scratch files live in a mktemp dir outside the repo,
# removed at the end.

const HOST_PROBE := "res://tests/net/net_probe_host.gd"
const CLIENT_PROBE := "res://tests/net/net_probe_client.gd"
const PORT: int = 7791
const TIMEOUT_MS: int = 60000
const POLL_MS: int = 100
## sh runs Godot with its output and exit code redirected to files; the pid is sh's, its child is killed on timeout.
const LAUNCH_SCRIPT := "\"$1\" --headless --path \"$2\" -s \"$3\" > \"$4\" 2>&1; echo $? > \"$5\""
const SCRATCH_TEMPLATE := "mktemp -d /tmp/net_probe.XXXXXX"

var _failures: int = 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _port_free(PORT):
		print("PROBE runner fail: port %d is busy; stop the process using it and run again" % PORT)
		quit(1)
		return
	var dir: String = _make_temp_dir()
	if dir == "":
		print("PROBE runner fail: could not create a temp dir")
		quit(1)
		return
	var host: Dictionary = _launch(HOST_PROBE, dir, "host")
	var client: Dictionary = _launch(CLIENT_PROBE, dir, "client")
	var started: int = Time.get_ticks_msec()
	for proc: Dictionary in [host, client]:
		if proc["pid"] < 0:
			_fail("%s probe could not start" % proc["role"])
	var pending: Array = [host, client]
	while not pending.is_empty() and Time.get_ticks_msec() - started < TIMEOUT_MS:
		pending = pending.filter(func(p: Dictionary) -> bool: return p["pid"] >= 0 and OS.is_process_running(p["pid"]))
		OS.delay_msec(POLL_MS)
	for proc: Dictionary in [host, client]:
		if proc["pid"] >= 0 and OS.is_process_running(proc["pid"]):
			_kill(proc["pid"])
			_fail("%s probe did not finish within %d s; killed" % [proc["role"], TIMEOUT_MS / 1000])
		elif proc["pid"] >= 0:
			_report(proc)
	_remove_dir(dir)
	print("TWO PROCESS PROBE: %s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
	quit(0 if _failures == 0 else 1)


## Starts one Godot probe through sh; returns its pid and the files it writes.
func _launch(script: String, dir: String, role: String) -> Dictionary:
	var out: String = dir.path_join("%s.out" % role)
	var rc: String = dir.path_join("%s.rc" % role)
	var args: PackedStringArray = ["-c", LAUNCH_SCRIPT, "sh", OS.get_executable_path(), ProjectSettings.globalize_path("res://"), script, out, rc]
	var pid: int = OS.create_process("/bin/sh", args)
	return {"pid": pid, "role": role, "out": out, "rc": rc}


## Prints the PROBE lines of one finished probe and records a failure when it exited non-zero or printed a fail.
func _report(proc: Dictionary) -> void:
	var lines: PackedStringArray = _read_lines(proc["out"])
	var rc_text: String = FileAccess.get_file_as_string(proc["rc"]).strip_edges() if FileAccess.file_exists(proc["rc"]) else ""
	var probe_lines: int = 0
	for line: String in lines:
		if line.begins_with("PROBE "):
			probe_lines += 1
			print(line)
			if line.contains(" fail"):
				_failures += 1
	if probe_lines == 0:
		_fail("%s probe printed no PROBE line (rc=%s)" % [proc["role"], rc_text])
	elif rc_text != "0":
		_fail("%s probe exited with rc=%s" % [proc["role"], rc_text])
	print("PROBE runner %s rc=%s" % [proc["role"], rc_text])


func _read_lines(path: String) -> PackedStringArray:
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	return FileAccess.get_file_as_string(path).split("\n")


func _kill(pid: int) -> void:
	OS.execute("pkill", ["-P", str(pid)])
	OS.kill(pid)


func _fail(reason: String) -> void:
	_failures += 1
	print("PROBE runner fail: %s" % reason)


## True when nothing listens on the UDP port (ENet runs over UDP). ENetMultiplayerPeer.create_server alone can
## succeed on a busy port on macOS, so the port is checked with a plain UDP bind.
func _port_free(port: int) -> bool:
	var udp := PacketPeerUDP.new()
	var err: Error = udp.bind(port, "0.0.0.0")
	udp.close()
	return err == OK


func _make_temp_dir() -> String:
	var out: Array = []
	var code: int = OS.execute("sh", ["-c", SCRATCH_TEMPLATE], out)
	if code != 0 or out.is_empty():
		return ""
	return String(out[0]).strip_edges()


func _remove_dir(dir: String) -> void:
	for role: String in ["host", "client"]:
		for ext: String in [".out", ".rc"]:
			DirAccess.remove_absolute(dir.path_join(role + ext))
	DirAccess.remove_absolute(dir)
