extends Node
## Autoload singleton (AntiCheat). Loaded from this addon; configure via Resource + optional ProjectSettings.

const _ConfigScript := preload("res://addons/beatrix_anticheat/core/anticheat_config.gd")

signal violation(code: int, detail: String)
signal dev_log_line(text: String)

enum Reaction {
	LOG_ONLY,
	DISABLE_CHECKS,
	QUIT_APP,
	MAIN_SCENE_FAILSAFE,
	MAIN_SCENE_HALT,
}

enum ViolationCode {
	OK = 0,
	DEBUG_BUILD,
	TIME_SKEW,
	NEGATIVE_DELTA,
	DELTA_SPIKE,
	TIMING_PROBE,
	SCENE_TAMPER,
	INPUT_FLOOD,
	PROCESS_TOOL,
	SUSPICIOUS_MODULE,
	INTEGRITY_MISMATCH,
	INVARIANT,
	CMDLINE_TAMPER,
	ENV_TAMPER,
	PHYSICS_DESYNC,
	GROUP_TAMPER,
	TREE_TOO_LARGE,
	MACRO_INPUT,
	USERFILE_TAMPER,
	FOCUS_TIMEOUT,
	LICENSE_ANOMALY,
	DUPLICATE_GUARD,
	RATE_LIMIT,
	CUSTOM_CHECK,
	DEBUGGER_ATTACHED,
	DEBUG_PAUSE,
	DUAL_TIMING_ANOMALY,
	TAMPER_SINGLETON,
	TAMPER_POLICY_FILE,
}

## Return false from `violation_reaction_gate` to skip built-in quit/failsafe (signal still emitted).
var violation_reaction_gate: Callable = Callable()
## Optional: `func() -> String` return empty if OK, else violation detail string.
var custom_periodic_check: Callable = Callable()

var cfg: Resource
var _tick: int = 0
var _accum_engine_ms: float = 0.0
var _boot_wall_ms: int = 0
var _neg_delta_streak: int = 0
var _process_accum_sec: float = 0.0
var _injector_module_accum_sec: float = 0.0
var _checks_disabled_for_dev: bool = false
var _dev_unlocked: bool = false

var _input_bucket: int = 0
var _input_bucket_frame: int = -1
var _macro_last: int = -1
var _macro_streak: int = 0

var _viol_hist: Array[float] = []
var _last_viol_time: Dictionary = {}  # ViolationCode -> msec

var _phys_acc: float = 0.0
var _proc_window_acc: float = 0.0

var _unfocused_since_ms: int = -1
var _session_nonce: String

var _dev_panel_instance: Node
var _last_frame_wall_ms: int = 0

var halt_scene = null

func _ready() -> void:
	_cfg_reload()
	_boot_wall_ms = Time.get_ticks_msec()
	_session_nonce = "%x-%x" % [randi(), Time.get_ticks_usec()]
	_log_dev("AntiCheat session %s — server authority still required for trust." % _session_nonce)
	if _relax_heuristic_antidebug():
		_log_dev(
			"Heuristic anti-debug relaxed (editor-launched run / separate debug window detected)."
		)
	_setup_dev_panel_tree()


func _cfg_reload() -> void:
	cfg = _ConfigScript.new()
	var path := _resolve_config_path()
	if path != "" and ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded and loaded.get_script() == _ConfigScript:
			cfg = loaded
		elif loaded:
			push_warning("BeatrixAC: config at %s is not anticheat_config.gd; using defaults." % path)


func _resolve_config_path() -> String:
	if ProjectSettings.has_setting("beatrix_ac/config_path"):
		var p := str(ProjectSettings.get_setting("beatrix_ac/config_path", "")).strip_edges()
		if p != "":
			return p
	if ResourceLoader.exists("res://addons/beatrix_anticheat/user/ac_config.tres"):
		return "res://addons/beatrix_anticheat/user/ac_config.tres"
	if ResourceLoader.exists("res://addons/beatrix_anticheat/user/example_ac_config.tres"):
		return "res://addons/beatrix_anticheat/user/example_ac_config.tres"
	return ""


## Call after you edit policy `.tres` at runtime or switch profiles.
func apply_policy(next: Resource) -> void:
	if next and next.get_script() == _ConfigScript:
		cfg = next
		_log_dev("AntiCheat policy replaced at runtime.")


func reload_policy_from_disk() -> void:
	_cfg_reload()
	_log_dev("Policy reloaded from disk (respects ProjectSettings beatrix_ac/config_path).")


