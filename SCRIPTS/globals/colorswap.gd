#global
extends Node

signal colors_updated(picked_color, dark_color_1, dark_color_2)

var picked_color: Color = Color.WHITE
var dark_color_1: Color = Color.GRAY
var dark_color_2: Color = Color.DARK_GRAY

func update_colors(new_base_color: Color):
	picked_color = new_base_color
	dark_color_1 = picked_color.darkened(0.2)
	dark_color_2 = dark_color_1.darkened(0.3)
	
	emit_signal("colors_updated", picked_color, dark_color_1, dark_color_2)
	
	print("--- Global Colors Updated (via Singleton) ---")
	print("Picked: ", picked_color)
	print("Dark 1: ", dark_color_1)
	print("Dark 2: ", dark_color_2)
