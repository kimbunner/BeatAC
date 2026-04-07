extends CanvasLayer
## Optional runtime Status / Log only. Enable via policy `in_game_dev_overlay_enabled`. Ctrl+Shift+F12.

@onready var _backdrop: ColorRect = $Backdrop
@onready var _gate: PanelContainer = $Gate
@onready var _password: LineEdit = $Gate/Margin/VBox/Password
@onready var _unlock_btn: Button = $Gate/Margin/VBox/Unlock
@onready var _gate_close: Button = $Gate/Margin/VBox/CloseGate

@onready var _main: PanelContainer = $Main
@onready var _close: Button = $Main/Margin/VBox/Header/Close
@onready var _tabs: TabContainer = $Main/Margin/VBox/Tabs
@onready var _status: TextEdit = $Main/Margin/VBox/Tabs/Status
@onready var _log: RichTextLabel = $Main/Margin/VBox/Tabs/LogScroll/Log
@onready var _hint_bar: Label = $HintBar

var _open_main: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	visible = false
	_backdrop.visible = false
	_gate.visible = false
	_main.visible = false
	_status.editable = false
	_log.bbcode_enabled = true
	_log.scroll_following = true

	_unlock_btn.pressed.connect(_on_unlock_pressed)
	_gate_close.pressed.connect(_close_gate)
	_close.pressed.connect(_close_all)
	_backdrop.gui_input.connect(_on_backdrop_input)

	AntiCheat.violation.connect(_on_violation)
	AntiCheat.dev_log_line.connect(_append_log)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_F12:
			_on_hotkey()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _open_main and _main.visible:
		_status.text = AntiCheat.current_status_text()


func _on_hotkey() -> void:
	if not AntiCheat.is_dev_menu_allowed():
		_toggle_gate()
	else:
		_toggle_main()


func _toggle_gate() -> void:
	var show_gate: bool = not (_gate.visible and not _main.visible)
	if show_gate:
		visible = true
		_backdrop.visible = true
		_gate.visible = true
		_main.visible = false
		_open_main = false
	else:
		_close_all()


func _toggle_main() -> void:
	if _main.visible:
		_close_all()
	else:
		visible = true
		_backdrop.visible = true
		_gate.visible = false
		_main.visible = true
		_open_main = true


func _on_unlock_pressed() -> void:
	if AntiCheat.dev_unlock(_password.text.strip_edges()):
		_password.text = ""
		_gate.visible = false
		_toggle_main()
	else:
		_append_log("[color=#f66]Unlock failed.[/color]")


func _close_gate() -> void:
	_gate.visible = false
	_backdrop.visible = false
	visible = false


func _close_all() -> void:
	_open_main = false
	_main.visible = false
	_gate.visible = false
	_backdrop.visible = false
	visible = false


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_all()


func _on_violation(code: int, detail: String) -> void:
	_append_log("[color=#ffcc44]violation %s[/color] %s" % [code, detail])


func _append_log(line: String) -> void:
	_log.append_text(line + "\n")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_hint_bar.text = "Focus lost — expect skew warnings if the OS stalls the process."
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_hint_bar.text = ""