func get_policy_source_path() -> String:
	return _resolve_config_path()


## Save the in-memory policy Resource to `path` (must be `res://…` for editor builds).
func save_policy_to_path(path: String) -> Error:
	var p: String = path.strip_edges()
	if p.is_empty():
		return ERR_INVALID_PARAMETER
	return ResourceSaver.save(cfg, p)


## Saves to the same path ProjectSettings / fallbacks use for loading.
func save_policy_to_source() -> Error:
	var p: String = get_policy_source_path()
	if p.is_empty():
		return ERR_FILE_BAD_PATH
	return ResourceSaver.save(cfg, p)


func get_session_nonce() -> String:
	return _session_nonce


func _cmdline_suggests_editor_debug_session() -> bool:
	for a: String in OS.get_cmdline_args():
		var low: String = str(a).to_lower()
		if low.contains("remote-debug"):
			return true
		if low.contains("wait-for-debugger"):
			return true
		if low.contains("editor-pid"):
			return true
	return false


func _relax_heuristic_antidebug() -> bool:
	if cfg == null:
		return false
	if not bool(cfg.relax_anti_debug_for_editor_launched_run):
		return false
	return _cmdline_suggests_editor_debug_session()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_unfocused_since_ms = Time.get_ticks_msec()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_unfocused_since_ms = -1


func _physics_process(delta: float) -> void:
	if not cfg.enabled or _checks_disabled_for_dev:
		return
	if cfg.physics_desync_check:
		_phys_acc += delta


func _process(delta: float) -> void:
	if not cfg.enabled or _checks_disabled_for_dev:
		_last_frame_wall_ms = Time.get_ticks_msec()
		return

	var wall_now: int = Time.get_ticks_msec()
	if (
		cfg.anti_debug_focus_pause_check
		and not Engine.is_editor_hint()
		and not _relax_heuristic_antidebug()
	):
		if Engine.get_process_frames() > 90 and _last_frame_wall_ms > 0:
			var gap_ms: int = wall_now - _last_frame_wall_ms
			if gap_ms > int(cfg.anti_debug_focus_pause_max_ms):
				var w: Window = get_window()
				if w != null and w.has_focus():
					notify_violation(
						ViolationCode.DEBUG_PAUSE,
						"Focused process stall ~%d ms (breakpoint/time-screw)." % gap_ms
					)
	_last_frame_wall_ms = wall_now

	_accum_engine_ms += delta * 1000.0
	_proc_window_acc += delta
	_tick += 1

	if cfg.process_scan_enabled:
		_process_accum_sec += delta
	if bool(cfg.injector_module_scan_enabled):
		_injector_module_accum_sec += delta

	var gated: bool = _tick % maxi(1, cfg.check_interval_frames) == 0
	if not gated:
		return

	if cfg.timing_probe_enabled and not _relax_heuristic_antidebug():
		_run_timing_probe()
	if cfg.anti_debug_dual_timing_pairs and not _relax_heuristic_antidebug():
		_run_dual_timing_probe()
	if cfg.anti_debug_os_attached_check and not _relax_heuristic_antidebug():
		_run_os_debugger_attached()
	if custom_periodic_check.is_valid():
		var r: Variant = custom_periodic_check.call()
		if r is String and (r as String).length() > 0:
			notify_violation(ViolationCode.CUSTOM_CHECK, r as String)

	_run_build_meta_guards()
	_run_tamper_guards()
	if cfg.cmdline_scan_enabled:
		_run_cmdline_scan()
	if cfg.env_scan_enabled:
		_run_env_scan()
	if cfg.time_sync_check:
		_run_time_guard()
	_run_negative_and_spike(delta)
	if cfg.physics_desync_check and _tick > 180:
		_run_physics_desync()
	_run_scene_and_group_guards()
	if cfg.max_scene_tree_node_count > 0 and _tick % maxi(120, cfg.check_interval_frames * 4) == 0:
		_run_tree_size_guard()
	if cfg.process_scan_enabled:
		if _process_accum_sec >= cfg.process_scan_interval_sec:
			_process_accum_sec = 0.0
			_run_process_scan()
	if bool(cfg.injector_module_scan_enabled):
		if _injector_module_accum_sec >= float(cfg.injector_module_scan_interval_sec):
			_injector_module_accum_sec = 0.0
			_run_injector_module_scan()
	if cfg.integrity_enabled:
		_run_integrity()
	if cfg.user_data_guard_enabled:
		_run_userdata_guard()
	if cfg.focus_loss_hard_cap_sec > 0.0:
		_run_focus_guard()
	if cfg.macro_detection_enabled:
		_macro_streak = maxi(0, _macro_streak - 1)

	_proc_window_acc = 0.0
	if cfg.physics_desync_check:
		_phys_acc = 0.0


