@tool
extends VBoxContainer
## Editor-only dock: project policy path + open resource in Inspector.

const _META := &"beatrix_plugin"
const _Obf := preload("res://addons/beatrix_anticheat/core/beatrix_obf.gd")


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var plugin: EditorPlugin = get_meta(_META) as EditorPlugin
	if plugin == null:
		push_error("BeatrixAC: dock missing editor plugin meta.")
		return

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 14)
	title.text = "Beatrix AntiCheat"
	add_child(title)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = (
		"Configure the policy Resource in the Inspector. "
		+ "Set `beatrix_ac/config_path` below so the game loads the correct `.tres`. "
		+ "New Godot versions run the game in its own window with `--remote-debug`; enable "
		+ "`relax_anti_debug_for_editor_launched_run` on the policy (default on) so F5 play does not false-trigger timing/pause checks. "
		+ "For Cheat Engine / DLL injectors: enable `process_scan_enabled` and/or `injector_module_scan_enabled` on the policy, then tune lists."
	)
	add_child(body)

	var path_row := HBoxContainer.new()
	var path_l := Label.new()
	path_l.text = "config_path"
	path_l.custom_minimum_size.x = 92
	path_row.add_child(path_l)
	var path_le := LineEdit.new()
	path_le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ProjectSettings.has_setting("beatrix_ac/config_path"):
		path_le.text = str(ProjectSettings.get_setting("beatrix_ac/config_path", ""))
	path_le.placeholder_text = "res://addons/beatrix_anticheat/user/example_ac_config.tres"
	path_row.add_child(path_le)
	add_child(path_row)

	var save_btn := Button.new()
	save_btn.text = "Save path to project.godot"
	save_btn.pressed.connect(
		func() -> void:
			var p: String = path_le.text.strip_edges()
			ProjectSettings.set_setting("beatrix_ac/config_path", p)
			var err: Error = ProjectSettings.save()
			if err == OK:
				print("BeatrixAC: saved beatrix_ac/config_path = ", p)
			else:
				push_error("BeatrixAC: ProjectSettings.save failed: %s" % error_string(err))
	)
	add_child(save_btn)

	var open_btn := Button.new()
	open_btn.text = "Open policy in Inspector"
	open_btn.pressed.connect(
		func() -> void:
			var path: String = path_le.text.strip_edges()
			if not ResourceLoader.exists(path):
				push_warning("BeatrixAC: resource does not exist: %s" % path)
				return
			var res: Resource = load(path)
			plugin.get_editor_interface().edit_resource(res)
	)
	add_child(open_btn)

	var fs_btn := Button.new()
	fs_btn.text = "Show in FileSystem dock"
	fs_btn.pressed.connect(
		func() -> void:
			var path: String = path_le.text.strip_edges()
			if path.is_empty():
				return
			var dock: FileSystemDock = plugin.get_editor_interface().get_file_system_dock()
			if dock:
				dock.navigate_to_path(path)
	)
	add_child(fs_btn)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	hint.text = "Tip: duplicate `user/example_ac_config.tres` to your own file and point config_path there."
	add_child(hint)

	add_child(HSeparator.new())

	var obf_h1 := Label.new()
	obf_h1.add_theme_font_size_override("font_size", 13)
	obf_h1.text = "Obfuscation (expectations)"
	add_child(obf_h1)

	var obf_doc := Label.new()
	obf_doc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obf_doc.add_theme_color_override("font_color", Color(0.75, 0.78, 0.9))
	obf_doc.text = (
		"GDScript cannot truly self-obfuscate at runtime. Real protection: Export without "
		+ "shipping `.gd` source, use encrypted PCK / binary export where supported, and move "
		+ "secrets to the server. The XOR helper below only hides literals from naive strings searches."
	)
	add_child(obf_doc)

	var obf_plain := LineEdit.new()
	obf_plain.placeholder_text = "Plain text to hide"
	var obf_key := LineEdit.new()
	obf_key.placeholder_text = "Passphrase"
	obf_key.secret = true
	var obf_gen := Button.new()
	obf_gen.text = "Print PackedByteArray → Output (paste into game)"
	obf_gen.pressed.connect(
		func() -> void:
			var enc: PackedByteArray = _Obf.encode_utf8(obf_plain.text, obf_key.text)
			var nums: PackedStringArray = PackedStringArray()
			for i: int in enc.size():
				nums.append(str(int(enc[i])))
			print("var _obf_secret: PackedByteArray = PackedByteArray([%s])" % ",".join(nums))
			print(
				"BeatrixAC: store key separately; runtime: BeatrixObf.decode_utf8(_obf_secret, <key>)"
			)
	)
	add_child(obf_plain)
	add_child(obf_key)
	add_child(obf_gen)

	custom_minimum_size = Vector2(320, 420)
