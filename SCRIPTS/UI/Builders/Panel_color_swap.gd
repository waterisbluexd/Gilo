extends CanvasItem

func _ready():
	if is_instance_valid(GlobalColors):
		GlobalColors.connect("colors_updated", Callable(self, "_update_material_colors"))
		_update_material_colors(GlobalColors.picked_color, GlobalColors.dark_color_1, GlobalColors.dark_color_2)
	else:
		print("ERROR: GlobalColors singleton not found. Cannot connect shader.")

func _update_material_colors(picked_color: Color, dark_color_1: Color, dark_color_2: Color) -> void:
	var material = self.material
	
	if material and material is ShaderMaterial:
		material.set_shader_parameter("new_color_1", picked_color)
		material.set_shader_parameter("new_color_2", dark_color_1)
		material.set_shader_parameter("new_color_3", dark_color_2)
	else:
		print("WARNING: Node %s does not have a ShaderMaterial attached." % self.name)