func notify_violation(code: ViolationCode, detail: String) -> void:
	var now: int = Time.get_ticks_msec()
	var key: int = int(code)
	if cfg.violation_cooldown_sec > 0.0 and _last_viol_time.has(key):
		if now - int(_last_viol_time[key]) < int(cfg.violation_cooldown_sec * 1000.0):
			return
	_last_viol_time[key] = now

	_trim_viol_hist(now)
	_viol_hist.append(now as float)
	var ratelimited: bool = _viol_hist.size() > cfg.max_violations_per_minute
	if ratelimited:
		_log_dev("[RATE LIMIT] %d violations / min exceeded." % cfg.max_violations_per_minute)

	violation.emit(int(code), detail)
	_log_dev("[VIOLATION %s] %s" % [_violation_name(code), detail])

	var apply_builtin := true
	if violation_reaction_gate.is_valid():
		var gate: Variant = violation_reaction_gate.call(int(code), detail)
		if gate == false:
			apply_builtin = false

	if ratelimited and cfg.rate_limit_clamps_reaction:
		apply_builtin = false

	if not apply_builtin:
		return

	if ratelimited:
		return

	match int(cfg.reaction_on_violation):
		Reaction.QUIT_APP:
			get_tree().quit(1)
		Reaction.MAIN_SCENE_FAILSAFE:
			var fs: String = str(cfg.failsafe_scene_path)
			if ResourceLoader.exists(fs):
				get_tree().change_scene_to_file(fs)
		Reaction.MAIN_SCENE_HALT:
			if ResourceLoader.exists(cfg.halt_scene_path):
				halt_scene = load(cfg.halt_scene_path).instantiate()
				get_tree().get_root().add_child(halt_scene)
				get_tree().get_root().get_node("/root/"+halt_scene.name).code = detail
				get_tree().get_root().get_node("/root/"+halt_scene.name).set_code()
				queue_free()
		_:
			pass


func _trim_viol_hist(now_ms: int) -> void:
	var cutoff: float = float(now_ms - 60_000)
	var kept: Array[float] = []
	for t: float in _viol_hist:
		if t >= cutoff:
			kept.append(t)
	_viol_hist = kept


func dev_unlock(password: String) -> bool:
	if password == cfg.dev_menu_password:
		_dev_unlocked = true
		return true
	return false


func dev_set_checks_disabled(off: bool) -> void:
	_checks_disabled_for_dev = off
	_log_dev("Checks disabled by dev session: %s" % _checks_disabled_for_dev)


func record_action_event(physical_keycode: int = -1) -> void:
	if not cfg.enabled or not cfg.input_sanity or _checks_disabled_for_dev:
		return
	var f: int = Engine.get_process_frames()
	if _input_bucket_frame != f:
		_input_bucket = 0
		_input_bucket_frame = f
	_input_bucket += 1
	if _input_bucket > cfg.max_actions_per_frame:
		notify_violation(ViolationCode.INPUT_FLOOD, "Input flood > %d / frame" % cfg.max_actions_per_frame)

	if cfg.macro_detection_enabled and physical_keycode >= 0:
		if physical_keycode == _macro_last:
			_macro_streak += 1
		else:
			_macro_streak = 1
			_macro_last = physical_keycode
		if _macro_streak >= cfg.macro_identical_press_threshold:
			notify_violation(ViolationCode.MACRO_INPUT, "Repeated physical key %d streak=%d" % [physical_keycode, _macro_streak])


func is_dev_menu_allowed() -> bool:
	if OS.has_feature("editor") or OS.is_debug_build():
		return true
	if cfg.dev_menu_allow_in_release:
		return true
	return _dev_unlocked


func current_status_text() -> String:
	return (
		"session=%s\nenabled=%s dev_off=%s\neditor=%s debug_os=%s\nskew≈%.0f ms\ntick=%s\nviolations_60s=%s"
		% [
			_session_nonce,
			cfg.enabled,
			_checks_disabled_for_dev,
			Engine.is_editor_hint(),
			OS.is_debug_build(),
			abs(_accum_engine_ms - float(Time.get_ticks_msec() - _boot_wall_ms)),
			_tick,
			_viol_hist.size(),
		]
	)


