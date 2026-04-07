extends Node
## Drop under your main scene. For macro detection, keyboard events forward physical_keycode.


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		AntiCheat.record_action_event(event.physical_keycode)
	elif event is InputEventMouseButton and event.pressed:
		AntiCheat.record_action_event(-1)
	elif event is InputEventJoypadButton and event.pressed:
		AntiCheat.record_action_event(-1)
