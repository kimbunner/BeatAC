extends Control

var code = "Null"

func set_code() -> void:
	$Label.text = "Session halted by Beatrix AntiCheat policy. "+code+"."