func _setup_dev_panel_tree() -> void:
	if not bool(cfg.in_game_dev_overlay_enabled):
		return
	var p := str(cfg.dev_panel_scene_path)
	if p != "" and ResourceLoader.exists(p):
		var inst = load(p).instantiate()
		add_child(inst)
		_dev_panel_instance = inst
		return
	if ResourceLoader.exists("res://addons/beatrix_anticheat/ui/dev_ac_panel.tscn"):
		var inst2 = load("res://addons/beatrix_anticheat/ui/dev_ac_panel.tscn").instantiate()
		add_child(inst2)
		_dev_panel_instance = inst2


func _run_build_meta_guards() -> void:
	if Engine.is_editor_hint():
		return
	if cfg.block_debug_in_export and OS.is_debug_build():
		pass
		#notify_violation(ViolationCode.DEBUG_BUILD, "Debug build running outside editor.")
	if cfg.require_release_feature and not OS.has_feature("editor"):
		if not OS.has_feature("release"):
			notify_violation(ViolationCode.INVARIANT, "Expected OS feature tag `release` missing.")
	if cfg.license_baseline_substring.length() > 0:
		var lt: String = Engine.get_license_text()
		if not lt.contains(cfg.license_baseline_substring):
			notify_violation(ViolationCode.LICENSE_ANOMALY, "Engine license text baseline not found.")
	_run_duplicate_autoload_guard()


func _run_duplicate_autoload_guard() -> void:
	var n: int = 0
	for c: Node in get_tree().root.get_children():
		if str(c.name) == "AntiCheat":
			n += 1
	if n > 1:
		notify_violation(ViolationCode.DUPLICATE_GUARD, "Multiple nodes named AntiCheat under root.")


func _run_cmdline_scan() -> void:
	var blob: String = " ".join(PackedStringArray(OS.get_cmdline_args())).to_lower()
	for s: String in cfg.banned_cmdline_substrings:
		if s.is_empty():
			continue
		if blob.find(s.to_lower()) >= 0:
			notify_violation(ViolationCode.CMDLINE_TAMPER, "Arg matched banned substring: %s" % s)
			return


func _run_env_scan() -> void:
	for name: String in cfg.suspicious_env_var_names:
		if name.is_empty():
			continue
		var v: String = OS.get_environment(name)
		if v != "":
			notify_violation(ViolationCode.ENV_TAMPER, "Environment `%s` is set." % name)
			return


func _run_time_guard() -> void:
	var wall: int = Time.get_ticks_msec() - _boot_wall_ms
	var skew: float = abs(_accum_engine_ms - float(wall))
	if skew > cfg.max_tick_skew_ms:
		pass
		#notify_violation(ViolationCode.TIME_SKEW, "Engine vs wall skew: %.1f ms" % skew)


func _run_negative_and_spike(delta: float) -> void:
	if delta < 0.0:
		_neg_delta_streak += 1
		if _neg_delta_streak >= cfg.max_negative_delta_frames:
			notify_violation(ViolationCode.NEGATIVE_DELTA, "Repeated negative delta.")
	else:
		_neg_delta_streak = 0

	var hz: float = DisplayServer.screen_get_refresh_rate()
	if hz <= 0.0:
		hz = 60.0
	var baseline: float = 1.0 / hz
	if delta > baseline * cfg.suspicious_delta_scale:
		notify_violation(ViolationCode.DELTA_SPIKE, "Delta spike: %.4f (baseline %.4f)" % [delta, baseline])


func _run_physics_desync() -> void:
	var pa: float = maxf(_phys_acc, 0.0)
	var pr: float = maxf(_proc_window_acc, 0.0)
	if pa < 0.0001 and pr > 0.05:
		notify_violation(ViolationCode.PHYSICS_DESYNC, "Physics idle while process advanced.")
		return
	var lim: float = float(maxi(cfg.max_physics_process_divisor, 2))
	if pa > 0.0001:
		var ratio: float = pr / pa
		if ratio > lim or ratio < 1.0 / lim:
			notify_violation(ViolationCode.PHYSICS_DESYNC, "Process vs physics Δ ratio %.3f" % ratio)


