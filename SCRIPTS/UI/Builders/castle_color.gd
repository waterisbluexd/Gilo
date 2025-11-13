extends ColorPickerButton

func _ready() -> void:
	if not is_connected("color_changed", Callable(self, "_on_color_changed")):
		connect("color_changed", Callable(self, "_on_color_changed"))
	
	_on_color_changed(self.color)
	
func _on_color_changed(new_color: Color) -> void:
	if is_instance_valid(GlobalColors):
		GlobalColors.update_colors(new_color)
	else:
		print("ERROR: GlobalColors singleton not found. Please set 'GlobalColorManager.gd' as an AutoLoad.")
