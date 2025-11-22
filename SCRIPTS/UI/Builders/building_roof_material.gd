extends Node

@export var materials: Array[StandardMaterial3D]  # Assign multiple materials

func _ready() -> void:
	if is_instance_valid(GlobalColors):
		GlobalColors.connect("colors_updated", Callable(self, "_on_colors_updated"))

func _on_colors_updated(picked_color: Color, dark_color_1: Color, dark_color_2: Color) -> void:
	for i in materials.size():
		if materials[i]:
			# You could assign different colors to different materials
			match i:
				0:
					materials[i].albedo_color = picked_color
				1:
					materials[i].albedo_color = dark_color_1
				2:
					materials[i].albedo_color = dark_color_2