func _run_timing_probe() -> void:
	var t0: int = Time.get_ticks_usec()
	var x: int = 0
	for i in 50000:
		x += i
	var dt: int = Time.get_ticks_usec() - t0
	if dt > cfg.timing_probe_max_usec:
		notify_violation(ViolationCode.TIMING_PROBE, "Heuristic stall: %d us (dummy %d)" % [dt, x & 1])


func _run_dual_timing_probe() -> void:
	var x1: int = 0
	var t0: int = Time.get_ticks_usec()
	for i in 40000:
		x1 += i
	var dt1: int = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	var x2: int = 0
	for i in 40000:
		x2 += i
	var dt2: int = Time.get_ticks_usec() - t0
	if dt1 <= 0 or dt2 <= 0:
		return
	var hi: int = maxi(dt1, dt2)
	var lo: int = maxi(mini(dt1, dt2), 1)
	var ratio: float = float(hi) / float(lo)
	if (
		ratio > float(cfg.anti_debug_dual_timing_ratio_max)
		and float(hi) > float(cfg.anti_debug_dual_timing_slow_usec)
	):
		notify_violation(
			ViolationCode.DUAL_TIMING_ANOMALY,
			"Dual timing anomaly dt=%d/%d ratio=%.2f (dummy %d)"
			% [dt1, dt2, ratio, (x1 + x2) & 1]
		)


func _run_os_debugger_attached() -> void:
	if Engine.is_editor_hint():
		return
	var sig := Callable(OS, "is_debugger_attached")
	if not sig.is_valid():
		return
	var attached: Variant = sig.call()
	if attached == true:
		notify_violation(ViolationCode.DEBUGGER_ATTACHED, "OS reports a debugger attached.")


func _run_tamper_guards() -> void:
	_run_tamper_singleton_script()
	_run_tamper_policy_file_md5()


func _run_tamper_singleton_script() -> void:
	if Engine.is_editor_hint():
		return
	var sub: String = str(cfg.tamper_singleton_path_substring).strip_edges()
	if sub.is_empty():
		return
	var scr: Script = get_script() as Script
	if scr == null:
		return
	var rp: String = scr.resource_path
	if rp.is_empty():
		return
	if not rp.contains(sub):
		notify_violation(ViolationCode.TAMPER_SINGLETON, "Unexpected singleton script path: %s" % rp)


func _run_tamper_policy_file_md5() -> void:
	if not bool(cfg.tamper_verify_policy_file_md5):
		return
	var expect: String = str(cfg.tamper_expected_policy_md5).strip_edges()
	if expect.length() != 32:
		return
	var path: String = get_policy_source_path()
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var disk: String = FileAccess.get_md5(path)
	if disk.to_lower() != expect.to_lower():
		notify_violation(
			ViolationCode.TAMPER_POLICY_FILE,
			"Policy on-disk MD5 != expected (%s vs %s)" % [disk, expect]
		)


func _run_scene_and_group_guards() -> void:
	var root: Window = get_tree().root
	for raw: String in cfg.scene_sanity_paths:
		var p: String = raw
		if p.begins_with("/root/"):
			p = p.substr("/root/".length())
		var n: Node = root.get_node_or_null(NodePath(p))
		if n == null:
			notify_violation(ViolationCode.SCENE_TAMPER, "Missing required node path: %s" % raw)

	if cfg.guard_group_name != "" and cfg.min_nodes_in_guard_group > 0:
		var gn: StringName = StringName(cfg.guard_group_name)
		var count: int = get_tree().get_nodes_in_group(gn).size()
		if count < cfg.min_nodes_in_guard_group:
			notify_violation(ViolationCode.GROUP_TAMPER, "Group %s count %d < %d" % [gn, count, cfg.min_nodes_in_guard_group])


func _run_tree_size_guard() -> void:
	var n: int = _count_nodes(get_tree().root)
	if n > cfg.max_scene_tree_node_count:
		notify_violation(ViolationCode.TREE_TOO_LARGE, "Scene tree nodes=%d cap=%d" % [n, cfg.max_scene_tree_node_count])


func _count_nodes(n: Node) -> int:
	var t: int = 1
	for ch: Node in n.get_children():
		t += _count_nodes(ch)
	return t


func _run_process_scan() -> void:
	var name: String = OS.get_name()
	if name == "Windows":
		_run_process_scan_windows()
	elif name in PackedStringArray(["Linux", "FreeBSD", "macOS", "Darwin"]):
		if cfg.process_use_unix_ps:
			_run_process_scan_unix()


