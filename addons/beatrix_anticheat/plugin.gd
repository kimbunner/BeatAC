@tool
extends EditorPlugin

const _AUTOLOAD := "AntiCheat"
const _PATH := "res://addons/beatrix_anticheat/core/anticheat_director.gd"
const _DOCK_SCENE := preload("res://addons/beatrix_anticheat/editor/beatrix_ac_dock.tscn")
const _META := &"beatrix_plugin"

var _dock: Control


func _enable_plugin() -> void:
	var key := "autoload/%s" % _AUTOLOAD
	if ProjectSettings.has_setting(key):
		var p := str(ProjectSettings.get_setting(key, ""))
		if p.contains("beatrix_anticheat/core/anticheat_director.gd"):
			pass
		else:
			push_warning(
				"Beatrix AntiCheat: autoload '%s' is already set to another script (%s). "
				% [_AUTOLOAD, p]
				+ "Point it to %s or remove the other entry manually." % _PATH
			)
	else:
		add_autoload_singleton(_AUTOLOAD, _PATH)

	_dock = _DOCK_SCENE.instantiate() as Control
	_dock.set_meta(_META, self)
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)


func _disable_plugin() -> void:
	if is_instance_valid(_dock):
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

	var key := "autoload/%s" % _AUTOLOAD
	if ProjectSettings.has_setting(key):
		var p := str(ProjectSettings.get_setting(key, ""))
		if p.contains("beatrix_anticheat/core/anticheat_director.gd"):
			remove_autoload_singleton(_AUTOLOAD)