func _run_process_scan_windows() -> void:
	var out: Array = []
	var code: int = OS.execute("cmd.exe", PackedStringArray(["/c", "tasklist"]), out, true, false)
	if code != OK or out.is_empty():
		return
	_match_process_blob(str(out[0]).to_lower())


func _run_process_scan_unix() -> void:
	var out: Array = []
	var code: int = OS.execute("/bin/sh", PackedStringArray(["-c", "ps aux 2>/dev/null || ps -e"]), out, true, false)
	if code != OK or out.is_empty():
		return
	_match_process_blob(str(out[0]).to_lower())


func _match_process_blob(blob: String) -> void:
	for s: String in cfg.suspicious_process_substrings:
		if s.is_empty():
			continue
		if blob.find(s.to_lower()) >= 0:
			cfg.reaction_on_violation = 4
			notify_violation(ViolationCode.PROCESS_TOOL, "Matched process substring: %s" % s)
			return


func _run_injector_module_scan() -> void:
	if cfg.suspicious_module_substrings.is_empty() && !cfg.use_startup_dll_only:
		return
	var os_id: String = OS.get_name()
	if os_id == "Windows":
		_run_injector_module_windows()
	elif os_id == "Linux":
		_run_injector_module_linux_maps()
	elif os_id in PackedStringArray(["macOS", "Darwin", "FreeBSD"]):
		_run_injector_module_lsof_unix()


func _run_injector_module_windows() -> void:
	var pid: int = OS.get_process_id()
	var ps_cmd: String = (
	    "(Get-Process -Id {pid} -ErrorAction SilentlyContinue).Modules"
		+ " | ForEach-Object { $_.FileName }"
	).format({"pid": pid})
	var out: Array = []
	var code: int = OS.execute(
		"powershell.exe",
		PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", ps_cmd]),
		out,
		true,
		false
	)
	if code != OK or out.is_empty():
		return
	_match_injector_modules_blob(str(out[0]).to_lower())


func _run_injector_module_linux_maps() -> void:
	var f: FileAccess = FileAccess.open("/proc/self/maps", FileAccess.READ)
	if f == null:
		return
	var blob: String = f.get_as_text().to_lower()
	f.close()
	_match_injector_modules_blob(blob)


func _run_injector_module_lsof_unix() -> void:
	var out: Array = []
	var code: int = OS.execute(
		"lsof",
		PackedStringArray(["-p", str(OS.get_process_id())]),
		out,
		true,
		false
	)
	if code != OK or out.is_empty():
		return
	_match_injector_modules_blob(str(out[0]).to_lower())


func _match_injector_modules_blob(blob: String) -> void:
	var normalized_blob = blob.replace(" ", "\\")
	var segments = normalized_blob.split("\\", false)

	var dlls_in_this_blob: Array[String] = []

	for segment in segments:
		if ".dll" in segment.to_lower():
			var cleaned = _clean_dll_name(segment)

			if cleaned.ends_with(".dll"):
				dlls_in_this_blob.append(cleaned)

	if cfg.use_startup_dll_only and cfg.startup_dll.is_empty():
		cfg.startup_dll = dlls_in_this_blob.duplicate()
		return

	var blob_lower = blob.to_lower()
	for s: String in cfg.suspicious_module_substrings:
		if not s.is_empty() and s.to_lower() in blob_lower:
			_trigger_violation("Suspicious match: %s" % s)
			return

	if cfg.use_startup_dll_only:
		for dll in dlls_in_this_blob:
			if not dll in cfg.startup_dll:
				if dll in ["dcomp.dll", "kernel32.dll", "ntdll.dll"]:
					continue
				_trigger_violation("Unauthorized module: %s" % dll)
				return

func _clean_dll_name(raw: String) -> String:
	var lower = raw.to_lower().strip_edges()

	if lower.begins_with("c:"):
		lower = lower.substr(2)

	var last_slash = max(lower.rfind("\\"), lower.rfind("/"))
	if last_slash != -1:
		lower = lower.substr(last_slash + 1)

	return lower

func _trigger_violation(reason: String) -> void:
	notify_violation(ViolationCode.SUSPICIOUS_MODULE, reason)
	cfg.reaction_on_violation = 4

func _run_integrity() -> void:
	var cnt: int = mini(cfg.integrity_paths.size(), cfg.integrity_expected_md5.size())
	for i in cnt:
		var path: String = cfg.integrity_paths[i]
		if not FileAccess.file_exists(path):
			notify_violation(ViolationCode.INTEGRITY_MISMATCH, "Missing integrity path: %s" % path)
			return
		var h: String = FileAccess.get_md5(path)
		if h != cfg.integrity_expected_md5[i]:
			notify_violation(ViolationCode.INTEGRITY_MISMATCH, "MD5 mismatch: %s" % path)


func _run_userdata_guard() -> void:
	var rel: String = str(cfg.user_data_relative_path).strip_edges()
	if rel.is_empty():
		return
	var full: String = "user://%s" % rel.lstrip("/")
	if not FileAccess.file_exists(full):
		if cfg.user_data_missing_is_violation:
			notify_violation(ViolationCode.USERFILE_TAMPER, "User data missing: %s" % full)
		return
	if str(cfg.user_data_expected_md5).is_empty():
		return
	var h: String = FileAccess.get_md5(full)
	if h != cfg.user_data_expected_md5:
		notify_violation(ViolationCode.USERFILE_TAMPER, "User data MD5 mismatch: %s" % full)


func _run_focus_guard() -> void:
	if _unfocused_since_ms < 0:
		return
	var dt_ms: int = Time.get_ticks_msec() - _unfocused_since_ms
	if dt_ms > int(cfg.focus_loss_hard_cap_sec * 1000.0):
		notify_violation(ViolationCode.FOCUS_TIMEOUT, "Unfocused for %.1f s" % [dt_ms / 1000.0])


func _violation_name(code: ViolationCode) -> String:
	match code:
		ViolationCode.OK:
			return "OK"
		ViolationCode.DEBUG_BUILD:
			return "DEBUG_BUILD"
		ViolationCode.TIME_SKEW:
			return "TIME_SKEW"
		ViolationCode.NEGATIVE_DELTA:
			return "NEGATIVE_DELTA"
		ViolationCode.DELTA_SPIKE:
			return "DELTA_SPIKE"
		ViolationCode.TIMING_PROBE:
			return "TIMING_PROBE"
		ViolationCode.SCENE_TAMPER:
			return "SCENE_TAMPER"
		ViolationCode.INPUT_FLOOD:
			return "INPUT_FLOOD"
		ViolationCode.PROCESS_TOOL:
			return "PROCESS_TOOL"
		ViolationCode.SUSPICIOUS_MODULE:
			return "SUSPICIOUS_MODULE"
		ViolationCode.INTEGRITY_MISMATCH:
			return "INTEGRITY_MISMATCH"
		ViolationCode.INVARIANT:
			return "INVARIANT"
		ViolationCode.CMDLINE_TAMPER:
			return "CMDLINE_TAMPER"
		ViolationCode.ENV_TAMPER:
			return "ENV_TAMPER"
		ViolationCode.PHYSICS_DESYNC:
			return "PHYSICS_DESYNC"
		ViolationCode.GROUP_TAMPER:
			return "GROUP_TAMPER"
		ViolationCode.TREE_TOO_LARGE:
			return "TREE_TOO_LARGE"
		ViolationCode.MACRO_INPUT:
			return "MACRO_INPUT"
		ViolationCode.USERFILE_TAMPER:
			return "USERFILE_TAMPER"
		ViolationCode.FOCUS_TIMEOUT:
			return "FOCUS_TIMEOUT"
		ViolationCode.LICENSE_ANOMALY:
			return "LICENSE_ANOMALY"
		ViolationCode.DUPLICATE_GUARD:
			return "DUPLICATE_GUARD"
		ViolationCode.RATE_LIMIT:
			return "RATE_LIMIT"
		ViolationCode.CUSTOM_CHECK:
			return "CUSTOM_CHECK"
		ViolationCode.DEBUGGER_ATTACHED:
			return "DEBUGGER_ATTACHED"
		ViolationCode.DEBUG_PAUSE:
			return "DEBUG_PAUSE"
		ViolationCode.DUAL_TIMING_ANOMALY:
			return "DUAL_TIMING_ANOMALY"
		ViolationCode.TAMPER_SINGLETON:
			return "TAMPER_SINGLETON"
		ViolationCode.TAMPER_POLICY_FILE:
			return "TAMPER_POLICY_FILE"
		_:
			return str(int(code))


func _log_dev(s: String) -> void:
	dev_log_line.emit(s)
	print("[AntiCheat] ", s)
